// RUN: %not %matchopt %s 2>&1 | %FileCheck %s

// match.deconstruct may only name a constructor the value's type declares:
// !match.option<i32> has "some" and "none", not "bogus".
module {
  func.func @bogus_constructor(%v: !match.option<i32>) -> i32 {
    %c0 = arith.constant 0 : i32
    %m = match.deconstruct %v, "bogus" : !match.option<i32> -> (i1)
    return %c0 : i32
  }
}

// CHECK: error: 'match.deconstruct' op constructor 'bogus' does not exist on type '!match.option<i32>'
