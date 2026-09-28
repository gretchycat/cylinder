@tool
class_name SolarCycleSimulator
extends RefCounted

## Astronomical Solar Cycle Simulator for Earth Latitudes
## Accurately models solar declination, hour angle, solar elevation,
## daylight spectrum, golden hour, civil/nautical/astronomical twilight,
## and night starlight across Earth latitudes and time of day.

const DEG_PER_HOUR: float = 15.0

# Calculate Day of Year (1 to 365/366) from calendar date
static func get_day_of_year(year: int, month: int, day: int) -> int:
	var days_in_months = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0):
		days_in_months[1] = 29
	var doy = 0
	for m in range(clampi(month - 1, 0, 11)):
		doy += days_in_months[m]
	doy += day
	return clampi(doy, 1, 366)

# Solar Declination in radians (Spencer 1971 / NOAA solar calculation)
static func calculate_solar_declination(day_of_year: int) -> float:
	var gamma = 2.0 * PI * float(day_of_year - 1) / 365.0
	var decl = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma) \
		- 0.006758 * cos(2.0 * gamma) + 0.000907 * sin(2.0 * gamma) \
		- 0.002697 * cos(3.0 * gamma) + 0.00148 * sin(3.0 * gamma)
	return decl

# Solar Hour Angle H in radians (-PI at midnight, 0 at solar noon, +PI at midnight)
static func calculate_hour_angle(time_hours: float) -> float:
	var h_deg = (fposmod(time_hours, 24.0) - 12.0) * DEG_PER_HOUR
	return deg_to_rad(h_deg)

# Solar Elevation angle alpha in degrees (-90.0° nadir to +90.0° zenith)
# sin(alpha) = sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(H)
static func calculate_solar_elevation(lat_deg: float, day_of_year: int, time_hours: float) -> float:
	var lat_rad = deg_to_rad(clampf(lat_deg, -90.0, 90.0))
	var decl_rad = calculate_solar_declination(day_of_year)
	var h_rad = calculate_hour_angle(time_hours)

	var sin_alpha = sin(lat_rad) * sin(decl_rad) + cos(lat_rad) * cos(decl_rad) * cos(h_rad)
	sin_alpha = clampf(sin_alpha, -1.0, 1.0)
	var alpha_rad = asin(sin_alpha)
	return rad_to_deg(alpha_rad)

# Solar Azimuth angle in degrees from North (0°=N, 90°=E, 180°=S, 270°=W)
static func calculate_solar_azimuth(lat_deg: float, day_of_year: int, time_hours: float) -> float:
	var lat_rad = deg_to_rad(clampf(lat_deg, -90.0, 90.0))
	var decl_rad = calculate_solar_declination(day_of_year)
	var h_rad = calculate_hour_angle(time_hours)
	var elev_deg = calculate_solar_elevation(lat_deg, day_of_year, time_hours)
	var elev_rad = deg_to_rad(elev_deg)

	var cos_elev = cos(elev_rad)
	if absf(cos_elev) < 1e-4:
		return 180.0 if lat_deg >= 0.0 else 0.0

	var cos_az = (sin(decl_rad) * cos(lat_rad) - cos(decl_rad) * sin(lat_rad) * cos(h_rad)) / cos_elev
	cos_az = clampf(cos_az, -1.0, 1.0)
	var az = rad_to_deg(acos(cos_az))
	if sin(h_rad) > 0.0:
		az = 360.0 - az
	return az

# Smooth Hermite interpolation helper
static func smooth_step(edge0: float, edge1: float, x: float) -> float:
	var t = clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

# Map solar elevation angle to atmospheric light output and spectrum
static func get_solar_lighting_at_elevation(elevation_deg: float, is_morning: bool = true) -> Dictionary:
	var sun_col: Color
	var intensity: float
	var fog_col: Color
	var phase: String

	if elevation_deg >= 25.0:
		# High Sun / Full Daylight (5800K white daylight)
		sun_col = Color(1.0, 0.98, 0.95)
		intensity = 3.5
		fog_col = Color(0.52, 0.72, 0.88, 1.0)
		phase = "Daylight (High Sun)"

	elif elevation_deg >= 10.0:
		# Midday to Afternoon/Morning Sun (Warm daylight white)
		var t = smooth_step(10.0, 25.0, elevation_deg)
		var col_low = Color(1.0, 0.88, 0.65) if is_morning else Color(1.0, 0.85, 0.62)
		var col_high = Color(1.0, 0.98, 0.95)
		sun_col = col_low.lerp(col_high, t)
		intensity = lerpf(2.6, 3.5, t)

		var fog_low = Color(0.60, 0.74, 0.88, 1.0)
		var fog_high = Color(0.52, 0.72, 0.88, 1.0)
		fog_col = fog_low.lerp(fog_high, t)
		phase = "Daylight (Morning Sun)" if is_morning else "Daylight (Afternoon Sun)"

	elif elevation_deg >= 0.0:
		# Golden Hour (Low sun traversing high Earth airmass)
		var t = smooth_step(0.0, 10.0, elevation_deg)
		var horizon_sun = Color(1.0, 0.52, 0.18) if is_morning else Color(1.0, 0.46, 0.15)
		var gold_sun = Color(1.0, 0.88, 0.65) if is_morning else Color(1.0, 0.85, 0.62)
		sun_col = horizon_sun.lerp(gold_sun, t)
		intensity = lerpf(1.2, 2.6, t)

		var fog_horizon = Color(0.85, 0.55, 0.40, 1.0) if is_morning else Color(0.88, 0.50, 0.35, 1.0)
		var fog_gold = Color(0.60, 0.74, 0.88, 1.0)
		fog_col = fog_horizon.lerp(fog_gold, t)
		phase = "Sunrise (Golden Hour)" if is_morning else "Sunset (Golden Hour)"

	elif elevation_deg >= -6.0:
		# Civil Twilight (Belt of Venus / sunset rose transitioning to twilight purple)
		var t = smooth_step(-6.0, 0.0, elevation_deg)
		var twilight_deep = Color(0.40, 0.35, 0.68) if is_morning else Color(0.65, 0.30, 0.65)
		var horizon_sun = Color(1.0, 0.52, 0.18) if is_morning else Color(1.0, 0.46, 0.15)
		sun_col = twilight_deep.lerp(horizon_sun, t)
		intensity = lerpf(0.15, 1.2, t)

		var fog_twilight = Color(0.28, 0.22, 0.50, 1.0)
		var fog_horizon = Color(0.85, 0.55, 0.40, 1.0) if is_morning else Color(0.88, 0.50, 0.35, 1.0)
		fog_col = fog_twilight.lerp(fog_horizon, t)
		phase = "Civil Twilight (Dawn)" if is_morning else "Civil Twilight (Dusk)"

	elif elevation_deg >= -8.0:
		# Nautical Twilight down to night threshold
		var t = smooth_step(-8.0, -6.0, elevation_deg)
		var night_dark = Color(0.16, 0.20, 0.32)
		var twilight_deep = Color(0.40, 0.35, 0.68) if is_morning else Color(0.65, 0.30, 0.65)
		sun_col = night_dark.lerp(twilight_deep, t)
		intensity = lerpf(0.12, 0.20, t)

		var fog_night = Color(0.08, 0.10, 0.17, 1.0)
		var fog_twilight = Color(0.28, 0.22, 0.50, 1.0)
		fog_col = fog_night.lerp(fog_twilight, t)
		phase = "Nautical Twilight (Dawn)" if is_morning else "Nautical Twilight (Dusk)"

	else:
		# Midnight / Deepest Night floor: luminous nocturnal starlight illumination
		sun_col = Color(0.16, 0.20, 0.32)
		intensity = 0.12
		fog_col = Color(0.08, 0.10, 0.17, 1.0)
		phase = "Night (Midnight Starlight)"

	return {
		"sun_color": sun_col,
		"intensity": intensity,
		"fog_color": fog_col,
		"phase_name": phase,
		"elevation_deg": elevation_deg
	}

# Sample lighting directly from time of day, Earth latitude, and day of year
static func get_solar_lighting_at_time(lat_deg: float, day_of_year: int, time_hours: float) -> Dictionary:
	var elev = calculate_solar_elevation(lat_deg, day_of_year, time_hours)
	var h_mod = fposmod(time_hours, 24.0)
	var is_morning = h_mod < 12.0
	var props = get_solar_lighting_at_elevation(elev, is_morning)
	props["time_hours"] = h_mod
	props["azimuth_deg"] = calculate_solar_azimuth(lat_deg, day_of_year, time_hours)
	return props

# Generate the diurnal axial gradient along the 18 km cylinder
# Segment i samples a time offset around base_time_hours
static func get_cylinder_axial_gradient(
	lat_deg: float,
	day_of_year: int,
	base_time_hours: float,
	num_segments: int,
	span_hours: float = 1.5
) -> Dictionary:
	var seg_colors: Array[Color] = []
	var seg_intensities: Array[float] = []
	var sum_col = Color.BLACK
	var sum_intensity = 0.0

	var n = max(num_segments, 1)
	for i in range(n):
		var s = float(i) / max(float(n - 1), 1.0)
		# Time offset along Z axis: South (i=0) to North (i=n-1)
		var t_offset = (s - 0.5) * span_hours
		var seg_time = fposmod(base_time_hours + t_offset, 24.0)
		var props = get_solar_lighting_at_time(lat_deg, day_of_year, seg_time)
		var col = props["sun_color"] as Color
		var inten = props["intensity"] as float
		seg_colors.append(col)
		seg_intensities.append(inten)
		sum_col += col
		sum_intensity += inten

	var avg_col = sum_col / float(n)
	var avg_inten = sum_intensity / float(n)

	# Center properties for overall scene directional light and atmosphere
	var center_props = get_solar_lighting_at_time(lat_deg, day_of_year, base_time_hours)

	return {
		"segment_colors": seg_colors,
		"segment_intensities": seg_intensities,
		"avg_color": avg_col,
		"avg_intensity": avg_inten,
		"center_color": center_props["sun_color"],
		"center_intensity": center_props["intensity"],
		"center_fog_color": center_props["fog_color"],
		"solar_elevation": center_props["elevation_deg"],
		"solar_azimuth": center_props["azimuth_deg"],
		"phase_name": center_props["phase_name"]
	}
