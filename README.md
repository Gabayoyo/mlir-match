# mlir-match

An out-of-tree [MLIR](https://mlir.llvm.org/) dialect for representing functional pattern matching, compiled with Maranget-style decision trees for optimisation.

`match.match` groups a scrutinee with ordered `case` arms, each headed by optional structured pattern and guards, and a fallback `default` region.

## Example

Below is an example of matching an `option` value. with cases: `some(1)`, `some(x)`, and `none`. The `match.match` op holds an attribute dictating what each arm's corresponding pattern is. Each arm can also specify a binding which is part of the condition to branch and is present in the body too:

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
- No system MLIR or LLVM build is needed.

```bash
python -m venv .venv
.venv/bin/pip install -r requirements.txt

cmake -S . -B build -G Ninja \
  -DMLIR_DIR=$PWD/.venv/lib/python3.12/site-packages/mlir_wheel/lib/cmake/mlir \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

The wheel version is pinned in `requirements.txt`; the project tracks that snapshot of MLIR.

## The dialect

All ops and types live in the `match` dialect and are printed with the `match.` prefix. The TableGen descriptions in `include/Match/*.td` are the canonical documentation for each op and type.

### Ops

| Op | Purpose |
| --- | --- |
| `match.match` | Groups a scrutinee value with `case` arms and a `default` region; selects the first arm whose pattern matches (and whose guard, if any, holds). |
| `match.guard` | Splits an arm into a condition computation and a body: the arm fires only when the guard condition is true. |
| `match.yield` | Terminates an arm or default region with the match's results. |
| `match.deconstruct` | The runtime primitive: tests a value's constructor and projects its fields. Emitted by lowering; its runtime representation is deliberately out of scope. |

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

Two conversion passes lower `match.match` to `scf` control flow; both stop at the semantic layer (`scf.if` plus `match.deconstruct`), leaving representation and codegen choices to downstream work.

**`-convert-match-to-scf`** — the naive fallback: arms are tested top to bottom, each arm's pattern compiled to a flat boolean condition, one `scf.if` per arm, the default in the last else.

**`-match-to-decision-tree`** — the Maranget-style pass: compiles eligible matches into a decision tree of shared constructor and literal tests. A pair scrutinee opens into two independently questioned columns; guarded arms become guard tests that fall through to the remaining rows when the guard fails; rows that can never fire are pruned; bindings are materialised from the slot that holds the matched field.

> [!IMPORTANT]
> The tree pass only compiles matches whose rows align on a common column structure. Matches it cannot align (for example, a bind used as a direct field of a multi-field constructor) are left untouched for the naive pass — never miscompiled.

## Repository layout

```
include/Match/            dialect definitions (TableGen) and headers
lib/Match/                op/type/attr implementations
lib/Match/Conversion/     lowering passes (MatchToSCF, MatchToDecisionTree)
match-opt/                the mlir-opt-style driver for the dialect
test/                     lit tests (verifier errors, round-trips, both lowerings)
programs/                 example programs with expected outputs
```

## Running and testing

`match-opt` is a standalone `mlir-opt`-style driver for the dialect. Without a pass it round-trips the input; the conversion passes lower it:

```bash
build/bin/match-opt programs/simple.mlir
build/bin/match-opt -convert-match-to-scf programs/literal-payload.mlir
build/bin/match-opt -match-to-decision-tree programs/literal-payload.mlir
```

The upstream `convert-scf-to-cf` pass lowers the result further to plain branches.

The lit suite lives under `test/` and covers verifier diagnostics, assembly round-trips, the naive conversion, and the decision-tree pass:

```bash
ninja -C build check-mlir-match
```

## Status and scope

Implemented: decision-tree lowering for options, nested options, pairs (two columns), guards, literal payloads, bindings materialised from slots, fallback-row semantics, and dead-arm pruning; verified behaviour in the lit suite.

Planned: column-choice heuristics (which column to question first), and the integration wrap-up of the two passes.

Out of scope: running the lowered code (no ABI or LLVM codegen for the tagged types, and no runner — the lowering intentionally stops at `scf` plus `match.deconstruct`); user-declared data types; general mixed-column matrices that need per-row column streams; or-patterns, multi-scrutinee matches, and exhaustiveness diagnostics.

## Further reading

Luc Maranget, *Compiling Pattern Matching to Good Decision Trees* — the compilation technique this dialect's tree pass implements.
