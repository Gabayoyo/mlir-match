cmake_minimum_required(VERSION 3.23)

if(POLICY CMP0116)
  cmake_policy(SET CMP0116 NEW)
endif()

project(mlir-match)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Consume the MLIR development package from the installed wheel. Point CMake at
# it at configure time with:  -DMLIR_DIR=<prefix>/lib/cmake/mlir
find_package(MLIR REQUIRED CONFIG)

message(STATUS "Using MLIRConfig.cmake in: ${MLIR_DIR}")
message(STATUS "Using LLVMConfig.cmake in: ${LLVM_DIR}")

# The MLIR package ships mlir-tblgen alongside the config; resolve it so our
# tablegen rules use the same toolchain as the imported MLIR headers.
set(MLIR_TABLEGEN_EXE "${MLIR_INSTALL_PREFIX}/bin/mlir-tblgen")
message(STATUS "Using mlir-tblgen: ${MLIR_TABLEGEN_EXE}")

set(LLVM_RUNTIME_OUTPUT_INTDIR ${CMAKE_BINARY_DIR}/bin)
set(LLVM_LIBRARY_OUTPUT_INTDIR ${CMAKE_BINARY_DIR}/lib)
set(MLIR_BINARY_DIR ${CMAKE_BINARY_DIR})

# Pull in the LLVM/MLIR cmake modules that provide tablegen(), mlir_tablegen()
# and add_mlir_dialect_library().
list(APPEND CMAKE_MODULE_PATH "${MLIR_CMAKE_DIR}")
list(APPEND CMAKE_MODULE_PATH "${LLVM_CMAKE_DIR}")

include(TableGen)
include(AddLLVM)
include(AddMLIR)
include(HandleLLVMOptions)

include_directories(${LLVM_INCLUDE_DIRS})
include_directories(${MLIR_INCLUDE_DIRS})
include_directories(${PROJECT_SOURCE_DIR}/include)
include_directories(${PROJECT_BINARY_DIR}/include)

add_subdirectory(include/Match)
add_subdirectory(lib/Match)
