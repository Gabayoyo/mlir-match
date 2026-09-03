# Tablegen lives beside the .td files, mirroring in-tree MLIR. The generated
# *.inc land in ${CMAKE_BINARY_DIR}/include/Match, which is why the headers can
# include them as "Match/MatchOps.h.inc" etc.
set(LLVM_TARGET_DEFINITIONS MatchOps.td)

mlir_tablegen(MatchOps.h.inc -gen-op-decls)
mlir_tablegen(MatchOps.cpp.inc -gen-op-defs)
mlir_tablegen(MatchOpsDialect.h.inc -gen-dialect-decls -dialect=match)
mlir_tablegen(MatchOpsDialect.cpp.inc -gen-dialect-defs -dialect=match)

add_public_tablegen_target(MatchOpsIncGen)

# Match attributes (e.g. PatternAttr).
set(LLVM_TARGET_DEFINITIONS MatchAttrs.td)

mlir_tablegen(MatchAttrs.h.inc -gen-attrdef-decls)
mlir_tablegen(MatchAttrs.cpp.inc -gen-attrdef-defs)

add_public_tablegen_target(MatchAttrsIncGen)

# Match types (e.g. !match.option).
set(LLVM_TARGET_DEFINITIONS MatchTypes.td)

mlir_tablegen(MatchTypes.h.inc -gen-typedef-decls)
mlir_tablegen(MatchTypes.cpp.inc -gen-typedef-defs)

add_public_tablegen_target(MatchTypesIncGen)
