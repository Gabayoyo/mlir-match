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

// ==== expected output: build/bin/match-opt -convert-match-to-scf ====
// module {
//   func.func @unwrap_twice(%arg0: !match.option<!match.option<i32>>) -> i32 {
//     %c0_i32 = arith.constant 0 : i32
//     %c1_i32 = arith.constant 1 : i32
//     %matched, %fields = match.deconstruct %arg0, "some" : !match.option<!match.option<i32>> -> (i1, !match.option<i32>)
//     %matched_0, %fields_1 = match.deconstruct %fields, "some" : !match.option<i32> -> (i1, i32)
//     %true = arith.constant true
//     %0 = arith.andi %matched_0, %true : i1
//     %1 = arith.andi %matched, %0 : i1
//     %2 = scf.if %1 -> (i32) {
//       scf.yield %fields_1 : i32
//     } else {
//       %matched_2, %fields_3 = match.deconstruct %arg0, "some" : !match.option<!match.option<i32>> -> (i1, !match.option<i32>)
//       %matched_4 = match.deconstruct %fields_3, "none" : !match.option<i32> -> (i1)
//       %3 = arith.andi %matched_2, %matched_4 : i1
//       %4 = scf.if %3 -> (i32) {
//         scf.yield %c1_i32 : i32
//       } else {
//         %matched_5 = match.deconstruct %arg0, "none" : !match.option<!match.option<i32>> -> (i1)
//         %5 = scf.if %matched_5 -> (i32) {
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
//   func.func @order_matters(%arg0: !match.option<!match.option<i32>>) -> i32 {
//     %c0_i32 = arith.constant 0 : i32
//     %matched, %fields = match.deconstruct %arg0, "some" : !match.option<!match.option<i32>> -> (i1, !match.option<i32>)
//     %matched_0 = match.deconstruct %fields, "none" : !match.option<i32> -> (i1)
//     %0 = arith.andi %matched, %matched_0 : i1
//     %1 = scf.if %0 -> (i32) {
//       scf.yield %c0_i32 : i32
//     } else {
//       %matched_1, %fields_2 = match.deconstruct %arg0, "some" : !match.option<!match.option<i32>> -> (i1, !match.option<i32>)
//       %matched_3, %fields_4 = match.deconstruct %fields_2, "some" : !match.option<i32> -> (i1, i32)
//       %true = arith.constant true
//       %2 = arith.andi %matched_3, %true : i1
//       %3 = arith.andi %matched_1, %2 : i1
//       %4 = scf.if %3 -> (i32) {
//         scf.yield %fields_4 : i32
//       } else {
//         %matched_5 = match.deconstruct %arg0, "none" : !match.option<!match.option<i32>> -> (i1)
//         %5 = scf.if %matched_5 -> (i32) {
//           scf.yield %c0_i32 : i32
//         } else {
//           scf.yield %c0_i32 : i32
//         }
//         scf.yield %5 : i32
//       }
//       scf.yield %4 : i32
//     }
//     return %1 : i32
//   }
// }

// ==== expected output: build/bin/match-opt (round-trip) ====
// module {
//   func.func @unwrap_twice(%arg0: !match.option<!match.option<i32>>) -> i32 {
//     %c0_i32 = arith.constant 0 : i32
//     %c1_i32 = arith.constant 1 : i32
//     %0 = match.match {patterns = [#match.pattern<"some" (#match.pattern<"some" (#match.pattern<"bind">)>)>, #match.pattern<"some" (#match.pattern<"none">)>, #match.pattern<"none">]} %arg0 : !match.option<!match.option<i32>> -> i32
//     case (%arg1: i32) {
//       match.yield %arg1 : i32
//     }
//     case {
//       match.yield %c1_i32 : i32
//     }
//     case {
//       match.yield %c0_i32 : i32
//     }
//     default {
//       match.yield %c0_i32 : i32
//     }
//     return %0 : i32
//   }
//   func.func @order_matters(%arg0: !match.option<!match.option<i32>>) -> i32 {
//     %c0_i32 = arith.constant 0 : i32
//     %0 = match.match {patterns = [#match.pattern<"some" (#match.pattern<"none">)>, #match.pattern<"some" (#match.pattern<"some" (#match.pattern<"bind">)>)>, #match.pattern<"none">]} %arg0 : !match.option<!match.option<i32>> -> i32
//     case {
//       match.yield %c0_i32 : i32
//     }
//     case (%arg1: i32) {
//       match.yield %arg1 : i32
//     }
//     case {
//       match.yield %c0_i32 : i32
//     }
//     default {
//       match.yield %c0_i32 : i32
//     }
//     return %0 : i32
//   }
// }
