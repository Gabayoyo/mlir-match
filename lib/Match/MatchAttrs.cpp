#include "Match/MatchAttrs.h"

#include "llvm/ADT/STLExtras.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/DialectImplementation.h"

namespace mlir {
namespace match {

// Structural kinds are closed: no sub-patterns, and only "literal" carries a
// payload, which is mandatory for it. Other kinds are constructor patterns.
LogicalResult PatternAttr::verify(function_ref<InFlightDiagnostic()> emitError,
                                  StringRef kind, IntegerAttr payload,
                                  ArrayRef<PatternAttr> subpatterns) {
  bool isStructural =
      kind == "bind" || kind == "wildcard" || kind == "literal";
  if (isStructural && !subpatterns.empty())
    return emitError() << "a '" << kind
                       << "' pattern cannot have sub-patterns";
  if (payload && kind != "literal")
    return emitError() << "only a 'literal' pattern can carry a payload";
  if (kind == "literal" && !payload)
    return emitError() << "a 'literal' pattern must carry a payload";
  return success();
}

// Custom assembly for PatternAttr, since the generated form cannot parse a
// StringRef / self-referential parameter list. Grammar (after the
// `#match.pattern` mnemonic):
//
//   `<` kind (`,` attribute)? (`(` pattern (`,` pattern)* `)`)? `>`
//
// The optional attribute is the "literal" payload (e.g. `3 : i32`).
Attribute PatternAttr::parse(AsmParser &odsParser, Type odsType) {
  Builder builder(odsParser.getContext());
  SMLoc loc = odsParser.getCurrentLocation();

  if (odsParser.parseLess())
    return {};

  // `kind` is a free-form tag, written as a keyword or quoted string. The
  // StringRef stored in the attribute must outlive the parse, so intern it in
  // the context.
  std::string kindStr;
  if (odsParser.parseKeywordOrString(&kindStr))
    return {};
  StringRef kind = builder.getStringAttr(kindStr).getValue();

  // Optional payload: the constant a "literal" pattern matches.
  IntegerAttr payload;
  if (succeeded(odsParser.parseOptionalComma())) {
    Attribute attr;
    if (odsParser.parseAttribute(attr))
      return {};
    payload = dyn_cast<IntegerAttr>(attr);
    if (!payload) {
      odsParser.emitError(loc, "expected an integer attribute payload");
      return {};
    }
  }

  // Optional parenthesised, comma-separated sub-patterns.
  SmallVector<PatternAttr> subpatterns;
  if (succeeded(odsParser.parseOptionalLParen())) {
    do {
      Attribute attr;
      if (odsParser.parseAttribute(attr))
        return {};
      if (auto sub = dyn_cast<PatternAttr>(attr)) {
        subpatterns.push_back(sub);
      } else {
        odsParser.emitError(odsParser.getCurrentLocation(),
                            "expected a match.pattern sub-pattern");
        return {};
      }
    } while (succeeded(odsParser.parseOptionalComma()));
    if (odsParser.parseRParen())
      return {};
  }

  if (odsParser.parseGreater())
    return {};

  // Validate before constructing, so malformed patterns fail at parse time.
  auto emitError = [&]() { return odsParser.emitError(loc); };
  if (failed(PatternAttr::verify(emitError, kind, payload, subpatterns)))
    return {};

  return PatternAttr::get(odsParser.getContext(), kind, payload, subpatterns);
}

void PatternAttr::print(AsmPrinter &odsPrinter) const {
  odsPrinter << '<' << '"' << getKind() << '"';
  if (IntegerAttr payload = getPayload()) {
    odsPrinter << ", ";
    odsPrinter.printAttribute(payload);
  }
  if (!getSubpatterns().empty()) {
    odsPrinter << " (";
    llvm::interleaveComma(
        getSubpatterns(), odsPrinter,
        [&](PatternAttr sub) { odsPrinter.printAttribute(sub); });
    odsPrinter << ')';
  }
  odsPrinter << '>';
}

} // namespace match
} // namespace mlir
