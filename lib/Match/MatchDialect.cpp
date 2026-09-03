#include "Match/MatchDialect.h"
#include "Match/MatchOps.h"

namespace mlir {

// every cpp needs the mlir and mlir::match namespaces
// since the dialect is in mlir::match namespace
namespace match {

void MatchDialect::initialize() {
  addOperations<MatchOp, YieldOp, GuardOp>();
}

} // namespace match

} // namespace mlir

// The generated op definitions are gated behind GET_OP_CLASSES (MatchOps.h
// undefines it after including the declarations), so re-define it first.
#define GET_OP_CLASSES
#include "Match/MatchOpsDialect.cpp.inc"  // defines MatchDialect::MatchDialect(MLIRContext*)
#include "Match/MatchOps.cpp.inc"         // defines generated op bodies (parse/print/adaptors)