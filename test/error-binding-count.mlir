// RUN: %not %matchopt %s 2>&1 | %FileCheck %s

// A "bind" pattern binds one value, so its arm must declare one entry block
// argument; here it declares none.
module {
  func.func @bad_binding(%x: i32) -> i32 {
    %c0 = arith.constant 0 : i32

    %result = match.match {patterns = [#match.pattern<"bind">]} %x : i32 -> i32
      case {
        match.yield %x : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %result : i32
  }
}

// CHECK: error: 'match.match' op arm 0 expects 1 binding(s) but has 0 block argument(s)
