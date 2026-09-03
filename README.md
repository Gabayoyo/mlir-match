# mlir-match
An out-of-tree MLIR dialect for the optimisation of pattern matching constructs/abstractions.

## Building

The MLIR development package is consumed from the Python wheel in `.venv`:

```bash
cmake -S . -B build -G Ninja \
  -DMLIR_DIR=$PWD/.venv/lib/python3.12/site-packages/mlir_wheel/lib/cmake/mlir \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

## Running

`match-opt` is an `mlir-opt`-style driver for the dialect; example programs live
under `programs/`:

```bash
build/bin/match-opt programs/simple.mlir
```

## Testing

`lit` tests live under `test/`:

```bash
ninja -C build check-mlir-match
```
