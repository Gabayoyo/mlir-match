// RUN: %matchopt -convert-match-to-scf %s | %FileCheck %s

// Pattern rows now drive the lowering: "some(bind)" becomes a
// match.deconstruct tag test whose body receives the extracted payload, and
// "none" nests in the else. The match op itself disappears.
module {
  func.func @classify(%v: !match.option<i32>) -> i32 {
    %c0 = arith.constant 0 : i32
    %c7 = arith.constant 7 : i32
    %r = match.match {patterns = [
      #match.pattern<"some"(#match.pattern<"bind">)>,
      #match.pattern<"none">
    ]} %v : !match.option<i32> -> i32
      case (%x: i32) {
        match.yield %x : i32
      }
      case {
        match.yield %c7 : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %r : i32
  }

  // A top-level "bind" arm matches anything, so the whole match inlines away
  // and the arm body's binding is the scrutinee itself.
  func.func @bind_inline(%v: !match.option<i32>) -> !match.option<i32> {
    %r = match.match {patterns = [#match.pattern<"bind">]} %v : !match.option<i32> -> !match.option<i32>
      case (%w: !match.option<i32>) {
        match.yield %w : !match.option<i32>
      }
      default {
        match.yield %v : !match.option<i32>
      }
    return %r : !match.option<i32>
  }
}

// CHECK: func.func @classify
// CHECK-NOT: match.match
// CHECK: %[[M:.*]], %[[F:.*]] = match.deconstruct %arg0, "some" : !match.option<i32> -> (i1, i32)
// CHECK: %[[C:.*]] = arith.andi %[[M]], %true : i1
// CHECK: %[[IF:.*]] = scf.if %[[C]] -> (i32) {
// CHECK: scf.yield %[[F]] : i32
// CHECK: } else {
// CHECK: %[[M2:.*]] = match.deconstruct %arg0, "none" : !match.option<i32> -> (i1)
// CHECK: scf.if %[[M2]] -> (i32) {
// CHECK: scf.yield %c7_i32 : i32
// CHECK: } else {
// CHECK: scf.yield %c0_i32 : i32
// CHECK: return %[[IF]] : i32

// CHECK: func.func @bind_inline
// CHECK-NOT: match.match
// CHECK-NOT: scf.if
// CHECK: return %arg0 : !match.option<i32>
