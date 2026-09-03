// A minimal match.match over an i32 scrutinee: positive arms yield 1, negative
// arms yield -1, and the default region yields 0.
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
