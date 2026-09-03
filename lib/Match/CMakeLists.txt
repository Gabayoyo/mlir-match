add_mlir_dialect_library(MLIRMatch
  MatchDialect.cpp
  MatchOps.cpp
  Conversion/MatchToSCF/MatchToSCF.cpp

  ADDITIONAL_HEADER_DIRS
  ${PROJECT_SOURCE_DIR}/include/Match

  DEPENDS
  MatchOpsIncGen
  MatchToSCFIncGen

  LINK_LIBS PUBLIC
  MLIRIR
  MLIRPass
  MLIRFuncDialect
  MLIRSCFDialect
  MLIRSideEffectInterfaces
  MLIRControlFlowInterfaces
  MLIRInferTypeOpInterface
)
