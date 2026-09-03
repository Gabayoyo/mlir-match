// RUN: %matchopt %s | %FileCheck %s

// Matching on !match.option<i32>: "some" and "none" are constructors declared
// by the type. A "some" pattern's payload is an i32, so its case header binds
// a single i32; "none" binds nothing. The verifier derives binding types from
// the scrutinee type, so the case header types must agree.
module {
  func.func @some(%v: !match.option<i32>) -> i32 {
    %c0 = arith.constant 0 : i32

    %result = match.match {patterns = [#match.pattern<"some"(#match.pattern<"bind">)>]} %v : !match.option<i32> -> i32
      case (%x: i32) {
        match.yield %x : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %result : i32
  }

  func.func @none(%v: !match.option<i32>) -> i32 {
    %c0 = arith.constant 0 : i32

    %result = match.match {patterns = [#match.pattern<"none">]} %v : !match.option<i32> -> i32
      case {
        match.yield %c0 : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %result : i32
  }

  // Constructor patterns nest: the outer "some" deconstructs an
  // !match.option<!match.option<i32>> into its !match.option<i32> payload, the
  // inner "some" deconstructs that into an i32, and the single "bind" is typed
  // by that innermost position.
  func.func @nested(%v: !match.option<!match.option<i32>>) -> i32 {
    %c0 = arith.constant 0 : i32

    %result = match.match {patterns = [#match.pattern<"some"(#match.pattern<"some"(#match.pattern<"bind">)>)>]} %v : !match.option<!match.option<i32>> -> i32
      case (%x: i32) {
        match.yield %x : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %result : i32
  }
}

// CHECK: func.func @some
// CHECK: match.match {patterns = [#match.pattern<"some" (#match.pattern<"bind">)>]} %arg0 : !match.option<i32> -> i32
// CHECK: case (%[[X:arg[0-9]+]]: i32) {
// CHECK-NOT: ^bb0
// CHECK: match.yield %[[X]] : i32
// CHECK: default {

// CHECK: func.func @none
// CHECK: match.match {patterns = [#match.pattern<"none">]} %arg0 : !match.option<i32> -> i32
// CHECK: case {
// CHECK: default {

// CHECK: func.func @nested
// CHECK: match.match {patterns = [#match.pattern<"some" (#match.pattern<"some" (#match.pattern<"bind">)>)>]} %arg0 : !match.option<!match.option<i32>> -> i32
// CHECK: case (%[[Y:arg[0-9]+]]: i32) {
// CHECK: match.yield %[[Y]] : i32
// CHECK: default {
