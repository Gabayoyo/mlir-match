#include "Match/Conversion/MatchToDecisionTree/Passes.h"
#include "Match/Conversion/LoweringUtils.h"
#include "Match/MatchOps.h"
#include "Match/MatchAttrs.h"
#include "Match/MatchTypes.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/SCF/IR/SCF.h"

#include <vector>

namespace mlir {
namespace match {
namespace {

#define GEN_PASS_DEF_MATCHTODECISIONTREEPASS
#include "Match/Conversion/MatchToDecisionTree/Passes.h.inc"
#include <set>
#include <algorithm>
#include <iterator>
#include <map>

struct Row {
  PatternAttr pattern;
  unsigned int armIndex;
  SmallVector<unsigned int> bindDepths;
};

// Tagged node: a self-referential std::variant would need indirection, so
// recursion goes through std::vector of complete nodes instead.
struct DecisionNode {
  enum class Kind { Fail, Leaf, CtorTest } kind;
  unsigned armIndex = 0;               // Leaf
  SmallVector<unsigned> bindDepths;    // Leaf
  SmallVector<StringRef> ctors;        // CtorTest
  std::vector<DecisionNode> children;  // CtorTest
};

// check whether a row is complete
bool isComplete(const Row &row) {
  return !row.pattern || row.pattern.getKind() == "wildcard" 
                      || row.pattern.getKind() == "bind";
}

// The constructors heading the rows' remaining patterns, in first-appearance
// order; irrefutable rows have no head to test and are skipped.
SmallVector<StringRef> headConstructors(ArrayRef<Row> rows) {
  SmallVector<StringRef> heads;

  for (const Row &row : rows) {
    if (!row.pattern || row.pattern.getKind() == "bind" ||
        row.pattern.getKind() == "wildcard")
      continue; // irrefutable or consumed: rides, never tested here
    StringRef ctor = row.pattern.getKind();
    if (llvm::is_contained(heads, ctor))
      continue; // already branching on this constructor
    heads.push_back(ctor);
  }

  return heads;
}

SmallVector<Row> specialise(ArrayRef<Row> rows, StringRef ctor, unsigned int depth) {
  SmallVector<Row> specialised;
  for (const Row &row : rows) {
    // Complete rows (bind/wildcard/consumed) match this constructor too and
    // ride into the child unchanged, preserving row order.
    if (isComplete(row)) {
      specialised.push_back(row);
      continue;
    }
    // if different constructor, we don't take this row into the specialised set
    if (row.pattern.getKind() != ctor)
      continue;
    // Consume the head: the sub-pattern (or nothing) is what remains.
    Row newRow;
    newRow.armIndex = row.armIndex;
    newRow.bindDepths = row.bindDepths;
    ArrayRef<PatternAttr> subs = row.pattern.getSubpatterns();
    newRow.pattern = subs.empty() ? PatternAttr() : subs.front();
    // A bind sub-pattern binds the field of this constructor, which sits one
    // level deeper than the parent matrix.
    if (!subs.empty() && subs.front().getKind() == "bind")
      newRow.bindDepths.push_back(depth);
    specialised.push_back(newRow);
  }
  return specialised;
}

DecisionNode compileRows(SmallVector<Row> rows, unsigned int depth) {
  if (rows.empty())
    return DecisionNode{DecisionNode::Kind::Fail, 0, {}, {}, {}};
  Row &first = rows.front();
  if (isComplete(first))
    // bind or wildcard at the head: the first row always fires
    return DecisionNode{DecisionNode::Kind::Leaf, first.armIndex,
                        first.bindDepths, {}, {}};

  std::vector<DecisionNode> children;
  SmallVector<StringRef> heads = headConstructors(rows);
  for (StringRef ctor : heads)
    children.push_back(compileRows(specialise(rows, ctor, depth + 1), depth + 1));

  // Rows that match none of the tested constructors are exactly the
  // irrefutable ones; they fire in the fail branch (first match wins), and
  // the default runs only when there are none.
  SmallVector<Row> fallbackRows;
  for (const Row &row : rows)
    if (isComplete(row))
      fallbackRows.push_back(row);
  children.push_back(compileRows(fallbackRows, depth));

  return DecisionNode{DecisionNode::Kind::CtorTest, 0, {}, heads,
                      std::move(children)};
}

void emitDefault(MatchOp match, Block &dst, OpBuilder &builder) {
  Block &def = match.getOtherwise().front();
  auto yield = cast<YieldOp>(def.getTerminator());
  builder.setInsertionPointToEnd(&dst);

  // Regular clone can't be used here as clones need to refer to their own ops
  // we use IRMapping to maintain relative mapping
  IRMapping mapping;
  for (Operation &op : llvm::make_early_inc_range(def)) {
    if (&op == yield)
      continue;

    // clone op with mapping in mind, and insert it into the new block
    Operation *clone = op.clone(mapping);
    builder.insert(clone);

    // map the original op's results to the clone's results
    for (auto [orig, repl] : llvm::zip(op.getResults(), clone->getResults()))
      mapping.map(orig, repl);
  }

  // clone the yield op, remapping its operands to the new block's values
  SmallVector<Value> results;
  for (Value operand : yield.getOperands())
    results.push_back(mapping.lookupOrDefault(operand));
  scf::YieldOp::create(builder, yield.getLoc(), ValueRange(results));
}

using PathResult = std::optional<SmallVector<Value>>;

PathResult emitCtorTest(const DecisionNode &node, SmallVectorImpl<Value> &chain,
                        MatchOp match, OpBuilder &builder, unsigned index);

PathResult emitNode(const DecisionNode &node, SmallVectorImpl<Value> &chain, 
                    MatchOp match, OpBuilder &builder) {
                      switch (node.kind) {
                        case DecisionNode::Kind::Leaf: {
                          SmallVector<Value> bindings;
                          for (unsigned depth : node.bindDepths)
                            bindings.push_back(chain[depth]);
                          emitBody(match.getArms()[node.armIndex].front(), *builder.getInsertionBlock(), builder, bindings);
                          return std::nullopt;
                        }
                        case DecisionNode::Kind::Fail: {
                          emitDefault(match, *builder.getInsertionBlock(), builder);
                          return std::nullopt;
                        }
                        case DecisionNode::Kind::CtorTest: {
                          return emitCtorTest(node, chain, match, builder, 0);
                        }
                      }
                    }

PathResult emitCtorTest(const DecisionNode &node, SmallVectorImpl<Value> &chain, 
                        MatchOp match, OpBuilder &builder, unsigned index) {
                          auto descriptorOpt =
                            lookupConstructor(chain.back().getType(), node.ctors[index]);
                          assert(descriptorOpt && descriptorOpt->fieldTypes.size() <= 1 &&
                                "tree-eligible constructor must exist and be single-field");
                          const ConstructorDescriptor &descriptor = *descriptorOpt;

                          SmallVector<Type> deconstructTypes{builder.getI1Type()};
                          deconstructTypes.append(descriptor.fieldTypes.begin(),
                                                  descriptor.fieldTypes.end());

                          auto deconstruct = match::DeconstructOp::create(
                              builder, match.getLoc(), deconstructTypes, chain.back(),
                              node.ctors[index]);

                          auto scfIf = scf::IfOp::create(
                              builder, match.getLoc(),
                              SmallVector<Type>(match.getResultTypes().begin(),
                                                match.getResultTypes().end()),
                              deconstruct.getResult(0), /*addThenBlock=*/true, /*addElseBlock=*/true);

                          // Then-branch: this constructor's child node.
                          Block &thenBlock = scfIf.getThenRegion().front();
                          builder.setInsertionPointToEnd(&thenBlock);

                          bool hasField = descriptor.fieldTypes.size() == 1;
                          if (hasField)
                            chain.push_back(deconstruct.getResult(1));

                          PathResult child = emitNode(node.children[index], chain, match, builder);
                            
                          if (hasField)
                            chain.pop_back();
                            
                          if (child) {
                            builder.setInsertionPointToEnd(&thenBlock);
                            scf::YieldOp::create(builder, match.getLoc(), ValueRange(*child));
                          }

                          // Else-branch: the next constructor test, or the
                          // fallback rows (last child) when none match.
                          Block &elseBlock = scfIf.getElseRegion().front();
                          builder.setInsertionPointToEnd(&elseBlock);
                          if (index + 1 < node.ctors.size()) {
                            PathResult rest = emitCtorTest(node, chain, match, builder, index + 1);
                            if (rest) {
                              builder.setInsertionPointToEnd(&elseBlock);
                              scf::YieldOp::create(builder, match.getLoc(), ValueRange(*rest));
                            }
                          } else {
                            PathResult fallback =
                                emitNode(node.children.back(), chain, match, builder);
                            if (fallback) {
                              builder.setInsertionPointToEnd(&elseBlock);
                              scf::YieldOp::create(builder, match.getLoc(),
                                                   ValueRange(*fallback));
                            }
                          }

                          return SmallVector<Value>(scfIf.getResults());
                        }

// True when a pattern is compileable by this pass: no literals and every
// constructor has at most one field, at every nesting depth.
bool isTreePattern(PatternAttr pattern) {
  StringRef kind = pattern.getKind();
  if (kind == "bind" || kind == "wildcard")
    return true;
  if (kind == "literal")
    return false;
  ArrayRef<PatternAttr> subs = pattern.getSubpatterns();
  if (subs.size() > 1)
    return false;
  if (subs.empty())
    return true; // zero-field constructor, e.g. none
  return isTreePattern(subs.front());
}

// A match is tree-eligible when it carries one pattern per arm, no guards,
// and every pattern is compileable (no literals, single-field constructors).
bool isEligible(MatchOp match) {
  auto patterns = match.getPatterns();
  if (!patterns || patterns->empty() ||
      patterns->size() != match.getArms().size())
    return false;
  for (Region &arm : match.getArms())
    if (hasGuard(arm))
      return false;
  for (Attribute pattern : *patterns)
    if (!isTreePattern(cast<PatternAttr>(pattern)))
      return false;
  return true;
}

// One row per arm; a top-level bind binds the scrutinee at depth 0.
SmallVector<Row> buildRows(MatchOp match) {
  SmallVector<Row> rows;
  for (auto [index, attribute] : llvm::enumerate(*match.getPatterns())) {
    PatternAttr pattern = cast<PatternAttr>(attribute);
    Row row{pattern, static_cast<unsigned>(index), {}};
    if (pattern.getKind() == "bind")
      row.bindDepths.push_back(0);
    rows.push_back(row);
  }
  return rows;
}

// Lowers pattern rows into a Maranget-style decision tree of scf control
// flow
struct MatchToDecisionTreePass
    : impl::MatchToDecisionTreePassBase<MatchToDecisionTreePass> {
  void runOnOperation() override {
    auto func = getOperation();
    SmallVector<MatchOp> matches;
    func.walk([&](MatchOp match) {
      if (isEligible(match))
        matches.push_back(match);
    });

    for (MatchOp match : matches) {
      DecisionNode tree = compileRows(buildRows(match), 0);

      // A tree rooted in a leaf means the first arm matches unconditionally;
      // inline it in place of the match.
      if (tree.kind != DecisionNode::Kind::Leaf) {
        OpBuilder builder(match.getOperation());
        SmallVector<Value> chain{match.getScrutinee()};
        PathResult results = emitNode(tree, chain, match, builder);
        if (results) {
          match.replaceAllUsesWith(*results);
          match.erase();
        }
      } else {
        OpBuilder builder(match.getOperation());
        Block &dst = *builder.getInsertionBlock();
        Block &armBlock = match.getArms()[tree.armIndex].front();

        SmallVector<Value> bindings;
        if (!tree.bindDepths.empty())
          bindings.push_back(match.getScrutinee());
        for (auto [argument, binding] :
            llvm::zip(armBlock.getArguments(), bindings))
          argument.replaceAllUsesWith(binding);

        auto yield = cast<YieldOp>(armBlock.getTerminator());
        SmallVector<Value> results(yield.getOperands());
        for (Operation &op : llvm::make_early_inc_range(armBlock)) {
          if (&op == yield)
            continue;
          op.moveBefore(&dst, builder.getInsertionPoint());
        }
        match.replaceAllUsesWith(results);
        match.erase();
      }
    }
  }
};

} // namespace

std::unique_ptr<Pass> createMatchToDecisionTreePass() {
  return std::make_unique<MatchToDecisionTreePass>();
}

} // namespace match
} // namespace mlir
