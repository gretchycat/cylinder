# Woodland bush asset

The existing `shrubs` catalog entry and `shrubs.tscn` now build an original,
procedural temperate understory bush. Placement, density, scale, and foliage
palettes remain controlled by the biome descriptors.

## Asset

- Approximately 1.11 × 0.97 × 1.06 metres; rooted at local origin, +Y up.
- Six tapered woody stems, 24 branchlets, 186 individually curved leaves.
- Deterministic asymmetrical branching, alternating leaves, varied roll, pitch,
  size, and shade. Eight-sided leaf silhouettes have raised midribs and curled tips.
- One opaque surface, one 512 × 512 leaf/bark atlas. Leaves use geometry rather
  than alpha cards, avoiding layers of transparent foliage overdraw.
- Atlas is original procedural artwork, with fine veins, mottling and bark
  furrows. It is not a photographic scan. Rebuild with
  `python scripts/generate_woodland_bush_texture.py` (Pillow required).
- Texture import enables mipmaps and VRAM compression (ETC2 on this environment).
  Imported texture including mipmaps is about 171 KiB.

## Integration

`clutter_geometry.gd::shrub()` delegates to `woodland_bush.gd`; the existing
`clutter_model.gd::build_mesh()` interface remains intact. Geometry is generated
when the catalog loads, then shared by MultiMesh instances.

The clutter material collector retains a source mesh's albedo atlas. The bush's
`palette_in_custom_data` mesh metadata prevents its woody pigment from being
multiplied by the foliage palette. This opt-in retains the existing treatment of
other assets. Leaf vertex alpha selects foliage tint; branch alpha preserves bark.
The bush opts into a 0.1 m extra culling margin (its computed bounds already
include 0.5 m padding), rather than the legacy 150 m margin. A very large margin
keeps the camera inside the bounds and defeats distance LOD. Godot selects one
LOD for the complete MultiMesh from its nearest AABB point, as described in the
[mesh LOD documentation](https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html#using-mesh-lod-with-multimesh-and-particles). Existing chunk streaming remains intact.

The default shrub catalog uses a neutral base color and gentle wind (0.018 m).

## Geometry cost

| Mesh | Triangles | Vertices | Material surfaces |
| --- | ---: | ---: | ---: |
| Old sphere placeholder | 392 | 1,176 | 1 |
| New close mesh | 1,752 | 2,010 | 1 |
| Native middle LOD | 1,008 | shared close vertex buffer | 1 |
| Native far LOD | 640 | shared close vertex buffer | 1 |
| Explicit `build_mesh(1)` | 960 | reduced vertex buffer | 1 |

The replacement costs more geometry than the placeholder. Index sharing keeps
vertex growth to about 71%, while retaining one batch per material/chunk. Native
mesh LODs reduce triangles without introducing scene nodes or per-frame CPU
updates. The explicit low-detail variant also remains available through the
existing builder interface; the active instancing path uses native mesh LODs.

Godot's [ArrayMesh LOD API](https://docs.godotengine.org/en/stable/classes/class_arraymesh.html#class-arraymesh-method-add-surface-from-arrays)
uses alternative index buffers. The bush uses thresholds 0.008 and 0.025 to
reserve detailed leaves for nearby views. Its LOD keys are distance-related thresholds,
not fixed world-metre switching distances.

## Validation and visual review

Run `bash build.sh test` for the headless suite, including bush geometry,
reproducibility, LOD, atlas and palette integration checks.

Render front/back/detail/LOD views and a 256-instance comparison:

```sh
godot --path . --display-driver x11 --rendering-method mobile --rendering-driver vulkan -s scripts/preview_woodland_bush.gd
```

Add `-- --screenshots-only` to skip the benchmark, or `-- --benchmark-only`
to skip the individual close-up views. Images are written to
`build/bush-*.png`. The preview uses the production clutter collector, shader,
and MultiMesh builder. A test-only copy of the old sphere construction provides
a repeatable comparison; it is never used for map placement.

Reviewed images for leaf silhouette, branch connectivity, foliage gaps,
asymmetry from opposite sides, bark/leaf separation, and low-detail coverage.
Close-up appearance intentionally remains constrained by a mobile geometry
budget; leaf edges are not a high-resolution hero-model silhouette.

The headless suite completed with `MAP PIPELINE FAILURES: 0` and 17/17
simulation tests passing. Existing shutdown resource-leak diagnostics remain.
The focused asset check also validates finite, non-degenerate geometry and the
production palette/atlas path.

The available Mobile Vulkan device is **llvmpipe software rendering**, not an
Android GPU. The benchmark logs average frame time, draw calls, and rendered
primitives for a 256-instance grid, including shadows, at 640 × 450 with 0.75
render scale and no MSAA. These measurements diagnose relative scene cost;
they are not a hardware FPS guarantee. Target-device profiling remains necessary.

Final isolated software-renderer comparison (8 measured frames after warm-up):

| 256-instance scene | Mean frame time | Draw calls |
| --- | ---: | ---: |
| Sphere placeholder | 658.1 ms | 4 |
| Woodland bush with corrected bounds and LOD | 1490.6 ms | 4 |

The more detailed bush was approximately 2.3× slower in this deliberately dense,
shadowed software-rendering test. An earlier run with the generic 150 m culling
margin retained the close mesh and was approximately 3.4× slower. The final run
selected the middle mesh LOD; close views retain the detailed mesh. These are
short-run measurements, affected by software-renderer scheduling and thermal
conditions. Do not interpret their absolute frame times as Android GPU results.
Native LOD operates per chunk, not per bush, so the nearest bush can retain a
higher LOD for its whole chunk. No biome densities were reduced to conceal cost.
