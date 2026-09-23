#include "Match/MatchOps.h"
#include "Match/MatchAttrs.h"
#include "Match/MatchTypes.h"
#include <string>

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

// Recursively check that a pattern matches the expected type, appending the
// type each bind captures to `bindings` in depth-first order
LogicalResult checkPattern(MatchOp match, PatternAttr pattern,
                           Type expectedType, SmallVectorImpl<Type> &bindings) {
  switch (getPatternKind(pattern)) {
    case PatternKind::Bind:
      bindings.push_back(expectedType);
      return success();
    case PatternKind::Wildcard:
      return success();
    case PatternKind::Literal: {
      IntegerAttr payload = pattern.getPayload();
      if (payload && payload.getType() != expectedType)
        return match.emitOpError("literal pattern payload type ")
              << payload.getType() << " does not match the expected type "
              << expectedType;
      return success();
    }
    case PatternKind::Constructor:
      break;
  }

  // A constructor pattern is checked against the dialect's constructor table
  StringRef kind = pattern.getKind();
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

    // check if any pattern failed, and fail if so
  for (auto [subpattern, fieldType] :
       llvm::zip(subpatterns, constructor->fieldTypes)) {
    if (failed(checkPattern(match, subpattern, fieldType, bindings)))
      return failure();
    }
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

  // Check each arm's pattern against the scrutinee type, and check that the
  // arm's block arguments match the types of the values bound by the pattern.
  if (patterns) {

    // loop through all patterns and check them against the scrutinee type
    Type scrutineeType = getScrutinee().getType();
    for (auto [index, patternValue] : llvm::enumerate(*patterns)) {
      auto pattern = cast<PatternAttr>(patternValue);
      SmallVector<Type> bindingTypes;

      // recursively check the pattern against the corresponding scrutinee type
      if (failed(checkPattern(*this, pattern, scrutineeType, bindingTypes)))
        return failure();

      // check that the number of bindings matches the number of block arguments
      // in the arm
      Block &armBlock = getArms()[index].front();
      if (bindingTypes.size() != armBlock.getNumArguments())
        return emitOpError("arm ")
               << index << " expects " << bindingTypes.size()
               << " binding(s) but has " << armBlock.getNumArguments()
               << " block argument(s)";
      for (auto [i, arg] : llvm::enumerate(armBlock.getArguments())) {
        if (arg.getType() != bindingTypes[i])
          return emitOpError("arm ")
                 << index << " binding " << i << " has type " << arg.getType()
                 << " but its pattern binds a value of type "
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

// RegionBranchOpInterface has no default implementation, so the successors are
// spelled out here for CFG analysis.
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
::mlir::ValueRange
MatchOp::getSuccessorInputs(::mlir::RegionSuccessor successor) {
  if (successor.isOperation())
    return getResults();
  return {};
}

// Parses `match.match [attr-dict] %scrutinee : type [-> results]`, followed by
// `case` regions that may declare bindings, then a `default` region.
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
    // The bindings print in the case header, not as a raw block header.
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

LogicalResult DeconstructOp::verify() {
  Type OperandType = getValue().getType();
  StringRef ConstructorName = getConstructor();
  auto results = getResults();

  auto constructor = lookupConstructor(OperandType, ConstructorName);

  // check if the constructor exists on the value's type
  if (!constructor) {
    return emitOpError("constructor '")
           << ConstructorName << "' does not exist on type " << OperandType;
  } else {
    // A constructor with N fields yields the match flag plus N results.
    if (results.size() != constructor->fieldTypes.size() + 1) {
      return emitOpError("number of results (")
             << getNumResults() << ") does not match the number of fields ("
             << constructor->fieldTypes.size() << ") for constructor '"
             << ConstructorName << "' on type " << OperandType;
    }

    // first result must be I1
    if (results[0].getType() != IntegerType::get(getContext(), 1)) {
      return emitOpError("first result must be of type i1 (matched flag)");
    }

    // each subsequent result must match the corresponding field type in the
    // constructor
    for (unsigned i = 0; i < constructor->fieldTypes.size(); ++i) {
      if (results[i + 1].getType() != constructor->fieldTypes[i]) {
        return emitOpError("result ")
               << (i + 1) << " type (" << results[i + 1].getType()
               << ") does not match the expected field type ("
               << constructor->fieldTypes[i] << ") for constructor '"
               << ConstructorName << "' on type " << OperandType;
      }
    }
  }

  return success();
}

ParseResult DeconstructOp::parse(OpAsmParser &parser, OperationState &result) {
  if (parser.parseOptionalAttrDict(result.attributes))
    return failure();

  OpAsmParser::UnresolvedOperand value;
  if (parser.parseOperand(value) || parser.parseComma())
    return failure();

  // Parse the constructor as a token so a following `: type` is not consumed
  // with it as an attribute's type suffix.
  std::string constructorName;
  if (parser.parseKeywordOrString(&constructorName))
    return failure();

  Type valueType;
  if (parser.parseColonType(valueType))
    return failure();

  SmallVector<Type> resultTypes;
  if (parser.parseOptionalArrowTypeList(resultTypes))
    return failure();
  result.addTypes(resultTypes);

  if (parser.resolveOperand(value, valueType, result.operands))
    return failure();
  result.addAttribute("constructor",
                      parser.getBuilder().getStringAttr(constructorName));
  return success();
}

void DeconstructOp::print(OpAsmPrinter &p) {
  p.printOptionalAttrDict((*this)->getAttrs(), /*elidedAttrs=*/{"constructor"});
  p << ' ' << getValue() << ", \"" << getConstructor()
    << "\" : " << getValue().getType();
  if (!getResults().empty())
    p << " -> (" << getResultTypes() << ')';
}

} // namespace match
} // namespace mlir
