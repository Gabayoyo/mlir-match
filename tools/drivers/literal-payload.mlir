// Driver for programs/literal-payload.mlir, spliced into the lowered module by
// tools/run-program.sh. An option value is a struct whose slot 0 holds the tag
// (`some` = 0, `none` = 1) and whose slot 1 holds the payload, so the driver
// builds the values the same way the lowered code reads them.

llvm.mlir.global internal constant @fmt_lit("classify_literal: %d %d %d\0A\00") : !llvm.array<28 x i8>
llvm.mlir.global internal constant @fmt_grd("guarded: %d %d %d\0A\00") : !llvm.array<19 x i8>
llvm.func @printf(!llvm.ptr, ...) -> i32

llvm.func @main() -> i32 {
  %fmt_lit = llvm.mlir.addressof @fmt_lit : !llvm.ptr
  %fmt_grd = llvm.mlir.addressof @fmt_grd : !llvm.ptr
  %zero = llvm.mlir.constant(0 : i32) : i32
  %one = llvm.mlir.constant(1 : i32) : i32
  %five = llvm.mlir.constant(5 : i32) : i32
  %nine = llvm.mlir.constant(9 : i32) : i32
  %twenty = llvm.mlir.constant(20 : i32) : i32
  %undef = llvm.mlir.undef : !llvm.struct<(i32, i32)>

  // some(1) -> 10, some(9) -> 18, none -> 0
  %some_tag = llvm.insertvalue %zero, %undef[0] : !llvm.struct<(i32, i32)>
  %some1 = llvm.insertvalue %one, %some_tag[1] : !llvm.struct<(i32, i32)>
  %some9 = llvm.insertvalue %nine, %some_tag[1] : !llvm.struct<(i32, i32)>
  %none = llvm.insertvalue %one, %undef[0] : !llvm.struct<(i32, i32)>

  %lit1 = llvm.call @classify_literal(%some1) : (!llvm.struct<(i32, i32)>) -> i32
  %lit9 = llvm.call @classify_literal(%some9) : (!llvm.struct<(i32, i32)>) -> i32
  %litn = llvm.call @classify_literal(%none) : (!llvm.struct<(i32, i32)>) -> i32
  %p1 = llvm.call @printf(%fmt_lit, %lit1, %lit9, %litn) vararg(!llvm.func<i32 (!llvm.ptr, ...)>) : (!llvm.ptr, i32, i32, i32) -> i32

  // some(20) -> 20, some(5) -> 0 (guard fails), none -> 0
  %some20 = llvm.insertvalue %twenty, %some_tag[1] : !llvm.struct<(i32, i32)>
  %some5 = llvm.insertvalue %five, %some_tag[1] : !llvm.struct<(i32, i32)>

  %grd20 = llvm.call @guarded(%some20) : (!llvm.struct<(i32, i32)>) -> i32
  %grd5 = llvm.call @guarded(%some5) : (!llvm.struct<(i32, i32)>) -> i32
  %grdn = llvm.call @guarded(%none) : (!llvm.struct<(i32, i32)>) -> i32
  %p2 = llvm.call @printf(%fmt_grd, %grd20, %grd5, %grdn) vararg(!llvm.func<i32 (!llvm.ptr, ...)>) : (!llvm.ptr, i32, i32, i32) -> i32

  llvm.return %zero : i32
}
