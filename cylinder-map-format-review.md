# Cylinder map format: descriptor/code review and Codex task brief

Repository: https://github.com/gretchycat/cylinder

Reviewed revision: `7e6153d93c54a4bd1dfa3831c6e79b2a206c4340` (2026-10-03).

Specification: [docs/map-descriptor.md at the reviewed revision](https://github.com/gretchycat/cylinder/blob/7e6153d93c54a4bd1dfa3831c6e79b2a206c4340/docs/map-descriptor.md).

## Task

Verify the findings below against the current checkout, then fix the remaining mismatches between schema 3's descriptor, the implementation, and the bundled example. Read and follow the current root AGENTS.md and any applicable nested instructions before making changes. No root AGENTS.md existed at the reviewed revision.

These findings come from source inspection and direct checks of the bundled map data. They are not claims that the affected cases were reproduced in Godot. The attempted `bash build.sh test` could not run because the review environment had no Godot executable. If newer commits already resolve a finding, confirm the resolution and avoid reintroducing changes.

Keep this task focused on the current format. Preserve unrelated work and the intended terrain, lighting, and geometry behavior. Do not implement the future event engine or IRC networking as part of these repairs.

## What matches the descriptor

- `map_config.json` is the authoritative authored definition; historical manifest/biome sidecars are not current inputs.
- Elevation uses the documented `CYLH` header and normalized float32 samples.
- Terrain uses biome raster IDs rather than RGB classification colors.
- Each layer has its own dimensions, independent of configured cylinder size and mesh tessellation.
- Placed instances have persistent IDs and refer to catalog assets by ID.
- The editor uses staged map revisions, writable user maps, and `.cylmap` archive import/export.
- The document loader retains the complete parsed dictionary, and definition saving duplicates it rather than reconstructing only selected fields. Optional future sections therefore remain available for preservation.

Direct checks of the bundled data found:

- `elevation.cylh`: 2048×1024, correct magic/header/byte count, all samples finite and within [0,1].
- `biomes.png`: 2048×1024 grayscale; all stored IDs resolve to biome definitions.
- 220 placement records: unique instance IDs and valid asset references.
- Next-generation dimensions are 1024×512 elevation and 512×256 terrain. Their difference from the decoded files is allowed by the descriptor: generation settings govern the next generation, not current sampling dimensions.

## 1. Saved transform precedence is inconsistent

Priority: high.

The descriptor states that an explicit 12-number placement transform takes precedence over surface coordinates. The object factory honors this, but streaming does not.

- [MapObjectFactory.create](https://github.com/gretchycat/cylinder/blob/7e6153d93c54a4bd1dfa3831c6e79b2a206c4340/scripts/map_object_factory.gd#L6) applies `transform` after constructing the object.
- [ReferenceObjects._record_surface_position](https://github.com/gretchycat/cylinder/blob/7e6153d93c54a4bd1dfa3831c6e79b2a206c4340/scripts/reference_objects.gd#L232) checks `theta`/`z` before `transform`.
- [_capture_live_placement](https://github.com/gretchycat/cylinder/blob/7e6153d93c54a4bd1dfa3831c6e79b2a206c4340/scripts/reference_objects.gd#L301) writes a transform without removing or updating old surface coordinates.

Consequently, an edited object can render at its new transform but stream according to its previous location.

Fix all position consumers to follow the same documented precedence. Preserve optional metadata and define whether redundant coordinates are removed or kept as non-authoritative metadata. Check the local/global transform convention while doing this; the descriptor describes a local transform, whereas capture currently uses `global_transform`.

Acceptance: move a surface-authored object beyond the streaming retention distance from its old location; save and reload. It must appear near its new location and stream correctly even when the input record contains stale `theta`/`z` alongside a transform.

## 2. Malformed elevation does not follow the intended error path

Priority: high.

[_read_elevation_data](https://github.com/gretchycat/cylinder/blob/7e6153d93c54a4bd1dfa3831c6e79b2a206c4340/scripts/terrain_manager.gd#L67) returns a nonempty `{"error": "..."}` dictionary on failure. Both `read_elevation` and `load_elevation` check `parsed.is_empty()` instead of checking the error result, then access missing `width`, `height`, and `samples` fields.

Use an explicit success/error contract in both callers. Return a clean failure and preserve the parser's specific diagnostic. Ensure failed layer loading leaves the previously loaded map/layers intact.

Acceptance: missing file, wrong magic, truncated samples, invalid dimensions, and a non-finite or out-of-range sample each produce a useful failure without invalid dictionary access. Test the static image-reader path as well as the normal layer-loading path.

## 3. Texture import and loading limits disagree

Priority: medium.

The descriptor and [editor import](https://github.com/gretchycat/cylinder/blob/7e6153d93c54a4bd1dfa3831c6e79b2a206c4340/scripts/map_editor_panel.gd#L402) allow textures up to 8192×8192. However, [MapAssetLoader.load_image](https://github.com/gretchycat/cylinder/blob/7e6153d93c54a4bd1dfa3831c6e79b2a206c4340/scripts/map_asset_loader.gd#L125) defaults to 16,777,216 pixels. Biome asset validation uses that default, so a texture accepted by the editor can be rejected when the map is validated or loaded.

Define one consistent policy for ground-texture imports, package validation, and rendering. Either support the documented limit throughout or deliberately revise the limit and documentation. Keep biome-raster limits separate from appearance-texture limits and consider mobile memory costs.

Acceptance: a valid image above the current pixel cap but within the advertised dimensions must either complete the import/save/reload workflow or be rejected during import with an accurate limit message. Use a compact test fixture rather than committing a large image.

## 4. Declared campfire shader parameters are not applied

Priority: medium.

The map config includes `shader_parameters["campfire_flame.gdshader"]`, consistent with the descriptor's map-owned shader parameter mechanism. But [SurfaceLightObject's model-loading and appearance path](https://github.com/gretchycat/cylinder/blob/7e6153d93c54a4bd1dfa3831c6e79b2a206c4340/scripts/surface_light_object.gd#L96) never applies MapRuntime shader parameters to the instantiated object's shader materials. Campfire and bonfire scenes retain their own flame parameter values.

Apply supported map-owned parameters to the appropriate object materials, including nested meshes and material overrides. Avoid mutating shared resources across objects or maps. Preserve the descriptor's precedence rules for dynamic runtime values.

Acceptance: changing a declared flame color or speed changes the relevant instantiated material; switching maps does not retain the previous map's override. Confirm scene reload and edited-object rebuild behavior.

## 5. Integer validation is weaker than the descriptor

Priority: medium.

[MapConfig.validate](https://github.com/gretchycat/cylinder/blob/7e6153d93c54a4bd1dfa3831c6e79b2a206c4340/scripts/map_config.gd#L106) uses `int(schema_version) != 3`, allowing fractional values such as `3.5` to pass as schema 3. [Biome raster validation](https://github.com/gretchycat/cylinder/blob/7e6153d93c54a4bd1dfa3831c6e79b2a206c4340/scripts/map_config.gd#L195) also casts IDs without rejecting fractional values first.

Require numerically integral values for these integer fields. Preserve compatibility with JSON values such as `3.0` and `5.0`, which are present in the bundled example and represent integers exactly. Check other explicitly integer-valued fields for the same inconsistency, without inventing a new schema.

Acceptance: valid integral values pass; fractional schema versions and raster IDs fail with clear messages; duplicate raster IDs still fail. Keep the bundled example valid.

## 6. Bundled placements still use an obsolete light-range key

Priority: medium.

All 220 bundled placement records contain `light_range` and none contain `light_range_m`. [MapObjectFactory.create](https://github.com/gretchycat/cylinder/blob/7e6153d93c54a4bd1dfa3831c6e79b2a206c4340/scripts/map_object_factory.gd#L6) reads `light_range_m`, so those per-instance values are ignored and catalog defaults are used instead. For example, `River_Bridge_1` has legacy range 38, while its catalog fallback is 50.

Align the bundled placements with the canonical schema. Verify whether the individual values are intended overrides before converting or removing them. Do not silently change effective lighting based solely on an unused legacy field. If a compatibility alias is introduced, define precedence when both keys occur and keep canonical saves consistent.

Acceptance: a canonical per-instance range override is applied and survives saving/reloading. The bundled example has a deliberate, documented resolution for its legacy fields.

## 7. Archive documentation contradicts itself

Priority: low.

The descriptor's editor-limits section says a `.cylmap` archive workflow is not part of the implementation. Its later user-map-library section describes that workflow, which is implemented in MapLibrary and connected to the editor.

Remove or update the stale statement and check the README for consistency. Document the current behavior accurately, including archive imports receiving a new world identity and bundled `res://` assets remaining engine dependencies.

## Future expansion hooks

The bundled definition contains `events`, `entities`, `relationships`, `extensions`, and `networking` sections. They are placeholders/preserved data, not implemented gameplay systems. No event execution or required-feature negotiation was found in the reviewed code.

Preserve these sections while fixing the issues above. Do not imply that retaining an event definition means the engine can execute it. Designing capability negotiation can be a later task; do not expand this repair into the original full RPG roadmap.

## Verification and completion

Add focused regression checks for the actual failure cases above, then run the relevant existing tests using `./build.sh test` with the project's supported Godot version. Source/data checks are useful but do not substitute for executing the affected Godot paths.

Report which findings were still present, what changed, and the exact checks run. Distinguish automated material/state checks from rendered visual verification and Android native-file-dialog testing. Report unavailable checks as unverified, not passed.
