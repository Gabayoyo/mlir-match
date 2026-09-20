// Driver for programs/two-columns.mlir, spliced into the lowered module by
// tools/run-program.sh. The pair is a struct of its two option fields, and each
// option is a tagged struct, so the values are inserted two levels deep.

llvm.mlir.global internal constant @fmt("matrix: %d %d %d %d | with_default: %d %d\0A\00") : !llvm.array<43 x i8>
llvm.func @printf(!llvm.ptr, ...) -> i32

llvm.func @main() -> i32 {
  %fmt = llvm.mlir.addressof @fmt : !llvm.ptr
  %zero = llvm.mlir.constant(0 : i32) : i32
  %one = llvm.mlir.constant(1 : i32) : i32
  %three = llvm.mlir.constant(3 : i32) : i32
  %four = llvm.mlir.constant(4 : i32) : i32
  %five = llvm.mlir.constant(5 : i32) : i32
  %six = llvm.mlir.constant(6 : i32) : i32

  %opt_undef = llvm.mlir.undef : !llvm.struct<(i32, i32)>
  %some = llvm.insertvalue %zero, %opt_undef[0] : !llvm.struct<(i32, i32)>
  %some3 = llvm.insertvalue %three, %some[1] : !llvm.struct<(i32, i32)>
  %some4 = llvm.insertvalue %four, %some[1] : !llvm.struct<(i32, i32)>
  %some5 = llvm.insertvalue %five, %some[1] : !llvm.struct<(i32, i32)>
  %some6 = llvm.insertvalue %six, %some[1] : !llvm.struct<(i32, i32)>
  %none = llvm.insertvalue %one, %opt_undef[0] : !llvm.struct<(i32, i32)>

  %pair_undef = llvm.mlir.undef : !llvm.struct<(struct<(i32, i32)>, struct<(i32, i32)>)>

  // (some 3, some 4) -> 7
  %p_ss_l = llvm.insertvalue %some3, %pair_undef[0] : !llvm.struct<(struct<(i32, i32)>, struct<(i32, i32)>)>
  %p_ss = llvm.insertvalue %some4, %p_ss_l[1] : !llvm.struct<(struct<(i32, i32)>, struct<(i32, i32)>)>
  // (some 3, none) -> 3
  %p_sn_l = llvm.insertvalue %some3, %pair_undef[0] : !llvm.struct<(struct<(i32, i32)>, struct<(i32, i32)>)>
  %p_sn = llvm.insertvalue %none, %p_sn_l[1] : !llvm.struct<(struct<(i32, i32)>, struct<(i32, i32)>)>
  // (none, some 4) -> 4
  %p_ns_l = llvm.insertvalue %none, %pair_undef[0] : !llvm.struct<(struct<(i32, i32)>, struct<(i32, i32)>)>
  %p_ns = llvm.insertvalue %some4, %p_ns_l[1] : !llvm.struct<(struct<(i32, i32)>, struct<(i32, i32)>)>
  // (none, none) -> 0
  %p_nn_l = llvm.insertvalue %none, %pair_undef[0] : !llvm.struct<(struct<(i32, i32)>, struct<(i32, i32)>)>
  %p_nn = llvm.insertvalue %none, %p_nn_l[1] : !llvm.struct<(struct<(i32, i32)>, struct<(i32, i32)>)>
  // (some 5, none) -> 5, and (some 5, some 6) -> 9 for the wildcard row
  %p_sn5_l = llvm.insertvalue %some5, %pair_undef[0] : !llvm.struct<(struct<(i32, i32)>, struct<(i32, i32)>)>
  %p_sn5 = llvm.insertvalue %none, %p_sn5_l[1] : !llvm.struct<(struct<(i32, i32)>, struct<(i32, i32)>)>
  %p_ss5_l = llvm.insertvalue %some5, %pair_undef[0] : !llvm.struct<(struct<(i32, i32)>, struct<(i32, i32)>)>
  %p_ss5 = llvm.insertvalue %some6, %p_ss5_l[1] : !llvm.struct<(struct<(i32, i32)>, struct<(i32, i32)>)>

  %m_ss = llvm.call @matrix(%p_ss) : (!llvm.struct<(struct<(i32, i32)>, struct<(i32, i32)>)>) -> i32
  %m_sn = llvm.call @matrix(%p_sn) : (!llvm.struct<(struct<(i32, i32)>, struct<(i32, i32)>)>) -> i32
  %m_ns = llvm.call @matrix(%p_ns) : (!llvm.struct<(struct<(i32, i32)>, struct<(i32, i32)>)>) -> i32
  %m_nn = llvm.call @matrix(%p_nn) : (!llvm.struct<(struct<(i32, i32)>, struct<(i32, i32)>)>) -> i32
  %d_sn = llvm.call @with_default(%p_sn5) : (!llvm.struct<(struct<(i32, i32)>, struct<(i32, i32)>)>) -> i32
  %d_ss = llvm.call @with_default(%p_ss5) : (!llvm.struct<(struct<(i32, i32)>, struct<(i32, i32)>)>) -> i32

  %p = llvm.call @printf(%fmt, %m_ss, %m_sn, %m_ns, %m_nn, %d_sn, %d_ss) vararg(!llvm.func<i32 (!llvm.ptr, ...)>) : (!llvm.ptr, i32, i32, i32, i32, i32, i32) -> i32
  llvm.return %zero : i32
}
