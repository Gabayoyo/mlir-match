#include "Match/MatchAttrs.h"

#include "llvm/ADT/STLExtras.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/DialectImplementation.h"

namespace mlir {
namespace match {

// Custom assembly for PatternAttr, since the generated form cannot parse a
// StringRef / self-referential parameter list. Grammar (after the
// `#match.pattern` mnemonic):
//
//   `<` kind (`(` pattern (`,` pattern)* `)`)? `>`
//
Attribute PatternAttr::parse(AsmParser &odsParser, Type odsType) {
  Builder builder(odsParser.getContext());

  if (odsParser.parseLess())
    return {};

  // `kind` is a free-form tag, written as a keyword or quoted string. The
  // StringRef stored in the attribute must outlive the parse, so intern it in
  // the context.
  std::string kindStr;
  if (odsParser.parseKeywordOrString(&kindStr))
    return {};
  StringRef kind = builder.getStringAttr(kindStr).getValue();

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

  return PatternAttr::get(odsParser.getContext(), kind, subpatterns);
}

void PatternAttr::print(AsmPrinter &odsPrinter) const {
  odsPrinter << '<' << '"' << getKind() << '"';
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
