// RUN: %matchopt -convert-match-to-scf %s | %FileCheck %s

// A pattern arm may also carry a match.guard. The guard's condition can use
// the binding: it must be hoisted after the binding is materialised, and the
// arm fires only when the pattern matches AND the guard passes.
module {
  func.func @some_big(%v: !match.option<i32>) -> i32 {
    %c0 = arith.constant 0 : i32
    %c10 = arith.constant 10 : i32
    %r = match.match {patterns = [#match.pattern<"some"(#match.pattern<"bind">)>]} %v : !match.option<i32> -> i32
      case (%x: i32) {
        %big = arith.cmpi sgt, %x, %c10 : i32
        match.guard %big
        match.yield %x : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %r : i32
  }
}

// CHECK: func.func @some_big
// CHECK-NOT: match.match
// CHECK: %[[M:.*]], %[[F:.*]] = match.deconstruct %arg0, "some" : !match.option<i32> -> (i1, i32)
// CHECK: %[[P:.*]] = arith.andi %[[M]], %true : i1
// CHECK: %[[GT:.*]] = arith.cmpi sgt, %[[F]], %c10_i32 : i32
// CHECK: %[[C:.*]] = arith.andi %[[P]], %[[GT]] : i1
// CHECK: %[[IF:.*]] = scf.if %[[C]] -> (i32) {
// CHECK: scf.yield %[[F]] : i32
// CHECK: } else {
// CHECK: scf.yield %c0_i32 : i32
// CHECK: return %[[IF]] : i32
