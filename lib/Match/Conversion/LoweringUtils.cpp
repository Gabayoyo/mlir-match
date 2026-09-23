#include "Match/Conversion/LoweringUtils.h"

#include "llvm/ADT/STLExtras.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/IRMapping.h"

namespace mlir {
namespace match {

// helper function for emitting the body of a if or else statement
void emitBody(Block &src, Block &dst, OpBuilder &builder,
              ArrayRef<Value> bindings) {
  auto yield = cast<YieldOp>(src.getTerminator());

  // Clone instead of moving: a row that does not test a column is copied into
  // each of its branches, so a body may be emitted more than once.
  IRMapping mapping;
  for (auto [argument, binding] : llvm::zip(src.getArguments(), bindings))
    mapping.map(argument, binding);

  // An arm's ops before its guard compute the guard condition, which the caller
  // hoists; the body is what follows the guard.
  bool guarded =
      llvm::any_of(src, [](Operation &op) { return isa<GuardOp>(op); });
  bool afterGuard = !guarded;

  builder.setInsertionPointToEnd(&dst);
  for (Operation &op : src) {
    if (&op == yield)
      continue;

    if (isa<GuardOp>(op)) {
      afterGuard = true;
      continue;
    }

    if (!afterGuard)
      continue;

    Operation *clone = op.clone(mapping);
    builder.insert(clone);
    for (auto [orig, repl] : llvm::zip(op.getResults(), clone->getResults()))
      mapping.map(orig, repl);
  }

  SmallVector<Value> results;
  for (Value operand : yield.getOperands())
    results.push_back(mapping.lookupOrDefault(operand));

  builder.setInsertionPointToEnd(&dst);
  scf::YieldOp::create(builder, yield.getLoc(), ValueRange(results));
}

// check if arm has a guard op
bool hasGuard(Region &arm) {
  return llvm::any_of(arm.front(),
                      [](Operation &op) { return isa<GuardOp>(op); });
}

} // namespace match
} // namespace mlir
