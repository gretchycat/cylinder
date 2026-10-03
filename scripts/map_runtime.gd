class_name MapRuntime
extends RefCounted
const Config = preload("res://scripts/map_config.gd")

static func document(node: Node) -> Dictionary:
	var world = node.get_tree().get_first_node_in_group("cylinder_world") if node.is_inside_tree() else null
	return world.active_map_config if world else Config.load_map_config(Config.active_map())

static func configure_node(node: Node, section: String, doc: Dictionary = {}) -> void:
	if doc.is_empty():
		doc = document(node)
	if doc.is_empty() or not doc.simulation.has(section):
		return
	node.set_meta("map_document", doc)
	var editable: Dictionary = {}
	for property in node.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_EDITOR:
			editable[property.name] = property.type
	for key in doc.simulation[section]:
		if editable.has(key):
			var value = doc.simulation[section][key]
			node.set(key, Config.color(value) if editable[key] == TYPE_COLOR else value)
	for key in ["cylinder_radius", "cylinder_length", "bar_length"]:
		if editable.has(key):
			node.set(key, doc.geometry.cylinder_radius_m if key == "cylinder_radius" else doc.geometry.cylinder_length_m)
	for property in node.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.type == TYPE_OBJECT:
			var value = node.get(property.name)
			if value is ShaderMaterial:
				shader_parameters(value, doc)

static func shader_parameters(material: ShaderMaterial, doc: Dictionary) -> void:
	if not material.shader or doc.is_empty():
		return
	var id = material.shader.resource_path.get_file()
	for key in doc.shader_parameters.get(id, {}):
		var value = doc.shader_parameters[id][key]
		if value is Array:
			if value.size() == 4:
				value = Config.color(value)
			elif value.size() == 3:
				value = Vector3(value[0],value[1],value[2])
			elif value.size() == 2:
				value = Vector2(value[0],value[1])
		material.set_shader_parameter(key, value)
