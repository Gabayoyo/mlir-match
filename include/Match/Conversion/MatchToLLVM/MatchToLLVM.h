#ifndef MATCH_CONVERSION_MATCHTOLLVM_MATCHTOLLVM_H
#define MATCH_CONVERSION_MATCHTOLLVM_MATCHTOLLVM_H

namespace mlir {
class ConversionTarget;
class LLVMTypeConverter;
class RewritePatternSet;

namespace match {

// Configure the target: which dialects and ops must be gone by the end.
void configureMatchToLLVMConversionLegality(ConversionTarget &target);

// Add the patterns that lower match ops to LLVM dialect ops.
void populateMatchToLLVMConversionPatterns(const LLVMTypeConverter &converter,
                                           RewritePatternSet &patterns);

} // namespace match
} // namespace mlir

#endif // MATCH_CONVERSION_MATCHTOLLVM_MATCHTOLLVM_H