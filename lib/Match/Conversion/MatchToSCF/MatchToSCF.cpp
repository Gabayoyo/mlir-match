#include "Match/Conversion/MatchToSCF/Passes.h"
#include "Match/MatchOps.h"

#include "llvm/ADT/STLExtras.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/SCF/IR/SCF.h"

#include <optional>

namespace mlir {
namespace match {
namespace {

#define GEN_PASS_DEF_MATCHTOSCFPASS
#include "Match/Conversion/MatchToSCF/Passes.h.inc"

// Move `src`'s body ops (everything before its match.yield) to the end of
// `dst`, then terminate `dst` with an scf.yield carrying the match.yield's
// operands.
static void emitBody(Block &src, Block &dst, OpBuilder &builder) {
  auto yield = cast<YieldOp>(src.getTerminator());
  SmallVector<Value> results(yield.getOperands());

  for (Operation &op : llvm::make_early_inc_range(src)) {
    if (&op == yield)
      continue;
    op.moveBefore(&dst, dst.end());
  }

  builder.setInsertionPointToEnd(&dst);
  scf::YieldOp::create(builder, yield.getLoc(), ValueRange(results));
}

// Returns true if the arm region contains a guard op.
static bool hasGuard(Region &arm) {
  return llvm::any_of(arm.front(), [](Operation &op) {
    return isa<GuardOp>(op);
  });
}

// The result values of a lowered chain, or nullopt when the chain terminated
// the current block itself (a guard-less arm or the default body).
using ChainResult = std::optional<SmallVector<Value>>;

// Lowers arms[armIndex..] plus the default into nested scf.if chains at
// `builder`'s insertion point; returns the values the chain produces. The
// base case (no arms left) runs the default body in the current block.
ChainResult buildChain(MatchOp matchOp, unsigned armIndex,
                       Region &defaultRegion, OpBuilder &builder) {

  // We still have arms to process.
  if (armIndex < matchOp.getArms().size()) {
    Block &condDst = *builder.getInsertionBlock();
    Block &condSrc = matchOp.getArms()[armIndex].front();

    // Split the arm at its guard: the ops before it compute the condition,
    // the ops after it form the body.
    GuardOp guardOp;
    bool beforeGuard = true;
    SmallVector<Operation *> condOps;
    SmallVector<Operation *> bodyOps;

    for (Operation &op : llvm::make_early_inc_range(condSrc)) {
      if (auto guard = dyn_cast<GuardOp>(op)) {
        guardOp = guard;
        beforeGuard = false;
        continue;
      }
      (beforeGuard ? condOps : bodyOps).push_back(&op);
    }

    if (!guardOp) {
      // An arm without a guard always matches, so it is terminal: inline its
      // body and return, leaving later arms unreachable.
      emitBody(condSrc, condDst, builder);
      return std::nullopt;
    }

    // Hoist the condition computation into the current block so it dominates
    // the scf.if and the region contents that use it.
    for (Operation *op : condOps)
      op->moveBefore(&condDst, builder.getInsertionPoint());

    // The arm's condition is the guard's operand.
    Value condition = guardOp.getCondition();
    guardOp->erase();
    auto scfIf = scf::IfOp::create(builder, matchOp.getLoc(),
                                   matchOp.getResultTypes(), condition,
                                   /*addThenBlock=*/true,
                                   /*addElseBlock=*/true);

    // The body (the ops after the guard) fills the then region.
    Block &thenBlock = scfIf.getThenRegion().front();
    emitBody(condSrc, thenBlock, builder);

    // The rest of the match goes into the if's else region.
    builder.setInsertionPointToEnd(&scfIf.getElseRegion().front());
    ChainResult inner = buildChain(matchOp, armIndex + 1, defaultRegion,
                                   builder);
    if (inner) {
      builder.setInsertionPointToEnd(&scfIf.getElseRegion().front());
      scf::YieldOp::create(builder, matchOp.getLoc(), ValueRange(*inner));
    }
    // The chain's result values are the scf.if's results.
    SmallVector<Value> results;
    results.append(scfIf.getResults().begin(), scfIf.getResults().end());
    return results;
  }

  // Base case: no arms remain; run the default body in the current block.
  emitBody(defaultRegion.front(), *builder.getInsertionBlock(), builder);
  return std::nullopt;
}

// This pass converts the match dialect to the SCF dialect
struct MatchToSCFPass : impl::MatchToSCFPassBase<MatchToSCFPass> {
  void runOnOperation() override {
    auto func = getOperation();
    SmallVector<MatchOp> matchOps;
    func.walk([&](MatchOp matchOp) {
      matchOps.push_back(matchOp);
    });

    for (MatchOp matchOp : matchOps) {
      OpBuilder builder(matchOp.getOperation());

      // A match whose first arm has no guard (or that has no arms at all)
      // never builds an scf.if: that arm, or the default, always matches. In
      // that case inline its body in place of the match and replace the
      // match's uses with the yielded values directly.
      Region &unconditional =
          !matchOp.getArms().empty() ? matchOp.getArms().front()
                                     : matchOp.getOtherwise();
      if (matchOp.getArms().empty() || !hasGuard(unconditional)) {
        Block &dst = *builder.getInsertionBlock();
        auto yield = cast<YieldOp>(unconditional.front().getTerminator());
        SmallVector<Value> results(yield.getOperands());

        for (Operation &op : llvm::make_early_inc_range(unconditional.front())) {
          if (&op == yield)
            continue;
          op.moveBefore(&dst, builder.getInsertionPoint());
        }
        matchOp.replaceAllUsesWith(results);
        matchOp.erase();
        continue;
      }

      ChainResult results = buildChain(matchOp, 0, matchOp.getOtherwise(),
                                       builder);
      if (results) {
        matchOp.replaceAllUsesWith(*results);
        matchOp.erase();
      }
    }
  }
};

} // namespace

std::unique_ptr<Pass> createMatchToSCFPass() {
  return std::make_unique<MatchToSCFPass>();
}

} // namespace match
} // namespace mlir
