#!/usr/bin/env python3
"""Command-line frontend to the engine's map generator.
Delegates execution to the Godot map generator CLI.
"""
import sys
import subprocess
from pathlib import Path

def main():
    script_dir = Path(__file__).resolve().parent
    shell_script = script_dir / "generate_map.sh"
    cmd = [str(shell_script)] + sys.argv[1:]
    raise SystemExit(subprocess.call(cmd))

if __name__ == "__main__":
    main()
