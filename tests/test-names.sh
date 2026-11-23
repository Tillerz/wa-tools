#!/bin/bash
# Looks for names that a script uses but never defines or imports (like a missing "import datetime").
# Python only finds such a mistake when the line runs, and some scripts (extract, deploy, find, tagmgr)
# have no fake server to run them against. This check reads all scripts of the repo folder.
# It is crude: it does not know scopes, a name that is defined anywhere in the file counts as defined.
# Run it from anywhere:  ./tests/test-names.sh
set -u
cd "$(dirname "$0")/.."

python3 -I - <<'PY'
import ast, builtins
from pathlib import Path

problems = []
for path in sorted(Path(".").glob("*.py")):
    tree = ast.parse(path.read_text())
    defined = set(dir(builtins)) | {"__file__", "__name__"}
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            defined.add(node.name)
        elif isinstance(node, ast.arg):
            defined.add(node.arg)
        elif isinstance(node, ast.Name) and isinstance(node.ctx, (ast.Store, ast.Del)):
            defined.add(node.id)
        elif isinstance(node, (ast.Import, ast.ImportFrom)):
            for alias in node.names:
                defined.add((alias.asname or alias.name).split(".")[0])
        elif isinstance(node, ast.ExceptHandler) and node.name:
            defined.add(node.name)
        elif isinstance(node, (ast.Global, ast.Nonlocal)):
            defined.update(node.names)
    for node in ast.walk(tree):
        if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Load) and node.id not in defined:
            problems.append(f"{path}:{node.lineno}: {node.id}")

scripts = len(list(Path(".").glob("*.py")))
for line in problems:
    print("  FAIL  undefined name", line)
if not problems:
    print(f"  PASS  no undefined names in {scripts} scripts")
raise SystemExit(1 if problems else 0)
PY
status=$?
echo "---------------------------------------------------------------"
if [ "$status" = 0 ]; then echo "ALL TESTS PASSED"; else echo "TESTS FAILED"; fi
exit $status
