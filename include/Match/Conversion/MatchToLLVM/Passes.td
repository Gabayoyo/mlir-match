#ifndef MATCH_CONVERSION_MATCHTOLLVM_PASSES_TD
#define MATCH_CONVERSION_MATCHTOLLVM_PASSES_TD

include "mlir/Pass/PassBase.td"

def MatchToLLVMPass : Pass<"match-to-llvm", "func::FuncOp"> {
  let summary = "Converts deconstruct, pair and option constructs to the LLVM dialect.";
  let constructor = "mlir::match::createMatchToLLVMPass()";
  let dependentDialects = ["llvm::LLVMDialect"];
}

#endif // MATCH_CONVERSION_MATCHTOLLVM_PASSES_TD
