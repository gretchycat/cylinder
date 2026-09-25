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
@onready var wobble_btn: Button = get_node_or_null("ActionButtons/WobbleButton")
@onready var fly_up_btn: Button = get_node_or_null("ActionButtons/FlyUpButton")
@onready var fly_down_btn: Button = get_node_or_null("ActionButtons/FlyDownButton")

func _ready() -> void:
	if not player:
		player = get_tree().get_first_node_in_group("player")

	if jump_btn:
		jump_btn.pressed.connect(_on_jump_pressed)
	if fly_btn:
		fly_btn.pressed.connect(_on_fly_pressed)
	if sprint_btn:
		sprint_btn.pressed.connect(_on_sprint_pressed)
	if wobble_btn:
		wobble_btn.pressed.connect(_on_wobble_pressed)

	if fly_up_btn:
		fly_up_btn.button_down.connect(func(): if player: player.fly_vertical_axis = 1.0)
		fly_up_btn.button_up.connect(func(): if player and player.fly_vertical_axis > 0: player.fly_vertical_axis = 0.0)
	if fly_down_btn:
		fly_down_btn.button_down.connect(func(): if player: player.fly_vertical_axis = -1.0)
		fly_down_btn.button_up.connect(func(): if player and player.fly_vertical_axis < 0: player.fly_vertical_axis = 0.0)

	_update_fly_buttons_visibility()
	_reset_joystick()

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
	if not joystick_base:
		return false
	var base_rect = joystick_base.get_global_rect()
	# Generous hit area around joystick base (expanded by 35 pixels)
	var active_rect = base_rect.grow(35.0 * ui_scale)
	return active_rect.has_point(pos)

func _is_pos_inside_ui(pos: Vector2) -> bool:
	if _is_pos_inside_action_buttons(pos):
		return true

	# Control panel or tuning settings
	var ctrl_panel = get_tree().root.find_child("ControlPanel", true, false) as Control
	if ctrl_panel and ctrl_panel.visible and ctrl_panel.get_global_rect().has_point(pos):
		return true

	var toggle_btn = get_tree().root.find_child("ToggleControlsButton", true, false) as Control
	if toggle_btn and toggle_btn.get_global_rect().has_point(pos):
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
				var center_local = Vector2(joystick_radius * ui_scale, joystick_radius * ui_scale)
				joystick_center = joystick_base.global_position + center_local
			else:
				joystick_center = pos
			_update_joystick_knob(pos)
			# NOTE: Never triggers look rotation!

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
			var center_local = Vector2(joystick_radius * ui_scale, joystick_radius * ui_scale)
			joystick_center = joystick_base.global_position + center_local
		else:
			joystick_center = pos
		_update_joystick_knob(pos)
	else:
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

	if joystick_knob:
		joystick_knob.position = Vector2(joystick_radius, joystick_radius) + (offset / ui_scale) - joystick_knob.size * 0.5

	var input_vec = offset / max(active_radius, 1.0)
	# Joystick only sets movement axis - NO rotation is performed!
	player.input_axis = Vector2(input_vec.x, input_vec.y)

func _reset_joystick() -> void:
	joystick_touch_id = -1
	is_mouse_joystick = false
	joystick_active = false
	if player:
		player.input_axis = Vector2.ZERO
	if joystick_base:
		var vp_h = get_viewport_rect().size.y / ui_scale
		joystick_base.position = Vector2(60, vp_h - 180)
		if joystick_knob:
			joystick_knob.position = Vector2(joystick_radius, joystick_radius) - joystick_knob.size * 0.5

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

func _on_wobble_pressed() -> void:
	if player:
		player.wobble_impulse(25.0)

func _update_fly_buttons_visibility() -> void:
	var flying = player.is_flying if player else false
	if fly_up_btn:
		fly_up_btn.visible = flying
	if fly_down_btn:
		fly_down_btn.visible = flying
