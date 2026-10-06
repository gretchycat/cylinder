#!/bin/sh
set -e

GODOT_BIN="${GODOT_BIN:-$(which godot 2>/dev/null || echo "godot")}"
if ! command -v "$GODOT_BIN" >/dev/null 2>&1 && [ ! -x "$GODOT_BIN" ]; then
    echo "Error: Godot executable '$GODOT_BIN' not found." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
exec "$GODOT_BIN" --headless --path "$PROJECT_DIR" -s res://scripts/generate_map_cli.gd -- "$@"
