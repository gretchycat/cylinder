class_name MobileTouchControls
extends Control

@export var player: PlayerController
@export var joystick_radius: float = 70.0
@export var touch_look_sensitivity: float = 0.0035

var ui_scale: float = 1.0

# Virtual joystick state
var joystick_touch_id: int = -1
var joystick_center: Vector2 = Vector2.ZERO
var joystick_knob_pos: Vector2 = Vector2.ZERO
var joystick_active: bool = false
var is_mouse_joystick: bool = false

# Touch / Drag look state
var look_touch_id: int = -1
var is_mouse_looking: bool = false
var last_look_pos: Vector2 = Vector2.ZERO

@onready var joystick_base: Control = $JoystickBase
@onready var joystick_knob: Control = $JoystickBase/Knob
@onready var jump_btn: Button = $ActionButtons/JumpButton
@onready var fly_btn: Button = $ActionButtons/FlyButton
@onready var sprint_btn: Button = $ActionButtons/SprintButton
@onready var flashlight_btn: Button = get_node_or_null("ActionButtons/FlashlightButton")
@onready var fly_up_btn: Button = get_node_or_null("ActionButtons/FlyUpButton")
@onready var fly_down_btn: Button = get_node_or_null("ActionButtons/FlyDownButton")

func _ready() -> void:
	if not player:
		player = get_tree().get_first_node_in_group("player")

	_ensure_joystick_created()

	if jump_btn:
		jump_btn.pressed.connect(_on_jump_pressed)
	if fly_btn:
		fly_btn.pressed.connect(_on_fly_pressed)
	if sprint_btn:
		sprint_btn.text = "SPRINT: ON" if (player and player.mobile_sprint_active) else "SPRINT: OFF"
		sprint_btn.pressed.connect(_on_sprint_pressed)
	if flashlight_btn and player:
		_update_flashlight_button()
		flashlight_btn.pressed.connect(_on_flashlight_pressed)

	if fly_up_btn:
		fly_up_btn.button_down.connect(func(): if player: player.fly_vertical_axis = 1.0)
		fly_up_btn.button_up.connect(func(): if player and player.fly_vertical_axis > 0: player.fly_vertical_axis = 0.0)
	if fly_down_btn:
		fly_down_btn.button_down.connect(func(): if player: player.fly_vertical_axis = -1.0)
		fly_down_btn.button_up.connect(func(): if player and player.fly_vertical_axis < 0: player.fly_vertical_axis = 0.0)

	_update_fly_buttons_visibility()
	_reset_joystick()

func _process(_delta: float) -> void:
	if (look_touch_id != -1 or is_mouse_looking) and player:
		player.look_control_timer = 0.5

func _input(event: InputEvent) -> void:
	if not player:
		return

	# 1. Touch Events (Mobile or emulated touch)
	if event is InputEventScreenTouch:
		if event.pressed:
			_handle_touch_start(event.index, event.position)
		else:
			_handle_touch_end(event.index)

	elif event is InputEventScreenDrag:
		_handle_touch_drag(event.index, event.position, event.relative)

	# 2. Mouse Drag Events (Desktop standard drag-to-look / drag-joystick)
	elif event is InputEventMouseButton and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_handle_mouse_press(event.position)
			else:
				_handle_mouse_release()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				if not _is_pos_inside_ui(event.position):
					is_mouse_looking = true
					last_look_pos = event.position
			else:
				is_mouse_looking = false

	elif event is InputEventMouseMotion and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_handle_mouse_motion(event.position, event.relative)

func _is_pos_inside_joystick_zone(pos: Vector2) -> bool:
	if not joystick_base or not joystick_base.is_visible_in_tree():
		return false
	var base_rect = joystick_base.get_global_rect()
	var active_rect = base_rect.grow(45.0 * ui_scale)
	return active_rect.has_point(pos)

func _is_pos_inside_ui(pos: Vector2) -> bool:
	if _is_pos_inside_action_buttons(pos):
		return true

	# Control panel or tuning settings
	var ctrl_panel = get_tree().root.find_child("ControlPanel", true, false) as Control
	if ctrl_panel and ctrl_panel.visible and ctrl_panel.get_global_rect().has_point(pos):
		return true

	var telem_panel = get_tree().root.find_child("TelemetryPanel", true, false) as Control
	if telem_panel and telem_panel.visible and telem_panel.get_global_rect().has_point(pos):
		return true

	var toggle_btn = get_tree().root.find_child("ToggleControlsButton", true, false) as Control
	if toggle_btn and toggle_btn.get_global_rect().has_point(pos):
		return true

	var toggle_telem_btn = get_tree().root.find_child("ToggleTelemetryButton", true, false) as Control
	if toggle_telem_btn and toggle_telem_btn.get_global_rect().has_point(pos):
		return true

	return false

func _handle_touch_start(id: int, pos: Vector2) -> void:
	if _is_pos_inside_ui(pos):
		return

	# If touch is in the bottom-left joystick zone: Virtual Joystick MOVEMENT ONLY
	if _is_pos_inside_joystick_zone(pos):
		if joystick_touch_id == -1:
			joystick_touch_id = id
			joystick_active = true
			if joystick_base:
				joystick_center = joystick_base.global_position + (joystick_base.size * 0.5 * ui_scale)
			else:
				joystick_center = pos
			_update_joystick_knob(pos)
			# NOTE: Never triggers look rotation!
		return

	# Dragging ANYWHERE ELSE on the screen: Camera Look Rotation
	elif look_touch_id == -1:
		look_touch_id = id
		last_look_pos = pos

func _handle_touch_drag(id: int, pos: Vector2, rel: Vector2) -> void:
	# Virtual joystick drag: moves player, NEVER rotates view
	if id == joystick_touch_id and joystick_active:
		_update_joystick_knob(pos)

	# Screen drag anywhere else: rotates camera view
	elif id == look_touch_id:
		var look_delta = rel * touch_look_sensitivity
		player.apply_look_input(look_delta)

func _handle_touch_end(id: int) -> void:
	if id == joystick_touch_id:
		_reset_joystick()
	elif id == look_touch_id:
		look_touch_id = -1

func _handle_mouse_press(pos: Vector2) -> void:
	if _is_pos_inside_ui(pos):
		return

	if _is_pos_inside_joystick_zone(pos):
		is_mouse_joystick = true
		joystick_active = true
		if joystick_base:
			joystick_center = joystick_base.global_position + (joystick_base.size * 0.5 * ui_scale)
		else:
			joystick_center = pos
		_update_joystick_knob(pos)
		return

	is_mouse_looking = true
	last_look_pos = pos

func _handle_mouse_motion(pos: Vector2, rel: Vector2) -> void:
	if is_mouse_joystick and joystick_active:
		_update_joystick_knob(pos)
	elif is_mouse_looking:
		var look_delta = rel * touch_look_sensitivity
		player.apply_look_input(look_delta)

func _handle_mouse_release() -> void:
	if is_mouse_joystick:
		is_mouse_joystick = false
		_reset_joystick()
	is_mouse_looking = false

func _update_joystick_knob(pos: Vector2) -> void:
	var offset = pos - joystick_center
	var active_radius = joystick_radius * ui_scale
	var dist = offset.length()
	if dist > active_radius:
		offset = offset.normalized() * active_radius
	joystick_knob_pos = joystick_center + offset

	if joystick_knob and joystick_base:
		var center_in_base = (joystick_base.size * 0.5) - (joystick_knob.size * 0.5)
		joystick_knob.position = center_in_base + (offset / ui_scale)

	var input_vec = offset / maxf(active_radius, 1.0)
	# Joystick only sets movement axis - NO rotation is performed!
	if player:
		player.joystick_override = true
		player.input_axis = Vector2(input_vec.x, input_vec.y)

func _reset_joystick() -> void:
	joystick_touch_id = -1
	is_mouse_joystick = false
	joystick_active = false
	if player:
		player.joystick_override = false
		player.input_axis = Vector2.ZERO
	if joystick_base and joystick_knob:
		joystick_knob.position = (joystick_base.size * 0.5) - (joystick_knob.size * 0.5)

func _ensure_joystick_created() -> void:
	if not joystick_base:
		joystick_base = get_node_or_null("JoystickBase") as Control
	if not joystick_base:
		joystick_base = Panel.new()
		joystick_base.name = "JoystickBase"
		joystick_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
		joystick_base.custom_minimum_size = Vector2(140.0, 140.0)
		joystick_base.layout_mode = 1
		joystick_base.anchors_preset = Control.PRESET_BOTTOM_LEFT
		joystick_base.anchor_left = 0.0
		joystick_base.anchor_right = 0.0
		joystick_base.anchor_top = 1.0
		joystick_base.anchor_bottom = 1.0
		joystick_base.offset_left = 40.0
		joystick_base.offset_top = -180.0
		joystick_base.offset_right = 180.0
		joystick_base.offset_bottom = -40.0
		joystick_base.grow_vertical = Control.GROW_DIRECTION_BEGIN

		var base_style = StyleBoxFlat.new()
		base_style.bg_color = Color(0.10, 0.14, 0.20, 0.65)
		base_style.set_border_width_all(3)
		base_style.border_color = Color(0.35, 0.75, 1.0, 0.8)
		base_style.set_corner_radius_all(70)
		joystick_base.add_theme_stylebox_override("panel", base_style)
		add_child(joystick_base)

	joystick_base.visible = true

	if not joystick_knob:
		joystick_knob = joystick_base.get_node_or_null("Knob") as Control
	if not joystick_knob:
		joystick_knob = Panel.new()
		joystick_knob.name = "Knob"
		joystick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
		joystick_knob.custom_minimum_size = Vector2(50.0, 50.0)
		joystick_knob.size = Vector2(50.0, 50.0)
		joystick_knob.layout_mode = 1
		joystick_knob.anchors_preset = Control.PRESET_CENTER
		joystick_knob.anchor_left = 0.5
		joystick_knob.anchor_right = 0.5
		joystick_knob.anchor_top = 0.5
		joystick_knob.anchor_bottom = 0.5
		joystick_knob.offset_left = -25.0
		joystick_knob.offset_top = -25.0
		joystick_knob.offset_right = 25.0
		joystick_knob.offset_bottom = 25.0
		joystick_knob.grow_horizontal = Control.GROW_DIRECTION_BOTH
		joystick_knob.grow_vertical = Control.GROW_DIRECTION_BOTH

		var knob_style = StyleBoxFlat.new()
		knob_style.bg_color = Color(0.25, 0.75, 1.0, 0.85)
		knob_style.set_border_width_all(2)
		knob_style.border_color = Color(0.85, 0.95, 1.0, 0.95)
		knob_style.set_corner_radius_all(25)
		joystick_knob.add_theme_stylebox_override("panel", knob_style)
		joystick_base.add_child(joystick_knob)

	joystick_knob.visible = true
	_ensure_crosshairs()

func _ensure_crosshairs() -> void:
	if not joystick_base:
		return
	var arrows = [
		{"name": "CrosshairN", "text": "▲", "top": 4.0, "bottom": 24.0, "left": -10.0, "right": 10.0, "anchor_x": 0.5, "anchor_y": 0.0},
		{"name": "CrosshairS", "text": "▼", "top": -24.0, "bottom": -4.0, "left": -10.0, "right": 10.0, "anchor_x": 0.5, "anchor_y": 1.0},
		{"name": "CrosshairW", "text": "◄", "top": -10.0, "bottom": 10.0, "left": 6.0, "right": 26.0, "anchor_x": 0.0, "anchor_y": 0.5},
		{"name": "CrosshairE", "text": "►", "top": -10.0, "bottom": 10.0, "left": -26.0, "right": -6.0, "anchor_x": 1.0, "anchor_y": 0.5},
	]
	for a in arrows:
		var lbl = joystick_base.get_node_or_null(a["name"]) as Label
		if not lbl:
			lbl = Label.new()
			lbl.name = a["name"]
			lbl.text = a["text"]
			lbl.layout_mode = 1
			lbl.anchor_left = a["anchor_x"]
			lbl.anchor_right = a["anchor_x"]
			lbl.anchor_top = a["anchor_y"]
			lbl.anchor_bottom = a["anchor_y"]
			lbl.offset_left = a["left"]
			lbl.offset_right = a["right"]
			lbl.offset_top = a["top"]
			lbl.offset_bottom = a["bottom"]
			lbl.add_theme_color_override("font_color", Color(0.4, 0.75, 1.0, 0.7))
			lbl.add_theme_font_size_override("font_size", 11)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			joystick_base.add_child(lbl)
		lbl.visible = true

func _is_pos_inside_action_buttons(pos: Vector2) -> bool:
	if not has_node("ActionButtons"):
		return false
	var buttons_container = get_node("ActionButtons") as Control
	return buttons_container.get_global_rect().has_point(pos)

func _on_jump_pressed() -> void:
	if player:
		player.jump_requested = true

func _on_fly_pressed() -> void:
	if player:
		player.toggle_fly_mode()
		if fly_btn:
			fly_btn.text = "FLY: ON" if player.is_flying else "FLY: OFF"
		_update_fly_buttons_visibility()

func _on_sprint_pressed() -> void:
	if player:
		player.mobile_sprint_active = not player.mobile_sprint_active
		player.is_sprinting = player.mobile_sprint_active
		if sprint_btn:
			sprint_btn.text = "SPRINT: ON" if player.mobile_sprint_active else "SPRINT: OFF"

func _on_flashlight_pressed() -> void:
	if player:
		player.toggle_debug_flashlight()
		_update_flashlight_button()

func _update_flashlight_button() -> void:
	if flashlight_btn and player:
		flashlight_btn.text = "LIGHT: ON" if player.debug_flashlight_enabled else "LIGHT: OFF"

func _update_fly_buttons_visibility() -> void:
	var flying = player.is_flying if player else false
	if fly_up_btn:
		fly_up_btn.visible = flying
	if fly_down_btn:
		fly_down_btn.visible = flying
