// Negative test: an arm's match.yield must carry exactly the match op's results.
// Here the match produces one i32, but the first arm's match.yield yields
// nothing, which should fail verification.
module {
  func.func @bad_yield(%x: i32) -> i32 {
    %c0 = arith.constant 0 : i32

    %result = "match.match"(%x) ({
      // default region yields the right arity
      ^bb0:
        "match.yield"(%c0) : (i32) -> ()
    }, {
      // arm: match.yield has zero operands, but the match returns one i32
      ^bb0:
        "match.yield"() : () -> ()
    }) : (i32) -> (i32)
    return %result : i32
  }
}
