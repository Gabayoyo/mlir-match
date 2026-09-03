get_property(dialect_libs GLOBAL PROPERTY MLIR_DIALECT_LIBS)
get_property(conversion_libs GLOBAL PROPERTY MLIR_CONVERSION_LIBS)
get_property(extension_libs GLOBAL PROPERTY MLIR_EXTENSION_LIBS)

set(LIBS
  ${dialect_libs}
  ${conversion_libs}
  ${extension_libs}
  MLIRMlirOptMain
  MLIRSupport
  MLIRMatch
)

add_llvm_executable(match-opt match-opt.cpp)

llvm_update_compile_flags(match-opt)
target_link_libraries(match-opt PRIVATE ${LIBS})
mlir_check_all_link_libraries(match-opt)
