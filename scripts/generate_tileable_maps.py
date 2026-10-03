#!/usr/bin/env python3
"""Command-line frontend to the engine's single schema-3 map generator.

World geometry, layer resolutions, biomes and artwork belong in map_config.json.
This frontend deliberately does not maintain a second generation algorithm.
"""
import argparse
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--map", default="default", help="Source map directory or bundled map name")
    parser.add_argument("--output-dir", required=True, help="New output directory; must not exist")
    parser.add_argument("--seed", type=int, help="Override the descriptor's generation seed")
    args = parser.parse_args()
    godot = shutil.which("godot")
    if not godot:
        parser.error("Godot is required; generation uses the same implementation as the editor")
    command = [godot, "--headless", "--path", str(Path(__file__).resolve().parents[1]),
               "-s", "scripts/generate_map_cli.gd", "--", args.map, args.output_dir]
    if args.seed is not None:
        command.append(str(args.seed))
    raise SystemExit(subprocess.call(command))


if __name__ == "__main__":
    main()
