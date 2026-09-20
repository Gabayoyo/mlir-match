#ifndef MATCH_CONVERSION_MATCHTOLLVM_PASSES_H
#define MATCH_CONVERSION_MATCHTOLLVM_PASSES_H

#include "mlir/Pass/Pass.h"
#include <memory>

namespace mlir {

namespace match {

#define GEN_PASS_DECL
#include "Match/Conversion/MatchToLLVM/Passes.h.inc"

std::unique_ptr<Pass> createMatchToLLVMPass();

} // namespace match

#define GEN_PASS_REGISTRATION
#include "Match/Conversion/MatchToLLVM/Passes.h.inc"

} // namespace mlir

#endif // MATCH_CONVERSION_MATCHTOLLVM_PASSES_H
