@tool
class_name ClimateSystem
extends RefCounted

## Climate, Biome & Yearly Cycle System for O'Neill Cylinder Habitats
## Models seasonal solar declination, latitude temperature profiles,
## annual precipitation biomes (from Tundra desert to Tropical Rainforest),
## and generates probabilistic weather condition profiles and states.

const SolarCycleSimulator = preload("res://scripts/solar_cycle_simulator.gd")

# Climate region descriptors
const CLIMATE_TUNDRA_DESERT = "Polar Desert (Ice Sheet)"
const CLIMATE_POLAR_TUNDRA = "Polar Tundra"
const CLIMATE_ARCTIC_TUNDRA = "Arctic Tundra Desert"
const CLIMATE_BOREAL_TUNDRA = "Boreal Tundra"
const CLIMATE_BOREAL_TAIGA = "Boreal Taiga (Subpolar Forest)"
const CLIMATE_SUBPOLAR_MARITIME = "Subpolar Maritime Forest"
const CLIMATE_COLD_DESERT = "Cold Desert / Arid Steppe"
const CLIMATE_TEMPERATE_STEPPE = "Temperate Steppe (Grassland)"
const CLIMATE_TEMPERATE_MIXED = "Temperate Mixed Forest"
const CLIMATE_HUMID_CONTINENTAL = "Humid Continental Forest"
const CLIMATE_TEMPERATE_RAINFOREST = "Temperate Rainforest"
const CLIMATE_SUBTROPICAL_DESERT = "Subtropical Arid Desert"
const CLIMATE_MEDITERRANEAN = "Mediterranean / Chaparral Scrub"
const CLIMATE_HUMID_SUBTROPICAL = "Humid Subtropical Woodland"
const CLIMATE_DECIDUOUS_FOREST = "Temperate Deciduous Forest"
const CLIMATE_SUBTROPICAL_RAINFOREST = "Subtropical Rainforest"
const CLIMATE_TROPICAL_DESERT = "Hyper-Arid Tropical Desert"
const CLIMATE_TROPICAL_SAVANNA = "Semi-Arid Tropical Savanna"
const CLIMATE_TROPICAL_DRY_FOREST = "Tropical Dry Woodland"
const CLIMATE_TROPICAL_MONSOON = "Tropical Monsoon & Seasonal Forest"
const CLIMATE_TROPICAL_RAINFOREST = "Tropical Rainforest"

# Classify climate name based on Earth latitude (-90 to +90) and yearly precipitation (mm)
static func get_climate_name(lat_deg: float, yearly_precip_mm: float) -> String:
	var abs_lat = absf(clampf(lat_deg, -90.0, 90.0))
	var precip = maxf(yearly_precip_mm, 0.0)

	if abs_lat >= 75.0:
		if precip < 250.0:
			return CLIMATE_TUNDRA_DESERT
		else:
			return CLIMATE_POLAR_TUNDRA

	elif abs_lat >= 60.0:
		if precip < 250.0:
			return CLIMATE_ARCTIC_TUNDRA
		elif precip < 550.0:
			return CLIMATE_BOREAL_TUNDRA
		elif precip < 1100.0:
			return CLIMATE_BOREAL_TAIGA
		else:
			return CLIMATE_SUBPOLAR_MARITIME

	elif abs_lat >= 45.0:
		if precip < 250.0:
			return CLIMATE_COLD_DESERT
		elif precip < 550.0:
			return CLIMATE_TEMPERATE_STEPPE
		elif precip < 1050.0:
			return CLIMATE_TEMPERATE_MIXED
		elif precip < 1900.0:
			return CLIMATE_HUMID_CONTINENTAL
		else:
			return CLIMATE_TEMPERATE_RAINFOREST

	elif abs_lat >= 25.0:
		if precip < 200.0:
			return CLIMATE_SUBTROPICAL_DESERT
		elif precip < 500.0:
			return CLIMATE_MEDITERRANEAN
		elif precip < 1000.0:
			return CLIMATE_HUMID_SUBTROPICAL
		elif precip < 1800.0:
			return CLIMATE_DECIDUOUS_FOREST
		else:
			return CLIMATE_SUBTROPICAL_RAINFOREST

	else:
		if precip < 200.0:
			return CLIMATE_TROPICAL_DESERT
		elif precip < 550.0:
			return CLIMATE_TROPICAL_SAVANNA
		elif precip < 1100.0:
			return CLIMATE_TROPICAL_DRY_FOREST
		elif precip < 2200.0:
			return CLIMATE_TROPICAL_MONSOON
		else:
			return CLIMATE_TROPICAL_RAINFOREST

# Get current season name based on hemisphere and day of year
static func get_season_name(lat_deg: float, day_of_year: int) -> String:
	var doy = clampi(day_of_year, 1, 366)
	var abs_lat = absf(lat_deg)

	# Near-equatorial tropical seasonal classification
	if abs_lat < 12.0:
		var decl = SolarCycleSimulator.calculate_solar_declination(doy)
		if absf(decl) < 0.12:
			return "Equinoctial Wet Season"
		elif decl > 0.0:
			return "Northern Solstice Monsoons"
		else:
			return "Southern Solstice Monsoons"

	# Standard 4 seasons
	var is_north = lat_deg >= 0.0
	if doy >= 80 and doy < 172:
		return "Spring" if is_north else "Autumn"
	elif doy >= 172 and doy < 264:
		return "Summer" if is_north else "Winter"
	elif doy >= 264 and doy < 355:
		return "Autumn" if is_north else "Spring"
	else:
		return "Winter" if is_north else "Summer"

# Compute ambient surface temperature in °C based on latitude, time of year, time of day, and precipitation
static func calculate_surface_temperature(lat_deg: float, day_of_year: int, time_hours: float, yearly_precip_mm: float) -> float:
	var lat_rad = deg_to_rad(clampf(lat_deg, -90.0, 90.0))
	var abs_lat = absf(lat_deg)
	var doy = clampi(day_of_year, 1, 366)

	# 1. Base annual mean temperature by latitude:
	# Equator (0°): ~29°C, 30°: ~21°C, 45°: ~11°C, 60°: ~0°C, 90°: ~-26°C
	var cos_lat = cos(lat_rad)
	var base_temp = 30.0 * pow(cos_lat, 1.25) - 27.0 * pow(abs_lat / 90.0, 1.4)

	# 2. Seasonal cycle swing from solar declination
	var decl = SolarCycleSimulator.calculate_solar_declination(doy)
	# Max declination is ~23.44° = 0.409 rad
	var decl_norm = decl / 0.409
	var seasonal_amp = 22.0 * pow(abs_lat / 90.0, 1.05)
	var hem_sign = 1.0 if lat_deg >= 0.0 else -1.0
	var seasonal_delta = hem_sign * decl_norm * seasonal_amp

	# 3. Diurnal (Day/Night) temperature cycle
	# Peak heating at 14:00, coldest at 05:00
	var hour_norm = fposmod(time_hours, 24.0)
	var diurnal_phase = ((hour_norm - 14.0) / 24.0) * TAU
	# Arid climates have larger day/night swing (14°C); humid rainforests have narrower swing (4°C)
	var precip_norm = clampf(yearly_precip_mm / 2500.0, 0.0, 1.0)
	var diurnal_amp = lerpf(13.0, 4.0, precip_norm) * sqrt(cos_lat)
	var diurnal_delta = cos(diurnal_phase) * (diurnal_amp * 0.5)

	# 4. Evaporative cooling factor in high precipitation zones
	var evaporative_cooling = lerpf(0.0, -1.8, precip_norm)

	var final_temp = base_temp + seasonal_delta + diurnal_delta + evaporative_cooling
	return final_temp

# Generate comprehensive climate weather profile
static func get_climate_weather_profile(lat_deg: float, yearly_precip_mm: float, day_of_year: int, time_hours: float) -> Dictionary:
	var temp_c = calculate_surface_temperature(lat_deg, day_of_year, time_hours, yearly_precip_mm)
	var climate_name = get_climate_name(lat_deg, yearly_precip_mm)
	var season_name = get_season_name(lat_deg, day_of_year)
	var is_snow = temp_c <= 4.0

	var precip_norm = clampf(yearly_precip_mm / 3000.0, 0.0, 1.5)
	var abs_lat = absf(lat_deg)

	# Seasonal rain probability modifier
	var seasonal_rain_boost = 1.0
	if season_name.contains("Wet") or season_name.contains("Monsoon"):
		seasonal_rain_boost = 1.45
	elif season_name.contains("Summer") and abs_lat < 40.0:
		seasonal_rain_boost = 1.25
	elif season_name.contains("Winter"):
		seasonal_rain_boost = 0.85

	var rain_prob = clampf((0.08 + 0.55 * precip_norm) * seasonal_rain_boost, 0.02, 0.90)
	var mean_clouds = clampf(0.12 + 0.60 * precip_norm, 0.05, 0.95)
	var mean_humidity = clampf(3.0 + 18.0 * precip_norm, 2.5, 28.0)
	var mean_dust = clampf(0.65 * (1.0 - clampf(precip_norm, 0.0, 1.0)), 0.04, 0.80)

	var max_precip_rate = clampf(lerpf(6.0, 48.0, precip_norm), 4.0, 50.0)

	return {
		"climate_name": climate_name,
		"season_name": season_name,
		"temperature_c": temp_c,
		"is_snow_mode": is_snow,
		"latitude_deg": lat_deg,
		"yearly_precip_mm": yearly_precip_mm,
		"day_of_year": day_of_year,
		"time_of_day_hours": time_hours,
		"rain_probability": rain_prob,
		"mean_cloud_coverage": mean_clouds,
		"mean_humidity_gm3": mean_humidity,
		"mean_dust_density": mean_dust,
		"max_precip_rate_mmh": max_precip_rate
	}

# Sample next weather state based on the climate descriptor and profile
static func generate_weather_state(profile: Dictionary, rng: RandomNumberGenerator = null) -> Dictionary:
	if not rng:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var is_snow = bool(profile.get("is_snow_mode", false))
	var temp_c = float(profile.get("temperature_c", 20.0))
	var rain_prob = float(profile.get("rain_probability", 0.3))
	var mean_clouds = float(profile.get("mean_cloud_coverage", 0.5))
	var mean_humidity = float(profile.get("mean_humidity_gm3", 14.0))
	var mean_dust = float(profile.get("mean_dust_density", 0.15))
	var max_precip = float(profile.get("max_precip_rate_mmh", 25.0))
	var climate_name = String(profile.get("climate_name", "Temperate Mixed Forest"))

	var roll = rng.randf()
	var state_name = ""
	var cloud_cov = 0.0
	var cloud_thick = 200.0
	var precip_rate = 0.0
	var humidity = mean_humidity
	var dust = mean_dust
	var duration = rng.randf_range(28.0, 50.0)

	if roll < (1.0 - rain_prob) * 0.45:
		# 1. Clear Sky
		cloud_cov = rng.randf_range(0.02, 0.18)
		cloud_thick = rng.randf_range(60.0, 140.0)
		precip_rate = 0.0
		humidity = maxf(mean_humidity * 0.75, 2.5)
		dust = mean_dust * 1.15
		state_name = "Crisp Subpolar Clear" if is_snow else "Clear Solar Sky"

	elif roll < (1.0 - rain_prob):
		# 2. Fair / Scattered Cumulus Deck
		cloud_cov = clampf(mean_clouds + rng.randf_range(-0.15, 0.15), 0.25, 0.60)
		cloud_thick = rng.randf_range(160.0, 320.0)
		precip_rate = 0.0
		humidity = mean_humidity
		dust = mean_dust * 0.85
		state_name = "Scattered Flurries Deck" if is_snow else "Fair Cumulus Skies"

	elif roll < (1.0 - rain_prob * 0.40):
		# 3. Light Precipitation (Mist / Light Rain or Flurries)
		cloud_cov = clampf(mean_clouds + rng.randf_range(0.15, 0.30), 0.65, 0.90)
		cloud_thick = rng.randf_range(300.0, 520.0)
		precip_rate = rng.randf_range(2.0, maxf(max_precip * 0.35, 4.0))
		humidity = mean_humidity * 1.25
		dust = mean_dust * 0.40
		state_name = "Gentle Snowfall & Flurries" if is_snow else "Light Rain & Atmospheric Mist"

	elif roll < (1.0 - rain_prob * 0.12):
		# 4. Moderate Precipitation
		cloud_cov = clampf(mean_clouds + rng.randf_range(0.25, 0.40), 0.82, 0.96)
		cloud_thick = rng.randf_range(450.0, 680.0)
		precip_rate = rng.randf_range(maxf(max_precip * 0.35, 6.0), maxf(max_precip * 0.75, 14.0))
		humidity = mean_humidity * 1.45
		dust = mean_dust * 0.20
		state_name = "Moderate Snow & Drifts" if is_snow else "Moderate Precipitation Deck"

	else:
		# 5. Heavy Storm / Blizzard / Downpour
		cloud_cov = rng.randf_range(0.94, 1.0)
		cloud_thick = rng.randf_range(600.0, 800.0)
		precip_rate = rng.randf_range(maxf(max_precip * 0.75, 16.0), max_precip)
		humidity = mean_humidity * 1.65
		dust = 0.04
		state_name = "Frigid Arctic Blizzard" if is_snow else "Heavy Atmospheric Downpour"

	# Heating circuit offsets adjusted by climate
	var endcap_temp = temp_c + rng.randf_range(-1.0, 1.5)
	var water_temp = temp_c + rng.randf_range(0.5, 2.5)

	return {
		"name": "%s: %s" % [climate_name, state_name],
		"short_name": state_name,
		"climate_name": climate_name,
		"is_snow": is_snow,
		"temperature_c": temp_c,
		"cloud_coverage": clampf(cloud_cov, 0.0, 1.0),
		"cloud_thickness_m": clampf(cloud_thick, 50.0, 800.0),
		"precipitation_rate_mmh": clampf(precip_rate, 0.0, 50.0),
		"humidity_density_gm3": clampf(humidity, 2.0, 30.0),
		"dust_density": clampf(dust, 0.0, 1.0),
		"endcap_air_temperature_c": endcap_temp,
		"water_pipe_temperature_c": water_temp,
		"duration": duration
	}
