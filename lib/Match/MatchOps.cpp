#include "Match/MatchOps.h"

namespace mlir {
namespace match {
namespace {

// match.yield must carry as many values as the match op has results
// and the types must match
LogicalResult checkYield(MatchOp match, Region &region) {
  auto yield = dyn_cast<YieldOp>(region.front().getTerminator());
  if (!yield)
    return match.emitOpError("region must terminate with a match.yield");
  if (yield.getNumOperands() != match.getNumResults())
    return match.emitOpError(
        "match.yield must carry as many values as the match op has results");
  for (unsigned i = 0, e = match.getNumResults(); i != e; ++i) {
    if (yield.getOperand(i).getType() != match.getResult(i).getType())
      return match.emitOpError(
          "match.yield result types must match the match op result types");
  }
  return success();
}

} // namespace

LogicalResult MatchOp::verify() {

    // default case should not contain guard
    for (Operation &op : getOtherwise().front()) {
        if (isa<GuardOp>(op))
            return emitOpError("the default region may not contain a match.guard");
    }

    // each arm may contain at most one guard
    for (Region &arm : getArms()) {
        bool hasGuard = false;
        for (Operation &op : arm.front()) {
            if (isa<GuardOp>(op)) {
                if (hasGuard)
                    return emitOpError("an arm may contain at most one match.guard");
                hasGuard = true;
            }
        }
    }

    // check default case's yield
    if (failed(checkYield(*this, getOtherwise())))
        return failure();
    
    // check each arm's yield
    for (Region &arm : getArms())
        if (failed(checkYield(*this, arm)))
            return failure();

    return success();
}

// We define getSuccessorRegions here since RegionBranchOpInterface has no default implementation
// Needed for CFG analysis, and to satisfy the RegionBranchOpInterface trait.
void MatchOp::getSuccessorRegions(
    ::mlir::RegionBranchPoint point,
    ::llvm::SmallVectorImpl<::mlir::RegionSuccessor> &regions) {
        
    // if the point is the parent op, we have multiple successors:
    // default case and every possible arm
    if (point.isParent()) {
        regions.push_back(::mlir::RegionSuccessor(&getOtherwise()));
        for (auto &arm : getArms())
            regions.push_back(::mlir::RegionSuccessor(&arm));
    } else {
        // else, the point is an arm, so the single successor is the parent op
        regions.push_back(::mlir::RegionSuccessor(getOperation()));
    }
}

// When a region's match.yield exits to this op, its operands become the op's
// results; the arm and default regions take no block arguments.
::mlir::ValueRange MatchOp::getSuccessorInputs(::mlir::RegionSuccessor successor) {
  if (successor.isOperation())
    return getResults();
  return {};
}

} // namespace match
} // namespace mlir
