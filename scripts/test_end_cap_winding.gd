extends SceneTree

# Run with: godot --headless --path . -s scripts/test_end_cap_winding.gd
func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var cylinder = load("res://scenes/cylinder_world.tscn").instantiate()
	root.add_child(cylinder)
	var arrays: Array = cylinder.mesh_instance.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var counts := [0, 0]
	var failures := [0, 0]
	for offset in range(0, indices.size(), 3):
		var a := indices[offset]
		var b := indices[offset + 1]
		var c := indices[offset + 2]
		if colors[a].b < 0.5:
			continue
		var center := (vertices[a] + vertices[b] + vertices[c]) / 3.0
		var side := 0 if center.z < 0.0 else 1
		counts[side] += 1
		# Godot's clockwise front-face normal must point into the habitat,
		# toward an interior light, and agree with the supplied vertex normals.
		var face_normal := (vertices[c] - vertices[a]).cross(vertices[b] - vertices[a]).normalized()
		var cap_center := Vector3(0.0, 0.0, signf(center.z) * cylinder.cylinder_length * 0.5)
		var to_light := (cap_center - center).normalized()
		var shading_normal := (normals[a] + normals[b] + normals[c]).normalized()
		if face_normal.dot(to_light) <= 0.0 or face_normal.dot(shading_normal) <= 0.0 or shading_normal.dot(to_light) <= 0.0:
			failures[side] += 1
	var expected: int = cylinder.radial_segments * (2 * cylinder.end_cap_rings - 1)
	var passed: bool = counts == [expected, expected] and failures == [0, 0]
	print("End-cap winding: triangles south/north=%s, incorrect=%s" % [counts, failures])
	cylinder.free()
	quit(0 if passed else 1)
