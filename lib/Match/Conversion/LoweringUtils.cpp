#include "Match/Conversion/LoweringUtils.h"

#include "llvm/ADT/STLExtras.h"
#include "mlir/Dialect/SCF/IR/SCF.h"

namespace mlir {
namespace match {

void emitBody(Block &src, Block &dst, OpBuilder &builder,
              ArrayRef<Value> bindings) {
  auto yield = cast<YieldOp>(src.getTerminator());

  // Rewrite the bindings' uses before moving, so moved ops and the yield
  // keep valid references once the arm block is gone.
  for (auto [argument, binding] : llvm::zip(src.getArguments(), bindings))
    argument.replaceAllUsesWith(binding);

  SmallVector<Value> results(yield.getOperands());

  for (Operation &op : llvm::make_early_inc_range(src)) {
    if (&op == yield)
      continue;
    op.moveBefore(&dst, dst.end());
  }

  builder.setInsertionPointToEnd(&dst);
  scf::YieldOp::create(builder, yield.getLoc(), ValueRange(results));
}

bool hasGuard(Region &arm) {
  return llvm::any_of(arm.front(), [](Operation &op) {
    return isa<GuardOp>(op);
  });
}

} // namespace match
} // namespace mlir
