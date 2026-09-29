@tool
class_name DebugConsole
extends CanvasLayer

# Simple in‑game console for Android builds.
# Logs are shown in a semi‑transparent panel at the top‑left.
# Usage: DebugConsole.log("message")

static var _instance: DebugConsole = null
static var _max_lines: int = 200
static var _buffer: PackedStringArray = PackedStringArray()

func _init() -> void:
	_instance = self

func _ready() -> void:
	var panel = Panel.new()
	panel.name = "DebugPanel"
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = 10
	panel.offset_top = 10
	panel.offset_right = -10
	panel.offset_bottom = -10
	panel.modulate = Color(0, 0, 0, 0.6)
	add_child(panel)

	var label = RichTextLabel.new()
	label.name = "LogLabel"
	label.scroll_active = true
	label.scroll_following = true
	label.bbcode_enabled = true
	label.fit_content = true
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(label)

	set_process(true)

static func get_instance() -> DebugConsole:
	return _instance

static func log(message: String) -> void:
	if _instance == null:
		print(message)
		return
	var ts = "[" + Time.get_datetime_string_from_system() + "] " + message
	_buffer.append(ts)
	if _buffer.size() > _max_lines:
		_buffer.remove_at(0)
	var label = _instance.get_node_or_null("DebugPanel/LogLabel") as RichTextLabel
	if label:
		label.clear()
		for line in _buffer:
			label.append_text(line + "\n")
	print(message)
