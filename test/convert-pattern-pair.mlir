// RUN: %matchopt -convert-match-to-scf %s | %FileCheck %s

// The two-column matrix: each row deconstructs the same pair into its two
// option fields and tests their constructors. The naive lowering re-tests
// per arm (each row deconstructs "pair" again) - the duplication a decision
// tree later removes.
module {
  func.func @two_columns(%v: !match.pair<!match.option<i32>, !match.option<i32>>) -> i32 {
    %c0 = arith.constant 0 : i32
    %c1 = arith.constant 1 : i32
    %c2 = arith.constant 2 : i32
    %r = match.match {patterns = [
      #match.pattern<"pair"(#match.pattern<"some"(#match.pattern<"bind">)>, #match.pattern<"none">)>,
      #match.pattern<"pair"(#match.pattern<"none">, #match.pattern<"some"(#match.pattern<"bind">)>)>,
      #match.pattern<"pair"(#match.pattern<"none">, #match.pattern<"none">)>
    ]} %v : !match.pair<!match.option<i32>, !match.option<i32>> -> i32
      case (%x: i32) {
        match.yield %c1 : i32
      }
      case (%y: i32) {
        match.yield %c2 : i32
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

// CHECK: func.func @two_columns
// CHECK-NOT: match.match
// CHECK: %[[P:.*]], %[[F:.*]]:2 = match.deconstruct %arg0, "pair" : !match.pair<!match.option<i32>, !match.option<i32>> -> (i1, !match.option<i32>, !match.option<i32>)
// CHECK: %[[S:.*]], %[[X:.*]] = match.deconstruct %[[F]]#0, "some" : !match.option<i32> -> (i1, i32)
// CHECK: %[[N:.*]] = match.deconstruct %[[F]]#1, "none" : !match.option<i32> -> (i1)
// CHECK: %[[IF:.*]] = scf.if %[[C:.*]] -> (i32) {
// CHECK: scf.yield %c1_i32 : i32
// CHECK: } else {
// The second row re-tests the pair and the "none"/"some" combination.
// CHECK: %[[P2:.*]], %[[F2:.*]]:2 = match.deconstruct %arg0, "pair" : !match.pair<!match.option<i32>, !match.option<i32>> -> (i1, !match.option<i32>, !match.option<i32>)
// CHECK: scf.yield %c2_i32 : i32
// CHECK: } else {
// CHECK: scf.yield %c0_i32 : i32
