# AGENTS.md — Cylinder World Engine: Architecture, Roadmap, and Agent Standards

> **Authority and scope.** This file guides AI coding agents and human contributors. It preserves the existing project's working behavior while establishing a long-term direction. **Current implementation** and **planned architecture** are distinguished explicitly; do not assume proposed abstractions already exist. Inspect the code and tests before modifying it. The repository owner's explicit instructions override recommendations in this document.

## 1. Mission and priorities

Cylinder is a **data-driven 3D world simulation and authoring platform**, initially demonstrated as an O'Neill cylinder habitat. It is **not merely a fixed game or level**. Users should eventually be able to create, edit, save, share, and load worlds, import models and textures, place objects, define interactions and events, and build experiences without programming. Future worlds may use other habitat geometries; the cylinder is the first supported geometry, not necessarily the permanent platform boundary.

**Near-term roadmap (in order):**
1. **Simulation backend and event history (current project):** develop the presentation-independent state, action, and event foundations described in `docs/about.md`.
2. **Usable world editor:** create, select, transform, configure, delete, save, reopen, and continue editing world contents.
3. **Movable/interactable entities and authored events:** add persistent dynamic entities and, later, editor-authored triggers, conditions, and actions.

**Current project direction:** focus first on simulation, event recording, and other backend systems. They may read state from existing cylinder systems and request supported state changes through those systems' functionality. Keep this work independent of UI controls, labels, and scene presentation. Do not build simulation authoring UI, new object presentation, or animations as part of this backend phase. Objects and animation can be added when the underlying system is ready to use them.

Read [`docs/about.md`](docs/about.md) before changing this area. It records the design work already discussed: the world and ecosystem premise; autonomous agents; actions, effects, and causal event history; maintenance-AI behavior; simulation at near, distant, and unloaded scales; a suggested implementation sequence; and open design questions. It is a living design reference, not proof that those systems or schemas already exist. Treat examples and possibilities there as provisional unless the owner makes a specific decision.

The **critical end-to-end milestone** is: create an object in the editor → save → reload → move/interact with it at runtime → persist and reload the changed state.

**Current priorities:** correctness, backend maintainability, stable mobile performance, and regression prevention. Preserve editor usability while the simulation foundation is developed separately. Do not pursue speculative optimization or premature generalization at the expense of these priorities.

## 2. Current technical baseline (verify against code)

- Engine: **Godot 4.7**, targeting the **Mobile renderer**, desktop and Android.
- Initial environment: rotating O'Neill cylinder, typically **8 km diameter × 18 km length**, radial/centrifugal gravity, axial light bar/day-night cycle, cylindrical heightmap terrain, climate/weather, biomes, objects, and ground clutter.
- Terrain/map data are authored/generated offline where practical. The runtime streams nearby content instead of instantiating an entire world.
- Ground clutter uses spatial chunks, background computation, GPU **MultiMesh** instancing, visibility/distance prioritization, and bounded main-thread assembly. Reference-object streaming uses a separate spatial index and placement budgets. **These are distinct systems.**
- Existing code has employed approximately **500 m × 500 m** spatial chunks for reference-object placement (`STREAM_CHUNK_SIZE_M`); clutter chunk size is **map-configurable** (`ground_clutter.chunk_size_m`). Do not conflate the two.
- Current code uses a **24 placements per tick** limit for reference objects, **not** a 24-ground-clutter limit.
- Typical recently observed frame rates on target hardware have been roughly **30–48 FPS**, occasionally **60 FPS**; these are anecdotal observations, not guaranteed performance targets or benchmark results. Protect the working baseline.

### Geometry and coordinates

Current cylindrical surface coordinates:

```text
x = (R + elevation) * cos(theta)
y = (R + elevation) * sin(theta)
z = z
```

`theta` wraps at `0 ≡ 2π`; `z` is axial distance, usually in `[-L/2, L/2]`. Respect seam wrapping in distance, chunk indexing, editing, movement, and persistence. Coordinate conventions, transforms, normals, winding order, and outward radial gravity must be explicitly checked when changing geometry.

### Existing source responsibilities

| Path | Current responsibility |
|---|---|
| `scripts/map_config.gd` | Map descriptor loading, validation, defaults and asset paths |
| `scripts/map_generator.gd` | Procedural map generation, biomes and placement generation |
| `scripts/cylinder_generator.gd` | Cylinder terrain mesh, geometry, collision, rendering setup |
| `scripts/terrain_manager.gd` | Terrain image/grid sampling and data access |
| `scripts/clutter_manager.gd` | Chunked MultiMesh ground clutter and worker tasks |
| `scripts/reference_objects.gd` | Placement indexing, streaming, local lights |
| `scripts/map_object_factory.gd` | Runtime instantiation of placed objects |
| `scripts/world_edit_storage.gd` | Persistence of world edits |
| `scripts/world_editor.gd`, `scripts/object_editor_ui.gd`, `scripts/map_editor_panel.gd` | Editor-related systems |
| `scripts/climate_system.gd`, `scripts/weather_system.gd` | Climate/weather simulation |
| `scripts/finite_state_automaton.gd`, `scripts/event_tracker.gd` | Data-driven finite-state transitions and bounded in-memory state/action event history |
| `scripts/windmill_simulation.gd` | Wind alignment, rotor dynamics, generated power, and energy for the windmill prototype |
| `scripts/player_controller.gd` | Player motion/orientation under cylinder gravity |
| `scripts/hud.gd` | HUD and runtime controls |

### Rust map-data migration: current status

- The migration plan and repository findings are documented in [`docs/CYLINDER_RUST_DATA_PIPELINE.md`](docs/CYLINDER_RUST_DATA_PIPELINE.md). Read it before continuing Rust map work; it records encoding semantics, milestones, ownership boundaries, and validation requirements.
- A Cargo workspace now exists at the repository root with `rust/cylinder-core` and `rust/cylinder-godot`. The core currently decodes CYLH normalized float32 elevation and categorical biome PNGs (including palette-index preservation) and supports cylindrical elevation/biome sampling. The GDExtension currently exposes those operations through `RustTerrainData`.
- `scripts/terrain_manager.gd` uses `RustTerrainData` through a dynamic optional backend when a matching extension is available, and retains the previous GDScript CYLH/image loaders and array sampling as a fallback on unsupported hosts. Keep both paths behaviorally aligned until supported platform artifacts are available and verified.
- The active procedural generator remains `scripts/map_generator.gd`. `scripts/generate_tileable_maps.py` is a wrapper around the shell generation path; the older Python implementation was much simpler than the current schema-4 GDScript generator. Rust procedural generation, the full Godot bridge, and replacement of the GDScript generator/terrain access are **not implemented yet**. Preserve the existing active map pipeline while building and comparing the Rust implementation incrementally.
- Android ARM64 debug and release libraries have been built at `target/aarch64-linux-android/{debug,release}/libcylinder_godot.so`. The `.gdextension` maps these only to Android ARM64. Do not map Android artifacts to Linux tags: a Termux Godot runtime reports Linux/ARM64 and panicked when loading the Android-target library because Android-specific APIs were unavailable.
- The current Termux Rust toolchain host is `aarch64-linux-android`; it does not have the Linux ARM64 Rust standard library installed. For Android ARM64, an amd64 Ubuntu host can cross-compile using Rust target `aarch64-linux-android` and the Android NDK linker, then copy the resulting library to the Android path above. To run a Linux GDExtension, build for the exact Linux ABI/runtime (for example, Linux x86_64 on an amd64 Ubuntu host); do not assume a Linux ARM64 glibc build will load in Termux's Bionic environment.
- `build.sh preflight` checks Rust/Cargo and the locked Cargo crate cache, offers to install the host Rust package or fetch missing crates, and reports the Android cross-target/NDK requirement. It does not install the Android NDK or Rust target component automatically.
- Latest local validation: `cargo fmt --all -- --check`, `cargo test -p cylinder-core` (4 passed), and the map pipeline (`MAP PIPELINE FAILURES: 0`) passed. The full `bash build.sh test` run timed out during `test_map_scene.gd`; the active user map outside the repository has biome raster ID 1 absent from its map config, causing terrain load and scene assertions to fail. The Rust terrain bridge check skips on this Termux Linux-reported runtime because no matching Linux ARM64 extension is built.

Check actual source before making assumptions: these responsibilities may evolve.

## 3. Architecture boundaries to preserve and develop

Aim toward the following separation **incrementally**, without imposing a new framework before there is a concrete need:

```text
Map package / persistent world definitions
                |
       Validated world/entity model
          /         |          \
     Editor     Runtime systems    Event engine (future)
                    |
        Streamed Godot nodes, physics,
         simulation, and rendering
```

### Persistent world model vs. scene representation

- A world entity's **identity and authoritative data must not depend on whether its Godot Node is currently instantiated**.
- Streaming a node out must not delete the entity from the world or lose durable changes.
- Distinguish **definitions/templates**, **placed instances**, **mutable runtime state**, and **ephemeral rendering/physics representation**.
- Use stable unique entity IDs, deterministic serialization, explicit ownership, and versioned schemas/migrations where warranted.
- Make save/load robust across map switches, process restarts, object deletion, duplication, and edits made while a node is unloaded.
- Keep authored map content distinct from user/runtime modifications; define precedence and merge behavior rather than silently overwriting authored data.
- Avoid making editor UI nodes or arbitrary scene nodes the sole authority for world state.

### Entity interfaces (planned, minimal first)

Before a full event engine, provide a small consistent interface through which editor tooling and later events can discover entity properties, invoke supported commands, and subscribe to notifications. **Do not implement a large ECS or scripting framework merely because this section mentions components.**

Illustrative entity contract, **not a required concrete schema**:

```yaml
id: vehicle_17
archetype: vehicle
components: [transform, movement, interaction]
commands: [start_engine, stop_engine, set_destination]
events: [engine_started, destination_reached, collision_detected]
```

- Commands should be validated, documented, and testable; events should carry stable IDs and defined payloads.
- The same object should remain the same entity when parked, moving, streamed out, or reloaded.
- Optional behaviors (physics, inventory, animation, machinery, interaction, AI) should be composable where practical, but favor simple interfaces over speculative infrastructure.
- **Not every movable entity requires full simulation at all distances.** Separate persistent state and low-frequency/offscreen simulation from nearby active physics and rendering.

### Geometry independence (future direction)

Cylinder-specific mathematics are appropriate in cylinder implementations, but avoid embedding new cylinder assumptions in unrelated editor, persistence, entity, or event code. Where a second geometry creates a demonstrated need, introduce a small geometry interface for operations such as surface position, world transform, gravity/up vector, distance, chunk address, and terrain sampling. **Do not refactor the entire engine into an abstract multi-geometry framework now.**

## 4. Streaming, scheduling, and performance contracts

- Prioritize useful work near the player/camera. Direction and predicted visibility can help, but only add complexity when profiling shows value.
- Prefer spatially bounded, independently completable workloads. Expensive work should be computed off the main thread where safe, with scene-tree modifications on the main thread.
- A workload may span multiple frames only with well-defined state and cancellation. A self-contained worker chunk should complete without leaving partially committed scene state.
- Prune queued or completed work that is no longer relevant. Ensure returning to an area correctly re-enqueues needed work.
- Maintain a distinction among **queued**, **running**, **completed**, **assembled**, **active**, **unloading**, and **cancelled/stale** states where relevant; avoid duplicate work or stale results being applied to a new map.
- Treat chunk results as belonging to a specific map/session/generation; on map changes, safely invalidate obsolete work.
- Avoid blocking the main thread while waiting for workers during ordinary gameplay. A reload may need synchronization, but it should not waste time assembling results that are about to be discarded.
- Bound pending task counts, result memory, live instances, and queue growth. Detect starvation and repeated unnecessary regeneration.
- Respect budgets, but remember a time check **after** an indivisible chunk assembly cannot prevent that single operation from overrunning the frame. Measure worst-case assembly cost and frame-time percentiles, not FPS averages alone.
- Different subsystems may have independent budgets today; monitor their combined frame-time cost before proposing a global scheduler.
- Do not add per-object scene-tree processing when batched or shader-based processing suffices. Preserve GPU instancing and existing adaptive quality mechanisms.
- Avoid turning every simulation into a per-frame update. Use event-driven, interval-based, deferred, and offscreen approximations where appropriate.

### Known audit targets: investigate, don't assume resolved

1. **Missing ground-clutter chunks:** inspect `clutter_manager.gd` chunk selection, visibility/culling, dispatch, worker completion, result pruning, assembly, map reloads, seam wrap, and camera movement. Distinguish missing generated data from invisible meshes, shader/material problems, winding order, and failed assembly. Add diagnostic counters and reproducible tests. **The reference-object 24-per-tick limit is not a ground-clutter limit.**
2. **Reference-object streaming stall:** in the reviewed implementation, `reference_objects.gd` can spawn at most `PLACEMENTS_PER_TICK = 24`, but may early-return when the player moves less than 15 m and at least one placement is live. Verify whether nearby placements can remain permanently unspawned for a stationary player; fix by continuing pending work until the eligible set is populated or the live-object cap is reached.
3. **Clutter reload/flush:** review `clutter_manager.gd`'s `flush_pending_chunk_tasks()` and `_clear_all_chunks()`. The reviewed path waits for tasks and may assemble results immediately before clearing chunks. Separate safe synchronization/cancellation from assembly where possible; test map switching and shutdown.
4. **Budget overruns:** measure main-thread chunk assembly and placement creation, including worst-case frame spikes; avoid unmeasured rewrites.
5. **Chunk/state invariants:** test no duplicate instances, no stale references, correct regeneration after culling, deterministic placement, proper persistence, and bounded memory/queues.

These are **investigation targets based on a prior static review**, not assertions that every issue is still present in the latest branch.

## 5. World editor: future deliverable

After the backend foundation is established, prioritize a coherent, usable editing loop:

1. Load/create a world from a map package.
2. Browse an object/asset palette; import supported assets where appropriate.
3. Select, place, move, rotate, scale, tint/configure, duplicate, and delete instances.
4. Show accurate gizmos and coordinate transforms on curved terrain; honor terrain normals, cylinder radial orientation, snapping, and seam behavior.
5. Support undo/redo with explicit transaction boundaries.
6. Save atomically where practical; reopen and verify exact state, IDs, transforms, and metadata.
7. Handle invalid assets, broken references, schema errors, and recovery without silent data loss.
8. Keep editor interaction independent of simulation timing and streamed node lifetimes.

A **workable editor** is one in which a user can create a small world entirely through the UI, close the application, reopen it, and continue editing without data loss. Prioritize that over a broad set of unfinished controls. Model creation itself belongs in external 3D tools; the editor primarily needs asset import, placement, scaling, tinting, configuration, and world composition.

## 6. Movable entities: following milestone

- This follows the initial backend and event-history foundation; full object behavior, physics, and animation are not the current focus.
- Introduce stable identity and lifecycle for players, vehicles, machinery, and interactive props.
- Distinguish authored spawn/default state, current runtime state, and persisted edits.
- Define movement and physics appropriate to local radial gravity and curved surfaces; explicitly test transitions between orientations and streamed areas.
- Provide simple, reusable command/event hooks early, so the editor and future event engine use the same contracts.
- Avoid running full physics or AI for distant/inactive entities; define dormant state and wake-up behavior.
- Test object ownership, collision, transforms, saves, and reloads before adding complicated vehicle simulation.

## 7. Simulation backend and event history: current project

- **Current prototype:** `assets/simulation/finite_state_automata.json` defines grazer, predator, raccoon, canine, and windmill automata, including a `simulation_tick_seconds` and declared `sensory_abilities` for each type. `assets/simulation/action_descriptors.json` defines action metadata, effects, and optional emitted events. `EventTracker` owns the active processors, routes events by stable processor ID, and records state changes/action starts in a bounded in-memory log.
- Each `SimulationEventProcessor` owns one FSA, its type-defined tick clock, mutable properties, and a private incoming event queue. Other processors can enqueue an event through `EventTracker.push_event`; queue contents are consumed only by the target processor during its tick. Actions can set/add/subtract the processor's own properties and emit events to self or another registered processor. The event history remains in-memory; durable event-log persistence is not implemented.
- The windmill is the first runtime object adapter. Its one-second type tick senses the supplied wind speed/direction, evaluates the heading/cut-in/cut-out window, and applies rotor torque, inertia, drag, generator load, efficiency, and spin direction. The visible `RotorHub` rotates between simulation ticks using the latest angular velocity. A newly placed mill begins at zero rotor speed. Windmill simulation state, including rotor speed, energy, FSA state, tick remainder, properties, and pending events, is stored with its placement record and restored when that object streams back in or its map is loaded.
- Windmill geometry currently uses the object surface-up direction as the shaft axis; the blade disk spans the local tangent/axial surface plane. Verify this against the actual placed-object transform when changing the model; a scene-local axis check alone does not prove its world orientation.
- `WeatherSystem.get_surface_wind_velocity(theta)` currently projects the existing global wind vector onto the local cylinder tangent and axial directions. It does not calculate spatially varying area weather; do not describe this prototype as using a local wind field until one exists.
- Keep simulation state, action evaluation, effects, and event recording independent of the HUD and other presentation/UI code. The backend may read current state from existing cylinder systems and apply changes through their supported APIs. Do not duplicate an existing system's state as a competing authority.
- Make the backend useful without adding UI panels or controls. UI may later inspect backend state and invoke supported operations; that is a separate integration step.
- Begin with a small, validated contract for state changes and events. Define stable event identity, actor/target references where applicable, payload shape, ordering, and causal references as the implementation needs them. Avoid committing to a large ECS, scripting language, or final schema before a concrete use case requires it.
- Treat the design in `docs/about.md`, Part II (“How It Works”), as prior design work and a guide to intended behavior. Its event/action example, autonomous-agent model, maintenance AI, ecological examples, and implementation sequence are proposals; the document also lists unresolved questions. Confirm decisions against the current code and owner direction before treating them as requirements.
- **Existing implementation:** `scripts/hud.gd` has a System Event Log console. It stores a bounded in-memory history for display/copy/clear and records diagnostics with real time, simulation time, and FPS. It is presentation-oriented diagnostic output, not a durable or authoritative simulation event history. Extend or replace its role only through a clear backend interface; do not mistake the existing console for the simulation event store.
- Persist meaningful world state and event history independently of whether related Godot nodes are loaded. Define retention, save/load, map/session ownership, and migration behavior as the durable format is designed.
- Prefer causal state changes over scripted story sequences: an action has validated preconditions and effects, and resulting events explain the changes. Agent perception, memory, dialogue, ecology, and caretaker-AI behavior can build on this foundation incrementally.
- Keep near-player detail, distant approximations, and unloaded-region updates consistent without requiring every entity to update each frame or exist as a live scene node.
- Defer new object actors, full object simulation, animation, and editor-authored event UI until the backend foundation demonstrates a concrete need for them.

### Later event authoring and presentation integration

- Build editor-authored events on stable entity IDs and backend commands, not hard-coded NodePaths or UI implementation details.
- Add triggers, conditions, and actions after the local backend contracts are reliable. Specify deterministic ordering where important, cancellation, lifecycle, persistence, and safe handling of missing or unloaded entities.
- Let presentation tools inspect event history and invoke validated backend operations without becoming the source of truth.
- Consider network/IRC relay or multiplayer integration as future extensions; do not build speculative distributed infrastructure before local semantics are reliable.

## 8. Existing configuration conventions (defaults, not invariants)

- Default unconstrained map sampling pitch: **8.0 m/pixel**.
- If no seed is specified, map generation may use a random seed; save the effective seed for reproducibility.
- Tree density baseline: **75% of legacy density** across manifests, map configs, and generated placement maps.
- Reference-object streaming defaults: **850 m spawn radius**, **1,250 m retention radius**, **256 maximum live placements**, **6 mobile local OmniLights**. These are tunable values, not fixed requirements.
- Object placement metadata includes `ground_offset_m`, `align_to_normal`, `yaw_rad`, `pitch_rad`, `roll_rad`, and optional fallen/on-side behavior. Respect authored transforms and ground alignment.
- Biomes are modular JSON definitions in `assets/biomes/`; preserve primary/filler roles, meta/hydrology biomes, artificial shapes and paths, and generated POI data.
- Preserve map portability, asset path resolution, extensible descriptors, and backward compatibility with existing saved worlds unless a migration is explicitly designed.

### Configuration values and test coverage

**No numerical value for map definition, world geometry, object density, chunk size, streaming distance, workload limit, or performance budget is gospel.** Values documented here reflect the current implementation, defaults, or observed behavior—not immutable architectural contracts. Do not hard-code them into unrelated subsystems or assert that they must equal today's defaults.

- Accept and correctly handle **all valid configurations within the actual supported domain**, not just the default or a few hand-picked examples. The supported domain is determined by explicit schema/engine constraints, not by a favorite benchmark value.
- Test **multiple valid values**, including meaningful boundaries, unusual but legitimate combinations, and nondefault map sizes, resolutions, densities, and budgets.
- Test **invalid inputs** (wrong types, missing required fields, out-of-range values, nonfinite numbers where applicable, contradictory settings, and malformed data). Invalid configurations must fail clearly and safely rather than hang, silently corrupt data, or unexpectedly substitute defaults.
- Use parameterized/property-based tests where practical. Test invariants such as correct wrapping, persistence, deterministic output for fixed seeds, bounded work, and safe resource cleanup—not equality to a particular tuning constant.
- **Safety exception:** Do not execute configurations that are reasonably expected to exhaust memory, saturate storage, lock up the system, or take impractically long. Use preflight cost estimates, safe test caps, mocks, or smaller representative cases; explicitly document why an extreme case was skipped. An unsafe stress case need not be run to prove the parser rejects it or the system guards against it.
- Performance goals should be **measured and configurable**, not treated as universal pass/fail numbers across hardware. Record test environment and regressions; distinguish acceptable parameter variation from genuinely pathological performance.
- Changes to defaults are permitted when justified; changes to the **supported valid domain** or schema compatibility require deliberate design and tests.

## 9. Agent workflow and coding standards

1. **Read this file, inspect relevant source and tests, and reproduce the issue before editing.** Don't trust assumptions from prior agent reports or comments without verification.
2. **Report root cause and evidence** (paths, functions, measurements, reproducible steps). Clearly separate confirmed defects, likely causes, and speculative improvements.
3. **Propose the smallest coherent change** that fixes the problem while preserving public behavior and extensibility. Ask before large architectural rewrites, schema breaks, new dependencies, or substantial feature changes.
4. Use typed GDScript and established project conventions. Preserve `@tool` behavior where applicable. Keep modules focused on clear responsibilities; avoid creating enormous multipurpose controllers or splitting files solely for cosmetic size.
5. Validate descriptors at boundaries. Prefer explicit, versioned data contracts and useful error messages. Never silently replace invalid state with fabricated defaults.
6. Respect Godot thread-safety rules. Worker threads should not directly mutate the live scene tree; protect shared mutable data and prevent stale async results.
7. Add or update regression tests for any bug fix, especially seam wrapping, stationary streaming, rapid movement, map transitions, save/load, and geometry winding/normal issues. Exercise valid and invalid configuration ranges as specified in Section 8, without running unsafe resource-exhaustion cases.
8. Profile before and after performance-related changes on relevant target hardware when available; report frame-time distributions, memory, worker queues, and rendering impact. Do not claim an optimization without evidence.
9. Run the existing headless suite before completion:

   ```bash
   bash build.sh test
   # Or individually:
   godot --headless -s res://scripts/test_map_pipeline.gd
   ```

   The existing pipeline suite should report **`MAP PIPELINE FAILURES: 0`**. If tests cannot be run, say why; do not claim they passed.
10. Summarize changed files, behavior, tests executed/results, known limitations, and follow-up risks. Do not commit or push unless the user has requested it.

## 10. Design philosophy

- **Data first, nodes second.** A scene node is a runtime representation, not the world's source of truth.
- **Extensible, not prematurely generic.** Preserve hooks for future world geometries, assets, entities, and events, but implement abstractions when actual use cases justify them.
- **Streaming is a lifecycle, not merely a distance test.** Handle creation, cancellation, unloading, re-entry, persistence, and stale work explicitly.
- **Prefer reproducible correctness over agent-generated complexity.** The fact that an agent can build something quickly is not evidence that it integrates safely.
- **Make the editor useful before expanding simulation scope.** User-authored worlds are the platform's central promise.
- **Protect the current working baseline.** Incremental, measured changes are preferable to redesigning functional systems without evidence.

