// Driver for programs/simple.mlir, spliced into the lowered module by
// tools/run-program.sh. The scrutinee is a plain i32, so there is nothing to
// construct: the three calls cover the positive, zero and negative cases.

llvm.mlir.global internal constant @fmt("classify: %d %d %d\0A\00") : !llvm.array<20 x i8>
llvm.func @printf(!llvm.ptr, ...) -> i32

llvm.func @main() -> i32 {
  %fmt = llvm.mlir.addressof @fmt : !llvm.ptr
  %neg3 = llvm.mlir.constant(-3 : i32) : i32
  %zero = llvm.mlir.constant(0 : i32) : i32
  %five = llvm.mlir.constant(5 : i32) : i32

  %a = llvm.call @classify(%neg3) : (i32) -> i32
  %b = llvm.call @classify(%zero) : (i32) -> i32
  %c = llvm.call @classify(%five) : (i32) -> i32

  %p = llvm.call @printf(%fmt, %a, %b, %c) vararg(!llvm.func<i32 (!llvm.ptr, ...)>) : (!llvm.ptr, i32, i32, i32) -> i32
  llvm.return %zero : i32
}
