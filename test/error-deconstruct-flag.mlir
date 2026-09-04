// RUN: %not %matchopt %s 2>&1 | %FileCheck %s

// The first result of match.deconstruct is the i1 matched flag; giving it
// another type is rejected.
module {
  func.func @flag_not_i1(%v: !match.option<i32>) -> i32 {
    %c0 = arith.constant 0 : i32
    %m, %p = match.deconstruct %v, "some" : !match.option<i32> -> (i32, i32)
    return %c0 : i32
  }
}

// CHECK: error: 'match.deconstruct' op result #0 must be 1-bit signless integer, but got 'i32'
