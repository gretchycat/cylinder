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
	panel.anchor_right = 0.75
	panel.anchor_bottom = 0.32
	panel.offset_left = 10
	panel.offset_top = 10
	panel.offset_right = -10
	panel.offset_bottom = -10
	panel.modulate = Color(0, 0, 0, 0.6)
	add_child(panel)

	var content = VBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_theme_constant_override("separation", 4)
	panel.add_child(content)

	var header = HBoxContainer.new()
	content.add_child(header)
	var title = Label.new()
	title.text = "Mobile Diagnostics"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var copy_button = Button.new()
	copy_button.text = "Copy Logs"
	copy_button.pressed.connect(_on_copy_pressed)
	header.add_child(copy_button)

	var label = RichTextLabel.new()
	label.name = "LogLabel"
	label.scroll_active = true
	label.scroll_following = true
	label.bbcode_enabled = false
	label.fit_content = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(label)
	for line in _buffer:
		label.append_text(line + "\n")

	set_process(true)

func _on_copy_pressed() -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set("\n".join(_buffer))

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
