#include "Match/Conversion/MatchToLLVM/Passes.h"
#include "Match/Conversion/MatchToLLVM/MatchToLLVM.h"
#include "Match/MatchOps.h"
#include "Match/MatchAttrs.h"
#include "Match/MatchTypes.h"
#include <iterator>

namespace mlir {

namespace match {

struct MatchToLLVMPass : public impl::MatchToLLVMPassBase<MatchToLLVMPass> {
    void runOnOperation() override {
    }
}

}
}