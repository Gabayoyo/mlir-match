// RUN: %not %matchopt %s 2>&1 | %FileCheck %s

// A constructor pattern must use a constructor the scrutinee type declares:
// !match.option<i32> only has "some" (one payload field) and "none".
module {
  func.func @bogus_kind(%v: !match.option<i32>) -> i32 {
    %c0 = arith.constant 0 : i32

    %result = match.match {patterns = [#match.pattern<"bogus">]} %v : !match.option<i32> -> i32
      case {
        match.yield %c0 : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %result : i32
  }
}

// CHECK: error: 'match.match' op pattern kind 'bogus' is not a constructor of '!match.option<i32>'
