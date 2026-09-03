// RUN: %not %matchopt %s 2>&1 | %FileCheck %s

// When a patterns attribute is present it must carry one entry per arm.
// Here there are two arms but only one pattern.
module {
  func.func @bad_pattern_count(%x: i32) -> i32 {
    %c0 = arith.constant 0 : i32
    %c1 = arith.constant 1 : i32
    %neg1 = arith.constant -1 : i32

    %result = match.match {patterns = [#match.pattern<"wildcard">]} %x : i32 -> i32
      case {
        match.yield %c1 : i32
      }
      case {
        match.yield %neg1 : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %result : i32
  }
}

// CHECK: error: 'match.match' op the number of patterns must match the number of arms
