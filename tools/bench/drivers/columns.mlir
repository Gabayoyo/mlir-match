// Bench driver for the `columns` family: the scrutinee is a pair of options.
// __ITERS__ is substituted by tools/bench/run.sh.

llvm.mlir.global internal constant @fmt("sum=%d\0A\00") : !llvm.array<8 x i8>
llvm.func @printf(!llvm.ptr, ...) -> i32

llvm.func @main() -> i32 {
  %fmt = llvm.mlir.addressof @fmt : !llvm.ptr
  %c0 = llvm.mlir.constant(0 : i32) : i32
  %c1 = llvm.mlir.constant(1 : i32) : i32
  %c3 = llvm.mlir.constant(3 : i32) : i32
  %c4 = llvm.mlir.constant(4 : i32) : i32
  %c5 = llvm.mlir.constant(5 : i32) : i32
  %c7 = llvm.mlir.constant(7 : i32) : i32
  %n = llvm.mlir.constant(__ITERS__ : i32) : i32
  llvm.br ^loop(%c0, %c0 : i32, i32)

^loop(%i: i32, %acc: i32):
  %done = llvm.icmp "sge" %i, %n : i32
  llvm.cond_br %done, ^exit, ^body

^body:
  %mix = llvm.add %i, %acc : i32
  // the two columns take independent tags and payloads
  %l5 = llvm.srem %mix, %c5 : i32
  %l_none = llvm.icmp "eq" %l5, %c0 : i32
  %l_tag = llvm.select %l_none, %c1, %c0 : i1, i32
  %l_payload = llvm.srem %mix, %c3 : i32
  %r7 = llvm.srem %mix, %c7 : i32
  %r_none = llvm.icmp "eq" %r7, %c0 : i32
  %r_tag = llvm.select %r_none, %c1, %c0 : i1, i32
  %r_payload = llvm.srem %mix, %c4 : i32

  %ou = llvm.mlir.undef : !llvm.struct<(i32, i32)>
  %la = llvm.insertvalue %l_tag, %ou[0] : !llvm.struct<(i32, i32)>
  %left = llvm.insertvalue %l_payload, %la[1] : !llvm.struct<(i32, i32)>
  %ra = llvm.insertvalue %r_tag, %ou[0] : !llvm.struct<(i32, i32)>
  %right = llvm.insertvalue %r_payload, %ra[1] : !llvm.struct<(i32, i32)>
  %pu = llvm.mlir.undef : !llvm.struct<(struct<(i32, i32)>, struct<(i32, i32)>)>
  %pl = llvm.insertvalue %left, %pu[0] : !llvm.struct<(struct<(i32, i32)>, struct<(i32, i32)>)>
  %pv = llvm.insertvalue %right, %pl[1] : !llvm.struct<(struct<(i32, i32)>, struct<(i32, i32)>)>
  %r = llvm.call @classify(%pv) : (!llvm.struct<(struct<(i32, i32)>, struct<(i32, i32)>)>) -> i32
  %acc2 = llvm.add %acc, %r : i32
  %inext = llvm.add %i, %c1 : i32
  llvm.br ^loop(%inext, %acc2 : i32, i32)

^exit:
  %p = llvm.call @printf(%fmt, %acc) vararg(!llvm.func<i32 (!llvm.ptr, ...)>) : (!llvm.ptr, i32) -> i32
  llvm.return %c0 : i32
}
