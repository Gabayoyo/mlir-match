// RUN: %matchopt -match-to-decision-tree %s | %FileCheck %s --check-prefix=TREE
// RUN: %matchopt -match-to-decision-tree %s | %FileCheck %s --check-prefix=DC
// RUN: %matchopt -convert-match-to-scf %s | %FileCheck %s --check-prefix=NAIVE
// RUN: %matchopt -convert-match-to-scf %s | %FileCheck %s --check-prefix=NC

// Nested constructors, rows ordered some(none), some(some(bind)), none.
// The tree asks each constructor test once and shares it across rows (4
// deconstructs); the naive pass re-tests per arm (5).
module {
  func.func @order(%v: !match.option<!match.option<i32>>) -> i32 {
    %c0 = arith.constant 0 : i32
    %c7 = arith.constant 7 : i32
    %c9 = arith.constant 9 : i32
    %r = match.match {patterns = [
      #match.pattern<"some"(#match.pattern<"none">)>,
      #match.pattern<"some"(#match.pattern<"some"(#match.pattern<"bind">)>)>,
      #match.pattern<"none">
    ]} %v : !match.option<!match.option<i32>> -> i32
      case {
        match.yield %c7 : i32
      }
      case (%x: i32) {
        match.yield %x : i32
      }
      case {
        match.yield %c9 : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %r : i32
  }
}

// TREE: func.func @order
// TREE-NOT: match.match
// TREE: %[[M0:.*]], %[[F0:.*]] = match.deconstruct %arg0, "some" : !match.option<!match.option<i32>> -> (i1, !match.option<i32>)
// TREE: %[[IF0:.*]] = scf.if %[[M0]] -> (i32) {
// TREE: %[[M1:.*]] = match.deconstruct %[[F0]], "none" : !match.option<i32> -> (i1)
// TREE: scf.if %[[M1]] -> (i32) {
// TREE: scf.yield %c7_i32 : i32
// TREE: } else {
// TREE: %[[M2:.*]], %[[F2:.*]] = match.deconstruct %[[F0]], "some" : !match.option<i32> -> (i1, i32)
// TREE: scf.if %[[M2]] -> (i32) {
// TREE: scf.yield %[[F2]] : i32
// TREE: } else {
// TREE: scf.yield %c0_i32 : i32
// TREE: } else {
// TREE: %[[M3:.*]] = match.deconstruct %arg0, "none" : !match.option<!match.option<i32>> -> (i1)
// TREE: scf.if %[[M3]] -> (i32) {
// TREE: scf.yield %c9_i32 : i32
// TREE: return %[[IF0]] : i32

// DC-COUNT-4: match.deconstruct

// NAIVE: func.func @order
// NAIVE-NOT: match.match
// NAIVE: scf.yield %c7_i32 : i32
// NAIVE: scf.yield %c9_i32 : i32
// NAIVE: scf.yield %c0_i32 : i32

// NC-COUNT-5: match.deconstruct
