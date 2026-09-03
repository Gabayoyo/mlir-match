// RUN: %matchopt -convert-match-to-scf -convert-scf-to-cf %s | %FileCheck %s

// Lowering the match all the way to control flow: after convert-scf-to-cf no
// scf.if or match op remains, only cf branches.
module {
  func.func @classify(%x: i32) -> i32 {
    %c0 = arith.constant 0 : i32
    %c1 = arith.constant 1 : i32
    %neg1 = arith.constant -1 : i32

    %result = match.match %x : i32 -> i32
      case {
        %is_pos = arith.cmpi sgt, %x, %c0 : i32
        match.guard %is_pos
        match.yield %c1 : i32
      }
      case {
        %is_neg = arith.cmpi slt, %x, %c0 : i32
        match.guard %is_neg
        match.yield %neg1 : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %result : i32
  }
}

// CHECK: func.func @classify
// CHECK-NOT: match.match
// CHECK-NOT: scf.if
// CHECK-COUNT-2: cf.cond_br
// CHECK: cf.br
// CHECK: return
