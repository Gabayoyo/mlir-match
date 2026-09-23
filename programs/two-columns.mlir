// Two-column matrix: a pair of two options, matched simultaneously. The naive
// lowering re-tests every constructor per row; a decision tree shares them.
module {
  // Exhaustive: four rows cover every pair of constructors.
  func.func @matrix(%v: !match.pair<!match.option<i32>, !match.option<i32>>) -> i32 {
    %c0 = arith.constant 0 : i32
    %r = match.match {patterns = [
      #match.pattern<"pair"(#match.pattern<"some"(#match.pattern<"bind">)>, #match.pattern<"some"(#match.pattern<"bind">)>)>,
      #match.pattern<"pair"(#match.pattern<"some"(#match.pattern<"bind">)>, #match.pattern<"none">)>,
      #match.pattern<"pair"(#match.pattern<"none">, #match.pattern<"some"(#match.pattern<"bind">)>)>,
      #match.pattern<"pair"(#match.pattern<"none">, #match.pattern<"none">)>
    ]} %v : !match.pair<!match.option<i32>, !match.option<i32>> -> i32
      case (%l: i32, %r1: i32) {
        %sum = arith.addi %l, %r1 : i32
        match.yield %sum : i32
      }
      case (%l: i32) {
        match.yield %l : i32
      }
      case (%r2: i32) {
        match.yield %r2 : i32
      }
      case {
        match.yield %c0 : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %r : i32
  }

  // Non-exhaustive variant with a wildcard tail instead of the (none, none)
  // row; the default is reachable.
  func.func @with_default(%v: !match.pair<!match.option<i32>, !match.option<i32>>) -> i32 {
    %c0 = arith.constant 0 : i32
    %r = match.match {patterns = [
      #match.pattern<"pair"(#match.pattern<"some"(#match.pattern<"bind">)>, #match.pattern<"none">)>,
      #match.pattern<"pair"(#match.pattern<"wildcard">, #match.pattern<"wildcard">)>
    ]} %v : !match.pair<!match.option<i32>, !match.option<i32>> -> i32
      case (%x: i32) {
        match.yield %x : i32
      }
      case {
        %c9 = arith.constant 9 : i32
        match.yield %c9 : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %r : i32
  }
}
