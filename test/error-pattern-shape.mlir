// RUN: %not %matchopt %s 2>&1 | %FileCheck %s

// Structural patterns ("bind", "wildcard", "literal") describe a single value
// directly, so they cannot deconstruct into sub-patterns; only constructor
// patterns may carry sub-patterns.
module {
  func.func @bind_with_sub(%x: i32) -> i32 {
    %c0 = arith.constant 0 : i32

    %result = match.match {patterns = [#match.pattern<"bind"(#match.pattern<"wildcard">)>]} %x : i32 -> i32
      case (%v: i32) {
        match.yield %v : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %result : i32
  }
}

// CHECK: error: a 'bind' pattern cannot have sub-patterns
