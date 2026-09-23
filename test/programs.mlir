// RUN: %matchopt -match-to-decision-tree -convert-match-to-scf -convert-scf-to-cf -match-to-llvm -convert-to-llvm %S/../programs/simple.mlir | %FileCheck %s --check-prefix=SIMPLE
// RUN: %matchopt -match-to-decision-tree -convert-match-to-scf -convert-scf-to-cf -match-to-llvm -convert-to-llvm %S/../programs/literal-payload.mlir | %FileCheck %s --check-prefix=LITERAL
// RUN: %matchopt -match-to-decision-tree -convert-match-to-scf -convert-scf-to-cf -match-to-llvm -convert-to-llvm %S/../programs/nested-options.mlir | %FileCheck %s --check-prefix=NESTED
// RUN: %matchopt -match-to-decision-tree -convert-match-to-scf -convert-scf-to-cf -match-to-llvm -convert-to-llvm %S/../programs/two-columns.mlir | %FileCheck %s --check-prefix=TWO
// RUN: %matchopt -match-to-decision-tree -convert-match-to-scf -convert-scf-to-cf -match-to-llvm -convert-to-llvm %S/../programs/two-columns.mlir | %not grep -E "match\.|!match"

// The sample programs under `programs/` are there to be read and run; these
// lines keep them compiling all the way out of the dialect, so they cannot rot.
// The lowerings themselves are checked in detail by the convert-* tests.

// SIMPLE: llvm.func @classify(%arg0: i32) -> i32

// LITERAL: llvm.func @classify_literal(%arg0: !llvm.struct<(i32, i32)>) -> i32
// LITERAL: llvm.func @guarded(%arg0: !llvm.struct<(i32, i32)>) -> i32

// NESTED: llvm.func @unwrap_twice(%arg0: !llvm.struct<(i32, struct<(i32, i32)>)>) -> i32
// NESTED: llvm.func @order_matters(%arg0: !llvm.struct<(i32, struct<(i32, i32)>)>) -> i32

// TWO: llvm.func @matrix(%arg0: !llvm.struct<(struct<(i32, i32)>, struct<(i32, i32)>)>) -> i32
// TWO: llvm.func @with_default(%arg0: !llvm.struct<(struct<(i32, i32)>, struct<(i32, i32)>)>) -> i32
// RUN: %matchopt -match-to-decision-tree -convert-match-to-scf -convert-scf-to-cf -match-to-llvm -convert-to-llvm %S/../programs/literals-16.mlir | %FileCheck %s --check-prefix=MATRIX
// RUN: %matchopt -match-to-decision-tree -convert-match-to-scf -convert-scf-to-cf -match-to-llvm -convert-to-llvm %S/../programs/nested-8.mlir | %FileCheck %s --check-prefix=MATRIX
// RUN: %matchopt -match-to-decision-tree -convert-match-to-scf -convert-scf-to-cf -match-to-llvm -convert-to-llvm %S/../programs/columns-3.mlir | %FileCheck %s --check-prefix=MATRIX

// The generated matrices are the programs that show the lowerings' cost
// difference; one per family is lowered here so they cannot rot.

// MATRIX: llvm.func @classify(%arg0:
