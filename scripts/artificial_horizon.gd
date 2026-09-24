@tool
class_name ArtificialHorizon
extends Control

@export var roll_deg: float = 0.0:
	set(val):
		roll_deg = val
		queue_redraw()

@export var pitch_deg: float = 0.0:
	set(val):
		pitch_deg = val
		queue_redraw()

@export var gravity_ratio: float = 1.0:
	set(val):
		gravity_ratio = clampf(val, 0.0, 1.0)
		queue_redraw()

@export var correction_rate: float = 16.0:
	set(val):
		correction_rate = val
		queue_redraw()

@export var locomotion_state: String = "IDLE":
	set(val):
		locomotion_state = val
		queue_redraw()

func _draw() -> void:
	var center = size * 0.5
	var radius = minf(size.x, size.y) * 0.42

	# Background circular dial
	draw_circle(center, radius, Color(0.04, 0.06, 0.09, 0.75))
	draw_arc(center, radius, 0.0, TAU, 64, Color(0.25, 0.45, 0.65, 0.8), 2.0, true)

	# Calculate pitch offset in pixels
	var pitch_pixel_scale = radius * 0.02
	var pitch_offset = clampf(pitch_deg * pitch_pixel_scale, -radius * 0.7, radius * 0.7)

	# Roll rotation (wobble roll)
	var roll_rad = deg_to_rad(roll_deg)
	var cos_r = cos(roll_rad)
	var sin_r = sin(roll_rad)

	# Horizon Line (Perpendicular reference to gravity axis)
	# Normal vector of horizon line:
	var horiz_dir = Vector2(cos_r, sin_r)
	var horiz_normal = Vector2(-sin_r, cos_r)

	var line_center = center + horiz_normal * pitch_offset
	var half_line_len = radius * 0.85
	var p1 = line_center - horiz_dir * half_line_len
	var p2 = line_center + horiz_dir * half_line_len

	# Horizon bar color:
	# Cyan when aligned/perpendicular, Gold/Amber when wobbling
	var is_aligned = absf(roll_deg) < 1.0
	var horiz_color = Color(0.2, 0.9, 1.0, 0.9) if is_aligned else Color(1.0, 0.75, 0.2, 0.95)

	# Draw horizon bar
	draw_line(p1, p2, horiz_color, 3.0, true)

	# Pitch ladder tick marks on horizon
	for deg in [-20, -10, 10, 20]:
		var tick_offset = line_center + horiz_normal * (float(deg) * pitch_pixel_scale)
		var tick_half_w = radius * 0.18
		if (tick_offset - center).length() < radius * 0.8:
			var t1 = tick_offset - horiz_dir * tick_half_w
			var t2 = tick_offset + horiz_dir * tick_half_w
			draw_line(t1, t2, Color(0.7, 0.8, 0.9, 0.4), 1.5, true)

	# Center aircraft / observer symbol (fixed in center)
	var reticle_w = radius * 0.28
	var wing_h = 3.0
	# Left wing
	draw_line(center - Vector2(reticle_w, 0), center - Vector2(8, 0), Color(1.0, 0.9, 0.2, 0.95), wing_h, true)
	# Right wing
	draw_line(center + Vector2(8, 0), center + Vector2(reticle_w, 0), Color(1.0, 0.9, 0.2, 0.95), wing_h, true)
	# Center pip
	draw_circle(center, 3.0, Color(1.0, 0.9, 0.2, 0.95))

	# Top and Bottom 0-degree roll index markers
	var top_marker = center - Vector2(0, radius - 4)
	draw_line(top_marker, top_marker + Vector2(0, 8), Color(1, 1, 1, 0.8), 2.0, true)

	# Roll indicator needle on dial perimeter
	var roll_marker_pos = center - Vector2(sin_r, cos_r) * (radius - 5.0)
	draw_circle(roll_marker_pos, 4.0, horiz_color)

	# Gravity Restoring Force Arc (shows stiffness scaling with gravity)
	# Draw arc on bottom showing restoring torque capacity
	var arc_radius = radius * 0.92
	var max_arc_sweep = PI * 0.6
	var arc_sweep = max_arc_sweep * gravity_ratio
	var arc_start = PI * 0.5 - arc_sweep * 0.5
	var arc_col = Color(0.2, 1.0, 0.4, 0.8).lerp(Color(0.2, 0.6, 1.0, 0.8), gravity_ratio)
	draw_arc(center, arc_radius, arc_start, arc_start + arc_sweep, 24, arc_col, 3.0, true)
