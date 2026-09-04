// RUN: %matchopt %s | %FileCheck %s

// match.deconstruct is the runtime primitive that enacts the constructor
// tables: given a tagged value and a constructor name it yields a matched
// flag plus the constructor's fields (all results are always produced; the
// fields are meaningful only when matched). It round-trips for option and
// pair constructors, with zero, one, or two fields.
module {
  func.func @some(%v: !match.option<i32>) -> i32 {
    %c0 = arith.constant 0 : i32
    %m, %p = match.deconstruct %v, "some" : !match.option<i32> -> (i1, i32)
    %r = arith.select %m, %p, %c0 : i32
    return %r : i32
  }

  func.func @none(%v: !match.option<i32>) -> i32 {
    %m = match.deconstruct %v, "none" : !match.option<i32> -> (i1)
    %r = arith.extui %m : i1 to i32
    return %r : i32
  }

  func.func @pair(%v: !match.pair<i32, i64>) -> i64 {
    %m, %l, %r2 = match.deconstruct %v, "pair" : !match.pair<i32, i64> -> (i1, i32, i64)
    %w = arith.extsi %l : i32 to i64
    %s = arith.addi %w, %r2 : i64
    return %s : i64
  }
}

// CHECK: func.func @some
// CHECK: %[[M:.*]], %[[F:.*]] = match.deconstruct %arg0, "some" : !match.option<i32> -> (i1, i32)
// CHECK: %[[S:.*]] = arith.select %[[M]], %[[F]], %c0_i32 : i32

// CHECK: func.func @none
// CHECK: %[[M2:.*]] = match.deconstruct %arg0, "none" : !match.option<i32> -> (i1)
// CHECK: %[[E:.*]] = arith.extui %[[M2]] : i1 to i32

// CHECK: func.func @pair
// CHECK: %[[M3:.*]], %[[F3:.*]]:2 = match.deconstruct %arg0, "pair" : !match.pair<i32, i64> -> (i1, i32, i64)
// CHECK: %[[W:.*]] = arith.extsi %[[F3]]#0 : i32 to i64
// CHECK: %[[A:.*]] = arith.addi %[[W]], %[[F3]]#1 : i64
