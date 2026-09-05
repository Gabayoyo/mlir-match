// RUN: %matchopt -match-to-decision-tree %s | %FileCheck %s

// Guarded rows: the arm fires only when its pattern matches AND its guard
// passes; a failed guard falls through to the remaining rows (or default).
module {
  func.func @guarded(%v: !match.option<i32>) -> i32 {
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

  // A trailing bind row must still fire when the guard fails and when the
  // pattern never matched.
  func.func @guard_fallback(%v: !match.option<i32>) -> i32 {
    %c0 = arith.constant 0 : i32
    %c1 = arith.constant 1 : i32
    %c2 = arith.constant 2 : i32
    %c10 = arith.constant 10 : i32
    %r = match.match {patterns = [#match.pattern<"some"(#match.pattern<"bind">)>, #match.pattern<"bind">]} %v : !match.option<i32> -> i32
      case (%x: i32) {
        %big = arith.cmpi sgt, %x, %c10 : i32
        match.guard %big
        match.yield %c1 : i32
      }
      case (%w: !match.option<i32>) {
        match.yield %c2 : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %r : i32
  }
}

// CHECK: func.func @guarded
// CHECK-NOT: match.match
// CHECK: %[[M:.*]], %[[F:.*]] = match.deconstruct %arg0, "some" : !match.option<i32> -> (i1, i32)
// CHECK: %[[IF0:.*]] = scf.if %[[M]] -> (i32) {
// The guard compares the binding; the body yields it when the guard passes.
// CHECK: %[[GT:.*]] = arith.cmpi sgt, %[[F]], %c10_i32 : i32
// CHECK: %[[IF1:.*]] = scf.if %[[GT]] -> (i32) {
// CHECK: scf.yield %[[F]] : i32
// CHECK: } else {
// Guard failed -> default.
// CHECK: scf.yield %c0_i32 : i32
// CHECK: } else {
// Not some -> default.
// CHECK: scf.yield %c0_i32 : i32
// CHECK: return %[[IF0]] : i32

// CHECK: func.func @guard_fallback
// CHECK-NOT: match.match
// CHECK: %[[M2:.*]], %[[F2:.*]] = match.deconstruct %arg0, "some" : !match.option<i32> -> (i1, i32)
// CHECK: %[[IF2:.*]] = scf.if %[[M2]] -> (i32) {
// Guard fails on a small payload -> the bind arm fires, not the default.
// CHECK: %[[GT2:.*]] = arith.cmpi sgt, %[[F2]], %c10_i32 : i32
// CHECK: %[[IF3:.*]] = scf.if %[[GT2]] -> (i32) {
// CHECK: scf.yield %c1_i32 : i32
// CHECK: } else {
// CHECK: scf.yield %c2_i32 : i32
// CHECK: } else {
// Not some -> the bind arm fires.
// CHECK: scf.yield %c2_i32 : i32
// CHECK: return %[[IF2]] : i32
