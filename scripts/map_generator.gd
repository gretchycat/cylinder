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
		if OS.get_thread_caller_id() == OS.get_main_thread_id():
			cb.call(fraction, message)
		else:
			cb.call_deferred(fraction, message)

static func generate(doc: Dictionary, cb: Callable = Callable()) -> Dictionary:
	await progress(cb, 0.00, "Initialization: Validating map configuration and grid parameters")
	var error = Config.validate(doc)
	if not error.is_empty():
		return {"error": error}
	var g: Dictionary = doc.geometry
	var p: Dictionary = doc.generation
	var dims = Config.get_grid_dimensions(doc)
	var w = dims.elevation_width
	var h = dims.elevation_height
	var tw = dims.terrain_width
	var th = dims.terrain_height
	if w * h > 33554432:
		return {"error": "Elevation generation is limited to 33,554,432 samples on this device. Reduce its width or height; the loaded map remains unchanged."}
	var active_biomes = 0
	for biome in doc.biomes.values():
		if biome.weight > 0:
			active_biomes += 1
	if tw * th * active_biomes > 536870912:
		return {"error": "Biome generation exceeds its mobile memory budget. Reduce terrain resolution or disable unused biomes; the loaded map remains unchanged."}
	
	await progress(cb, 0.02, "Initialization: Setting up FastNoiseLite fields and lake coordinates")
	var n = noise(int(p.seed), p.noise_wavelength_m, p)
	var detail = noise(int(p.seed) + 1, p.detail_wavelength_m, p)
	var coast = noise(int(p.seed) + 2, p.coast_wavelength_m, p)
	
	var rng = RandomNumberGenerator.new()
	rng.seed = int(p.seed)
	
	var lake_x = PackedFloat32Array()
	var lake_y = PackedFloat32Array()
	for i in int(p.lake_count):
		lake_x.append(rng.randf())
		lake_y.append(rng.randf())

	var rad_m: float = g.cylinder_radius_m
	var len_m: float = g.cylinder_length_m
	var tau_rad: float = TAU * rad_m
	var base_h: float = p.base_height_m
	var relief_m: float = p.relief_m
	var ridge_h: float = p.ridge_height_m
	var detail_str: float = p.detail_strength
	var coast_var: float = p.coast_variation_m
	var sea_w: float = p.sea_width_m
	var sea_center_v: float = p.sea_center_v
	var sea_target: float = g.water_sea_level_m - p.sea_depth_m
	var lake_target: float = g.water_sea_level_m - p.lake_depth_m
	var lake_rad: float = p.lake_radius_m
	var river_w: float = p.river_width_m
	var river_d: float = p.river_depth_m
	var elev_var: float = g.elevation_variance_m
	var river_count: int = int(p.river_count)

	var gw = mini(w, 2048)
	var gh = mini(h, 1024)

	await progress(cb, 0.04, "Initialization: Precomputing radial & axial lookup matrices (%d × %d)" % [gw, gh])
	var cos_gw = PackedFloat32Array()
	cos_gw.resize(gw)
	var sin_gw = PackedFloat32Array()
	sin_gw.resize(gw)
	for x in gw:
		var angle: float = (float(x) / float(gw)) * TAU
		cos_gw[x] = cos(angle) * rad_m
		sin_gw[x] = sin(angle) * rad_m

	var river_u_matrix = PackedFloat32Array()
	river_u_matrix.resize(gh * river_count)
	for y in gh:
		var v: float = float(y) / float(maxi(gh - 1, 1))
		for river in river_count:
			river_u_matrix[y * river_count + river] = float(river + 1) / (river_count + 1) + sin(v * TAU + river) * coast_var / (TAU * rad_m)

	var relief_bytes = PackedFloat32Array()
	relief_bytes.resize(gw * gh)

	var num_cpu_cores = 1 if (DisplayServer.get_name() == "dummy" or OS.has_feature("single_threaded")) else maxi(OS.get_processor_count(), 1)
	var num_chunks = mini(gh, num_cpu_cores)
	var rows_per_chunk = int(ceil(float(gh) / float(num_chunks)))

	await progress(cb, 0.05, "Elevation Generation: Building physical relief noise (%d chunks)" % num_chunks)

	var relief_mutex = Mutex.new()
	var relief_done = [0]
	var relief_task_id = WorkerThreadPool.add_group_task(func(chunk_idx: int):
		var y_start = chunk_idx * rows_per_chunk
		var y_end = mini(y_start + rows_per_chunk, gh)
		
		for y in range(y_start, y_end):
			var v: float = float(y) / float(maxi(gh - 1, 1))
			var v_z: float = (v - 0.5) * len_m
			var sea_distance: float = absf((v - sea_center_v) * len_m)
			var row_off = y * gw
			var river_row_offset = y * river_count
			
			for x in gw:
				var u: float = float(x) / float(gw)
				var cx: float = cos_gw[x]
				var sx: float = sin_gw[x]

				var broad: float = n.get_noise_3d(cx, sx, v_z)
				var fine: float = detail.get_noise_3d(cx, sx, v_z)
				var height: float = base_h + broad * relief_m + (1.0 - absf(broad)) * maxf(broad, 0.0) * ridge_h + fine * relief_m * detail_str
				var local_sea_dist: float = sea_distance - coast.get_noise_3d(cx, sx, v_z) * coast_var
				
				if sea_w > 0.0:
					var basin: float = 1.0 - smoothstep(sea_w * 0.25, sea_w * 0.75, local_sea_dist)
					height = lerpf(height, sea_target, basin)
				
				for l in lake_x.size():
					var d: float = Vector2(wrapf(u - lake_x[l], -0.5, 0.5) * tau_rad, (v - lake_y[l]) * len_m).length()
					height = lerpf(height, lake_target, 1.0 - smoothstep(lake_rad * 0.3, lake_rad, d))
				
				for river in river_count:
					var r_u: float = river_u_matrix[river_row_offset + river]
					var d: float = absf(wrapf(u - r_u, -0.5, 0.5)) * tau_rad
					var channel: float = 1.0 - smoothstep(0.0, river_w, d)
					height -= channel * river_d
				
				relief_bytes[row_off + x] = clampf(height / elev_var, 0.0, 1.0)

		relief_mutex.lock()
		relief_done[0] += 1
		var done_count = relief_done[0]
		relief_mutex.unlock()
		progress(cb, 0.05 + 0.20 * (float(done_count) / float(num_chunks)), "Elevation Generation: Building physical relief (Chunk %d/%d)" % [done_count, num_chunks])
	, num_chunks)
	
	WorkerThreadPool.wait_for_group_task_completion(relief_task_id)

	var heights: PackedFloat32Array
	if gw == w and gh == h:
		heights = relief_bytes
	else:
		await progress(cb, 0.26, "Elevation Generation: Rescaling physical relief map to grid dimensions (%d × %d)" % [w, h])
		var img_h = Image.create_from_data(gw, gh, false, Image.FORMAT_RF, relief_bytes.to_byte_array())
		img_h.resize(w, h, Image.INTERPOLATE_BILINEAR)
		heights = img_h.get_data().to_float32_array()

	var histogram = PackedInt32Array()
	histogram.resize(4096)
	var num_h_chunks = mini(h, num_cpu_cores)
	var h_rows_per_chunk = int(ceil(float(h) / float(num_h_chunks)))
	var local_histograms: Array[PackedInt32Array] = []
	for c in num_h_chunks:
		var hist = PackedInt32Array()
		hist.resize(4096)
		local_histograms.append(hist)

	await progress(cb, 0.28, "Elevation Generation: Analyzing elevation distribution histogram (%d chunks)" % num_h_chunks)
	var hist_mutex = Mutex.new()
	var hist_done = [0]
	var hist_task_id = WorkerThreadPool.add_group_task(func(chunk_idx: int):
		var y_start = chunk_idx * h_rows_per_chunk
		var y_end = mini(y_start + h_rows_per_chunk, h)
		var local_hist = local_histograms[chunk_idx]
		for y in range(y_start, y_end):
			var row_off = y * w
			for x in w:
				local_hist[mini(4095, int(heights[row_off + x] * 4095.0))] += 1
		
		hist_mutex.lock()
		hist_done[0] += 1
		var done_count = hist_done[0]
		hist_mutex.unlock()
		progress(cb, 0.28 + 0.03 * (float(done_count) / float(num_h_chunks)), "Elevation Generation: Analyzing elevation distribution (Chunk %d/%d)" % [done_count, num_h_chunks])
	, num_h_chunks)
	WorkerThreadPool.wait_for_group_task_completion(hist_task_id)

	for c in num_h_chunks:
		var lh = local_histograms[c]
		for bin in 4096:
			histogram[bin] += lh[bin]

	await progress(cb, 0.31, "Elevation Generation: Reshaping elevation toward biome proportions")
	
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
				cdf += b.weight / total_weight * clampf((mid - bounds.x) / maxf(bounds.y - bounds.x, 0.001), 0.0, 1.0)
			if cdf < quantile:
				low = mid
			else:
				high = mid
		lut[bin] = (low + high) * 0.5 / g.elevation_variance_m

	var lut_chunks = mini(heights.size(), num_cpu_cores)
	var lut_chunk_size = int(ceil(float(heights.size()) / float(lut_chunks)))

	var lut_mutex = Mutex.new()
	var lut_done = [0]
	var lut_task_id = WorkerThreadPool.add_group_task(func(chunk_idx: int):
		var start = chunk_idx * lut_chunk_size
		var finish = mini(start + lut_chunk_size, heights.size())
		for i in range(start, finish):
			heights[i] = lut[mini(4095, int(heights[i] * 4095.0))]
		
		lut_mutex.lock()
		lut_done[0] += 1
		var done_count = lut_done[0]
		lut_mutex.unlock()
		progress(cb, 0.31 + 0.02 * (float(done_count) / float(lut_chunks)), "Elevation Generation: Reshaping elevation toward biomes (Chunk %d/%d)" % [done_count, lut_chunks])
	, lut_chunks)
	WorkerThreadPool.wait_for_group_task_completion(lut_task_id)

	await progress(cb, 0.33, "Elevation Generation: Initializing talus slope erosion parameters")
	var dx: float = TAU * rad_m / float(w)
	var dz: float = len_m / float(maxi(h - 1, 1))
	var talus = tan(deg_to_rad(p.talus_slope_deg)) / elev_var
	var talus_dx = talus * dx
	var talus_dz = talus * dz
	var num_erosion_passes = int(p.erosion_iterations)
	
	var heights_a = heights
	var heights_b = PackedFloat32Array()
	heights_b.resize(w * h)

	for iteration in num_erosion_passes:
		await progress(cb, 0.33 + 0.10 * float(iteration) / maxf(num_erosion_passes, 1.0), "Elevation Generation: Relaxing steep terrain (Pass %d/%d)" % [iteration + 1, num_erosion_passes])
		
		var even = (iteration % 2 == 0)
		var src_h = heights_a if even else heights_b
		var dst_h = heights_b if even else heights_a
		
		var erosion_task_id = WorkerThreadPool.add_group_task(func(chunk_idx: int):
			var y_start = chunk_idx * h_rows_per_chunk
			var y_end = mini(y_start + h_rows_per_chunk, h)
			for y in range(y_start, y_end):
				var row_off = y * w
				var y_next_off = mini(y + 1, h - 1) * w
				var y_prev_off = maxi(y - 1, 0) * w
				for x in w:
					var i = row_off + x
					var h_i = src_h[i]
					var x_next_i = row_off + (x + 1) % w
					var x_prev_i = row_off + (x - 1 + w) % w
					var y_next_i = y_next_off + x
					var y_prev_i = y_prev_off + x
					
					var diff_r = h_i - src_h[x_next_i]
					var diff_l = h_i - src_h[x_prev_i]
					var diff_d = h_i - src_h[y_next_i]
					var diff_u = h_i - src_h[y_prev_i]
					
					var tr_r = signf(diff_r) * maxf(absf(diff_r) - talus_dx, 0.0) * 0.0625
					var tr_l = signf(diff_l) * maxf(absf(diff_l) - talus_dx, 0.0) * 0.0625
					var tr_d = signf(diff_d) * maxf(absf(diff_d) - talus_dz, 0.0) * 0.0625
					var tr_u = signf(diff_u) * maxf(absf(diff_u) - talus_dz, 0.0) * 0.0625
					
					dst_h[i] = h_i - tr_r - tr_l - tr_d - tr_u
		, num_h_chunks)
		WorkerThreadPool.wait_for_group_task_completion(erosion_task_id)

	heights = heights_a if (num_erosion_passes % 2 == 0) else heights_b

	await progress(cb, 0.44, "Elevation Generation: Computing slope angles across heightmap")
	var elevation = Image.create_from_data(w, h, false, Image.FORMAT_RF, heights.to_byte_array())
	var slopes = compute_slopes_grid(heights, w, h, g, cb)
	
	var terrain_bytes = PackedByteArray()
	terrain_bytes.resize(tw * th)
	
	var temperature = noise(int(p.seed) + 10, p.climate_wavelength_m, p)
	var moisture = noise(int(p.seed) + 11, p.climate_wavelength_m, p)
	
	var score_stride = enabled.size()
	var region_fields: Array[FastNoiseLite] = []
	for key in enabled:
		region_fields.append(noise(int(p.seed) ^ str(key).hash(), p.biome_region_wavelength_m, p))
		
	var cgw = mini(tw, 1024)
	var cgh = mini(th, 512)
	
	var cos_cgw = PackedFloat32Array()
	cos_cgw.resize(cgw)
	var sin_cgw = PackedFloat32Array()
	sin_cgw.resize(cgw)
	for x in cgw:
		var angle: float = (float(x) / float(cgw)) * TAU
		cos_cgw[x] = cos(angle) * rad_m
		sin_cgw[x] = sin(angle) * rad_m

	var climate_chunks = mini(cgh, num_cpu_cores)
	var climate_rows_per_chunk = int(ceil(float(cgh) / float(climate_chunks)))
	
	var temp_grid = PackedFloat32Array()
	temp_grid.resize(cgw * cgh)
	var moist_grid = PackedFloat32Array()
	moist_grid.resize(cgw * cgh)
	var reg_grids: Array[PackedFloat32Array] = []
	for k in score_stride:
		var rg = PackedFloat32Array()
		rg.resize(cgw * cgh)
		reg_grids.append(rg)

	await progress(cb, 0.46, "Terrain Generation: Sampling 3D temperature, moisture, and region noise fields (%d chunks)" % climate_chunks)
	var climate_mutex = Mutex.new()
	var climate_done = [0]
	var climate_noise_task_id = WorkerThreadPool.add_group_task(func(chunk_idx: int):
		var y_start = chunk_idx * climate_rows_per_chunk
		var y_end = mini(y_start + climate_rows_per_chunk, cgh)
		
		for y in range(y_start, y_end):
			var v: float = float(y) / float(maxi(cgh - 1, 1))
			var v_z: float = (v - 0.5) * len_m
			var row_off = y * cgw
			
			for x in cgw:
				var cx: float = cos_cgw[x]
				var sx: float = sin_cgw[x]
				var idx = row_off + x
				temp_grid[idx] = temperature.get_noise_3d(cx, sx, v_z) * 0.5 + 0.5
				moist_grid[idx] = moisture.get_noise_3d(cx, sx, v_z) * 0.5 + 0.5
				for k in score_stride:
					reg_grids[k][idx] = region_fields[k].get_noise_3d(cx, sx, v_z)

		climate_mutex.lock()
		climate_done[0] += 1
		var done_count = climate_done[0]
		climate_mutex.unlock()
		progress(cb, 0.46 + 0.03 * (float(done_count) / float(climate_chunks)), "Terrain Generation: Sampling climate fields (Chunk %d/%d)" % [done_count, climate_chunks])
	, climate_chunks)
	WorkerThreadPool.wait_for_group_task_completion(climate_noise_task_id)

	var temp_upscaled: PackedFloat32Array
	var moist_upscaled: PackedFloat32Array
	var reg_upscaled: Array[PackedFloat32Array] = []

	if cgw == tw and cgh == th:
		temp_upscaled = temp_grid
		moist_upscaled = moist_grid
		reg_upscaled = reg_grids
	else:
		await progress(cb, 0.49, "Terrain Generation: Rescaling climate maps to terrain grid resolution (%d × %d)" % [tw, th])
		var img_t = Image.create_from_data(cgw, cgh, false, Image.FORMAT_RF, temp_grid.to_byte_array())
		img_t.resize(tw, th, Image.INTERPOLATE_BILINEAR)
		temp_upscaled = img_t.get_data().to_float32_array()

		var img_m = Image.create_from_data(cgw, cgh, false, Image.FORMAT_RF, moist_grid.to_byte_array())
		img_m.resize(tw, th, Image.INTERPOLATE_BILINEAR)
		moist_upscaled = img_m.get_data().to_float32_array()
		
		for k in score_stride:
			var img_r = Image.create_from_data(cgw, cgh, false, Image.FORMAT_RF, reg_grids[k].to_byte_array())
			img_r.resize(tw, th, Image.INTERPOLATE_BILINEAR)
			reg_upscaled.append(img_r.get_data().to_float32_array())

	var b_low = PackedFloat32Array()
	var b_high = PackedFloat32Array()
	var b_max_slope = PackedFloat32Array()
	var b_submerged = PackedByteArray()
	var b_temp = PackedFloat32Array()
	var b_moist = PackedFloat32Array()
	var b_raster_id = PackedByteArray()
	b_low.resize(score_stride)
	b_high.resize(score_stride)
	b_max_slope.resize(score_stride)
	b_submerged.resize(score_stride)
	b_temp.resize(score_stride)
	b_moist.resize(score_stride)
	b_raster_id.resize(score_stride)
	
	for k in score_stride:
		var key = enabled[k]
		var b: Dictionary = doc.biomes[key]
		var bounds = elevation_bounds(b, g)
		b_low[k] = bounds.x
		b_high[k] = bounds.y
		b_max_slope[k] = float(b.max_slope_deg)
		b_submerged[k] = 1 if bool(b.submerged) else 0
		b_temp[k] = float(b.temperature)
		b_moist[k] = float(b.moisture)
		b_raster_id[k] = int(b.raster_id)

	await progress(cb, 0.50, "Terrain Generation: Fitting climate and biome region suitability")

	var th_chunks = mini(th, num_cpu_cores)
	var th_rows_per_chunk = int(ceil(float(th) / float(th_chunks)))
	var water_sea_m: float = g.water_sea_level_m
	var biome_reg_str: float = p.biome_region_strength
	var is_direct_grid: bool = (tw == w and th == h)

	var unsuitable = PackedByteArray()
	unsuitable.resize(tw * th)
	var scores = PackedFloat32Array()
	scores.resize(tw * th * score_stride)

	var fit_mutex = Mutex.new()
	var fit_done = [0]
	var fit_task_id = WorkerThreadPool.add_group_task(func(chunk_idx: int):
		var y_start = chunk_idx * th_rows_per_chunk
		var y_end = mini(y_start + th_rows_per_chunk, th)
		
		for y in range(y_start, y_end):
			var v: float = float(y) / float(maxi(th - 1, 1))
			var row_tw_offset = y * tw
			
			for x in tw:
				var u: float = float(x) / float(tw)
				var cell_idx = row_tw_offset + x
				
				var e: float = 0.0
				var slope: float = 0.0
				if is_direct_grid:
					e = heights[cell_idx] * elev_var
					slope = slopes[cell_idx]
				else:
					e = sample_heights(heights, w, h, u, v) * elev_var
					slope = sample_heights(slopes, w, h, u, v)
				
				var temp: float = temp_upscaled[cell_idx]
				var moist: float = moist_upscaled[cell_idx]
				var cell_offset: int = cell_idx * score_stride
				var valid_options: int = 0
				
				for k in score_stride:
					var low = b_low[k]
					var high = b_high[k]
					var outside: float = maxf(maxf(low - e, e - high), 0.0)
					var max_slp = b_max_slope[k]
					var penalty: float = outside / elev_var * 50.0 + maxf(slope - max_slp, 0.0) / 5.0
					var is_sub = (b_submerged[k] != 0)
					var is_underwater = (e < water_sea_m)
					if is_sub != is_underwater:
						penalty += 20.0
					var valid: bool = (outside <= 0.001 and slope <= max_slp and is_sub == is_underwater)
					if valid:
						valid_options += 1
					var reg_val: float = reg_upscaled[k][cell_idx]
					var dt = temp - b_temp[k]
					var dm = moist - b_moist[k]
					scores[cell_offset + k] = -(dt * dt) - (dm * dm) + reg_val * biome_reg_str - penalty
				
				unsuitable[cell_idx] = 1 if valid_options == 0 else 0

		fit_mutex.lock()
		fit_done[0] += 1
		var done_count = fit_done[0]
		fit_mutex.unlock()
		progress(cb, 0.50 + 0.08 * (float(done_count) / float(th_chunks)), "Terrain Generation: Evaluating biome suitability (Chunk %d/%d)" % [done_count, th_chunks])
	, th_chunks)
	
	WorkerThreadPool.wait_for_group_task_completion(fit_task_id)

	var counts = PackedInt32Array()
	counts.resize(score_stride)
	var best_error = INF
	var best_ids = PackedByteArray()
	var best_counts = PackedInt32Array()
	best_counts.resize(score_stride)
	
	var biases = PackedFloat32Array()
	biases.resize(score_stride)
	
	var bal_chunks = mini(terrain_bytes.size(), num_cpu_cores)
	var bal_chunk_size = int(ceil(float(terrain_bytes.size()) / float(bal_chunks)))
	var chunk_counts: Array[PackedInt32Array] = []
	var chunk_ids: Array[PackedByteArray] = []
	for c in bal_chunks:
		var cc = PackedInt32Array()
		cc.resize(score_stride)
		chunk_counts.append(cc)
		var arr = PackedByteArray()
		var c_size = mini(bal_chunk_size, terrain_bytes.size() - c * bal_chunk_size)
		arr.resize(c_size)
		chunk_ids.append(arr)

	var num_bal_iterations = int(p.balance_iterations)
	await progress(cb, 0.58, "Terrain Generation: Initializing biome area balancing passes (%d passes)" % num_bal_iterations)
	for iteration in num_bal_iterations:
		await progress(cb, 0.59 + float(iteration) / num_bal_iterations * 0.18, "Terrain Generation: Balancing requested biome areas (Pass %d/%d)" % [iteration + 1, num_bal_iterations])
		counts.fill(0)
		for c in bal_chunks:
			chunk_counts[c].fill(0)
			
		var bal_task_id = WorkerThreadPool.add_group_task(func(chunk_idx: int):
			var start = chunk_idx * bal_chunk_size
			var finish = mini(start + bal_chunk_size, terrain_bytes.size())
			var local_cc = chunk_counts[chunk_idx]
			var local_ids = chunk_ids[chunk_idx]
			for i in range(start, finish):
				var offset = i * score_stride
				var best = 0
				var best_s = scores[offset] + biases[0]
				for k in range(1, score_stride):
					var s = scores[offset + k] + biases[k]
					if s > best_s:
						best_s = s
						best = k
				local_ids[i - start] = b_raster_id[best]
				local_cc[best] += 1
		, bal_chunks)
		WorkerThreadPool.wait_for_group_task_completion(bal_task_id)

		for c in bal_chunks:
			var start = c * bal_chunk_size
			var local_ids = chunk_ids[c]
			for i in local_ids.size():
				terrain_bytes[start + i] = local_ids[i]

		for c in bal_chunks:
			var lcc = chunk_counts[c]
			for k in score_stride:
				counts[k] += lcc[k]

		var error_sum = 0.0
		for k in score_stride:
			var target: float = doc.biomes[enabled[k]].weight / total_weight
			var area_error: float = target - counts[k] / float(tw * th)
			error_sum += absf(area_error)
			biases[k] += area_error * 0.8 / sqrt(iteration + 1.0)
		if error_sum < best_error:
			best_error = error_sum
			best_ids = terrain_bytes.duplicate()
			best_counts = counts.duplicate()
		if error_sum < 0.02:
			progress(cb, 0.77, "Terrain Generation: Target biome mix achieved at Pass %d/%d (error %.1f%%) — early exit" % [iteration + 1, num_bal_iterations, error_sum * 100.0])
			break

	terrain_bytes = best_ids
	counts = best_counts
	
	var warnings: Array[String] = []
	var unsuitable_count = 0
	for value in unsuitable:
		unsuitable_count += value
	if unsuitable_count > 0:
		warnings.append("%.2f%% of cells have no selected biome satisfying all elevation/slope/water constraints; closest selected biome used. Broaden biome ranges or reduce relief." % (100.0 * unsuitable_count / float(tw * th)))
	
	var report: Dictionary = {}
	for k in score_stride:
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
	var skip_objects: bool = p.get("skip_objects", false)
	if skip_objects:
		await progress(cb, 0.84, "Object Placement: Skipping object scattering as requested (performance mode)")
	else:
		await progress(cb, 0.78, "Object Placement: Calculating biome surface areas for object scattering")
		var total_area_km2: float = (TAU * rad_m * len_m) / 1000000.0
		var biome_keys = doc.biomes.keys()
		var num_biome_keys = biome_keys.size()
		for b_idx in range(num_biome_keys):
			var b_id = biome_keys[b_idx]
			var biome: Dictionary = doc.biomes[b_id]
			await progress(cb, 0.78 + 0.06 * (float(b_idx + 1) / float(maxi(num_biome_keys, 1))), "Object Placement: Scattering objects for biome '%s'" % biome.get("name", b_id))
			if biome.get("weight", 0.0) <= 0.0 or not biome.has("objects") or not (biome.objects is Array) or biome.objects.is_empty():
				continue
			var r_id = int(biome.raster_id)
			var cell_indices: Array[Vector2i] = []
			for y in th:
				var row_off = y * tw
				for x in tw:
					if terrain_bytes[row_off + x] == r_id:
						cell_indices.append(Vector2i(x, y))
			if cell_indices.is_empty():
				continue
			var biome_area_fraction = float(cell_indices.size()) / float(tw * th)
			var biome_area_km2 = total_area_km2 * biome_area_fraction

			for rule in biome.objects:
				if not rule is Dictionary or not rule.has("asset") or not rule.has("density_per_sq_km"):
					continue
				var target_count = mini(int(round(biome_area_km2 * float(rule.density_per_sq_km))), 800)
				if target_count <= 0:
					continue
				var scale_min = 1.0
				var scale_max = 1.0
				if rule.has("scale_range") and rule.scale_range is Array and rule.scale_range.size() >= 2:
					scale_min = float(rule.scale_range[0])
					scale_max = float(rule.scale_range[1])

				var catalog_entry: Dictionary = doc.objects.model_catalog.get(rule.asset, {})
				var catalog_offset = Config.get_object_ground_offset(catalog_entry, rule.asset)
				var catalog_align = Config.get_object_align_to_normal(catalog_entry, rule.asset)
				var catalog_random_yaw = Config.get_object_random_yaw(catalog_entry, rule.asset)
				var catalog_on_side = Config.get_object_allow_on_side(catalog_entry, rule.asset)
				var catalog_side_chance = Config.get_object_on_side_chance(catalog_entry, rule.asset)
				
				var attempts = 0
				var max_attempts = target_count * 5
				var placed_for_rule = 0
				while placed_for_rule < target_count and attempts < max_attempts:
					attempts += 1
					var cell = cell_indices[rng.randi() % cell_indices.size()]
					var u = (float(cell.x) + rng.randf()) / float(tw)
					var v = (float(cell.y) + rng.randf()) / float(th)
					var e = sample_heights(heights, w, h, u, v) * elev_var
					var slope = sample_heights(slopes, w, h, u, v)
					if not biome.get("submerged", false) and e < water_sea_m:
						continue
					if slope > float(biome.get("max_slope_deg", 90.0)):
						continue
					var theta = u * TAU
					var z = (v - 0.5) * len_m
					var scale_val = rng.randf_range(scale_min, scale_max) if scale_max > scale_min else scale_min

					var yaw_val = rng.randf() * TAU if catalog_random_yaw else 0.0
					var pitch_val = 0.0
					var roll_val = 0.0
					var item_offset = catalog_offset

					var is_fallen = catalog_on_side and rng.randf() < catalog_side_chance
					if is_fallen:
						pitch_val = rng.randf_range(deg_to_rad(75.0), deg_to_rad(105.0))
						roll_val = rng.randf() * TAU
						item_offset = -0.25

					objects.append({
						"id": "obj_%s_%d" % [rule.asset, objects.size() + 1],
						"asset": rule.asset,
						"theta": theta,
						"z": z,
						"elevation": e,
						"yaw_rad": yaw_val,
						"pitch_rad": pitch_val,
						"roll_rad": roll_val,
						"scale": scale_val,
						"ground_offset_m": item_offset,
						"align_to_normal": catalog_align
					})
					placed_for_rule += 1

	var spawn: Dictionary = {}
	var best_spawn = -INF
	await progress(cb, 0.85, "Object Placement: Determining landing spawn location")
	
	var spawn_clearance: float = p.spawn_clearance_m
	
	for y in th:
		var v = float(y) / float(maxi(th - 1, 1))
		var row_tw_offset = y * tw
		for x in tw:
			var u = float(x) / float(tw)
			
			var e = 0.0
			var slope = 0.0
			if is_direct_grid:
				var idx = row_tw_offset + x
				e = heights[idx] * elev_var
				slope = slopes[idx]
			else:
				e = sample_heights(heights, w, h, u, v) * elev_var
				slope = sample_heights(slopes, w, h, u, v)
				
			var spawn_score = -slope - absf(v - 0.5)
			if e >= water_sea_m + spawn_clearance and spawn_score > best_spawn:
				best_spawn = spawn_score
				spawn = {"theta": u * TAU, "z": (v - 0.5) * len_m, "elevation": e, "is_default": true, "name": "Landing", "facing_yaw_rad": 0}

	if spawn.is_empty():
		return {"error": "No dry spawn with the requested clearance; adjust biome elevations or sea level"}

	# Collect Points of Interest (POIs)
	var pois: Array = []
	for i in int(p.lake_count):
		var lu = lake_x[i]
		var lv = lake_y[i]
		var theta = lu * TAU
		var z_m = (lv - 0.5) * len_m
		var px = rad_m * cos(theta)
		var py = rad_m * sin(theta)
		var p_elev = sample_heights(heights, w, h, lu, lv) * elev_var
		pois.append({
			"id": "poi_lake_" + str(i + 1),
			"name": "Freshwater Lake " + str(i + 1),
			"type": "lake",
			"u_frac": lu,
			"v_frac": lv,
			"coordinates_3d": {"x": px, "y": py, "z": z_m},
			"elevation_m": p_elev
		})

	if doc.has("generation_descriptor") and doc.generation_descriptor is Dictionary:
		var desc: Dictionary = doc.generation_descriptor
		for art in desc.get("artificial_biomes", []):
			if art is Dictionary and art.get("add_to_poi_list", false):
				var au = float(art.get("center_u_frac", 0.5))
				var av = float(art.get("center_v_frac", 0.5))
				var theta = au * TAU
				var z_m = (av - 0.5) * len_m
				var px = rad_m * cos(theta)
				var py = rad_m * sin(theta)
				var p_elev = sample_heights(heights, w, h, au, av) * elev_var
				pois.append({
					"id": "poi_art_" + str(pois.size() + 1),
					"name": str(art.get("poi_name", "Artificial Landmark")),
					"type": str(art.get("poi_type", "landmark")),
					"u_frac": au,
					"v_frac": av,
					"coordinates_3d": {"x": px, "y": py, "z": z_m},
					"elevation_m": p_elev
				})

	await progress(cb, 0.90, "Map Package: Assembling generated elevation, terrain, and object structures")
	return {"warnings": warnings, "document": doc.duplicate(true), "elevation_image": elevation, "terrain_image": terrain, "objects_data": {"objects": objects, "spawn_points": [spawn]}, "report": report, "pois": pois}

static func compute_slopes_grid(heights: PackedFloat32Array, w: int, h: int, g: Dictionary, cb: Callable = Callable()) -> PackedFloat32Array:
	var slopes = PackedFloat32Array()
	slopes.resize(w * h)
	var num_cpu_cores = 1 if (DisplayServer.get_name() == "dummy" or OS.has_feature("single_threaded")) else maxi(OS.get_processor_count(), 1)
	var num_chunks = mini(h, num_cpu_cores)
	var rows_per_chunk = int(ceil(float(h) / float(num_chunks)))
	var rad_m: float = g.cylinder_radius_m
	var len_m: float = g.cylinder_length_m
	var elev_var: float = g.elevation_variance_m
	var du: float = 1.0 / float(w)
	var dv: float = 1.0 / float(maxi(h - 1, 1))
	var du_dist: float = 2.0 * du * TAU * rad_m
	
	var slopes_mutex = Mutex.new()
	var slopes_done = [0]
	var task_id = WorkerThreadPool.add_group_task(func(chunk_idx: int):
		var y_start = chunk_idx * rows_per_chunk
		var y_end = mini(y_start + rows_per_chunk, h)
		for y in range(y_start, y_end):
			var y_up = mini(y + 1, h - 1)
			var y_dn = maxi(y - 1, 0)
			var dz_dist = maxf(float(y_up - y_dn) * dv, dv) * len_m
			var row_offset = y * w
			var up_offset = y_up * w
			var dn_offset = y_dn * w
			for x in w:
				var x_r = (x + 1) % w
				var x_l = (x - 1 + w) % w
				var sx = (heights[row_offset + x_r] - heights[row_offset + x_l]) * elev_var / du_dist
				var sz = (heights[up_offset + x] - heights[dn_offset + x]) * elev_var / dz_dist
				slopes[row_offset + x] = rad_to_deg(atan(sqrt(sx * sx + sz * sz)))
		
		slopes_mutex.lock()
		slopes_done[0] += 1
		var done_count = slopes_done[0]
		slopes_mutex.unlock()
		progress(cb, 0.44 + 0.02 * (float(done_count) / float(num_chunks)), "Elevation Generation: Computing slope angles (Chunk %d/%d)" % [done_count, num_chunks])
	, num_chunks)
	WorkerThreadPool.wait_for_group_task_completion(task_id)
	return slopes

static func elevation_bounds(b: Dictionary, g: Dictionary) -> Vector2:
	var low = clampf(b.elevation_range_m[0], 0, g.elevation_variance_m)
	var high = clampf(b.elevation_range_m[1], low, g.elevation_variance_m)
	if b.submerged:
		high = minf(high, g.water_sea_level_m)
	else:
		low = maxf(low, g.water_sea_level_m)
	return Vector2(low, maxf(low, high))

static func sample_heights(heights: PackedFloat32Array, w: int, h: int, u: float, v: float) -> float:
	var x = fposmod(u, 1.0) * w
	var y = clampf(v, 0.0, 1.0) * float(h - 1)
	var x0 = int(floor(x)) % w
	var x1 = (x0 + 1) % w
	var y0 = int(floor(y))
	var y1 = mini(y0 + 1, h - 1)
	var fx = x - floor(x)
	var fy = y - floor(y)
	var h0 = lerpf(heights[y0 * w + x0], heights[y0 * w + x1], fx)
	var h1 = lerpf(heights[y1 * w + x0], heights[y1 * w + x1], fx)
	return lerpf(h0, h1, fy)

static func slope_from_heights(heights: PackedFloat32Array, w: int, h: int, u: float, v: float, g: Dictionary) -> float:
	var du = 1.0 / float(w)
	var dv = 1.0 / float(maxi(h - 1, 1))
	var v_up = mini(1.0, v + dv)
	var v_dn = maxf(0.0, v - dv)
	var sx = (sample_heights(heights, w, h, u + du, v) - sample_heights(heights, w, h, u - du, v)) * g.elevation_variance_m / (2.0 * du * TAU * g.cylinder_radius_m)
	var sz = (sample_heights(heights, w, h, u, v_up) - sample_heights(heights, w, h, u, v_dn)) * g.elevation_variance_m / (maxf(v_up - v_dn, dv) * g.cylinder_length_m)
	return rad_to_deg(atan(Vector2(sx, sz).length()))

static func slope_at(img: Image, u: float, v: float, g: Dictionary) -> float:
	var du = 1.0 / img.get_width()
	var dv = 1.0 / (img.get_height() - 1)
	var sx = (Terrain.sample_image(img, u + du, v) - Terrain.sample_image(img, u - du, v)) * g.elevation_variance_m / (2 * du * TAU * g.cylinder_radius_m)
	var sz = (Terrain.sample_image(img, u, minf(1, v + dv)) - Terrain.sample_image(img, u, maxf(0, v - dv))) * g.elevation_variance_m / (maxf(minf(1, v + dv) - maxf(0, v - dv), dv) * g.cylinder_length_m)
	return rad_to_deg(atan(Vector2(sx, sz).length()))

static func save_generated_map_package(result: Dictionary, directory: String, cb: Callable = Callable()) -> bool:
	if result.has("error"):
		Config.last_error = str(result.error)
		return false
	progress(cb, 0.91, "Map Package: Preparing destination directory %s" % directory)
	var doc: Dictionary = result.document
	var error = Config.copy_directory(doc.map_directory, directory, false)
	if error != OK:
		return false
	progress(cb, 0.93, "Map Package: Writing float32 elevation heightmap binary (.cylh)")
	error = Terrain.write_elevation(directory.path_join(doc.files.elevation_map), result.elevation_image)
	if error != OK:
		Config.copy_failure("save elevation", directory.path_join(doc.files.elevation_map), error)
		return false
	progress(cb, 0.95, "Map Package: Saving PNG biome terrain map (.png)")
	error = result.terrain_image.save_png(directory.path_join(doc.files.terrain_map))
	if error != OK:
		Config.copy_failure("save biomes", directory.path_join(doc.files.terrain_map), error)
		return false
	progress(cb, 0.97, "Map Package: Saving object placements JSON map (.json)")
	error = Config.write_json(directory.path_join(doc.files.object_map), result.objects_data)
	if error != OK:
		Config.copy_failure("save placements", directory.path_join(doc.files.object_map), error)
		return false
	if result.has("pois") and not (result.pois as Array).is_empty():
		progress(cb, 0.98, "Map Package: Saving POI list manifest (pois.json)")
		Config.write_json(directory.path_join("pois.json"), {"points_of_interest": result.pois})
	doc["generation_report"] = result.report
	doc["generation_warnings"] = result.warnings
	progress(cb, 0.99, "Map Package: Saving descriptor document metadata")
	var saved_ok = Config.save_document(doc, directory) == OK
	if saved_ok:
		progress(cb, 1.00, "Map Package: Generation and package save complete")
	return saved_ok
