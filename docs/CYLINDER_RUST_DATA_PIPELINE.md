# Cylinder: Rust-Owned Data Pipeline Migration Plan

**Status:** Implementation plan for coding agent
**Scope:** Terrain/map data loading, indexed PNG interpretation, procedural generation, runtime queries, simulation data ownership, and Godot integration
**Initial supported targets:** Linux and Android
**Related document:** `CYLINDER_RUST_MIGRATION.md`

## 1. Objective

Move **all non-presentation map and indexed-data processing** into a standalone Rust core. Godot remains the application shell for **rendering, graphics resources, animation, audio, user input, UI, and engine-specific physics/navigation integration**. Godot must not decode and interpret terrain pixels, reconstruct indexed data, or independently repeat generation and simulation calculations.

**Primary rule:** Rust owns authoritative world data and produces renderer-ready output; Godot owns presentation and forwards user input and interface commands to Rust.

This is an **incremental migration**, not permission to rewrite working systems or change the visual result. The existing application must remain usable after each stage.

## 2. Repository reconnaissance (required before edits)

1. Read root `AGENTS.md` and any applicable nested agent instructions. Follow them over this plan if they conflict; report conflicts.
2. Inspect the current Godot version, renderers, project layout, build scripts, Android export configuration, and any existing Rust/GDExtension integration.
3. Trace the complete current map pipeline: PNG files → decoding → index/elevation lookup → biome/material mapping → terrain geometry → ground clutter/object placement → scene/rendering. Identify where Godot currently converts indexed pixels into 32-bit integers, `Color`, `Variant`, or other intermediate formats.
4. Record layer resolutions, coordinate conventions, wrap behavior, encodings, elevation scaling, palette semantics, procedural seeds, and any caching.
5. Capture baseline **correctness**, startup/load times, peak RAM, frame-time distribution, generation times, and Android/Linux build status. Use representative small and large maps; distinguish CPU generation from scene-tree and GPU bottlenecks.
6. Produce a short migration inventory mapping each existing function/module to **Rust core**, **thin Godot adapter**, or **Godot presentation**. Do not guess about uninspected code.

## 3. Ownership boundaries

| Responsibility | Owner | Notes |
|---|---|---|
| Read PNG bytes and decode map layers | Rust | Validate encoding, dimensions, palette/index semantics |
| Interpret indexed values, elevation, biomes, materials | Rust | No pixel-by-pixel interpretation in GDScript |
| Map coordinates, cylindrical wrap, resampling | Rust | Single authoritative coordinate implementation |
| Terrain mesh computation and normal/UV generation | Rust | Output arrays compatible with Godot's chosen mesh API |
| Procedural clutter/object placement | Rust | Deterministic seeds and compact instance data |
| Region caches and spatial queries | Rust | No duplicate world-data caches in Godot unless presentation-specific |
| World state, events, agent logic | Rust | Add incrementally; maintain existing behavior |
| UI, input, camera, audio, animation | Godot | Translate interactions to typed commands |
| Image/texture, mesh, MultiMesh and scene resources | Godot adapter | Construct resources from Rust-provided buffers |
| Physics and navigation engine services | Godot where needed | Rust requests/receives results via narrow adapter, not an accidental second physics engine |
| Persistence and serialization of authoritative state | Rust | Versioned and engine-independent |

The **Godot adapter** may copy/repack data when an API requires it, but must not perform substantive terrain calculations or per-pixel semantic interpretation.

## 4. Data format: layered PNG inputs

Retain the existing portable map files and metadata during migration. Do **not** impose a new container format or require equal resolutions across layers.

Example logical layer manifest (illustrative only; adapt to the actual repository):

```yaml
coordinate_system:
  kind: cylinder_surface
  circumferential_wrap: true
layers:
  biome:
    path: biome.png
    encoding: indexed_u8
  elevation:
    path: elevation.png
    encoding: grayscale_u16
    scale: 0.1
    offset: 0.0
  vegetation:
    path: vegetation.png
    encoding: grayscale_u8
```

**Encoding requirements:**

- For PNG **palette-indexed** (`color type 3`) layers, preserve the **original palette index**, not the palette's expanded RGB/RGBA color. Many decoders expand indexed PNGs by default; explicitly configure or implement index-preserving decoding and test it.
- PNG palette indices are 1–8 bits, not arbitrary 16-bit indices. If a layer needs more than 256 categories, choose an explicit alternative representation rather than silently treating RGB colors as indices.
- For numeric layers, support their actual encodings (e.g. 8/16-bit grayscale). Decode 16-bit samples with the correct PNG byte order and preserve integer precision until a consumer explicitly requires conversion.
- Distinguish **categorical** layers (nearest-neighbor semantics) from **continuous** layers (defined interpolation). Never interpolate biome IDs.
- Honor each layer's independent dimensions and defined sampling transform. Handle circumferential wrapping consistently at seams.
- Do not assume PNG is decoded by the GPU: ordinary PNG decompression is generally CPU-side. Optimize for minimal allocations, compact decoded arrays, and efficient GPU upload, not mythical zero-cost PNG decoding.
- Reject invalid or incompatible files with actionable diagnostics; never silently reinterpret unexpected color types, bit depths, or palette mappings.

## 5. Rust core architecture

Keep the core free of Godot and OS-specific APIs wherever practical.

Suggested conceptual modules (adapt names to the repository):

```text
rust/
  Cargo.toml                  # workspace
  cylinder-core/
    src/
      map/                    # PNG loading, layer schema, indexed access
      coordinates/            # cylindrical transforms and seam handling
      terrain/                # geometry, materials, normals, UVs
      generation/             # deterministic objects/clutter
      spatial/                # region queries and indexes
      simulation/             # world state, agents, event processing
      persistence/            # versioned state and save/load
  cylinder-godot/
    src/                      # GDExtension bridge only
```

Expose an API based on **coarse-grained operations** rather than one FFI call per pixel/object:

```text
load_world(manifest_or_path) -> WorldHandle
get_region_data(region, requested_outputs) -> RegionBuffers
query_terrain(position) -> TerrainSample
advance_simulation(fixed_dt) -> ChangeSet
apply_command(command) -> Result
get_render_updates(visible_regions) -> RenderBatch
save_world(path) -> Result
```

These are illustrative contracts, not prescribed function signatures. Define precise ownership, lifetimes, error handling, and synchronization before implementing the bridge.

## 6. Memory representation and Rust-to-Godot transfer

1. Decode and store indexed layers as compact contiguous typed arrays (`u8`, `u16`, etc.) in Rust. Keep authoritative data there.
2. Perform all lookup, filtering, interpolation, biome/material mapping, geometry generation, and placement computations in Rust.
3. Return **batched, renderer-ready** buffers: vertex/index arrays, packed transforms, material lookup textures, height textures, or instance batches as appropriate.
4. Have the GDExtension adapter construct Godot `Image`, `ImageTexture`, `ArrayMesh`, `MultiMesh`, or other resources. Avoid GDScript loops over each pixel, vertex, or instance.
5. Prefer compatible single-channel GPU formats for numeric layers when Godot and the selected renderer support them. Confirm exact formats and conversion requirements against the installed Godot version; do not assume that a `u16` height array maps directly to a 16-bit integer texture or that half-float is lossless for all integer values.
6. Use Godot's required vertex/index element formats at the boundary. A conversion/copy may be necessary; **zero-copy GPU upload is not guaranteed** by GDExtension.
7. Batch updates by dirty region or changed object set. Avoid retransmitting unchanged full maps each frame.
8. Document whether buffers are copied or borrowed, how long they remain valid, and which thread may create Godot resources. Do not retain invalid references to Rust-owned memory.
9. Keep rendering-specific derived caches in Godot only when necessary; Rust remains the authoritative source.

**Desired flow:**

```text
Indexed / grayscale PNG layers + manifest
                  |
                  v
      Rust decoder and typed arrays
                  |
                  v
 Rust terrain, generation, queries, simulation
                  |
                  v
    Compact renderer-ready region batches
                  |
                  v
        Thin GDExtension adapter
                  |
                  v
 Godot GPU resources / scene / UI / audio

Godot input -> typed command -> Rust state -> change batch -> Godot presentation
```

## 7. Incremental migration milestones

### Phase A — Baseline and integration skeleton

- Establish Cargo workspace and thin GDExtension; compile/load on Linux and Android.
- Implement one minimal round-trip API call with deterministic test data.
- Keep current Godot pipeline active behind a temporary migration switch.
- Verify the Android export includes correct ABI-specific extension libraries and loads on a real device.

**Gate:** Both targets launch; existing maps still work; baseline recorded.

### Phase B — PNG decoding and indexed queries in Rust

- Implement layer loader preserving palette indices and grayscale numeric samples.
- Add manifest/schema validation and per-layer dimensions/resampling rules.
- Move all map sampling and biome/elevation/material interpretation to Rust.
- Provide batch sampling/query APIs and unit tests, including palette index ≠ RGB value, 16-bit elevation, differing resolutions, seam wrap, and corrupt PNG handling.
- Keep Godot rendering unchanged initially, but remove redundant pixel interpretation as each caller migrates.

**Gate:** Rust results match current intended terrain semantics on representative fixtures; Godot no longer owns map pixel interpretation for migrated layers.

### Phase C — Rust-generated terrain render data

- Move terrain mesh computation, normals, UVs, and any splat/material index calculations into Rust.
- Produce exactly the arrays/textures Godot needs for resource construction.
- Transfer region batches across the adapter, then instantiate/update render resources on the appropriate Godot thread.
- Compare visuals, winding order, lighting, seams, and frame-time/load-time behavior with baseline.

**Gate:** Same intended terrain appearance; no duplicate geometry calculations in GDScript.

### Phase D — Procedural objects and clutter

- Move deterministic placement, density sampling, randomization, and object classification into Rust.
- Emit compact instance transforms and resource identifiers; Godot renders through batching/`MultiMesh` or other proven approach.
- Preserve manual placements separately from generated placements, with stable IDs and seeds/provenance so selected regions/categories can be regenerated without overwriting manual edits.
- Support incremental dirty-region rebuilds and cached layer data.

**Gate:** Reproducible placement; no per-object Godot-side placement calculations; no regressions in visual output or performance.

### Phase E — State, events, and runtime updates

- Move persistent indexed/environmental state and non-visual event/action processing into Rust as needed.
- Define typed commands from Godot input and typed changes from Rust; use fixed-step simulation independent of rendering FPS.
- Implement the **wind → windmill** integration test: environmental wind state changes, Rust updates angular velocity using wind orientation, inertia, and resistance; Godot displays the resulting rotation. Keep the windmill's authoritative dynamic state in Rust.
- Later expose wind fields to shaders as presentation data; no per-blade/grass simulation required.

**Gate:** The windmill accelerates/decelerates coherently, with identical logical behavior independent of display frame rate; no competing simulation logic in Godot.

### Phase F — Remove redundant paths and package

- Remove obsolete GDScript decoding, interpretation, and generation paths **only after** parity tests pass.
- Document and automate reproducible Linux and Android exports, including architecture-specific Rust builds and GDExtension descriptors.
- Provide release/debug packaging scripts, artifact verification, smoke tests, and a short developer build guide.

**Gate:** Clean checkout builds and runs on Linux and Android without the legacy map-processing path.

## 8. Linux and Android packaging

- Linux: compile the extension for the actual target architecture(s), run the Godot project, and produce a reproducible distributable package.
- Android: configure supported Rust Android targets and Android NDK toolchain; include appropriate `.so` files for the selected ABIs (at minimum `arm64-v8a` if that matches project support). Ensure export filters and extension paths are correct.
- Keep engine version, Rust toolchain, dependencies, NDK, and export templates pinned/documented as appropriate.
- Test **on a real Android device**, not just a successful build or emulator, and report startup, loading, memory, and rendering results.
- Avoid requiring Windows or macOS machines for current acceptance. Preserve a portable core and document untested future targets rather than claiming they work.
- If the current environment cannot run the Android export/device, build what is possible, provide exact commands, and explicitly mark device validation as pending. Never claim unperformed verification.

## 9. Performance and correctness measurements

Measure before and after each phase:

| Metric | Why |
|---|---|
| PNG decode time and allocations | Verify index-preserving decoding efficiency |
| Peak decoded-layer RAM | Detect hidden expansion from 1/2-byte samples to 4/16-byte representations |
| Map/region generation time | Confirm computational work actually moved and improved |
| FFI call count and bytes transferred | Detect excessive boundary chatter |
| Scene/resource construction time | Distinguish Rust gains from Godot render bottlenecks |
| Startup and map load time | Track end-user experience |
| Frame-time percentiles and GPU time | Avoid mistaking faster CPU code for faster rendering |
| Android peak memory and startup | Prevent mobile regressions |
| Output parity / deterministic seeds | Protect map appearance and procedural results |

Do not optimize based on intuition alone. Avoid claims of GPU PNG decoding or guaranteed zero-copy transfers. A Rust rewrite does not automatically fix scene-tree traversal or draw-call overhead.

## 10. Tests and invariants

- PNG fixture tests: palette-index preservation, sub-8-bit indexed images, grayscale 8/16-bit, corrupt files, unexpected color types.
- Coordinate tests: cylinder wrap, seam continuity, layer resolution mismatch, edge sampling.
- Terrain tests: elevation scale, normals, winding, UV alignment, material selection, stable geometry output.
- Generation tests: fixed seeds, object IDs, manually placed object preservation, category/region regeneration.
- Integration tests: load map → request region → build Godot resource → render; user input → Rust command → changed presentation.
- Packaging tests: Linux and Android extension discovery and runtime loading.
- Use representative real project maps in addition to tiny synthetic fixtures.

## 11. Agent working instructions

1. Inspect first; propose a concrete inventory and phase sequence based on **actual** code.
2. Implement in small reviewable changes; preserve existing behavior and current user-facing features.
3. Keep `cylinder-core` free of Godot dependencies; isolate all engine-specific types in the adapter.
4. Do not change map file encodings, coordinate conventions, or generation semantics without documenting and testing a migration.
5. Prefer compact arrays, bulk APIs, region caches, and explicit dirty updates over per-element Godot calls.
6. Never duplicate authoritative world state across Rust and Godot. Presentation caches are allowed with explicit invalidation.
7. After each phase, run available tests and builds, compare metrics, and record what remains unverified.
8. Do not delete working code until the replacement is demonstrated on both target platforms or behind a safe fallback.
9. Update repository documentation and build scripts with each meaningful architectural change.
10. If an existing requirement conflicts with this plan, stop and report the conflict instead of silently redesigning the project.

## 12. Definition of done

The migration is complete when:

- Rust loads and interprets **all terrain/indexed PNG layers** and owns their authoritative decoded state.
- Rust performs all terrain sampling, computational map processing, procedural placement, and migrated simulation/event logic.
- Godot receives renderer-ready batches and state changes, handling presentation and user input without semantic reprocessing of indexed data.
- Linux and Android builds/package successfully; both have been runtime-tested where hardware is available.
- The current terrain, objects, and interaction behavior remain correct, with measured performance and memory results.
- The codebase has a documented ownership boundary, no redundant legacy path, and a portable standalone Rust core.

**First action for the coding agent:** Read `AGENTS.md`, inspect the existing repository and the related migration plan, inventory the present map/data pipeline, then implement **Phase A** and **Phase B** before attempting large-scale terrain or rendering changes.
