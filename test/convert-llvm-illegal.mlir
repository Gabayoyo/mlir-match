// RUN: %not %matchopt -match-to-llvm %s 2>&1 | %FileCheck %s --check-prefix=ERR

// The pass lowers `match.deconstruct`, which is what the control-flow passes
// leave behind: `match.match`, `match.guard` and `match.yield` are gone by then.
// The match ops are marked illegal in the conversion target, so a module that
// still holds one fails the pass instead of passing through with match ops in
// it - the pipeline must run the earlier passes first.

module {
  func.func @unlowered(%v: !match.option<i32>) -> i32 {
    %c0 = arith.constant 0 : i32
    %r = match.match {patterns = [#match.pattern<"some"(#match.pattern<"bind">)>, #match.pattern<"bind">]} %v : !match.option<i32> -> i32
      case (%x: i32) {
        match.yield %x : i32
      }
      case (%w: !match.option<i32>) {
        match.yield %c0 : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %r : i32
  }
}

// ERR: failed to legalize operation 'match.match'
