class_name AIPlayer
extends RefCounted
## Simple rule-based opponent. It acts only through the Game action API, so it obeys
## the same rules as the human, but it reads the full GameState (ignores fog of war).
##
## Per turn: pick research -> pick production -> city bombard -> units
## (ranged first, then melee, then settlers). Military units are either city
## garrisons or part of a field army that attacks the nearest enemy city once
## it is big enough.

const BUILDING_PRIORITY: Array[String] = ["monument", "granary", "library", "market", "workshop", "walls", "temple", "university"]
const TECH_PREFERENCE := {
	"bronze_working": 3, "archery": 3, "pottery": 2, "mining": 2, "writing": 2,
	"currency": 2, "iron_working": 2, "mathematics": 1,
}
const ARMY_SIZE := 3


static func take_turn(game: Game, player: Player) -> void:
	var state := game.state
	if not player.alive or state.game_over:
		return
	_choose_research(game, player)
	_assign_garrisons(state, player)
	_manage_cities(game, player)
	_city_attacks(game, player)
	var ctx := _war_context(state, player)
	var units := state.player_units(player.id)
	units.sort_custom(func(a, b): return _unit_order(a) < _unit_order(b))
	for u in units:
		if state.game_over:
			return
		if not state.units.has(u.id) or u.owner != player.id:
			continue
		if u.is_civilian():
			_act_settler(game, player, u)
		else:
			_act_military(game, player, u, ctx)
	_manage_cities(game, player)


static func _unit_order(u: Unit) -> int:
	if u.is_civilian():
		return 2
	return 0 if u.is_ranged() else 1


# --- Research & production -------------------------------------------------

static func _choose_research(game: Game, player: Player) -> void:
	if player.research != "":
		return
	var best := ""
	var best_score := -INF
	for t in TechRules.available(player):
		var score: float = -float(Defs.techs[t].cost) + TECH_PREFERENCE.get(t, 0) * 10.0 + game.state.rng.randf() * 8.0
		if score > best_score:
			best_score = score
			best = t
	if best != "":
		game.set_research(player.id, best)


static func _manage_cities(game: Game, player: Player) -> void:
	var state := game.state
	for city in state.player_cities(player.id):
		if city.build.is_empty():
			var choice := _choose_build(game, player, city)
			if not choice.is_empty():
				game.set_production(city.id, choice.kind, choice.id)
		_maybe_purchase(game, player, city)


static func _choose_build(game: Game, player: Player, city: City) -> Dictionary:
	var state := game.state
	var options := CityRules.build_options(state, city)
	var available := {}
	for o in options:
		available[o.id] = o.kind
	var cities := state.player_cities(player.id).size()
	var military := 0
	var settlers := 0
	for u in state.player_units(player.id):
		if u.is_military():
			military += 1
		elif u.has_ability("found_city"):
			settlers += 1
	for c in state.player_cities(player.id):
		if c.build.get("id", "") == "settler":
			settlers += 1

	var threat := _enemies_near(state, player.id, city.coord, 4)
	if threat > 0 and _friends_near(state, player.id, city.coord, 2) <= threat:
		var defender := _best_military(state, city, options)
		if defender != "":
			return {"kind": "unit", "id": defender}

	var can_grow := city.population >= 2 or CityRules.food_surplus(state, city) >= 2
	if available.has("settler") and can_grow and settlers < 2 and cities + settlers < _target_city_count(state) and military >= mini(cities, 3):
		return {"kind": "unit", "id": "settler"}

	# Stay solvent: going broke disbands units, so everything past a minimal
	# garrison has to fit in the budget.
	var budget := _budget(state, player)
	if military < cities + 2 + state.turn / 20 and (budget > 0 or military < cities):
		var unit_id := _best_military(state, city, options)
		if unit_id != "":
			return {"kind": "unit", "id": unit_id}

	for b in _building_order(budget):
		if available.get(b, "") == "building" and int(Defs.buildings[b].get("upkeep", 0)) < budget:
			return {"kind": "building", "id": b}

	if budget > 0:
		var fallback := _best_military(state, city, options)
		if fallback != "":
			return {"kind": "unit", "id": fallback}
	return {}  # nothing affordable: production banks until something is


## Net gold per turn, minus the upkeep of buildings already in production.
static func _budget(state: GameState, player: Player) -> int:
	var net := int(CityRules.player_income(state, player.id).net_gold)
	for c in state.player_cities(player.id):
		if c.build.get("kind", "") == "building":
			net -= int(Defs.buildings[c.build.id].get("upkeep", 0))
	return net


## Buildings in the order the AI wants them; the market jumps the queue when money is tight.
## Buildings missing from BUILDING_PRIORITY (e.g. newly added to the data) go last, cheapest first.
static func _building_order(budget: int) -> Array[String]:
	var order: Array[String] = []
	if budget < 3:
		order.append("market")
	for b in BUILDING_PRIORITY:
		if not order.has(b):
			order.append(b)
	var extra: Array = Defs.buildings.keys().filter(func(b): return not order.has(b))
	extra.sort_custom(func(a, b): return int(Defs.buildings[a].cost) < int(Defs.buildings[b].cost))
	for b in extra:
		order.append(b)
	return order


static func _best_military(state: GameState, city: City, options: Array) -> String:
	var melee := 0
	var ranged := 0
	for u in state.player_units(city.owner):
		if u.is_military():
			if u.is_ranged():
				ranged += 1
			else:
				melee += 1
	var want_ranged := ranged * 2 < melee
	var best := ""
	var best_score := -1.0
	for o in options:
		if o.kind != "unit":
			continue
		var d: Dictionary = Defs.units[o.id]
		if d.get("class", "") == "civilian":
			continue
		var power := float(maxi(int(d.get("strength", 0)), int(d.get("ranged_strength", 0))))
		if (int(d.get("range", 0)) > 0) == want_ranged:
			power *= 1.3
		power += state.rng.randf() * 2.0
		if power > best_score:
			best_score = power
			best = o.id
	return best


static func _maybe_purchase(game: Game, player: Player, city: City) -> void:
	if city.build.is_empty():
		return
	var kind: String = city.build.kind
	var id: String = city.build.id
	var cost := CityRules.purchase_cost(kind, id)
	var urgent := kind == "unit" and id != "settler" and _enemies_near(game.state, player.id, city.coord, 3) > 0
	if (urgent or player.gold > cost + 150) and game.can_purchase(city, kind, id):
		game.purchase(city.id, kind, id)


static func _target_city_count(state: GameState) -> int:
	var land := 0
	for t in state.map.tiles:
		if t.is_passable_land():
			land += 1
	var alive := state.players.filter(func(p): return p.alive).size()
	return clampi(land / maxi(1, alive) / 14, 3, 10)


static func _city_attacks(game: Game, player: Player) -> void:
	var state := game.state
	var reach: int = Defs.rules.city.ranged_range
	for city in state.player_cities(player.id):
		if not game.city_can_attack(city):
			continue
		var best: Unit = null
		for c in Hex.within(city.coord, reach):
			var u := state.military_at(c)
			if u != null and u.owner != player.id and (best == null or u.hp < best.hp):
				best = u
		if best != null:
			game.city_attack(city.id, best.coord)


# --- Settlers --------------------------------------------------------------

static func _act_settler(game: Game, player: Player, u: Unit) -> void:
	var state := game.state
	if not u.has_ability("found_city"):
		return
	if state.player_cities(player.id).is_empty() and CityRules.found_blocker(state, player.id, u.coord) == "":
		game.found_city(u.id)
		return
	var target := _ai_coord(u, "target")
	if target == Hex.NONE or CityRules.found_blocker(state, player.id, target) != "" or state.has_enemy_unit(target, player.id):
		target = _best_city_site(state, player, u)
		_set_ai_coord(u, "target", target)
	if target == Hex.NONE:
		game.skip_unit(u.id)
		return
	if u.coord != target and not game.move_unit(u.id, target):
		_set_ai_coord(u, "target", Hex.NONE)
		return
	if state.units.has(u.id) and u.coord == target and u.moves_left > 0:
		game.found_city(u.id)


static func _best_city_site(state: GameState, player: Player, u: Unit) -> Vector2i:
	var result := Pathfinder.search(state, u, Hex.NONE, u.max_moves() * 8)
	var best := Hex.NONE
	var best_score := -INF
	for c in result.g:
		if CityRules.found_blocker(state, player.id, c) != "" or state.has_enemy_unit(c, player.id):
			continue
		var score := site_value(state, player, c) - Pathfinder.turns_for(u, result.g[c]) * 2.5
		if score > best_score:
			best_score = score
			best = c
	return best


static func site_value(state: GameState, player: Player, c: Vector2i) -> float:
	var v := 0.0
	for t in state.map.tiles_within(c, 2):
		if t.owner != -1 and t.owner != player.id:
			continue
		if t.city_id != -1:
			v -= 0.5
			continue
		var y := Yields.tile_yields(t, player)
		v += y.food * 1.5 + y.production * 1.2 + y.gold * 0.6
		if t.resource != "":
			v += 1.5
	if state.tile(c).elevation == "hills":
		v += 2.0
	for n in state.map.neighbors(c):
		if n.is_water():
			v += 1.0
			break
	return v


# --- Military --------------------------------------------------------------

static func _assign_garrisons(state: GameState, player: Player) -> void:
	var taken := {}
	for u in state.player_units(player.id):
		if u.ai.get("role", "") != "garrison":
			continue
		var cid := int(u.ai.get("city", -1))
		var city := state.get_city(cid)
		if city == null or city.owner != player.id or taken.has(cid):
			u.ai.erase("role")
			u.ai.erase("city")
		else:
			taken[cid] = true
	for city in state.player_cities(player.id):
		if taken.has(city.id):
			continue
		var best: Unit = null
		var best_d := 1 << 20
		for u in state.player_units(player.id):
			if not u.is_military() or u.ai.get("role", "") == "garrison":
				continue
			var d := Hex.distance(u.coord, city.coord)
			if d < best_d:
				best_d = d
				best = u
		if best != null:
			best.ai["role"] = "garrison"
			best.ai["city"] = city.id
			taken[city.id] = true


## Picks the enemy city the field army should march on, and whether it's ready.
static func _war_context(state: GameState, player: Player) -> Dictionary:
	var home := state.capital_of(player.id)
	var mine := state.player_cities(player.id)
	var origin: Vector2i = home.coord if home != null else (mine[0].coord if not mine.is_empty() else Hex.NONE)
	var target: City = null
	var best_d := 1 << 20
	if origin != Hex.NONE:
		for city in state.cities.values():
			if city.owner == player.id:
				continue
			var d := Hex.distance(origin, city.coord)
			if d < best_d:
				best_d = d
				target = city
	var field := 0
	for u in state.player_units(player.id):
		if u.is_military() and u.ai.get("role", "") != "garrison" and u.hp > 50:
			field += 1
	var staging := Hex.NONE
	if target != null:
		var closest := 1 << 20
		for city in mine:
			var d := Hex.distance(city.coord, target.coord)
			if d < closest:
				closest = d
				staging = city.coord
	return {"target": target, "ready": field >= ARMY_SIZE, "staging": staging}


static func _act_military(game: Game, player: Player, u: Unit, ctx: Dictionary) -> void:
	var state := game.state
	if u.ai.get("role", "") == "garrison":
		_act_garrison(game, player, u)
		return
	if u.hp < 45 and _retreat(game, player, u):
		return
	if _try_attack(game, player, u):
		return
	var target: City = ctx.target
	if target != null and state.cities.has(target.id) and target.owner != player.id:
		if ctx.ready:
			var stop := u.attack_range() if u.is_ranged() else 1
			if _approach(game, u, target.coord, stop):
				_try_attack(game, player, u)
				return
		elif ctx.staging != Hex.NONE and Hex.distance(u.coord, ctx.staging) > 2:
			if _approach(game, u, ctx.staging, 1):
				return
	if u.moves_left > 0 and not u.fortified:
		game.fortify(u.id)


static func _act_garrison(game: Game, player: Player, u: Unit) -> void:
	var city := game.state.get_city(int(u.ai.get("city", -1)))
	if city == null:
		return
	if u.coord != city.coord:
		if not game.move_unit(u.id, city.coord):
			_approach(game, u, city.coord, 1)
		return
	if u.is_ranged():
		_try_attack(game, player, u)
	if game.state.units.has(u.id) and not u.fortified and u.moves_left > 0:
		game.fortify(u.id)


## Attacks the most attractive target reachable this turn. Returns true if it attacked.
static func _try_attack(game: Game, player: Player, u: Unit) -> bool:
	var state := game.state
	if u.moves_left <= 0 or u.has_attacked:
		return false
	var reach := u.attack_range() if u.is_ranged() else u.moves_left + 1
	var best := Hex.NONE
	var best_value := -INF
	for c in Hex.within(u.coord, reach):
		if c == u.coord or not state.map.in_bounds(c):
			continue
		var enemy_civilian := state.civilian_at(c)
		if enemy_civilian != null and enemy_civilian.owner != player.id and state.military_at(c) == null and state.city_at(c) == null and not u.is_ranged():
			var path := Pathfinder.find_path(state, u, c)
			if not path.is_empty() and path.size() <= u.moves_left:
				best = c
				best_value = 1000.0
				break
		var info := Combat.preview(state, u, c)
		if info.is_empty():
			continue
		var value := _attack_value(state, u, info)
		if value > best_value:
			best_value = value
			best = c
	if best == Hex.NONE or best_value <= 0.0:
		return false
	if best_value >= 1000.0:
		return game.move_unit(u.id, best)
	if u.is_ranged():
		return game.attack(u.id, best)
	return game.move_and_attack(u.id, best) and u.has_attacked


static func _attack_value(state: GameState, u: Unit, info: Dictionary) -> float:
	var dealt: int = info.damage_to_defender
	var taken: int = info.damage_to_attacker
	if u.hp - taken <= 10:
		return -1.0
	if info.defender_kind == "city":
		var city := state.get_city(info.defender_city_id)
		if u.can_capture_cities() and city.hp <= dealt:
			return 500.0
		if u.is_ranged():
			return 40.0 + dealt
		return (dealt - taken) + 10.0 if u.hp - taken > 40 else -1.0
	var d := state.get_unit(info.defender_unit_id)
	if dealt >= d.hp:
		return 200.0 + d.def().cost
	if u.is_ranged():
		return 20.0 + dealt
	return float(dealt - taken) + 5.0


static func _retreat(game: Game, player: Player, u: Unit) -> bool:
	var state := game.state
	var here := state.city_at(u.coord)
	if here != null and here.owner == player.id:
		if not u.fortified:
			game.fortify(u.id)
		return true
	var best: City = null
	var best_d := 1 << 20
	for city in state.player_cities(player.id):
		var d := Hex.distance(u.coord, city.coord)
		if d < best_d and not Pathfinder.blocked_by_friend(state, u, city.coord):
			best_d = d
			best = city
	if best == null:
		return false
	return game.move_unit(u.id, best.coord)


## Moves toward a free tile within `stop` of `target`. Returns false if already there or stuck.
static func _approach(game: Game, u: Unit, target: Vector2i, stop: int) -> bool:
	var state := game.state
	if Hex.distance(u.coord, target) <= stop:
		return false
	var spots: Array = []
	for c in Hex.ring(target, stop):
		var t := state.tile(c)
		if t == null or not t.is_passable_land() or state.has_enemy_unit(c, u.owner):
			continue
		if Pathfinder.blocked_by_friend(state, u, c):
			continue
		var city := state.city_at(c)
		if city != null and city.owner != u.owner:
			continue
		spots.append(c)
	spots.sort_custom(func(a, b): return Hex.distance(a, u.coord) < Hex.distance(b, u.coord))
	for i in mini(3, spots.size()):
		if game.move_unit(u.id, spots[i]):
			return true
	return false


# --- AI memory helpers (stored JSON-safe so saves round-trip) ---------------

static func _ai_coord(u: Unit, key: String) -> Vector2i:
	var v: Variant = u.ai.get(key)
	if v is Array and v.size() == 2:
		return Vector2i(int(v[0]), int(v[1]))
	return Hex.NONE


static func _set_ai_coord(u: Unit, key: String, c: Vector2i) -> void:
	if c == Hex.NONE:
		u.ai.erase(key)
	else:
		u.ai[key] = [c.x, c.y]


static func _enemies_near(state: GameState, pid: int, c: Vector2i, radius: int) -> int:
	var n := 0
	for u in state.units.values():
		if u.owner != pid and u.is_military() and Hex.distance(u.coord, c) <= radius:
			n += 1
	return n


static func _friends_near(state: GameState, pid: int, c: Vector2i, radius: int) -> int:
	var n := 0
	for u in state.units.values():
		if u.owner == pid and u.is_military() and Hex.distance(u.coord, c) <= radius:
			n += 1
	return n
