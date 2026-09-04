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

// ==== expected output: build/bin/match-opt -convert-match-to-scf ====
// module {
//   func.func @classify_literal(%arg0: !match.option<i32>) -> i32 {
//     %c0_i32 = arith.constant 0 : i32
//     %c2_i32 = arith.constant 2 : i32
//     %c10_i32 = arith.constant 10 : i32
//     %matched, %fields = match.deconstruct %arg0, "some" : !match.option<i32> -> (i1, i32)
//     %c1_i32 = arith.constant 1 : i32
//     %0 = arith.cmpi eq, %fields, %c1_i32 : i32
//     %1 = arith.andi %matched, %0 : i1
//     %2 = scf.if %1 -> (i32) {
//       scf.yield %c10_i32 : i32
//     } else {
//       %matched_0, %fields_1 = match.deconstruct %arg0, "some" : !match.option<i32> -> (i1, i32)
//       %true = arith.constant true
//       %3 = arith.andi %matched_0, %true : i1
//       %4 = scf.if %3 -> (i32) {
//         %5 = arith.muli %fields_1, %c2_i32 : i32
//         scf.yield %5 : i32
//       } else {
//         %matched_2 = match.deconstruct %arg0, "none" : !match.option<i32> -> (i1)
//         %5 = scf.if %matched_2 -> (i32) {
//           scf.yield %c0_i32 : i32
//         } else {
//           scf.yield %c0_i32 : i32
//         }
//         scf.yield %5 : i32
//       }
//       scf.yield %4 : i32
//     }
//     return %2 : i32
//   }
//   func.func @guarded(%arg0: !match.option<i32>) -> i32 {
//     %c0_i32 = arith.constant 0 : i32
//     %c10_i32 = arith.constant 10 : i32
//     %matched, %fields = match.deconstruct %arg0, "some" : !match.option<i32> -> (i1, i32)
//     %true = arith.constant true
//     %0 = arith.andi %matched, %true : i1
//     %1 = arith.cmpi sgt, %fields, %c10_i32 : i32
//     %2 = arith.andi %0, %1 : i1
//     %3 = scf.if %2 -> (i32) {
//       scf.yield %fields : i32
//     } else {
//       scf.yield %c0_i32 : i32
//     }
//     return %3 : i32
//   }
// }

// ==== expected output: build/bin/match-opt (round-trip) ====
// module {
//   func.func @classify_literal(%arg0: !match.option<i32>) -> i32 {
//     %c0_i32 = arith.constant 0 : i32
//     %c2_i32 = arith.constant 2 : i32
//     %c10_i32 = arith.constant 10 : i32
//     %0 = match.match {patterns = [#match.pattern<"some" (#match.pattern<"literal", 1 : i32>)>, #match.pattern<"some" (#match.pattern<"bind">)>, #match.pattern<"none">]} %arg0 : !match.option<i32> -> i32
//     case {
//       match.yield %c10_i32 : i32
//     }
//     case (%arg1: i32) {
//       %1 = arith.muli %arg1, %c2_i32 : i32
//       match.yield %1 : i32
//     }
//     case {
//       match.yield %c0_i32 : i32
//     }
//     default {
//       match.yield %c0_i32 : i32
//     }
//     return %0 : i32
//   }
//   func.func @guarded(%arg0: !match.option<i32>) -> i32 {
//     %c0_i32 = arith.constant 0 : i32
//     %c10_i32 = arith.constant 10 : i32
//     %0 = match.match {patterns = [#match.pattern<"some" (#match.pattern<"bind">)>]} %arg0 : !match.option<i32> -> i32
//     case (%arg1: i32) {
//       %1 = arith.cmpi sgt, %arg1, %c10_i32 : i32
//       match.guard %1
//       match.yield %arg1 : i32
//     }
//     default {
//       match.yield %c0_i32 : i32
//     }
//     return %0 : i32
//   }
// }
