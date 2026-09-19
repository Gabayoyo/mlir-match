// RUN: %matchopt -match-to-decision-tree=column-choice=leftmost %s | %FileCheck %s --check-prefix=LEFT
// RUN: %matchopt -match-to-decision-tree=column-choice=mixture %s | %FileCheck %s --check-prefix=MIX
// RUN: %matchopt -match-to-decision-tree=column-choice=leftmost %s > %t.left
// RUN: %matchopt -match-to-decision-tree=column-choice=mixture %s > %t.mix
// RUN: %not diff -q %t.left %t.mix

// Mixed columns: a row whose pattern leaves a column unquestioned (a bind or a
// wildcard) is copied into every branch of the test on that column, with the
// column consumed, which is what the mixture rule weighs when it picks the
// column to question first.
module {
  // A row that stops questioning the first column rides into the branch that
  // deconstructs the first field, and the value it binds is that field.
  func.func @ride_padded(%v: !match.pair<!match.pair<i32, i32>, i32>) -> i32 {
    %c0 = arith.constant 0 : i32
    %c1 = arith.constant 1 : i32
    %c2 = arith.constant 2 : i32
    %c3 = arith.constant 3 : i32
    %r = match.match {patterns = [
      #match.pattern<"pair"(#match.pattern<"bind">, #match.pattern<"literal", 1 : i32>)>,
      #match.pattern<"pair"(#match.pattern<"pair"(#match.pattern<"literal", 2 : i32>, #match.pattern<"literal", 3 : i32>)>, #match.pattern<"literal", 1 : i32>)>
    ]} %v : !match.pair<!match.pair<i32, i32>, i32> -> i32
      case (%x: !match.pair<i32, i32>) {
        %m, %f0, %f1 = match.deconstruct %x, "pair" : !match.pair<i32, i32> -> (i1, i32, i32)
        %s = arith.addi %f0, %f1 : i32
        match.yield %s : i32
      }
      case {
        match.yield %c2 : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %r : i32
  }

  // Two binds in one arm: the payload of `some` is bound first, then the second
  // field, and both must reach the arm in that order even though the arm body is
  // emitted through the branch that specialises the first column.
  func.func @bind_order(%v: !match.pair<!match.option<i32>, i32>) -> i32 {
    %c0 = arith.constant 0 : i32
    %c5 = arith.constant 5 : i32
    %c7 = arith.constant 7 : i32
    %c100 = arith.constant 100 : i32
    %r = match.match {patterns = [
      #match.pattern<"pair"(#match.pattern<"some"(#match.pattern<"bind">)>, #match.pattern<"bind">)>,
      #match.pattern<"pair"(#match.pattern<"none">, #match.pattern<"literal", 5 : i32>)>
    ]} %v : !match.pair<!match.option<i32>, i32> -> i32
      case (%x: i32, %y: i32) {
        %a = arith.muli %x, %c100 : i32
        %b = arith.addi %a, %y : i32
        match.yield %b : i32
      }
      case {
        match.yield %c7 : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %r : i32
  }

  // A guarded row that binds everything is complete, so it needs no column test;
  // its guard is tried in front of the test the remaining row produces.
  func.func @ride_guarded(%v: !match.pair<i32, i32>, %limit: i32) -> i32 {
    %c0 = arith.constant 0 : i32
    %c1 = arith.constant 1 : i32
    %c9 = arith.constant 9 : i32
    %r = match.match {patterns = [
      #match.pattern<"bind">,
      #match.pattern<"pair"(#match.pattern<"literal", 1 : i32>, #match.pattern<"bind">)>
    ]} %v : !match.pair<i32, i32> -> i32
      case (%whole: !match.pair<i32, i32>) {
        %big = arith.cmpi sgt, %limit, %c9 : i32
        match.guard %big
        match.yield %c1 : i32
      }
      case (%y: i32) {
        match.yield %y : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %r : i32
  }

  // The first column holds a bind in one row, so testing it copies that row into
  // both branches and re-tests the second column in each. The second column
  // holds no such row, so the mixture rule questions it first and pays for one
  // literal test instead of three.
  func.func @mixture_choice(%v: !match.pair<i32, i32>) -> i32 {
    %c0 = arith.constant 0 : i32
    %c1 = arith.constant 1 : i32
    %c2 = arith.constant 2 : i32
    %r = match.match {patterns = [
      #match.pattern<"pair"(#match.pattern<"bind">, #match.pattern<"literal", 1 : i32>)>,
      #match.pattern<"pair"(#match.pattern<"literal", 2 : i32>, #match.pattern<"literal", 1 : i32>)>
    ]} %v : !match.pair<i32, i32> -> i32
      case (%x: i32) {
        match.yield %x : i32
      }
      case {
        match.yield %c2 : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %r : i32
  }
}

// LEFT-LABEL: func.func @ride_padded
// LEFT-NOT: match.match
// LEFT: %[[PM:.*]], %[[PF:.*]]:2 = match.deconstruct %arg0, "pair" : !match.pair<!match.pair<i32, i32>, i32> -> (i1, !match.pair<i32, i32>, i32)
// LEFT: scf.if %[[PM]] -> (i32) {
// The first field is questioned; the row that binds it rides with the column
// consumed, keeping the field's own two sub-columns in place.
// LEFT: %[[IM:.*]], %[[IF:.*]]:2 = match.deconstruct %[[PF]]#0, "pair" : !match.pair<i32, i32> -> (i1, i32, i32)
// LEFT: scf.if %[[IM]] -> (i32) {
// The riding row's bind is the whole inner pair, so its body deconstructs it.
// LEFT: match.deconstruct %[[PF]]#0, "pair" : !match.pair<i32, i32> -> (i1, i32, i32)
// LEFT: arith.addi

// LEFT-LABEL: func.func @bind_order
// LEFT-NOT: match.match
// LEFT: %[[BM:.*]], %[[BF:.*]]:2 = match.deconstruct %arg0, "pair" : !match.pair<!match.option<i32>, i32> -> (i1, !match.option<i32>, i32)
// LEFT: scf.if %[[BM]] -> (i32) {
// LEFT: %[[SM:.*]], %[[SF:.*]] = match.deconstruct %[[BF]]#0, "some" : !match.option<i32> -> (i1, i32)
// LEFT: scf.if %[[SM]] -> (i32) {
// The payload is the first binding, the second field the second.
// LEFT: arith.muli %[[SF]], %c100_i32
// LEFT: arith.addi %{{.*}}, %[[BF]]#1 : i32

// LEFT-LABEL: func.func @ride_guarded
// LEFT-NOT: match.match
// The guard condition is re-emitted in front of the test it guards.
// LEFT: %[[GT:.*]] = arith.cmpi sgt, %arg1, %c9_i32 : i32
// LEFT: %[[IF0:.*]] = scf.if %[[GT]] -> (i32) {
// LEFT: scf.yield %c1_i32 : i32
// LEFT: } else {
// The guard failed, so the remaining row is compiled in the else branch.
// LEFT: %[[GM:.*]], %[[GF:.*]]:2 = match.deconstruct %arg0, "pair" : !match.pair<i32, i32> -> (i1, i32, i32)
// LEFT: arith.cmpi eq, %[[GF]]#0, %c1_i32
// LEFT: scf.yield %[[GF]]#1 : i32

// LEFT-LABEL: func.func @mixture_choice
// LEFT-NOT: match.match
// LEFT: %[[LM:.*]], %[[LF:.*]]:2 = match.deconstruct %arg0, "pair" : !match.pair<i32, i32> -> (i1, i32, i32)
// LEFT: scf.if %[[LM]] -> (i32) {
// Source order questions the bind column first, so the second column's literal
// test is emitted once per branch: two of them here, plus one in the fail
// branch.
// LEFT: arith.cmpi eq, %[[LF]]#0, %c2_i32
// LEFT: arith.cmpi eq, %[[LF]]#1, %c1_i32
// LEFT: arith.cmpi eq, %[[LF]]#1, %c1_i32

// MIX-LABEL: func.func @mixture_choice
// MIX-NOT: match.match
// MIX: %[[XM:.*]], %[[XF:.*]]:2 = match.deconstruct %arg0, "pair" : !match.pair<i32, i32> -> (i1, i32, i32)
// MIX: scf.if %[[XM]] -> (i32) {
// The mixture rule questions the column no row leaves unquestioned: one test.
// MIX: arith.cmpi eq, %[[XF]]#1, %c1_i32
// MIX-NOT: arith.cmpi eq, %[[XF]]#0, %c2_i32
