// RUN: %matchopt %s | %FileCheck %s

// A match on an i32 scrutinee with two guarded arms and a default region.
module {
  func.func @classify(%x: i32) -> i32 {
    %c0 = arith.constant 0 : i32
    %c1 = arith.constant 1 : i32
    %neg1 = arith.constant -1 : i32

    %result = "match.match"(%x) ({
      // default region
      ^bb0:
        "match.yield"(%c0) : (i32) -> ()
    }, {
      // arm: x > 0
      ^bb0:
        %is_pos = arith.cmpi sgt, %x, %c0 : i32
        "match.guard"(%is_pos) : (i1) -> ()
        "match.yield"(%c1) : (i32) -> ()
    }, {
      // arm: x < 0
      ^bb0:
        %is_neg = arith.cmpi slt, %x, %c0 : i32
        "match.guard"(%is_neg) : (i1) -> ()
        "match.yield"(%neg1) : (i32) -> ()
    }) : (i32) -> (i32)
    return %result : i32
  }
}

// CHECK: func.func @classify
// CHECK: "match.match"(%arg0) ({
// CHECK: "match.yield"(%c0_i32) : (i32) -> ()
// CHECK: "match.guard"
// CHECK: "match.yield"(%c1_i32) : (i32) -> ()
// CHECK: "match.guard"
// CHECK: "match.yield"(%c-1_i32) : (i32) -> ()
// CHECK: }) : (i32) -> i32
