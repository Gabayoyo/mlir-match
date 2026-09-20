set(LLVM_TARGET_DEFINITIONS ${CMAKE_CURRENT_SOURCE_DIR}/Passes.td)

mlir_tablegen(Passes.h.inc -gen-pass-decls -name MatchToLLVM)

add_public_tablegen_target(MatchToLLVMIncGen)
