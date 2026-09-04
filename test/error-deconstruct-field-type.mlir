// RUN: %not %matchopt %s 2>&1 | %FileCheck %s

// The field results of match.deconstruct must line up with the constructor's
// field types in order: "some" over !match.option<i32> projects an i32, not
// an i64.
module {
  func.func @wrong_field_type(%v: !match.option<i32>) -> i32 {
    %c0 = arith.constant 0 : i32
    %m, %p = match.deconstruct %v, "some" : !match.option<i32> -> (i1, i64)
    return %c0 : i32
  }
}

// CHECK: error: 'match.deconstruct' op result 1 type ('i64') does not match the expected field type ('i32') for constructor 'some' on type '!match.option<i32>'
