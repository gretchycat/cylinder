class_name EventTracker
extends RefCounted

const ProcessorClass = preload("res://scripts/simulation_event_processor.gd")
const FiniteStateAutomatonClass = preload("res://scripts/finite_state_automaton.gd")
const ACTIONS_PATH := "res://assets/simulation/action_descriptors.json"
const AUTOMATA_PATH := "res://assets/simulation/finite_state_automata.json"
const MAX_RECORDED_EVENTS: int = 4096

var action_descriptors: Dictionary = {}
var automaton_descriptors: Dictionary = {}
var windmill_parameters: Dictionary = {}
var _processors: Dictionary = {}
var events: Array[Dictionary] = []
var next_event_sequence: int = 1

func load_default_descriptors() -> bool:
	var actions_doc := _read_json_dictionary(ACTIONS_PATH)
	var automata_doc := _read_json_dictionary(AUTOMATA_PATH)
	if actions_doc.is_empty() or automata_doc.is_empty():
		return false
	if int(actions_doc.get("schema_version", 0)) != 1 or int(automata_doc.get("schema_version", 0)) != 1:
		return false
	var raw_actions: Variant = actions_doc.get("actions", [])
	var raw_automata: Variant = automata_doc.get("automata", {})
	var raw_windmill_parameters: Variant = automata_doc.get("windmill_parameters", {})
	if not raw_actions is Array or not raw_automata is Dictionary or not raw_windmill_parameters is Dictionary:
		return false

	var parsed_actions: Dictionary = {}
	for action_variant in raw_actions:
		if not action_variant is Dictionary:
			return false
		var action: Dictionary = action_variant
		var action_id := str(action.get("id", ""))
		var preconditions: Variant = action.get("preconditions", {})
		var effects: Variant = action.get("effects", [])
		var emits: Variant = action.get("emits", [])
		if action_id.is_empty() or parsed_actions.has(action_id) or not preconditions is Dictionary or not effects is Array or not emits is Array:
			return false
		if not FiniteStateAutomatonClass._condition_is_valid(preconditions):
			return false
		for effect_variant in effects:
			if not effect_variant is Dictionary:
				return false
			var effect: Dictionary = effect_variant
			if str(effect.get("target", "")).is_empty() or str(effect.get("state", "")).is_empty() or str(effect.get("operation", "")).is_empty():
				return false
		for emit_variant in emits:
			if not emit_variant is Dictionary:
				return false
			var emit: Dictionary = emit_variant
			if str(emit.get("target", "")).is_empty() or str(emit.get("event_type", "")).is_empty() or not emit.get("payload", {}) is Dictionary:
				return false
		parsed_actions[action_id] = action.duplicate(true)

	var parsed_automata: Dictionary = {}
	for automaton_id_variant in raw_automata:
		var automaton_id := str(automaton_id_variant)
		var descriptor: Variant = raw_automata[automaton_id_variant]
		if automaton_id.is_empty() or not descriptor is Dictionary:
			return false
		var definition: Dictionary = descriptor.duplicate(true)
		var tick_interval: Variant = definition.get("simulation_tick_seconds")
		var sensory_abilities: Variant = definition.get("sensory_abilities", [])
		if not (tick_interval is int or tick_interval is float) or not is_finite(float(tick_interval)) or float(tick_interval) <= 0.0:
			return false
		if not sensory_abilities is Array:
			return false
		for ability_variant in sensory_abilities:
			if not ability_variant is String or str(ability_variant).is_empty():
				return false
		var fsa: Variant = FiniteStateAutomatonClass.new()
		definition["id"] = automaton_id
		if not fsa.configure(definition):
			return false
		for state_variant in definition.states.values():
			var state: Dictionary = state_variant
			var action_id := str(state.get("action_id", ""))
			if not action_id.is_empty() and not parsed_actions.has(action_id) and not action_id.begins_with("windmill_") and action_id != "convert_wind_to_rotation":
				return false
		parsed_automata[automaton_id] = definition

	if not _valid_windmill_parameters(raw_windmill_parameters):
		return false
	action_descriptors = parsed_actions
	automaton_descriptors = parsed_automata
	windmill_parameters = raw_windmill_parameters.duplicate(true)
	return true

func register_agent(agent_id: String, automaton_type: String, initial_state: String = "", persistent_state: Dictionary = {}) -> bool:
	if agent_id.is_empty() or _processors.has(agent_id) or not automaton_descriptors.has(automaton_type):
		return false
	var definition: Dictionary = automaton_descriptors[automaton_type].duplicate(true)
	if not initial_state.is_empty():
		if not definition.states.has(initial_state):
			return false
		definition.initial_state = initial_state
	var sensory_abilities: Array[String] = []
	for ability_variant in definition.get("sensory_abilities", []):
		sensory_abilities.append(str(ability_variant))
	var processor: Variant = ProcessorClass.new(
		agent_id,
		automaton_type,
		definition,
		float(definition.simulation_tick_seconds),
		action_descriptors,
		sensory_abilities,
		persistent_state
	)
	if processor.automaton == null:
		return false
	_processors[agent_id] = processor
	return true

func unregister_agent(agent_id: String) -> bool:
	return _processors.erase(agent_id)

func has_processor(agent_id: String) -> bool:
	return _processors.has(agent_id)

func set_agent_property(agent_id: String, key: String, value: Variant) -> bool:
	if not _processors.has(agent_id) or key.is_empty():
		return false
	_processors[agent_id].properties[key] = value
	return true

func advance_agent(agent_id: String, elapsed_seconds: float, observations: Dictionary) -> Dictionary:
	if not _processors.has(agent_id):
		return {}
	var result: Dictionary = _processors[agent_id].advance(elapsed_seconds, observations)
	_record_processor_results(agent_id, result.get("tick_results", []))
	return result

func get_tick_interval(agent_id: String) -> float:
	if not _processors.has(agent_id):
		return 0.0
	return float(_processors[agent_id].tick_interval_seconds)

func get_sensory_abilities(agent_id: String) -> Array[String]:
	if not _processors.has(agent_id):
		return []
	return _processors[agent_id].sensory_abilities.duplicate()

func _get_persistent_state_for_save(agent_id: String) -> Dictionary:
	if not _processors.has(agent_id):
		return {}
	return _processors[agent_id].persistent_state()

func push_event(source_id: String, target_id: String, event_type: String, payload: Dictionary = {}) -> bool:
	if source_id.is_empty() or target_id.is_empty() or event_type.is_empty():
		return false
	if not _processors.has(source_id) or not _processors.has(target_id):
		return false
	var event := {
		"event_id": "%s_event_%08d" % [source_id, next_event_sequence],
		"sequence": next_event_sequence,
		"event_type": event_type,
		"source_id": source_id,
		"target_id": target_id,
		"payload": payload.duplicate(true)
	}
	if not _processors[target_id].enqueue_event(event):
		return false
	next_event_sequence += 1
	_record_event(event)
	return true

func get_events_after(sequence: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event in events:
		if int(event.sequence) > sequence:
			result.append(event.duplicate(true))
	return result

func _record_processor_results(agent_id: String, tick_results: Variant) -> void:
	if not tick_results is Array:
		return
	for result_variant in tick_results:
		if not result_variant is Dictionary:
			continue
		var result: Dictionary = result_variant
		if bool(result.get("changed", false)):
			record_event("state_changed", agent_id, {
				"automaton_type": str(result.get("object_type", "")),
				"from_state": str(result.get("previous_state", "")),
				"to_state": str(result.get("state", ""))
			})
		if bool(result.get("action_started", false)):
			record_event("action_started", agent_id, {"action_id": str(result.get("action_id", "")), "state": str(result.get("state", ""))})
		for emit_variant in result.get("emitted_events", []):
			if not emit_variant is Dictionary:
				continue
			var emit: Dictionary = emit_variant
			var target := agent_id if str(emit.target) == "self" else str(emit.target)
			push_event(agent_id, target, str(emit.event_type), emit.get("payload", {}))

func record_event(event_type: String, actor_id: String, payload: Dictionary = {}) -> Dictionary:
	if event_type.is_empty() or actor_id.is_empty():
		return {}
	var event := {
		"event_id": "%s_event_%08d" % [actor_id, next_event_sequence],
		"sequence": next_event_sequence,
		"event_type": event_type,
		"actor_id": actor_id,
		"payload": payload.duplicate(true)
	}
	next_event_sequence += 1
	_record_event(event)
	return event.duplicate(true)

func _record_event(event: Dictionary) -> void:
	events.append(event.duplicate(true))
	if events.size() > MAX_RECORDED_EVENTS:
		events.pop_front()

static func _read_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

static func _valid_windmill_parameters(parameters: Dictionary) -> bool:
	var required := [
		"alignment_tolerance_deg", "cut_in_speed_m_s", "cut_out_speed_m_s", "blade_radius_m",
		"air_density_kg_m3", "torque_coefficient", "rotor_inertia_kg_m2",
		"bearing_drag_nm_per_rad_s", "generator_load_nm", "generator_efficiency", "max_rotor_speed_rad_s"
	]
	for key_variant in required:
		var key := str(key_variant)
		var value: Variant = parameters.get(key)
		if not parameters.has(key) or not (value is int or value is float) or not is_finite(float(value)):
			return false
	return (
		float(parameters.alignment_tolerance_deg) >= 0.0 and float(parameters.alignment_tolerance_deg) <= 90.0
		and float(parameters.cut_in_speed_m_s) >= 0.0
		and float(parameters.cut_out_speed_m_s) > float(parameters.cut_in_speed_m_s)
		and float(parameters.blade_radius_m) > 0.0
		and float(parameters.air_density_kg_m3) >= 0.0
		and float(parameters.torque_coefficient) >= 0.0
		and float(parameters.rotor_inertia_kg_m2) > 0.0
		and float(parameters.bearing_drag_nm_per_rad_s) >= 0.0
		and float(parameters.generator_load_nm) >= 0.0
		and float(parameters.generator_efficiency) >= 0.0 and float(parameters.generator_efficiency) <= 1.0
		and float(parameters.max_rotor_speed_rad_s) > 0.0
	)
