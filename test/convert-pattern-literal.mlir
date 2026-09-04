// RUN: %matchopt -convert-match-to-scf %s | %FileCheck %s

// A top-level "literal" row over a scalar scrutinee needs no deconstruct:
// its condition is an equality test against the literal's payload.
module {
  func.func @is_one(%x: i32) -> i32 {
    %c0 = arith.constant 0 : i32
    %c1 = arith.constant 1 : i32
    %r = match.match {patterns = [#match.pattern<"literal", 1 : i32>]} %x : i32 -> i32
      case {
        match.yield %c1 : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %r : i32
  }
}

// CHECK: func.func @is_one
// CHECK-NOT: match.match
// CHECK: %[[EQ:.*]] = arith.cmpi eq, %arg0, %[[K:.*]] : i32
// CHECK: %[[IF:.*]] = scf.if %[[EQ]] -> (i32) {
// CHECK: scf.yield %c1_i32 : i32
// CHECK: } else {
// CHECK: scf.yield %c0_i32 : i32
// CHECK: return %[[IF]] : i32
