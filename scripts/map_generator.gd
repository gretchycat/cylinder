class_name MapGenerator
extends RefCounted

const Config = preload("res://scripts/map_config.gd")
const Terrain = preload("res://scripts/terrain_manager.gd")

static func noise(seed_value: int, wavelength: float, settings: Dictionary) -> FastNoiseLite:
	var n = FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = 1.0 / wavelength
	n.fractal_octaves = int(settings.noise_octaves)
	n.fractal_gain = settings.noise_gain
	return n

static func field(n: FastNoiseLite, u: float, v: float, geometry: Dictionary) -> float:
	var angle = u * TAU
	return n.get_noise_3d(cos(angle) * geometry.cylinder_radius_m, sin(angle) * geometry.cylinder_radius_m, (v - 0.5) * geometry.cylinder_length_m)

static func progress(cb: Callable, fraction: float, message: String) -> void:
	if cb.is_valid():
		await cb.call(fraction, message)

static func generate(doc: Dictionary, cb: Callable = Callable()) -> Dictionary:
	var error = Config.validate(doc)
	if not error.is_empty():
		return {"error": error}
	var g: Dictionary = doc.geometry
	var p: Dictionary = doc.generation
	var w = int(p.elevation_width)
	var h = int(p.elevation_height)
	var tw = int(p.terrain_width)
	var th = int(p.terrain_height)
	if w * h > 2097152:
		return {"error": "Elevation generation is limited to 2,097,152 samples on this device. Reduce its width or height; the loaded map remains unchanged."}
	var active_biomes = 0
	for biome in doc.biomes.values():
		if biome.weight > 0:
			active_biomes += 1
	if tw * th * active_biomes > 8388608:
		return {"error": "Biome generation exceeds its mobile memory budget. Reduce terrain resolution or disable unused biomes; the loaded map remains unchanged."}
	var n = noise(int(p.seed), p.noise_wavelength_m, p)
	var detail = noise(int(p.seed) + 1, p.detail_wavelength_m, p)
	var coast = noise(int(p.seed) + 2, p.coast_wavelength_m, p)
	var heights = PackedFloat32Array()
	heights.resize(w * h)
	var histogram = PackedInt32Array()
	histogram.resize(4096)
	var rng = RandomNumberGenerator.new()
	rng.seed = int(p.seed)
	var lakes: Array[Vector2] = []
	for i in int(p.lake_count):
		lakes.append(Vector2(rng.randf(), rng.randf()))
	for y in h:
		if y % 16 == 0:
			await progress(cb, 0.05 + 0.25 * float(y) / h, "Building relief in physical metres")
		var v = float(y) / (h - 1)
		for x in w:
			var u = float(x) / w
			var broad = field(n, u, v, g)
			var fine = field(detail, u, v, g)
			var height = p.base_height_m + broad * p.relief_m + (1.0 - absf(broad)) * maxf(broad, 0) * p.ridge_height_m + fine * p.relief_m * p.detail_strength
			var sea_distance = absf((v - p.sea_center_v) * g.cylinder_length_m) - field(coast, u, v, g) * p.coast_variation_m
			if p.sea_width_m > 0:
				var basin = 1.0 - smoothstep(p.sea_width_m * 0.25, p.sea_width_m * 0.75, sea_distance)
				height = lerpf(height, g.water_sea_level_m - p.sea_depth_m, basin)
			for lake in lakes:
				var d = Vector2(wrapf(u - lake.x, -0.5, 0.5) * TAU * g.cylinder_radius_m, (v - lake.y) * g.cylinder_length_m).length()
				height = lerpf(height, g.water_sea_level_m - p.lake_depth_m, 1.0 - smoothstep(p.lake_radius_m * 0.3, p.lake_radius_m, d))
			# Channels converge into the axial sea. Their meander is periodic in U.
			for river in int(p.river_count):
				var river_u = float(river + 1) / (p.river_count + 1) + sin(v * TAU + river) * p.coast_variation_m / (TAU * g.cylinder_radius_m)
				var d = absf(wrapf(u - river_u, -0.5, 0.5)) * TAU * g.cylinder_radius_m
				var channel = 1.0 - smoothstep(0.0, p.river_width_m, d)
				height -= channel * p.river_depth_m
			height = clampf(height / g.elevation_variance_m, 0, 1)
			heights[y * w + x] = height
			histogram[mini(4095, int(height * 4095))] += 1
	await progress(cb, 0.31, "Reshaping elevation toward biome proportions")
	# Monotonic quantile transport preserves connected ridges and drainage lows
	# while matching the mixture of requested biome elevation intervals.
	var enabled: Array = []
	var total_weight = 0.0
	for key in doc.biomes:
		var b: Dictionary = doc.biomes[key]
		if b.weight > 0:
			enabled.append(key)
			total_weight += b.weight
	var lut = PackedFloat32Array()
	lut.resize(4096)
	var cumulative = 0
	for bin in 4096:
		var quantile = (cumulative + histogram[bin] * 0.5) / float(w * h)
		cumulative += histogram[bin]
		var low = 0.0
		var high: float = g.elevation_variance_m
		for iteration in 18:
			var mid = (low + high) * 0.5
			var cdf = 0.0
			for key in enabled:
				var b: Dictionary = doc.biomes[key]
				var bounds = elevation_bounds(b, g)
				cdf += b.weight / total_weight * clampf((mid - bounds.x) / maxf(bounds.y - bounds.x, 0.001), 0, 1)
			if cdf < quantile:
				low = mid
			else:
				high = mid
		lut[bin] = (low + high) * 0.5 / g.elevation_variance_m
	for i in heights.size():
		heights[i] = lut[mini(4095, int(heights[i] * 4095))]
	var dx: float = TAU * g.cylinder_radius_m / w
	var dz: float = g.cylinder_length_m / (h - 1)
	var talus = tan(deg_to_rad(p.talus_slope_deg)) / g.elevation_variance_m
	for iteration in int(p.erosion_iterations):
		await progress(cb, 0.33 + 0.12 * iteration / maxf(p.erosion_iterations, 1), "Relaxing steep terrain")
		var next = heights.duplicate()
		for y in h:
			for x in w:
				var i = y * w + x
				for j in [y * w + (x + 1) % w, mini(y + 1, h - 1) * w + x]:
					var distance = dx if j / w == y else dz
					var diff = heights[i] - heights[j]
					var transfer = signf(diff) * maxf(absf(diff) - talus * distance, 0) * 0.125
					next[i] -= transfer
					next[j] += transfer
		heights = next
	var elevation = Image.create_from_data(w, h, false, Image.FORMAT_RF, heights.to_byte_array())
	var terrain_bytes = PackedByteArray()
	terrain_bytes.resize(tw * th)
	var temperature = noise(int(p.seed) + 10, p.climate_wavelength_m, p)
	var moisture = noise(int(p.seed) + 11, p.climate_wavelength_m, p)
	var unsuitable = PackedByteArray()
	# One flat packed score buffer avoids a per-pixel Array allocation. The
	# previous Array[PackedFloat32Array] shape multiplied allocator overhead on
	# mobile and could exhaust memory before generation reached balancing.
	var score_stride = enabled.size()
	var scores = PackedFloat32Array()
	scores.resize(tw * th * score_stride)
	var region_fields: Array[FastNoiseLite] = []
	for key in enabled:
		region_fields.append(noise(int(p.seed) ^ str(key).hash(), p.biome_region_wavelength_m, p))
	var biases = PackedFloat32Array()
	biases.resize(enabled.size())
	# Cache suitability; each balancing pass then only compares scores.
	for y in th:
		if y % 16 == 0:
			await progress(cb, 0.46 + 0.12 * float(y) / th, "Fitting climate and biome regions")
		for x in tw:
			var u = float(x) / tw
			var v = float(y) / (th - 1)
			var e = Terrain.sample_image(elevation, u, v) * g.elevation_variance_m
			var slope = slope_at(elevation, u, v, g)
			var temp = field(temperature, u, v, g) * 0.5 + 0.5
			var moist = field(moisture, u, v, g) * 0.5 + 0.5
			var cell_offset = (y * tw + x) * score_stride
			var valid_options = 0
			for k in enabled.size():
				var key = enabled[k]
				var b: Dictionary = doc.biomes[key]
				var bounds = elevation_bounds(b, g)
				var outside = maxf(maxf(bounds.x - e, e - bounds.y), 0)
				var penalty = outside / g.elevation_variance_m * 20 + maxf(slope - b.max_slope_deg, 0) / 10
				if bool(b.submerged) != (e < g.water_sea_level_m):
					penalty += 1000
				var valid = outside <= 0.001 and slope <= b.max_slope_deg and bool(b.submerged) == (e < g.water_sea_level_m)
				if valid:
					valid_options += 1
				scores[cell_offset + k] = -pow(temp - b.temperature, 2) - pow(moist - b.moisture, 2) + field(region_fields[k], u, v, g) * p.biome_region_strength - penalty if valid else -10000.0 - penalty
			unsuitable.append(int(valid_options == 0))
	var counts = PackedInt32Array()
	var best_error = INF
	var best_ids = PackedByteArray()
	var best_counts = PackedInt32Array()
	for iteration in int(p.balance_iterations):
		await progress(cb, 0.59 + float(iteration) / p.balance_iterations * 0.18, "Balancing requested biome areas")
		counts.resize(enabled.size())
		counts.fill(0)
		for start in range(0, terrain_bytes.size(), 8192):
			await progress(cb, 0.59 + (float(iteration) + float(start) / terrain_bytes.size()) / p.balance_iterations * 0.18, "Balancing requested biome areas")
			var finish = mini(start + 8192, terrain_bytes.size())
			for i in range(start, finish):
				var offset = i * score_stride
				var best = 0
				for k in enabled.size():
					if scores[offset + k] + biases[k] > scores[offset + best] + biases[best]:
						best = k
				terrain_bytes[i] = int(doc.biomes[enabled[best]].raster_id)
				counts[best] += 1
		var error_sum = 0.0
		for k in enabled.size():
			var target: float = doc.biomes[enabled[k]].weight / total_weight
			var area_error: float = target - counts[k] / float(tw * th)
			error_sum += absf(area_error)
			biases[k] += area_error * 0.8 / sqrt(iteration + 1.0)
		if error_sum < best_error:
			best_error = error_sum
			best_ids = terrain_bytes.duplicate()
			best_counts = counts.duplicate()
		if error_sum < 0.02:
			break
	terrain_bytes = best_ids
	counts = best_counts
	var warnings: Array[String] = []
	var unsuitable_count = 0
	for value in unsuitable:
		unsuitable_count += value
	if unsuitable_count > 0:
		warnings.append("%.2f%% of cells have no selected biome satisfying all elevation/slope/water constraints; closest selected biome used. Broaden biome ranges or reduce relief." % (100.0 * unsuitable_count / (tw * th)))
	var report: Dictionary = {}
	for k in enabled.size():
		report[enabled[k]] = {"requested": doc.biomes[enabled[k]].weight / total_weight, "achieved": counts[k] / float(tw * th)}
	var terrain = Image.create_from_data(tw, th, false, Image.FORMAT_L8, terrain_bytes)
	var tm = Terrain.new()
	tm.configure(doc)
	tm.elevation_grid_u = w
	tm.elevation_grid_v = h
	tm.elevation_data = heights.duplicate()
	for i in tm.elevation_data.size():
		tm.elevation_data[i] *= g.elevation_variance_m
	tm.terrain_grid_u = tw
	tm.terrain_grid_v = th
	tm.terrain_data = terrain_bytes
	var objects: Array = []
	var spawn: Dictionary = {}
	var best_spawn = -INF
	var cell_area: float = TAU * g.cylinder_radius_m * g.cylinder_length_m / (tw * th)
	for y in th:
		if y % 16 == 0:
			await progress(cb, 0.78 + 0.12 * float(y) / th, "Placing map-defined objects")
		for x in tw:
			var b: Dictionary = doc.biomes[tm.biome_by_id[int(terrain_bytes[y * tw + x])]]
			var u = float(x) / tw
			var v = float(y) / (th - 1)
			var e = Terrain.sample_image(elevation, u, v) * g.elevation_variance_m
			var slope = slope_at(elevation, u, v, g)
			var spawn_score = -slope - absf(v - 0.5)
			if e >= g.water_sea_level_m + p.spawn_clearance_m and spawn_score > best_spawn:
				best_spawn = spawn_score
				spawn = {"theta": u * TAU, "z": (v - 0.5) * g.cylinder_length_m, "elevation": e, "is_default": true, "name": "Landing", "facing_yaw_rad": 0}
			for rule in b.objects:
				var expected: float = rule.density_per_sq_km * cell_area / 1000000.0
				var count = int(expected) + int(rng.randf() < fposmod(expected, 1.0))
				for j in count:
					if objects.size() >= int(p.object_limit):
						break
					var ou = fposmod(u + rng.randf_range(-0.5, 0.5) / tw, 1)
					var ov = clampf(v + rng.randf_range(-0.5, 0.5) / (th - 1), 0, 1)
					if tm.get_biome_id(ou * TAU, (ov - 0.5) * g.cylinder_length_m, g.cylinder_length_m) != int(b.raster_id) or slope_at(elevation, ou, ov, g) > b.max_slope_deg:
						continue
					objects.append({"id": "%s_%d_%d" % [doc.world_id, int(p.seed), objects.size()], "asset": rule.asset, "theta": ou * TAU, "z": (ov - 0.5) * g.cylinder_length_m, "yaw_rad": rng.randf() * TAU, "scale": rng.randf_range(rule.scale_range[0], rule.scale_range[1]), "tint": doc.objects.model_catalog[rule.asset].tint})
	if spawn.is_empty():
		return {"error": "No dry spawn with the requested clearance; adjust biome elevations or sea level"}
	if objects.size() >= int(p.object_limit):
		warnings.append("Object placement reached the map's object limit.")
	return {"warnings": warnings, "document": doc.duplicate(true), "elevation_image": elevation, "terrain_image": terrain, "objects_data": {"objects": objects, "spawn_points": [spawn]}, "report": report}

static func elevation_bounds(b: Dictionary, g: Dictionary) -> Vector2:
	var low = clampf(b.elevation_range_m[0], 0, g.elevation_variance_m)
	var high = clampf(b.elevation_range_m[1], low, g.elevation_variance_m)
	if b.submerged:
		high = minf(high, g.water_sea_level_m)
	else:
		low = maxf(low, g.water_sea_level_m)
	return Vector2(low, maxf(low, high))

static func slope_at(img: Image, u: float, v: float, g: Dictionary) -> float:
	var du = 1.0 / img.get_width()
	var dv = 1.0 / (img.get_height() - 1)
	var sx = (Terrain.sample_image(img, u + du, v) - Terrain.sample_image(img, u - du, v)) * g.elevation_variance_m / (2 * du * TAU * g.cylinder_radius_m)
	var sz = (Terrain.sample_image(img, u, minf(1, v + dv)) - Terrain.sample_image(img, u, maxf(0, v - dv))) * g.elevation_variance_m / (maxf(minf(1, v + dv) - maxf(0, v - dv), dv) * g.cylinder_length_m)
	return rad_to_deg(atan(Vector2(sx, sz).length()))

static func save_generated_map_package(result: Dictionary, directory: String) -> bool:
	if result.has("error"):
		Config.last_error = str(result.error)
		return false
	var doc: Dictionary = result.document
	# These layers are replaced below; only preserve definitions and assets.
	var error = Config.copy_directory(doc.map_directory, directory, false)
	if error != OK:
		return false
	error = Terrain.write_elevation(directory.path_join(doc.files.elevation_map), result.elevation_image)
	if error != OK:
		Config.copy_failure("save elevation", directory.path_join(doc.files.elevation_map), error)
		return false
	error = result.terrain_image.save_png(directory.path_join(doc.files.terrain_map))
	if error != OK:
		Config.copy_failure("save biomes", directory.path_join(doc.files.terrain_map), error)
		return false
	error = Config.write_json(directory.path_join(doc.files.object_map), result.objects_data)
	if error != OK:
		Config.copy_failure("save placements", directory.path_join(doc.files.object_map), error)
		return false
	doc["generation_report"] = result.report
	doc["generation_warnings"] = result.warnings
	return Config.save_document(doc, directory) == OK
