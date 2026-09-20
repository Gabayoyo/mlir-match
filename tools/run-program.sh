#!/usr/bin/env bash
#
# Runs a lowered program.
#
# The program is lowered out of the dialect, a driver from tools/drivers/ is
# spliced into the same module, and the result is translated to LLVM IR and
# executed. The driver is MLIR rather than C so that both sides agree on the
# calling convention: the lowered functions take the tagged types by value, and
# a C compiler coerces small aggregates to a scalar instead.
#
# Usage: tools/run-program.sh <program.mlir> [--variant naive|maranget|both]

set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
match_opt="$root/build/bin/match-opt"
translate="$root/.venv/lib/python3.12/site-packages/mlir_wheel/bin/mlir-translate"

[[ -x "$match_opt" ]] || { echo "missing $match_opt (run: ninja -C build)" >&2; exit 1; }
[[ -x "$translate" ]] || { echo "missing $translate" >&2; exit 1; }

# The wheel ships no runner, so use a host lli new enough for the IR it emits.
lli=""
for cand in /opt/homebrew/opt/llvm/bin/lli /opt/homebrew/opt/llvm@22/bin/lli "$(command -v lli || true)"; do
  if [[ -x "$cand" ]] && "$cand" --version >/dev/null 2>&1; then lli="$cand"; break; fi
done
[[ -n "$lli" ]] || { echo "no lli found (install llvm: brew install llvm)" >&2; exit 1; }

variant="both"
src=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --variant) variant="$2"; shift 2 ;;
    *) src="$1"; shift ;;
  esac
done

[[ -n "$src" && -f "$src" ]] || { echo "usage: tools/run-program.sh <program.mlir>" >&2; exit 1; }

name="$(basename "$src" .mlir)"
driver="$root/tools/drivers/$name.mlir"
[[ -f "$driver" ]] || { echo "no driver at tools/drivers/$name.mlir" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

tail_passes=(-convert-scf-to-cf -match-to-llvm -convert-to-llvm)

# macOS ships bash 3.2, which has no associative arrays.
passes_for() {
  case "$1" in
    naive) echo "-convert-match-to-scf" ;;
    maranget) echo "-match-to-decision-tree -convert-match-to-scf" ;;
  esac
}

case "$variant" in
  naive|maranget) wish=("$variant") ;;
  both) wish=(naive maranget) ;;
  *) echo "unknown variant '$variant'" >&2; exit 1 ;;
esac

for v in "${wish[@]}"; do
  lowered="$tmp/$name-$v.mlir"
  # shellcheck disable=SC2086
  if ! "$match_opt" $(passes_for "$v") "${tail_passes[@]}" "$src" > "$lowered" 2>"$tmp/err"; then
    echo "$v: lowering failed" >&2
    cat "$tmp/err" >&2
    continue
  fi

  # Splice the driver into the lowered module: one module, one calling
  # convention, so no boundary needs an ABI translation. The lowered output is
  # `module { ... }` plus a trailing blank line, so drop the wrapper and the
  # blank lines before appending the driver.
  merged="$tmp/$name-$v-merged.mlir"
  { echo "module {"; sed '/^$/d' "$lowered" | sed '1d;$d'; cat "$driver"; echo "}"; } > "$merged"

  if ! "$translate" --mlir-to-llvmir "$merged" > "$tmp/$v.ll" 2>"$tmp/err"; then
    echo "$v: translation failed" >&2
    cat "$tmp/err" >&2
    continue
  fi

  printf '%s\n' "--- $v ---"
  if ! "$lli" "$tmp/$v.ll" > "$tmp/$v.out" 2>"$tmp/$v.err"; then
    echo "(run failed)" >&2
    cat "$tmp/$v.err" >&2
    continue
  fi
  cat "$tmp/$v.out"
done

if [[ ${#wish[@]} -eq 2 && -f "$tmp/naive.out" && -f "$tmp/maranget.out" ]]; then
  if diff "$tmp/naive.out" "$tmp/maranget.out" >/dev/null; then
    echo "both lowerings agree"
  else
    echo "LOWERINGS DISAGREE"
    diff "$tmp/naive.out" "$tmp/maranget.out"
  fi
fi
