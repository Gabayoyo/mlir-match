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
#include <set>
#include <iterator>
#include <map>

// One column: a position still to test, holding the pattern to check against
// the value at `slot`, an index into this pass's array of SSA values.
struct Col {
  PatternAttr pattern; // null when this row does not test the position
  unsigned slot;
  unsigned bindBase; // binds before it, i.e. the index its first bind takes
};

struct Row {
  SmallVector<Col> cols; // remaining columns, in order
  // (bind index, value slot) of each bind captured without a test, in that
  // order
  SmallVector<std::pair<unsigned, unsigned>> bound;
  unsigned armIndex;
  bool hasGuard = false;
};

struct DecisionNode {
  enum class Kind {
    Fail,
    Leaf,
    CtorTest,
    GuardTest,
    LiteralTest,
    Ineligible
  } kind;
  unsigned armIndex = 0;           // Leaf / GuardTest
  SmallVector<unsigned> bindSlots; // Leaf / GuardTest
  SmallVector<StringRef> ctors;    // CtorTest
  unsigned slot = 0;               // CtorTest + LiteralTest: tested slot
  SmallVector<unsigned> ctorBases; // CtorTest: first field slot per ctor
  // CtorTest + LiteralTest; the last child is the fallback branch.
  std::vector<DecisionNode> children;
  SmallVector<IntegerAttr> literals; // LiteralTest
};

// True when a column needs a test: its pattern can fail, unlike a bind, a
// wildcard, or a position this row no longer tests.
bool isRefutable(const Col &col) {
  return col.pattern && !isIrrefutable(col.pattern);
}

// True when a row has nothing left to test: no columns, or every remaining
// column a bind, a wildcard, or a position it no longer tests.
bool isComplete(const Row &row) {
  for (const Col &col : row.cols)
    if (isRefutable(col))
      return false;
  return true;
}

// How many binds a pattern holds, in depth-first order.
unsigned bindCount(PatternAttr pattern) {
  if (getPatternKind(pattern) == PatternKind::Bind)
    return 1;

  unsigned count = 0;
  for (PatternAttr sub : pattern.getSubpatterns())
    count += bindCount(sub);

  return count;
}

// The value slots each bind of a complete row captures, in arm order.
SmallVector<unsigned> rowBindSlots(const Row &row) {
  SmallVector<std::pair<unsigned, unsigned>> binds(row.bound.begin(),
                                                   row.bound.end());
  for (const Col &col : row.cols) {
    if (col.pattern && getPatternKind(col.pattern) == PatternKind::Bind) {
      binds.push_back({col.bindBase, col.slot});
    }
  }

  llvm::sort(binds);
  SmallVector<unsigned> slots;
  for (auto [ordinal, slot] : binds)
    slots.push_back(slot);

  return slots;
}

// Copy `row` without the column being tested, leaving `fill` placeholder
// entries so its later columns stay aligned with the rows that were split.
Row rideRow(const Row &row, unsigned column, unsigned fill) {
  Row ridden;
  ridden.armIndex = row.armIndex;
  ridden.hasGuard = row.hasGuard;
  ridden.bound = row.bound;
  Col col = row.cols[column];

  if (col.pattern && getPatternKind(col.pattern) == PatternKind::Bind) {
    ridden.bound.push_back({col.bindBase, col.slot});
  }
  ridden.cols.append(row.cols.begin(), row.cols.begin() + column);
  for (unsigned i = 0; i < fill; ++i) {
    ridden.cols.push_back({PatternAttr(), 0, 0});
  }
  ridden.cols.append(row.cols.begin() + column + 1, row.cols.end());

  return ridden;
}

// The constructors named at `column` by the rows that still test, in
// first-appearance order; rows with no pattern there are skipped.
SmallVector<StringRef> headConstructors(ArrayRef<Row> rows, unsigned column) {
  SmallVector<StringRef> heads;

  for (const Row &row : rows) {
    // A complete row may hold fewer columns than the one being tested, and its
    // patterns are never tested here.
    if (isComplete(row) || row.cols.size() <= column)
      continue;
    Col col = row.cols[column];

    // bind, wildcard or dropped: no test needed here
    if (!col.pattern || isIrrefutable(col.pattern))
      continue;

    // get ctor
    StringRef ctor = col.pattern.getKind();

    // if the constructor has already been seen, the row belongs to that branch
    if (llvm::is_contained(heads, ctor))
      continue;

    heads.push_back(ctor);
  }

  return heads;
}

// The literal payloads named at `column` by the rows that still test, in
// first-appearance order; rows with no pattern there are skipped.
SmallVector<IntegerAttr> headLiterals(ArrayRef<Row> rows, unsigned column) {
  SmallVector<IntegerAttr> heads;

  for (const Row &row : rows) {
    if (isComplete(row) || row.cols.size() <= column)
      continue;
    Col col = row.cols[column];

    if (col.pattern && getPatternKind(col.pattern) == PatternKind::Literal) {
      IntegerAttr literal = col.pattern.getPayload();

      // if the literal has not been seen, add it to the list of literal heads
      if (!llvm::is_contained(heads, literal))
        heads.push_back(literal);
    }
  }
  return heads;
}

// Split the rows on constructor `ctor` at the column being tested, splicing
// its sub-patterns in; rows naming another constructor there are excluded.
SmallVector<Row> specialise(ArrayRef<Row> rows, StringRef ctor, unsigned column,
                            unsigned &nextSlot) {
  SmallVector<Row> specialised;

  // One shared value per field: every row split here deconstructs the same one.
  unsigned k = 0;

  // Find the number of fields in the constructor being tested, so the new rows
  // can reserve the right number of slots for them.
  for (const Row &row : rows) {
    if (!isComplete(row) && row.cols.size() > column &&
        isRefutable(row.cols[column]) &&
        row.cols[column].pattern.getKind() == ctor) {
      k = row.cols[column].pattern.getSubpatterns().size();
      break;
    }
  }

  // set the base slot for the fields of this constructor
  unsigned base = nextSlot;

  // and increment the next slot index for the next constructor's fields
  nextSlot += k;

  // create the specialised rows
  for (const Row &row : rows) {

    // if the row is complete, it is added to the specialised rows without
    // change
    if (isComplete(row)) {
      specialised.push_back(row);
      continue;
    }

    // if the row is irrefutable, its columns are copied into every current
    // branch of the test
    Col col = row.cols[column];
    if (!isRefutable(col)) {
      specialised.push_back(rideRow(row, column, k));
      continue;
    }

    // another constructor's row belongs to that branch
    if (col.pattern.getKind() != ctor)
      continue;

    Row newRow;
    newRow.armIndex = row.armIndex;
    newRow.hasGuard = row.hasGuard;
    newRow.bound = row.bound;
    newRow.cols.append(row.cols.begin(), row.cols.begin() + column);
    unsigned subBase = col.bindBase;

    // Give the tested column one column per sub-pattern, in order
    for (auto [index, sub] : llvm::enumerate(col.pattern.getSubpatterns())) {
      newRow.cols.push_back(
          {sub, base + static_cast<unsigned>(index), subBase});

      // iterate the bind base by the number of binds in the sub-pattern
      // in order to keep the bind bases of the later columns aligned with the
      // rows
      subBase += bindCount(sub);
    }

    // Copy the remaining columns after the tested column, which are unaffected
    // by the test
    newRow.cols.append(row.cols.begin() + column + 1, row.cols.end());
    specialised.push_back(newRow);
  }
  return specialised;
}

// Split the rows on the literal `payload` at the column being tested, dropping
// it, since a literal has no sub-patterns to splice in.
SmallVector<Row> specialiseLiteral(ArrayRef<Row> rows, IntegerAttr payload,
                                   unsigned column) {
  SmallVector<Row> specialised;

  for (const Row &row : rows) {

    // if the row is complete, ignore it and add it to the specialised rows
    // without change
    if (isComplete(row)) {
      specialised.push_back(row);
      continue;
    }

    Col col = row.cols[column];

    // if the row is irrefutable, its columns are copied into every current
    // branch of the test
    if (!isRefutable(col)) {
      specialised.push_back(rideRow(row, column, 0));
      continue;
    }

    // if the pattern is not literal, ignore it
    if (getPatternKind(col.pattern) != PatternKind::Literal ||
        col.pattern.getPayload() != payload)
      continue;

    Row newRow;
    newRow.armIndex = row.armIndex;
    newRow.hasGuard = row.hasGuard;
    newRow.bound = row.bound;

    // Copy the columns before and after the tested column
    // drop the tested column since it has no sub-patterns
    newRow.cols.append(row.cols.begin(), row.cols.begin() + column);
    newRow.cols.append(row.cols.begin() + column + 1, row.cols.end());
    specialised.push_back(newRow);
  }
  return specialised;
}

// What a test reads: the value slot the rows being tested share, and whether
// the column holds literals rather than constructors.
struct ColumnTest {
  unsigned slot = 0;
  bool literal = false;
};

// The test to apply at `column`, or nullopt when the rows being tested read
// different slots
std::optional<ColumnTest> columnTest(ArrayRef<Row> rows, unsigned column) {
  std::optional<ColumnTest> test;

  for (const Row &row : rows) {

    // if the row is complete, or is irrefutable, we ignore
    if (isComplete(row) || row.cols.size() <= column ||
        !isRefutable(row.cols[column]))
      continue;

    ColumnTest candidate{row.cols[column].slot,
                         getPatternKind(row.cols[column].pattern) ==
                             PatternKind::Literal};

    // check that the slots are all the same, else we return a nullopt
    if (test && test->slot != candidate.slot)
      return std::nullopt;
    test = candidate;
  }
  return test;
}

// The column to test first: the mixture rule prefers the column that copies the
// fewest rows into its branches, then the one that splits them the most.
unsigned chooseColumn(ArrayRef<Row> rows) {
  unsigned limit = 0;
  bool anyNonComplete = false;

  for (const Row &row : rows) {

    // if row is complete, we ignore
    if (isComplete(row))
      continue;

    // The shortest non-complete row bounds how far the search may look.
    if (!anyNonComplete || row.cols.size() < limit) {
      // save the row with the most columns
      limit = row.cols.size();
      anyNonComplete = true;
    }
  }

  // if all rows are complete, there are no rows we can test/specialise
  if (!anyNonComplete)
    return 0;

  unsigned bestColumn = 0;
  unsigned bestRidden = 0;
  unsigned bestScore = 0;
  bool haveBest = false;

  // iterate through every column left to right
  for (unsigned column = 0; column < limit; ++column) {
    // if we cant devise a column test, we ignore this column
    if (!columnTest(rows, column))
      continue;

    // We count how many rows would ride if we were to test this column
    unsigned ridden = 0;
    for (const Row &row : rows) {
      if (!isComplete(row) && row.cols.size() > column &&
          !isRefutable(row.cols[column]))
        ++ridden;
    }

    unsigned score = columnTest(rows, column)->literal
                         ? headLiterals(rows, column).size()
                         : headConstructors(rows, column).size();

    // a column is better if it rides less rows or in case of a tiebreak,
    // which would have the least branches amongst ctors and literals
    bool better = !haveBest || ridden < bestRidden ||
                  (ridden == bestRidden && score > bestScore);

    // testing this column is better, save and compare with later columns
    if (better) {
      haveBest = true;
      bestColumn = column;
      bestRidden = ridden;
      bestScore = score;
    }
  }
  return bestColumn;
}

// The rows that reach the fail branch of the test
// These
SmallVector<Row> fallbackRows(ArrayRef<Row> rows, unsigned column) {
  SmallVector<Row> fallback;

  for (const Row &row : rows) {
    if (isComplete(row)) {
      fallback.push_back(row);
    } else if (!isRefutable(row.cols[column])) {
      // possible that the "taken" branch could still reach these rows
      // so we must ride them into that branch as well
      fallback.push_back(rideRow(row, column, 0));
    }
  }

  return fallback;
}

// Turns the remaining rows into a tree of questions, branching once per answer
// and recursing on each branch until a row is left with nothing to check.
DecisionNode compileRows(SmallVector<Row> rows, unsigned &nextSlot,
                         ColumnChoice choice) {
  if (rows.empty())
    return DecisionNode{DecisionNode::Kind::Fail, 0, {}, {}, 0, {}, {}, {}};

  for (;;) {
    Row &front = rows.front();
    if (isComplete(front))
      break;
    bool allIrrefutable = true;

    // check if all rows are irrefutable, if so, exit loop
    for (const Row &row : rows) {
      if (isComplete(row))
        continue;
      if (isRefutable(row.cols.front()))
        allIrrefutable = false;
    }
    if (!allIrrefutable)
      break;

    // all rows cant fail; untestable position; we drop columns iteratively
    // resulting in either all rows become complete or some testable position
    for (Row &row : rows) {
      if (isComplete(row))
        continue;
      Col col = row.cols.front();

      // records bindings and what slot it comes from; sets up its use as
      // arguments
      if (col.pattern && getPatternKind(col.pattern) == PatternKind::Bind)
        row.bound.push_back({col.bindBase, col.slot});

      row.cols.erase(row.cols.begin());
    }
  }

  Row &first = rows.front();
  if (isComplete(first)) {
    // A guarded complete row cannot be dropped: try it, and fall back to the
    // remaining rows when the guard fails.
    SmallVector<unsigned> binds = rowBindSlots(first);
    if (first.hasGuard) {
      SmallVector<Row> rest(rows.begin() + 1, rows.end());
      std::vector<DecisionNode> child{
          compileRows(std::move(rest), nextSlot, choice)};
      return DecisionNode{DecisionNode::Kind::GuardTest,
                          first.armIndex,
                          binds,
                          {},
                          0,
                          {},
                          std::move(child),
                          {}};
    }
    // A bind or wildcard pattern: the first row always applies
    return DecisionNode{
        DecisionNode::Kind::Leaf, first.armIndex, binds, {}, 0, {}, {}, {}};
  }

  // Leftmost column by default; otherwise the mixture rule picks the column
  // that copies the fewest rows.
  unsigned column = 0;

  // if mixture column choice option, we pick the best column
  if (choice == ColumnChoice::Mixture)
    column = chooseColumn(rows);

  // test the chosen column
  std::optional<ColumnTest> test = columnTest(rows, column);

  if (!test)
    return DecisionNode{
        DecisionNode::Kind::Ineligible, 0, {}, {}, 0, {}, {}, {}};

  // test is literal
  if (test->literal) {
    // gather literal heads and test each differing one
    SmallVector<IntegerAttr> heads = headLiterals(rows, column);
    std::vector<DecisionNode> children;

    for (IntegerAttr literal : heads) {
      // recurse into the posibilities
      DecisionNode child = compileRows(specialiseLiteral(rows, literal, column),
                                       nextSlot, choice);

      if (child.kind == DecisionNode::Kind::Ineligible)
        return child;
      children.push_back(std::move(child));
    }

    // The rows that do not test the column, and complete rows, reach the fail
    // branch: the default region runs only when there are none.
    {
      DecisionNode child =
          compileRows(fallbackRows(rows, column), nextSlot, choice);
      if (child.kind == DecisionNode::Kind::Ineligible)
        return child;
      children.push_back(std::move(child));
    }

    return DecisionNode{DecisionNode::Kind::LiteralTest,
                        0,
                        {},
                        {},
                        test->slot,
                        {},
                        std::move(children),
                        std::move(heads)};
  }

  // else is a constructor test, gather heads and recurse through children
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

  // The rows that do not test the column, and complete rows, reach the fail
  // branch: the default region runs only when there are none.
  {
    DecisionNode child =
        compileRows(fallbackRows(rows, column), nextSlot, choice);
    if (child.kind == DecisionNode::Kind::Ineligible)
      return child;
    children.push_back(std::move(child));
  }

  return DecisionNode{
      DecisionNode::Kind::CtorTest, 0, {}, heads, test->slot, std::move(bases),
      std::move(children),          {}};
}

// copies the match's default region into the branch where nothing matched
// is called when the DecisionNode is a Fail (e.g. branch has no rows left)
void emitDefault(MatchOp match, Block &dst, OpBuilder &builder) {
  Block &def = match.getOtherwise().front();
  auto yield = cast<YieldOp>(def.getTerminator());
  builder.setInsertionPointToEnd(&dst);

  // Clone with an IRMapping so clones reference each other's results
  // Important so that results are shared and not local within regions
  IRMapping mapping;

  // for every op, insert the clone into the region
  for (Operation &op : llvm::make_early_inc_range(def)) {
    // ignore match.yield
    if (&op == yield)
      continue;

    // maintain mapping
    Operation *clone = op.clone(mapping);
    builder.insert(clone);
    for (auto [orig, repl] : llvm::zip(op.getResults(), clone->getResults()))
      mapping.map(orig, repl);
  }

  // Get the match.yield results and assign it to scf.yield
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

PathResult emitGuardTest(const DecisionNode &node,
                         SmallVectorImpl<Value> &slots, MatchOp match,
                         OpBuilder &builder);

// core node emission function, delegates to various emission functions
PathResult emitNode(const DecisionNode &node, SmallVectorImpl<Value> &slots,
                    MatchOp match, OpBuilder &builder) {
  switch (node.kind) {
  // leaf case, emit body
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
    return emitGuardTest(node, slots, match, builder);
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

  // get the constructor type
  auto descriptorOpt =
      lookupConstructor(slots[node.slot].getType(), node.ctors[index]);
  assert(descriptorOpt && "tree-eligible constructor must exist");
  const ConstructorDescriptor &descriptor = *descriptorOpt;

  // Gather types of the descriptor so we know the result types of the
  // deconstruct op. I1 Type always due to %matched, the bool for if it matches
  // the ctor
  SmallVector<Type> deconstructTypes{builder.getI1Type()};
  deconstructTypes.append(descriptor.fieldTypes.begin(),
                          descriptor.fieldTypes.end());

  // make deconstruct op
  auto deconstruct =
      match::DeconstructOp::create(builder, match.getLoc(), deconstructTypes,
                                   slots[node.slot], node.ctors[index]);

  // make the if op and set it based on the match.deconstruct's %matched
  auto scfIf = scf::IfOp::create(
      builder, match.getLoc(),
      SmallVector<Type>(match.getResultTypes().begin(),
                        match.getResultTypes().end()),
      deconstruct.getResult(0), /*addThenBlock=*/true, /*addElseBlock=*/true);

  // Then-branch
  Block &thenBlock = scfIf.getThenRegion().front();
  builder.setInsertionPointToEnd(&thenBlock);
  unsigned fieldBase = node.ctorBases[index];

  // constructor fields become values the child node and its leaves can read
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

  // if still more constructors to test
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
  // construct the condition, the literal test
  Value literal =
      arith::ConstantOp::create(builder, match.getLoc(), node.literals[index]);

  // comparison op used
  Value equal =
      arith::CmpIOp::create(builder, match.getLoc(), arith::CmpIPredicate::eq,
                            slots[node.slot], literal);

  auto scfIf =
      scf::IfOp::create(builder, match.getLoc(),
                        SmallVector<Type>(match.getResultTypes().begin(),
                                          match.getResultTypes().end()),
                        equal, /*addThenBlock=*/true, /*addElseBlock=*/true);

  // Then-branch: this literal's child node. No new values appear: the tested
  // slot still holds what later columns and bind rows read.
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

  // if still more literals to test
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

// The guard tests, crafting an scf.if op with the guard as the condition
PathResult emitGuardTest(const DecisionNode &node,
                         SmallVectorImpl<Value> &slots, MatchOp match,
                         OpBuilder &builder) {
  SmallVector<Value> bindings;
  for (unsigned slot : node.bindSlots)
    bindings.push_back(slots[slot]);

  Block &armBlock = match.getArms()[node.armIndex].front();
  IRMapping mapping;
  for (auto [argument, binding] : llvm::zip(armBlock.getArguments(), bindings))
    mapping.map(argument, binding);

  // The guard's condition is computed by the ops before the guard marker, which
  // are re-emitted here so the arm stays intact for its body.
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

  // create if op with guard as condition
  auto scfIf = scf::IfOp::create(
      builder, match.getLoc(),
      SmallVector<Type>(match.getResultTypes().begin(),
                        match.getResultTypes().end()),
      condition, /*addThenBlock=*/true, /*addElseBlock=*/true);

  // Then-branch: the guard held, so this arm's body fires.
  Block &thenBlock = scfIf.getThenRegion().front();
  builder.setInsertionPointToEnd(&thenBlock);
  emitBody(armBlock, thenBlock, builder, bindings);

  // Else-branch: the guard failed, so matching continues with the remaining
  // rows, which a guard test holds as its single child.
  Block &elseBlock = scfIf.getElseRegion().front();
  builder.setInsertionPointToEnd(&elseBlock);
  PathResult rest = emitNode(node.children.front(), slots, match, builder);
  if (rest) {
    builder.setInsertionPointToEnd(&elseBlock);
    scf::YieldOp::create(builder, match.getLoc(), ValueRange(*rest));
  }
  return SmallVector<Value>(scfIf.getResults());
}

// A match is tree-eligible when it carries one pattern per arm; any pattern the
// verifier accepts compiles.
bool isEligible(MatchOp match) {
  auto patterns = match.getPatterns();
  return patterns && !patterns->empty() &&
         patterns->size() == match.getArms().size();
}

// One row per arm, with a single column: the scrutinee itself (slot 0).
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

// Lowers eligible pattern rows via a Maranget-style decision tree of scf
// control flow
struct MatchToDecisionTreePass
    : impl::MatchToDecisionTreePassBase<MatchToDecisionTreePass> {
  void runOnOperation() override {
    auto func = getOperation();
    ColumnChoice choice = columnChoice;

    // walk for match ops and collect eligible matches
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

        // add bindings
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

      // else, recursive emission approach
      OpBuilder builder(match.getOperation());
      SmallVector<Value> slots(nextSlot);
      slots[0] = match.getScrutinee();
      PathResult results = emitNode(tree, slots, match, builder);

      // replace the match.match op with scf.if chain
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
