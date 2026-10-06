@tool
extends MeshInstance3D

const Geometry = preload("res://assets/maps/default/models/ground_clutter/clutter_geometry.gd")

@export_enum("grass", "flower", "rock", "crop", "shrub", "mushroom") var model_kind: String = "grass"

func build_mesh(lod_level: int = 0) -> Mesh:
	match model_kind:
		"grass":
			return Geometry.grass(0.55, 0.85, lod_level)
		"flower":
			return Geometry.flower(0.45, 0.80, lod_level)
		"rock":
			return Geometry.rock(0.42, 0.35, lod_level)
		"crop":
			return Geometry.crop(0.50, 1.15, lod_level)
		"shrub":
			return Geometry.shrub(1.10, 0.95, lod_level)
		"mushroom":
			return Geometry.mushroom(0.22, 0.24, lod_level)
	return null
