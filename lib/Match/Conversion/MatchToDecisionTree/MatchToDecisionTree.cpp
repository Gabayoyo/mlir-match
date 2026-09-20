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
#include <utility>
#include <vector>

namespace mlir {
namespace match {
namespace {

#define GEN_PASS_DEF_MATCHTODECISIONTREEPASS
#include "Match/Conversion/MatchToDecisionTree/Passes.h.inc"

// A remaining match position: the pattern still to check against the value
// stored in `slot` (an entry of the emitter's slot array). A null pattern marks
// the column as consumed: this row does not question the position, but keeps it
// so its remaining columns stay aligned with the other rows'. `bindBase` counts
// the binds preceding this pattern in its arm, which is the ordinal a bind here
// binds in.
struct Col {
  PatternAttr pattern;
  unsigned slot;
  unsigned bindBase;
};

struct Row {
  SmallVector<Col> cols; // remaining columns, in order
  // (ordinal, slot) of each bind consumed without a test, in the order consumed
  SmallVector<std::pair<unsigned, unsigned>> bound;
  unsigned armIndex;
  bool hasGuard = false;
};

struct DecisionNode {
  enum class Kind {
    Fail, Leaf, CtorTest, GuardTest, LiteralTest, Ineligible
  } kind;
  unsigned armIndex = 0;               // Leaf / GuardTest
  SmallVector<unsigned> bindSlots;     // Leaf / GuardTest
  SmallVector<StringRef> ctors;        // CtorTest
  unsigned slot = 0;                   // CtorTest + LiteralTest: tested slot
  SmallVector<unsigned> ctorBases;     // CtorTest: first field slot per ctor
  // CtorTest + LiteralTest; the last child is the fallback branch.
  std::vector<DecisionNode> children;
  SmallVector<IntegerAttr> literals;   // LiteralTest
};

// True when a column still asks something: a refutable pattern is needed to
// test it, while a consumed position or an irrefutable pattern rides.
bool isRefutable(const Col &col) {
  return col.pattern && col.pattern.getKind() != "bind" &&
         col.pattern.getKind() != "wildcard";
}

// True when a row has nothing left to test: no columns, or every remaining
// column irrefutable (bind/wildcard) or consumed.
bool isComplete(const Row &row) {
  for (const Col &col : row.cols)
    if (isRefutable(col))
      return false;
  return true;
}

// How many binds a pattern holds, in depth-first order.
unsigned bindCount(PatternAttr pattern) {
  if (pattern.getKind() == "bind")
    return 1;
  unsigned count = 0;
  for (PatternAttr sub : pattern.getSubpatterns())
    count += bindCount(sub);
  return count;
}

// The slots each bind of a complete row captures, in arm order.
SmallVector<unsigned> rowBindSlots(const Row &row) {
  SmallVector<std::pair<unsigned, unsigned>> binds(row.bound.begin(),
                                                   row.bound.end());
  for (const Col &col : row.cols)
    if (col.pattern && col.pattern.getKind() == "bind")
      binds.push_back({col.bindBase, col.slot});
  llvm::sort(binds);
  SmallVector<unsigned> slots;
  for (auto [ordinal, slot] : binds)
    slots.push_back(slot);
  return slots;
}

// Copy `row` with the questioned column consumed: replaced by `fill` consumed
// entries, one per field of the tested constructor (none for a literal test),
// so the row's later columns stay aligned with the specialised rows.
Row rideRow(const Row &row, unsigned column, unsigned fill) {
  Row ridden;
  ridden.armIndex = row.armIndex;
  ridden.hasGuard = row.hasGuard;
  ridden.bound = row.bound;
  Col col = row.cols[column];
  if (col.pattern && col.pattern.getKind() == "bind")
    ridden.bound.push_back({col.bindBase, col.slot});
  ridden.cols.append(row.cols.begin(), row.cols.begin() + column);
  for (unsigned i = 0; i < fill; ++i)
    ridden.cols.push_back({PatternAttr(), 0, 0});
  ridden.cols.append(row.cols.begin() + column + 1, row.cols.end());
  return ridden;
}

// The constructors heading the non-complete rows' given column, in
// first-appearance order; irrefutable rows are skipped.
SmallVector<StringRef> headConstructors(ArrayRef<Row> rows, unsigned column) {
  SmallVector<StringRef> heads;
  for (const Row &row : rows) {
    // Complete rows ride, so they may hold fewer columns than the one asked
    // about, and their heads are never tested here.
    if (isComplete(row) || row.cols.size() <= column)
      continue;
    Col col = row.cols[column];
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

// The literal payloads heading the non-complete rows' given column, in
// first-appearance order; irrefutable rows are skipped.
SmallVector<IntegerAttr> headLiterals(ArrayRef<Row> rows, unsigned column) {
  SmallVector<IntegerAttr> heads;
  for (const Row &row : rows) {
    if (isComplete(row) || row.cols.size() <= column)
      continue;
    Col col = row.cols[column];
    if (col.pattern && col.pattern.getKind() == "literal") {
      IntegerAttr literal = col.pattern.getPayload();
      if (!llvm::is_contained(heads, literal))
        heads.push_back(literal);
    }
  }
  return heads;
}

// Consume constructor `ctor` from the rows' questioned column, splicing its
// sub-patterns in. Rows headed by another constructor are excluded, while rows
// that leave the column unquestioned ride into the branch with it consumed.
SmallVector<Row> specialise(ArrayRef<Row> rows, StringRef ctor, unsigned column,
                            unsigned &nextSlot) {
  SmallVector<Row> specialised;
  // One shared slot per field: every consuming row deconstructs the same value.
  unsigned k = 0;
  for (const Row &row : rows)
    if (!isComplete(row) && row.cols.size() > column &&
        isRefutable(row.cols[column]) &&
        row.cols[column].pattern.getKind() == ctor) {
      k = row.cols[column].pattern.getSubpatterns().size();
      break;
    }
  unsigned base = nextSlot;
  nextSlot += k;

  for (const Row &row : rows) {
    if (isComplete(row)) {
      specialised.push_back(row);
      continue;
    }
    Col col = row.cols[column];
    if (!isRefutable(col)) {
      specialised.push_back(rideRow(row, column, k));
      continue;
    }
    if (col.pattern.getKind() != ctor)
      continue; // another constructor's row belongs to that branch

    Row newRow;
    newRow.armIndex = row.armIndex;
    newRow.hasGuard = row.hasGuard;
    newRow.bound = row.bound;
    newRow.cols.append(row.cols.begin(), row.cols.begin() + column);
    // Field slots are shared, and the bind ordinals continue from the examined
    // pattern's base.
    unsigned subBase = col.bindBase;
    for (auto [index, sub] : llvm::enumerate(col.pattern.getSubpatterns())) {
      newRow.cols.push_back(
          {sub, base + static_cast<unsigned>(index), subBase});
      subBase += bindCount(sub);
    }
    newRow.cols.append(row.cols.begin() + column + 1, row.cols.end());
    specialised.push_back(newRow);
  }
  return specialised;
}

// Consume the literal `payload` from the rows' questioned column, dropping it:
// a literal has no sub-patterns, so neither the rows that match it nor the rows
// that leave the column unquestioned gain a column.
SmallVector<Row> specialiseLiteral(ArrayRef<Row> rows, IntegerAttr payload,
                                   unsigned column) {
  SmallVector<Row> specialised;
  for (const Row &row : rows) {
    if (isComplete(row)) {
      specialised.push_back(row);
      continue;
    }
    Col col = row.cols[column];
    if (!isRefutable(col)) {
      specialised.push_back(rideRow(row, column, 0));
      continue;
    }
    if (col.pattern.getKind() != "literal" ||
        col.pattern.getPayload() != payload)
      continue;

    Row newRow;
    newRow.armIndex = row.armIndex;
    newRow.hasGuard = row.hasGuard;
    newRow.bound = row.bound;
    newRow.cols.append(row.cols.begin(), row.cols.begin() + column);
    newRow.cols.append(row.cols.begin() + column + 1, row.cols.end());
    specialised.push_back(newRow);
  }
  return specialised;
}

// What a test on a column asks: the slot its questioned rows share, and whether
// the column holds literals rather than constructors.
struct ColumnTest {
  unsigned slot = 0;
  bool literal = false;
};

// The test the rows would submit to at `column`, or nullopt when the rows that
// question the column read different slots: one node deconstructs one slot.
std::optional<ColumnTest> columnTest(ArrayRef<Row> rows, unsigned column) {
  std::optional<ColumnTest> test;
  for (const Row &row : rows) {
    if (isComplete(row) || row.cols.size() <= column ||
        !isRefutable(row.cols[column]))
      continue;
    ColumnTest candidate{row.cols[column].slot,
                         row.cols[column].pattern.getKind() == "literal"};
    if (test && test->slot != candidate.slot)
      return std::nullopt;
    test = candidate;
  }
  return test;
}

// The column a test should ask about first. Rows that leave a column
// unquestioned are copied into every branch, so the mixture rule prefers the
// column that makes the fewest of them ride, then the one that splits the rows
// into the most groups. Returns 0, the leftmost column, when nothing beats it.
unsigned chooseColumn(ArrayRef<Row> rows) {
  unsigned limit = 0;
  bool anyNonComplete = false;
  for (const Row &row : rows) {
    if (isComplete(row))
      continue;

    // The shortest non-complete row bounds how far the search may look.
    if (!anyNonComplete || row.cols.size() < limit) {
      limit = row.cols.size();
      anyNonComplete = true;
    }
  }
  if (!anyNonComplete)
    return 0;

  unsigned bestColumn = 0;
  unsigned bestRidden = 0;
  unsigned bestScore = 0;
  bool haveBest = false;

  for (unsigned column = 0; column < limit; ++column) {
    if (!columnTest(rows, column))
      continue; // the rows that question this column disagree on its slot

    // Rows that leave the column unquestioned are copied into every branch, so
    // the mixture rule prefers the column that makes the fewest of them ride,
    // and then the one that splits the rows into the most groups.
    unsigned ridden = 0;
    for (const Row &row : rows)
      if (!isComplete(row) && row.cols.size() > column &&
          !isRefutable(row.cols[column]))
        ++ridden;
    unsigned score = columnTest(rows, column)->literal
                         ? headLiterals(rows, column).size()
                         : headConstructors(rows, column).size();

    bool better = !haveBest || ridden < bestRidden ||
                  (ridden == bestRidden && score > bestScore);
    if (better) {
      haveBest = true;
      bestColumn = column;
      bestRidden = ridden;
      bestScore = score;
    }
  }
  return bestColumn;
}

// The rows that reach the fail branch of a test on `column`: rows that leave
// the column unquestioned, with the column consumed, plus the complete rows.
SmallVector<Row> fallbackRows(ArrayRef<Row> rows, unsigned column) {
  SmallVector<Row> fallback;
  for (const Row &row : rows) {
    if (isComplete(row))
      fallback.push_back(row);
    else if (!isRefutable(row.cols[column]))
      fallback.push_back(rideRow(row, column, 0));
  }
  return fallback;
}

// Which column the compiler questions first: `leftmost` keeps the source
// column order, `mixture` picks the column that copies the fewest rows.
enum class ColumnChoice { Leftmost, Mixture };

DecisionNode compileRows(SmallVector<Row> rows, unsigned &nextSlot,
                         ColumnChoice choice) {
  if (rows.empty())
    return DecisionNode{DecisionNode::Kind::Fail, 0, {}, {}, 0, {}, {}, {}};

  // An all-irrefutable leading column needs no test; consume it (and binds).
  for (;;) {
    Row &front = rows.front();
    if (isComplete(front))
      break;
    bool allIrrefutable = true;
    for (const Row &row : rows) {
      if (isComplete(row))
        continue;
      if (isRefutable(row.cols.front()))
        allIrrefutable = false;
    }
    if (!allIrrefutable)
      break;
    for (Row &row : rows) {
      if (isComplete(row))
        continue;
      Col col = row.cols.front();
      if (col.pattern && col.pattern.getKind() == "bind")
        row.bound.push_back({col.bindBase, col.slot});
      row.cols.erase(row.cols.begin());
    }
  }

  Row &first = rows.front();
  if (isComplete(first)) {
    // A guarded complete row cannot prune: try it, then continue on guard
    // failure with the remaining rows.
    SmallVector<unsigned> binds = rowBindSlots(first);
    if (first.hasGuard) {
      SmallVector<Row> rest(rows.begin() + 1, rows.end());
      std::vector<DecisionNode> child{
          compileRows(std::move(rest), nextSlot, choice)};
      return DecisionNode{DecisionNode::Kind::GuardTest, first.armIndex,
                          binds, {}, 0, {}, std::move(child), {}};
    }
    // bind or wildcard at the head: the first row always fires
    return DecisionNode{DecisionNode::Kind::Leaf, first.armIndex,
                        binds, {}, 0, {}, {}, {}};
  }

  // Leftmost column by default; otherwise the mixture rule picks the column
  // that forces the fewest rows to be copied.
  unsigned column = 0;
  if (choice == ColumnChoice::Mixture)
    column = chooseColumn(rows);

  // One node deconstructs one slot, so every row it questions must read that
  // slot; rows that leave the column unquestioned ride and do not constrain it.
  std::optional<ColumnTest> test = columnTest(rows, column);
  if (!test)
    return DecisionNode{DecisionNode::Kind::Ineligible, 0, {}, {}, 0, {}, {},
                        {}};

  if (test->literal) {
    SmallVector<IntegerAttr> heads = headLiterals(rows, column);
    std::vector<DecisionNode> children;
    for (IntegerAttr literal : heads) {
      DecisionNode child =
          compileRows(specialiseLiteral(rows, literal, column), nextSlot,
                      choice);
      if (child.kind == DecisionNode::Kind::Ineligible)
        return child;
      children.push_back(std::move(child));
    }

    // Rows that leave the column unquestioned, and complete rows, reach the
    // fail branch: the default region runs only when there are none.
    {
      DecisionNode child =
          compileRows(fallbackRows(rows, column), nextSlot, choice);
      if (child.kind == DecisionNode::Kind::Ineligible)
        return child;
      children.push_back(std::move(child));
    }

    return DecisionNode{DecisionNode::Kind::LiteralTest, 0, {}, {}, test->slot,
                        {}, std::move(children), std::move(heads)};
  }

  SmallVector<StringRef> heads = headConstructors(rows, column);
  SmallVector<unsigned> bases;
  std::vector<DecisionNode> children;
  for (StringRef ctor : heads) {
    bases.push_back(nextSlot);
    DecisionNode child =
        compileRows(specialise(rows, ctor, column, nextSlot), nextSlot, choice);
    if (child.kind == DecisionNode::Kind::Ineligible)
      return child;
    children.push_back(std::move(child));
  }

  // Rows that leave the column unquestioned, and complete rows, reach the fail
  // branch: the default region runs only when there are none.
  {
    DecisionNode child =
        compileRows(fallbackRows(rows, column), nextSlot, choice);
    if (child.kind == DecisionNode::Kind::Ineligible)
      return child;
    children.push_back(std::move(child));
  }

  return DecisionNode{DecisionNode::Kind::CtorTest, 0, {}, heads, test->slot,
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

PathResult emitLiteralTest(const DecisionNode &node,
                           SmallVectorImpl<Value> &slots, MatchOp match,
                           OpBuilder &builder, unsigned index);

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

    // The arm's bindings are its entry args. The condition computation is
    // re-emitted here, so the arm stays intact for the branches that emit the
    // same row again.
    Block &armBlock = match.getArms()[node.armIndex].front();
    IRMapping mapping;
    for (auto [argument, binding] :
         llvm::zip(armBlock.getArguments(), bindings))
      mapping.map(argument, binding);

    GuardOp guardOp;
    bool beforeGuard = true;
    for (Operation &op : armBlock) {
      if (auto guard = dyn_cast<GuardOp>(op)) {
        guardOp = guard;
        beforeGuard = false;
        continue;
      }
      if (!beforeGuard)
        continue;
      Operation *clone = op.clone(mapping);
      builder.insert(clone);
      builder.setInsertionPointAfter(clone);
      for (auto [orig, repl] : llvm::zip(op.getResults(), clone->getResults()))
        mapping.map(orig, repl);
    }
    assert(guardOp && "guard-test arm must contain a guard");
    Value condition = mapping.lookupOrDefault(guardOp.getCondition());

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

// Chain of constructor tests: ctors[index] gets an scf.if whose then-branch
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
PathResult emitLiteralTest(const DecisionNode &node,
                           SmallVectorImpl<Value> &slots, MatchOp match,
                           OpBuilder &builder, unsigned index) {
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

// A match is tree-eligible when it carries one pattern per arm. Every pattern
// the verifier accepts compiles: rows that leave a column unquestioned are
// copied into every branch rather than restricting the shape of a pattern.
bool isEligible(MatchOp match) {
  auto patterns = match.getPatterns();
  return patterns && !patterns->empty() &&
         patterns->size() == match.getArms().size();
}

// One row per arm: a single column matching the scrutinee (slot 0).
SmallVector<Row> buildRows(MatchOp match) {
  SmallVector<Row> rows;
  for (auto [index, attribute] : llvm::enumerate(*match.getPatterns())) {
    PatternAttr pattern = cast<PatternAttr>(attribute);
    Row row;
    row.cols.push_back({pattern, 0, 0});
    row.armIndex = static_cast<unsigned>(index);
    row.hasGuard = hasGuard(match.getArms()[index]);
    rows.push_back(row);
  }
  return rows;
}

// Accepted option spellings: one source of truth for parsing and for the
// diagnostic that reports an unrecognised value.
const std::pair<StringRef, ColumnChoice> kColumnChoices[] = {
    {"leftmost", ColumnChoice::Leftmost},
    {"mixture", ColumnChoice::Mixture}};

// Returns the strategy named by `value`, or nullopt when it is not accepted.
std::optional<ColumnChoice> parseColumnChoice(StringRef value) {
  for (auto [name, choice] : kColumnChoices)
    if (value == name)
      return choice;
  return std::nullopt;
}

// Lowers eligible pattern rows via a Maranget-style decision tree of scf
// control flow
struct MatchToDecisionTreePass
    : impl::MatchToDecisionTreePassBase<MatchToDecisionTreePass> {
  void runOnOperation() override {
    auto func = getOperation();

    // An unrecognised value must not fall back to leftmost: a typo would make
    // the column-choice comparison meaningless.
    std::optional<ColumnChoice> parsedChoice =
        parseColumnChoice(columnChoice.getValue());
    if (!parsedChoice) {
      InFlightDiagnostic diag = func.emitError()
                                << "Invalid column-choice option: '"
                                << columnChoice.getValue() << "'; expected ";
      llvm::interleaveComma(
          kColumnChoices, diag,
          [&](const std::pair<StringRef, ColumnChoice> &entry) {
            diag << "'" << entry.first << "'";
          });
      return signalPassFailure();
    }

    ColumnChoice choice = *parsedChoice;

    SmallVector<MatchOp> matches;
    func.walk([&](MatchOp match) {
      if (isEligible(match))
        matches.push_back(match);
    });

    for (MatchOp match : matches) {
      unsigned nextSlot = 1; // slot 0 is the scrutinee
      DecisionNode tree = compileRows(buildRows(match), nextSlot, choice);

      if (tree.kind == DecisionNode::Kind::Ineligible)
        continue; // rows disagree on a column's value: leave for the naive pass

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
