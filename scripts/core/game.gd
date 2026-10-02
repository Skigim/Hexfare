class_name Game
extends RefCounted
## The rules engine's public API. The UI and the AI both drive the game only through
## these methods, and observe it through the signals.
##
## Players PLAN with orders (issue_order and the helpers below), then submit. When every
## human has submitted, the AI plans and TurnResolver resolves all players' orders at once.
## Planning never changes the world; only resolution does.

signal changed                                   ## Something changed; views should refresh.
signal unit_created(unit: Unit)
signal unit_removed(unit: Unit)
signal combat_resolved(result: Dictionary)
signal city_founded(city: City)
signal city_captured(city: City, old_owner: int)
signal city_changed(city: City)
signal borders_changed
signal tech_learned(player: Player, tech_id: String)
signal turn_started(player: Player)              ## A new planning phase began for this human.
signal turn_resolved(events: Array)              ## Plain-data events of the resolution, by tick.
signal notified(entry: Dictionary)               ## {turn, player, text, coord}
signal game_ended(winner: int, victory_type: String)

var state: GameState
var log_entries: Array = []  # notifications, newest last

# Resolution bookkeeping (valid while a turn resolves).
var _resolving := false
var _tick := 0
var _dirty := false                 # something visible changed during this tick
var _events: Array = []
var _elim_pending: Dictionary = {}  # player id -> true; checked at the end of each tick
var _science_winners: Array = []    # players that finished the last tech this turn


# --- Setup -----------------------------------------------------------------

## settings: {width, height, players, seed, human (bool)}
static func new_game(settings: Dictionary) -> Game:
	Defs.ensure_loaded()
	var game := Game.new()
	var s := GameState.new()
	game.state = s
	s.settings = settings.duplicate()
	var seed_value: int = settings.get("seed", 1)
	s.rng.seed = seed_value
	var count: int = mini(int(settings.get("players", 4)), Defs.civs.size())
	var gen := MapGenerator.generate(int(settings.get("width", 44)), int(settings.get("height", 28)), seed_value, count)
	s.map = gen.map
	var starts: Array = gen.starts
	count = mini(count, starts.size())
	var civ_order: Array = range(Defs.civs.size())
	for i in count:
		var p := Player.new()
		p.id = i
		p.civ_index = civ_order[i]
		p.name = Defs.civs[p.civ_index].name
		p.color = Color.html(Defs.civs[p.civ_index].color)
		p.is_human = i == 0 and settings.get("human", true)
		p.gold = int(Defs.rules.start.gold)
		s.players.append(p)
		for unit_type in Defs.rules.start.units:
			var u := game.create_unit(unit_type, p.id, starts[i])
			if u == null:
				game.create_unit(unit_type, p.id, _free_neighbor(s, starts[i], unit_type))
	for p in s.players:
		Visibility.update(s, p)
	return game


static func _free_neighbor(s: GameState, c: Vector2i, unit_type: String) -> Vector2i:
	var military: bool = Defs.units[unit_type].get("class", "") != "civilian"
	for n in Hex.neighbors(c):
		var t := s.tile(n)
		if t == null or not t.is_passable_land():
			continue
		var taken := false
		for u in s.units_at(n):
			taken = taken or u.is_military() == military
		if not taken:
			return n
	return c


## Starts the first planning phase. Without a human (simulations) call run_ai_turns() afterwards.
func start() -> void:
	_reset_budgets()
	for p in state.players:
		Visibility.update(state, p)
	var human := state.human_player()
	if human != null:
		turn_started.emit(human)
	changed.emit()


func _reset_budgets() -> void:
	for u in state.units.values():
		u.moves_left = u.max_moves()
		u.acted = false


## True while the human may still plan this turn.
func is_human_turn() -> bool:
	var human := state.human_player()
	return human != null and human.alive and not human.ready and not state.game_over


# --- Notifications ---------------------------------------------------------

## "a Warrior", "an Archer".
static func article(noun: String) -> String:
	return ("an " if noun.left(1).to_lower() in ["a", "e", "i", "o", "u"] else "a ") + noun


func notify(pid: int, text: String, coord: Vector2i = Hex.NONE) -> void:
	var entry := {"turn": state.turn, "player": pid, "text": text, "coord": coord}
	log_entries.append(entry)
	if log_entries.size() > 400:
		log_entries = log_entries.slice(-300)
	notified.emit(entry)


# --- Orders (planning) -----------------------------------------------------
# Planning never changes the world: these only store intent in Player.orders, and never touch
# state.rng. Everything that changes the world happens when the turn resolves.

## Validates and stores `order` for player `pid`. Returns {"ok": bool, "reason": String}.
func issue_order(pid: int, order: Dictionary) -> Dictionary:
	var reason := validate_order(pid, order)
	if reason != "":
		return {"ok": false, "reason": reason}
	state.player(pid).set_order(order.duplicate(true))
	changed.emit()
	return {"ok": true, "reason": ""}


## Removes a planned order. Units default to their "act" slot.
func cancel_order(pid: int, kind: String, id: int, slot: String = Orders.SLOT_ACT) -> bool:
	var p := state.player(pid)
	if p == null or p.ready or state.game_over:
		return false
	if not p.remove_order(kind, id, slot):
		return false
	changed.emit()
	return true


## Removes every planned order of `pid`.
func clear_orders(pid: int) -> void:
	var p := state.player(pid)
	if p != null and not p.ready and not state.game_over:
		p.clear_orders()
		changed.emit()


## The orders `viewer` may see for player `pid`: only your own.
func orders_of(pid: int, viewer: int) -> Array:
	var p := state.player(pid)
	if p == null or pid != viewer:
		return []
	return p.sorted_orders()


## The planned "act" order of a unit, or {}.
func unit_order(u: Unit) -> Dictionary:
	return state.player(u.owner).unit_order(u.id)


## True if the unit is idle and the player should give it an order this turn.
func needs_orders(u: Unit) -> bool:
	return not u.fortified and not u.sleeping and unit_order(u).is_empty()


## "" if `order` is legal for `pid` right now, otherwise the reason it is not.
func validate_order(pid: int, order: Dictionary) -> String:
	var p := state.player(pid)
	if p == null or not p.alive:
		return "no such player"
	if state.game_over:
		return "the game is over"
	if p.ready:
		return "turn already submitted"
	if not (order.has("kind") and order.has("id") and order.has("slot") and order.has("type")):
		return "malformed order"
	match order.kind:
		Orders.KIND_UNIT:
			return _validate_unit_order(p, order)
		Orders.KIND_CITY:
			return _validate_city_order(p, order)
	return "unknown actor"


func _validate_unit_order(p: Player, order: Dictionary) -> String:
	var u := state.get_unit(int(order.id))
	if u == null or u.owner != p.id:
		return "not your unit"
	if order.slot != Orders.SLOT_ACT:
		return "bad slot"
	match order.type:
		"move":
			var to := Orders.coord(order, "to")
			if not state.map.in_bounds(to):
				return "off the map"
			if to == u.coord:
				return "already there"
			if plan_path(u, to).is_empty():
				return "no path"
		"attack":
			if not u.is_ranged():
				return "only ranged units attack by order"
			var at := Orders.coord(order, "at")
			var dist := Hex.distance(u.coord, at)
			if not state.map.in_bounds(at) or dist < 1 or dist > u.attack_range():
				return "out of range"
			if Combat.preview(state, u, at).is_empty():
				return "nothing to attack there"
		"found_city":
			if not u.has_ability("found_city"):
				return "cannot found cities"
			var at := Orders.coord(order, "at")
			if not state.map.in_bounds(at):
				return "off the map"
			var blocker := CityRules.found_blocker(state, u.owner, at)
			if blocker != "":
				return blocker
			if at != u.coord and plan_path(u, at).is_empty():
				return "no path"
		"fortify":
			if not u.is_military():
				return "only military units fortify"
		"sleep", "wake", "disband":
			pass
		_:
			return "unknown order"
	return ""


func _validate_city_order(p: Player, order: Dictionary) -> String:
	var city := state.get_city(int(order.id))
	if city == null or city.owner != p.id:
		return "not your city"
	if order.slot != order.type:
		return "bad slot"
	match order.type:
		"bombard":
			var at := Orders.coord(order, "at")
			if not state.map.in_bounds(at) or Hex.distance(city.coord, at) > int(Defs.rules.city.ranged_range):
				return "out of range"
			if Combat.preview_city_attack(state, city, at).is_empty():
				return "nothing to bombard there"
		"purchase":
			var kind: String = order.get("item_kind", "")
			var id: String = order.get("item_id", "")
			if not can_purchase(city, kind, id, _queued_purchase_cost(p, city.id)):
				return "cannot buy that"
		_:
			return "unknown order"
	return ""


## Gold already committed to other cities' queued purchases.
func _queued_purchase_cost(p: Player, except_city: int) -> int:
	var total := 0
	for o in p.orders:
		if o.kind == Orders.KIND_CITY and o.type == "purchase" and int(o.id) != except_city:
			total += CityRules.purchase_cost(o.item_kind, o.item_id)
	return total


## Path for planning `u` to `to` with a full movement budget: routes around stationary friendly
## units, and may end on an enemy-held tile for melee units (an assault move). [] if impossible.
func plan_path(u: Unit, to: Vector2i) -> Array:
	var probe := plan_probe(u)
	var blocked := _stationary_friends(u)
	var city := state.city_at(to)
	var enemy_there := (state.military_at(to) != null and state.is_enemy(state.military_at(to).owner, u.owner)) \
			or (city != null and state.is_enemy(city.owner, u.owner))
	if enemy_there:
		if not u.can_attack_on_contact():
			return []
		return Pathfinder.find_attack_path(state, probe, to, blocked)
	var moving_friend := false
	for other in state.units_at(to):
		if other != u and other.owner == u.owner and other.is_military() == u.is_military() and _is_moving(other):
			moving_friend = true
	return Pathfinder.find_path(state, probe, to, blocked, moving_friend)


## A copy of `u` with a full movement budget, so planning does not depend on this turn's budget.
func plan_probe(u: Unit) -> Unit:
	var probe := Unit.new()
	probe.id = u.id
	probe.type = u.type
	probe.owner = u.owner
	probe.coord = u.coord
	probe.hp = u.hp
	probe.moves_left = u.max_moves()
	probe.fortified = u.fortified
	return probe


## Tiles holding same-kind friendly units that are not moving: planned paths avoid them.
func _stationary_friends(u: Unit) -> Dictionary:
	var out := {}
	for other in state.player_units(u.owner):
		if other != u and other.is_military() == u.is_military() and not _is_moving(other):
			out[other.coord] = true
	return out


## True if `u` has a movement order that is not already complete.
func _is_moving(u: Unit) -> bool:
	var o := unit_order(u)
	if o.is_empty():
		return false
	if o.type == "move":
		return Orders.coord(o, "to") != u.coord
	if o.type == "found_city":
		return Orders.coord(o, "at") != u.coord
	return false


# --- Order helpers (for the UI and the AI) ---------------------------------
# Each returns true if the order was accepted. They plan only; nothing happens until the turn resolves.

func _order_unit(unit_id: int, order: Dictionary) -> bool:
	var u := state.get_unit(unit_id)
	return u != null and issue_order(u.owner, order).ok


## Plans a move; melee units may target an enemy tile to assault it.
func move_unit(unit_id: int, target: Vector2i) -> bool:
	return _order_unit(unit_id, Orders.move(unit_id, target))


## Ranged unit: shoot the tile `target` from where it stands.
func attack(unit_id: int, target: Vector2i) -> bool:
	return _order_unit(unit_id, Orders.attack(unit_id, target))


func found_city(unit_id: int) -> bool:
	var u := state.get_unit(unit_id)
	return u != null and issue_order(u.owner, Orders.found_city(unit_id, u.coord)).ok


func fortify(unit_id: int) -> bool:
	return _order_unit(unit_id, Orders.fortify(unit_id))


func sleep(unit_id: int) -> bool:
	return _order_unit(unit_id, Orders.sleep(unit_id))


func wake(unit_id: int) -> bool:
	return _order_unit(unit_id, Orders.wake(unit_id))


func disband(unit_id: int) -> bool:
	return _order_unit(unit_id, Orders.disband(unit_id))


## Cancels the unit's planned order (it keeps any stance it already has).
func cancel_orders(unit_id: int) -> bool:
	var u := state.get_unit(unit_id)
	return u != null and cancel_order(u.owner, Orders.KIND_UNIT, unit_id)


func city_attack(city_id: int, target: Vector2i) -> bool:
	var city := state.get_city(city_id)
	return city != null and issue_order(city.owner, Orders.bombard(city_id, target)).ok


func purchase(city_id: int, kind: String, id: String) -> bool:
	var city := state.get_city(city_id)
	return city != null and issue_order(city.owner, Orders.purchase(city_id, kind, id)).ok


# --- Units -----------------------------------------------------------------

## Server-side: puts a unit on the map. Not part of the player command surface.
func create_unit(unit_type: String, owner: int, coord: Vector2i) -> Unit:
	if Pathfinder.blocked_by_friend(state, _probe(unit_type, owner), coord):
		return null
	var u := Unit.new()
	u.id = state.new_id()
	u.type = unit_type
	u.owner = owner
	u.coord = coord
	u.hp = int(Defs.rules.units.max_hp)
	u.moves_left = 0
	u.priority = Orders.mix(state.rng.seed, u.id) % int(Defs.rules.units.priority_range) \
			+ int(Defs.units[unit_type].get("priority_bonus", 0))
	state.add_unit(u)
	_ev("unit_created", {"unit": u.id, "owner": owner, "type": unit_type, "coord": _arr(coord)})
	unit_created.emit(u)
	changed.emit()
	return u


func _probe(unit_type: String, owner: int) -> Unit:
	var u := Unit.new()
	u.id = -1
	u.type = unit_type
	u.owner = owner
	return u


func _remove_unit(u: Unit) -> void:
	state.remove_unit(u)
	var p := state.player(u.owner)
	if p != null:
		p.remove_order(Orders.KIND_UNIT, u.id, Orders.SLOT_ACT)
	unit_removed.emit(u)


# --- Resolution primitives (used by TurnResolver) ----------------------------

## A military unit entering a tile captures any enemy civilians there.
func _capture_civilians(u: Unit, c: Vector2i) -> void:
	if not u.is_military():
		return
	for other in state.units_at(c):
		if state.is_enemy(other.owner, u.owner) and other.is_civilian():
			var old_owner: int = other.owner
			state.player(old_owner).remove_order(Orders.KIND_UNIT, other.id, Orders.SLOT_ACT)
			other.owner = u.owner
			other.moves_left = 0
			other.ai = {}
			_ev("unit_captured", {"unit": other.id, "owner": u.owner, "old_owner": old_owner, "coord": _arr(c)})
			notify(u.owner, "Captured an enemy %s!" % other.display_name(), c)
			notify(old_owner, "Your %s was captured!" % other.display_name(), c)
			unit_created.emit(other)
			_check_elimination(old_owner)


func _found_city_now(u: Unit) -> void:
	var player := state.player(u.owner)
	var city := City.new()
	city.id = state.new_id()
	city.owner = u.owner
	city.original_owner = u.owner
	city.coord = u.coord
	city.name = CityRules.next_city_name(player)
	city.founded_turn = state.turn
	if state.player_cities(u.owner).is_empty():
		city.buildings["palace"] = true
	city.hp = Combat.city_max_hp(city)
	state.add_city(city)
	var center := state.tile(u.coord)
	center.feature = ""
	var neighbor_city := state.get_city(center.city_id)
	for t in state.map.tiles_within(city.coord, int(Defs.rules.city.initial_radius)):
		if t.owner == -1 or t.coord == city.coord:
			t.owner = city.owner
			t.city_id = city.id
	CityRules.assign_work(state, city)
	if neighbor_city != null:
		CityRules.assign_work(state, neighbor_city)
	_remove_unit(u)
	_dirty = true
	_ev("city_founded", {"city": city.id, "owner": city.owner, "coord": _arr(city.coord)})
	notify(player.id, "%s has been founded." % city.name, city.coord)
	city_founded.emit(city)
	borders_changed.emit()
	changed.emit()


## One melee attack by `u` on the tile `target`, applied at once (a melee unit's contact with an enemy).
## Returns false if there was nothing to attack.
func _resolve_attack(u: Unit, target: Vector2i) -> bool:
	var info := Combat.preview(state, u, target)
	if info.is_empty():
		return false
	info.merge(Combat.roll(state, info))
	info.from = u.coord
	info.target = target
	u.acted = true
	u.moves_left = 0
	u.fortified = false
	var attacker_owner := u.owner
	var defender_owner := -1
	if info.defender_kind == "city":
		var city := state.get_city(info.defender_city_id)
		defender_owner = city.owner
		city.hp = maxi(0, city.hp - int(info.to_defender))
		u.hp -= int(info.to_attacker)
		info.defender_hp = city.hp
		info.attacker_hp = u.hp
		if u.hp <= 0:
			_kill_unit(u, "destroyed attacking %s" % city.name)
		elif city.hp <= 0 and u.can_capture_cities():
			_capture_city(city, u)
		_record_attack(info, attacker_owner, defender_owner)
		combat_resolved.emit(info)
		notify(defender_owner, "%s was attacked by %s." % [city.name, article("%s %s" % [state.player(attacker_owner).name, u.display_name()])], city.coord)
	else:
		var d := state.get_unit(info.defender_unit_id)
		defender_owner = d.owner
		d.hp -= int(info.to_defender)
		u.hp -= int(info.to_attacker)
		info.defender_hp = d.hp
		info.attacker_hp = u.hp
		_record_attack(info, attacker_owner, defender_owner)
		combat_resolved.emit(info)
		var d_name := d.display_name()
		var attacker_desc := article("%s %s" % [state.player(attacker_owner).name, u.display_name()])
		if d.hp <= 0:
			_kill_unit(d, "destroyed by %s" % attacker_desc)
			notify(attacker_owner, "Your %s destroyed an enemy %s." % [u.display_name(), d_name], target)
		else:
			notify(defender_owner, "Your %s was attacked by %s (%d HP left)." % [d_name, attacker_desc, d.hp], target)
		if u.hp <= 0:
			_kill_unit(u, "destroyed attacking %s" % article(d_name))
		elif d.hp <= 0 and state.military_at(target) == null and state.city_at(target) == null:
			var from := u.coord
			state.move_unit_to(u, target)
			_ev("move", {"unit": u.id, "owner": u.owner, "from": _arr(from), "to": _arr(target)})
			_capture_civilians(u, target)
	_dirty = true
	changed.emit()
	return true


func _record_attack(info: Dictionary, attacker_owner: int, defender_owner: int) -> void:
	_ev("attack", {
		"from": _arr(info.from), "target": _arr(info.target), "ranged": info.ranged,
		"attacker_owner": attacker_owner, "defender_owner": defender_owner,
		"to_defender": int(info.to_defender), "to_attacker": int(info.to_attacker),
		"attacker_hp": int(info.attacker_hp), "defender_hp": int(info.defender_hp),
	})


## True if a city has enemy units within bombard range (used to decide whether to plan a bombardment).
func city_can_attack(city: City) -> bool:
	for c in Hex.within(city.coord, int(Defs.rules.city.ranged_range)):
		var u := state.military_at(c)
		if u != null and state.is_enemy(u.owner, city.owner):
			return true
	return false


func _kill_unit(u: Unit, reason: String) -> void:
	_ev("unit_died", {"unit": u.id, "owner": u.owner, "type": u.type, "coord": _arr(u.coord)})
	notify(u.owner, "Your %s was %s." % [u.display_name(), reason], u.coord)
	_remove_unit(u)
	_check_elimination(u.owner)


func _capture_city(city: City, conqueror: Unit) -> void:
	var old_owner := city.owner
	var new_owner := conqueror.owner
	var was_capital := city.is_capital()
	for other in state.units_at(city.coord):
		if other.owner == old_owner and other.is_military():
			_remove_unit(other)
	city.owner = new_owner
	city.population = maxi(1, city.population - 1)
	city.buildings.erase("palace")
	city.hp = int(Combat.city_max_hp(city) * float(Defs.rules.city.capture_hp_ratio))
	city.build = {}
	city.production = 0
	city.food = 0
	city.culture = 0
	state.player(old_owner).remove_order(Orders.KIND_CITY, city.id, "purchase")
	state.player(old_owner).remove_order(Orders.KIND_CITY, city.id, "bombard")
	for t in state.map.tiles:
		if t.city_id == city.id:
			t.owner = new_owner
	var from := conqueror.coord
	state.move_unit_to(conqueror, city.coord)
	_ev("move", {"unit": conqueror.id, "owner": new_owner, "from": _arr(from), "to": _arr(city.coord)})
	_ev("city_captured", {"city": city.id, "owner": new_owner, "old_owner": old_owner, "coord": _arr(city.coord)})
	_capture_civilians(conqueror, city.coord)
	CityRules.assign_work(state, city)
	if was_capital:
		_relocate_capital(old_owner)
	notify(new_owner, "You captured %s!" % city.name, city.coord)
	notify(old_owner, "%s has fallen to %s!" % [city.name, state.player(new_owner).name], city.coord)
	city_captured.emit(city, old_owner)
	borders_changed.emit()
	_check_elimination(old_owner)


func _relocate_capital(pid: int) -> void:
	var remaining := state.player_cities(pid)
	if remaining.is_empty():
		return
	remaining.sort_custom(func(a, b): return a.population > b.population)
	remaining[0].buildings["palace"] = true
	notify(pid, "The palace has moved to %s." % remaining[0].name, remaining[0].coord)


# --- Cities and research (planning intent) -----------------------------------

## Chooses what a city builds. Pure intent: nothing is spent until production completes.
## `pid` (optional) restricts the change to that player's own cities.
func set_production(city_id: int, kind: String, id: String, pid: int = -1) -> bool:
	var city := state.get_city(city_id)
	if city == null or state.game_over or (pid >= 0 and city.owner != pid):
		return false
	if state.player(city.owner).ready:
		return false
	if CityRules.build_blocker(state, city, kind, id) != "":
		return false
	city.build = {"kind": kind, "id": id}
	city_changed.emit(city)
	changed.emit()
	return true


## `committed` is gold already promised to other queued purchases.
func can_purchase(city: City, kind: String, id: String, committed: int = 0) -> bool:
	if CityRules.build_blocker(state, city, kind, id) != "":
		return false
	if state.player(city.owner).gold - committed < CityRules.purchase_cost(kind, id):
		return false
	if kind == "unit":
		var pop_cost := int(Defs.units[id].get("pop_cost", 0))
		if pop_cost > 0 and city.population <= pop_cost:
			return false
		return CityRules.spawn_tile(state, city, id) != Hex.NONE
	return true


## Carries out a purchase order during resolution.
func _do_purchase(city: City, kind: String, id: String) -> bool:
	if city.owner < 0 or not can_purchase(city, kind, id):
		return false
	var player := state.player(city.owner)
	player.gold -= CityRules.purchase_cost(kind, id)
	if kind == "building":
		city.buildings[id] = true
		if city.build.get("id", "") == id:
			city.build = {}
	else:
		var pop_cost := int(Defs.units[id].get("pop_cost", 0))
		if pop_cost > 0:
			city.population -= pop_cost
			CityRules.assign_work(state, city)
		create_unit(id, city.owner, CityRules.spawn_tile(state, city, id))
	notify(player.id, "Purchased %s in %s." % [CityRules.item_name(kind, id), city.name], city.coord)
	city_changed.emit(city)
	changed.emit()
	return true


func set_research(pid: int, tech_id: String) -> bool:
	var p := state.player(pid)
	if p == null or p.ready or not TechRules.set_research(p, tech_id):
		return false
	changed.emit()
	return true


func learn_tech(player: Player, tech_id: String) -> void:
	player.techs[tech_id] = true
	notify(player.id, "Researched %s." % Defs.techs[tech_id].name)
	for res in TechRules.unlocks(tech_id).resources:
		notify(player.id, "%s can now be seen on the map." % Defs.resources[res].name)
	tech_learned.emit(player, tech_id)
	if Defs.rules.victory.get("science", true) and TechRules.has_all(player):
		if _resolving:
			_science_winners.append(player.id)
		else:
			_end_game(player.id, "science")


# --- Turn flow -------------------------------------------------------------

## Decisions the player must make before ending the turn: {"kind": "research"|"production", ...}
func pending_decision(pid: int) -> Dictionary:
	var p := state.player(pid)
	if p.research == "" and not TechRules.available(p).is_empty():
		return {"kind": "research"}
	for city in state.player_cities(pid):
		if city.build.is_empty():
			return {"kind": "production", "city_id": city.id}
	return {}


## Locks in `pid`'s orders. When every human has submitted, the AI plans and the turn resolves.
func submit_turn(pid: int) -> bool:
	var p := state.player(pid)
	if p == null or not p.alive or p.ready or state.game_over:
		return false
	p.ready = true
	changed.emit()
	_try_resolve()
	return true


## Takes a submission back, as long as the turn has not resolved yet.
func unsubmit_turn(pid: int) -> bool:
	var p := state.player(pid)
	if p == null or not p.ready or state.game_over:
		return false
	p.ready = false
	changed.emit()
	return true


## Submits the human's orders (single-player convenience).
func end_turn() -> void:
	var human := state.human_player()
	if human != null:
		submit_turn(human.id)


func _try_resolve() -> void:
	for p in state.players:
		if p.alive and p.is_human and not p.ready:
			return
	resolve_turn()


## For simulations/tests with no human: AI players plan and resolve until `last_turn` has finished.
func run_ai_turns(last_turn: int) -> void:
	var guard := 0
	while not state.game_over and state.turn <= last_turn and guard < 100000:
		resolve_turn()
		guard += 1


func _plan_ai_players() -> void:
	for p in state.players:
		if p.alive and not p.is_human and not p.ready:
			AIPlayer.plan_turn(self, p)
			p.ready = true


## Lets the AI plan, then resolves everyone's orders at once. Returns the events by tick.
func resolve_turn() -> Array:
	if state.game_over:
		return []
	_plan_ai_players()
	_begin_resolution()
	var resolver := TurnResolver.new(self)
	resolver.run_ticks()
	resolver.run_economy()
	_end_resolution()
	var events := _events
	turn_resolved.emit(events)
	var human := state.human_player()
	if human != null and human.alive and not state.game_over:
		turn_started.emit(human)
	changed.emit()
	return events


## Test hook: only the movement/combat ticks (no economy, healing or turn rollover).
func resolve_ticks() -> Array:
	_begin_resolution()
	TurnResolver.new(self).run_ticks()
	_resolving = false
	return _events


func _begin_resolution() -> void:
	_resolving = true
	_events = []
	_elim_pending.clear()
	_science_winners.clear()
	_tick = 0
	for u in state.units.values():
		u.moves_left = u.max_moves()


## Healing, budget refill, clearing submissions, advancing the clock, and deciding victory.
func _end_resolution() -> void:
	var r: Dictionary = Defs.rules.units
	var ids: Array = state.units.keys()
	ids.sort()
	for uid in ids:
		var u: Unit = state.units[uid]
		if not u.acted:
			u.hp = mini(int(r.max_hp), u.hp + _heal_amount(u))
		u.acted = false
		u.moves_left = u.max_moves()
	for city in state.cities.values():
		city.has_attacked = false
		city.hp = mini(Combat.city_max_hp(city), city.hp + int(Defs.rules.city.heal_per_turn))
	for p in state.players:
		p.ready = false
		if not p.alive:
			p.clear_orders()
	state.turn += 1
	state.time += int(Defs.rules.turn.seconds)
	for p in state.players:
		if p.alive:
			Visibility.update(state, p)
	_resolving = false
	_decide_victory()


func _heal_amount(u: Unit) -> int:
	var r: Dictionary = Defs.rules.units
	var city := state.city_at(u.coord)
	if city != null and city.owner == u.owner:
		return int(r.heal_city)
	if state.tile(u.coord).owner == u.owner:
		return int(r.heal_friendly)
	return int(r.heal_field)


## One player's income, city processing, science and fog for the economy phase.
func _economy_for(p: Player) -> void:
	if not p.alive:
		return
	var income := CityRules.player_income(state, p.id)
	for city in state.player_cities(p.id):
		CityRules.process_turn(self, city)
	p.gold += int(income.net_gold)
	if p.gold < 0:
		_bankrupt(p)
	TechRules.add_science(self, p, int(income.science))
	Visibility.update(state, p)


func _bankrupt(p: Player) -> void:
	var units := state.player_units(p.id).filter(func(u): return u.is_military())
	if not units.is_empty():
		units.sort_custom(func(a, b): return a.def().cost < b.def().cost or (a.def().cost == b.def().cost and a.id < b.id))
		var u: Unit = units[0]
		notify(p.id, "Out of gold! Your %s was disbanded." % u.display_name(), u.coord)
		_remove_unit(u)
	p.gold = 0


# --- Events ----------------------------------------------------------------

## Records a plain-data event for this resolution (tick 0 = before the first tick).
func _ev(type: String, data: Dictionary = {}) -> void:
	if not _resolving:
		return
	var e := {"tick": _tick, "type": type}
	e.merge(data)
	_events.append(e)


static func _arr(c: Vector2i) -> Array:
	return [c.x, c.y]


# --- Victory ---------------------------------------------------------------

func score(pid: int) -> int:
	var total := 0
	for city in state.player_cities(pid):
		total += 10 + city.population * 3
	total += state.player(pid).techs.size() * 5
	for t in state.map.tiles:
		if t.owner == pid:
			total += 1
	return total


## Highest score wins; equal scores go to the lower player id.
func _leader_by_score(candidates: Array = []) -> int:
	var best := -1
	var best_score := -1
	for p in state.players:
		if not p.alive or (not candidates.is_empty() and not candidates.has(p.id)):
			continue
		if score(p.id) > best_score:
			best_score = score(p.id)
			best = p.id
	return best


func _check_elimination(pid: int) -> void:
	if _resolving:
		_elim_pending[pid] = true
		return
	if _eliminate_if_destroyed(pid):
		_check_victory()


## Applies the eliminations recorded since the last call (at the end of each tick).
func _process_eliminations() -> void:
	var pids: Array = _elim_pending.keys()
	pids.sort()
	_elim_pending.clear()
	for pid in pids:
		_eliminate_if_destroyed(pid)


## A player with no cities and no settlers is out. Returns true if it just was eliminated.
func _eliminate_if_destroyed(pid: int) -> bool:
	var p := state.player(pid)
	if p == null or not p.alive:
		return false
	if not state.player_cities(pid).is_empty():
		return false
	for u in state.player_units(pid):
		if u.has_ability("found_city"):
			return false
	p.alive = false
	p.clear_orders()
	for u in state.player_units(pid):
		_remove_unit(u)
	for t in state.map.tiles:
		if t.owner == pid:
			t.owner = -1
			t.city_id = -1
	for other in state.players:
		notify(other.id, "The %s civilization has been destroyed!" % p.name)
	borders_changed.emit()
	return true


## Decided once, after the whole turn resolved. Ties go to the higher score, then the lower id.
func _decide_victory() -> void:
	if state.game_over:
		return
	if not _science_winners.is_empty():
		_end_game(_leader_by_score(_science_winners), "science")
		return
	_check_victory()
	if state.game_over:
		return
	if state.turn > int(Defs.rules.victory.get("turn_limit", 100000)):
		_end_game(_leader_by_score(), "score")


func _check_victory() -> void:
	if state.game_over:
		return
	var alive := state.players.filter(func(p): return p.alive)
	if alive.is_empty():
		_end_game(-1, "draw")
		return
	var human := state.human_player()
	if human != null and not human.alive:
		_end_game(_leader_by_score(), "defeat")
		return
	if alive.size() == 1 and Defs.rules.victory.get("domination", true):
		_end_game(alive[0].id, "domination")


func _end_game(winner: int, victory_type: String) -> void:
	if state.game_over:
		return
	state.game_over = true
	state.winner = winner
	state.victory_type = victory_type
	game_ended.emit(winner, victory_type)
	changed.emit()
