// RUN: %not %matchopt %s 2>&1 | %FileCheck %s

// "some" on !match.option<i32> carries exactly one sub-pattern (the payload's
// pattern); giving it two is an arity error against the type's constructor
// table.
module {
  func.func @too_many_subs(%v: !match.option<i32>) -> i32 {
    %c0 = arith.constant 0 : i32

    %result = match.match {patterns = [#match.pattern<"some"(#match.pattern<"bind">, #match.pattern<"bind">)>]} %v : !match.option<i32> -> i32
      case (%x: i32, %y: i32) {
        match.yield %x : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %result : i32
  }
}

// CHECK: error: 'match.match' op constructor 'some' expects 1 sub-pattern(s) but has 2
