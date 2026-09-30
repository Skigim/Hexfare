class_name CityRules
extends RefCounted
## City economy: yields, growth, production, borders, worked tiles.


# --- Queries ---------------------------------------------------------------

static func growth_threshold(population: int) -> int:
	var r: Dictionary = Defs.rules.city
	var n := population - 1
	return int(r.growth_base + r.growth_per_pop * n + pow(n, r.growth_exponent))


static func border_threshold(city: City) -> int:
	var r: Dictionary = Defs.rules.city
	var n := city.border_growths
	return int(r.border_base + r.border_per_tile * n + pow(n, r.border_exponent))


static func food_upkeep(city: City) -> int:
	return city.population * int(Defs.rules.city.food_per_pop)


## Total yields of the city (before food upkeep).
static func city_yields(state: GameState, city: City) -> Dictionary:
	var r: Dictionary = Defs.rules.city
	var player := state.player(city.owner)
	var y := Yields.empty()
	Yields.add(y, center_yields(state, city))
	for c in city.worked:
		Yields.add(y, Yields.tile_yields(state.tile(c), player))
	Yields.add(y, r.base_yields)
	for k in r.pop_yields:
		y[k] += int(floor(city.population * float(r.pop_yields[k])))
	var percent := {}
	for b in city.buildings:
		var bd: Dictionary = Defs.buildings[b]
		Yields.add(y, bd.get("yields", {}))
		Yields.add(percent, bd.get("yield_percent", {}))
	for k in percent:
		y[k] = int(y[k] * (100 + percent[k]) / 100.0)
	return y


static func center_yields(state: GameState, city: City) -> Dictionary:
	var y := Yields.tile_yields(state.tile(city.coord), state.player(city.owner))
	var mins: Dictionary = Defs.rules.city.center_min_yields
	for k in mins:
		y[k] = maxi(int(y.get(k, 0)), int(mins[k]))
	return y


static func food_surplus(state: GameState, city: City) -> int:
	return int(city_yields(state, city).food) - food_upkeep(city)


static func turns_to_grow(state: GameState, city: City) -> int:
	var surplus := food_surplus(state, city)
	if surplus <= 0:
		return -1
	return maxi(1, int(ceil(float(growth_threshold(city.population) - city.food) / surplus)))


static func item_cost(kind: String, id: String) -> int:
	if kind == "unit":
		return int(Defs.units[id].cost)
	return int(Defs.buildings[id].cost)


static func item_name(kind: String, id: String) -> String:
	return Defs.units[id].name if kind == "unit" else Defs.buildings[id].name


static func purchase_cost(kind: String, id: String) -> int:
	return item_cost(kind, id) * int(Defs.rules.economy.purchase_multiplier)


static func turns_to_build(state: GameState, city: City, kind: String, id: String) -> int:
	var prod := int(city_yields(state, city).production)
	if prod <= 0:
		return -1
	var have := city.production if not city.build.is_empty() and city.build.kind == kind and city.build.id == id else 0
	return maxi(1, int(ceil(float(item_cost(kind, id) - have) / prod)))


## True if the player owns a tile with this (revealed) resource.
static func player_has_resource(state: GameState, pid: int, resource_id: String) -> bool:
	var player := state.player(pid)
	if not Yields.resource_visible(resource_id, player):
		return false
	for t in state.map.tiles:
		if t.owner == pid and t.resource == resource_id:
			return true
	return false


## Why this city can't build the item, or "" if it can.
static func build_blocker(state: GameState, city: City, kind: String, id: String) -> String:
	var player := state.player(city.owner)
	if kind == "unit":
		var ud: Dictionary = Defs.units[id]
		if not player.has_tech(ud.get("tech", "")):
			return "Requires %s" % Defs.techs[ud.tech].name
		var res: String = ud.get("requires_resource", "")
		if res != "" and not player_has_resource(state, city.owner, res):
			return "Requires %s" % Defs.resources[res].name
		return ""
	var bd: Dictionary = Defs.buildings[id]
	if not bd.get("buildable", true):
		return "Not buildable"
	if city.buildings.has(id):
		return "Already built"
	if not player.has_tech(bd.get("tech", "")):
		return "Requires %s" % Defs.techs[bd.tech].name
	return ""


## Everything the city could build now: [{kind, id}].
static func build_options(state: GameState, city: City) -> Array:
	var out: Array = []
	for id in Defs.units:
		if build_blocker(state, city, "unit", id) == "":
			out.append({"kind": "unit", "id": id})
	for id in Defs.buildings:
		if build_blocker(state, city, "building", id) == "":
			out.append({"kind": "building", "id": id})
	return out


static func upkeep(state: GameState, pid: int) -> int:
	var total := 0
	var cities := state.player_cities(pid)
	for city in cities:
		for b in city.buildings:
			total += int(Defs.buildings[b].get("upkeep", 0))
	var r: Dictionary = Defs.rules.units
	var paid_units := maxi(0, state.player_units(pid).size() - cities.size() * int(r.free_units_per_city))
	return total + paid_units * int(r.upkeep_per_unit)


## Per-turn totals for a player: {gold, science, upkeep, net_gold}.
static func player_income(state: GameState, pid: int) -> Dictionary:
	var gold := 0
	var science := 0
	for city in state.player_cities(pid):
		var y := city_yields(state, city)
		gold += int(y.gold)
		science += int(y.science)
	var up := upkeep(state, pid)
	return {"gold": gold, "science": science, "upkeep": up, "net_gold": gold - up}


# --- Founding --------------------------------------------------------------

## Why a city can't be founded at `c` by player `pid`, or "" if it can.
static func found_blocker(state: GameState, pid: int, c: Vector2i) -> String:
	var t := state.tile(c)
	if t == null or not t.is_passable_land():
		return "Cities must be on passable land"
	if t.owner != -1 and t.owner != pid:
		return "Tile belongs to another civilization"
	var min_d: int = Defs.rules.city.min_distance
	for other in state.cities.values():
		if Hex.distance(other.coord, c) < min_d:
			return "Too close to %s" % other.name
	return ""


static func next_city_name(player: Player) -> String:
	var names: Array = player.civ().cities
	var i := player.city_name_index
	player.city_name_index += 1
	if i < names.size():
		return names[i]
	return "%s %d" % [player.civ().name, i + 1]


# --- Tiles -----------------------------------------------------------------

## Gives the city the tile (if unowned or owned by the same player without a city).
static func claim_tile(state: GameState, city: City, c: Vector2i) -> bool:
	var t := state.tile(c)
	if t == null:
		return false
	if t.owner != -1 and t.owner != city.owner:
		return false
	if t.city_id != -1 and t.city_id != city.id and state.cities.has(t.city_id):
		return false
	t.owner = city.owner
	t.city_id = city.id
	return true


static func tile_score(y: Dictionary) -> int:
	return int(y.food) * 3 + int(y.production) * 2 + int(y.gold) + int(y.science) + int(y.culture)


## Picks which owned tiles the citizens work (greedy, food-leaning).
static func assign_work(state: GameState, city: City) -> void:
	var player := state.player(city.owner)
	var radius: int = Defs.rules.city.work_radius
	var candidates: Array = []
	for t in state.map.tiles_within(city.coord, radius):
		if t.coord == city.coord or t.city_id != city.id or not t.is_workable():
			continue
		if state.has_enemy_unit(t.coord, city.owner):
			continue
		var score := tile_score(Yields.tile_yields(t, player))
		candidates.append({"coord": t.coord, "score": score * 100 - Hex.distance(t.coord, city.coord)})
	candidates.sort_custom(func(a, b): return a.score > b.score)
	city.worked.clear()
	for i in mini(city.population, candidates.size()):
		city.worked.append(candidates[i].coord)


## Picks the best unowned tile next to the city's borders; returns Hex.NONE if none.
static func best_expansion_tile(state: GameState, city: City) -> Vector2i:
	var player := state.player(city.owner)
	var radius: int = Defs.rules.city.work_radius
	var best := Hex.NONE
	var best_score := -INF
	for t in state.map.tiles_within(city.coord, radius):
		if t.owner != -1:
			continue
		var touches := false
		for n in state.map.neighbors(t.coord):
			if n.city_id == city.id:
				touches = true
				break
		if not touches:
			continue
		var score := float(tile_score(Yields.tile_yields(t, player)))
		if t.resource != "":
			score += 4.0
		score -= Hex.distance(t.coord, city.coord) * 1.5
		score += (t.variant % 7) * 0.01  # stable tie-break
		if score > best_score:
			best_score = score
			best = t.coord
	return best


# --- Turn processing -------------------------------------------------------

## End-of-turn processing for one city: growth, production, border growth.
static func process_turn(game: Game, city: City) -> void:
	var state := game.state
	var y := city_yields(state, city)

	# Food and growth
	city.food += int(y.food) - food_upkeep(city)
	var threshold := growth_threshold(city.population)
	if city.food >= threshold:
		city.food -= threshold
		city.population += 1
		assign_work(state, city)
		game.notify(city.owner, "%s has grown to size %d." % [city.name, city.population], city.coord)
	elif city.food < 0:
		city.food = 0
		if city.population > 1:
			city.population -= 1
			assign_work(state, city)
			game.notify(city.owner, "%s is starving and lost a citizen!" % city.name, city.coord)

	# Production
	city.production += int(y.production)
	if not city.build.is_empty():
		var cost := item_cost(city.build.kind, city.build.id)
		if city.production >= cost:
			if _complete_build(game, city):
				city.production -= cost
				city.build = {}
			else:
				city.production = cost

	# Culture and borders
	city.culture += int(y.culture)
	var needed := border_threshold(city)
	if city.culture >= needed:
		var c := best_expansion_tile(state, city)
		if c != Hex.NONE and claim_tile(state, city, c):
			city.culture -= needed
			city.border_growths += 1
			assign_work(state, city)
			game.borders_changed.emit()
		else:
			city.culture = needed


static func _complete_build(game: Game, city: City) -> bool:
	var state := game.state
	var kind: String = city.build.kind
	var id: String = city.build.id
	if build_blocker(state, city, kind, id) != "":
		game.notify(city.owner, "%s can no longer build %s." % [city.name, item_name(kind, id)], city.coord)
		city.build = {}
		return false
	if kind == "building":
		city.buildings[id] = true
		game.notify(city.owner, "%s completed the %s." % [city.name, item_name(kind, id)], city.coord)
		game.city_changed.emit(city)
		return true
	var ud: Dictionary = Defs.units[id]
	var pop_cost := int(ud.get("pop_cost", 0))
	if pop_cost > 0 and city.population <= pop_cost:
		game.notify(city.owner, "%s must grow before it can finish a %s." % [city.name, ud.name], city.coord)
		return false
	var spawn := spawn_tile(state, city, id)
	if spawn == Hex.NONE:
		game.notify(city.owner, "No room near %s for a new %s." % [city.name, ud.name], city.coord)
		return false
	if pop_cost > 0:
		city.population -= pop_cost
		assign_work(state, city)
	game.create_unit(id, city.owner, spawn)
	game.notify(city.owner, "%s trained a %s." % [city.name, ud.name], spawn)
	return true


## Where a unit of `unit_type` built in `city` appears, or Hex.NONE.
static func spawn_tile(state: GameState, city: City, unit_type: String) -> Vector2i:
	var military: bool = Defs.units[unit_type].get("class", "") != "civilian"
	var options: Array = [city.coord]
	options.append_array(Hex.neighbors(city.coord))
	for c in options:
		var t := state.tile(c)
		if t == null or not t.is_passable_land() or state.has_enemy_unit(c, city.owner):
			continue
		var other_city := state.city_at(c)
		if other_city != null and other_city.owner != city.owner:
			continue
		var taken := false
		for u in state.units_at(c):
			if u.is_military() == military:
				taken = true
				break
		if not taken:
			return c
	return Hex.NONE
