// RUN: %not %matchopt %s 2>&1 | %FileCheck %s

// A "literal" pattern exists to match one specific constant; without a
// payload it has nothing to compare the scrutinee against.
module {
  func.func @no_payload(%x: i32) -> i32 {
    %c0 = arith.constant 0 : i32

    %result = match.match {patterns = [#match.pattern<"literal">]} %x : i32 -> i32
      case {
        match.yield %c0 : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %result : i32
  }
}

// CHECK: error: a 'literal' pattern must carry a payload
