# Maps

The authoritative specification is [Map descriptor, schema 3](../../docs/map-descriptor.md).
The complete bundled example is `default/map_config.json`.

A map contains one definition (`map_config.json`), float elevation (`elevation.cylh`),
a byte-ID biome raster (`biomes.png`), placements (`placements.json`), and imported
`assets/`. Definitions include geometry, generation settings, environment, biome
materials, clutter palettes, simulation settings and the object catalog.

In EDIT mode, open REGEN MAP to edit the map. Expand a biome to change its weight,
import a ground texture, choose clutter from either catalog, import a GLB, and edit
RGBA palette stops. Object palette entries have independent appearance and emitted
light colors. SELECT also offers tint controls for the object under the crosshair.
Save applies definitions and appearance; Generate replaces terrain and placements.
Both create a new writable map under `user://maps/`; the bundled example is unchanged.
The last activated map is remembered in `user://active_map.txt`.

Generate from the same implementation on the command line:

```sh
./build.sh maps default user://maps/my_world 123
```

The destination must not already exist. Edit `generation` resolutions in the source
map before generation; each layer stretches over the entire configured cylinder.

Historical `map_manifest.json`, `map_generation_descriptor.json`,
`biomes_manifest.json`, RGB terrain previews and the old conversion utility are
not inputs to schema 3. The engine does not merge them with the current definition.

## Saving and sharing maps

The app copies the bundled default template into writable `user://maps/` on first
launch. App upgrades preserve user maps; **New map from current app template**
starts a separate map using the latest bundled template.

Open the map editor (or tap **SAVE**), enter a map name, and choose **Save map**.
**Save as a new map** keeps the original map separately. Use the map picker and
**Load selected map** to switch maps; save unsaved changes before switching.
**Save and export map** writes a `.cylmap` ZIP archive, and **Import map** validates
and loads an archive as a separate user map. Custom models and textures travel
with the archive. Each import receives a new `world_id`; built-in `res://` asset
references remain dependencies on assets bundled with the app.
