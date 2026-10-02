#!/usr/bin/env bash
# Runs the headless test suite (Linux/macOS/CI twin of run_tests.ps1).
# Usage: tools/run_tests.sh [name_fragment]     GODOT=/path/to/godot overrides the binary.
set -u
project="$(cd "$(dirname "$0")/.." && pwd)"
godot="${GODOT:-godot}"

# Import first so class_name scripts and textures are registered.
"$godot" --headless --path "$project" --import >/dev/null 2>&1 || true

args=(--headless --path "$project" -s res://tests/run_tests.gd)
if [ -n "${1:-}" ]; then args+=(-- "--only=$1"); fi
exec "$godot" "${args[@]}"
