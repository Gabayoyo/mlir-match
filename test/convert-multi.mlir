// RUN: %matchopt -convert-match-to-scf %s | %FileCheck %s

// A match producing two results lowers to an scf.if with both result types;
// both arms yield two values and the uses are rewired to the two results.
module {
  func.func @multi(%x: i32) -> (i32, i32) {
    %c0 = arith.constant 0 : i32
    %c1 = arith.constant 1 : i32
    %c2 = arith.constant 2 : i32

    %r:2 = match.match %x : i32 -> (i32, i32)
      case {
        %is_pos = arith.cmpi sgt, %x, %c0 : i32
        match.guard %is_pos
        match.yield %c1, %c2 : i32, i32
      }
      default {
        match.yield %c0, %c0 : i32, i32
      }
    return %r#0, %r#1 : i32, i32
  }
}

// CHECK: func.func @multi
// CHECK: %[[POS:.*]] = arith.cmpi sgt, %arg0, %c0_i32 : i32
// CHECK: %[[RES:.*]]:2 = scf.if %[[POS]] -> (i32, i32) {
// CHECK:   scf.yield %c1_i32, %c2_i32 : i32, i32
// CHECK: } else {
// CHECK:   scf.yield %c0_i32, %c0_i32 : i32, i32
// CHECK: }
// CHECK: return %[[RES]]#0, %[[RES]]#1 : i32, i32
