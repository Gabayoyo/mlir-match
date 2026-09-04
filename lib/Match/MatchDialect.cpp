#include "Match/MatchDialect.h"
#include "Match/MatchAttrs.h"
#include "Match/MatchOps.h"
#include "Match/MatchTypes.h"

#include "mlir/IR/DialectImplementation.h"

namespace mlir {

// every cpp needs the mlir and mlir::match namespaces
// since the dialect is in mlir::match namespace
namespace match {

void MatchDialect::initialize() {
  addOperations<MatchOp, YieldOp, GuardOp, DeconstructOp>();
  addAttributes<PatternAttr>();
  addTypes<OptionType, PairType>();
}

} // namespace match

} // namespace mlir

#define GET_ATTRDEF_CLASSES
#include "Match/MatchAttrs.cpp.inc"       // attribute storage/accessors/TypeID

#define GET_TYPEDEF_CLASSES
#include "Match/MatchTypes.cpp.inc"       // type storage/accessors/TypeID

#define GET_OP_CLASSES
#include "Match/MatchOpsDialect.cpp.inc"  // defines MatchDialect::MatchDialect(MLIRContext*)
#include "Match/MatchOps.cpp.inc"         // defines generated op bodies (parse/print/adaptors)