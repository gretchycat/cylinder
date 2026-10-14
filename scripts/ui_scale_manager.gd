class_name UIScaleManager
extends RefCounted

const SETTINGS_PATH: String = "user://ui_settings.cfg"

static func calculate_intelligent_scale(custom_dpi: float = -1.0, custom_size: Vector2 = Vector2.ZERO, force_mobile: bool = false) -> Dictionary:
	var has_mobile_feature = OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios") or force_mobile

	var reported_dpi = custom_dpi if custom_dpi > 0 else float(DisplayServer.screen_get_dpi())
	var screen_size = custom_size if custom_size.length_squared() > 0 else Vector2(DisplayServer.screen_get_size())

	var fallback_dpi = 420.0 if has_mobile_feature else 96.0
	var dpi = reported_dpi
	var dpi_valid = is_finite(dpi) and dpi > 0.0
	var has_resolution = screen_size.x > 0.0 and screen_size.y > 0.0
	var fallback_reason := ""
	var reported_diagonal_inches: float = screen_size.length() / reported_dpi if has_resolution and is_finite(reported_dpi) and reported_dpi > 0.0 else 0.0
	if not dpi_valid:
		fallback_reason = "DPI missing or non-positive"
	elif has_mobile_feature and (dpi < 100.0 or dpi > 1000.0):
		dpi_valid = false
		fallback_reason = "reported DPI is outside the plausible mobile panel-density range"
	elif has_mobile_feature and has_resolution:
		# Cross-check Android/iOS DPI against physical pixel resolution. A
		# 1080x2400 phone reporting 72 DPI implies a 36-inch diagonal, so the
		# operating-system DPI is clearly not the panel density in that case.
		if reported_diagonal_inches < 3.0 or reported_diagonal_inches > 16.0:
			dpi_valid = false
			fallback_reason = "reported DPI implies an implausible mobile screen diagonal (%.1f in)" % reported_diagonal_inches
	if not dpi_valid:
		dpi = fallback_dpi

	var diag_inches: float = screen_size.length() / dpi if has_resolution else 0.0

	var is_phone = diag_inches > 0.0 and diag_inches < 7.2
	var is_tablet = diag_inches >= 7.2 and diag_inches < 12.0

	var scale_factor: float = 1.0
	var device_type: String = "Desktop"

	if has_mobile_feature:
		device_type = "Android Phone" if is_phone else ("Android Tablet" if is_tablet else "Mobile")
		# DPI is the scaling input on mobile. Resolution is used only to reject
		# obviously inconsistent OS readings, never to derive a separate scale.
		scale_factor = clampf(dpi / 160.0, 1.0, 3.5)
	elif is_phone:
		device_type = "Phone"
		var density = dpi / 160.0
		scale_factor = clampf(density, 2.25, 3.25)
	elif is_tablet:
		device_type = "Tablet"
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
	var description = "%s (%.1f\", %.1f DPI%s)" % [device_type, diag_inches, dpi, ", fallback" if not dpi_valid else ""]

	return {
		"scale": scale_factor,
		"device_type": device_type,
		"mobile_platform": has_mobile_feature,
		"dpi": dpi,
		"reported_dpi": reported_dpi,
		"dpi_valid": dpi_valid,
		"fallback_reason": fallback_reason,
		"screen_size": screen_size,
		"reported_diagonal_inches": reported_diagonal_inches,
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
