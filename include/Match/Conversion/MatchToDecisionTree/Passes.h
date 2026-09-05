#ifndef MATCH_CONVERSION_MATCHTODECISIONTREE_PASSES_H
#define MATCH_CONVERSION_MATCHTODECISIONTREE_PASSES_H

#include "mlir/Pass/Pass.h"

namespace mlir {
namespace match {

#define GEN_PASS_DECL
#include "Match/Conversion/MatchToDecisionTree/Passes.h.inc"

std::unique_ptr<Pass> createMatchToDecisionTreePass();

} // namespace match

#define GEN_PASS_REGISTRATION
#include "Match/Conversion/MatchToDecisionTree/Passes.h.inc"

} // namespace mlir

#endif // MATCH_CONVERSION_MATCHTODECISIONTREE_PASSES_H
