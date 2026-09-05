// RUN: %matchopt -match-to-decision-tree %s | %FileCheck %s

// Literal heads are compiled into equality-test nodes: after the shared
// constructor test, each payload is tried with arith.cmpi eq, and rows that
// bind ride into the final else as usual.

// A payload column split across two literal rows and a bind row: the "some"
// tag is tested once for every row, then the payload is compared to 1 and 2,
// with the bind row firing when neither matches.
module {
  func.func @classify(%v: !match.option<i32>) -> i32 {
    %c0 = arith.constant 0 : i32
    %c10 = arith.constant 10 : i32
    %c20 = arith.constant 20 : i32
    %r = match.match {patterns = [
      #match.pattern<"some"(#match.pattern<"literal", 1 : i32>)>,
      #match.pattern<"some"(#match.pattern<"literal", 2 : i32>)>,
      #match.pattern<"some"(#match.pattern<"bind">)>,
      #match.pattern<"none">
    ]} %v : !match.option<i32> -> i32
      case {
        match.yield %c10 : i32
      }
      case {
        match.yield %c20 : i32
      }
      case (%x: i32) {
        match.yield %x : i32
      }
      case {
        match.yield %c0 : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %r : i32
  }

  // A scalar scrutinee has no constructors, so the tree is equality tests
  // only: no match.deconstruct appears anywhere.
  func.func @scalar_literals(%x: i32) -> i32 {
    %c0 = arith.constant 0 : i32
    %c11 = arith.constant 11 : i32
    %c22 = arith.constant 22 : i32
    %r = match.match {patterns = [
      #match.pattern<"literal", 1 : i32>,
      #match.pattern<"literal", 2 : i32>,
      #match.pattern<"bind">
    ]} %x : i32 -> i32
      case {
        match.yield %c11 : i32
      }
      case {
        match.yield %c22 : i32
      }
      case (%w: i32) {
        match.yield %w : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %r : i32
  }

  // A guarded literal row: when the payload equals 5 the guard still decides,
  // and a failed guard falls through to the bind row, not the default.
  func.func @guarded_literal(%v: !match.option<i32>, %limit: i32) -> i32 {
    %c0 = arith.constant 0 : i32
    %c7 = arith.constant 7 : i32
    %c10 = arith.constant 10 : i32
    %r = match.match {patterns = [
      #match.pattern<"some"(#match.pattern<"literal", 5 : i32>)>,
      #match.pattern<"some"(#match.pattern<"bind">)>,
      #match.pattern<"none">
    ]} %v : !match.option<i32> -> i32
      case {
        %big = arith.cmpi sgt, %limit, %c10 : i32
        match.guard %big
        match.yield %c7 : i32
      }
      case (%x: i32) {
        match.yield %x : i32
      }
      case {
        match.yield %c0 : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %r : i32
  }

  // Two literal columns under a pair: the second column's equality tests nest
  // inside the first's, so each column is questioned only after the previous
  // one matched.
  func.func @pair_literals(%v: !match.pair<i32, i32>) -> i32 {
    %c0 = arith.constant 0 : i32
    %c11 = arith.constant 11 : i32
    %c21 = arith.constant 21 : i32
    %c12 = arith.constant 12 : i32
    %r = match.match {patterns = [
      #match.pattern<"pair"(#match.pattern<"literal", 1 : i32>, #match.pattern<"literal", 10 : i32>)>,
      #match.pattern<"pair"(#match.pattern<"literal", 1 : i32>, #match.pattern<"literal", 20 : i32>)>,
      #match.pattern<"pair"(#match.pattern<"literal", 2 : i32>, #match.pattern<"literal", 10 : i32>)>
    ]} %v : !match.pair<i32, i32> -> i32
      case {
        match.yield %c11 : i32
      }
      case {
        match.yield %c21 : i32
      }
      case {
        match.yield %c12 : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %r : i32
  }

  // A bind as a direct field of a multi-field constructor cannot align with
  // the column model; the match stays put for the naive pass.
  func.func @ineligible(%v: !match.pair<i32, i32>) -> i32 {
    %c0 = arith.constant 0 : i32
    %c1 = arith.constant 1 : i32
    %r = match.match {patterns = [
      #match.pattern<"pair"(#match.pattern<"bind">, #match.pattern<"literal", 1 : i32>)>
    ]} %v : !match.pair<i32, i32> -> i32
      case (%x: i32) {
        match.yield %c1 : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %r : i32
  }
}

// CHECK-LABEL: func.func @classify
// CHECK-NOT: match.match
// CHECK: %[[M:.*]], %[[F:.*]] = match.deconstruct %arg0, "some" : !match.option<i32> -> (i1, i32)
// CHECK: %[[IF0:.*]] = scf.if %[[M]] -> (i32) {
// CHECK: %[[C1:.*]] = arith.constant 1 : i32
// CHECK: %[[EQ1:.*]] = arith.cmpi eq, %[[F]], %[[C1]] : i32
// CHECK: %[[IF1:.*]] = scf.if %[[EQ1]] -> (i32) {
// CHECK: scf.yield %c10_i32 : i32
// CHECK: } else {
// CHECK: %[[C2:.*]] = arith.constant 2 : i32
// CHECK: %[[EQ2:.*]] = arith.cmpi eq, %[[F]], %[[C2]] : i32
// CHECK: %[[IF2:.*]] = scf.if %[[EQ2]] -> (i32) {
// CHECK: scf.yield %c20_i32 : i32
// CHECK: } else {
// Neither literal matched: the bind row fires, binding the payload.
// CHECK: scf.yield %[[F]] : i32
// CHECK: } else {
// CHECK: %[[M2:.*]] = match.deconstruct %arg0, "none" : !match.option<i32> -> (i1)
// CHECK: scf.if %[[M2]] -> (i32) {
// CHECK: scf.yield %c0_i32 : i32
// CHECK: } else {
// CHECK: scf.yield %c0_i32 : i32
// CHECK: return %[[IF0]] : i32

// CHECK-LABEL: func.func @scalar_literals
// CHECK-NOT: match.match
// CHECK-NOT: match.deconstruct
// CHECK: %[[C1:.*]] = arith.constant 1 : i32
// CHECK: %[[EQ1:.*]] = arith.cmpi eq, %arg0, %[[C1]] : i32
// CHECK: %[[IF1:.*]] = scf.if %[[EQ1]] -> (i32) {
// CHECK: scf.yield %c11_i32 : i32
// CHECK: } else {
// CHECK: %[[C2:.*]] = arith.constant 2 : i32
// CHECK: %[[EQ2:.*]] = arith.cmpi eq, %arg0, %[[C2]] : i32
// CHECK: %[[IF2:.*]] = scf.if %[[EQ2]] -> (i32) {
// CHECK: scf.yield %c22_i32 : i32
// CHECK: } else {
// The bind row binds the scrutinee itself.
// CHECK: scf.yield %arg0 : i32
// CHECK: return %[[IF1]] : i32

// CHECK-LABEL: func.func @guarded_literal
// CHECK-NOT: match.match
// CHECK: %[[M:.*]], %[[F:.*]] = match.deconstruct %arg0, "some" : !match.option<i32> -> (i1, i32)
// CHECK: %[[IF0:.*]] = scf.if %[[M]] -> (i32) {
// CHECK: %[[C5:.*]] = arith.constant 5 : i32
// CHECK: %[[EQ:.*]] = arith.cmpi eq, %[[F]], %[[C5]] : i32
// CHECK: %[[IF1:.*]] = scf.if %[[EQ]] -> (i32) {
// The guard runs only when the payload equals 5.
// CHECK: %[[GT:.*]] = arith.cmpi sgt, %arg1, %c10_i32 : i32
// CHECK: %[[IF2:.*]] = scf.if %[[GT]] -> (i32) {
// CHECK: scf.yield %c7_i32 : i32
// CHECK: } else {
// Guard failed: continue with the bind row.
// CHECK: scf.yield %[[F]] : i32
// CHECK: } else {
// Payload was not 5: the bind row fires directly.
// CHECK: scf.yield %[[F]] : i32
// CHECK: return %[[IF0]] : i32

// CHECK-LABEL: func.func @pair_literals
// CHECK-NOT: match.match
// CHECK: %[[M:.*]], %[[F:.*]]:2 = match.deconstruct %arg0, "pair" : !match.pair<i32, i32> -> (i1, i32, i32)
// CHECK: %[[IF0:.*]] = scf.if %[[M]] -> (i32) {
// CHECK: %[[C1:.*]] = arith.constant 1 : i32
// CHECK: %[[EQ1:.*]] = arith.cmpi eq, %[[F]]#0, %[[C1]] : i32
// CHECK: %[[IF1:.*]] = scf.if %[[EQ1]] -> (i32) {
// The second column is tested inside the first alternative.
// CHECK: %[[C10:.*]] = arith.constant 10 : i32
// CHECK: %[[EQ2:.*]] = arith.cmpi eq, %[[F]]#1, %[[C10]] : i32
// CHECK: %[[IF2:.*]] = scf.if %[[EQ2]] -> (i32) {
// CHECK: scf.yield %c11_i32 : i32
// CHECK: } else {
// CHECK: %[[C20:.*]] = arith.constant 20 : i32
// CHECK: %[[EQ3:.*]] = arith.cmpi eq, %[[F]]#1, %[[C20]] : i32
// CHECK: scf.yield %c21_i32 : i32
// CHECK: } else {
// CHECK: %[[C2:.*]] = arith.constant 2 : i32
// CHECK: %[[EQ4:.*]] = arith.cmpi eq, %[[F]]#0, %[[C2]] : i32
// CHECK: scf.yield %c12_i32 : i32
// CHECK: return %[[IF0]] : i32

// CHECK-LABEL: func.func @ineligible
// CHECK: %[[R:.*]] = match.match {patterns = [{{.*}}]} %arg0 : !match.pair<i32, i32> -> i32
// CHECK: return %[[R]] : i32
