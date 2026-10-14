# OpenUSD compatibility audit

**Repository:** `gretchycat/cylinder` checkout  
**Branch:** `main`  
**Commit:** `be0bed2c17073f8ed1dffd81245f8d67cfe32579`  
**Scope:** investigation only. This report does not change the runtime format or add a USD dependency.

## Executive conclusion

OpenUSD is feasible as a portable authoring/interchange layer, with caveats. It should not replace the current map package wholesale and should not be treated as the runtime gameplay database.

The recommended boundary is:

```text
USD stage/layers + source rasters + procedural descriptor
                         |
                 validated project importer
                         |
        engine-independent compiled world description/cache
                         |
              Godot terrain, shaders, streaming, physics
```

USD directly covers the scene-graph portion well: hierarchical prims, typed attributes, relationships, transforms, meshes, normals, UV primvars, material bindings, references, payloads, variants, time-varying values, and `UsdGeomPointInstancer`. Its composition model is useful for separating authored content, reusable assets, overrides, and optional payloads. See the [official USD introduction](https://openusd.org/dev/intro.html), [composition glossary](https://openusd.org/dev/glossary.html), [stage metrics](https://openusd.org/dev/user_guides/schemas/usdGeom/overview.html), [mesh schema](https://openusd.org/dev/api/class_usd_geom_mesh.html), and [PointInstancer API](https://openusd.org/release/api/class_usd_geom_point_instancer.html).

USD does not provide a standardized semantic for this project's normalized float terrain raster, categorical biome-ID raster, procedural biome rules, cylinder periodicity, radial gravity, Godot shaders, streaming budgets, collision generation, event execution, or mutable gameplay state. Those require project metadata/schema and import-time compilation. The best first implementation is therefore the hybrid approach: preserve editable source rasters and procedural parameters, author portable scene/asset/placement information in USD, and generate the existing Godot-oriented mesh, shader inputs, collision, clutter chunks, and spatial indexes as derived data.

This preserves procedural generation and mobile performance, permits non-cylinder consumers to use the scene portion, and avoids claiming that arbitrary USD stages can be bent into a cylinder without restrictions.

## 1. Evidence and current data flow

### 1.1 Package entry point and validation

`map_config.json` is the current authoritative descriptor. `scripts/map_config.gd:77-93` parses it, validates it, and attaches `map_directory`. Validation requires schema version **4**, a permanent `world_id`, and the sections `geometry`, `rendering`, `environment`, `generation`, `biomes`, `objects`, `ground_clutter`, `files`, `simulation`, `shader_parameters`, `lighting_palette`, and `weather_palette` (`scripts/map_config.gd:106-122`). The document is retained as a dictionary rather than reconstructed from a fixed field list.

The bundled `map_manifest.json` and `map_generation_descriptor.json` are present, but the current runtime loading path is `map_config.json`; the current descriptor points to `elevation.cylh`, `biomes.png`, and `placements.json` (`assets/maps/default/map_config.json:1427-1431`). `map_config.gd:527-534` exposes optional `entities`, `events`, and `relationships` dictionaries, but no executor was found. The bundled sections are placeholders/preserved data (`assets/maps/default/map_config.json:1347-1351,1422-1426,2156-2159`).

Loading is staged: `MapConfig.load_map_config()` validates the JSON, `MapLibrary.validate_package()` validates layers/assets, and `CylinderGenerator.load_map_package()` installs a configured `TerrainManager` only after the incoming package is valid (`scripts/map_library.gd:8-35`, `scripts/cylinder_generator.gd:142-182`). Saves use a temporary JSON file and rename (`scripts/map_config.gd:346-365`); map archives are handled by `scripts/map_library.gd:37-180`. Imported archives receive a new `world_id` (`map_library.gd:173-178`).

### 1.2 Actual inputs

| Input | Evidence and current meaning | Type/units/validation | Lifecycle |
|---|---|---|---|
| `map_config.json` | Geometry, rendering, environment, generation, biome catalog, object catalog, clutter catalog, simulation, shader parameters, palettes, optional future sections (`map_config.gd:106-290`; bundled file sections above). | JSON object; meters, seconds, degrees/radians, colors as RGBA arrays, normalized weights and enumerations. Required fields and numeric ranges are explicitly checked. `schema_version` must be integral value 4. | Authored definition plus saved editor state. |
| `elevation.cylh` | `TerrainManager._read_elevation_data()` expects `CYLH`, little-endian width/height, followed by exactly `width*height` float32 values (`terrain_manager.gd:70-98`). Samples must be finite normalized `[0,1]`; runtime multiplies by `geometry.elevation_variance_m` (`terrain_manager.gd:113-125`). | Binary float32 normalized raster; resulting elevation is meters. The checked-out bundled file is 3142×2250; descriptor generation settings may specify another future resolution. | Authored/generated terrain layer; loaded into an in-memory `PackedFloat32Array`. |
| `biomes.png` / terrain map | Loaded, converted to `Image.FORMAT_L8`, and every byte is checked against `biome_by_id` (`terrain_manager.gd:129-147`). | 8-bit categorical IDs, not RGB colors, weights, or interpolated values. The checked-out bundled file is 3142×2250. Nearest/rounded sampling is used at runtime (`terrain_manager.gd:188-193`). | Authored/generated classification layer. |
| Biome definitions | Each biome has unique `raster_id` 0–255, weight, elevation range, slope/climate preferences, `blended`, texture path, texture size, tint, roughness, clutter rules, and object rules (`map_config.gd:209-248`). | JSON; IDs are exact integers. `weight` is a generation preference, not a per-pixel blend weight. | Authored catalog and procedural-generation input. |
| Biome appearance textures | Each biome points to an image, commonly PNG, JPG, JPEG, or WebP through `MapAssetLoader`; rendering uploads an array of textures plus per-ID tint/size/roughness parameters (`cylinder_generator.gd:533-587`; `map_asset_loader.gd:206-304`). | Image asset; physical repeat size is `texture_size_m`. Texture pixel colors are appearance data, not classification IDs. | Authored external asset, copied/packaged and sampled by Godot shader. |
| End-cap texture | `rendering.end_cap_texture` is validated and bound separately (`map_config.gd:253-256`; `cylinder_generator.gd:571-576`). | Image asset and RGBA tint. | Authored rendering asset. |
| Procedural generation parameters | Noise wavelengths, seed, relief, climate, sea/lake/river settings, erosion, resolution, biome proportions, and limits are under `generation` (`map_config.gd:131-162`; `map_generator.gd:26-145`). | JSON; physical dimensions in meters, counts/iterations integer-valued, seed deterministic when supplied. If absent, validation creates a time/random-derived seed (`map_config.gd:144-145`). | Authored generator input; output is generated intermediate. |
| Generated POIs and report | Generator writes `pois.json` and stores `generation_report` (`map_generator.gd:839-872`). | JSON; POIs include IDs, fractions, 3D coordinates, type and elevation. | Generated intermediate/diagnostic; not a behavior engine. |
| Placed reference objects | `placements.json` records stable `id`, catalog `asset`, either surface `theta`/`z`/elevation or a packed 12-number transform, scale, yaw/pitch/roll, tint and light overrides. `MapObjectFactory` resolves the catalog scene and builds a `SurfaceLightObject` (`map_object_factory.gd:6-47`). | JSON; theta radians, z/elevation/offset/ranges meters, rotations radians, colors RGBA. IDs and asset references are validated (`map_config.gd:573-626`). | Authored placements plus mutable editor/runtime snapshot. |
| Object catalog/assets | `objects.model_catalog` maps stable catalog IDs to Godot `scene_path`, behavior/variant enums, tint, local-light fields, solid collision and optional collision configuration (`map_config.gd:263-290`; `map_asset_loader.gd:16-61`). | Godot PackedScenes/GLB-derived data in current implementation; package validation forbids unsafe unresolved content according to the library path. | Reusable asset definitions, engine-specific at runtime. |
| Ground clutter catalog/rules | `ground_clutter.models` points to procedural meshes/scenes and shader parameters; biome rules specify density, scale range, palette and model (`map_config.gd:235-246`; `clutter_manager.gd:91-169`). | JSON plus Godot scenes; density per m², scale unitless, chunk/view/fade distances meters. | Authored rules; runtime compiles into GPU MultiMeshes. |
| Ground clutter instances | `ClutterManager` samples biome/elevation, uses seeded random placement, builds transform/color batches, and assembles `MultiMeshInstance3D` chunks (`clutter_manager.gd:620-724`). | Derived transforms/colors; no durable per-instance gameplay identity. | Runtime/generated cache, spatially chunked and streamed. |
| Environment and simulation | Sky/air/water parameters, light-bar solar cycle, weather palettes, particles, player defaults, rotation and gravity-related values are descriptor sections (`map_config.gd:163-186`; `assets/maps/default/map_config.json:1352-1420,2428-2550`). Runtime adapters apply them to shaders/systems (`map_runtime.gd:9-45`). | JSON; colors, densities, pressure, intensities, speeds, periods, angles. | Authored world settings consumed by engine systems. |
| Shader parameter overrides | `shader_parameters` is a map-owned dictionary; `MapRuntime.shader_parameters()` applies compatible keys to shader materials (`map_runtime.gd:32-45`). Terrain/clutter paths use it; it is not a USD shader graph. | JSON values converted to Godot shader uniforms. | Authored override/engine-specific. |
| Events/entities/relationships/extensions/networking | Sections exist in the bundled descriptor, and getters preserve them (`map_config.gd:527-534`), but searches found no event dispatch, trigger evaluation, entity lifecycle, or network connection from map data. | Opaque JSON placeholder data. | Preserved authoring metadata, not runtime behavior. |
| Player mutable state | `WorldEditStorage` stores object records and optional player position, basis, pitch, and flying state (`world_edit_storage.gd:8-88`). | JSON; local/world transform arrays and validated finite values. | Mutable gameplay/editor state, separate from authored definitions in concept, though currently colocated in `placements.json`. |

### 1.3 Raster sampling, material resolution, and generation

The elevation raster maps normalized horizontal coordinate `u = theta/(2π)` periodically around the circumference and `v = z/length + 0.5` axially. `TerrainManager.get_elevation()` bilinearly samples both dimensions, wrapping x and clamping y (`terrain_manager.gd:177-186`). The terrain-ID raster maps with rounded x/y and wraps x, clamps y (`terrain_manager.gd:188-193`). Thus elevation is continuous/interpolated; classification is categorical/nearest-like and must not be filtered.

The generated tube uses `x=(R-elevation)cos(theta)`, `y=(R-elevation)sin(theta)`, `z=z` (`cylinder_generator.gd:664-704`). This is an inward-facing surface: larger terrain elevation moves toward the cylinder axis. The normal is derived from a five-point elevation stencil and points inward. The tube has a duplicated seam column (`radial_segments+1`) and periodic sampling. UVs are `(theta/(2π), (z+L/2)/L)` (`cylinder_generator.gd:665-710`). Vertex color carries normalized elevation and the terrain ID; the shader also receives the full ID image and a texture catalog (`cylinder_generator.gd:547-587`).

The shader uses the ID as a lookup into an array of biome textures and parameters. `blended` controls whether the material permits its terrain blending behavior; it is not a second raster of continuous weights. The terrain map is therefore a palette/index map. There is no evidence that neighboring layer values are composited as USD material opinions; the engine performs lookup/blending in the shader.

End caps are generated as inward-facing hemispherical bulkheads at `z=±L/2`, with cap-specific normals/UVs and structural terrain IDs (`cylinder_generator.gd:771-915`). Physics uses a separate lighter collision mesh (`cylinder_generator.gd:924-983`). The surface convention is not a generic flat-world convention and must be made explicit in any interchange schema.

Procedural generation occurs in `MapGenerator.generate()`, normally from the editor workflow, using `FastNoiseLite`, a seeded `RandomNumberGenerator`, worker tasks, periodic u-distance, climate fields, erosion, and biome balancing (`map_generator.gd:7-17,26-145,262-367`). The generated package writes the CYLH layer, terrain PNG, placements, POIs and report (`map_generator.gd:839-872`). A supplied seed gives reproducible intent, but exact cross-engine reproduction should not be promised: noise implementation, string hashing (`str(key).hash()`), floating-point behavior, generator version, and ordering are part of the effective algorithm and are not recorded as a formal algorithm version in USD today.

Clutter is a distinct runtime system. It uses map-configurable chunks (default 40 m here), worker-generated results, generation envelopes, cancellation/pruning, and GPU `MultiMesh` batches (`clutter_manager.gd:19-73,171-180,329-414,424-470,665-727`). Reference objects use a separate spatial index and 500 m chunk constant, 850 m spawn/1250 m retention defaults, a 256 live cap, and 24-per-tick placement assembly (`reference_objects.gd:291-373`). These budgets should remain runtime policy, not be encoded as if they were USD geometry semantics.

## 2. OpenUSD capability assessment

The following uses core USD terminology, not proposed project schemas.

* A `UsdStage` is the composed view of layers; prims form the hierarchy and carry typed attributes, relationships, metadata, and applied schemas. A stage should author `upAxis` and `metersPerUnit`; USD's official guidance says omitting them forces downstream assumptions ([stage metrics](https://openusd.org/dev/user_guides/schemas/usdGeom/overview.html)). USD's units are not a terrain coordinate convention: the project must still define cylinder radius, length, theta origin/direction, seam, and inward surface direction.
* `UsdGeomXformable`/`Xform` can represent authored rigid transforms and hierarchy. `UsdGeomMesh` supports points, topology, normals and primvars; UVs are ordinarily a `texcoord` primvar. Normal interpolation and face-varying/vertex interpolation are standard, but a mesh that is bent must have sufficient subdivision or the bend is only piecewise linear. The mesh schema does not know that a surface is a periodic cylinder.
* `UsdShadeMaterial`, shader networks, material bindings, `UsdPreviewSurface`, and renderer-specific contexts cover portable basic PBR materials. Material binding is a relationship and can be inherited or applied to `UsdGeomSubset`; it is not equivalent to Godot's shader parameter dictionary. See the [UsdShade overview](https://openusd.org/22.08/api/usd_shade_page_front.html) and [binding API](https://openusd.org/dev/api/class_usd_shade_material_binding_a_p_i.html). MaterialX can be a useful companion/interchange shading representation, but the Godot mobile shader still needs translation.
* References compose reusable assets; payloads are deferred references which can be loaded/unloaded; sublayers stack opinions; variants select authored alternatives. These are a good fit for asset libraries, authored-vs-overrides, LOD/representation choices, and optional runtime payloads. USD composition is not the same as the project's stream-generation scheduler; Godot still needs its own chunk lifecycle.
* `UsdGeomPointInstancer` is a direct fit for clutter/vegetation representations: prototypes plus `protoIndices`, positions, orientations, scales and optional stable `ids`. It is intentionally compact for very large instance populations ([official API](https://openusd.org/release/api/class_usd_geom_point_instancer.html)). It does not encode the project's biome-conditioned random generator, mobile density adaptation, or per-chunk cancellation; those are custom metadata/compiled runtime behavior.
* Time samples animate attribute values. They can represent transforms, visibility, or numeric state over time; they do not execute triggers, conditions, commands, or event graphs. The official time guide explicitly describes time samples as value sources ([Time and Animated Values](https://openusd.org/release/user_guides/time_and_animated_values.html)). Gameplay events remain a separate behavior system.
* Ordinary PNG/TIFF/EXR and other image files can be referenced by asset paths or custom attributes and consumed by an importer/shader. USD has no standard terrain-heightmap, biome-ID, splatmap, vegetation-density, or cylinder-terrain semantic schema. An image reference alone does not specify channel meaning, normalization, physical extent, wrap mode, color space, interpolation, or whether values are IDs. These must be project-defined. GeoTIFF is justified only if geographic CRS/georeferencing is needed; it does not solve cylinder semantics.
* glTF is a sensible companion for portable static models and basic PBR asset interchange. USD can reference a USD-converted model, but a project importer should retain the original glTF or a content-addressed source where round-trip matters. Godot scenes/GLBs remain engine-runtime assets in the current implementation.

## 3. Compatibility matrix

Risk labels: **1** direct standard representation; **2** USD plus project metadata/schema; **3** import-time transformation/bake; **4** separate runtime/behavior system; **5** unsupported/unclear until a subset is defined.

| Current concept | Source code/data | Standard USD representation | Custom schema needed? | Conversion needed? | Fidelity/round-trip risk | Runtime/performance impact | Recommendation |
|---|---|---|---|---|---|---|---|
| World identity/version/author/license | `map_config.gd:106-112`; JSON root | Stage metadata/custom asset metadata | Yes for project schema and package identity | No | Low | None | Keep in package manifest; mirror as USD metadata. |
| Cylinder radius/length/seam/topology | `map_config.json:1518-1522`; `cylinder_generator.gd:664-704` | Stage metadata plus a custom `CylinderSurface` prim/API schema | Yes | No for source form | High if omitted; USD mesh alone loses procedural intent | No effect until compiled | Preserve explicit geometry descriptor; never infer from mesh bounds. |
| CYLH normalized float32 elevation | `terrain_manager.gd:70-125` | Asset path attribute to external binary/raster; optionally generated `Mesh.points` | Yes for encoding, normalization, wrap, extent | Yes if baking mesh | Lossy if converted to 8-bit or mesh only | External source is cheap to keep; sampling/mesh bake costs build time | Preserve CYLH or a documented standard raster plus custom metadata; compile mesh. |
| Categorical biome-ID PNG | `terrain_manager.gd:129-147,188-193` | Asset path attribute; generated primvar/texture/material lookup | Yes | Usually yes for renderer-specific lookup | High if filtered, gamma-transformed, or converted to weights | ID texture is cheap; baked assignments increase geometry/material splits | Preserve exact 8-bit ID image; mark linear/nearest/no-filter; optionally bake IDs as custom primvar. |
| Continuous splat/weight map (not currently present) | No current layer; future possibility | External image asset paths and shader inputs | Yes | Often compile to material masks | Continuous values can be preserved if channel/precision/color-space metadata survives | Shader masks may be cheaper than huge face subsets | Treat separately from ID maps; use linear data, explicit channels and precision. |
| Biome catalog/rules | `map_config.gd:209-248` | Materials, prim metadata, custom rule attributes | Yes | Rule compilation | USD materials do not preserve generator semantics by themselves | Keep rules off runtime hot path | Store as project schema; bake material table and generator inputs. |
| Biome appearance textures | `cylinder_generator.gd:547-576` | `UsdUVTexture`/asset paths in `UsdShade` | Usually no for basic PBR; custom texture role metadata may help | Translate to Godot | Shader graph fidelity varies | Runtime translation/cache required | Use USD Preview Surface/MaterialX for portable subset; keep source textures. |
| Terrain tube mesh | `cylinder_generator.gd:655-770` | `UsdGeomMesh` points/topology/normals/UV primvars | Custom provenance/topology metadata optional | Bake/generate | Mesh preserves appearance, not generator editability | Large mesh load; can be preview/distribution payload | Generate as derived USD payload and retain source rasters. |
| End caps | `cylinder_generator.gd:771-915` | Mesh + material/UVs | Custom role metadata useful | Bake/generate | Low for static appearance; high if procedural cap semantics omitted | Same as mesh | Export as separate named prims or representation. |
| Inward normals/winding | `cylinder_generator.gd:704,751-769,819-915` | Mesh normals, orientation metadata, `orientation` | Custom cylinder convention | Recompute/check | Medium; USD does not imply inward-facing habitat | Importer must preserve culling/normal direction | Validate normals against declared surface normal; include fixture. |
| Static catalog model | `map_asset_loader.gd:16-61`; catalog | `UsdGeom` asset, reference/payload; glTF companion | Optional asset-role metadata | GLB/Godot/USD conversion | Materials, scripts, collision may be lossy | Payloads help authoring; runtime still compiles | Accept static data-only models; reject scripts/unsupported scenes. |
| Placed object identity | `placements.json`; `world_edit_storage.gd:24-39` | Prim path plus custom stable ID attribute | Recommended custom ID/schema | No | Prim path is not a durable ID under renaming/composition | None | Add immutable `cyl:entityId`; never derive identity from path/order. |
| Surface placement theta/z/elevation | `map_object_factory.gd:8-29`; `reference_objects.gd:267-279` | Xform transform | Yes for surface-authored placement semantics | Convert surface coords to transform at import | Transform loses intent to follow edited terrain unless metadata retained | Runtime resolves surface transform | Store authoritative surface coordinates and derived transform, with explicit precedence. |
| Explicit 12-number transform | `map_object_factory.gd:41-47`; `world_edit_storage.gd:29-38` | `UsdGeomXformable` ops | Optional provenance | Pack/unpack | Low if local-vs-world convention documented | Direct transform is cheap | Prefer standard xform plus local/world metadata. |
| Ground alignment/yaw/pitch/roll/offset | `map_object_factory.gd:18-29`; `map_config.gd:278-287` | Xform ops | Yes for align-to-surface and offset semantics | Convert to basis | Medium | Runtime recomputes against terrain | Preserve as custom authored placement properties; bake only for static export. |
| Per-object lights/flicker | Catalog and factory; `surface_light_object.gd` | `UsdLux` light for static light | Yes for flicker behavior and object role | Runtime conversion | Flicker/runtime light behavior lossy | Mobile local-light cap remains engine policy | Export static light properties; keep flicker in runtime behavior metadata. |
| Collision/solid flag | `map_asset_loader.gd:63-200`; catalog | No universal core collision scene semantics | Yes or separate physics schema | Generate collision | High across engines | Runtime collision generation cost | Keep collision descriptor/compiled Godot shape separate. |
| Ground clutter prototypes | `clutter_manager.gd:91-169` | `UsdGeomPointInstancer` prototypes | Yes for source rule/provenance | Generate positions or retain procedural source | Instance IDs/appearance can round-trip; random rule not automatically | USD instancer is efficient authoring data; Godot still builds MultiMesh | Export generated instancer as optional preview/distribution payload; retain rules. |
| Clutter chunking/streaming | `clutter_manager.gd:171-470` | Payloads/variants can suggest load groups | Yes | Compile runtime index | USD payload boundaries do not preserve Godot scheduler behavior | Must keep current chunk worker/budget path | Do not replace scheduler with USD composition. |
| Environment/sky/water | `map_config.gd`; `map_runtime.gd` | Some `UsdLux`/material data | Yes for cylinder atmosphere/water | Translate | Medium/high for custom shaders | Runtime-specific | Keep project environment metadata; export basic lights/materials only. |
| Procedural seed/noise/erosion | `map_generator.gd:7-17,26-145` | Custom attributes/metadata | Yes | No if importer understands; otherwise bake | High across implementations | Offline compile avoids mobile cost | Preserve all parameters, effective seed, generator/version; also store outputs. |
| POIs | `pois.json`; generator | Xform/Scope prims with typed attrs | Optional type/role schema | Convert | Low | None | Export as typed metadata/markers, not gameplay. |
| Events/triggers/commands | `map_config.json:1422-1426`; no executor | Attributes/relationships could store declarations | Yes, but not core USD behavior | Runtime import only | No execution/semantic portability | Separate engine | Keep outside core USD or namespaced metadata; do not claim USD implements it. |
| Mutable player/object state | `world_edit_storage.gd:8-88` | Time-sampled or override-layer attrs could store values | Yes for state schema | Convert | High if mixed with authored opinions | Runtime save/load remains separate | Keep a separate versioned state store/override layer. |
| Shader uniform dictionary | `map_runtime.gd:32-45` | Shader inputs in `UsdShade` | Yes for Godot-specific uniforms | Translate | High for custom shaders | No USD runtime on Android | Map only portable PBR values; keep namespaced Godot overrides. |
| Archive/package | `map_library.gd:37-180` | USD package/layer files plus ordinary assets | Package manifest required | Package/build step | Paths/resolver behavior can vary | Offline package resolution needed | Keep `.cylmap` or define a USD-based package with explicit resolver rules. |

## 4. Terrain decision analysis

### Option 1: source rasters referenced from USD custom properties

The USD stage contains geometry metrics, generator metadata, and asset paths such as `cyl:heightAsset`, `cyl:terrainIdAsset`, and `cyl:sourceDescriptor`. The importer reads the rasters and generates the current terrain.

This is the most editable and deterministic option. It preserves float32 precision and exact categorical IDs, has compact storage, and avoids baking a large mesh for every authoring edit. Scene load is light if the stage is opened without generated payloads. Runtime cost remains the current compile/load cost, so an Android build should use a cached compiled result rather than regenerate on every launch. It has the best lossless round-trip potential for the current authoring model, but only if the custom metadata specifies dimensions, physical extent, normalization, channel, wrap, interpolation, and color space.

### Option 2: bake terrain into USD mesh

The stage contains `UsdGeomMesh` geometry, normals, UVs, material bindings, and perhaps a baked ID primvar. This is portable to DCC/rendering consumers and can be loaded without a project generator. It costs more storage and scene load time, and edits to source terrain require a new bake. It can preserve rendered appearance but cannot losslessly recover the original procedural parameters, raster sampling grid, erosion order, or ID image from arbitrary mesh output. It is useful as a distribution/preview representation, not as the sole editable source.

### Option 3: hybrid (recommended)

Keep source descriptor, CYLH/float raster, exact ID raster, biome catalog, texture assets, seed and generator version. Add an optional generated USD mesh and PointInstancer payload for preview/interchange, plus a separately compiled runtime cache for Godot terrain shaders, collision, clutter chunks and spatial indexes.

This has the best combined editability, portability and runtime behavior. Storage is larger than source-only, but generated artifacts can be content-addressed and omitted from an authoring archive. It also supports non-cylinder consumers: they can use the standard scene payload or source data if they understand the project extension, while the cylinder importer uses the custom mapping.

### ID maps versus continuous splat maps

The current `biomes.png` is a categorical ID map. It must remain an exact integer field: no bilinear interpolation, mip averaging, gamma conversion, or color-management transform. Store it as an 8-bit linear/data image with nearest sampling and an explicit `idRange`/palette mapping. A color-looking palette in historical descriptors must not be mistaken for the stored meaning.

A splat/weight map is different: each channel is a continuous weight, normally linear data, with explicit channel roles, precision, normalization, and blend policy. It may be filtered and interpolated under controlled rules. USD can point to either image, but neither meaning is standardized; the custom schema must distinguish `categoricalId` from `continuousWeight`.

## 5. Proposed authoring/interchange schema

This is **proposed**, not current implementation.

Use standard USD for the scene and composition, with a small namespaced project schema (`cyl:`) for cylinder/procedural semantics. Keep mutable state in a stronger override layer or separate state file, not in the base authored layer.

Suggested package:

```text
world.cylusd/
  root.usda                    # stage metrics and composition
  authored/world.usda          # geometry descriptor, materials, placements
  authored/terrain.usda        # optional generated terrain payload
  overrides/editor.usda        # authored editor edits/strong opinions
  generated/terrain.usdc       # optional compiled mesh/cache
  generated/clutter.usdc       # optional PointInstancer preview
  source/map.json              # project descriptor, versioned
  source/elevation.cylh        # exact source raster, or documented replacement
  source/biomes.png            # exact categorical IDs
  source/biomes/*.json         # biome rules/catalog
  assets/models/*.glb          # portable static source assets
  assets/textures/*
  runtime/godot/*              # optional engine cache, never authoritative
  manifest.json
```

Proposed `.usda` excerpt:

```usda
#usda 1.0
(
    defaultPrim = "World"
    upAxis = "Z"
    metersPerUnit = 1.0
    customLayerData = {
        string cyl:schema = "com.gretchycat.cylinder.world"
        string cyl:schemaVersion = "0.1"
        string cyl:sourceDescriptor = "source/map.json"
    }
)

def Xform "World" (
    kind = "assembly"
)
{
    def Scope "Terrain" {
        custom string cyl:topology = "periodic_cylinder_inner_surface"
        custom double cyl:radiusMeters = 4000.0
        custom double cyl:lengthMeters = 18000.0
        custom double cyl:elevationVarianceMeters = 100.0
        custom string cyl:thetaAxis = "+X_to_+Y"
        custom string cyl:axialAxis = "Z"
        custom string cyl:surfaceNormal = "inward_radial"
        custom string cyl:seamPolicy = "periodic_u"
        custom asset cyl:heightAsset = @../source/elevation.cylh@
        custom asset cyl:terrainIdAsset = @../source/biomes.png@
        custom token cyl:terrainIdEncoding = "R8_integer_nearest"
        custom token cyl:heightEncoding = "normalized_float32_times_elevationVariance"
        custom token cyl:heightInterpolation = "bilinear"

        def Mesh "CompiledMesh" (
            prepend payload = @../generated/terrain.usdc@
        )
        {
        }
    }

    def Scope "Materials" {
        # UsdShade materials and bindings go here.
    }

    def Scope "Placements" {
        def Xform "obj_tree_3_1" {
            custom string cyl:entityId = "obj_tree_3_1"
            custom asset cyl:assetId = @../assets/models/tree.glb@
            custom double cyl:thetaRadians = 1.3826783
            custom double cyl:zMeters = 1592.2949
            custom bool cyl:alignToSurfaceNormal = false
            custom double cyl:groundOffsetMeters = 0.0
            # Standard xformOps contain the derived/explicit transform.
        }
    }
}
```

A production schema should use registered typed schemas when the subset stabilizes, rather than relying indefinitely on untyped custom attributes. All `cyl:` attributes should define ownership, units, allowed values, versioning, and whether they are authoritative or derived.

## 6. Lossless, lossy, and required transformations

Potentially lossless within the declared project schema: JSON scalar/catalog metadata; stable IDs; exact float32 CYLH bytes; exact R8 ID raster; texture/model asset bytes; explicit placement transforms; seed and generator parameters; POI records; source package paths after resolver normalization.

Lossy or engine-dependent: CYLH to a baked mesh; procedural rules to generated clutter transforms; Godot shader graphs to `UsdPreviewSurface`; Godot PackedScenes/scripts to static USD; collision hulls; local-light flicker; weather, player physics, event behavior, mutable runtime state, and mobile streaming policy. A USD export must declare which representation is authoritative and retain source files when round-trip is promised.

Required transformations include: coordinate-system conversion from source stage metrics; flat-to-cylinder mapping; mesh subdivision before vertex bending; normal/tangent recomputation; seam duplication or shared seam policy; conversion of glTF/Godot assets; material translation; exact raster import with data color space; and compilation of engine-specific caches.

## 7. Flat-scene-to-cylinder proof of concept

This experiment should import a third-party, unmodified USD stage using the official Python USD SDK. It should not modify the source stage and should reject unsupported content explicitly.

### Supported initial subset

Support: `Xform`, static `Mesh`, `UsdShade` basic PBR/Preview Surface, file-backed image textures, external USD references/payloads after composition, and `PointInstancer` with static prototypes. Support standard stage `upAxis` and `metersPerUnit`, `xformOp` transforms, normals, UVs, material bindings, and stable PointInstancer IDs.

Exclude initially: skeletal animation, blend shapes, skinned meshes, deforming/time-sampled geometry, subdivision surfaces, NURBS/curves, particles, volumes, arbitrary shader networks, constraints, physics schemas, cameras as gameplay cameras, lights as dynamic simulation, scripts, custom event graphs, and assets requiring unresolved proprietary resolvers. A stage containing excluded required content must fail or report an explicit partial import; it must not silently flatten it.

### Coordinate and mapping contract

The fixture source convention is right-handed flat space with source `X` across the future circumference, source `Y` along the cylinder axis, and source `Z` as height. The importer first converts the stage to meters using `metersPerUnit` and rotates source `upAxis` (`Y` or `Z`) into source height `Z`. Let `C=2πR` and choose a fit scale `s` so the selected source width maps to a declared fraction of C. For a point `(x,y,z)`:

```text
u = (x - x_min) / source_width
theta = theta0 + wrap(u * circumference_fraction * 2π)
z_axis = z_min + (y - y_min) * s
radial_distance = R - terrain_elevation(theta, z_axis) + z * s
P = (radial_distance*cos(theta), radial_distance*sin(theta), z_axis)
```

The initial fixture uses `theta0=0`, positive X to positive Y, positive source Y to positive cylinder Z, and inward radial altitude. Out-of-range axial coordinates are rejected by default; a later mode may clamp or split into another segment. Circumference is periodic only when the source explicitly declares wrap-compatible edges; otherwise the importer leaves a seam gap or duplicates edge vertices with a warning. It must not silently weld unrelated edges.

### Bending versus rigid placement

For a continuous terrain/grid surface, bend every vertex using the mapping. A rigid object must instead be transformed by its authored origin and orientation: its mesh should not be curved merely because its origin lies on the cylinder. To bend a broad building or bridge as a surface-following asset, subdivide it sufficiently along the circumferential direction before bending; otherwise a single large triangle/chord cuts through the cylinder. Subdivision density must be a declared tolerance, not an arbitrary fixed count.

After bending, recompute normals from the transformed triangles or transform/re-orthogonalize authored normals only when mathematically valid. Recompute tangents from the final positions and UVs. Preserve UVs for rigid objects; for terrain, use declared cylindrical UVs. Ensure triangle winding produces the declared inward normal and use seam-duplicate vertices where UVs or normals require a discontinuity.

Placed objects use source USD transforms, then an explicit surface-placement policy. Prototype instances become ordinary placements for the first proof of concept, while PointInstancer prototypes become generated MultiMesh/instancer batches. Lights are imported only as static preview lights; cameras are inspection cameras, not player cameras. Physics/collision is excluded from USD import and generated separately from accepted meshes.

Expected failures include missing stage metrics, unresolved references, nonuniform/unsupported transforms, nonmanifold or invalid mesh topology, unsupported materials, stage units that make the fit unsafe, source geometry crossing axial bounds, and assets whose intended semantics depend on scripts or physics.

### Deterministic fixtures

Create a small third-party-style stage and do not edit it during import:

1. A flat numbered grid with unique tile labels/materials, including explicit left/right edge markers.
2. A heightmap/continuous grid with distinct high/low features at both circumferential edges.
3. A row of asymmetric buildings (different front/back colors and a visible antenna) to test orientation.
4. A `PointInstancer` vegetation patch with at least two prototypes and stable IDs.
5. A basic Preview Surface material with an external texture and a second material assignment.

### Acceptance measurements

Record source hash, importer version, USD SDK version, stage metrics, import duration, peak memory, output object/mesh/material/instance counts, and generated file sizes. Test:

* position and normal continuity at a declared periodic seam;
* edge-feature preservation and no accidental axial wrap;
* predictable building placement, up direction, and asymmetry orientation;
* material/texture preservation for the supported Preview Surface subset;
* PointInstancer prototype/ID/count preservation;
* inward normals and correct lighting from a cylinder-local test light;
* stable output hashes across two runs;
* import duration and memory on desktop, with generated runtime load/frame-time measured separately on the target Godot device;
* explicit rejection/reporting of each excluded feature.

The result is a constrained importer test, not proof of arbitrary USD conversion.

## 8. Import/export architecture alternatives

### 1. Offline Python/OpenUSD SDK importer — recommended first

The official SDK performs composition, asset resolution, schema access, references, payloads, variants, and typed data handling. The importer can emit an engine-independent intermediate plus USD-derived caches; Android does not need to ship the USD library. It has the smallest runtime footprint and best incremental-build story: hash the stage/layers/assets and regenerate only affected outputs.

Trade-offs: desktop/CI tooling distribution, Python/USD version management, and a build pipeline are required. Custom metadata can be copied into the intermediate if the importer explicitly walks it. This is the clearest way to keep Godot independent.

### 2. Native C++ OpenUSD importer via GDExtension

This provides direct in-editor/native import and potentially avoids an external preprocessing step. It has the largest dependency footprint, difficult Android cross-compilation/package size, ABI/build complexity, licensing/notice management, and integration risk with Godot's resource/import lifecycle. It is justified only after profiling proves offline import is inadequate or interactive USD editing is a firm requirement.

### 3. Export through an existing USD-compatible tool/conversion chain

Use Blender/Houdini/Omniverse or another established USD-capable tool for third-party asset conversion, then consume a constrained interchange subset. This reduces custom model conversion work and benefits from mature USD support, but it introduces tool/version variability and does not solve Cylinder's raster/procedural/custom-runtime semantics. It should be an optional authoring path, not the authoritative runtime pipeline.

Do not hand-write a USDA/USDC parser. It would reproduce composition and resolver behavior incompletely and create avoidable interoperability failures.

## 9. Ranked implementation stages and next steps

1. **Specification fixture (low risk):** define the `cyl:` namespace, authority rules, package resolver, source-raster metadata, ID-map color/data rules, and a tiny USD fixture. No runtime dependency.
2. **Offline reader/validator:** use official Python USD SDK to compose stages, enforce the supported subset, collect metrics, preserve custom metadata, and emit a deterministic intermediate manifest. Add source hashes and generator version.
3. **Static asset/placement import:** map references, meshes, transforms, Preview Surface materials, PointInstancer data and stable IDs into a portable intermediate; convert accepted models through glTF/USD tooling as needed.
4. **Cylinder compiler:** consume source rasters and project metadata to produce the existing terrain mesh/material inputs, collision, placement records, and clutter/instancing caches. Verify seam, inward normals and categorical-ID handling.
5. **Optional USD generated payload:** write a preview/distribution mesh and instancer payload without making it the editable source. Measure load/memory against the current Godot baseline.
6. **Mutable state boundary:** keep editor/runtime state in a separate versioned override/state layer or companion file with stable IDs and explicit authored-vs-runtime precedence.
7. **Only then consider native integration:** profile actual authoring needs before packaging OpenUSD into Godot/Android.

## 10. Open questions and risks

* Should a USD export be source-authoritative, generated-mesh-authoritative, or explicitly hybrid for each asset? The answer affects round-trip promises.
* Will the project register a real `UsdSchema` plugin, or begin with namespaced custom properties and a versioned manifest? The latter is simpler for the proof of concept.
* What exact glTF/USD material subset can Godot preserve on Android, including texture color spaces, alpha modes, normal maps and tangent conventions?
* Should source heightmaps remain CYLH, move to a documented TIFF/EXR data raster, or support both? GeoTIFF adds value only if geographic metadata is actually needed.
* How are authored surface placements expected to respond to later terrain edits? Store surface coordinates as authoritative when they should follow terrain; store explicit transforms when they should not.
* How will content-addressed references and package-local asset resolution work after archive relocation and on Android?
* What generator implementation/version is required for cross-machine reproducibility? Seed alone is insufficient evidence of bit-identical output.
* USD payloads can defer scene loading, but they do not automatically reproduce the current worker queues, seam-aware chunk selection, adaptive density, collision simplification, or mobile frame budgets.
* Arbitrary USD stages may contain features outside the supported subset; the importer must report or reject them rather than silently flattening behavior.

The central risk is conflating a portable scene description with a portable simulation. Keeping authored definitions, compiled runtime assets, and mutable gameplay state separate avoids that failure while still making USD useful for authoring and interchange.
