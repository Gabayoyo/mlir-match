import lit.formats
import os

# Self-contained lit config: tool paths are derived from the repository layout
# (build/bin for match-opt, the mlir-wheel bin for FileCheck/not) so no cmake
# site-config plumbing is required.
repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

config.name = "match-dialect"
config.test_format = lit.formats.ShTest(True)
config.suffixes = [".mlir"]
config.test_source_root = os.path.dirname(__file__)
config.test_exec_root = os.path.join(repo_root, "build", "test-exec")
os.makedirs(config.test_exec_root, exist_ok=True)
config.excludes = ["Inputs", "CMakeLists.txt", "lit.cfg.py"]

match_bin = os.path.join(repo_root, "build", "bin")
wheel_bin = os.path.join(
    repo_root, ".venv", "lib", "python3.12", "site-packages", "mlir_wheel", "bin"
)

config.substitutions.append(("%matchopt", os.path.join(match_bin, "match-opt")))
config.substitutions.append(("%FileCheck", os.path.join(wheel_bin, "FileCheck")))
config.substitutions.append(("%not", os.path.join(wheel_bin, "not")))
