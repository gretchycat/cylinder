class_name FiniteStateAutomaton
extends RefCounted

const VALID_OPERATORS: Array[String] = ["eq", "ne", "gt", "gte", "lt", "lte", "truthy", "falsey", "exists", "event"]

var automaton_id: String = ""
var initial_state: String = ""
var current_state: String = ""
var states: Dictionary = {}

func configure(definition: Dictionary) -> bool:
	automaton_id = str(definition.get("id", ""))
	initial_state = str(definition.get("initial_state", ""))
	var raw_states: Variant = definition.get("states", {})
	if initial_state.is_empty() or not raw_states is Dictionary or raw_states.is_empty():
		return false
	if not raw_states.has(initial_state):
		return false

	for state_id_variant in raw_states:
		var state_id := str(state_id_variant)
		var state_data: Variant = raw_states[state_id_variant]
		if state_id.is_empty() or not state_data is Dictionary:
			return false
		var transitions: Variant = state_data.get("transitions", [])
		if not transitions is Array:
			return false
		for transition_variant in transitions:
			if not transition_variant is Dictionary:
				return false
			var destination := str(transition_variant.get("to", ""))
			var condition: Variant = transition_variant.get("when", {})
			if not raw_states.has(destination) or not condition is Dictionary or not _condition_is_valid(condition):
				return false

	states = raw_states.duplicate(true)
	current_state = initial_state
	return true

func step(observations: Dictionary) -> Dictionary:
	if current_state.is_empty() or not states.has(current_state):
		return {}
	var previous_state := current_state
	var current_data: Dictionary = states[current_state]
	for transition_variant in current_data.get("transitions", []):
		var transition: Dictionary = transition_variant
		if _condition_matches(transition.get("when", {}), observations):
			current_state = str(transition.to)
			break
	var state_data: Dictionary = states[current_state]
	return {
		"automaton_id": automaton_id,
		"previous_state": previous_state,
		"state": current_state,
		"changed": previous_state != current_state,
		"action_id": str(state_data.get("action_id", ""))
	}

static func _condition_is_valid(condition: Dictionary) -> bool:
	if condition.has("all") or condition.has("any"):
		var key := "all" if condition.has("all") else "any"
		var terms: Variant = condition[key]
		if not terms is Array or terms.is_empty():
			return false
		for term_variant in terms:
			if not term_variant is Dictionary or not _condition_is_valid(term_variant):
				return false
		return true
	var operation := str(condition.get("op", ""))
	if not condition.has("key") or str(condition.get("key", "")).is_empty() or not VALID_OPERATORS.has(operation):
		return false
	return operation in ["truthy", "falsey", "exists"] or condition.has("value")

static func _condition_matches(condition: Dictionary, observations: Dictionary) -> bool:
	if condition.has("all"):
		for term_variant in condition.all:
			if not _condition_matches(term_variant, observations):
				return false
		return true
	if condition.has("any"):
		for term_variant in condition.any:
			if _condition_matches(term_variant, observations):
				return true
		return false

	var key := str(condition.get("key", ""))
	var operation := str(condition.get("op", ""))
	var actual: Variant = observations.get(key)
	if operation == "event":
		var events: Variant = observations.get("_events", [])
		if not events is Array:
			return false
		for event_variant in events:
			if event_variant is Dictionary and str(event_variant.get("event_type", "")) == str(condition.get("value", "")):
				return true
		return false
	if operation == "exists":
		return observations.has(key)
	if not observations.has(key):
		return false
	var expected: Variant = condition.get("value")
	match operation:
		"eq": return actual == expected
		"ne": return actual != expected
		"truthy": return bool(actual)
		"falsey": return not bool(actual)
		"gt", "gte", "lt", "lte":
			if not (actual is int or actual is float) or not (expected is int or expected is float):
				return false
			match operation:
				"gt": return float(actual) > float(expected)
				"gte": return float(actual) >= float(expected)
				"lt": return float(actual) < float(expected)
				"lte": return float(actual) <= float(expected)
	return false
