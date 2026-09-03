#include "Match/MatchTypes.h"
#include <utility>

namespace mlir {
namespace match {

// each tagged type lists the constructors that can build its values, with their field types
SmallVector<ConstructorDescriptor> getConstructors(Type type) {
  SmallVector<ConstructorDescriptor> constructors;
  if (auto option = dyn_cast<OptionType>(type)) {
    constructors.push_back({"some", {option.getPayload()}});
    constructors.push_back({"none", {}});
  }
  if (auto pair = dyn_cast<PairType>(type)) {
    constructors.push_back({"pair", {pair.getFirst(), pair.getSecond()}});
  }
  return constructors;
}

// look up a constructor by name for a given type, returning its descriptor if found
std::optional<ConstructorDescriptor> lookupConstructor(Type type,
                                                       StringRef name) {
  for (const ConstructorDescriptor &constructor : getConstructors(type))
    if (constructor.name == name)
      return constructor;
  return std::nullopt;
}

} // namespace match
} // namespace mlir
