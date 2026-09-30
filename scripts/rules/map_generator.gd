class_name MapGenerator
extends RefCounted
## Procedural continent map + fair-ish start positions. Deterministic for a given seed.
## Uses percentiles (not absolute noise values) so the ratios in rules.json hold on any seed.


## Returns {"map": HexMap, "starts": Array of Vector2i}.
static func generate(width: int, height: int, seed_value: int, player_count: int) -> Dictionary:
	var result := {}
	for attempt in 16:
		result = _try_generate(width, height, seed_value + attempt * 7919, player_count)
		if result.starts.size() >= player_count:
			return result
	push_warning("MapGenerator: only placed %d of %d starts" % [result.starts.size(), player_count])
	return result


static func _try_generate(width: int, height: int, seed_value: int, player_count: int) -> Dictionary:
	var cfg: Dictionary = Defs.rules.map
	var map := HexMap.new(width, height)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := map.size()

	var elev_noise := _noise(seed_value, 0.07, 5)
	var rough_noise := _noise(seed_value + 1, 0.18, 3)
	var moist_noise := _noise(seed_value + 2, 0.09, 3)
	var forest_noise := _noise(seed_value + 3, 0.16, 3)

	# 1. Elevation with a radial falloff so land gathers in the middle.
	var elev := PackedFloat32Array()
	elev.resize(n)
	var edge: int = cfg.edge_water
	for i in n:
		var t := map.tiles[i]
		var o := Hex.axial_to_offset(t.coord)
		var p := Hex.to_pixel(t.coord) / Hex.TILE_WIDTH
		var dx := (o.x - (width - 1) * 0.5) / ((width - 1) * 0.5)
		var dy := (o.y - (height - 1) * 0.5) / ((height - 1) * 0.5)
		var d := sqrt(dx * dx + dy * dy) / sqrt(2.0)
		var e := elev_noise.get_noise_2dv(p) - pow(d, 1.8) * 0.9
		if o.x < edge or o.y < edge or o.x >= width - edge or o.y >= height - edge:
			e -= 10.0
		elev[i] = e

	# 2. Sea level from the land ratio.
	var sea := _percentile_threshold(elev, float(cfg.land_ratio))
	var land: Array = []
	for i in n:
		if elev[i] > sea:
			land.append(i)
			map.tiles[i].terrain = "grassland"

	# 3. Mountains (highest land) and hills (high + rough land).
	land.sort_custom(func(a, b): return elev[a] > elev[b])
	var mountain_count := int(land.size() * float(cfg.mountain_ratio))
	for k in mountain_count:
		map.tiles[land[k]].elevation = "mountains"
	var rest: Array = land.slice(mountain_count)
	var hill_score := {}
	for i in rest:
		var p := Hex.to_pixel(map.tiles[i].coord) / Hex.TILE_WIDTH
		hill_score[i] = elev[i] * 0.6 + rough_noise.get_noise_2dv(p)
	rest.sort_custom(func(a, b): return hill_score[a] > hill_score[b])
	for k in int(land.size() * float(cfg.hills_ratio)):
		map.tiles[rest[k]].elevation = "hills"

	# 4. Climate: tundra by latitude, desert where driest, grass/plains by moisture.
	var moisture := {}
	var temperate: Array = []
	for i in land:
		var t := map.tiles[i]
		var o := Hex.axial_to_offset(t.coord)
		var p := Hex.to_pixel(t.coord) / Hex.TILE_WIDTH
		moisture[i] = moist_noise.get_noise_2dv(p)
		var lat: float = absf(o.y - (height - 1) * 0.5) / ((height - 1) * 0.5) + moisture[i] * 0.1
		if lat > float(cfg.tundra_latitude):
			t.terrain = "tundra"
		else:
			temperate.append(i)
	temperate.sort_custom(func(a, b): return moisture[a] < moisture[b])
	var desert_count := int(land.size() * float(cfg.desert_ratio))
	var median: float = moisture[temperate[temperate.size() / 2]] if not temperate.is_empty() else 0.0
	for k in temperate.size():
		var i: int = temperate[k]
		if k < desert_count:
			map.tiles[i].terrain = "desert"
		elif moisture[i] < median:
			map.tiles[i].terrain = "plains"
		else:
			map.tiles[i].terrain = "grassland"

	# 5. Forests on eligible land.
	var forestable: Array = []
	var forest_score := {}
	for i in land:
		var t := map.tiles[i]
		if t.is_mountain() or not Defs.terrains[t.terrain].get("forest_allowed", false):
			continue
		forestable.append(i)
		forest_score[i] = forest_noise.get_noise_2dv(Hex.to_pixel(t.coord) / Hex.TILE_WIDTH) + moisture[i] * 0.3
	forestable.sort_custom(func(a, b): return forest_score[a] > forest_score[b])
	for k in int(land.size() * float(cfg.forest_ratio)):
		if k < forestable.size():
			map.tiles[forestable[k]].feature = "forest"

	# 6. Water depth and art variants.
	for t in map.tiles:
		t.variant = rng.randi() % 1000
		if t.terrain == "ocean":
			for nb in map.neighbors(t.coord):
				if not nb.is_water():
					t.terrain = "coast"
					break

	# 7. Starts on the largest landmass.
	var component := _largest_land_component(map)
	var starts := _pick_starts(map, component, player_count, rng, int(cfg.min_start_distance))
	for s in starts:
		var st := map.get_tile(s)
		st.feature = ""
		st.resource = ""
		if st.elevation == "mountains":
			st.elevation = "flat"

	# 8. Resources.
	_place_resources(map, starts, rng, float(cfg.resource_density))
	for s in starts:
		_ensure_resource_near(map, s, "horses", 4, rng)
		_ensure_resource_near(map, s, "iron", 5, rng)
	return {"map": map, "starts": starts}


static func _noise(seed_value: int, frequency: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	return noise


## Value such that `ratio` of the entries are strictly above it.
static func _percentile_threshold(values: PackedFloat32Array, ratio: float) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	var idx := clampi(int(sorted.size() * (1.0 - ratio)), 0, sorted.size() - 1)
	return sorted[idx] - 0.000001 if idx > 0 else sorted[0] - 1.0


static func _largest_land_component(map: HexMap) -> Dictionary:
	var seen := {}
	var best := {}
	for t in map.tiles:
		if not t.is_passable_land() or seen.has(t.coord):
			continue
		var comp := {}
		var stack: Array = [t.coord]
		seen[t.coord] = true
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			comp[c] = true
			for nb in map.neighbors(c):
				if nb.is_passable_land() and not seen.has(nb.coord):
					seen[nb.coord] = true
					stack.append(nb.coord)
		if comp.size() > best.size():
			best = comp
	return best


static func start_score(map: HexMap, c: Vector2i) -> float:
	var score := 0.0
	for t in map.tiles_within(c, 2):
		if t.is_mountain():
			continue
		var y := Yields.tile_yields(t, null)
		score += y.food * 2.0 + y.production * 1.5 + y.gold * 0.5
		if t.resource != "":
			score += 2.0
	return score


static func _pick_starts(map: HexMap, component: Dictionary, count: int, rng: RandomNumberGenerator, min_distance: int) -> Array:
	var candidates: Array = []
	for c in component:
		var t := map.get_tile(c)
		var o := Hex.axial_to_offset(c)
		if o.x < 3 or o.y < 3 or o.x >= map.width - 3 or o.y >= map.height - 3:
			continue
		if t.terrain != "grassland" and t.terrain != "plains":
			continue
		candidates.append({"coord": c, "score": start_score(map, c)})
	if candidates.is_empty():
		return []
	candidates.sort_custom(func(a, b): return a.score > b.score)
	candidates = candidates.slice(0, maxi(count * 4, candidates.size() / 2))
	for required in range(min_distance, 3, -1):
		var starts: Array = [candidates[rng.randi() % mini(5, candidates.size())].coord]
		while starts.size() < count:
			var best: Dictionary = {}
			var best_d := -1
			for cand in candidates:
				var d := 1 << 20
				for s in starts:
					d = mini(d, Hex.distance(s, cand.coord))
				if d >= required and (d > best_d or (d == best_d and cand.score > best.score)):
					best_d = d
					best = cand
			if best.is_empty():
				break
			starts.append(best.coord)
		if starts.size() >= count:
			return starts
	return []


static func _resource_fits(res: Dictionary, t: Tile) -> bool:
	if t.is_water() or t.is_mountain():
		return false
	if not t.terrain in res.get("terrains", []):
		return false
	if not t.elevation in res.get("elevations", ["flat"]):
		return false
	if res.get("no_feature", false) and t.feature != "":
		return false
	return true


## Picks each resource by its weight, then a random free tile it fits on, so the overall mix
## follows the data whatever the terrain (choosing per tile would put gold on every forest).
static func _place_resources(map: HexMap, starts: Array, rng: RandomNumberGenerator, density: float) -> void:
	var ids: Array = Defs.resources.keys()
	var total := 0
	var spots := {}  # id -> tiles it could go on
	for id in ids:
		total += int(Defs.resources[id].get("weight", 1))
		spots[id] = map.tiles.filter(func(t): return not (t.coord in starts) and _resource_fits(Defs.resources[id], t))
	if total <= 0:
		return
	var land := map.tiles.filter(func(t): return t.is_passable_land()).size()
	for i in int(land * density):
		var roll := rng.randi() % total
		for id in ids:
			roll -= int(Defs.resources[id].get("weight", 1))
			if roll < 0:
				_place_on_free_spot(spots[id], id, rng)
				break


static func _place_on_free_spot(spots: Array, resource_id: String, rng: RandomNumberGenerator) -> void:
	while not spots.is_empty():
		var k := rng.randi() % spots.size()
		var t: Tile = spots[k]
		spots.remove_at(k)
		if t.resource == "":
			t.resource = resource_id
			return


static func _ensure_resource_near(map: HexMap, start: Vector2i, resource_id: String, radius: int, rng: RandomNumberGenerator) -> void:
	var res: Dictionary = Defs.resources[resource_id]
	var spots: Array = []
	for t in map.tiles_within(start, radius):
		if t.resource == resource_id:
			return
		if Hex.distance(t.coord, start) >= 2 and t.resource == "" and _resource_fits(res, t):
			spots.append(t)
	if spots.is_empty():
		# Make a spot: turn a nearby plain land tile into something that fits.
		for t in map.tiles_within(start, radius):
			if Hex.distance(t.coord, start) >= 2 and t.is_passable_land() and t.resource == "":
				t.terrain = res.terrains[0]
				t.elevation = res.get("elevations", ["flat"])[0]
				t.feature = ""
				spots.append(t)
				break
	if not spots.is_empty():
		spots[rng.randi() % spots.size()].resource = resource_id
