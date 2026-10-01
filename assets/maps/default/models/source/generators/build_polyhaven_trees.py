"""Download CC0 Poly Haven trees and export mobile-friendly GLBs with Blender.

Run with:
  blender --background --python build_polyhaven_trees.py

The original source files are downloaded to a temporary directory. Optimized,
texture-embedded GLBs are written under this map's models/objects/trees folder.
"""

import json
import os
import shutil
import tempfile
import urllib.request

import bpy
from mathutils import Vector


MAP_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
OUTPUT_DIR = os.path.join(MAP_DIR, "models", "objects", "trees")
USER_AGENT = "CylinderMapAssetBuilder/1.0 (Poly Haven CC0 asset download)"

# Output key -> Poly Haven asset slug and triangle budget.
TREES = {
    "oak": ("tree_small_02", 55000),
    "pine": ("pine_sapling_small", 45000),
    "birch": ("island_tree_01", 55000),
    "willow": ("island_tree_02", 55000),
    "cherry_blossom": ("jacaranda_tree", 45000),
    "dead_standing": ("dead_quiver_trunk", 25000),
    "fallen_log": ("dead_tree_trunk_02", 25000),
}


def _request(url):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=90) as response:
        return response.read()


def download_source(asset_slug, destination):
    metadata = json.loads(_request("https://api.polyhaven.com/files/" + asset_slug))
    gltf_entry = metadata["gltf"]["1k"]["gltf"]
    files = {"model.gltf": gltf_entry}
    files.update(gltf_entry.get("include", {}))
    for relative_path, entry in files.items():
        target = os.path.join(destination, relative_path)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, "wb") as output:
            output.write(_request(entry["url"]))
    return os.path.join(destination, "model.gltf")


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.cameras, bpy.data.lights):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def import_and_optimize(source_path, output_path, triangle_budget):
    clear_scene()
    bpy.ops.import_scene.gltf(filepath=source_path)
    imported = list(bpy.context.scene.objects)
    meshes = [obj for obj in imported if obj.type == "MESH"]
    if not meshes:
        raise RuntimeError("No mesh data imported from " + source_path)

    source_triangles = sum(sum(max(len(poly.vertices) - 2, 1) for poly in obj.data.polygons) for obj in meshes)
    ratio = min(1.0, float(triangle_budget) / max(float(source_triangles), 1.0))
    for obj in meshes:
        if len(obj.data.polygons) <= 4:
            continue
        modifier = obj.modifiers.new("MobileTreeLOD", "DECIMATE")
        modifier.ratio = ratio
        modifier.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj.select_set(False)

    # Place each imported model on the ground and center its footprint so the
    # scene origin is the trunk base used by the map placement system.
    depsgraph = bpy.context.evaluated_depsgraph_get()
    bounds = []
    for obj in meshes:
        evaluated = obj.evaluated_get(depsgraph)
        bounds.extend(obj.matrix_world @ Vector(corner) for corner in evaluated.bound_box)
    min_x = min(point.x for point in bounds)
    max_x = max(point.x for point in bounds)
    min_y = min(point.y for point in bounds)
    max_y = max(point.y for point in bounds)
    min_z = min(point.z for point in bounds)
    max_z = max(point.z for point in bounds)
    shift = Vector((-(min_x + max_x) * 0.5, -(min_y + max_y) * 0.5, -min_z))
    roots = [obj for obj in imported if obj.parent is None]
    for obj in roots:
        obj.location += shift

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=output_path,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_image_format="AUTO",
        export_materials="EXPORT",
        use_selection=False,
    )
    final_triangles = sum(sum(max(len(poly.vertices) - 2, 1) for poly in obj.data.polygons) for obj in meshes)
    print("Optimized %s: %d -> %d triangles; height %.2fm; %.1f MB" % (
        os.path.basename(output_path), source_triangles, final_triangles,
        max_z - min_z, os.path.getsize(output_path) / 1_000_000.0))


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="cylinder_polyhaven_trees_") as temp_dir:
        for variant, (asset_slug, triangle_budget) in TREES.items():
            output_path = os.path.join(OUTPUT_DIR, variant + ".glb")
            if os.path.exists(output_path):
                print("Already built %s; skipping" % output_path, flush=True)
                continue
            asset_dir = os.path.join(temp_dir, asset_slug)
            os.makedirs(asset_dir)
            source_path = download_source(asset_slug, asset_dir)
            import_and_optimize(source_path, output_path, triangle_budget)


if __name__ == "__main__":
    main()
