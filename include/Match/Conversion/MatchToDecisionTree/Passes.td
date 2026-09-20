#ifndef MATCH_CONVERSION_MATCHTODECISIONTREE_PASSES_TD
#define MATCH_CONVERSION_MATCHTODECISIONTREE_PASSES_TD

include "mlir/Pass/PassBase.td"

def MatchToDecisionTreePass : Pass<"match-to-decision-tree", "func::FuncOp"> {
  let summary = "Lower pattern rows via a Maranget-style decision tree of scf control flow.";
  let constructor = "mlir::match::createMatchToDecisionTreePass()";
  let dependentDialects = ["scf::SCFDialect", "arith::ArithDialect"];

  let options = [Option<"columnChoice", "column-choice", "std::string",
         "\"leftmost\"", "Column-choice heuristic: 'leftmost' or 'mixture'">];
}

#endif // MATCH_CONVERSION_MATCHTODECISIONTREE_PASSES_TD
