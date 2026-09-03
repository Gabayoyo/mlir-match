// RUN: %matchopt %s | %FileCheck %s

// Matching on !match.pair<i32, i64>: "pair" is the type's single constructor,
// deconstructing into its two fields. The case header declares the two
// bindings, whose types must match the field types the verifier derives.
module {
  func.func @pair_fields(%v: !match.pair<i32, i64>) -> i64 {
    %c0 = arith.constant 0 : i64

    %result = match.match {patterns = [#match.pattern<"pair"(#match.pattern<"bind">, #match.pattern<"bind">)>]} %v : !match.pair<i32, i64> -> i64
      case (%left: i32, %right: i64) {
        %wide = arith.extsi %left : i32 to i64
        %sum = arith.addi %wide, %right : i64
        match.yield %sum : i64
      }
      default {
        match.yield %c0 : i64
      }
    return %result : i64
  }

  // Two columns at once: each row's pattern deconstructs the same pair into
  // its two option fields, so arms bind 2, 1, 1, or 0 values depending on how
  // many "some" payloads the row keeps. This is the matrix shape a decision
  // tree later optimises.
  func.func @two_columns(%v: !match.pair<!match.option<i32>, !match.option<i32>>) -> i32 {
    %c0 = arith.constant 0 : i32
    %c1 = arith.constant 1 : i32
    %c2 = arith.constant 2 : i32
    %c3 = arith.constant 3 : i32

    %result = match.match {patterns = [
      #match.pattern<"pair"(#match.pattern<"some"(#match.pattern<"bind">)>, #match.pattern<"some"(#match.pattern<"bind">)>)>,
      #match.pattern<"pair"(#match.pattern<"some"(#match.pattern<"bind">)>, #match.pattern<"none">)>,
      #match.pattern<"pair"(#match.pattern<"none">, #match.pattern<"some"(#match.pattern<"bind">)>)>,
      #match.pattern<"pair"(#match.pattern<"none">, #match.pattern<"none">)>
    ]} %v : !match.pair<!match.option<i32>, !match.option<i32>> -> i32
      case (%l: i32, %r1: i32) {
        match.yield %c1 : i32
      }
      case (%l: i32) {
        match.yield %c2 : i32
      }
      case (%r1: i32) {
        match.yield %c2 : i32
      }
      case {
        match.yield %c3 : i32
      }
      default {
        match.yield %c0 : i32
      }
    return %result : i32
  }
}

// CHECK: func.func @pair_fields
// CHECK: match.match {patterns = [#match.pattern<"pair" (#match.pattern<"bind">, #match.pattern<"bind">)>]} %arg0 : !match.pair<i32, i64> -> i64
// CHECK: case (%[[L:arg[0-9]+]]: i32, %[[R:arg[0-9]+]]: i64) {
// CHECK-NOT: ^bb0
// CHECK: %[[W:.*]] = arith.extsi %[[L]] : i32 to i64
// CHECK: %[[S:.*]] = arith.addi %[[W]], %[[R]] : i64
// CHECK: match.yield %[[S]] : i64
// CHECK: default {

// CHECK: func.func @two_columns
// CHECK: match.match {patterns = [#match.pattern<"pair" (#match.pattern<"some" (#match.pattern<"bind">)>, #match.pattern<"some" (#match.pattern<"bind">)>)>,
// CHECK: #match.pattern<"pair" (#match.pattern<"some" (#match.pattern<"bind">)>, #match.pattern<"none">)>,
// CHECK: #match.pattern<"pair" (#match.pattern<"none">, #match.pattern<"some" (#match.pattern<"bind">)>)>,
// CHECK: #match.pattern<"pair" (#match.pattern<"none">, #match.pattern<"none">)>]} %arg0 : !match.pair<!match.option<i32>, !match.option<i32>> -> i32
// CHECK: case (%[[L1:arg[0-9]+]]: i32, %[[R1:arg[0-9]+]]: i32) {
// CHECK-NOT: ^bb0
// CHECK: match.yield %c1_i32 : i32
// CHECK: case (%[[L2:arg[0-9]+]]: i32) {
// CHECK: match.yield %c2_i32 : i32
// CHECK: case (%[[R2:arg[0-9]+]]: i32) {
// CHECK: case {
// CHECK: default {
