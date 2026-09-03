#ifndef MATCH_MATCHTYPES_H
#define MATCH_MATCHTYPES_H

#include "mlir/IR/Types.h"

#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"

#include <optional>

// Bring the generated type classes (e.g. mlir::match::OptionType) into scope.
// The definitions live in MatchTypes.cpp.inc.
#define GET_TYPEDEF_CLASSES
#include "Match/MatchTypes.h.inc"

namespace mlir {
namespace match {

// Describes one constructor of a tagged match type: its name and the types of
// the fields a pattern deconstructs into.
struct ConstructorDescriptor {
  StringRef name;
  SmallVector<Type> fieldTypes;
};

// All constructors of `type`. Non-tagged types (plain scalars, ...) have no
// constructors, so the result is empty.
SmallVector<ConstructorDescriptor> getConstructors(Type type);

// Returns the constructor of `type` named `name`, or std::nullopt when `type`
// does not declare one (including when `type` is not a tagged match type at
// all).
std::optional<ConstructorDescriptor> lookupConstructor(Type type,
                                                       StringRef name);

} // namespace match
} // namespace mlir

#endif // MATCH_MATCHTYPES_H
