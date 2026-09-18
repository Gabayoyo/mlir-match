// RUN: %matchopt -match-to-decision-tree %s > %t.default
// RUN: %matchopt -match-to-decision-tree=column-choice=leftmost %s > %t.leftmost
// RUN: %matchopt -match-to-decision-tree=column-choice=discriminating %s > %t.discriminating
// RUN: diff %t.default %t.leftmost
// RUN: diff %t.default %t.discriminating
// RUN: %matchopt -match-to-decision-tree=column-choice=discriminating %s | %FileCheck %s

// The column-choice option is accepted in both spellings, and while column
// selection is not wired into the compiler yet every spelling emits the same
// tree. The checks pin the lowered shape so a silently skipped lowering cannot
// pass this test either.
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
