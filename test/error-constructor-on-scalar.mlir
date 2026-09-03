// RUN: %not %matchopt %s 2>&1 | %FileCheck %s

// Constructors belong to tagged match types; a plain i32 has no constructor
// table, so matching it with a constructor pattern is a type error rather
// than silently matching nothing.
module {
  func.func @constructor_on_scalar(%x: i32) -> i32 {
    %c0 = arith.constant 0 : i32

    %result = match.match {patterns = [#match.pattern<"some"(#match.pattern<"bind">)>]} %x : i32 -> i32
      case (%v: i32) {
        match.yield %v : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %result : i32
  }
}

// CHECK: error: 'match.match' op pattern kind 'some' is not a constructor of 'i32'
