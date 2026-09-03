// RUN: %not %matchopt %s 2>&1 | %FileCheck %s

// The payload of a top-level "literal" pattern must have the scrutinee's
// type; here an i64 constant is matched against an i32 scrutinee.
module {
  func.func @type_mismatch(%x: i32) -> i32 {
    %c0 = arith.constant 0 : i32

    %result = match.match {patterns = [#match.pattern<"literal", 1 : i64>]} %x : i32 -> i32
      case {
        match.yield %c0 : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %result : i32
  }
}

// CHECK: error: 'match.match' op literal pattern payload type 'i64' does not match the expected type 'i32'
