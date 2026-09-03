#ifndef MATCH_ATTRS
#define MATCH_ATTRS

include "MatchDialect.td"
include "mlir/IR/AttrTypeBase.td"
include "mlir/IR/CommonAttrConstraints.td"

// A structured pattern describing the shape of a value an arm matches. A
// pattern is data (an MLIR attribute), not runtime code: it is what a
// decision-tree pass reads and reorders, and it defines the bindings an arm's
// body expects.
def Match_Pattern : AttrDef<Match_Dialect, "Pattern"> {
  let summary = "A pattern describing the shape of a value an arm matches.";
  let description = [{
    A `PatternAttr` describes the shape a scrutinee must have for an arm to
    apply, in the style of functional pattern matching. It carries a kind tag,
    an optional literal payload, and the sub-patterns that a constructor
    pattern deconstructs into.
  }];
  let mnemonic = "pattern";
  let hasCustomAssemblyFormat = 1;
  // Generates PatternAttr::verify plus getChecked, so structural kinds and the
  // literal payload can be validated when the attribute is built.
  let genVerifyDecl = 1;

  // kind is "wildcard", "bind", "literal", or a constructor name
  // payload is the constant a "literal" pattern matches
  // sub-patterns are the patterns that a constructor pattern deconstructs into
  let parameters = (ins
      "StringRef":$kind,
      OptionalParameter<"::mlir::IntegerAttr", "payload">:$payload,
      OptionalArrayRefParameter<"::mlir::match::PatternAttr",
                               "sub-patterns">:$subpatterns);
}

// An array of patterns, index-aligned one-per-arm with the match op's arms.
def Match_PatternList : TypedArrayAttrBase<Match_Pattern,
                                           "array of match patterns">;

#endif // MATCH_ATTRS
