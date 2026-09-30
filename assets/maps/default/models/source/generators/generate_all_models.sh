#!/bin/bash
# Master script to regenerate all 3D models for the Cylinder project.
# Requires: blender, openscad, python3
#
# Usage: bash assets/maps/default/models/source/generators/generate_all_models.sh
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TREE_DIR="$MODEL_DIR/trees"
MAP_DIR="$(cd "$MODEL_DIR/../.." && pwd)"

echo "=== Cylinder 3D Model Generator ==="
echo "Map package: $MAP_DIR"
echo ""

# Create output directories
mkdir -p "$MODEL_DIR"
mkdir -p "$TREE_DIR"

# Generate Blender models
echo "[1/7] Generating tree models (6 variants)..."
blender --background --python "$SCRIPT_DIR/generate_trees.py" 2>&1 | tail -1

echo "[2/7] Generating campfire model..."
blender --background --python "$SCRIPT_DIR/generate_campfire.py" 2>&1 | tail -1

echo "[3/7] Generating bonfire model..."
blender --background --python "$SCRIPT_DIR/generate_bonfire.py" 2>&1 | tail -1

echo "[4/7] Generating house model..."
blender --background --python "$SCRIPT_DIR/generate_house.py" 2>&1 | tail -1

echo "[5/7] Generating windmill model..."
blender --background --python "$SCRIPT_DIR/generate_windmill.py" 2>&1 | tail -1

echo "[6/7] Generating bridge model..."
blender --background --python "$SCRIPT_DIR/generate_bridge.py" 2>&1 | tail -1

# Generate OpenSCAD models and convert to GLB
echo "[7/7] Generating lamp post and beacon lantern (OpenSCAD)..."
openscad -o "$MODEL_DIR/lamp_post.stl" "$SCRIPT_DIR/lamp_post.scad" 2>&1 | tail -1
openscad -o "$MODEL_DIR/beacon_lantern.stl" "$SCRIPT_DIR/beacon_lantern.scad" 2>&1 | tail -1

blender --background --python "$SCRIPT_DIR/convert_scad_to_glb.py" -- \
    "$MODEL_DIR/lamp_post.stl" "$MODEL_DIR/lamp_post.glb" lamp_post 2>&1 | tail -1
blender --background --python "$SCRIPT_DIR/convert_scad_to_glb.py" -- \
    "$MODEL_DIR/beacon_lantern.stl" "$MODEL_DIR/beacon_lantern.glb" beacon_lantern 2>&1 | tail -1

# Assign tree variants to object map
echo ""
echo "Assigning tree variants to object_map.json..."
if [[ -f "$SCRIPT_DIR/assign_tree_variants.py" ]]; then
    python3 "$SCRIPT_DIR/assign_tree_variants.py"
fi

echo ""
echo "=== All models generated ==="
echo "Models:"
find "$MODEL_DIR" -name "*.glb" -printf "  %p (%s bytes)\n" | sort
echo ""
echo "Generation scripts:"
find "$SCRIPT_DIR" -type f -printf "  %f\n" | sort
