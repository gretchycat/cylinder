class_name SimulationEventProcessor
extends RefCounted

const FiniteStateAutomatonClass = preload("res://scripts/finite_state_automaton.gd")
const MAX_PENDING_EVENTS := 256
const MAX_CATCH_UP_TICKS := 16

var processor_id: String
var object_type: String
var tick_interval_seconds: float
var sensory_abilities: Array[String] = []
var tick_accumulator_seconds: float = 0.0
var automaton: Variant
var action_descriptors: Dictionary
var properties: Dictionary = {}
var _event_queue: Array[Dictionary] = []
var last_action_id: String = ""

func _init(
	p_processor_id: String,
	p_object_type: String,
	automaton_definition: Dictionary,
	p_tick_interval_seconds: float,
	p_action_descriptors: Dictionary,
	p_sensory_abilities: Array[String] = [],
	persistent_state: Dictionary = {}
) -> void:
	processor_id = p_processor_id
	object_type = p_object_type
	tick_interval_seconds = p_tick_interval_seconds
	sensory_abilities = p_sensory_abilities.duplicate()
	action_descriptors = p_action_descriptors
	automaton = FiniteStateAutomatonClass.new()
	if not automaton.configure(automaton_definition):
		automaton = null
		return
	var stored_state := str(persistent_state.get("fsm_state", ""))
	if not stored_state.is_empty() and automaton.states.has(stored_state):
		automaton.current_state = stored_state
	tick_accumulator_seconds = maxf(float(persistent_state.get("tick_accumulator_seconds", 0.0)), 0.0)
	last_action_id = str(persistent_state.get("last_action_id", ""))
	var stored_properties: Variant = persistent_state.get("properties", {})
	if stored_properties is Dictionary:
		properties = stored_properties.duplicate(true)
	var stored_events: Variant = persistent_state.get("pending_events", [])
	if stored_events is Array:
		for event_variant in stored_events.slice(maxi(stored_events.size() - MAX_PENDING_EVENTS, 0)):
			if event_variant is Dictionary:
				_event_queue.append(event_variant.duplicate(true))

func enqueue_event(event: Dictionary) -> bool:
	if event.is_empty() or _event_queue.size() >= MAX_PENDING_EVENTS:
		return false
	_event_queue.append(event.duplicate(true))
	return true

func advance(delta: float, observations: Dictionary) -> Dictionary:
	if not is_finite(delta) or delta <= 0.0 or tick_interval_seconds <= 0.0 or automaton == null:
		return _idle_result()
	tick_accumulator_seconds += delta
	var results: Array[Dictionary] = []
	while results.size() < MAX_CATCH_UP_TICKS and tick_accumulator_seconds + 0.0000001 >= tick_interval_seconds:
		tick_accumulator_seconds = maxf(tick_accumulator_seconds - tick_interval_seconds, 0.0)
		results.append(_process_tick(observations))
	var output: Dictionary = results.back() if not results.is_empty() else _idle_result()
	output["ticks_processed"] = results.size()
	output["tick_results"] = results
	return output

func _process_tick(observations: Dictionary) -> Dictionary:
	var tick_observations := observations.duplicate(true)
	var received_events := _event_queue
	_event_queue = []
	tick_observations["_events"] = received_events
	var result: Dictionary = automaton.step(tick_observations)
	var action_id := str(result.get("action_id", ""))
	var action: Dictionary = action_descriptors.get(action_id, {}).duplicate(true)
	var action_started := not action_id.is_empty() and action_id != last_action_id
	var applied_effects: Array[Dictionary] = []
	if action_started:
		for effect_variant in action.get("effects", []):
			if not effect_variant is Dictionary:
				continue
			var effect: Dictionary = effect_variant
			if str(effect.get("target", "")) not in ["self", "actor"]:
				continue
			var key := str(effect.get("state", ""))
			var operation := str(effect.get("operation", ""))
			if key.is_empty() or operation not in ["set", "add", "subtract"] or not effect.has("value"):
				continue
			var value: Variant = effect.value
			match operation:
				"set": properties[key] = value
				"add", "subtract":
					if (value is int or value is float) and (properties.get(key, 0) is int or properties.get(key, 0) is float):
						var signed_value := float(value) if operation == "add" else -float(value)
						properties[key] = float(properties.get(key, 0.0)) + signed_value
			applied_effects.append(effect.duplicate(true))
	if action_started:
		last_action_id = action_id
	var output := result.duplicate(true)
	output["processor_id"] = processor_id
	output["object_type"] = object_type
	output["action"] = action
	output["action_started"] = action_started
	output["applied_effects"] = applied_effects
	output["emitted_events"] = action.get("emits", []).duplicate(true) if action_started else []
	output["received_event_count"] = received_events.size()
	output["properties"] = properties.duplicate(true)
	return output

func current_state() -> String:
	return str(automaton.current_state) if automaton != null else ""

func persistent_state() -> Dictionary:
	return {
		"fsm_state": current_state(),
		"tick_accumulator_seconds": tick_accumulator_seconds,
		"last_action_id": last_action_id,
		"properties": properties.duplicate(true),
		"pending_events": _event_queue.duplicate(true)
	}

func _idle_result() -> Dictionary:
	return {
		"processor_id": processor_id,
		"object_type": object_type,
		"state": current_state(),
		"action_id": last_action_id,
		"action_started": false,
		"ticks_processed": 0,
		"tick_results": []
	}
