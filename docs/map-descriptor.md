# Cylinder map descriptor, schema 3

`map_config.json` is the sole authored definition. No manifest/descriptor/biome
sidecar is consulted. The engine implements algorithms; the map supplies world
values. Missing required fields are errors, not invitations to invent a world.
The bundled map is a complete example. No compatibility contract with older
schemas is provided.

## Coordinates and resolution

Distances are metres. The cylinder axis is Z; its centre is the origin.
`geometry.cylinder_radius_m` and `cylinder_length_m` are authoritative.
`theta = TAU * u`, `z = (v - 0.5) * length`, position is
`((radius-height)*cos(theta), (radius-height)*sin(theta), z)`.
Positive height points inward. U wraps; V clamps at the end caps.
Raster sample (x,y) is at `(x/width, y/(height-1))`. Elevation interpolates
bilinearly, including the U seam. Biome IDs use nearest samples. Each layer
owns its dimensions, independently of every other layer and mesh tessellation.
Minimum dimensions are 2x2; implementation resource limits are validation limits,
not physical world dimensions. Mesh segments are independently map-configured.

## Definition sections

- `schema_version`: 3; `world_id`: persistent string; human `display_name`,
  `description`, `author`, `license`.
- `geometry`: radius, length, elevation variance and water sea level in metres.
- `rendering`: radial/length segments, end-cap rings, dish depth, include caps,
  biome texture resolution, end-cap texture and tint.
- `environment`: sky, ambient and air RGBA colors, ambient energy, air density,
  air-distance bounds, and `water` shader properties (shallow/deep RGBA,
  wave speed, roughness, specular).
- `simulation`: per-component exported settings (`light_bar`, `weather_system`,
  `player`, `particle_emitter`). Only exported scalar/color properties are applied;
  radius/length always derive from `geometry`. No conflicting geometry copies.
- `lighting_palette`: named colors for daylight, dawn, dusk, night and lamp spine.
- `shader_parameters`: map-owned artistic parameters by shader filename. Runtime
  geometry, current weather, light LUTs and layer textures take precedence over
  static shader values. Shader algorithms and engine resource limits remain code.
- `generation`: seed, independent layer dimensions, physical noise wavelengths,
  base height, relief, ridge amplitude, erosion iterations/talus slope,
  hydrology carving settings, climate field wavelength and spawn clearance.
- `biomes`: dictionary keyed by permanent string ID. Each has a unique integer
  `raster_id` (0..255), name, target weight, elevation range in metres, maximum
  slope in degrees, moisture/temperature preferences (0..1), texture path,
  texture repeat size in metres, roughness, RGBA tint, and clutter/object rules.
  `submerged` distinguishes waterbed from land. Weights are normalized across all
  enabled biomes, including submerged biomes; zero disables generation.
  Material colors are never IDs.
- `objects.model_catalog`: dictionary of stable asset IDs, each with name,
  scene path, behavior type/variant, RGBA tint, light RGBA,
  energy, `light_range_m` and flicker. Placement-level `light_range_m`
  overrides the catalog value; the obsolete `light_range` key is invalid.
  IDs do not encode behavior enum numbers.
- `ground_clutter`: view radius, chunk size, density multiplier and model catalog.
  Biome `clutter` rules select model IDs, density per square metre, scale range,
  and a color palette. Any palette may contain one or more RGBA stops; uniform
  interpolation traverses consecutive stops, including alpha. Palettes tint the
  source material; they are not a list of discrete random swatches.
- Biome `objects` rules select catalog IDs, density per square kilometre and
  scale range. Placement is seeded, measured in physical area, and rejects
  incompatible terrain. Generated instance IDs and spawn are saved.
- `files`: elevation and terrain paths plus object placement JSON path.

Colors are four sRGB components in [0,1]. Appearance tint multiplies source
material color. Terrain tint alpha is coverage against the untinted texture
(the solid collision surface does not disappear). Object alpha controls visual
opacity. Light RGBA RGB controls emission color; alpha multiplies light energy.
Appearance tint and emitted light tint are independent.

## Layers, assets and persistence

Elevation uses `CYLH` binary: four ASCII magic bytes, little-endian uint32 width
and height, then width*height little-endian float32 normalized samples in row
order. Metres = sample * elevation variance. This avoids PNG quantization.
Terrain is an L8 PNG of biome raster IDs, never an RGB classification image.
The descriptor accepts up to 4,194,304 samples per layer so saved maps can be
loaded independently from generation capacity. On mobile, generation currently
limits elevation to 2,097,152 samples and the packed biome score buffer to
8,388,608 values. Over-budget generation reports an error and preserves the
loaded map. Generation yields during balancing so the interface can update.
Decoded dimensions are authoritative; descriptor resolutions govern the next
generation only. Sampling and rendering use the decoded dimensions.

New textures are decoded and copied into `assets/` as PNG; models are imported
as self-contained GLB and copied into `assets/`. Imported GLB is data, not script.
Package-relative paths must stay within the map. Bundled procedural scenes may
use explicit `res://` references; these require this engine's bundled assets.
Runtime imports do not accept arbitrary scripted scenes.

Edits are made on a copy of the document. Generation writes a new complete user
map directory and validates it before activation. The active-world pointer is
changed only after successful loading. Failed generation leaves the previous
world intact. Saving a document uses a temporary file and atomic rename.
Bundled `res://` maps are read-only. Saves go into `user://maps/`, which uses
Android's app-private writable storage and requires no shared-storage permission.
Copy bundled data through `FileAccess` so resource packs are supported. Exported
biome PNGs may exist only as imported textures; decode those through the resource
loader and write a lossless PNG when making the writable map copy. Biome textures
must use lossless import without mipmaps to preserve the raster IDs.

The editor saves imported assets and definitions without requiring regeneration.
Changing target weights affects the next generation; changing appearance affects
the current map. Existing raster IDs must not be reassigned on rename.

## Generation contract

Noise is evaluated in metres on a circular 3D embedding, so U is periodic and
world aspect ratio does not distort hills. Seeded broad relief and ridges are
combined with hydrology carving and bounded thermal erosion. Classification
samples elevation at the biome layer's own world coordinates and measures slopes
in physical units. Before classification, monotonic quantile transport reshapes elevation to the
weighted mixture of the selected biomes' elevation ranges. This preserves the
ordering of ridges and basins while moving land area toward the requested mix.
Climate fields provide contiguous regions; iterative weight correction then fits
biome coverage. Elevation and slope constraints take precedence in classification.
Where no enabled biome fits, the closest is used and `generation_warnings` reports
the unsuitable fraction. `generation_report` records requested and achieved
fractions for each enabled biome; these are not presented as exact quotas. This is a terrain synthesis model,
not a geological or fluid simulation. Changing resolution changes resolved
small-scale detail and erosion discretization, not physical feature wavelengths.

## Editor workflow and limits

EDIT → REGEN MAP opens the map editor. Expand geometry/generation, environment,
simulation, object catalog or individual biome sections. Biome weights are
relative, not percentages required to sum to 100. Zero disables a biome for the
next generation without invalidating existing raster IDs. Add Biome allocates a
new unused byte ID. Name changes preserve it.

The biome panel supports importing PNG/JPEG/WebP ground textures, selecting any
clutter model or object-catalog mesh as clutter, self-contained GLB imports,
per-rule density/scale controls, and adding/removing RGBA palette stops.
Object catalog RGBA controls affect future placements and generated objects;
SELECT's tint controls apply to the aimed existing object. Map Save preserves
current authored placements. Object Save records transforms, tint, light settings,
instance/asset IDs and the editor's default player location in the map itself.
There is no separate legacy snapshot format.

Ground textures may be at most 8192 pixels on either side and 16,777,216 pixels
total; editor imports are limited to 64 MiB encoded. This total-pixel ceiling
keeps decoded texture memory bounded on mobile. GLB imports are limited to 64 MiB.
Raster dimensions are 2..4096 with at most 4,194,304 samples per layer. Biome count
is 1..256, and biome-count × terrain-samples may not exceed 16,777,216. Texture
array layers are resized to the map's 16..512 `biome_texture_resolution`; imported
source images remain unchanged. The current mesh builder supports 16..256 radial
segments, 4..360 axial segments and 8..64 cap rings. These bounds are explicit
performance constraints, not alternative physical dimensions.

Thermal erosion is bounded to 0..64 iterations. Hydrology uses basin/channel
carving, not a fluid simulation; disconnected or uphill local channel segments
are possible after elevation reshaping. Object count is bounded by the map's
`object_limit` (maximum 50,000), with a warning when capped. A map with no dry
landing satisfying spawn clearance is rejected without activating it.

Imported GLB scenes keep their materials and mesh hierarchy. Ground clutter
instances mesh parts only (no per-clutter physics, animation or lights). Bundled
procedural models are engine dependencies; imported models/textures are packaged.
Shader parameters in the map are applied to duplicated object materials, so one
map's values do not mutate shared model resources. Runtime systems may subsequently
override dynamic shader values. The implemented `.cylmap` import/export workflow
is documented under User map library below; imports receive a new `world_id`.

## Verification

Run `./build.sh test` for generation/layer round-trips, map loading/editor smoke,
imports/relocation, object editing/persistence, and simulation regressions.
`test_map_scene.gd -- --screenshots` additionally captures desktop/mobile-size UI
and world frames when a rendering display is available. Headless tests do not
establish GPU appearance or Android native file-picker behavior.

`weather_palette` defines precipitation/dust colors; `environment.water` also
provides absorption coefficients (`extinction_rgb`), reflection, foam, caustic
and overcast colors. Named light/weather palettes are editable in the map editor.

Placement records reference a catalog `asset`. Surface records use `theta`, `z`,
`yaw_rad` and scale and follow sampled terrain at load. Edited placements save an
explicit 12-number local transform (basis columns then origin); that transform
takes precedence over `theta`/`z` and remains fixed in metres when geometry
changes. Once an edit is saved as a transform, redundant `theta`/`z` fields are
removed. Appearance and light overrides are stored per instance. Ground-clutter palettes apply to
instanced mesh appearance; they do not instantiate light devices for every blade.

The included full-resolution seed-42 check (1024×512 elevation, 512×256 biome
IDs) produced a maximum absolute biome-area error below 0.004 (0.4 percentage
points). This measures one descriptor/seed, not a guarantee for every constraint
combination. Tests cover both successful imports and persistence; rendered
appearance still needs an available GPU/display and target-device review.

A positive object `light_energy` adds a basic omnidirectional light when the
model has no embedded light. Zero energy disables emission. The light color
alpha scales that energy; it does not change mesh opacity.

## User map library and application updates

The bundled `assets/maps/default/` package is the app's current read-only template.
On first launch the engine creates a complete writable copy in `user://maps/`,
assigns a random `world_id`, and selects it through `user://active_map.txt`.
`template_revision` records the source descriptor's SHA-256. Installing an app
update replaces the bundled template, never the selected user map or its edits.
“New map from current app template” creates another independent copy using the
new template. App-private maps survive normal upgrades; uninstalling/clearing app
data removes them, so use exports for backups.

`name` is the user-facing map name. It is separate from filesystem directory names
and `world_id`. Save writes a staged revision and activates it after successful
loading; Save As assigns a fresh identity. `saved_at_unix` orders revisions, and
the load picker shows the newest published revision for each identity. The
internal `.map_ready` marker excludes incomplete saves/imports from the picker.
Loading a different map replaces unsaved edits; the editor states this beside
the load controls. The name field is available before saving or generating.

`.cylmap` is a standard ZIP containing `map_config.json`, the declared elevation,
biome and placement files, and package-relative assets. Export saves current
editor definitions and placements first. Import validates archive paths, file
counts and decompressed sizes, descriptor, asset references and terrain layers
before publishing a new identity. Archive scripts/Godot scenes are rejected;
custom models use self-contained GLB. Maximum archive/unpacked size is 512 MiB,
with up to 4096 entries. ZIP64, encrypted and multi-disk archives are unsupported.
Native file dialogs handle Android import/export selection.

Explicit `res://` model/texture references still refer to assets supplied by this
app; exports retain these references. Imported custom assets are included in the
archive. Thus maps using bundled resources require an app version containing
those resources. User map definitions and terrain do not track template updates.
