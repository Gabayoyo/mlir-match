// RUN: %matchopt %s | %FileCheck %s

// An arm whose pattern binds values declares them in the case header,
// `case (%name : type, ...) {`. The declared bindings become the arm region's
// entry block arguments, so the body can use them by name. No ^bb0 block
// header should leak into the printed form.
module {
  func.func @single_binding(%x: i32) -> i32 {
    %c0 = arith.constant 0 : i32

    %result = match.match {patterns = [#match.pattern<"bind">]} %x : i32 -> i32
      case (%bound: i32) {
        match.yield %bound : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %result : i32
  }

  // A constructor pattern with two nested binds declares two bindings, one
  // per nested bind, in depth-first order. Each nested bind is itself a full
  // #match.pattern attribute.
  func.func @nested_bindings(%x: i32) -> i64 {
    %c0 = arith.constant 0 : i64

    %result = match.match {patterns = [#match.pattern<"pair"(#match.pattern<"bind">, #match.pattern<"bind">)>]} %x : i32 -> i64
      case (%left: i32, %right: i64) {
        %wide = arith.extsi %left : i32 to i64
        %sum = arith.addi %wide, %right : i64
        match.yield %sum : i64
      }
      default {
        match.yield %c0 : i64
      }
    return %result : i64
  }
}

// CHECK: func.func @single_binding
// CHECK: match.match {patterns = [#match.pattern<"bind">]} %arg0 : i32 -> i32
// CHECK: case (%[[V:arg[0-9]+]]: i32) {
// CHECK-NOT: ^bb0
// CHECK: match.yield %[[V]] : i32
// CHECK: default {
// CHECK: match.yield %c0_i32 : i32
// CHECK: }

// CHECK: func.func @nested_bindings
// CHECK: match.match {patterns = [#match.pattern<"pair" (#match.pattern<"bind">, #match.pattern<"bind">)>]} %arg0 : i32 -> i64
// CHECK: case (%[[L:arg[0-9]+]]: i32, %[[R:arg[0-9]+]]: i64) {
// CHECK-NOT: ^bb0
// CHECK: %[[W:.*]] = arith.extsi %[[L]] : i32 to i64
// CHECK: %[[S:.*]] = arith.addi %[[W]], %[[R]] : i64
// CHECK: match.yield %[[S]] : i64
// CHECK: default {
