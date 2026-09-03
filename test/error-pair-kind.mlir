// RUN: %not %matchopt %s 2>&1 | %FileCheck %s

// Constructors belong to the scrutinee type's table: "pair" is declared by
// !match.pair<...>, not by !match.option<i32>, so matching an option value
// with a pair pattern is rejected.
module {
  func.func @pair_on_option(%v: !match.option<i32>) -> i32 {
    %c0 = arith.constant 0 : i32

    %result = match.match {patterns = [#match.pattern<"pair"(#match.pattern<"bind">, #match.pattern<"bind">)>]} %v : !match.option<i32> -> i32
      case (%a: i32, %b: i32) {
        match.yield %a : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %result : i32
  }
}

// CHECK: error: 'match.match' op pattern kind 'pair' is not a constructor of '!match.option<i32>'
