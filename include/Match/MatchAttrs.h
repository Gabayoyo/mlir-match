#ifndef MATCH_MATCHATTRS_H
#define MATCH_MATCHATTRS_H

#include "mlir/IR/Attributes.h"

// Bring the generated attribute classes (e.g. mlir::match::PatternAttr) into
// scope. The definitions live in MatchAttrs.cpp.inc.
#define GET_ATTRDEF_CLASSES
#include "Match/MatchAttrs.h.inc"

#endif // MATCH_MATCHATTRS_H
