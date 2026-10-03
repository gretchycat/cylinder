#!/usr/bin/env python3
"""
convert_map_package.py
----------------------
CLI & Python library tool for importing, converting, upsampling, and exporting
O'Neill Cylinder world map packages into the dedicated .cylmap format.

Features:
- Imports legacy map directories (containing map_config.json, elevation_map.png, terrain_map.png, object_map.json, biomes_manifest.json)
  or existing unpacked .cylmap directories and archives.
- Preserves physical cylinder dimensions (radius, length, elevation variance, water level)
  independently of raster image resolutions (u/v stretching onto the physical cylinder surface).
- Converts 8-bit elevation maps to 16-bit PNG (R16 / uint16) for high-precision elevation sampling.
- Assigns stable UUIDs to all placed objects, settlements, and spawn points.
- Builds map_manifest.json (v2.0.0 schema) with extension hooks for entities, events, relationships, and networking.
- Exports to either a single-file .cylmap ZIP container or an unpacked .cylmap directory.

Usage:
  python3 scripts/convert_map_package.py --input assets/maps/default --output build/default.cylmap --format zip
  python3 scripts/convert_map_package.py --input assets/maps/default --output assets/maps/default.cylmap --format dir
"""

import os
import sys
import json
import uuid
import zipfile
import argparse
import shutil
from pathlib import Path
from typing import Dict, Any, List, Tuple, Optional

import numpy as np
from PIL import Image

# Version of the .cylmap specification
SCHEMA_VERSION = "2.0.0"

DEFAULT_PALETTE = {
    "0": [35, 105, 195, 255],    # Water
    "1": [225, 190, 125, 255],   # Sand
    "2": [115, 78, 48, 255],     # Dirt
    "3": [60, 140, 42, 255],     # Grass
    "4": [165, 120, 50, 255],    # Farmland
    "5": [95, 100, 108, 255],    # Rocks
    "6": [175, 180, 188, 255],   # Concrete
    "7": [42, 44, 48, 255]       # Road
}

def generate_stable_id(prefix: str = "obj") -> str:
    """Generate a clean UUID-v4 based identifier."""
    return f"{prefix}_{uuid.uuid4().hex[:12]}"

class MapPackageConverter:
    """Handles importing, converting, and exporting O'Neill Cylinder map packages."""

    def __init__(self, input_path: str, output_path: str, fmt: str = "zip", elevation_bits: int = 16):
        self.input_path = Path(input_path).resolve()
        self.output_path = Path(output_path).resolve()
        self.fmt = fmt.lower()
        self.elevation_bits = elevation_bits
        self.temp_dir: Optional[Path] = None

    def convert(self) -> Path:
        """Run the full conversion pipeline and return the final output path."""
        print(f"[MapConverter] Loading input package from: {self.input_path}")
        if not self.input_path.exists():
            raise FileNotFoundError(f"Input path does not exist: {self.input_path}")

        # Staging directory for transactional assembly
        staging_dir = self.output_path.parent / f".staging_{uuid.uuid4().hex[:8]}"
        if staging_dir.exists():
            shutil.rmtree(staging_dir)
        staging_dir.mkdir(parents=True, exist_ok=True)

        try:
            # 1. Unpack input if it's a zip archive
            src_dir = self._prepare_source_directory(staging_dir)

            # 2. Read existing map_config.json / map_manifest.json
            config, manifest_existing = self._load_input_metadata(src_dir)

            # 3. Read & convert elevation map (8-bit to 16-bit PNG if requested)
            elev_info = self._process_elevation_map(src_dir, staging_dir, config)

            # 4. Read & process terrain biome map
            terrain_info = self._process_terrain_map(src_dir, staging_dir, config)

            # 5. Process & normalize object placements (assign stable UUIDs)
            objects_data = self._process_objects(src_dir, staging_dir, config)

            # 6. Copy biomes manifest
            biomes_data = self._process_biomes_manifest(src_dir, staging_dir, config)

            # 7. Copy bundled asset subdirectories (models, textures, attributions)
            self._copy_bundled_assets(src_dir, staging_dir)

            # 8. Build the unified v2.0.0 manifest
            manifest = self._build_manifest(
                config=config,
                existing_manifest=manifest_existing,
                elev_info=elev_info,
                terrain_info=terrain_info,
                objects_data=objects_data,
                biomes_data=biomes_data
            )

            # Write map_manifest.json
            manifest_file = staging_dir / "map_manifest.json"
            with open(manifest_file, "w", encoding="utf-8") as f:
                json.dump(manifest, f, indent=2)

            # Also write map_config.json for backwards compatibility with legacy engine code
            config_file = staging_dir / "map_config.json"
            with open(config_file, "w", encoding="utf-8") as f:
                json.dump(manifest, f, indent=2)

            # Write object_map.json
            obj_file = staging_dir / "object_map.json"
            with open(obj_file, "w", encoding="utf-8") as f:
                json.dump(objects_data, f, indent=2)

            # 9. Final export (ZIP or unpacked directory)
            final_path = self._finalize_export(staging_dir)
            print(f"[MapConverter] Conversion complete! Output saved to: {final_path}")
            return final_path

        finally:
            # Clean up staging directory
            if staging_dir.exists():
                shutil.rmtree(staging_dir, ignore_errors=True)

    def _prepare_source_directory(self, staging_dir: Path) -> Path:
        """If input is a zip archive, extract it to a temporary location; else return path."""
        if self.input_path.is_file() and self.input_path.suffix.lower() in [".zip", ".cylmap"]:
            extracted = staging_dir / "_unpacked_input"
            extracted.mkdir(parents=True, exist_ok=True)
            with zipfile.ZipFile(self.input_path, "r") as z:
                z.extractall(extracted)
            return extracted
        return self.input_path

    def _load_input_metadata(self, src_dir: Path) -> Tuple[Dict[str, Any], Optional[Dict[str, Any]]]:
        """Load map_config.json or map_manifest.json if available."""
        manifest_file = src_dir / "map_manifest.json"
        config_file = src_dir / "map_config.json"

        manifest_data = None
        if manifest_file.exists():
            with open(manifest_file, "r", encoding="utf-8") as f:
                manifest_data = json.load(f)

        config_data = {}
        if config_file.exists():
            with open(config_file, "r", encoding="utf-8") as f:
                config_data = json.load(f)
        elif manifest_data:
            config_data = manifest_data

        return config_data, manifest_data

    def _process_elevation_map(self, src_dir: Path, staging_dir: Path, config: Dict[str, Any]) -> Dict[str, Any]:
        """Load elevation PNG, record raster dimensions vs physical cylinder size, and convert to 16-bit uint16 PNG if requested."""
        elev_rel = config.get("files", {}).get("elevation_map", "elevation_map.png")
        elev_path = src_dir / elev_rel

        if not elev_path.exists():
            elev_path = src_dir / "elevation_map.png"

        if not elev_path.exists():
            print(f"[Warning] Elevation map image not found at {elev_path}, creating default flat heightmap.")
            arr = np.full((1024, 2048), 32768, dtype=np.uint16)
            img = Image.fromarray(arr)
            dest_file = staging_dir / "elevation_map.png"
            img.save(dest_file)
            return {
                "file": "elevation_map.png",
                "width": 2048,
                "height": 1024,
                "bit_depth": 16,
                "encoding": "PNG_R16",
                "elevation_variance_m": config.get("geometry", {}).get("elevation_variance_m", 100.0)
            }

        img = Image.open(elev_path)
        w, h = img.size
        print(f"[Elevation] Loaded '{elev_rel}' (Dimensions: {w}x{h}, Mode: {img.mode})")

        out_bit_depth = 16 if self.elevation_bits == 16 else 8
        dest_file = staging_dir / "elevation_map.png"

        if out_bit_depth == 16:
            if img.mode in ["I;16", "I", "F"]:
                arr = np.array(img, dtype=np.uint16)
            elif img.mode == "L":
                # Convert 8-bit (0..255) to 16-bit (0..65535) via 257 multiplier
                arr_8 = np.array(img, dtype=np.uint8)
                arr = (arr_8.astype(np.uint32) * 257).astype(np.uint16)
            else:
                gray = img.convert("L")
                arr_8 = np.array(gray, dtype=np.uint8)
                arr = (arr_8.astype(np.uint32) * 257).astype(np.uint16)

            out_img = Image.fromarray(arr)
            out_img.save(dest_file)
            encoding_name = "PNG_R16"
        else:
            if img.mode != "L":
                img = img.convert("L")
            img.save(dest_file)
            encoding_name = "PNG_L8"

        variance_m = config.get("geometry", {}).get("elevation_variance_m", 100.0)

        return {
            "file": "elevation_map.png",
            "width": w,
            "height": h,
            "bit_depth": out_bit_depth,
            "encoding": encoding_name,
            "elevation_variance_m": variance_m,
            "stretching_note": "Raster resolution (w, h) is stretched over physical cylinder size (2*pi*R by L)"
        }

    def _process_terrain_map(self, src_dir: Path, staging_dir: Path, config: Dict[str, Any]) -> Dict[str, Any]:
        """Load terrain biome PNG and save to output package."""
        terr_rel = config.get("files", {}).get("terrain_map", "terrain_map.png")
        terr_path = src_dir / terr_rel

        if not terr_path.exists():
            terr_path = src_dir / "terrain_map.png"

        dest_file = staging_dir / "terrain_map.png"

        if terr_path.exists():
            img = Image.open(terr_path)
            w, h = img.size
            print(f"[Terrain] Loaded '{terr_rel}' (Dimensions: {w}x{h}, Mode: {img.mode})")
            shutil.copy2(terr_path, dest_file)
        else:
            print(f"[Warning] Terrain map image not found at {terr_path}, creating default meadow terrain map.")
            w, h = 512, 256
            arr = np.full((h, w, 4), (60, 140, 42, 255), dtype=np.uint8)
            img = Image.fromarray(arr)
            img.save(dest_file)

        return {
            "file": "terrain_map.png",
            "width": w,
            "height": h,
            "encoding": "PNG_PALETTE",
            "palette": DEFAULT_PALETTE,
            "stretching_note": "Raster resolution (w, h) is stretched over physical cylinder size (2*pi*R by L) independently of elevation resolution"
        }

    def _process_objects(self, src_dir: Path, staging_dir: Path, config: Dict[str, Any]) -> Dict[str, Any]:
        """Load object_map.json and assign permanent UUIDs to placed objects."""
        obj_rel = config.get("files", {}).get("object_map", "object_map.json")
        obj_path = src_dir / obj_rel

        if not obj_path.exists():
            obj_path = src_dir / "object_map.json"

        data: Dict[str, Any] = {}
        if obj_path.exists():
            with open(obj_path, "r", encoding="utf-8") as f:
                data = json.load(f)
        else:
            print(f"[Warning] Object map JSON not found at {obj_path}.")
            data = {"placed_objects": [], "settlements": [], "spawn_points": []}

        placed_objects = data.get("objects", data.get("placed_objects", []))
        for obj in placed_objects:
            if "id" not in obj or not obj["id"]:
                obj["id"] = generate_stable_id("obj")

        settlements = data.get("settlements", [])
        for s in settlements:
            if "id" not in s or not s["id"]:
                s["id"] = generate_stable_id("settlement")

        spawns = data.get("spawn_points", data.get("spawns", []))
        for sp in spawns:
            if "id" not in sp or not sp["id"]:
                sp["id"] = generate_stable_id("spawn")

        data["objects"] = placed_objects
        data["placed_objects"] = placed_objects
        data["settlements"] = settlements
        data["spawn_points"] = spawns
        data["total_placed_objects"] = len(placed_objects)

        print(f"[Objects] Processed {len(placed_objects)} objects, {len(settlements)} settlements, {len(spawns)} spawns with stable UUIDs.")

        # Copy object_map.png preview image if present
        obj_img_path = src_dir / "object_map.png"
        if obj_img_path.exists():
            shutil.copy2(obj_img_path, staging_dir / "object_map.png")

        return data

    def _process_biomes_manifest(self, src_dir: Path, staging_dir: Path, config: Dict[str, Any]) -> Dict[str, Any]:
        """Load or create biomes_manifest.json."""
        bio_rel = config.get("files", {}).get("biomes_manifest", "biomes_manifest.json")
        bio_path = src_dir / bio_rel

        if not bio_path.exists():
            bio_path = src_dir / "biomes_manifest.json"

        data: Dict[str, Any] = {}
        if bio_path.exists():
            with open(bio_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            shutil.copy2(bio_path, staging_dir / "biomes_manifest.json")
        else:
            data = {"version": "1.0.0", "biomes": {}}
            with open(staging_dir / "biomes_manifest.json", "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)

        return data

    def _copy_bundled_assets(self, src_dir: Path, staging_dir: Path) -> None:
        """Copy models/, textures/, and documentation files into staging."""
        for sub in ["models", "textures"]:
            sub_path = src_dir / sub
            if sub_path.exists() and sub_path.is_dir():
                dest_sub = staging_dir / sub
                if dest_sub.exists():
                    shutil.rmtree(dest_sub)
                shutil.copytree(sub_path, dest_sub)
                print(f"[Assets] Copied '{sub}/' folder into package.")

        for doc_file in ["ATTRIBUTIONS.md", "README.md"]:
            doc_path = src_dir / doc_file
            if doc_path.exists() and doc_path.is_file():
                shutil.copy2(doc_path, staging_dir / doc_file)

    def _build_manifest(
        self,
        config: Dict[str, Any],
        existing_manifest: Optional[Dict[str, Any]],
        elev_info: Dict[str, Any],
        terrain_info: Dict[str, Any],
        objects_data: Dict[str, Any],
        biomes_data: Dict[str, Any]
    ) -> Dict[str, Any]:
        """Build unified v2.0.0 map_manifest.json specification."""

        world_id = (
            existing_manifest.get("world_id") if existing_manifest else
            config.get("world_id", generate_stable_id("world"))
        )

        map_name = config.get("map_name", self.output_path.stem)
        display_name = config.get("display_name", map_name.replace("_", " ").title())

        # Physical geometry parameters
        geometry = {
            "cylinder_radius_m": float(config.get("geometry", {}).get("cylinder_radius_m", 4000.0)),
            "cylinder_length_m": float(config.get("geometry", {}).get("cylinder_length_m", 18000.0)),
            "endcap_radius_m": float(config.get("geometry", {}).get("endcap_radius_m", 4000.0)),
            "elevation_variance_m": float(config.get("geometry", {}).get("elevation_variance_m", 100.0)),
            "water_sea_level_m": float(config.get("geometry", {}).get("water_sea_level_m", 20.0))
        }

        # Environment & celestial settings
        celestial = config.get("celestial", {
            "day_length_hours": 24.0,
            "year_length_days": 365,
            "earth_latitude_deg": 35.0,
            "axial_tilt_deg": 23.44,
            "solar_lighting_mode": "SOLAR_CYCLE",
            "base_solar_intensity": 3.5,
            "midnight_intensity": 0.12
        })

        climate = config.get("climate_and_atmosphere", {
            "spin_direction": 1,
            "rotation_period_sec": 127.0,
            "base_gravity_m_s2": 9.5,
            "air_density": 1.225,
            "temperature_min_c": -10.0,
            "temperature_max_c": 38.0,
            "cloud_altitude_m": 1250.0,
            "cloud_thickness_m": 250.0,
            "cloud_coverage": 0.55
        })

        manifest = {
            "schema_version": SCHEMA_VERSION,
            "world_id": world_id,
            "map_name": map_name,
            "display_name": display_name,
            "version": config.get("version", "2.0.0"),
            "author": config.get("author", "Colony Architect"),
            "description": config.get("description", "O'Neill Cylinder World Map Package"),
            "license": config.get("license", "CC-BY-4.0"),
            "geometry": geometry,
            "celestial": celestial,
            "climate_and_atmosphere": climate,
            "layers": {
                "elevation": elev_info,
                "terrain": terrain_info,
                "object_preview": {
                    "file": "object_map.png"
                }
            },
            "objects": {
                "model_catalog": config.get("objects", {}).get("model_catalog", {}),
                "settlements": objects_data.get("settlements", []),
                "spawn_points": objects_data.get("spawn_points", []),
                "placed_objects_count": objects_data.get("total_placed_objects", 0),
                "placed_objects_source": "object_map.json"
            },
            "ground_clutter": config.get("ground_clutter", {
                "view_radius_m": 220.0,
                "chunk_size_m": 40.0,
                "density_multiplier": 1.0,
                "biomes_manifest": "biomes_manifest.json"
            }),
            "entities": config.get("entities", {"groups": [], "spawns": []}),
            "events": config.get("events", {"scheduled": [], "environmental_triggers": []}),
            "relationships": config.get("relationships", {"factions": [], "routes": []}),
            "networking": config.get("networking", {
                "irc_server": "",
                "irc_channel": "",
                "allow_multiplayer": False
            }),
            "files": {
                "manifest": "map_manifest.json",
                "elevation_map": elev_info["file"],
                "terrain_map": terrain_info["file"],
                "object_map": "object_map.json",
                "biomes_manifest": "biomes_manifest.json"
            },
            "extensions": config.get("extensions", {})
        }

        return manifest

    def _finalize_export(self, staging_dir: Path) -> Path:
        """Move staged directory to final zip archive or unpacked directory."""
        if self.fmt == "zip" or (self.output_path.suffix.lower() == ".cylmap" and not self.output_path.is_dir() and self.fmt != "dir"):
            # Prepare zip archive path
            zip_dest = self.output_path
            if zip_dest.suffix.lower() not in [".zip", ".cylmap"]:
                zip_dest = zip_dest.with_suffix(".cylmap")

            if zip_dest.exists():
                zip_dest.unlink()

            print(f"[Export] Creating ZIP archive at: {zip_dest}")
            with zipfile.ZipFile(zip_dest, "w", zipfile.ZIP_DEFLATED) as z:
                for root, _, files in os.walk(staging_dir):
                    for file in files:
                        full_p = Path(root) / file
                        rel_p = full_p.relative_to(staging_dir)
                        # Skip temporary files
                        if rel_p.parts[0].startswith("_"):
                            continue
                        z.write(full_p, rel_p)

            return zip_dest

        else:
            # Unpacked directory export
            dest_dir = self.output_path
            if dest_dir.exists():
                shutil.rmtree(dest_dir)
            
            shutil.copytree(staging_dir, dest_dir, ignore=shutil.ignore_patterns("_*"))
            print(f"[Export] Created unpacked directory package at: {dest_dir}")
            return dest_dir

def main():
    parser = argparse.ArgumentParser(description="O'Neill Cylinder Map Package Importer, Converter & Exporter")
    parser.add_argument("--input", "-i", type=str, required=True, help="Input map directory or .cylmap archive path")
    parser.add_argument("--output", "-o", type=str, required=True, help="Target output .cylmap file or directory path")
    parser.add_argument("--format", "-f", type=str, choices=["zip", "dir"], default="zip", help="Export format: 'zip' (.cylmap archive) or 'dir' (unpacked directory)")
    parser.add_argument("--elevation-bits", type=int, choices=[8, 16], default=16, help="Elevation map bit depth (default: 16 for high-precision uint16 PNG)")
    
    args = parser.parse_args()

    converter = MapPackageConverter(
        input_path=args.input,
        output_path=args.output,
        fmt=args.format,
        elevation_bits=args.elevation_bits
    )
    
    try:
        out = converter.convert()
        print(f"SUCCESS: Package exported to {out}")
    except Exception as e:
        print(f"ERROR: Conversion failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
