class_name UIScaleManager
extends RefCounted

const SETTINGS_PATH: String = "user://ui_settings.cfg"

static func calculate_intelligent_scale(custom_dpi: float = -1.0, custom_size: Vector2 = Vector2.ZERO, force_mobile: bool = false) -> Dictionary:
	var has_mobile_feature = OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios") or force_mobile

	var dpi = custom_dpi if custom_dpi > 0 else float(DisplayServer.screen_get_dpi())
	var screen_size = custom_size if custom_size.length_squared() > 0 else Vector2(DisplayServer.screen_get_size())

	if dpi <= 0:
		dpi = 420.0 if has_mobile_feature else 96.0

	if screen_size.x <= 0 or screen_size.y <= 0:
		screen_size = Vector2(2400, 1080) if has_mobile_feature else Vector2(1920, 1080)

	var diag_pixels = screen_size.length()
	var diag_inches = diag_pixels / dpi

	var is_phone = (has_mobile_feature and diag_inches < 7.2) or diag_inches < 7.2
	var is_tablet = (has_mobile_feature and diag_inches >= 7.2 and diag_inches < 12.0) or (diag_inches >= 7.2 and diag_inches < 12.0 and dpi > 180.0)

	var scale_factor: float = 1.0
	var device_type: String = "Desktop"

	if is_phone:
		device_type = "Android Phone" if has_mobile_feature else "Phone"
		var density = dpi / 160.0
		# CanvasItem font sizes are pixel based. The old 0.65 factor made 10–12px
		# labels physically tiny on high-density Android displays.
		scale_factor = clampf(density, 2.25, 3.25)
	elif is_tablet:
		device_type = "Android Tablet" if has_mobile_feature else "Tablet"
		var density = dpi / 160.0
		scale_factor = clampf(density * 0.85, 1.9, 2.8)
	else:
		if dpi > 150.0 and not has_mobile_feature:
			device_type = "High-DPI Desktop"
			scale_factor = clampf((dpi / 96.0) * 0.85, 1.25, 1.75)
		else:
			device_type = "Desktop"
			scale_factor = 1.00

	scale_factor = snappedf(scale_factor, 0.05)
	var description = "%s (%.1f\", %d DPI)" % [device_type, diag_inches, int(dpi)]

	return {
		"scale": scale_factor,
		"device_type": device_type,
		"dpi": dpi,
		"diagonal_inches": diag_inches,
		"description": description
	}

static func save_user_scale(scale_val: float, is_auto: bool) -> void:
	var config = ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("ui", "scale", scale_val)
	config.set_value("ui", "is_auto", is_auto)
	config.save(SETTINGS_PATH)

static func load_user_scale() -> Dictionary:
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_PATH)
	if err == OK:
		var scale_val = config.get_value("ui", "scale", -1.0)
		var is_auto = config.get_value("ui", "is_auto", true)
		if scale_val > 0.4 and scale_val < 4.0:
			return {"has_saved": true, "scale": scale_val, "is_auto": is_auto}
	return {"has_saved": false, "scale": 1.0, "is_auto": true}
