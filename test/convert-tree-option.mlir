// RUN: %matchopt -match-to-decision-tree %s | %FileCheck %s

// The tree pass lowers eligible pattern matches to shared constructor tests;
// matches with guards are left untouched for the naive conversion.
module {
  func.func @classify(%v: !match.option<i32>) -> i32 {
    %c0 = arith.constant 0 : i32
    %c7 = arith.constant 7 : i32
    %r = match.match {patterns = [#match.pattern<"some"(#match.pattern<"bind">)>, #match.pattern<"none">]} %v : !match.option<i32> -> i32
      case (%x: i32) {
        match.yield %x : i32
      }
      case {
        match.yield %c7 : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %r : i32
  }

  // A trailing "bind" row must catch every value the tested constructors
  // don't cover, here the none values: the fail branch yields the bind arm's
  // constant, not the default's.
  func.func @fallback(%v: !match.option<i32>) -> i32 {
    %c0 = arith.constant 0 : i32
    %c1 = arith.constant 1 : i32
    %c2 = arith.constant 2 : i32
    %r = match.match {patterns = [#match.pattern<"some"(#match.pattern<"bind">)>, #match.pattern<"bind">]} %v : !match.option<i32> -> i32
      case (%x: i32) {
        match.yield %c1 : i32
      }
      case (%w: !match.option<i32>) {
        match.yield %c2 : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %r : i32
  }

  // Ineligible: a guarded arm means the whole match is left alone.
  func.func @guarded(%v: !match.option<i32>) -> i32 {
    %c0 = arith.constant 0 : i32
    %c10 = arith.constant 10 : i32
    %r = match.match {patterns = [#match.pattern<"some"(#match.pattern<"bind">)>]} %v : !match.option<i32> -> i32
      case (%x: i32) {
        %big = arith.cmpi sgt, %x, %c10 : i32
        match.guard %big
        match.yield %x : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %r : i32
  }
}

// CHECK: func.func @classify
// CHECK-NOT: match.match
// CHECK: %[[M:.*]], %[[F:.*]] = match.deconstruct %arg0, "some" : !match.option<i32> -> (i1, i32)
// CHECK: %[[IF:.*]] = scf.if %[[M]] -> (i32) {
// CHECK: scf.yield %[[F]] : i32
// CHECK: } else {
// CHECK: %[[M2:.*]] = match.deconstruct %arg0, "none" : !match.option<i32> -> (i1)
// CHECK: scf.if %[[M2]] -> (i32) {
// CHECK: scf.yield %c7_i32 : i32
// CHECK: } else {
// CHECK: scf.yield %c0_i32 : i32
// CHECK: return %[[IF]] : i32

// CHECK: func.func @fallback
// CHECK-NOT: match.match
// CHECK: %[[M3:.*]], %[[F3:.*]] = match.deconstruct %arg0, "some" : !match.option<i32> -> (i1, i32)
// CHECK: scf.if %[[M3]] -> (i32) {
// CHECK: scf.yield %c1_i32 : i32
// CHECK: } else {
// The fail branch fires the trailing bind row, not the default.
// CHECK: scf.yield %c2_i32 : i32

// CHECK: func.func @guarded
// CHECK: match.match {patterns = [#match.pattern<"some" (#match.pattern<"bind">)>]} %arg0 : !match.option<i32> -> i32
// CHECK: match.guard
