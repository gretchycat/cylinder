# Agent prompt: overhaul Cylinder's map format

You are working on https://github.com/gretchycat/cylinder, a Godot project for an explorable O’Neill cylinder habitat that is intended to grow into an RPG creation system.

Implement an extensible, portable world/map package format and integrate it with the existing runtime and editor. This is an implementation task, not just a design proposal. Inspect the current repository first, make a concise plan, then carry out the work and verify it. Read and follow the root AGENTS.md and applicable nested instructions. If no AGENTS.md exists, report that and ask only about genuinely consequential repository conventions that cannot be inferred; proceed with routine decisions. Preserve unrelated work and avoid unrelated refactors. Do not publish releases or push changes unless separately authorized.

## Product intent

Creators should eventually be able to build complete RPG adventures without programming: paint/sculpt terrain, import models, place objects and characters, configure behaviors, create dialogue and quests, and use an in-client visual event editor. They should save a world into a single shareable file and load it on another device without manually repairing paths or copying dependencies.

There is no functioning event system yet. This overhaul must establish extension points for future systems without implementing a speculative RPG engine. Future optional multiplayer may use a dedicated IRC channel to relay movement, gameplay events, and chat. The persistent format must accommodate future networking without depending on IRC.

Preserve the existing principle that physical cylinder dimensions come from configuration, independent of raster dimensions. Terrain-category and elevation layers must support different resolutions. Resolution controls detail, not the world's physical size.

## Starting evidence to verify against the current checkout

An earlier inspection found these files and behaviors. Treat them as leads, not immutable facts; inspect their current contents and callers:

- assets/maps/README.md documents map directories and package-relative assets.
- assets/maps/default/map_config.json contains geometry, environment settings, model catalogs, files, and empty entities/events/relationships sections.
- object_map.json contains original object placements, settlements, spawns, and generator metadata. Placement records include overlapping representations such as u/v, theta/z, and elevation.
- scripts/map_config.gd resolves packages and builds a normalized dictionary. Selected-field normalization can discard unknown top-level data if used as the only source for saving.
- scripts/terrain_manager.gd loads elevation and terrain into separate arrays but both loaders overwrite shared grid_u/grid_v dimensions. Both samplers then use those shared dimensions. This needs correction for genuinely independent layer resolutions.
- Elevation loading currently converts to FORMAT_L8, imposing 8-bit precision.
- scripts/world_edit_storage.gd saves local object snapshots with a different representation from object_map.json, including 12-number transforms, model paths, and player spawn. Its default save identity is derived from the map directory path.
- scripts/map_asset_loader.gd loads models through ResourceLoader and has a direct-image fallback. Imported project assets and arbitrary runtime-imported assets require different handling.
- Inspect cylinder_generator.gd, reference_objects.gd, world_editor.gd, object_editor_ui.gd, player_controller.gd, clutter_manager.gd, and affected shaders/tests as needed.

Trace the actual data flow before changing it. Do not assume that every field present in JSON is currently consumed by the runtime. Identify duplicated settings, their effective precedence, legacy fallback behavior, and coordinate conventions.

## Scope

Implement now:

1. A documented, versioned world document and single-file package container.
2. Load, validate, save, import, and export, used by both runtime and existing editor.
3. Backward-compatible loading/migration of existing maps and editor saves.
4. Independent terrain/elevation dimensions and correct sampling/export.
5. Stable identities, portable asset references, and lossless preservation of optional unknown data.
6. Practical UI entry points for opening/importing and saving/exporting maps, with useful errors.
7. A bounded runtime model-import path, preferably GLB as the initial portable format, connected to the existing placement workflow.
8. Tests and documentation of the format and migration behavior.

Do not implement the full visual event editor, character AI, dialogue/quest execution, combat, IRC client, multiplayer synchronization, or a complete terrain-painting UI in this task. Create only the data hooks and architectural boundaries needed to add these later. Do not present reserved sections as working gameplay features.

## Package and document structure

Use a ZIP-based container with an appropriate dedicated extension, such as .cylmap. Keep the logical format equally usable as an unpacked development directory. JSON is appropriate for structured content; images or explicit binary arrays are appropriate for dense terrain data. Avoid a bespoke binary container or a giant JSON array for every pixel.

Choose a simple documented layout containing a manifest, terrain layers, object/asset definitions, and packaged assets. Empty future sections may be omitted. The exact names are your implementation choice, but preserve clear boundaries and avoid overengineering.

The manifest must distinguish:

- Format/schema version, separate from content revision.
- Permanent world ID, preserved across moves and ordinary saves.
- Human metadata: title/name, description, author, and optional attribution/license information.
- Content revision and a defined basis for future content fingerprinting.
- Required and optional feature capabilities, with versions where needed.
- References to the document's sections/layers and asset catalog.
- A namespaced extensions container for experimental or third-party data.

Define the semantics of Save, Save As, and Duplicate: ordinary save and a relocated copy preserve identity; deliberate duplication can create a new world ID. Never regenerate persistent IDs on each load. Document how an explicit duplicate remaps internal references if IDs are world-global.

Use explicit migrations for supported old versions. Reject unsupported incompatible schema versions clearly rather than silently interpreting them as the current version. Optional unknown data within a supported compatibility envelope must survive editing and saving. Unknown required capabilities prevent normal gameplay loading, with a useful explanation; safe inspection may be offered if practical.

## One authored document, separate runtime state

Maintain a complete authored document as the source of truth. Runtime nodes and caches are derived views. Do not reconstruct the entire saved world from only currently instantiated nodes: unloaded objects, unknown components, reserved sections, and uninstantiated metadata must survive.

Preserve unknown JSON fields recursively, unknown optional component records, and referenced opaque package files. Semantic JSON preservation is sufficient; whitespace and key ordering need not be identical. Unmodified binary assets should remain byte-identical. Edits to known fields must not erase unrelated fields on the same record.

Keep these concepts distinct:

- World package: authored content, starting conditions, terrain, asset definitions, objects, and future gameplay definitions.
- Saved game: changes during play, referring to world ID and compatible revision—inventory, quest progress, destroyed/opened objects, current character position, and simulation time.
- Session/network state: connected peers, transient ownership, messages, and synchronization state.

Do not build a full save-game or session implementation yet. Establish/document the boundary, and distinguish editor “set default spawn” from resuming a player's current position. Preserve the useful existing save behavior during migration.

## Terrain, coordinates, and precision

Each raster layer owns its dimensions, encoding, sampling rules, and physical interpretation. Never use the terrain layer's width/height to index elevation or vice versa. Audit CPU sampling, GPU textures/uniforms, spawn selection, clutter, collision/mesh generation, and save/export paths for shared-grid assumptions.

Preserve the existing physical mapping and seam alignment during migration. Document axis direction, angular zero and direction, origin, units, circumference wrapping, axial bounds, and height reference. Define pixel-center/edge conventions consistently. Test non-square layers and the wrap seam.

Terrain categories are stable semantic IDs with explicit palette/material associations, rather than arbitrary RGB values acting as the permanent identity. Keep existing color images importable and preserve the current visual result. Category sampling must remain discrete; any material-blending representation is a separate future feature.

Support elevation precision beyond 8 bits through an explicitly declared encoding that can load and save in exported builds. Choose a practical higher-precision implementation after checking the project's Godot version. Legacy L8 must remain importable. Do not silently quantize higher-precision data on save or claim that converting an existing 8-bit image recovers lost detail.

Define canonical placement records with explicit coordinate-space semantics. Preserve exact existing placements—including orientation, scale, end-cap objects, and objects above the surface. A cylindrical surface placement and a local 3D transform may both be supported as tagged alternatives; avoid competing unlabeled coordinates. Derive redundant values rather than maintaining inconsistent copies. Document whether a surface placement follows edited terrain and what its height offset means. Terrain dimensions must never alter the configured cylinder size.

## Objects, assets, and future behaviors

Give assets and object instances stable IDs independent of display names, node paths, array positions, file locations, and numeric enum order. Distinguish a reusable asset or definition from each placed instance. Preserve IDs through save/reload and rename; duplication creates a new instance ID.

Separate appearance from behavior. An object can reference a model and carry typed, versioned component/property records. The initial components should cover only existing behavior, such as lights and current object variants. Do not redesign all game logic into a new framework merely to serialize it.

Reserve optional referenceable sections for characters/entities, behaviors, dialogue, quests, event definitions, regions/triggers, factions/relationships, routes, and world variables. Use a small extension contract instead of inventing complete schemas for every unbuilt system.

Future events should be compatible with non-programmer authoring: triggers, conditions, and actions; parameters can refer to stable object/region/variable IDs. Document one illustrative event record, clearly labeled non-executable future data. Loading it must not imply an event engine exists. Distinguish persistent event definitions from transient multiplayer event messages.

Portable packages must not require absolute host paths, another user's user:// paths, or unresolved development res:// paths. Define explicit built-in asset references with an appropriate compatibility/dependency contract; bundle custom assets and their necessary dependencies. Preserve attribution files.

Check support against the actual Godot version and exported target platforms. For runtime GLB import, make the imported model available in the existing object catalog/placement workflow and persist it into the package. State exactly which formats are supported at runtime. Do not promise that arbitrary editor-importable source formats work in the installed game. Preserve existing trusted built-in scripted/procedural assets without requiring creators to write scripts.

Do not automatically execute scripts supplied by a downloaded map. Keep ordinary imported content data-only. If executable mod support is wanted later, it needs an explicit separate capability/trust model; do not introduce it incidentally through scene loading.

## Future networking boundary

Allow optional declarative multiplayer/session hints in the document, including a future transport type and IRC server/channel configuration. Keep credentials and live connection state outside shareable maps. Opening a map must not automatically connect to a supplied server.

Design IDs and content revision information so future participants can verify they have the same world content. Document that shared-state authority, join snapshots, message ordering/deduplication, and reconnect behavior belong to the session layer. Host-player authority is a plausible future approach, not something to implement or permanently hard-code here. The map must remain usable offline without IRC.

## Migration and integration

Create one common document/serialization service used by the runtime and editor. Small runtime adapters are fine; divergent editor-only and original-map object formats must not continue as the long-term design.

Load existing map directories through a legacy adapter or explicit migration. Preserve original files. Convert to the new format on explicit save/export or a documented migration operation. Map legacy enums and model paths to stable references, retaining enough information to diagnose unsupported records.

Migrate existing world_edits snapshots where available. They currently represent an object snapshot, so do not naively append them to original placements and duplicate the world. Preserve the effective edited result, including deletions, transforms, light settings, custom models, and saved default spawn. Report ambiguous metadata/identity matches instead of silently attaching data to the wrong object. Assign migrated IDs consistently and persist them.

Determine current precedence for duplicated geometry, hydrology, lighting, settlement, and spawn settings; choose a canonical authored location and compatibility mapping without changing effective behavior. Preserve currently unused legacy metadata as metadata/extensions where appropriate.

Map discovery must include writable user content, not only bundled res:// directories. A map should still load after export, relocation, re-import, or application restart. Shareable references must resolve within the package or its declared built-ins.

Make saving transactional: write a complete temporary result, validate it, then replace the intended destination. A failed save must not destroy the previous map. Import/validation failure must leave the active world intact. Use coherent staged replacement for directory saves as well as archives.

Validate archive paths and dependencies; reject traversal, absolute-path escapes, duplicate/conflicting entries, and unreasonable expanded sizes using documented bounds. Report malformed documents, duplicate IDs, missing required assets, dangling known references, and unsupported capabilities with actionable messages. Do not silently load the default world's objects into a broken imported map.

Keep the mobile/touch interface practical. Add only the UI needed for map open/import, save/export, and the bounded model-import workflow; avoid a broad UI redesign. Consider archive/image/model processing costs on existing mobile targets and avoid unnecessary repeated decoding or full-buffer copies.

## Verification and acceptance criteria

Use focused tests that demonstrate behavior, plus the existing relevant project checks. Specifically establish:

1. The default legacy world loads with equivalent dimensions, terrain appearance, placements, lighting configuration, climate settings, and spawn behavior.
2. Unequal, non-square terrain/elevation resolutions sample correctly at known points and across the circumference seam; export/reload preserves each layer's dimensions.
3. Higher-precision elevation survives round-trip within its declared tolerance; legacy L8 imports correctly.
4. An edited legacy snapshot migrates without duplicating objects or resurrecting deleted ones, and preserves placement/light/spawn changes.
5. Place, move, rename, duplicate, and delete objects; save and reload; verify identities, transforms, and supported properties.
6. Unknown nested fields, optional future components, an illustrative event definition, and opaque referenced files survive a round-trip without execution or accidental removal.
7. Unsupported required capabilities and incompatible format versions produce clear failures; malformed imports and failed saves preserve the prior valid state.
8. A package exported to a fresh location loads using only its contents and explicitly declared built-ins, with no dependency on the author's original paths.
9. A runtime-imported model can be placed, packaged, reloaded, and rendered in an exported build. If that environment is unavailable, report this as unverified, never as passed.
10. Opening and saving maps works offline and does not initiate network connections or run downloaded scripts.

Include representative tiny fixtures rather than large unnecessary assets. Run relevant Godot parser/headless checks, migration/round-trip tests, and a visual smoke test of the existing scene when available. Avoid altering geometry winding, lighting algorithms, shaders, or unrelated mechanics unless a specific integration issue requires it; verify any necessary changes.

## Deliverables and completion report

Deliver working code, the format specification and migration guide in the repository, representative examples/fixtures, and focused tests. Document the extension/versioning rules, coordinate conventions, precision, supported runtime asset formats, asset dependency rules, and editor workflow.

Implement in coherent stages: inspect and specify the minimal schema, add document/migration support, integrate terrain and objects, add package/assets and UI workflows, then verify. Make reasonable implementation choices and document them; do not stop at an architecture essay or a list of TODOs.

In the final report, summarize what now works, how existing maps/saves are handled, exact tests actually run, and any unverified exported/mobile behavior. Clearly separate implemented functionality from reserved future event/RPG/network hooks. Call out remaining limitations without claiming that placeholder metadata implements a feature.
