#include "Match/Conversion/MatchToDecisionTree/Passes.h"
#include "Match/Conversion/LoweringUtils.h"
#include "Match/MatchOps.h"
#include "Match/MatchAttrs.h"
#include "Match/MatchTypes.h"

#include "llvm/ADT/STLExtras.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/Arith/IR/Arith.h"

#include <optional>
#include <vector>

namespace mlir {
namespace match {
namespace {

#define GEN_PASS_DEF_MATCHTODECISIONTREEPASS
#include "Match/Conversion/MatchToDecisionTree/Passes.h.inc"
#include <iterator>
#include <utility>

// A remaining match position: the pattern still to check against the value
// stored in `slot` (an entry of the emitter's slot array).
struct Col {
  PatternAttr pattern;
  unsigned slot;
};

struct Row {
  SmallVector<Col> cols;      // remaining columns, in order
  SmallVector<unsigned> bound; // slots of binds consumed without a test
  unsigned armIndex;
  bool hasGuard = false;
};

struct DecisionNode {
  enum class Kind { Fail, Leaf, CtorTest, GuardTest, LiteralTest, Ineligible } kind;
  unsigned armIndex = 0;               // Leaf / GuardTest
  SmallVector<unsigned> bindSlots;     // Leaf / GuardTest
  SmallVector<StringRef> ctors;        // CtorTest
  unsigned slot = 0;                   // CtorTest + LiteralTest: slot being tested
  SmallVector<unsigned> ctorBases;     // CtorTest: first field slot per ctor
  std::vector<DecisionNode> children;  // CtorTest + LiteralTest (+ implicit fallback last)
  SmallVector<IntegerAttr> literals;   // LiteralTest
};

// True when a row has nothing left to test: no columns, or every remaining
// column is irrefutable (bind/wildcard).
bool isComplete(const Row &row) {
  if (row.cols.empty())
    return true;
  for (const Col &col : row.cols)
    if (col.pattern && col.pattern.getKind() != "bind" &&
        col.pattern.getKind() != "wildcard")
      return false;
  return true;
}

// The slots each bind of a complete row captures, in column order.
SmallVector<unsigned> rowBindSlots(const Row &row) {
  SmallVector<unsigned> slots(row.bound.begin(), row.bound.end());
  for (const Col &col : row.cols)
    if (col.pattern && col.pattern.getKind() == "bind")
      slots.push_back(col.slot);
  return slots;
}

// The constructors heading the non-complete rows' first column, in
// first-appearance order; irrefutable rows are skipped.
SmallVector<StringRef> headConstructors(ArrayRef<Row> rows) {
  SmallVector<StringRef> heads;
  for (const Row &row : rows) {
    if (row.cols.empty())
      continue;
    Col col = row.cols.front();
    if (!col.pattern || col.pattern.getKind() == "bind" ||
        col.pattern.getKind() == "wildcard")
      continue; // irrefutable or consumed: rides, never tested here
    StringRef ctor = col.pattern.getKind();
    if (llvm::is_contained(heads, ctor))
      continue;
    heads.push_back(ctor);
  }
  return heads;
}

// The literal payloads heading the non-complete rows' first column, in
// first-appearance order; irrefutable rows are skipped.
SmallVector<IntegerAttr> headLiterals(ArrayRef<Row> rows) {
  SmallVector<IntegerAttr> heads;
  for (const Row &row : rows) {
    if (row.cols.empty())
      continue;
    Col col = row.cols.front();
    if (col.pattern && col.pattern.getKind() == "literal") {
      IntegerAttr literal = col.pattern.getPayload();
      if (!llvm::is_contained(heads, literal))
        heads.push_back(literal);
    }
  }
  return heads;
}

// Consume constructor `ctor` from the rows' first column, splicing its
// sub-patterns in; complete rows ride, other constructors are excluded.
SmallVector<Row> specialise(ArrayRef<Row> rows, StringRef ctor,
                            unsigned &nextSlot) {
  SmallVector<Row> specialised;
  // One shared slot per field: every consuming row deconstructs the same value.
  unsigned k = 0;
  for (const Row &row : rows)
    if (!isComplete(row) && !row.cols.empty() &&
        row.cols.front().pattern.getKind() == ctor) {
      k = row.cols.front().pattern.getSubpatterns().size();
      break;
    }
  unsigned base = nextSlot;
  nextSlot += k;

  for (const Row &row : rows) {
    if (isComplete(row)) {
      specialised.push_back(row);
      continue;
    }
    if (row.cols.front().pattern.getKind() != ctor)
      continue;
    Row newRow;
    newRow.armIndex = row.armIndex;
    newRow.hasGuard = row.hasGuard;
    newRow.bound = row.bound;
    ArrayRef<PatternAttr> subs = row.cols.front().pattern.getSubpatterns();
    for (auto [index, sub] : llvm::enumerate(subs))
      newRow.cols.push_back({sub, base + static_cast<unsigned>(index)});
    newRow.cols.append(row.cols.begin() + 1, row.cols.end());
    specialised.push_back(newRow);
  }
  return specialised;
}

SmallVector<Row> specialiseLiteral(ArrayRef<Row> rows, IntegerAttr payload) {
  SmallVector<Row> specialised;
  for (const Row &row : rows) {
    if (isComplete(row)) {
      specialised.push_back(row);
      continue;
    }

    // if the first column is not a literal, or the literal does not match the payload, skip this row
    if (!row.cols.front().pattern ||
        row.cols.front().pattern.getKind() != "literal" ||
        row.cols.front().pattern.getPayload() != payload)
      continue;

    Row newRow;
    newRow.armIndex = row.armIndex;
    newRow.hasGuard = row.hasGuard;
    newRow.bound = row.bound;
    newRow.cols.append(row.cols.begin() + 1, row.cols.end());
    specialised.push_back(newRow);
  }
  return specialised;
}

DecisionNode compileRows(SmallVector<Row> rows, unsigned &nextSlot) {
  if (rows.empty())
    return DecisionNode{DecisionNode::Kind::Fail, 0, {}, {}, 0, {}, {}, {}};

  // An all-irrefutable leading column needs no test; consume it (and binds).
  for (;;) {
    Row &front = rows.front();
    if (isComplete(front))
      break;
    bool allIrrefutable = true;
    for (Row &row : rows) {
      if (isComplete(row))
        continue;
      Col col = row.cols.front();
      if (!col.pattern || (col.pattern.getKind() != "bind" &&
                           col.pattern.getKind() != "wildcard"))
        allIrrefutable = false;
    }
    if (!allIrrefutable)
      break;
    for (Row &row : rows) {
      if (isComplete(row))
        continue;
      Col col = row.cols.front();
      if (col.pattern && col.pattern.getKind() == "bind")
        row.bound.push_back(col.slot);
      row.cols.erase(row.cols.begin());
    }
  }

  for (const Row &row : rows)
    if (!isComplete(row) && !row.cols.empty()) {
      Col col = row.cols.front();
      if (!col.pattern || col.pattern.getKind() == "bind" ||
          col.pattern.getKind() == "wildcard")
        return DecisionNode{DecisionNode::Kind::Ineligible, 0, {}, {}, 0, {},
                            {}, {}};
    }

  Row &first = rows.front();
  if (isComplete(first)) {
    // A guarded complete row cannot prune: try it, then continue on guard
    // failure with the remaining rows.
    SmallVector<unsigned> binds = rowBindSlots(first);
    if (first.hasGuard) {
      SmallVector<Row> rest(rows.begin() + 1, rows.end());
      std::vector<DecisionNode> child{
          compileRows(std::move(rest), nextSlot)};
      return DecisionNode{DecisionNode::Kind::GuardTest, first.armIndex,
                          binds, {}, 0, {}, std::move(child), {}};
    }
    // bind or wildcard at the head: the first row always fires
    return DecisionNode{DecisionNode::Kind::Leaf, first.armIndex,
                        binds, {}, 0, {}, {}, {}};
  }

  if (first.cols.front().pattern.getKind() == "literal") {
    SmallVector<IntegerAttr> heads = headLiterals(rows);
    std::vector<DecisionNode> children;
    for (IntegerAttr literal : heads) {
      DecisionNode child =
          compileRows(specialiseLiteral(rows, literal), nextSlot);
      if (child.kind == DecisionNode::Kind::Ineligible)
        return child;
      children.push_back(std::move(child));
    }

    // Irrefutable rows match none of the tested literals; they fire in the
    // fail branch, and the default runs only when there are none.
    SmallVector<Row> fallbackRows;
    for (const Row &row : rows)
      if (isComplete(row))
        fallbackRows.push_back(row);
    {
      DecisionNode child = compileRows(std::move(fallbackRows), nextSlot);
      if (child.kind == DecisionNode::Kind::Ineligible)
        return child;
      children.push_back(std::move(child));
    }

    unsigned slot = first.cols.front().slot;
    return DecisionNode{DecisionNode::Kind::LiteralTest, 0, {}, {}, slot, {},
                        std::move(children), std::move(heads)};
  }

  SmallVector<StringRef> heads = headConstructors(rows);
  SmallVector<unsigned> bases;
  std::vector<DecisionNode> children;
  for (StringRef ctor : heads) {
    bases.push_back(nextSlot);
    DecisionNode child =
        compileRows(specialise(rows, ctor, nextSlot), nextSlot);
    if (child.kind == DecisionNode::Kind::Ineligible)
      return child;
    children.push_back(std::move(child));
  }

  // Irrefutable rows match none of the tested constructors; they fire in the
  // fail branch, and the default runs only when there are none.
  SmallVector<Row> fallbackRows;
  for (const Row &row : rows)
    if (isComplete(row))
      fallbackRows.push_back(row);
  {
    DecisionNode child = compileRows(std::move(fallbackRows), nextSlot);
    if (child.kind == DecisionNode::Kind::Ineligible)
      return child;
    children.push_back(std::move(child));
  }

  unsigned slot = first.cols.front().slot;
  return DecisionNode{DecisionNode::Kind::CtorTest, 0, {}, heads, slot,
                      std::move(bases), std::move(children), {}};
}

void emitDefault(MatchOp match, Block &dst, OpBuilder &builder) {
  Block &def = match.getOtherwise().front();
  auto yield = cast<YieldOp>(def.getTerminator());
  builder.setInsertionPointToEnd(&dst);

  // Clone with an IRMapping so clones reference each other's results.
  IRMapping mapping;
  for (Operation &op : llvm::make_early_inc_range(def)) {
    if (&op == yield)
      continue;
    Operation *clone = op.clone(mapping);
    builder.insert(clone);
    for (auto [orig, repl] : llvm::zip(op.getResults(), clone->getResults()))
      mapping.map(orig, repl);
  }

  SmallVector<Value> results;
  for (Value operand : yield.getOperands())
    results.push_back(mapping.lookupOrDefault(operand));
  scf::YieldOp::create(builder, yield.getLoc(), ValueRange(results));
}

using PathResult = std::optional<SmallVector<Value>>;

PathResult emitCtorTest(const DecisionNode &node, SmallVectorImpl<Value> &slots,
                        MatchOp match, OpBuilder &builder, unsigned index);

PathResult emitLiteralTest(const DecisionNode &node, SmallVectorImpl<Value> &slots,
                           MatchOp match, OpBuilder &builder, unsigned index);

PathResult emitNode(const DecisionNode &node, SmallVectorImpl<Value> &slots,
                    MatchOp match, OpBuilder &builder) {
  switch (node.kind) {
  case DecisionNode::Kind::Leaf: {
    SmallVector<Value> bindings;
    for (unsigned slot : node.bindSlots)
      bindings.push_back(slots[slot]);
    emitBody(match.getArms()[node.armIndex].front(),
             *builder.getInsertionBlock(), builder, bindings);
    return std::nullopt;
  }
  case DecisionNode::Kind::Fail: {
    emitDefault(match, *builder.getInsertionBlock(), builder);
    return std::nullopt;
  }
  case DecisionNode::Kind::CtorTest: {
    return emitCtorTest(node, slots, match, builder, 0);
  }
  case DecisionNode::Kind::GuardTest: {
    SmallVector<Value> bindings;
    for (unsigned slot : node.bindSlots)
      bindings.push_back(slots[slot]);

    // The arm's bindings are its entry args; remap them so the guard ops and
    // body keep valid references.
    Block &armBlock = match.getArms()[node.armIndex].front();
    for (auto [argument, binding] :
         llvm::zip(armBlock.getArguments(), bindings))
      argument.replaceAllUsesWith(binding);

    // Move the condition computation (the ops before the guard) into the
    // current block; the body stays put.
    GuardOp guardOp;
    bool beforeGuard = true;
    Block &dst = *builder.getInsertionBlock();
    for (Operation &op : llvm::make_early_inc_range(armBlock)) {
      if (auto guard = dyn_cast<GuardOp>(op)) {
        guardOp = guard;
        beforeGuard = false;
        continue;
      }
      if (beforeGuard)
        op.moveBefore(&dst, builder.getInsertionPoint());
    }
    assert(guardOp && "guard-test arm must contain a guard");
    Value condition = guardOp.getCondition();
    guardOp->erase();

    auto scfIf = scf::IfOp::create(
        builder, match.getLoc(),
        SmallVector<Type>(match.getResultTypes().begin(),
                          match.getResultTypes().end()),
        condition, /*addThenBlock=*/true, /*addElseBlock=*/true);

    // Then-branch: the guarded arm's body fires.
    Block &thenBlock = scfIf.getThenRegion().front();
    builder.setInsertionPointToEnd(&thenBlock);
    emitBody(armBlock, thenBlock, builder, bindings);

    // Else-branch: the guard failed, so matching continues with the rest.
    Block &elseBlock = scfIf.getElseRegion().front();
    builder.setInsertionPointToEnd(&elseBlock);
    PathResult rest = emitNode(node.children.front(), slots, match, builder);
    if (rest) {
      builder.setInsertionPointToEnd(&elseBlock);
      scf::YieldOp::create(builder, match.getLoc(), ValueRange(*rest));
    }
    return SmallVector<Value>(scfIf.getResults());
  }
  case DecisionNode::Kind::LiteralTest: {
    return emitLiteralTest(node, slots, match, builder, 0);
  }
  case DecisionNode::Kind::Ineligible:
    // Ineligible trees are filtered before emission ever runs.
    llvm_unreachable("ineligible tree reached the emitter");
  }
  llvm_unreachable("unhandled decision node kind");
}

// Chain of constructor tests: `ctors[index]` gets an scf.if whose then-branch
// holds its child node and whose else holds the next test (or the fallback).
PathResult emitCtorTest(const DecisionNode &node, SmallVectorImpl<Value> &slots,
                        MatchOp match, OpBuilder &builder, unsigned index) {
  auto descriptorOpt =
      lookupConstructor(slots[node.slot].getType(), node.ctors[index]);
  assert(descriptorOpt && "tree-eligible constructor must exist");
  const ConstructorDescriptor &descriptor = *descriptorOpt;

  SmallVector<Type> deconstructTypes{builder.getI1Type()};
  deconstructTypes.append(descriptor.fieldTypes.begin(),
                          descriptor.fieldTypes.end());
  auto deconstruct = match::DeconstructOp::create(
      builder, match.getLoc(), deconstructTypes, slots[node.slot],
      node.ctors[index]);

  auto scfIf = scf::IfOp::create(
      builder, match.getLoc(),
      SmallVector<Type>(match.getResultTypes().begin(),
                        match.getResultTypes().end()),
      deconstruct.getResult(0), /*addThenBlock=*/true, /*addElseBlock=*/true);

  // Then-branch: this constructor's child node. The deconstructed fields
  // become the slots the child (and its leaves) read.
  Block &thenBlock = scfIf.getThenRegion().front();
  builder.setInsertionPointToEnd(&thenBlock);
  unsigned fieldBase = node.ctorBases[index];
  for (auto [fieldIndex, field] :
       llvm::enumerate(deconstruct.getResults().drop_front()))
    slots[fieldBase + fieldIndex] = field;
  PathResult child = emitNode(node.children[index], slots, match, builder);
  if (child) {
    builder.setInsertionPointToEnd(&thenBlock);
    scf::YieldOp::create(builder, match.getLoc(), ValueRange(*child));
  }

  // Else-branch: the next constructor test, or the fallback rows (last
  // child) when none match.
  Block &elseBlock = scfIf.getElseRegion().front();
  builder.setInsertionPointToEnd(&elseBlock);
  if (index + 1 < node.ctors.size()) {
    PathResult rest = emitCtorTest(node, slots, match, builder, index + 1);
    if (rest) {
      builder.setInsertionPointToEnd(&elseBlock);
      scf::YieldOp::create(builder, match.getLoc(), ValueRange(*rest));
    }
  } else {
    PathResult fallback = emitNode(node.children.back(), slots, match, builder);
    if (fallback) {
      builder.setInsertionPointToEnd(&elseBlock);
      scf::YieldOp::create(builder, match.getLoc(), ValueRange(*fallback));
    }
  }

  return SmallVector<Value>(scfIf.getResults());
}

// Chain of equality tests: `literals[index]` gets an scf.if whose then-branch
// holds its child node and whose else holds the next test (or the fallback).
PathResult emitLiteralTest(const DecisionNode &node, SmallVectorImpl<Value> &slots,
                           MatchOp match, OpBuilder &builder, unsigned index) {
  Value literal = arith::ConstantOp::create(builder, match.getLoc(),
                                            node.literals[index]);
  Value equal = arith::CmpIOp::create(builder, match.getLoc(),
                                      arith::CmpIPredicate::eq,
                                      slots[node.slot], literal);

  auto scfIf = scf::IfOp::create(
      builder, match.getLoc(),
      SmallVector<Type>(match.getResultTypes().begin(),
                        match.getResultTypes().end()),
      equal, /*addThenBlock=*/true, /*addElseBlock=*/true);

  // Then-branch: this literal's child node. No new values appear: the tested
  // slot still holds the value deeper columns (and bind rows) read.
  Block &thenBlock = scfIf.getThenRegion().front();
  builder.setInsertionPointToEnd(&thenBlock);
  PathResult child = emitNode(node.children[index], slots, match, builder);
  if (child) {
    builder.setInsertionPointToEnd(&thenBlock);
    scf::YieldOp::create(builder, match.getLoc(), ValueRange(*child));
  }

  // Else-branch: the next literal test, or the fallback rows (last child)
  // when none match.
  Block &elseBlock = scfIf.getElseRegion().front();
  builder.setInsertionPointToEnd(&elseBlock);
  if (index + 1 < node.literals.size()) {
    PathResult rest = emitLiteralTest(node, slots, match, builder, index + 1);
    if (rest) {
      builder.setInsertionPointToEnd(&elseBlock);
      scf::YieldOp::create(builder, match.getLoc(), ValueRange(*rest));
    }
  } else {
    PathResult fallback = emitNode(node.children.back(), slots, match, builder);
    if (fallback) {
      builder.setInsertionPointToEnd(&elseBlock);
      scf::YieldOp::create(builder, match.getLoc(), ValueRange(*fallback));
    }
  }

  return SmallVector<Value>(scfIf.getResults());
}

// Compileable patterns: literals and binds only under single-field
// constructors (never a direct field of a multi-field one).
bool isTreePattern(PatternAttr pattern) {
  StringRef kind = pattern.getKind();
  if (kind == "bind" || kind == "wildcard")
    return true;
  ArrayRef<PatternAttr> subs = pattern.getSubpatterns();
  if (subs.size() > 1) {
    for (PatternAttr sub : subs)
      if (sub.getKind() == "bind" || sub.getKind() == "wildcard")
        return false;
  }
  for (PatternAttr sub : subs)
    if (!isTreePattern(sub))
      return false;
  return true;
}

// A match is tree-eligible when it carries one pattern per arm,
// and every pattern is compileable under the column restrictions.
bool isEligible(MatchOp match) {
  auto patterns = match.getPatterns();
  if (!patterns || patterns->empty() ||
      patterns->size() != match.getArms().size())
    return false;
  for (Attribute pattern : *patterns)
    if (!isTreePattern(cast<PatternAttr>(pattern)))
      return false;
  return true;
}

// One row per arm: a single column matching the scrutinee (slot 0).
SmallVector<Row> buildRows(MatchOp match) {
  SmallVector<Row> rows;
  for (auto [index, attribute] : llvm::enumerate(*match.getPatterns())) {
    PatternAttr pattern = cast<PatternAttr>(attribute);
    Row row;
    row.cols.push_back({pattern, 0});
    row.armIndex = static_cast<unsigned>(index);
    row.hasGuard = hasGuard(match.getArms()[index]);
    rows.push_back(row);
  }
  return rows;
}

// Lowers eligible pattern rows via a Maranget-style decision tree of scf
// control flow
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
      unsigned nextSlot = 1; // slot 0 is the scrutinee
      DecisionNode tree = compileRows(buildRows(match), nextSlot);

      if (tree.kind == DecisionNode::Kind::Ineligible)
        continue; // cannot align columns: leave for the naive pass

      // A tree rooted in a leaf means the first arm matches unconditionally;
      // inline it in place of the match.
      if (tree.kind == DecisionNode::Kind::Leaf) {
        OpBuilder builder(match.getOperation());
        Block &dst = *builder.getInsertionBlock();
        Block &armBlock = match.getArms()[tree.armIndex].front();

        SmallVector<Value> bindings;
        for (unsigned slot : tree.bindSlots)
          if (slot == 0)
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
        continue;
      }

      OpBuilder builder(match.getOperation());
      SmallVector<Value> slots(nextSlot);
      slots[0] = match.getScrutinee();
      PathResult results = emitNode(tree, slots, match, builder);
      if (results) {
        match.replaceAllUsesWith(*results);
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
