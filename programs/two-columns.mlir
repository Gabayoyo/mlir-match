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

// ==== expected output: build/bin/match-opt -convert-match-to-scf ====
// module {
//   func.func @matrix(%arg0: !match.pair<!match.option<i32>, !match.option<i32>>) -> i32 {
//     %c0_i32 = arith.constant 0 : i32
//     %matched, %fields:2 = match.deconstruct %arg0, "pair" : !match.pair<!match.option<i32>, !match.option<i32>> -> (i1, !match.option<i32>, !match.option<i32>)
//     %matched_0, %fields_1 = match.deconstruct %fields#0, "some" : !match.option<i32> -> (i1, i32)
//     %true = arith.constant true
//     %0 = arith.andi %matched_0, %true : i1
//     %1 = arith.andi %matched, %0 : i1
//     %matched_2, %fields_3 = match.deconstruct %fields#1, "some" : !match.option<i32> -> (i1, i32)
//     %true_4 = arith.constant true
//     %2 = arith.andi %matched_2, %true_4 : i1
//     %3 = arith.andi %1, %2 : i1
//     %4 = scf.if %3 -> (i32) {
//       %5 = arith.addi %fields_1, %fields_3 : i32
//       scf.yield %5 : i32
//     } else {
//       %matched_5, %fields_6:2 = match.deconstruct %arg0, "pair" : !match.pair<!match.option<i32>, !match.option<i32>> -> (i1, !match.option<i32>, !match.option<i32>)
//       %matched_7, %fields_8 = match.deconstruct %fields_6#0, "some" : !match.option<i32> -> (i1, i32)
//       %true_9 = arith.constant true
//       %5 = arith.andi %matched_7, %true_9 : i1
//       %6 = arith.andi %matched_5, %5 : i1
//       %matched_10 = match.deconstruct %fields_6#1, "none" : !match.option<i32> -> (i1)
//       %7 = arith.andi %6, %matched_10 : i1
//       %8 = scf.if %7 -> (i32) {
//         scf.yield %fields_8 : i32
//       } else {
//         %matched_11, %fields_12:2 = match.deconstruct %arg0, "pair" : !match.pair<!match.option<i32>, !match.option<i32>> -> (i1, !match.option<i32>, !match.option<i32>)
//         %matched_13 = match.deconstruct %fields_12#0, "none" : !match.option<i32> -> (i1)
//         %9 = arith.andi %matched_11, %matched_13 : i1
//         %matched_14, %fields_15 = match.deconstruct %fields_12#1, "some" : !match.option<i32> -> (i1, i32)
//         %true_16 = arith.constant true
//         %10 = arith.andi %matched_14, %true_16 : i1
//         %11 = arith.andi %9, %10 : i1
//         %12 = scf.if %11 -> (i32) {
//           scf.yield %fields_15 : i32
//         } else {
//           %matched_17, %fields_18:2 = match.deconstruct %arg0, "pair" : !match.pair<!match.option<i32>, !match.option<i32>> -> (i1, !match.option<i32>, !match.option<i32>)
//           %matched_19 = match.deconstruct %fields_18#0, "none" : !match.option<i32> -> (i1)
//           %13 = arith.andi %matched_17, %matched_19 : i1
//           %matched_20 = match.deconstruct %fields_18#1, "none" : !match.option<i32> -> (i1)
//           %14 = arith.andi %13, %matched_20 : i1
//           %15 = scf.if %14 -> (i32) {
//             scf.yield %c0_i32 : i32
//           } else {
//             scf.yield %c0_i32 : i32
//           }
//           scf.yield %15 : i32
//         }
//         scf.yield %12 : i32
//       }
//       scf.yield %8 : i32
//     }
//     return %4 : i32
//   }
//   func.func @with_default(%arg0: !match.pair<!match.option<i32>, !match.option<i32>>) -> i32 {
//     %c0_i32 = arith.constant 0 : i32
//     %matched, %fields:2 = match.deconstruct %arg0, "pair" : !match.pair<!match.option<i32>, !match.option<i32>> -> (i1, !match.option<i32>, !match.option<i32>)
//     %matched_0, %fields_1 = match.deconstruct %fields#0, "some" : !match.option<i32> -> (i1, i32)
//     %true = arith.constant true
//     %0 = arith.andi %matched_0, %true : i1
//     %1 = arith.andi %matched, %0 : i1
//     %matched_2 = match.deconstruct %fields#1, "none" : !match.option<i32> -> (i1)
//     %2 = arith.andi %1, %matched_2 : i1
//     %3 = scf.if %2 -> (i32) {
//       scf.yield %fields_1 : i32
//     } else {
//       %matched_3, %fields_4:2 = match.deconstruct %arg0, "pair" : !match.pair<!match.option<i32>, !match.option<i32>> -> (i1, !match.option<i32>, !match.option<i32>)
//       %true_5 = arith.constant true
//       %4 = arith.andi %matched_3, %true_5 : i1
//       %true_6 = arith.constant true
//       %5 = arith.andi %4, %true_6 : i1
//       %6 = scf.if %5 -> (i32) {
//         %c9_i32 = arith.constant 9 : i32
//         scf.yield %c9_i32 : i32
//       } else {
//         scf.yield %c0_i32 : i32
//       }
//       scf.yield %6 : i32
//     }
//     return %3 : i32
//   }
// }

// ==== expected output: build/bin/match-opt (round-trip) ====
// module {
//   func.func @matrix(%arg0: !match.pair<!match.option<i32>, !match.option<i32>>) -> i32 {
//     %c0_i32 = arith.constant 0 : i32
//     %0 = match.match {patterns = [#match.pattern<"pair" (#match.pattern<"some" (#match.pattern<"bind">)>, #match.pattern<"some" (#match.pattern<"bind">)>)>, #match.pattern<"pair" (#match.pattern<"some" (#match.pattern<"bind">)>, #match.pattern<"none">)>, #match.pattern<"pair" (#match.pattern<"none">, #match.pattern<"some" (#match.pattern<"bind">)>)>, #match.pattern<"pair" (#match.pattern<"none">, #match.pattern<"none">)>]} %arg0 : !match.pair<!match.option<i32>, !match.option<i32>> -> i32
//     case (%arg1: i32, %arg2: i32) {
//       %1 = arith.addi %arg1, %arg2 : i32
//       match.yield %1 : i32
//     }
//     case (%arg1: i32) {
//       match.yield %arg1 : i32
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
//   func.func @with_default(%arg0: !match.pair<!match.option<i32>, !match.option<i32>>) -> i32 {
//     %c0_i32 = arith.constant 0 : i32
//     %0 = match.match {patterns = [#match.pattern<"pair" (#match.pattern<"some" (#match.pattern<"bind">)>, #match.pattern<"none">)>, #match.pattern<"pair" (#match.pattern<"wildcard">, #match.pattern<"wildcard">)>]} %arg0 : !match.pair<!match.option<i32>, !match.option<i32>> -> i32
//     case (%arg1: i32) {
//       match.yield %arg1 : i32
//     }
//     case {
//       %c9_i32 = arith.constant 9 : i32
//       match.yield %c9_i32 : i32
//     }
//     default {
//       match.yield %c0_i32 : i32
//     }
//     return %0 : i32
//   }
// }
