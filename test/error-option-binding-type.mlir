// RUN: %not %matchopt %s 2>&1 | %FileCheck %s

// The binding types an arm declares in its case header must match the types
// derived from its pattern: "some" over !match.option<i32> binds an i32, so
// declaring the binding as i64 is rejected.
module {
  func.func @wrong_binding_type(%v: !match.option<i32>) -> i32 {
    %c0 = arith.constant 0 : i32

    %result = match.match {patterns = [#match.pattern<"some"(#match.pattern<"bind">)>]} %v : !match.option<i32> -> i32
      case (%x: i64) {
        match.yield %c0 : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %result : i32
  }
}

// CHECK: error: 'match.match' op arm 0 binding 0 has type 'i64' but its pattern binds a value of type 'i32'
