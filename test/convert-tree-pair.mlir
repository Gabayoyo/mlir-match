// RUN: %matchopt -match-to-decision-tree %s | %FileCheck %s --check-prefix=TREE
// RUN: %matchopt -match-to-decision-tree %s | %FileCheck %s --check-prefix=DC
// RUN: %matchopt -convert-match-to-scf %s | %FileCheck %s --check-prefix=NC

// Multi-field constructors: the tree deconstructs the pair once and shares
// the two field tests across all four rows (1 pair deconstruct); the naive
// pass re-tests the pair per arm (4). The first row binds both fields.
module {
  func.func @matrix(%v: !match.pair<!match.option<i32>, !match.option<i32>>) -> i32 {
    %c0 = arith.constant 0 : i32
    %r = match.match {patterns = [
      #match.pattern<"pair"(#match.pattern<"some"(#match.pattern<"bind">)>, #match.pattern<"some"(#match.pattern<"bind">)>)>,
      #match.pattern<"pair"(#match.pattern<"some"(#match.pattern<"bind">)>, #match.pattern<"none">)>,
      #match.pattern<"pair"(#match.pattern<"none">, #match.pattern<"some"(#match.pattern<"bind">)>)>,
      #match.pattern<"pair"(#match.pattern<"none">, #match.pattern<"none">)>
    ]} %v : !match.pair<!match.option<i32>, !match.option<i32>> -> i32
      case (%l: i32, %r1: i32) {
        %sum = arith.addi %l, %r1 : i32
        match.yield %sum : i32
      }
      case (%l: i32) {
        match.yield %l : i32
      }
      case (%r2: i32) {
        match.yield %r2 : i32
      }
      case {
        match.yield %c0 : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %r : i32
  }
}

// TREE: func.func @matrix
// TREE-NOT: match.match
// TREE: %[[M:.*]], %[[F:.*]]:2 = match.deconstruct %arg0, "pair" : !match.pair<!match.option<i32>, !match.option<i32>> -> (i1, !match.option<i32>, !match.option<i32>)
// TREE: scf.if %[[M]] -> (i32) {
// TREE: %[[S0:.*]], %[[F0:.*]] = match.deconstruct %[[F]]#0, "some" : !match.option<i32> -> (i1, i32)
// TREE: scf.if %[[S0]] -> (i32) {
// TREE: %[[S1:.*]], %[[F1:.*]] = match.deconstruct %[[F]]#1, "some" : !match.option<i32> -> (i1, i32)
// TREE: scf.if %[[S1]] -> (i32) {
// Both bindings are the two field slots, summed in the first arm's body.
// TREE: %[[SUM:.*]] = arith.addi %[[F0]], %[[F1]] : i32
// TREE: scf.yield %[[SUM]] : i32
// TREE: %[[N1:.*]] = match.deconstruct %[[F]]#1, "none" : !match.option<i32> -> (i1)
// TREE: scf.yield %[[F0]] : i32
// TREE: %[[N0:.*]] = match.deconstruct %[[F]]#0, "none" : !match.option<i32> -> (i1)
// TREE: scf.yield %c0_i32 : i32

// DC-COUNT-1: match.deconstruct %arg0, "pair"
// NC-COUNT-4: match.deconstruct %arg0, "pair"
