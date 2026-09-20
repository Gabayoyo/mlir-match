// Bench driver for the `literals` family: the scrutinee is an option<i32>.
// __ITERS__ is substituted by tools/bench/run.sh.
//
// The input of each iteration depends on the accumulator, so the loop carries a
// dependency and neither lowering gets vectorised or folded away more than the
// other.

llvm.mlir.global internal constant @fmt("sum=%d\0A\00") : !llvm.array<8 x i8>
llvm.func @printf(!llvm.ptr, ...) -> i32

llvm.func @main() -> i32 {
  %fmt = llvm.mlir.addressof @fmt : !llvm.ptr
  %c0 = llvm.mlir.constant(0 : i32) : i32
  %c1 = llvm.mlir.constant(1 : i32) : i32
  %c5 = llvm.mlir.constant(5 : i32) : i32
  %c16 = llvm.mlir.constant(16 : i32) : i32
  %n = llvm.mlir.constant(__ITERS__ : i32) : i32
  llvm.br ^loop(%c0, %c0 : i32, i32)

^loop(%i: i32, %acc: i32):
  %done = llvm.icmp "sge" %i, %n : i32
  llvm.cond_br %done, ^exit, ^body

^body:
  %mix = llvm.add %i, %acc : i32
  // one value in five is none, the rest carry a payload 0..15
  %r5 = llvm.srem %mix, %c5 : i32
  %is_none = llvm.icmp "eq" %r5, %c0 : i32
  %tag = llvm.select %is_none, %c1, %c0 : i1, i32
  %payload = llvm.srem %mix, %c16 : i32
  %ou = llvm.mlir.undef : !llvm.struct<(i32, i32)>
  %oa = llvm.insertvalue %tag, %ou[0] : !llvm.struct<(i32, i32)>
  %ov = llvm.insertvalue %payload, %oa[1] : !llvm.struct<(i32, i32)>
  %r = llvm.call @classify(%ov) : (!llvm.struct<(i32, i32)>) -> i32
  %acc2 = llvm.add %acc, %r : i32
  %inext = llvm.add %i, %c1 : i32
  llvm.br ^loop(%inext, %acc2 : i32, i32)

^exit:
  %p = llvm.call @printf(%fmt, %acc) vararg(!llvm.func<i32 (!llvm.ptr, ...)>) : (!llvm.ptr, i32) -> i32
  llvm.return %c0 : i32
}
