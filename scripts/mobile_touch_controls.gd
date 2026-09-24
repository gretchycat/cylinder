class_name MobileTouchControls
extends Control

@export var player: PlayerController
@export var joystick_radius: float = 70.0
@export var touch_look_sensitivity: float = 0.0035

# Virtual joystick state
var joystick_touch_id: int = -1
var joystick_center: Vector2 = Vector2.ZERO
var joystick_knob_pos: Vector2 = Vector2.ZERO
var joystick_active: bool = false

# Touch look state
var look_touch_id: int = -1
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

	if event is InputEventScreenTouch:
		if event.pressed:
			_handle_touch_start(event.index, event.position)
		else:
			_handle_touch_end(event.index)

	elif event is InputEventScreenDrag:
		_handle_touch_drag(event.index, event.position, event.relative)

func _handle_touch_start(id: int, pos: Vector2) -> void:
	var screen_width = get_viewport_rect().size.x

	# Left side of screen: Virtual Joystick
	if pos.x < screen_width * 0.45 and joystick_touch_id == -1:
		joystick_touch_id = id
		joystick_active = true
		joystick_center = pos
		joystick_knob_pos = pos
		if joystick_base:
			joystick_base.global_position = pos - Vector2(joystick_radius, joystick_radius)
			joystick_base.visible = true
			if joystick_knob:
				joystick_knob.position = Vector2(joystick_radius, joystick_radius) - joystick_knob.size * 0.5

	# Right side of screen: Camera Look
	elif pos.x >= screen_width * 0.45 and look_touch_id == -1:
		# Check if clicking on action buttons
		if not _is_pos_inside_action_buttons(pos):
			look_touch_id = id
			last_look_pos = pos

func _handle_touch_drag(id: int, pos: Vector2, rel: Vector2) -> void:
	if id == joystick_touch_id and joystick_active:
		var offset = pos - joystick_center
		var dist = offset.length()
		if dist > joystick_radius:
			offset = offset.normalized() * joystick_radius
		joystick_knob_pos = joystick_center + offset

		if joystick_knob:
			joystick_knob.position = Vector2(joystick_radius, joystick_radius) + offset - joystick_knob.size * 0.5

		var input_vec = offset / joystick_radius
		player.input_axis = Vector2(input_vec.x, input_vec.y)

	elif id == look_touch_id:
		var look_delta = rel * touch_look_sensitivity
		player.apply_look_input(look_delta)

func _handle_touch_end(id: int) -> void:
	if id == joystick_touch_id:
		_reset_joystick()
	elif id == look_touch_id:
		look_touch_id = -1

func _reset_joystick() -> void:
	joystick_touch_id = -1
	joystick_active = false
	if player:
		player.input_axis = Vector2.ZERO
	if joystick_base:
		joystick_base.position = Vector2(80, get_viewport_rect().size.y - 180)
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
