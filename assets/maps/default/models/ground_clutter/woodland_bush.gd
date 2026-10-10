@tool
extends RefCounted

# Original temperate understory shrub; metres, +Y up, rooted at the origin.
# One opaque surface: leaf silhouettes are geometry, not overlapping alpha cards.
const ATLAS = preload("res://assets/maps/default/models/ground_clutter/woodland_bush_atlas.png")

static func build(width_m: float, height_m: float, lod_level: int = 0) -> ArrayMesh:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 61409
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaf_specs: Array[Dictionary] = []
	var sides: int = 5 if lod_level == 0 else 3
	for stem: int in range(6):
		var angle: float = float(stem) * 2.399963 + rng.randf_range(-0.22, 0.22)
		var outward: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		var lateral: Vector3 = Vector3(-sin(angle), 0.0, cos(angle))
		var base: Vector3 = outward * rng.randf_range(0.015, 0.055)
		var tip: Vector3 = outward * width_m * rng.randf_range(0.22, 0.44)
		tip += lateral * width_m * rng.randf_range(-0.09, 0.09)
		tip.y = height_m * rng.randf_range(0.66, 1.00)
		var bend: Vector3 = base.lerp(tip, 0.46) - outward * width_m * 0.07
		_branch(st, base, bend, 0.019 * width_m, 0.010 * width_m, sides)
		_branch(st, bend, tip, 0.010 * width_m, 0.0025 * width_m, sides)
		for twig: int in range(4):
			var t: float = 0.34 + float(twig) * 0.16
			var joint: Vector3 = bend.lerp(tip, (t - 0.46) / 0.54) if t > 0.46 else base.lerp(bend, t / 0.46)
			var turn: float = (-1.0 if twig % 2 == 0 else 1.0) * rng.randf_range(0.45, 1.35)
			var twig_dir: Vector3 = outward.rotated(Vector3.UP, turn)
			twig_dir.y = rng.randf_range(0.15, 0.7)
			var end: Vector3 = joint + twig_dir.normalized() * width_m * rng.randf_range(0.22, 0.36)
			_branch(st, joint, end, 0.0045 * width_m, 0.0010 * width_m, 3)
			for leaf: int in range(7):
				var along: float = 0.16 + float(leaf) * 0.128
				var leaf_base: Vector3 = joint.lerp(end, along)
				var side_sign: float = -1.0 if leaf % 2 == 0 else 1.0
				var direction: Vector3 = twig_dir.rotated(Vector3.UP, side_sign * rng.randf_range(0.65, 1.35))
				direction.y = rng.randf_range(-0.45, 0.55)
				leaf_specs.append({"base": leaf_base, "direction": direction.normalized(),
					"length": width_m * rng.randf_range(0.095, 0.155),
					"roll": rng.randf_range(-0.95, 0.95), "shade": rng.randf_range(0.70, 1.0)})
		for crown_leaf: int in range(3):
			var direction: Vector3 = outward.rotated(Vector3.UP, float(crown_leaf) * 2.1)
			direction.y = rng.randf_range(0.15, 0.6)
			leaf_specs.append({"base": tip, "direction": direction.normalized(),
				"length": width_m * rng.randf_range(0.09, 0.13),
				"roll": rng.randf_range(-0.8, 0.8), "shade": 1.0})
	# Keep branches in native mesh LODs, but thin evenly distributed leaves.
	var branch_vertices: int = (6 * 2 * sides * 6) + (6 * 4 * 3 * 6)
	var distant_indices: PackedInt32Array = PackedInt32Array()
	var far_indices: PackedInt32Array = PackedInt32Array()
	for index: int in range(branch_vertices):
		distant_indices.append(index)
		far_indices.append(index)
	var leaf_number: int = 0
	for spec_index: int in range(leaf_specs.size()):
		if lod_level > 0 and spec_index % 2 != 0:
			continue
		var spec: Dictionary = leaf_specs[spec_index]
		_leaf(st, spec.base, spec.direction, spec.length, spec.roll, spec.shade)
		if leaf_number % 2 == 0:
			for index: int in range(24):
				distant_indices.append(branch_vertices + leaf_number * 24 + index)
		if leaf_number % 4 == 0:
			for index: int in range(24):
				far_indices.append(branch_vertices + leaf_number * 24 + index)
		leaf_number += 1
	st.index()
	var arrays: Array = st.commit_to_arrays()
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for index: int in range(distant_indices.size()):
		distant_indices[index] = indices[distant_indices[index]]
	for index: int in range(far_indices.size()):
		far_indices[index] = indices[far_indices[index]]
	var mesh: ArrayMesh = ArrayMesh.new()
	# Keep bark pigment independent of the biome foliage palette.
	mesh.set_meta("palette_in_custom_data", true)
	mesh.set_meta("extra_cull_margin_m", 0.1)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {0.008: distant_indices, 0.025: far_indices} if lod_level == 0 else {})
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_texture = ATLAS
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.88
	mesh.surface_set_material(0, material)
	return mesh

static func _vertex(st: SurfaceTool, point: Vector3, normal: Vector3, uv: Vector2, color: Color) -> void:
	st.set_normal(normal)
	st.set_uv(uv)
	st.set_color(color)
	st.add_vertex(point)

static func _branch(st: SurfaceTool, start: Vector3, end: Vector3, r0: float, r1: float, sides: int) -> void:
	var axis: Vector3 = (end - start).normalized()
	var helper: Vector3 = Vector3.RIGHT if absf(axis.y) > 0.9 else Vector3.UP
	var side: Vector3 = axis.cross(helper).normalized()
	var other: Vector3 = axis.cross(side).normalized()
	var tint: Color = Color(0.85, 0.85, 0.85, 0.0)
	for face: int in range(sides):
		var n0: Vector3 = side * cos(TAU * face / sides) + other * sin(TAU * face / sides)
		var n1: Vector3 = side * cos(TAU * (face + 1) / sides) + other * sin(TAU * (face + 1) / sides)
		var points: Array[Vector3] = [start + n0 * r0, end + n0 * r1, end + n1 * r1, start + n1 * r0]
		var normals: Array[Vector3] = [n0, n0, n1, n1]
		var u0: float = 0.78 + 0.20 * float(face) / sides
		var u1: float = 0.78 + 0.20 * float(face + 1) / sides
		var uvs: Array[Vector2] = [Vector2(u0, 0.02), Vector2(u0, 0.98), Vector2(u1, 0.98), Vector2(u1, 0.02)]
		for index: int in [0, 1, 2, 0, 2, 3]:
			_vertex(st, points[index], normals[index], uvs[index], tint)

static func _leaf(st: SurfaceTool, base: Vector3, direction: Vector3, length_m: float, roll: float, shade: float) -> void:
	var side: Vector3 = direction.cross(Vector3.UP).normalized().rotated(direction, roll)
	var normal: Vector3 = side.cross(direction).normalized()
	# Eight outline points around a raised midrib: eight curved triangles.
	var points: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	for row: int in range(5):
		var t: float = [0.0, 0.20, 0.48, 0.76, 1.0][row]
		var width: float = [0.0, 0.19, 0.27, 0.19, 0.0][row] * length_m
		var center: Vector3 = base + direction * length_m * t + normal * length_m * (0.10 * sin(t * PI) - 0.12 * t * t)
		for column: int in range(3):
			var offset: float = float(column - 1)
			points.append(center + side * width * offset - normal * absf(offset) * length_m * 0.055 * sin(t * PI))
			uvs.append(Vector2((0.5 + offset * 0.48) * 0.74, 0.02 + t * 0.96))
	var triangles: Array[int] = [7, 1, 3, 7, 3, 6, 7, 6, 9, 7, 9, 13, 7, 13, 11, 7, 11, 8, 7, 8, 5, 7, 5, 1]
	for index: int in triangles:
		var tint: Color = Color(shade, shade, shade, 1.0)
		var n: Vector3 = (normal + side * float(index % 3 - 1) * 0.25).normalized()
		_vertex(st, points[index], n, uvs[index], tint)
