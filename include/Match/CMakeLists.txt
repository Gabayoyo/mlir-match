# Tablegen lives beside the .td files, mirroring in-tree MLIR. The generated
# *.inc land in ${CMAKE_BINARY_DIR}/include/Match, which is why the headers can
# include them as "Match/MatchOps.h.inc" etc.
set(LLVM_TARGET_DEFINITIONS MatchOps.td)

mlir_tablegen(MatchOps.h.inc -gen-op-decls)
mlir_tablegen(MatchOps.cpp.inc -gen-op-defs)
mlir_tablegen(MatchOpsDialect.h.inc -gen-dialect-decls -dialect=match)
mlir_tablegen(MatchOpsDialect.cpp.inc -gen-dialect-defs -dialect=match)

add_public_tablegen_target(MatchOpsIncGen)
