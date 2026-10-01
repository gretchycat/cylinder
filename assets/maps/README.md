# Map packages

Each map lives in `assets/maps/<mapname>/`. Its `map_config.json` points to height and terrain images, model assets, and optional terrain textures. Asset paths in the config are relative to that map directory, so each map can carry its own models and visual setup.

The `ground_clutter` section supports `grassland_density_multiplier` and `farmland_density_multiplier` (default `1.0`, capped at `10.0`) to control grass and crop placement density independently per map.

Each procedural model may set `gradient_mode` to `linear`, `radial`, or `none`, plus `gradient_extent_m`. Linear gradients blend from the base color at the ground to the tip color along the model height. Radial gradients blend from the model's local center outward, for round forms such as rocks, shrubs, and mushrooms.

Model catalog `scene_path` values accept Godot imported 3D scenes such as `.gltf`, `.glb`, `.fbx`, `.dae`, `.blend`, `.tscn`, and `.scn`. Ground clutter also accepts an imported mesh resource such as `.obj`; it is converted to a `MeshInstance3D` for instancing. Godot recommends glTF for 3D scenes. Blender source files need Blender available during editor import, and OBJ has fewer material and scene features than glTF.

The optional `terrain_textures` object in `map_config.json` can override the default terrain textures. Each terrain key (`grass`, `sand`, `dirt`, `farmland`, `rocks`, `concrete`, or `road`) takes up to three image paths. `end_cap_ribs` takes one image path. For example:

```json
"terrain_textures": {
  "grass": ["textures/grass_a.webp", "textures/grass_b.jpg", "textures/grass_c.png"],
  "end_cap_ribs": "textures/ribs.tga"
}
```

Godot image imports include BMP, DDS, KTX, EXR, HDR, JPEG, PNG, TGA, WebP, and SVG. Height and terrain maps use the same image decoder; height maps are read as grayscale and terrain maps are matched to the terrain palette. KTX is limited to 2D images by Godot's importer.
