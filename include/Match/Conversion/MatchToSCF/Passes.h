#ifndef MATCH_CONVERSION_MATCHTOSCF_PASSES_H
#define MATCH_CONVERSION_MATCHTOSCF_PASSES_H

#include "mlir/Pass/Pass.h"

namespace mlir {
namespace match {

#define GEN_PASS_DECL
#include "Match/Conversion/MatchToSCF/Passes.h.inc"

std::unique_ptr<Pass> createMatchToSCFPass();

} // namespace match

#define GEN_PASS_REGISTRATION
#include "Match/Conversion/MatchToSCF/Passes.h.inc"

} // namespace mlir

#endif // MATCH_CONVERSION_MATCHTOSCF_PASSES_H
