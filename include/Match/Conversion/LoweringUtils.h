#ifndef MATCH_CONVERSION_LOWERINGUTILS_H
#define MATCH_CONVERSION_LOWERINGUTILS_H

#include "Match/MatchOps.h"

#include "mlir/IR/Builders.h"

namespace mlir {
namespace match {

// Move `src`'s body ops into `dst` and terminate `dst` with an scf.yield,
// rewriting the arm's bindings (`src`'s entry arguments) onto `bindings`.
void emitBody(Block &src, Block &dst, OpBuilder &builder,
              ArrayRef<Value> bindings = {});

// Returns true if the arm region contains a guard op.
bool hasGuard(Region &arm);

} // namespace match
} // namespace mlir

#endif // MATCH_CONVERSION_LOWERINGUTILS_H
