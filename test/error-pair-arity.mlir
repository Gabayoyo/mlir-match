// RUN: %not %matchopt %s 2>&1 | %FileCheck %s

// "pair" on !match.pair<i32, i64> deconstructs into exactly two fields, so a
// pair pattern must carry exactly two sub-patterns.
module {
  func.func @too_few_subs(%v: !match.pair<i32, i64>) -> i64 {
    %c0 = arith.constant 0 : i64

    %result = match.match {patterns = [#match.pattern<"pair"(#match.pattern<"bind">)>]} %v : !match.pair<i32, i64> -> i64
      case (%a: i32) {
        match.yield %c0 : i64
      }
      default {
        match.yield %c0 : i64
      }
    return %result : i64
  }
}

// CHECK: error: 'match.match' op constructor 'pair' expects 2 sub-pattern(s) but has 1
