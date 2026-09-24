class_name CylinderRigidBody
extends RigidBody3D

@export var cylinder_radius: float = 80.0
@export var base_gravity: float = 12.0

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var pos = state.transform.origin
	var radial = Vector3(pos.x, pos.y, 0.0)
	var dist = radial.length()

	if dist > 0.01:
		var dir = radial / dist
		var mag = base_gravity * clampf(dist / cylinder_radius, 0.0, 1.0)
		var gravity_force = dir * mag * mass
		state.apply_central_force(gravity_force)
