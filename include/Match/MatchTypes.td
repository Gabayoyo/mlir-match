#ifndef MATCH_TYPES
#define MATCH_TYPES

include "MatchDialect.td"
include "mlir/IR/AttrTypeBase.td"

// A tagged option value, either `some` with some payload or `none`.
def Match_OptionType : TypeDef<Match_Dialect, "Option"> {
  let summary = "A tagged option value: either `some` or `none`.";
  let description = [{
    `!match.option<T>` is a sum type with two constructors: `some` carrying a
    single payload of type `T`, and `none` carrying nothing. Pattern matching
    on a scrutinee of this type tests which constructor built the value and,
    for `some`, extracts the payload to feed the arm's bindings.
  }];
  let mnemonic = "option";

  let parameters = (ins
      TypeParameter<"::mlir::Type", "payload type">:$payload);
  let assemblyFormat = "`<` $payload `>`";
}

def Match_PairType : TypeDef<Match_Dialect, "Pair"> {
  let summary = "A pair of two values.";
  let description = [{
    `!match.pair<T1, T2>` is a product type with two fields, the first of type `T1` 
    and the second of type `T2`. Pattern matching on a scrutinee of this type extracts 
    the two fields to feed the arm's bindings.
  }];
  let mnemonic = "pair";

  let parameters = (ins
      TypeParameter<"::mlir::Type", "first type">:$first,
      TypeParameter<"::mlir::Type", "second type">:$second);
  let assemblyFormat = "`<` $first `,` $second `>`";
}

#endif // MATCH_TYPES
