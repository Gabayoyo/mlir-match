#!/usr/bin/env bash
#
# Compares two lowerings of the same program: the naive arm-by-arm pass and the
# Maranget decision-tree pass.
#
# Both are lowered through the same pipeline, spliced with the same bench driver
# (tools/bench/drivers/), compiled with the same flags and run the same number
# of times. The static numbers come from the lowered program alone, so they
# describe the lowering rather than the harness. The two checksums have to agree
# before a speedup is reported.
#
# Usage: tools/bench/run.sh <program.mlir> --driver <driver.mlir> [options]
#   --iters N     loop iterations (default 50000000)
#   --repeats R   runs per method, best is reported (default 5)
#   --opt LEVEL   clang optimisation level (default O1)

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
match_opt="$root/build/bin/match-opt"
translate="$root/.venv/lib/python3.12/site-packages/mlir_wheel/bin/mlir-translate"

[[ -x "$match_opt" ]] || { echo "missing $match_opt (run: ninja -C build)" >&2; exit 1; }

clang_bin=""
for cand in /opt/homebrew/opt/llvm/bin/clang "$(command -v clang || true)"; do
  [[ -x "$cand" ]] && { clang_bin="$cand"; break; }
done
[[ -n "$clang_bin" ]] || { echo "no clang found" >&2; exit 1; }

iters=50000000
repeats=5
opt=O1
src=""
driver=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --driver) driver="$2"; shift 2 ;;
    --iters) iters="$2"; shift 2 ;;
    --repeats) repeats="$2"; shift 2 ;;
    --opt) opt="$2"; shift 2 ;;
    *) src="$1"; shift ;;
  esac
done

[[ -n "$src" && -f "$src" ]] || { echo "usage: tools/bench/run.sh <program.mlir> --driver <driver.mlir>" >&2; exit 1; }
[[ -n "$driver" && -f "$driver" ]] || { echo "missing --driver (see tools/bench/drivers/)" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

tail_passes=(-convert-scf-to-cf -match-to-llvm -convert-to-llvm)
methods="naive maranget"

lowering_for() {
  case "$1" in
    naive) echo "-convert-match-to-scf" ;;
    maranget) echo "-match-to-decision-tree -convert-match-to-scf" ;;
  esac
}

# Static shape of the lowered program, without the driver in the way.
static_counts() { # <file> <regex>
  local n
  n="$(grep -cE "$2" "$1" 2>/dev/null)"
  echo "${n:-0}"
}

for m in $methods; do
  # shellcheck disable=SC2086
  "$match_opt" $(lowering_for "$m") "${tail_passes[@]}" "$src" 2>"$tmp/err" > "$tmp/$m.mlir" || {
    echo "$m: lowering failed" >&2; cat "$tmp/err" >&2; exit 1; }

  "$translate" --mlir-to-llvmir "$tmp/$m.mlir" > "$tmp/$m.ll" 2>"$tmp/err" || {
    echo "$m: translation failed" >&2; cat "$tmp/err" >&2; exit 1; }
  "$clang_bin" -S "-$opt" "$tmp/$m.ll" -o "$tmp/$m.s" 2>/dev/null

  # The measured binary is the program plus the driver.
  sed "s/__ITERS__/$iters/" "$driver" > "$tmp/driver.mlir"
  { echo "module {"; sed '/^$/d' "$tmp/$m.mlir" | sed '1d;$d'; cat "$tmp/driver.mlir"; echo "}"; } > "$tmp/$m-merged.mlir"
  "$translate" --mlir-to-llvmir "$tmp/$m-merged.mlir" > "$tmp/$m-merged.ll" 2>"$tmp/err" || {
    echo "$m: driver merge failed" >&2; cat "$tmp/err" >&2; exit 1; }
  "$clang_bin" "-$opt" "$tmp/$m-merged.ll" -o "$tmp/$m.bin" 2>/dev/null || {
    echo "$m: compile failed" >&2; exit 1; }
done

# Time each binary; keep the best run so a stray scheduler hiccup does not win.
python3 - "$tmp" "$iters" "$repeats" "$clang_bin" "$opt" <<'PY'
import subprocess, sys, time, re, pathlib

tmp, iters, repeats, clang, opt = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], sys.argv[5]
tmp = pathlib.Path(tmp)

def stat(name, regex):
    text = (tmp / name).read_text() if (tmp / name).exists() else ""
    return len(re.findall(regex, text, re.M))

rows = {}
for m in ("naive", "maranget"):
    ll, s = tmp / f"{m}.ll", tmp / f"{m}.s"
    # instruction and branch counts of the program functions in the -S output
    insns = branches = 0
    if s.exists():
        body = s.read_text()
        insns = len(re.findall(r"^\s+[a-z]", body, re.M))
        branches = len(re.findall(r"^\s+(?:b\.|cbz|cbnz|tbz|tbnz)", body, re.M))
    best, out = 9e9, ""
    for _ in range(repeats):
        t0 = time.perf_counter()
        out = subprocess.run([str(tmp / f"{m}.bin")], capture_output=True, text=True).stdout.strip()
        best = min(best, time.perf_counter() - t0)
    rows[m] = dict(
        tests=stat(f"{m}.ll", r"\bicmp "),
        cond=stat(f"{m}.ll", r"br i1"),
        blocks=stat(f"{m}.ll", r"^[0-9]+:"),
        insns=insns,
        branches=branches,
        ms=best * 1000,
        sum=out,
    )

a, b = rows["naive"], rows["maranget"]
print(f"{'method':10} {'tests':>6} {'cond':>5} {'blocks':>7} {'insns':>6} {'branch':>7} {'ms':>9} {'speedup':>8}  checksum")
for name, r in (("naive", a), ("maranget", b)):
    sp = f"{a['ms'] / b['ms']:.2f}x" if name == "maranget" else "-"
    print(f"{name:10} {r['tests']:6} {r['cond']:5} {r['blocks']:7} {r['insns']:6} {r['branches']:7} {r['ms']:8.1f} {sp:>8}  {r['sum']}")
if a["sum"] != b["sum"]:
    print("WARNING: checksums differ, the two lowerings do not compute the same thing", file=sys.stderr)
    sys.exit(2)
PY
