// Literals nested under constructors: matching option values by payload.
module {
  // some(1) -> 10; some(x) -> x*2; none -> 0.
  func.func @classify_literal(%v: !match.option<i32>) -> i32 {
    %c0 = arith.constant 0 : i32
    %c2 = arith.constant 2 : i32
    %c10 = arith.constant 10 : i32
    %r = match.match {patterns = [
      #match.pattern<"some"(#match.pattern<"literal", 1 : i32>)>,
      #match.pattern<"some"(#match.pattern<"bind">)>,
      #match.pattern<"none">
    ]} %v : !match.option<i32> -> i32
      case {
        match.yield %c10 : i32
      }
      case (%x: i32) {
        %twice = arith.muli %x, %c2 : i32
        match.yield %twice : i32
      }
      case {
        match.yield %c0 : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %r : i32
  }

  // Guarded variant: only some(x) with x > 10 fires; everything else falls
  // to the default.
  func.func @guarded(%v: !match.option<i32>) -> i32 {
    %c0 = arith.constant 0 : i32
    %c10 = arith.constant 10 : i32
    %r = match.match {patterns = [#match.pattern<"some"(#match.pattern<"bind">)>]} %v : !match.option<i32> -> i32
      case (%x: i32) {
        %big = arith.cmpi sgt, %x, %c10 : i32
        match.guard %big
        match.yield %x : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %r : i32
  }
}
