// RUN: %not %matchopt %s 2>&1 | %FileCheck %s

// The default region has no pattern to refine, so it must not contain a guard.
module {
  func.func @bad_guard(%x: i32) -> i32 {
    %c0 = arith.constant 0 : i32
    %true = arith.constant true

    %result = match.match %x : i32 -> i32
      default {
        match.guard %true
        match.yield %c0 : i32
      }
    return %result : i32
  }
}

// CHECK: error: 'match.match' op the default region may not contain a match.guard
