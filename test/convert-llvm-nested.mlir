// RUN: %matchopt -match-to-decision-tree -convert-match-to-scf -match-to-llvm %s | %FileCheck %s
// RUN: %matchopt -match-to-decision-tree -convert-match-to-scf -match-to-llvm %s | %not grep -E "match\.|!match"

// Match types nest, so the conversions compose: a pair of options becomes a
// struct whose fields are themselves tagged structs. Reading a field of the pair
// yields the inner struct, and the arm tests that value's own tag.

module {
  func.func @nested(%v: !match.pair<!match.option<i32>, !match.option<i32>>) -> i32 {
    %c0 = arith.constant 0 : i32
    %r = match.match {patterns = [#match.pattern<"pair"(#match.pattern<"some"(#match.pattern<"bind">)>, #match.pattern<"none">)>]} %v : !match.pair<!match.option<i32>, !match.option<i32>> -> i32
      case (%x: i32) {
        match.yield %x : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %r : i32
  }
}

// CHECK-LABEL: llvm.func @nested(%arg0: !llvm.struct<(struct<(i32, i32)>, struct<(i32, i32)>)>) -> i32

// The outer pair is untagged, so its flag is a constant and its fields are in
// slots 0 and 1.
// CHECK: %[[TRUE:.*]] = arith.constant true
// CHECK: %[[PAIR0:.*]] = llvm.extractvalue %arg0[0] : !llvm.struct<(struct<(i32, i32)>, struct<(i32, i32)>)>
// CHECK: %[[PAIR1:.*]] = llvm.extractvalue %arg0[1] : !llvm.struct<(struct<(i32, i32)>, struct<(i32, i32)>)>
// CHECK: scf.if %[[TRUE]] -> (i32)

// The first field is an option, so it is tested for `some` on its own tag slot.
// CHECK: %[[TAG0:.*]] = llvm.extractvalue %[[PAIR0]][0] : !llvm.struct<(i32, i32)>
// CHECK: %[[ZERO:.*]] = arith.constant 0 : i32
// CHECK: %[[IS_SOME:.*]] = arith.cmpi eq, %[[TAG0]], %[[ZERO]] : i32
// CHECK: %[[PAYLOAD:.*]] = llvm.extractvalue %[[PAIR0]][1] : !llvm.struct<(i32, i32)>

// The second field is tested for `none`, constructor 1.
// CHECK: %[[TAG1:.*]] = llvm.extractvalue %[[PAIR1]][0] : !llvm.struct<(i32, i32)>
// CHECK: %[[ONE:.*]] = arith.constant 1 : i32
// CHECK: %[[IS_NONE:.*]] = arith.cmpi eq, %[[TAG1]], %[[ONE]] : i32
// CHECK: scf.yield %[[PAYLOAD]] : i32
