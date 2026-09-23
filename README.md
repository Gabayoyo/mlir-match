# mlir-match

An out-of-tree [MLIR](https://mlir.llvm.org/) dialect for representing functional pattern matching, compiled with Maranget-style decision trees for optimisation.

`match.match` groups a scrutinee with ordered `case` arms, each headed by optional structured pattern and guards, and a fallback `default` region.

## Example

Below is an example of matching an `option` value, with cases `some(1)`, `some(x)`, and `none`. The `match.match` op holds an attribute dictating what each arm's corresponding pattern is. Each arm can also specify a binding which is part of the condition to branch and is present in the body too:

```mlir
// high-level representation (scala-inspired)
//
// r match
//   case Some(1) => 10
//   case Some(x) => x * 2    // binding of x to arm body
//   case None => 0
//   case _ => 0

%r = match.match {patterns = [
  #match.pattern<"some"(#match.pattern<"literal", 1 : i32>)>,
  #match.pattern<"some"(#match.pattern<"bind">)>,
  #match.pattern<"none">
]} %v : !match.option<i32> -> i32
  case {
    match.yield %c10 : i32
  }
  case (%x: i32) {
    %twice = arith.muli %x, %c2 : i32
    match.yield %twice : i32
  }
  case {
    match.yield %c0 : i32
  }
  default {
    match.yield %c0 : i32
  }
```

The naive lowering gives each arm its own branch, re-asking "is this a `some`?" for every `some` row. The decision-tree/maranget pass restructures the match so this question is only asked once, reducing the total number of branches:

```mlir
// Arm-by-arm lowering would test `some` twice:
//   if some && payload == 1  -> 10
//   if some                  -> x * 2    // `some` asked again
//
// The decision tree asks `some` once; the second Some row rides the else:
%matched, %field = match.deconstruct %v, "some" : !match.option<i32> -> (i1, i32)
%r = scf.if %matched -> (i32) {
  // payload == 1 ? 10 : x * 2   // the Some(1) / Some(x) split
  ...
} else {
  // none arm and the default
  ...
}
```

## Quick start

Prerequisites:

- Python 3.12 with a virtual environment; `requirements.txt` installs the pinned `mlir-wheel` (the MLIR development package this project builds against), `cmake`, `ninja`, and `lit`.
- No system MLIR or LLVM build is needed for the pass; running a program through `tools/run.py` additionally needs a host `clang` (e.g. `brew install llvm`).

```bash
python -m venv .venv
.venv/bin/pip install -r requirements.txt

cmake -S . -B build -G Ninja \
  -DMLIR_DIR=$PWD/.venv/lib/python3.12/site-packages/mlir_wheel/lib/cmake/mlir \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

The wheel version is pinned in `requirements.txt`; the project tracks that snapshot of MLIR, and sources are formatted with `clang-format` using the repository's `.clang-format`.

## The dialect

All ops and types live in the `match` dialect and are printed with the `match.` prefix. The TableGen descriptions in `include/Match/*.td` are the canonical documentation for each op and type.

### Ops

| Op | Purpose |
| --- | --- |
| `match.match` | Groups a scrutinee value with `case` arms and a `default` region; selects the first arm whose pattern matches (and whose guard, if any, holds). |
| `match.guard` | Splits an arm into a condition computation and a body: the arm fires only when the guard condition is true. |
| `match.yield` | Terminates an arm or default region with the match's results. |
| `match.deconstruct` | The runtime primitive: tests a value's constructor and projects its fields. Emitted by lowering, and given a runtime representation by `-match-to-llvm`. |

A `case` header may declare the arm's bindings, which become the arm region's entry arguments:

```mlir
case (%x: i32) { ... }   // binds the payload of some(x)
```

### Patterns

Each arm carries a structured pattern attribute, `#match.pattern<...>`, which is data the lowering reads and reorders:

- `bind` / `wildcard` — match anything; a `bind` also captures the value as an arm binding.
- `literal` — matches a constant payload (e.g. `#match.pattern<"literal", 1 : i32>`).
- constructor kinds — e.g. `"some"(...)`, `"pair"(..., ...)` — nest sub-patterns and are validated against the scrutinee's constructor table.

### Types

Pattern matching is typed by constructor tables, which list each tagged type's constructors and their field types:

- `!match.option<T>` — `some` (carries a payload of type `T`) and `none`.
- `!match.pair<T1, T2>` — `pair` with two fields.

The table is the single source of truth shared by the verifier (which derives each arm's binding types from its pattern), the naive conversion, and the decision-tree pass.

## Lowering

Three conversion passes. The first two lower `match.match` to `scf` control flow (`scf.if` plus `match.deconstruct`); the third gives the tagged types a representation.

**`-convert-match-to-scf`** — the naive fallback: one `scf.if` per arm, each arm's pattern compiled to a flat boolean condition, the default in the last else.

**`-match-to-decision-tree`** — the Maranget-style pass, compiling pattern rows into a decision tree that shares tests:

- `column-choice=leftmost` (the default) questions columns of the decision matrix in source order
- `column-choice=mixture` (main novelty) prefers the column that copies the fewest rows and then the one that splits them into the most groups.

**`-match-to-llvm`** — gives the tagged types an LLVM representation and lowers `match.deconstruct` to LLVM ops. Done last to fully eliminate any match dialect ops (post-optimisation).

## Findings

Now that we have a means to reduce the average number of tests per pattern matching construct, we can verify that the runtime of the program decreases accordingly (except in cases of small trees) when applying maranget's algorithm.

| program | tests per value (mean) | tests per value (worst) | naive | maranget | speedup |
| --- | --- | --- | --- | --- | --- |
| four literal rows | 7.0 → 3.3 | 10 → 5 | 30 ms | 21 ms | 1.45x |
| sixteen literal rows | 19.6 → 9.1 | 34 → 17 | 66 ms | 22 ms | 3.04x |
| eight nested constructors | 18.1 → 5.5 | 28 → 10 | 64 ms | 25 ms | 2.51x |
| full matrix over a pair | 19.2 → 4.2 | 30 → 6 | 45 ms | 52 ms | 0.86x |
| a wider version of that matrix | 33.1 → 5.2 | 56 → 8 | 97 ms | 58 ms | 1.68x |

Runtime is measured with `tools/run.py programs/<shape>.mlir`: eight random inputs called on repeat, 50M calls, `clang -O1`, best of five.

## Repository layout

```
include/Match/            dialect definitions (TableGen) and headers
lib/Match/                op/type/attr implementations
lib/Match/Conversion/     lowering passes (MatchToSCF, MatchToDecisionTree, MatchToLLVM)
match-opt/                the mlir-opt-style driver for the dialect
test/                     lit tests (verifier errors, round-trips, all three lowerings)
programs/                 programs to run: samples and generated matrices
tools/                    the runner and the matrix generator (not part of the build)
```

## Running

`match-opt` is a standalone `mlir-opt`-style driver for the dialect:

```bash
# one branch per arm
build/bin/match-opt -convert-match-to-scf -match-to-llvm programs/literal-payload.mlir

# apply maranget's algorithm onto the pattern matching construct
build/bin/match-opt -match-to-decision-tree -convert-match-to-scf -match-to-llvm \
  programs/literal-payload.mlir
```
Adding the `-match-to-llvm` pass after the transform passes removes the match dialect from the IR, leaving upstream MLIR dialects.

## Testing

`tools/run.py` runs a program from `programs/` on random inputs through both lowerings, checks that they compute the same results and reports the speedup. `tools/gen_programs.py` writes the larger matrices the speedup needs into `programs/`. Both sit outside the build and the lit suite, since timings are not reproducible in CI.

The lit suite lives under `test/` and covers verifier diagnostics, assembly round-trips, and all three lowerings:

```bash
ninja -C build check-mlir-match
```

## Status and scope

The dialect, its verifier and its three lowerings are implemented and covered by the lit suite: `match.match` compiles to `scf`, and a program can be lowered out of the dialect entirely, into upstream MLIR dialects.

Extensions that fit the current design:

- **A front end.** Nothing parses a source language into `match.match`; the op is written by hand or produced by whatever lowers into it.
- **Producer ops** — `match.some`, `match.none`, `match.pair` — so match values can be built rather than only deconstructed.
- **User-defined types.** Declare constructors in IR instead of the built-in `option` and `pair`, and read the constructor table from those declarations.
- **Or-patterns and multi-scrutinee matches.**
- **A switch-based lowering.** A column with three or more constructors currently becomes a chain of comparisons; a tag switch would test it once.
- **Exhaustiveness and reachability diagnostics** at the points the passes already compute the relevant sets.
- **Jump-summary sharing.** A tree that copies a row duplicates its arm code rather than jumping to the next matrix.

## Further reading

Luc Maranget, *Compiling Pattern Matching to Good Decision Trees* — the compilation technique this dialect's tree pass implements.
