// A minimal match.match over an i32 scrutinee.
//
// match.match is a high-level, declarative op: it describes a scrutinee, a set
// of arms and a default region, and a later lowering pass turns it into the
// branch structure that actually decides which arm runs. The example below
// classifies a value: negative arms yield -1, positive arms yield 1, and the
// default region yields 0.
//
// Layout: region 0 is the default, every following region is one arm. Each
// region is a single block terminated by match.yield (written explicitly here
// because the generic parser does not insert implicit terminators). A guard
// op refines when an arm applies; the default region carries none.
module {
  func.func @classify(%x: i32) -> i32 {
    %c0 = arith.constant 0 : i32
    %c1 = arith.constant 1 : i32
    %neg1 = arith.constant -1 : i32

    %result = "match.match"(%x) ({
      // default region: no guard, applies when no arm matches
      ^bb0:
        "match.yield"(%c0) : (i32) -> ()
    }, {
      // arm: x > 0
      ^bb0:
        %is_pos = arith.cmpi sgt, %x, %c0 : i32
        "match.guard"(%is_pos) : (i1) -> ()
        "match.yield"(%c1) : (i32) -> ()
    }, {
      // arm: x < 0
      ^bb0:
        %is_neg = arith.cmpi slt, %x, %c0 : i32
        "match.guard"(%is_neg) : (i1) -> ()
        "match.yield"(%neg1) : (i32) -> ()
    }) : (i32) -> (i32)
    return %result : i32
  }
}
