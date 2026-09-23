#ifndef MATCH_CONVERSION_MATCHTODECISIONTREE_PASSES_TD
#define MATCH_CONVERSION_MATCHTODECISIONTREE_PASSES_TD

include "mlir/Pass/PassBase.td"

def MatchToDecisionTreePass : Pass<"match-to-decision-tree", "func::FuncOp"> {
  let summary = "Lower pattern rows via a Maranget-style decision tree of scf control flow.";
  let constructor = "mlir::match::createMatchToDecisionTreePass()";
  let dependentDialects = ["scf::SCFDialect", "arith::ArithDialect"];

  let options = [
    Option<"columnChoice", "column-choice", "::mlir::match::ColumnChoice",
           /*default=*/"::mlir::match::ColumnChoice::Leftmost",
           "Which column a test questions first",
           [{::llvm::cl::values(
             clEnumValN(::mlir::match::ColumnChoice::Leftmost, "leftmost",
                        "question columns in source order"),
             clEnumValN(::mlir::match::ColumnChoice::Mixture, "mixture",
                        "question the column that copies the fewest rows")
           )}]>,
  ];
}

#endif // MATCH_CONVERSION_MATCHTODECISIONTREE_PASSES_TD
