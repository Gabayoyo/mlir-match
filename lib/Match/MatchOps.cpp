#include "Match/MatchOps.h"
#include "Match/MatchAttrs.h"
#include "Match/MatchTypes.h"

namespace mlir {
namespace match {
namespace {

// match.yield must carry as many values as the match op has results
// and the types must match
LogicalResult checkYield(MatchOp match, Region &region) {
  auto yield = dyn_cast<YieldOp>(region.front().getTerminator());
  if (!yield)
    return match.emitOpError("region must terminate with a match.yield");
  if (yield.getNumOperands() != match.getNumResults())
    return match.emitOpError(
        "match.yield must carry as many values as the match op has results");
  for (unsigned i = 0, e = match.getNumResults(); i != e; ++i) {
    if (yield.getOperand(i).getType() != match.getResult(i).getType())
      return match.emitOpError(
          "match.yield result types must match the match op result types");
  }
  return success();
}

// Recursively check that a pattern matches the expected type
LogicalResult checkPattern(MatchOp match, PatternAttr pattern, Type expectedType,
                           SmallVectorImpl<Type> &bindings) {
  StringRef kind = pattern.getKind();
  if (kind == "bind") {
    bindings.push_back(expectedType);
    return success();
  }
  if (kind == "wildcard")
    return success();
  if (kind == "literal") {
    IntegerAttr payload = pattern.getPayload();
    if (payload && payload.getType() != expectedType)
      return match.emitOpError("literal pattern payload type ")
             << payload.getType()
             << " does not match the expected type " << expectedType;
    return success();
  }

  // constructor pattern, taken from the dialect's constructor table
  std::optional<ConstructorDescriptor> constructor =
      lookupConstructor(expectedType, kind);
  if (!constructor)
    return match.emitOpError("pattern kind '")
           << kind << "' is not a constructor of " << expectedType;
  ArrayRef<PatternAttr> subpatterns = pattern.getSubpatterns();
  if (subpatterns.size() != constructor->fieldTypes.size())
    return match.emitOpError("constructor '")
           << kind << "' expects " << constructor->fieldTypes.size()
           << " sub-pattern(s) but has " << subpatterns.size();
  for (auto [subpattern, fieldType] :
       llvm::zip(subpatterns, constructor->fieldTypes))
    if (failed(checkPattern(match, subpattern, fieldType, bindings)))
      return failure();
  return success();
}

} // namespace

LogicalResult MatchOp::verify() {
    auto patterns = getPatterns();
    // An empty pattern list counts as "no patterns", so skip the count check.
    if (patterns && patterns->size() != 0 && patterns->size() != getArms().size())
        return emitOpError("the number of patterns must match the number of arms");

    // default case should not contain guard
    for (Operation &op : getOtherwise().front()) {
        if (isa<GuardOp>(op))
            return emitOpError("the default region may not contain a match.guard");
    }

    // each arm may contain at most one guard
    for (Region &arm : getArms()) {
        bool hasGuard = false;
        for (Operation &op : arm.front()) {
            if (isa<GuardOp>(op)) {
                if (hasGuard)
                    return emitOpError("an arm may contain at most one match.guard");
                hasGuard = true;
            }
        }
    }

    // Check each arm's pattern against the scrutinee type, and check that the arm's
    // block arguments match the types of the values bound by the pattern.
    if (patterns) {
        
        // loop through all patterns and check them against the scrutinee type
        Type scrutineeType = getScrutinee().getType();
        for (auto [index, patternValue] : llvm::enumerate(*patterns)) {
            auto pattern = cast<PatternAttr>(patternValue);
            SmallVector<Type> bindingTypes;

            // recursively check the pattern against the corresponding scrutinee type
            if (failed(checkPattern(*this, pattern, scrutineeType, bindingTypes)))
            return failure();

            // check that the number of bindings matches the number of block arguments in the arm
            Block &armBlock = getArms()[index].front();
            if (bindingTypes.size() != armBlock.getNumArguments())
                return emitOpError("arm ")
                    << index << " expects " << bindingTypes.size()
                    << " binding(s) but has " << armBlock.getNumArguments()
                    << " block argument(s)";
            for (auto [i, arg] : llvm::enumerate(armBlock.getArguments())) {
                if (arg.getType() != bindingTypes[i])
                    return emitOpError("arm ")
                    << index << " binding " << i << " has type "
                    << arg.getType() << " but its pattern binds a value of type "
                    << bindingTypes[i];
            }
        }
    }

    // check default case's yield
    if (failed(checkYield(*this, getOtherwise())))
        return failure();
    
    // check each arm's yield
    for (Region &arm : getArms())
        if (failed(checkYield(*this, arm)))
            return failure();

    return success();
}

// We define getSuccessorRegions here since RegionBranchOpInterface has no default implementation
// Needed for CFG analysis, and to satisfy the RegionBranchOpInterface trait.
void MatchOp::getSuccessorRegions(
    ::mlir::RegionBranchPoint point,
    ::llvm::SmallVectorImpl<::mlir::RegionSuccessor> &regions) {
        
    // if the point is the parent op, we have multiple successors:
    // default case and every possible arm
    if (point.isParent()) {
        regions.push_back(::mlir::RegionSuccessor(&getOtherwise()));
        for (auto &arm : getArms())
            regions.push_back(::mlir::RegionSuccessor(&arm));
    } else {
        // else, the point is an arm, so the single successor is the parent op
        regions.push_back(::mlir::RegionSuccessor(getOperation()));
    }
}

// When a region's match.yield exits to this op, its operands become the op's
// results; the arm and default regions take no block arguments.
::mlir::ValueRange MatchOp::getSuccessorInputs(::mlir::RegionSuccessor successor) {
  if (successor.isOperation())
    return getResults();
  return {};
}

// Syntax:
//   match.match [attr-dict] %scrutinee : type [-> results]
//       (case [(%name : type, ...)] { .. })*
//       default { .. }
// The optional `(%name : type, ...)` list after a `case` declares the arm's
// bindings: one typed entry per value the arm's pattern binds, in the order
// `countBindings` walks. The list becomes the arm region's entry block
// arguments, so the body can refer to the bound values by name. Cases are
// printed before the default, but the default is stored as region 0.
ParseResult MatchOp::parse(OpAsmParser &parser, OperationState &result) {
  if (parser.parseOptionalAttrDict(result.attributes))
    return failure();

  OpAsmParser::UnresolvedOperand scrutinee;
  Type scrutineeType;
  if (parser.parseOperand(scrutinee) || parser.parseColonType(scrutineeType))
    return failure();

  SmallVector<Type> resultTypes;
  if (parser.parseOptionalArrowTypeList(resultTypes))
    return failure();
  result.addTypes(resultTypes);

  if (parser.resolveOperand(scrutinee, scrutineeType, result.operands))
    return failure();

  SmallVector<std::unique_ptr<Region>> cases;
  while (succeeded(parser.parseOptionalKeyword("case"))) {
    SmallVector<OpAsmParser::Argument> bindings;
    if (succeeded(parser.parseOptionalLParen())) {
      if (parser.parseArgumentList(bindings, OpAsmParser::Delimiter::None,
                                   /*allowType=*/true) ||
          parser.parseRParen())
        return failure();
    }

    // The first block of the region takes the declared bindings as its
    // arguments, so uses of the names inside the braces resolve to them.
    auto region = std::make_unique<Region>();
    if (parser.parseRegion(*region, bindings))
      return failure();
    cases.push_back(std::move(region));
  }

  auto defaultRegion = std::make_unique<Region>();
  if (parser.parseKeyword("default") || parser.parseRegion(*defaultRegion))
    return failure();

  // Default goes first so it lands in region 0; cases follow.
  result.addRegion(std::move(defaultRegion));
  for (auto &region : cases)
    result.addRegion(std::move(region));
  return success();
}

void MatchOp::print(OpAsmPrinter &p) {
  // printOptionalAttrDict emits a leading space itself when non-empty.
  p.printOptionalAttrDict((*this)->getAttrs());
  p << ' ';
  p << getScrutinee() << " : " << getScrutinee().getType();
  if (!getResults().empty())
    p << " -> " << getResultTypes();

  for (Region &arm : getArms()) {
    p.printNewline();
    p << "case";
    // Print the arm's bindings (its entry block arguments) in the case
    // header, so the syntax stays `case (%name : type, ...) {` rather than
    // exposing a raw ^bb0 block header.
    if (!arm.empty() && !arm.front().getArguments().empty()) {
      p << " (";
      llvm::interleaveComma(
          arm.front().getArguments(), p,
          [&](BlockArgument arg) { p.printRegionArgument(arg); });
      p << ')';
    }
    p << ' ';
    // The bindings were printed above, so don't repeat them here.
    p.printRegion(arm, /*printEntryBlockArgs=*/false);
  }
  p.printNewline();
  p << "default ";
  p.printRegion(getOtherwise());
}

} // namespace match
} // namespace mlir
