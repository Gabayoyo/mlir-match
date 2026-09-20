// RUN: %matchopt -match-to-decision-tree -convert-match-to-scf -match-to-llvm %s | %FileCheck %s
// RUN: %matchopt -match-to-decision-tree -convert-match-to-scf -match-to-llvm %s | %not grep -E "match\.|!match"
// RUN: %matchopt -match-to-decision-tree -convert-match-to-scf -convert-scf-to-cf -match-to-llvm -convert-to-llvm %s | %mlirtranslate --mlir-to-llvmir | %FileCheck %s --check-prefix=IR

// An `option` value is tagged, so the converted struct stores its constructor in
// slot 0 and the payload in slot 1. Each arm's condition becomes a comparison of
// that tag against the constructor's index in the type's table, where `some` is
// 0 and `none` is 1. The second RUN line asserts the whole module is free of
// match ops and match types once the pipeline finishes.

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

// The signature is converted along with the body: an option arrives as a struct.
// CHECK-LABEL: llvm.func @classify(%arg0: !llvm.struct<(i32, i32)>) -> i32

// `some` is constructor 0, so the tag in slot 0 is compared against 0 and the
// payload in slot 1 is what the arm yields.
// CHECK: %[[TAG:.*]] = llvm.extractvalue %arg0[0] : !llvm.struct<(i32, i32)>
// CHECK: %[[ZERO:.*]] = arith.constant 0 : i32
// CHECK: %[[IS_SOME:.*]] = arith.cmpi eq, %[[TAG]], %[[ZERO]] : i32
// CHECK: %[[PAYLOAD:.*]] = llvm.extractvalue %arg0[1] : !llvm.struct<(i32, i32)>
// CHECK: scf.if %[[IS_SOME]] -> (i32)
// CHECK: scf.yield %[[PAYLOAD]] : i32

// `none` is constructor 1, tested against the same tag slot.
// CHECK: %[[TAG2:.*]] = llvm.extractvalue %arg0[0] : !llvm.struct<(i32, i32)>
// CHECK: %[[ONE:.*]] = arith.constant 1 : i32
// CHECK: %[[IS_NONE:.*]] = arith.cmpi eq, %[[TAG2]], %[[ONE]] : i32

// IR-LABEL: define i32 @classify({ i32, i32 } %{{.*}})
// IR: extractvalue { i32, i32 } %{{.*}}, 0
// IR: icmp eq i32
