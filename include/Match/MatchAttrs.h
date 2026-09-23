#ifndef MATCH_MATCHATTRS_H
#define MATCH_MATCHATTRS_H

#include "mlir/IR/Attributes.h"
#include "mlir/IR/BuiltinAttributes.h"

// Bring the generated attribute classes (e.g. mlir::match::PatternAttr) into
// scope. The definitions live in MatchAttrs.cpp.inc.
#define GET_ATTRDEF_CLASSES
#include "Match/MatchAttrs.h.inc"

namespace mlir {
namespace match {

// The shapes a pattern can take. Everything that is not structural names a
// constructor of the scrutinee's type, so the kind is not a closed set.
enum class PatternKind { Bind, Wildcard, Literal, Constructor };

// Kind of `pattern`, mapping a constructor name to `Constructor`.
PatternKind getPatternKind(PatternAttr pattern);

// True when `pattern` matches every value of its type, so testing for it
// decides nothing.
bool isIrrefutable(PatternAttr pattern);

} // namespace match
} // namespace mlir

#endif // MATCH_MATCHATTRS_H
