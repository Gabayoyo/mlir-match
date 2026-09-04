// RUN: %not %matchopt %s 2>&1 | %FileCheck %s

// Deconstructing "some" yields exactly the matched flag plus its single
// field: two results. Declaring three is an arity error against the type's
// constructor table.
module {
  func.func @too_many_results(%v: !match.option<i32>) -> i32 {
    %c0 = arith.constant 0 : i32
    %m, %p, %q = match.deconstruct %v, "some" : !match.option<i32> -> (i1, i32, i32)
    return %c0 : i32
  }
}

// CHECK: error: 'match.deconstruct' op number of results (3) does not match the number of fields (1) for constructor 'some' on type '!match.option<i32>'
