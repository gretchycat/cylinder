@tool
extends RefCounted

# Procedural 3-D geometry for ground clutter.
#
# These functions deliberately return low-poly ArrayMesh objects.  The
# ClutterManager can continue to share/instance the resulting meshes.

static func _add_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_normal(n)
	st.add_vertex(c)


static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_add_triangle(st, a, b, c)
	_add_triangle(st, a, c, d)


static func _add_triangle_colored(st: SurfaceTool, a: Vector3, ca: Color, b: Vector3, cb: Color, c: Vector3, cc: Color) -> void:
	var n := (b - a).cross(c - a).normalized()
	st.set_normal(n)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_normal(n)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_normal(n)
	st.set_color(cc)
	st.add_vertex(c)


static func _add_quad_colored(st: SurfaceTool, a: Vector3, ca: Color, b: Vector3, cb: Color, c: Vector3, cc: Color, d: Vector3, cd: Color) -> void:
	_add_triangle_colored(st, a, ca, b, cb, c, cc)
	_add_triangle_colored(st, a, ca, c, cc, d, cd)


static func _ring_point(center: Vector3, radius: float, angle: float) -> Vector3:
	return center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


# Grass: several real 3-D tapered blades rather than intersecting cards.
static func grass(width_m: float = 0.55, height_m: float = 0.85, _lod_level: int = 0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var blade_count := 9
	for i in range(blade_count):
		var a := TAU * float(i) / float(blade_count)
		var lean := Vector3(cos(a), 0.0, sin(a)) * width_m * 0.22
		var side := Vector3(-sin(a), 0.0, cos(a))
		var root := Vector3.ZERO
		var mid := lean * 0.55 + Vector3(0.0, height_m * 0.55, 0.0)
		var tip := lean + Vector3(0.0, height_m, 0.0)

		var root_w := width_m * 0.075
		var mid_w := width_m * 0.055

		var r1 := root - side * root_w
		var r2 := root + side * root_w
		var m1 := mid - side * mid_w
		var m2 := mid + side * mid_w

		# Calculate subtle pseudo-random luminance variation per blade
		var var_v := 0.94 + 0.12 * sin(float(i * 3 + 1))

		var col_root := Color(0.35 * var_v, 0.35 * var_v, 0.35 * var_v, 1.0)
		var col_mid  := Color(0.68 * var_v, 0.68 * var_v, 0.68 * var_v, 1.0)
		var col_tip  := Color(1.00 * var_v, 1.00 * var_v, 1.00 * var_v, 1.0)

		_add_quad_colored(st, r1, col_root, r2, col_root, m2, col_mid, m1, col_mid)
		_add_triangle_colored(st, m1, col_mid, m2, col_mid, tip, col_tip)

	return st.commit()


# A flower with a cylindrical stem, two small leaves, and a faceted blossom.
static func flower(width_m: float = 0.45, height_m: float = 0.80, _lod_level: int = 0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Stem & leaves: explicit green RGB, alpha = 0.0 so instance palette tinting is bypassed.
	st.set_color(Color(0.18, 0.52, 0.14, 0.0))
	_add_cylinder(st, 0.01 * width_m / 0.45, height_m * 0.82, 7, Vector3.ZERO)

	# Two leaves.
	st.set_color(Color(0.22, 0.58, 0.16, 0.0))
	var leaf_y := height_m * 0.40
	_add_leaf(st, Vector3(0, leaf_y, 0), Vector3(1, 0.08, 0.15), width_m * 0.55, width_m * 0.21)
	_add_leaf(st, Vector3(0, leaf_y * 1.12, 0), Vector3(-0.8, 0.06, 0.3), width_m * 0.52, width_m * 0.19)

	# Tilt the flower face off the stem axis. Instance yaw rotates the tilt
	# direction independently, so flowers do not all face parallel to the soil.
	var center := Vector3(0, height_m * 0.86, 0)
	var petal_radius := width_m * 0.32
	var head_up := Vector3(0.24, 0.96, -0.12).normalized()
	var head_right := (Vector3.RIGHT - head_up * head_up.dot(Vector3.RIGHT)).normalized()
	var head_forward := head_up.cross(head_right).normalized()
	var center_lift := head_up * width_m * 0.045
	st.set_color(Color(1.0, 1.0, 1.0, 1.0))
	for i in range(8):
		var a := TAU * float(i) / 8.0
		var dir := head_right * cos(a) + head_forward * sin(a)
		var side := -head_right * sin(a) + head_forward * cos(a)
		var p0 := center + dir * width_m * 0.06
		var p1 := center + dir * petal_radius
		var p2 := p1 + side * width_m * 0.12
		var p3 := p1 - side * width_m * 0.12
		_add_triangle(st, p0, p3, p2)
		_add_triangle(st, p2, p3, center + center_lift)

	# Raised golden center, independent of each instance's petal hue.
	st.set_color(Color(0.95, 0.82, 0.15, 0.0))
	_add_uv_sphere(st, center + center_lift * 1.15, width_m * 0.10, 6, 3)

	return st.commit()


# Mushroom: curved-ish segmented stem plus a low-poly hemispherical cap.
static func mushroom(width_m: float = 0.22, height_m: float = 0.24, _lod_level: int = 0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var stem_r := width_m * 0.15
	var stem_h := height_m * 0.58
	# Vertex alpha marks the stem separately from the per-instance cap color.
	st.set_color(Color(1.0, 1.0, 1.0, 0.20))
	_add_curved_cylinder(
		st,
		[
			Vector3(0, 0, 0),
			Vector3(width_m * 0.025, stem_h * 0.35, width_m * 0.01),
			Vector3(-width_m * 0.03, stem_h * 0.72, width_m * 0.015),
			Vector3(0, stem_h, 0)
		],
		stem_r,
		7
	)

	st.set_color(Color(1.0, 1.0, 1.0, 1.0))
	var cap_center := Vector3(0, stem_h, 0)
	_add_hemisphere(st, cap_center, width_m * 0.52, 8, 3)

	return st.commit()


# Rock: smooth rounded 3D boulder with base shadow and top highlight.
static func rock(radius: float = 0.42, height: float = 0.35, _lod_level: int = 0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var sides := 10
	var rings := 3
	var radii: Array[float] = [radius * 0.80, radius * 1.00, radius * 0.65]
	var ys: Array[float] = [-height * 0.10, height * 0.30, height * 0.80]
	var col_bottom := Color(0.24, 0.26, 0.34, 1.0)
	var col_mid    := Color(0.40, 0.44, 0.50, 1.0)
	var col_top    := Color(0.75, 0.82, 0.95, 1.0)

	var rings_pts: Array = []
	for r in range(rings):
		var pts: Array[Vector3] = []
		for i in range(sides):
			var a := TAU * float(i) / float(sides)
			# Gentle organic oval variation (smooth round stone, no star spikes)
			var variation := 0.95 + 0.08 * sin(a * 2.0 + float(r) * 0.4)
			var xz: float = radii[r] * variation
			pts.append(Vector3(cos(a) * xz, ys[r], sin(a) * xz))
		rings_pts.append(pts)

	# Quads between rings
	for r in range(rings - 1):
		var c1: Color = col_bottom if r == 0 else col_mid
		var c2: Color = col_mid if r == 0 else col_top
		for i in range(sides):
			var j := (i + 1) % sides
			_add_quad_colored(st, rings_pts[r][i], c1, rings_pts[r][j], c1, rings_pts[r + 1][j], c2, rings_pts[r + 1][i], c2)

	# Top cap
	var top := Vector3(0, height * 1.02, 0)
	for i in range(sides):
		var j := (i + 1) % sides
		_add_triangle_colored(st, rings_pts[2][i], col_top, rings_pts[2][j], col_top, top, col_top)

	# Bottom cap
	var bottom := Vector3(0, -height * 0.18, 0)
	for i in range(sides):
		var j := (i + 1) % sides
		_add_triangle_colored(st, bottom, col_bottom, rings_pts[0][j], col_bottom, rings_pts[0][i], col_bottom)

	st.generate_normals()
	return st.commit()


# Crop/wheat: several real cylindrical stalks with a small grain head.
static func crop(width_m: float = 0.50, height_m: float = 1.15, _lod_level: int = 0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(5):
		var a := TAU * float(i) / 5.0
		var offset := Vector3(cos(a), 0, sin(a)) * width_m * 0.18
		var lean := Vector3(cos(a + 0.7), 0, sin(a + 0.7)) * width_m * 0.12
		_add_curved_cylinder(
			st,
			[offset, offset + lean * 0.4 + Vector3(0, height_m * 0.45, 0),
				offset + lean + Vector3(0, height_m, 0)],
			width_m * 0.025,
			6
		)
		_add_uv_sphere(st, offset + lean + Vector3(0, height_m, 0), width_m * 0.055, 5, 3)

	return st.commit()


# Shrub: a compact cluster of low-poly leaf blobs around short stems.
static func shrub(width_m: float = 1.10, height_m: float = 0.95, _lod_level: int = 0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(7):
		var a := TAU * float(i) / 7.0
		var radius := width_m * (0.20 + 0.12 * float(i % 3))
		var center := Vector3(
			cos(a) * radius,
			height_m * (0.35 + 0.08 * float(i % 2)),
			sin(a) * radius
		)
		var var_v := 0.92 + 0.14 * sin(float(i * 3 + 1))
		st.set_color(Color(0.70 * var_v, 0.70 * var_v, 0.70 * var_v, 1.0))
		_add_uv_sphere(st, center, width_m * (0.20 + 0.025 * float(i % 3)), 6, 4)

	st.set_color(Color(0.95, 0.95, 0.95, 1.0))
	_add_uv_sphere(st, Vector3(0, height_m * 0.62, 0), width_m * 0.30, 7, 4)

	return st.commit()


static func _add_cylinder(
	st: SurfaceTool,
	radius: float,
	height: float,
	sides: int,
	base: Vector3
) -> void:
	var bottom := base
	var top := base + Vector3(0, height, 0)

	for i in range(sides):
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var b0 := bottom + Vector3(cos(a0) * radius, 0, sin(a0) * radius)
		var b1 := bottom + Vector3(cos(a1) * radius, 0, sin(a1) * radius)
		var t0 := top + Vector3(cos(a0) * radius, 0, sin(a0) * radius)
		var t1 := top + Vector3(cos(a1) * radius, 0, sin(a1) * radius)
		_add_quad(st, b0, b1, t1, t0)


static func _add_curved_cylinder(
	st: SurfaceTool,
	points: Array[Vector3],
	radius: float,
	sides: int
) -> void:
	for p in range(points.size() - 1):
		var a := points[p]
		var b := points[p + 1]
		var tangent := (b - a).normalized()
		var helper := Vector3.UP
		if absf(tangent.dot(helper)) > 0.9:
			helper = Vector3.RIGHT
		var side := tangent.cross(helper).normalized()
		var up := side.cross(tangent).normalized()

		for i in range(sides):
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)
			var v0 := cos(a0) * side + sin(a0) * up
			var v1 := cos(a1) * side + sin(a1) * up
			_add_quad(
				st,
				a + v0 * radius,
				a + v1 * radius,
				b + v1 * radius,
				b + v0 * radius
			)


static func _add_leaf(
	st: SurfaceTool,
	base: Vector3,
	direction: Vector3,
	length: float,
	width: float
) -> void:
	var d := direction.normalized()
	var side := Vector3(-d.z, 0, d.x).normalized()
	var tip := base + d * length + Vector3(0, length * 0.18, 0)
	_add_triangle(st, base, base + side * width, tip)
	_add_triangle(st, base, tip, base - side * width)


static func _add_hemisphere(
	st: SurfaceTool,
	center: Vector3,
	radius: float,
	sides: int,
	rings: int
) -> void:
	for r in range(rings):
		var v0 := float(r) / float(rings)
		var v1 := float(r + 1) / float(rings)
		var phi0 := (PI * 0.5) * v0
		var phi1 := (PI * 0.5) * v1

		for i in range(sides):
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)

			var p00 := center + Vector3(cos(a0) * cos(phi0), sin(phi0), sin(a0) * cos(phi0)) * radius
			var p01 := center + Vector3(cos(a1) * cos(phi0), sin(phi0), sin(a1) * cos(phi0)) * radius
			var p10 := center + Vector3(cos(a0) * cos(phi1), sin(phi1), sin(a0) * cos(phi1)) * radius
			var p11 := center + Vector3(cos(a1) * cos(phi1), sin(phi1), sin(a1) * cos(phi1)) * radius
			_add_quad(st, p00, p01, p11, p10)


static func _add_uv_sphere(
	st: SurfaceTool,
	center: Vector3,
	radius: float,
	sides: int,
	rings: int
) -> void:
	for r in range(rings):
		var v0 := float(r) / float(rings)
		var v1 := float(r + 1) / float(rings)
		var phi0 := PI * v0
		var phi1 := PI * v1

		for i in range(sides):
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)

			var p00 := center + Vector3(sin(phi0) * cos(a0), cos(phi0), sin(phi0) * sin(a0)) * radius
			var p01 := center + Vector3(sin(phi0) * cos(a1), cos(phi0), sin(phi0) * sin(a1)) * radius
			var p10 := center + Vector3(sin(phi1) * cos(a0), cos(phi1), sin(phi1) * sin(a0)) * radius
			var p11 := center + Vector3(sin(phi1) * cos(a1), cos(phi1), sin(phi1) * sin(a1)) * radius
			_add_quad(st, p00, p01, p11, p10)
