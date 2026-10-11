# AGENTS.md — Cylinder World Engine: Architecture, Roadmap, and Agent Standards

> **Authority and scope.** This file guides AI coding agents and human contributors. It preserves the existing project's working behavior while establishing a long-term direction. **Current implementation** and **planned architecture** are distinguished explicitly; do not assume proposed abstractions already exist. Inspect the code and tests before modifying it. The repository owner's explicit instructions override recommendations in this document.

## 1. Mission and priorities

Cylinder is a **data-driven 3D world simulation and authoring platform**, initially demonstrated as an O'Neill cylinder habitat. It is **not merely a fixed game or level**. Users should eventually be able to create, edit, save, share, and load worlds, import models and textures, place objects, define interactions and events, and build experiences without programming. Future worlds may use other habitat geometries; the cylinder is the first supported geometry, not necessarily the permanent platform boundary.

**Near-term roadmap (in order):**
1. **Usable world editor:** create, select, transform, configure, delete, save, reopen, and continue editing world contents. Make this reliable before broad feature expansion.
2. **Movable/interactable entities:** players, vehicles, machinery, and other dynamic objects, including persistent identity and state, streaming, and appropriate physics/animation.
3. **Event engine:** triggers, conditions, and actions coordinating entities and world systems, ideally editable through the world editor without requiring code.

The **critical end-to-end milestone** is: create an object in the editor → save → reload → move/interact with it at runtime → persist and reload the changed state.

**Current priorities:** correctness, editor usability, maintainability, stable mobile performance, regression prevention. Do not pursue speculative optimization or premature generalization at the expense of these priorities.

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
| `scripts/player_controller.gd` | Player motion/orientation under cylinder gravity |
| `scripts/hud.gd` | HUD and runtime controls |

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

## 5. World editor: next deliverable

Prioritize a coherent, usable editing loop:

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

- Introduce stable identity and lifecycle for players, vehicles, machinery, and interactive props.
- Distinguish authored spawn/default state, current runtime state, and persisted edits.
- Define movement and physics appropriate to local radial gravity and curved surfaces; explicitly test transitions between orientations and streamed areas.
- Provide simple, reusable command/event hooks early, so the editor and future event engine use the same contracts.
- Avoid running full physics or AI for distant/inactive entities; define dormant state and wake-up behavior.
- Test object ownership, collision, transforms, saves, and reloads before adding complicated vehicle simulation.

## 7. Event engine: later milestone

- Build on stable entity IDs and commands, rather than hard-coded NodePaths or editor UI implementation details.
- Support triggers (area entry, timer, interaction, state change), conditions, and actions (entity commands, world changes, notifications).
- Use a serializable, versioned representation that can be authored in the world editor and extended later.
- Specify deterministic ordering where important, cancellation, lifecycle, persistence, and safe handling of missing or unloaded entities.
- Design for debugging: inspectable event history, clear error reporting, reproducible tests, and cycle/recursion safeguards.
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

