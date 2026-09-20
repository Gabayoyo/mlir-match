// Bench driver for the `nested` family: the scrutinee is an
// option<option<i32>>. __ITERS__ is substituted by tools/bench/run.sh.

llvm.mlir.global internal constant @fmt("sum=%d\0A\00") : !llvm.array<8 x i8>
llvm.func @printf(!llvm.ptr, ...) -> i32

llvm.func @main() -> i32 {
  %fmt = llvm.mlir.addressof @fmt : !llvm.ptr
  %c0 = llvm.mlir.constant(0 : i32) : i32
  %c1 = llvm.mlir.constant(1 : i32) : i32
  %c3 = llvm.mlir.constant(3 : i32) : i32
  %c4 = llvm.mlir.constant(4 : i32) : i32
  %c16 = llvm.mlir.constant(16 : i32) : i32
  %n = llvm.mlir.constant(__ITERS__ : i32) : i32
  llvm.br ^loop(%c0, %c0 : i32, i32)

^loop(%i: i32, %acc: i32):
  %done = llvm.icmp "sge" %i, %n : i32
  llvm.cond_br %done, ^exit, ^body

^body:
  %mix = llvm.add %i, %acc : i32
  // one in four is an outer none, and one in three carries an inner none
  %r4 = llvm.srem %mix, %c4 : i32
  %outer_none = llvm.icmp "eq" %r4, %c0 : i32
  %outer_tag = llvm.select %outer_none, %c1, %c0 : i1, i32
  %r3 = llvm.srem %mix, %c3 : i32
  %inner_none = llvm.icmp "eq" %r3, %c0 : i32
  %inner_tag = llvm.select %inner_none, %c1, %c0 : i1, i32
  %payload = llvm.srem %mix, %c16 : i32
  %iu = llvm.mlir.undef : !llvm.struct<(i32, i32)>
  %ia = llvm.insertvalue %inner_tag, %iu[0] : !llvm.struct<(i32, i32)>
  %inner = llvm.insertvalue %payload, %ia[1] : !llvm.struct<(i32, i32)>
  %ou = llvm.mlir.undef : !llvm.struct<(i32, struct<(i32, i32)>)>
  %oa = llvm.insertvalue %outer_tag, %ou[0] : !llvm.struct<(i32, struct<(i32, i32)>)>
  %ov = llvm.insertvalue %inner, %oa[1] : !llvm.struct<(i32, struct<(i32, i32)>)>
  %r = llvm.call @classify(%ov) : (!llvm.struct<(i32, struct<(i32, i32)>)>) -> i32
  %acc2 = llvm.add %acc, %r : i32
  %inext = llvm.add %i, %c1 : i32
  llvm.br ^loop(%inext, %acc2 : i32, i32)

^exit:
  %p = llvm.call @printf(%fmt, %acc) vararg(!llvm.func<i32 (!llvm.ptr, ...)>) : (!llvm.ptr, i32) -> i32
  llvm.return %c0 : i32
}
