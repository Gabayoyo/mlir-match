// RUN: %matchopt -convert-match-to-scf %s | %FileCheck %s

// A match with only a default has no guarded arms, so it never builds an
// scf.if: the default body is inlined in place of the match.
module {
  func.func @default_only(%x: i32) -> i32 {
    %c7 = arith.constant 7 : i32

    %result = match.match %x : i32 -> i32
      default {
        match.yield %c7 : i32
      }
    return %result : i32
  }
}

// CHECK: func.func @default_only
// CHECK-NOT: match.match
// CHECK-NOT: scf.if
// CHECK: %c7_i32 = arith.constant 7 : i32
// CHECK: return %c7_i32 : i32
