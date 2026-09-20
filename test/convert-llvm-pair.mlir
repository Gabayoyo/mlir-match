// RUN: %matchopt -match-to-decision-tree -convert-match-to-scf -match-to-llvm %s | %FileCheck %s
// RUN: %matchopt -match-to-decision-tree -convert-match-to-scf -match-to-llvm %s | %not grep -E "match\.|!match"

// A type with a single constructor needs no tag: every value of it has the same
// shape, so the match flag is a constant rather than a comparison, and the
// fields occupy slots from 0. The conversion still has to produce a flag,
// because `match.deconstruct` declares that result.

module {
  func.func @sum(%p: !match.pair<i32, i32>) -> i32 {
    %c0 = arith.constant 0 : i32
    %r = match.match {patterns = [#match.pattern<"pair"(#match.pattern<"bind">, #match.pattern<"bind">)>]} %p : !match.pair<i32, i32> -> i32
      case (%a: i32, %b: i32) {
        %s = arith.addi %a, %b : i32
        match.yield %s : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %r : i32
  }
}

// The pair becomes an untagged struct of its two field types.
// CHECK-LABEL: llvm.func @sum(%arg0: !llvm.struct<(i32, i32)>) -> i32

// No tag to test: the flag is a constant, and the fields are read from slots 0
// and 1.
// CHECK: %[[TRUE:.*]] = arith.constant true
// CHECK: %[[FIRST:.*]] = llvm.extractvalue %arg0[0] : !llvm.struct<(i32, i32)>
// CHECK: %[[SECOND:.*]] = llvm.extractvalue %arg0[1] : !llvm.struct<(i32, i32)>
// CHECK: scf.if %[[TRUE]] -> (i32)
// CHECK: %[[SUM:.*]] = arith.addi %[[FIRST]], %[[SECOND]] : i32
// CHECK: scf.yield %[[SUM]] : i32
