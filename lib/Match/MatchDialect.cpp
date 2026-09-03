#include "Match/MatchDialect.h"
#include "Match/MatchAttrs.h"
#include "Match/MatchOps.h"

#include "mlir/IR/DialectImplementation.h"

namespace mlir {

// every cpp needs the mlir and mlir::match namespaces
// since the dialect is in mlir::match namespace
namespace match {

void MatchDialect::initialize() {
  addOperations<MatchOp, YieldOp, GuardOp>();
  addAttributes<PatternAttr>();
}

} // namespace match

} // namespace mlir

// The generated op definitions are gated behind GET_OP_CLASSES (MatchOps.h
// undefines it after including the declarations), so re-define it first. The
// attribute-generated parse/print helpers must come first, since the dialect's
// default attribute dispatch (below) references them.
#define GET_ATTRDEF_CLASSES
#include "Match/MatchAttrs.cpp.inc"       // attribute storage/accessors/TypeID

#define GET_OP_CLASSES
#include "Match/MatchOpsDialect.cpp.inc"  // defines MatchDialect::MatchDialect(MLIRContext*)
#include "Match/MatchOps.cpp.inc"         // defines generated op bodies (parse/print/adaptors)