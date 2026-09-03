// RUN: %not %matchopt %s 2>&1 | %FileCheck %s

// An arm's match.yield must carry exactly the match op's results; here the
// match returns one i32 but the first arm's match.yield yields nothing.
module {
  func.func @bad_yield(%x: i32) -> i32 {
    %c0 = arith.constant 0 : i32

    %result = match.match %x : i32 -> i32
      case {
        match.yield
      }
      default {
        match.yield %c0 : i32
      }
    return %result : i32
  }
}

// CHECK: error: 'match.match' op match.yield must carry as many values as the match op has results
