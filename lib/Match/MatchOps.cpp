#include "Match/MatchOps.h"

using namespace mlir;

namespace mlir::match {
    
// placeholder for now
LogicalResult MatchOp::verify() {
    return success();
}

void MatchOp::getSuccessorRegions(
    ::mlir::RegionBranchPoint point,
    ::llvm::SmallVectorImpl<::mlir::RegionSuccessor> &regions) {
        if (point.isParent()) {
            if (!getArms().empty())
                // if the parent op is the branch point, then the first arm is the successor
                regions.push_back(RegionSuccessor(&getArms().front()));
        } else {
            // get the terminator's predecessor
            auto pred = point.getTerminatorPredecessorOrNull();
            if (pred) {
                // since its a final terminator, we can just add the parent op as the successor
                regions.push_back(::mlir::RegionSuccessor(getOperation()));

                // if yield is conditional, its either the parent or the next arm
                if (isa<CondYieldOp>(pred)) {
                    auto index = pred->getParentRegion()->getRegionNumber();
                    if (index + 1 < getArms().size()) {
                        regions.push_back(::mlir::RegionSuccessor(&getArms()[index + 1]));
                    }
                }
            } else {
                llvm_unreachable("unexpected branch point");
            }
        }
    }

} // namespace mlir::match