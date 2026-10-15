class_name WindmillSimulation
extends RefCounted

const EventTrackerClass = preload("res://scripts/event_tracker.gd")

var event_tracker: Variant
var agent_id: String = "windmill"
var rotor_angular_velocity_rad_s: float = 0.0
var generated_energy_j: float = 0.0
var last_power_w: float = 0.0
var last_drive_torque_nm: float = 0.0
var last_alignment_delta_deg: float = 180.0
var last_state: String = "stopped"

func _init(p_agent_id: String = "windmill", shared_tracker: Variant = null, persistent_state: Dictionary = {}) -> void:
	agent_id = p_agent_id if not p_agent_id.is_empty() else "windmill"
	event_tracker = shared_tracker if shared_tracker != null else EventTrackerClass.new()
	if event_tracker.automaton_descriptors.is_empty():
		event_tracker.load_default_descriptors()
	rotor_angular_velocity_rad_s = _valid_state_number(persistent_state, "rotor_angular_velocity_rad_s", 0.0)
	generated_energy_j = maxf(_valid_state_number(persistent_state, "generated_energy_j", 0.0), 0.0)
	last_power_w = maxf(_valid_state_number(persistent_state, "generated_power_w", 0.0), 0.0)
	last_drive_torque_nm = _valid_state_number(persistent_state, "drive_torque_nm", 0.0)
	last_alignment_delta_deg = clampf(_valid_state_number(persistent_state, "alignment_delta_deg", 180.0), 0.0, 180.0)
	last_state = str(persistent_state.get("state", "stopped"))
	var processor_state: Variant = persistent_state.get("processor", {})
	if not processor_state is Dictionary:
		processor_state = {}
	if not event_tracker.has_processor(agent_id):
		event_tracker.register_agent(agent_id, "windmill", "", processor_state)
	elif not processor_state.is_empty():
		# Re-register only if a prior streamed representation did not unregister cleanly.
		event_tracker.unregister_agent(agent_id)
		event_tracker.register_agent(agent_id, "windmill", "", processor_state)
	if event_tracker.has_processor(agent_id):
		var restored_fsm_state := str(processor_state.get("fsm_state", ""))
		if not restored_fsm_state.is_empty():
			last_state = restored_fsm_state

func step(
	delta: float,
	wind_speed_m_s: float,
	wind_direction_deg: float,
	rotor_heading_deg: float,
	spin_direction: int = 1
) -> Dictionary:
	if not is_finite(delta) or delta <= 0.0:
		return get_state()
	if not is_finite(wind_speed_m_s) or not is_finite(wind_direction_deg) or not is_finite(rotor_heading_deg):
		return get_state()

	var params: Dictionary = event_tracker.windmill_parameters
	var wind_speed := maxf(wind_speed_m_s, 0.0)
	var tolerance := clampf(float(params.get("alignment_tolerance_deg", 25.0)), 0.0, 90.0)
	var speed_cut_in := maxf(float(params.get("cut_in_speed_m_s", 2.0)), 0.0)
	var speed_cut_out := maxf(float(params.get("cut_out_speed_m_s", 25.0)), speed_cut_in)
	var directed_delta := absf(wrapf(wind_direction_deg - rotor_heading_deg + 180.0, 0.0, 360.0) - 180.0)
	var alignment_delta := minf(directed_delta, absf(180.0 - directed_delta))
	var wind_usable := alignment_delta <= tolerance and wind_speed >= speed_cut_in and wind_speed <= speed_cut_out
	var wind_sensor := {
		"speed_m_s": wind_speed,
		"direction_deg": wind_direction_deg,
		"rotor_alignment_delta_deg": alignment_delta
	}
	var tick_result: Dictionary = event_tracker.advance_agent(agent_id, delta, {
		"wind_usable": wind_usable,
		"wind": wind_sensor
	})
	var ticks: Array = tick_result.get("tick_results", [])
	for decision_variant in ticks:
		if decision_variant is Dictionary:
			_integrate_tick(float(event_tracker.get_tick_interval(agent_id)), wind_speed, alignment_delta, spin_direction, decision_variant)
	var output := get_state()
	output["ticks_processed"] = ticks.size()
	output["wind_usable"] = wind_usable
	output["wind_speed_m_s"] = wind_speed
	output["wind_sensor"] = wind_sensor
	if not ticks.is_empty():
		output["decision"] = ticks.back()
	return output

func _integrate_tick(tick_seconds: float, wind_speed: float, alignment_delta: float, spin_direction: int, decision: Dictionary) -> void:
	last_state = str(decision.get("state", last_state))
	last_alignment_delta_deg = alignment_delta
	var drive_torque := 0.0
	if last_state == "turning":
		var params: Dictionary = event_tracker.windmill_parameters
		var radius := maxf(float(params.get("blade_radius_m", 3.1)), 0.1)
		var swept_area := PI * radius * radius
		var air_density := maxf(float(params.get("air_density_kg_m3", 1.225)), 0.0)
		var torque_coefficient := maxf(float(params.get("torque_coefficient", 0.08)), 0.0)
		var aligned_speed := wind_speed * cos(deg_to_rad(alignment_delta))
		drive_torque = 0.5 * air_density * swept_area * aligned_speed * aligned_speed * radius * torque_coefficient
	last_drive_torque_nm = drive_torque

	var params: Dictionary = event_tracker.windmill_parameters
	var direction := -1.0 if spin_direction < 0 else 1.0
	var inertia := maxf(float(params.get("rotor_inertia_kg_m2", 90.0)), 0.01)
	var bearing_drag := maxf(float(params.get("bearing_drag_nm_per_rad_s", 0.5)), 0.0)
	var generator_load := maxf(float(params.get("generator_load_nm", 70.0)), 0.0) if last_state == "turning" else 0.0
	var maximum_speed := maxf(float(params.get("max_rotor_speed_rad_s", 2.5)), 0.01)
	var signed_drive_torque := drive_torque * direction
	var load_scale := clampf(absf(rotor_angular_velocity_rad_s) / maximum_speed, 0.0, 1.0)
	var generator_drag := signf(rotor_angular_velocity_rad_s) * generator_load * load_scale
	var bearing_torque := bearing_drag * rotor_angular_velocity_rad_s
	var angular_acceleration := (signed_drive_torque - generator_drag - bearing_torque) / inertia
	rotor_angular_velocity_rad_s = clampf(
		rotor_angular_velocity_rad_s + angular_acceleration * tick_seconds,
		-maximum_speed,
		maximum_speed
	)
	var efficiency := clampf(float(params.get("generator_efficiency", 0.75)), 0.0, 1.0)
	last_power_w = generator_load * absf(rotor_angular_velocity_rad_s) * efficiency if last_state == "turning" else 0.0
	generated_energy_j += last_power_w * tick_seconds
	event_tracker.set_agent_property(agent_id, "rotor_angular_velocity_rad_s", rotor_angular_velocity_rad_s)
	event_tracker.set_agent_property(agent_id, "generated_energy_j", generated_energy_j)

func get_state() -> Dictionary:
	return {
		"state": last_state,
		"rotor_angular_velocity_rad_s": rotor_angular_velocity_rad_s,
		"generated_power_w": last_power_w,
		"generated_energy_j": generated_energy_j,
		"drive_torque_nm": last_drive_torque_nm,
		"alignment_delta_deg": last_alignment_delta_deg,
		"tick_interval_seconds": event_tracker.get_tick_interval(agent_id) if event_tracker and event_tracker.has_processor(agent_id) else 0.0
	}

func get_persistent_state() -> Dictionary:
	var state := get_state()
	state["processor"] = event_tracker._get_persistent_state_for_save(agent_id) if event_tracker and event_tracker.has_processor(agent_id) else {}
	return state

func dispose() -> void:
	if event_tracker and event_tracker.has_processor(agent_id):
		event_tracker.unregister_agent(agent_id)

func _valid_state_number(state: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = state.get(key, fallback)
	if not (value is int or value is float) or not is_finite(float(value)):
		return fallback
	return float(value)
