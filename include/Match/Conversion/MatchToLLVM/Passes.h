#ifndef MATCH_CONVERSION_MATCHTOLLVM_PASSES_H
#define MATCH_CONVERSION_MATCHTOLLVM_PASSES_H

#include "mlir/Pass/Pass.h"
#include <memory>

namespace mlir {

// forward declarations, used in in-tree dialects too, cheaper than including headers
class ConversionTarget;
class LLVMTypeConverter;
class RewritePatternSet;
class Pass;

namespace match {

#define GEN_PASS_DECL
#include "Match/Conversion/MatchToLLVM/Passes.h.inc"

std::unique_ptr<Pass> createMatchToLLVMPass();                                

} // namespace match

#define GEN_PASS_REGISTRATION
#include "Match/Conversion/MatchToLLVM/Passes.h.inc"

} // namespace mlir

#endif // MATCH_CONVERSION_MATCHTOLLVM_PASSES_H
