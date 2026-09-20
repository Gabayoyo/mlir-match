add_mlir_dialect_library(MLIRMatch
  MatchDialect.cpp
  MatchOps.cpp
  MatchAttrs.cpp
  MatchTypes.cpp
  Conversion/LoweringUtils.cpp
  Conversion/MatchToSCF/MatchToSCF.cpp
  Conversion/MatchToDecisionTree/MatchToDecisionTree.cpp
  Conversion/MatchToLLVM/MatchToLLVM.cpp

  ADDITIONAL_HEADER_DIRS
  ${PROJECT_SOURCE_DIR}/include/Match

  DEPENDS
  MatchOpsIncGen
  MatchAttrsIncGen
  MatchTypesIncGen
  MatchToSCFIncGen
  MatchToDecisionTreeIncGen
  MatchToLLVMIncGen

  LINK_LIBS PUBLIC
  MLIRIR
  MLIRPass
  MLIRFuncDialect
  MLIRSCFDialect
  MLIRLLVMDialect
  MLIRSideEffectInterfaces
  MLIRControlFlowInterfaces
  MLIRInferTypeOpInterface
  MLIRLLVMCommonConversion
)
