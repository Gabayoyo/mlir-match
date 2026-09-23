// RUN: %matchopt -match-to-decision-tree %s > %t.default
// RUN: %matchopt -match-to-decision-tree=column-choice=leftmost %s > %t.leftmost
// RUN: diff %t.default %t.leftmost
// RUN: %matchopt -match-to-decision-tree=column-choice=leftmost %s | %FileCheck %s --check-prefix=LEFT
// RUN: %matchopt -match-to-decision-tree=column-choice=mixture %s | %FileCheck %s --check-prefix=MIX
// RUN: %not %matchopt -match-to-decision-tree=column-choice=bogus %s 2>&1 | %FileCheck %s --check-prefix=ERR

// The default spelling and `leftmost` are the same pass configuration; an
// unrecognised spelling is rejected by the driver before the pass runs.
// `leftmost` questions a row's columns in source order, while `mixture`
// questions the column that copies the fewest rows first, falling back on the
// one that splits the rows into the most groups, so the two differ on a matrix
// whose leading column is uniform.
module {
  // A single column: both strategies can only question it, so they agree.
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

  // Two columns, and every row asks for `some` in the first one: that column
  // scores 1 (a test there partitions nothing), while the second column's heads
  // are `none` and `some`, so `mixture` questions it first instead.
  func.func @uniform_first_column(%v: !match.pair<!match.option<i32>, !match.option<i32>>) -> i32 {
    %c0 = arith.constant 0 : i32
    %c10 = arith.constant 10 : i32
    %c20 = arith.constant 20 : i32
    %r = match.match {patterns = [
      #match.pattern<"pair"(#match.pattern<"some"(#match.pattern<"literal", 1 : i32>)>, #match.pattern<"none">)>,
      #match.pattern<"pair"(#match.pattern<"some"(#match.pattern<"literal", 2 : i32>)>, #match.pattern<"none">)>,
      #match.pattern<"pair"(#match.pattern<"some"(#match.pattern<"literal", 3 : i32>)>, #match.pattern<"some"(#match.pattern<"bind">)>)>
    ]} %v : !match.pair<!match.option<i32>, !match.option<i32>> -> i32
      case {
        match.yield %c10 : i32
      }
      case {
        match.yield %c20 : i32
      }
      case (%y: i32) {
        match.yield %y : i32
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
// CHECK: scf.yield %[[F]] : i32
// CHECK: } else {
// CHECK: %[[M2:.*]] = match.deconstruct %arg0, "none" : !match.option<i32> -> (i1)
// CHECK: scf.if %[[M2]] -> (i32) {
// CHECK: scf.yield %c7_i32 : i32
// CHECK: } else {
// CHECK: scf.yield %c0_i32 : i32
// CHECK: return %[[IF0]] : i32

// LEFT-LABEL: func.func @uniform_first_column
// LEFT-NOT: match.match
// LEFT: %[[LM:.*]], %[[LF:.*]]:2 = match.deconstruct %arg0, "pair" : !match.pair<!match.option<i32>, !match.option<i32>> -> (i1, !match.option<i32>, !match.option<i32>)
// LEFT: scf.if %[[LM]] -> (i32) {
// Source order: the first field is questioned first, even though every row wants
// `some` there.
// LEFT: %[[LS:.*]], %[[LP:.*]] = match.deconstruct %[[LF]]#0, "some" : !match.option<i32> -> (i1, i32)
// LEFT: scf.if %[[LS]] -> (i32) {

// MIX-LABEL: func.func @uniform_first_column
// MIX-NOT: match.match
// MIX: %[[HM:.*]], %[[HF:.*]]:2 = match.deconstruct %arg0, "pair" : !match.pair<!match.option<i32>, !match.option<i32>> -> (i1, !match.option<i32>, !match.option<i32>)
// MIX: scf.if %[[HM]] -> (i32) {
// The column whose heads split the rows is questioned first: the second field.
// MIX: %[[HS:.*]] = match.deconstruct %[[HF]]#1, "none" : !match.option<i32> -> (i1)
// MIX: scf.if %[[HS]] -> (i32) {

// ERR: Cannot find option named 'bogus'
