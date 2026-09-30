@tool
extends MeshInstance3D

const Geometry = preload("res://assets/maps/default/models/ground_clutter/clutter_geometry.gd")

@export_enum("grass", "flower", "rock", "crop", "shrub", "mushroom") var model_kind: String = "grass"

func build_mesh() -> Mesh:
	match model_kind:
		"grass":
			return Geometry.grass(0.55, 0.85)
		"flower":
			return Geometry.flower(0.45, 0.80)
		"rock":
			return Geometry.rock(0.40, 0.25)
		"crop":
			return Geometry.crop(0.50, 1.15)
		"shrub":
			return Geometry.shrub(1.10, 0.95)
		"mushroom":
			return Geometry.mushroom(0.22, 0.24)
	return null
