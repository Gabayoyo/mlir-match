// Nested constructors: matching !match.option<!match.option<i32>>.
module {
  // some(some(x)) -> x; some(none) -> 1; none -> 0.
  func.func @unwrap_twice(%v: !match.option<!match.option<i32>>) -> i32 {
    %c0 = arith.constant 0 : i32
    %c1 = arith.constant 1 : i32
    %r = match.match {patterns = [
      #match.pattern<"some"(#match.pattern<"some"(#match.pattern<"bind">)>)>,
      #match.pattern<"some"(#match.pattern<"none">)>,
      #match.pattern<"none">
    ]} %v : !match.option<!match.option<i32>> -> i32
      case (%x: i32) {
        match.yield %x : i32
      }
      case {
        match.yield %c1 : i32
      }
      case {
        match.yield %c0 : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %r : i32
  }

  // Same rows, reordered: row order decides which arm fires first.
  func.func @order_matters(%v: !match.option<!match.option<i32>>) -> i32 {
    %c0 = arith.constant 0 : i32
    %r = match.match {patterns = [
      #match.pattern<"some"(#match.pattern<"none">)>,
      #match.pattern<"some"(#match.pattern<"some"(#match.pattern<"bind">)>)>,
      #match.pattern<"none">
    ]} %v : !match.option<!match.option<i32>> -> i32
      case {
        match.yield %c0 : i32
      }
      case (%x: i32) {
        match.yield %x : i32
      }
      case {
        match.yield %c0 : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %r : i32
  }
}
