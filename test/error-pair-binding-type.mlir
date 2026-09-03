// RUN: %not %matchopt %s 2>&1 | %FileCheck %s

// The bindings a pair pattern declares must line up with the field types in
// the order the type declares them: first field is i32, second is i64.
// Swapping them in the case header is rejected.
module {
  func.func @swapped_fields(%v: !match.pair<i32, i64>) -> i64 {
    %c0 = arith.constant 0 : i64

    %result = match.match {patterns = [#match.pattern<"pair"(#match.pattern<"bind">, #match.pattern<"bind">)>]} %v : !match.pair<i32, i64> -> i64
      case (%left: i64, %right: i32) {
        match.yield %c0 : i64
      }
      default {
        match.yield %c0 : i64
      }
    return %result : i64
  }
}

// CHECK: error: 'match.match' op arm 0 binding 0 has type 'i64' but its pattern binds a value of type 'i32'
