#include "Match/MatchDialect.h"
#include "Match/MatchOps.h"

using namespace mlir;

// every cpp needs the mlir and mlir::match namespaces
// since the dialect is in mlir::match namespace
namespace mlir::match {

void MatchDialect::initialize() {
  addOperations<MatchOp, YieldOp, CondYieldOp>();
}

} // namespace mlir::match

#include "Match/MatchOpsDialect.cpp.inc"  // defines MatchDialect::MatchDialect(MLIRContext*)
#include "Match/MatchOps.cpp.inc"         // defines generated op bodies (parse/print/adaptors)