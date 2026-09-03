#ifndef MATCH_CONVERSION_MATCHTOSCF_PASSES_TD
#define MATCH_CONVERSION_MATCHTOSCF_PASSES_TD

include "mlir/Pass/PassBase.td"

def MatchToSCFPass : Pass<"convert-match-to-scf", "func::FuncOp"> {
  let summary = "Convert match.match into scf control flow.";
  let constructor = "mlir::match::createMatchToSCFPass()";
  let dependentDialects = ["scf::SCFDialect"];
}

#endif // MATCH_CONVERSION_MATCHTOSCF_PASSES_TD
