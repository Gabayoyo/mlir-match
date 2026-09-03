// RUN: %matchopt -convert-match-to-scf %s | %FileCheck %s

// Two guarded arms and a default lower to a nested scf.if chain: arm
// conditions are hoisted, bodies become scf.yield results, and the default
// fills the deepest else.
module {
  func.func @classify(%x: i32) -> i32 {
    %c0 = arith.constant 0 : i32
    %c1 = arith.constant 1 : i32
    %neg1 = arith.constant -1 : i32

    %result = match.match %x : i32 -> i32
      case {
        %is_pos = arith.cmpi sgt, %x, %c0 : i32
        match.guard %is_pos
        match.yield %c1 : i32
      }
      case {
        %is_neg = arith.cmpi slt, %x, %c0 : i32
        match.guard %is_neg
        match.yield %neg1 : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %result : i32
  }
}

// CHECK: func.func @classify
// CHECK-NOT: match.match
// CHECK: %[[POS:.*]] = arith.cmpi sgt, %arg0, %c0_i32 : i32
// CHECK: %[[IF0:.*]] = scf.if %[[POS]] -> (i32) {
// CHECK:   scf.yield %c1_i32 : i32
// CHECK: } else {
// CHECK:   %[[NEG:.*]] = arith.cmpi slt, %arg0, %c0_i32 : i32
// CHECK:   %[[IF1:.*]] = scf.if %[[NEG]] -> (i32) {
// CHECK:     scf.yield %c-1_i32 : i32
// CHECK:   } else {
// CHECK:     scf.yield %c0_i32 : i32
// CHECK:   }
// CHECK:   scf.yield %[[IF1]] : i32
// CHECK: }
// CHECK: return %[[IF0]] : i32
