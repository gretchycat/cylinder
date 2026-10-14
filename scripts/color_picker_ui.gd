class_name ColorPickerUI
extends RefCounted

const UIScale = preload("res://scripts/ui_scale_manager.gd")

static func configure(picker: ColorPickerButton) -> void:
	picker.picker_created.connect(func(): _configure_created_picker(picker), CONNECT_ONE_SHOT)

static func _configure_created_picker(picker: ColorPickerButton) -> void:
	var scale_info: Dictionary = UIScale.calculate_intelligent_scale()
	var dpi_scale := maxf(float(scale_info.get("scale", 1.0)), 1.0)
	var screen_size := DisplayServer.screen_get_size()
	var popup_size := Vector2i(roundi(360.0 * dpi_scale), roundi(440.0 * dpi_scale))
	if screen_size.x > 0 and screen_size.y > 0:
		popup_size.x = mini(popup_size.x, maxi(screen_size.x - 32, 1))
		popup_size.y = mini(popup_size.y, maxi(screen_size.y - 48, 1))
	var popup := picker.get_popup()
	popup.min_size = popup_size
	popup.size = popup_size
	var color_picker := picker.get_picker()
	var picker_size := Vector2(popup_size) - Vector2(20.0, 64.0) * dpi_scale
	color_picker.custom_minimum_size = picker_size
	color_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_picker.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# ColorPicker's internal labels and slider geometry otherwise retain the
	# engine theme's unscaled dimensions even when the popup has been enlarged.
	color_picker.add_theme_font_size_override("font_size", roundi(16.0 * dpi_scale))
	color_picker.add_theme_constant_override("h_width", roundi(30.0 * dpi_scale))
	color_picker.add_theme_constant_override("label_width", roundi(10.0 * dpi_scale))
	color_picker.add_theme_constant_override("margin", roundi(4.0 * dpi_scale))
	color_picker.add_theme_constant_override("separation", roundi(4.0 * dpi_scale))

	# The popup can grow independently of ColorPicker's saturation/value field,
	# whose theme defaults are fixed pixel dimensions. Scale that field with the
	# popup and leave a proportionate amount of room for the now-scaled hue,
	# alpha, text, and preset controls below it.
	var scaled_field_size := 256.0 * dpi_scale
	var field_width := mini(scaled_field_size, picker_size.x - 48.0 * dpi_scale)
	var field_height := mini(scaled_field_size, picker_size.y - 120.0 * dpi_scale)
	color_picker.add_theme_constant_override("sv_width", maxi(roundi(field_width), 1))
	color_picker.add_theme_constant_override("sv_height", maxi(roundi(field_height), 1))
	_scale_picker_controls(color_picker, dpi_scale)

static func _scale_picker_controls(node: Node, dpi_scale: float) -> void:
	# Godot builds ColorPicker's mode tabs, sliders, and numeric editors as
	# internal child nodes, which get_children() omits unless requested.
	for child in node.get_children(true):
		if child is Control:
			var control := child as Control
			control.add_theme_font_size_override("font_size", roundi(16.0 * dpi_scale))
			var minimum := control.custom_minimum_size
			if child is HSlider:
				minimum.y = maxf(minimum.y, 24.0 * dpi_scale)
			elif child is VSlider:
				minimum.x = maxf(minimum.x, 24.0 * dpi_scale)
			elif child is SpinBox or child is LineEdit:
				minimum.y = maxf(minimum.y, 32.0 * dpi_scale)
			elif child is Button:
				minimum = minimum.max(Vector2(36.0, 36.0) * dpi_scale)
			control.custom_minimum_size = minimum
		_scale_picker_controls(child, dpi_scale)
