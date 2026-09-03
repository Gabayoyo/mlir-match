// RUN: %matchopt %s | %FileCheck %s

// An arm whose pattern binds a value declares it in the case header,
// `case (%name : type) {`. The declared binding becomes the arm region's
// entry block argument, so the body can use it by name. No ^bb0 block header
// should leak into the printed form.
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
}

// CHECK: func.func @single_binding
// CHECK: match.match {patterns = [#match.pattern<"bind">]} %arg0 : i32 -> i32
// CHECK: case (%[[V:arg[0-9]+]]: i32) {
// CHECK-NOT: ^bb0
// CHECK: match.yield %[[V]] : i32
// CHECK: default {
// CHECK: match.yield %c0_i32 : i32
// CHECK: }
