#!/usr/bin/env python3
"""Compares the two lowerings of a match program.

    tools/run.py programs/literals-16.mlir [--seed N] [--iterations 50M] [--opt O1]

The program is lowered both ways, and two things are reported.

Static: every path through the lowered code is walked and the comparisons on it
counted, giving the fewest, mean and most tests one value can cost. No inputs, no
seed and no machine are involved, so this is the same everywhere and is what the
comparison rests on.

Timing: a fixed set of random inputs is drawn from the seed, called on repeat and
run against `clang -O<N>` binaries, best of `--runs`. Real time depends on which
values dominate, so it is reported underneath as context rather than as the
claim.

Values are drawn per type: a constructor is picked from the ones the type
declares, and payloads land in 0..3 by default. The tag convention comes from the
dialect's LLVM representation — a type with more than one constructor keeps the
constructor's index in field 0 — see configureMatchToLLVMTypeConverter.
"""

import argparse
import pathlib
import random
import re
import shutil
import subprocess
import sys
import tempfile
import time

DEFAULT_PAYLOAD_RANGE = 4
PAYLOAD_RANGE = DEFAULT_PAYLOAD_RANGE  # payloads are drawn from 0..PAYLOAD_RANGE-1
SCALAR_RANGE = 3  # plain scalars from -SCALAR_RANGE..SCALAR_RANGE
DEFAULT_INPUTS = 8  # distinct random inputs the timing loop calls

TAIL_PASSES = ["-convert-scf-to-cf", "-match-to-llvm", "-convert-to-llvm"]
VARIANTS = {
    "naive": ["-convert-match-to-scf"],
    "maranget": ["-match-to-decision-tree", "-convert-match-to-scf"],
}


def find_toolchain():
    """Locates the tools this runner drives: match-opt, mlir-translate and clang."""
    root = pathlib.Path(__file__).resolve().parent.parent
    match_opt = root / "build" / "bin" / "match-opt"
    translate = root / ".venv/lib/python3.12/site-packages/mlir_wheel/bin/mlir-translate"
    for path, hint in ((match_opt, "ninja -C build"), (translate, "pip install -r requirements.txt")):
        if not path.exists():
            sys.exit(f"run.py: missing {path} ({hint})")

    # The wheel ships no code generator, so runs go through a host clang.
    for candidate in ("/opt/homebrew/opt/llvm/bin/clang", shutil.which("clang")):
        if candidate and pathlib.Path(candidate).exists():
            return str(match_opt), str(translate), candidate
    sys.exit("run.py: no clang found (install a host LLVM, e.g. brew install llvm)")


class Build:
    """Emits the MLIR that builds values, into a single function body."""

    def __init__(self):
        self.lines = []
        self.counter = 0

    def name(self, prefix):
        self.counter += 1
        return f"%{prefix}{self.counter}"

    def emit(self, line):
        self.lines.append("    " + line)

    def constant(self, value, type_text):
        name = self.name("c")
        self.emit(f"{name} = llvm.mlir.constant({value} : {type_text}) : {type_text}")
        return name

    def undef(self, type_text):
        name = self.name("u")
        self.emit(f"{name} = llvm.mlir.undef : {type_text}")
        return name

    def insert(self, value, container, index, type_text):
        name = self.name("s")
        self.emit(f"{name} = llvm.insertvalue {value}, {container}[{index}] : {type_text}")
        return name

    def build(self, node, value):
        """Emits the construction of `value` and returns the name holding it."""
        type_text = llvm_type(node)
        if node[0] == "int":
            return self.constant(value, type_text)
        if node[0] == "pair":
            container = self.undef(type_text)
            first, second = value
            container = self.insert(self.build(node[1], first), container, 0, type_text)
            return self.insert(self.build(node[2], second), container, 1, type_text)
        # An option stores the constructor's index in field 0, then its payload;
        # none carries no payload, so that field stays undefined.
        tag, payload = value
        container = self.undef(type_text)
        container = self.insert(self.constant(tag, "i32"), container, 0, type_text)
        if tag == 0:
            container = self.insert(self.build(node[1], payload), container, 1, type_text)
        return container


def read_group(text, start, open_ch, close_ch):
    """Returns the text inside the group opening at `start` and the index after it."""
    assert text[start] == open_ch
    depth, i = 0, start
    while i < len(text):
        if text[i] == open_ch:
            depth += 1
        elif text[i] == close_ch:
            depth -= 1
            if depth == 0:
                return text[start + 1 : i], i + 1
        i += 1
    sys.exit(f"run.py: unbalanced '{open_ch}' in '{text[:40]}'")


def split_top_level(text, sep=","):
    """Splits on `sep` at nesting depth zero, so types may contain commas."""
    parts, depth, current = [], 0, ""
    for char in text:
        if char in "<([{":
            depth += 1
        elif char in ">)]}":
            depth -= 1
        if char == sep and depth == 0:
            parts.append(current.strip())
            current = ""
        else:
            current += char
    if current.strip():
        parts.append(current.strip())
    return [part for part in parts if part]


def parse_type(text):
    """Parses a parameter type written in the program into a small tree."""
    text = text.strip()
    if re.fullmatch(r"i\d+", text):
        return ("int", text)
    m = re.match(r"!match\.(option|pair)<", text)
    if not m:
        sys.exit(f"run.py: unsupported parameter type '{text}'")
    inner, end = read_group(text, m.end() - 1, "<", ">")
    if end != len(text):
        sys.exit(f"run.py: unsupported parameter type '{text}'")
    parts = split_top_level(inner)
    if m.group(1) == "option":
        return ("option", parse_type(parts[0]))
    return ("pair", parse_type(parts[0]), parse_type(parts[1]))


def entry_signatures(text, keyword):
    """Name, parameter types and result types of every `keyword` function."""
    entries = []
    for m in re.finditer(re.escape(keyword) + r"\s+@(\w+)\s*\(", text):
        params, after = read_group(text, m.end() - 1, "(", ")")
        rest = text[after:].lstrip()
        results = []
        if rest.startswith("->"):
            rest = rest[2:].lstrip()
            if rest.startswith("("):
                group, _ = read_group(rest, 0, "(", ")")
                results = split_top_level(group)
            else:
                end = min((i for i in (rest.find("{"), rest.find("\n")) if i != -1), default=len(rest))
                results = [rest[:end].strip()]
        entries.append(
            (
                m.group(1),
                [p.split(":", 1)[-1].strip() for p in split_top_level(params)],
                [r for r in results if r],
            )
        )
    return entries


def llvm_type(node):
    """The LLVM type a parameter lowers to, following the pass's layout."""
    if node[0] == "int":
        return node[1]
    if node[0] == "pair":
        return f"!llvm.struct<({llvm_type(node[1])}, {llvm_type(node[2])})>"
    return f"!llvm.struct<(i32, {llvm_type(node[1])})>"


def describe(node, value):
    """Reads a drawn value back as the match value it stands for."""
    if node[0] == "int":
        return str(value)
    if node[0] == "pair":
        return f"pair({describe(node[1], value[0])}, {describe(node[2], value[1])})"
    tag, payload = value
    return f"some({describe(node[1], payload)})" if tag == 0 else "none"


def draw(node, rng, payload=False):
    """Draws a value: tags come from the constructors the type declares.

    Fields drawn as payloads stay in 0..PAYLOAD_RANGE-1 so literal rows are
    reached; a parameter of the entry is drawn across a wider range.
    """
    if node[0] == "int":
        return rng.randrange(PAYLOAD_RANGE) if payload else rng.randint(-SCALAR_RANGE, SCALAR_RANGE)
    if node[0] == "pair":
        return (draw(node[1], rng, payload), draw(node[2], rng, payload))
    tag = rng.randrange(2)  # some or none
    return (tag, draw(node[1], rng, True))


def source_entries(text):
    """The program's entry functions, as name and written parameter types."""
    return [(name, params) for name, params, _ in entry_signatures(text, "func.func")]


def lowered_signatures(text):
    """Operand and result types of each entry, as the call has to spell them."""
    lowered = {}
    for name, params, results in entry_signatures(text, "llvm.func"):
        lowered[name] = (params, results[0] if results else "")
    return lowered


def format_global(index, text):
    """A printf format holding text known before the run."""
    literal = text.replace("\\", "\\\\").replace('"', '\\"') + "\\0A\\00"
    return f'  llvm.mlir.global internal constant @fmt{index}("{literal}") : !llvm.array<{len(text) + 2} x i8>'


def generate_driver(program_text, lowered_text, seed, inputs, iterations):
    """Builds the `main` that calls each entry on the drawn inputs.

    The entries are only declared here, so they are compiled separately: the
    optimiser cannot see their bodies, which is what keeps the repeated calls of
    the timing loop from being folded into a single result.

    With `iterations` above zero the same calls are repeated in a loop and summed
    into a checksum, which is what the timing measures; the checksum also keeps
    the loop from being optimised away.
    """
    rng = random.Random(seed)
    signatures = lowered_signatures(lowered_text)
    globals_, printed, loop, build = [], [], [], Build()
    calls, declarations = [], []

    for index, (name, params) in enumerate(source_entries(program_text)):
        if name not in signatures:
            continue
        operand_types, result_type = signatures[name]
        nodes = [parse_type(p) for p in params]
        # MLIR prints nested struct types without their dialect prefix, so the
        # comparison ignores the prefix on both sides.
        expected = [llvm_type(n) for n in nodes]
        if [t.replace("!llvm.", "") for t in expected] != [
            t.replace("!llvm.", "") for t in operand_types
        ]:
            sys.exit(
                f"run.py: '{name}' lowered to ({', '.join(operand_types)}), but this runner "
                f"expects ({', '.join(expected)}): the LLVM layout changed"
            )
        if result_type not in ("i32", "i64"):
            sys.exit(f"run.py: only i32/i64 results can be printed, not '{result_type}'")

        arg_types = ", ".join(operand_types)
        declarations.append(f"  llvm.func @{name}({arg_types}) -> {result_type}")
        descriptions, results = [], []
        for _ in range(inputs):
            values = [draw(node, rng) for node in nodes]
            arguments = [build.build(node, value) for node, value in zip(nodes, values)]
            results.append(build.name("r"))
            printed.append(
                f"    {results[-1]} = llvm.call @{name}({', '.join(arguments)}) "
                f": ({arg_types}) -> {result_type}"
            )
            descriptions.append(
                f"{name}(" + ", ".join(describe(n, v) for n, v in zip(nodes, values)) + ")"
            )
            calls.append((name, arguments, arg_types, result_type))

        # One line per entry, listing what each drawn input produced.
        label = ", ".join(f"{text} = %d" for text in descriptions)
        globals_.append(format_global(index, label))
        fmt = build.name("f")
        printed.append(f"    {fmt} = llvm.mlir.addressof @fmt{index} : !llvm.ptr")
        printed.append(
            f"    %printed{index} = llvm.call @printf({fmt}, {', '.join(results)}) "
            f'vararg(!llvm.func<i32 (!llvm.ptr, ...)>) : (!llvm.ptr, '
            f'{", ".join([result_type] * inputs)}) -> i32'
        )

    if not calls:
        sys.exit("run.py: no entry function found in the program")

    rounds = iterations // len(calls)
    if rounds:
        globals_.append(format_global(len(globals_), "checksum = %d"))
        loop += [
            f"    %sumfmt = llvm.mlir.addressof @fmt{len(globals_) - 1} : !llvm.ptr",
            f"    %limit = llvm.mlir.constant({rounds} : i32) : i32",
            "    %start = llvm.mlir.constant(0 : i32) : i32",
            "    %step = llvm.mlir.constant(1 : i32) : i32",
            "    llvm.br ^loop(%start, %start : i32, i32)",
            "  ^loop(%round: i32, %sum: i32):",
            '    %done = llvm.icmp "sge" %round, %limit : i32',
            "    llvm.cond_br %done, ^done(%sum : i32), ^body(%round, %sum : i32, i32)",
            "  ^body(%count: i32, %acc: i32):",
        ]
        carried = "%acc"
        for call_index, (name, arguments, arg_types, result_type) in enumerate(calls):
            loop.append(
                f"    %called{call_index} = llvm.call @{name}({', '.join(arguments)}) "
                f": ({arg_types}) -> {result_type}"
            )
            value = f"%called{call_index}"
            if result_type != "i32":
                loop.append(f"    %narrow{call_index} = llvm.trunc {value} : i64 to i32")
                value = f"%narrow{call_index}"
            loop.append(f"    %carried{call_index} = llvm.add {carried}, {value} : i32")
            carried = f"%carried{call_index}"
        loop += [
            "    %next = llvm.add %count, %step : i32",
            f"    llvm.br ^loop(%next, {carried} : i32, i32)",
            "  ^done(%total: i32):",
            "    %summed = llvm.call @printf(%sumfmt, %total) "
            'vararg(!llvm.func<i32 (!llvm.ptr, ...)>) : (!llvm.ptr, i32) -> i32',
        ]

    return "\n".join(
        [
            "  llvm.func @printf(!llvm.ptr, ...) -> i32",
            *declarations,
            *globals_,
            "  llvm.func @main() -> i32 {",
            *build.lines,
            *printed,
            *loop,
            "    %zero = llvm.mlir.constant(0 : i32) : i32",
            "    llvm.return %zero : i32",
            "  }",
        ]
    )


def path_tests(ir):
    """Tests per path of each function, as (paths, min, mean, max).

    Every path from entry to a return is walked and the comparisons on it
    counted, which is the number of tests one value costs on that path. Cyclic
    control flow has no finite path count and is reported rather than guessed at.
    """
    stats = []
    for chunk in re.split(r"^define ", ir, flags=re.M)[1:]:
        body = re.split(r"^\}", chunk, flags=re.M)[0]
        parts = re.split(r"^(\d+):.*$", body, flags=re.M)
        blocks = [("entry", parts[0])] + [
            (parts[i], parts[i + 1]) for i in range(1, len(parts), 2)
        ]
        # Costs first: a block may branch forward to one not seen yet.
        cost = {label: len(re.findall(r"\bicmp\b", text)) for label, text in blocks}
        succ = {
            label: [t for t in re.findall(r"label %([\w.$]+)", text) if t in cost]
            for label, text in blocks
        }

        totals, stack = [], [("entry", cost["entry"], ("entry",))]
        while stack:
            label, running, trail = stack.pop()
            if not succ[label]:
                totals.append(running)
                continue
            for target in succ[label]:
                if target in trail:
                    return None  # a loop: the number of paths is unbounded
                stack.append((target, running + cost[target], trail + (target,)))
        if totals:
            stats.append((len(totals), min(totals), sum(totals) / len(totals), max(totals)))
    return stats or None


def run(cmd):
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(result.stderr.strip() or f"run.py: failed to run {' '.join(cmd)}")
    return result.stdout


def summarise(stats):
    """Collapses per-function path counts into one line of numbers."""
    paths = sum(p for p, _, _, _ in stats)
    mean = sum(paths_i * mean_i for paths_i, _, mean_i, _ in stats) / paths
    return paths, min(low for _, low, _, _ in stats), mean, max(high for _, _, _, high in stats)


def main():
    global PAYLOAD_RANGE, SCALAR_RANGE
    parser = argparse.ArgumentParser(description="Compare the two lowerings of a match program.")
    parser.add_argument("program", type=pathlib.Path)
    parser.add_argument("--seed", type=int)
    parser.add_argument("--variant", choices=["naive", "maranget", "both"], default="both")
    parser.add_argument("--payload-range", type=int,
                        help="payloads are drawn from 0..N-1; default: just past the "
                             "program's largest literal, so its literal rows are reached")
    parser.add_argument("--scalar-range", type=int, default=SCALAR_RANGE,
                        help="plain scalars from -N..N (default 3)")
    parser.add_argument("--inputs", type=int, default=DEFAULT_INPUTS,
                        help="distinct random inputs the timing loop calls (default 8)")
    parser.add_argument("--opt", default="O1", help="clang optimisation level (default O1)")
    parser.add_argument("--iterations", type=int, default=50000000,
                        help="calls per run of the timing loop (default 50M, 0 disables)")
    parser.add_argument("--runs", type=int, default=3,
                        help="timed runs per lowering, best is reported (default 3)")
    args = parser.parse_args()

    match_opt, translate, clang = find_toolchain()
    program_text = args.program.read_text()

    literals = [int(n) for n in re.findall(r'#match\.pattern<"literal", (-?\d+)', program_text)]
    if args.payload_range is None:
        PAYLOAD_RANGE = max(literals) + 1 if literals else DEFAULT_PAYLOAD_RANGE
        range_note = "from the program's literals" if literals else "default"
    else:
        PAYLOAD_RANGE = args.payload_range
        range_note = "from --payload-range"
    SCALAR_RANGE = args.scalar_range
    seed = args.seed if args.seed is not None else random.randrange(1 << 30)
    variants = list(VARIANTS) if args.variant == "both" else [args.variant]

    print(f"{args.program}  seed {seed}")
    work = pathlib.Path(tempfile.mkdtemp())
    try:
        lowered, static = {}, {}
        for variant in variants:
            lowered[variant] = run(
                [match_opt, *VARIANTS[variant], *TAIL_PASSES, str(args.program)]
            )
            # Static counts come from the lowered program alone, with no driver.
            program_mlir = work / f"{variant}-program.mlir"
            program_mlir.write_text(lowered[variant])
            static[variant] = path_tests(run([translate, "--mlir-to-llvmir", str(program_mlir)]))

        print("\ntests per value, counting every path through the lowered code")
        if all(static[v] for v in variants):
            print(f"{'variant':10} {'paths':>6} {'min':>5} {'mean':>7} {'max':>5}")
            counts = {}
            for variant in variants:
                counts[variant] = summarise(static[variant])
                print(f"{variant:10} {counts[variant][0]:6} {counts[variant][1]:5.0f} "
                      f"{counts[variant][2]:7.1f} {counts[variant][3]:5.0f}")
            if len(variants) == 2:
                naive, tree = counts["naive"], counts["maranget"]
                print(
                    f"the tree asks {naive[2] / tree[2]:.2f}x fewer tests on average and "
                    f"{naive[3] / tree[3]:.2f}x fewer in the worst case"
                )
        else:
            print("unavailable: the lowered code has a loop or an external branch")

        if args.iterations:
            def compile_ir(text, tag):
                """Translates MLIR and compiles it to an object file."""
                mlir = work / f"{tag}.mlir"
                ll = work / f"{tag}.ll"
                obj = work / f"{tag}.o"
                mlir.write_text(text)
                ll.write_text(run([translate, "--mlir-to-llvmir", str(mlir)]))
                run([clang, f"-{args.opt}", "-Wno-override-module", "-c", str(ll),
                     "-o", str(obj)])
                return obj

            def build_binary(variant, iterations, tag):
                """Links the lowered program with a driver that calls it."""
                driver = generate_driver(
                    program_text, lowered[variant], seed, args.inputs, iterations
                )
                program_obj = compile_ir(lowered[variant], f"{variant}-program")
                driver_obj = compile_ir(f"module {{\n{driver}\n}}\n", f"{tag}-driver")
                binary = work / tag
                run([clang, str(driver_obj), str(program_obj), "-o", str(binary)])
                return binary

            def timed(binary):
                best = 9e9
                for _ in range(args.runs):
                    started = time.perf_counter()
                    subprocess.run([str(binary)], capture_output=True)
                    best = min(best, time.perf_counter() - started)
                return best * 1000

            print(
                f"\ntiming, {args.inputs} random inputs on repeat ({range_note}), "
                f"clang -{args.opt}, best of {args.runs}"
            )
            results, times = {}, {}
            for variant in variants:
                # Measuring the loop alone: the same build without a loop gives
                # the startup and printing cost to subtract.
                startup = timed(build_binary(variant, 0, f"{variant}-plain"))
                binary = build_binary(variant, args.iterations, variant)
                total = timed(binary)
                output = subprocess.run([str(binary)], capture_output=True, text=True).stdout
                results[variant] = "\n".join(
                    line for line in output.splitlines() if not line.startswith("checksum")
                ).strip()
                times[variant] = max(total - startup, 0.0)

            print(f"\n{'variant':10} {'ms':>9} {'ns/call':>9}")
            for variant in variants:
                per_call = times[variant] * 1e6 / args.iterations
                print(f"{variant:10} {times[variant]:9.1f} {per_call:9.2f}")
            if len(variants) == 2 and min(times.values()) > 0:
                ratio = times["naive"] / times["maranget"]
                faster = "maranget" if ratio >= 1 else "naive"
                print(f"{faster} is {max(ratio, 1 / ratio):.2f}x faster on these inputs")
            agreed = len(set(results.values())) == 1
            print("results " + (results[variants[0]] if agreed else "DIFFER"))
            if not agreed:
                for variant in variants:
                    print(f"  {variant}: {results[variant]}")
    finally:
        shutil.rmtree(work)


if __name__ == "__main__":
    main()
