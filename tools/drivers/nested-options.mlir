// Driver for programs/nested-options.mlir, spliced into the lowered module by
// tools/run-program.sh. The scrutinee is an option whose payload is another
// option, so the value is a struct that nests a tagged struct in slot 1.

llvm.mlir.global internal constant @fmt("unwrap: %d %d %d | order: %d %d %d\0A\00") : !llvm.array<36 x i8>
llvm.func @printf(!llvm.ptr, ...) -> i32

llvm.func @main() -> i32 {
  %fmt = llvm.mlir.addressof @fmt : !llvm.ptr
  %zero = llvm.mlir.constant(0 : i32) : i32
  %one = llvm.mlir.constant(1 : i32) : i32
  %seven = llvm.mlir.constant(7 : i32) : i32

  %inner_undef = llvm.mlir.undef : !llvm.struct<(i32, i32)>
  %inner_some = llvm.insertvalue %zero, %inner_undef[0] : !llvm.struct<(i32, i32)>
  %inner_some7 = llvm.insertvalue %seven, %inner_some[1] : !llvm.struct<(i32, i32)>
  %inner_none = llvm.insertvalue %one, %inner_undef[0] : !llvm.struct<(i32, i32)>

  %outer_undef = llvm.mlir.undef : !llvm.struct<(i32, struct<(i32, i32)>)>
  %outer_base = llvm.insertvalue %zero, %outer_undef[0] : !llvm.struct<(i32, struct<(i32, i32)>)>
  %outer_none = llvm.insertvalue %one, %outer_undef[0] : !llvm.struct<(i32, struct<(i32, i32)>)>

  // some(some(7)) -> 7, some(none) -> 1, none -> 0
  %ss = llvm.insertvalue %inner_some7, %outer_base[1] : !llvm.struct<(i32, struct<(i32, i32)>)>
  %sn = llvm.insertvalue %inner_none, %outer_base[1] : !llvm.struct<(i32, struct<(i32, i32)>)>

  %u_ss = llvm.call @unwrap_twice(%ss) : (!llvm.struct<(i32, struct<(i32, i32)>)>) -> i32
  %u_sn = llvm.call @unwrap_twice(%sn) : (!llvm.struct<(i32, struct<(i32, i32)>)>) -> i32
  %u_n = llvm.call @unwrap_twice(%outer_none) : (!llvm.struct<(i32, struct<(i32, i32)>)>) -> i32

  // The same rows in the other order, where some(none) is tested first.
  %o_sn = llvm.call @order_matters(%sn) : (!llvm.struct<(i32, struct<(i32, i32)>)>) -> i32
  %o_ss = llvm.call @order_matters(%ss) : (!llvm.struct<(i32, struct<(i32, i32)>)>) -> i32
  %o_n = llvm.call @order_matters(%outer_none) : (!llvm.struct<(i32, struct<(i32, i32)>)>) -> i32

  %p = llvm.call @printf(%fmt, %u_ss, %u_sn, %u_n, %o_sn, %o_ss, %o_n) vararg(!llvm.func<i32 (!llvm.ptr, ...)>) : (!llvm.ptr, i32, i32, i32, i32, i32, i32) -> i32
  llvm.return %zero : i32
}
