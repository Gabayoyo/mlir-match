add_mlir_dialect_library(MLIRMatch
  MatchDialect.cpp
  MatchOps.cpp

  ADDITIONAL_HEADER_DIRS
  ${PROJECT_SOURCE_DIR}/include/Match

  DEPENDS
  MatchOpsIncGen

  LINK_LIBS PUBLIC
  MLIRIR
  MLIRSideEffectInterfaces
  MLIRControlFlowInterfaces
  MLIRInferTypeOpInterface
)
