#ifndef MATCH_CONVERSION_LOWERINGUTILS_H
#define MATCH_CONVERSION_LOWERINGUTILS_H

#include "Match/MatchOps.h"

#include "mlir/IR/Builders.h"

namespace mlir {
namespace match {

// Clone `src`'s body ops into `dst`, terminated by an scf.yield, rewriting its
// bindings onto `bindings`; ops before a guard stay the caller's to hoist.
void emitBody(Block &src, Block &dst, OpBuilder &builder,
              ArrayRef<Value> bindings = {});

// Returns true if the arm region contains a guard op.
bool hasGuard(Region &arm);

} // namespace match
} // namespace mlir

#endif // MATCH_CONVERSION_LOWERINGUTILS_H
