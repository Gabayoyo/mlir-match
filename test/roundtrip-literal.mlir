// RUN: %matchopt %s | %FileCheck %s

// A "literal" pattern carries the constant it matches as an integer payload,
// which round-trips through the attribute syntax.
module {
  func.func @classify_literal(%x: i32) -> i32 {
    %c0 = arith.constant 0 : i32
    %c1 = arith.constant 1 : i32

    %result = match.match {patterns = [#match.pattern<"literal", 1 : i32>]} %x : i32 -> i32
      case {
        match.yield %c1 : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %result : i32
  }

  // literal and wildcard rows side by side; both kinds bind nothing.
  func.func @lit_or_wild(%x: i32) -> i32 {
    %c0 = arith.constant 0 : i32
    %c1 = arith.constant 1 : i32
    %c2 = arith.constant 2 : i32

    %result = match.match {patterns = [#match.pattern<"literal", 1 : i32>, #match.pattern<"wildcard">]} %x : i32 -> i32
      case {
        match.yield %c1 : i32
      }
      case {
        match.yield %c2 : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %result : i32
  }
}

// CHECK: func.func @classify_literal
// CHECK: match.match {patterns = [#match.pattern<"literal", 1 : i32>]} %arg0 : i32 -> i32
// CHECK: default {
// CHECK: match.yield %c0_i32 : i32

// CHECK: func.func @lit_or_wild
// CHECK: match.match {patterns = [#match.pattern<"literal", 1 : i32>, #match.pattern<"wildcard">]} %arg0 : i32 -> i32
// CHECK: default {
