class_name Game
extends RefCounted
## The rules engine's public API. The UI and the AI both drive the game only through
## these methods, and observe it through the signals. Actions return true on success.

signal changed                                   ## Something changed; views should refresh.
signal unit_moved(unit: Unit, path: Array)       ## path includes the start tile.
signal unit_created(unit: Unit)
signal unit_removed(unit: Unit)
signal combat_resolved(result: Dictionary)
signal city_founded(city: City)
signal city_captured(city: City, old_owner: int)
signal city_changed(city: City)
signal borders_changed
signal tech_learned(player: Player, tech_id: String)
signal turn_started(player: Player)
signal notified(entry: Dictionary)               ## {turn, player, text, coord}
signal game_ended(winner: int, victory_type: String)

var state: GameState
var log_entries: Array = []  # notifications, newest last


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


## Starts turn 1. With a human player, runs AI players until it's the human's turn.
## Without one (simulations), call run_ai_turns() afterwards.
func start() -> void:
	state.current_player = 0
	_begin_player_turn(current_player())
	if state.human_player() != null:
		_run_until_human()


func current_player() -> Player:
	return state.players[state.current_player]


func is_human_turn() -> bool:
	return not state.game_over and current_player().is_human


# --- Notifications ---------------------------------------------------------

func notify(pid: int, text: String, coord: Vector2i = Hex.NONE) -> void:
	var entry := {"turn": state.turn, "player": pid, "text": text, "coord": coord}
	log_entries.append(entry)
	if log_entries.size() > 400:
		log_entries = log_entries.slice(-300)
	notified.emit(entry)


# --- Unit actions ----------------------------------------------------------

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
	state.add_unit(u)
	unit_created.emit(u)
	changed.emit()
	return u


func _probe(unit_type: String, owner: int) -> Unit:
	var u := Unit.new()
	u.id = -1
	u.type = unit_type
	u.owner = owner
	return u


func _own_unit(unit_id: int) -> Unit:
	var u := state.get_unit(unit_id)
	if u == null or state.game_over or u.owner != state.current_player:
		return null
	return u


## Orders a unit to go to `target`; it moves as far as it can now and continues next turns.
func move_unit(unit_id: int, target: Vector2i) -> bool:
	var u := _own_unit(unit_id)
	if u == null:
		return false
	var path := Pathfinder.find_path(state, u, target)
	if path.is_empty():
		return false
	u.has_destination = true
	u.destination = target
	u.fortified = false
	u.sleeping = false
	_follow_path(u, path)
	return true


## Moves next to an enemy at `target` and attacks it if movement remains.
func move_and_attack(unit_id: int, target: Vector2i) -> bool:
	var u := _own_unit(unit_id)
	if u == null or not u.is_military() or u.has_attacked:
		return false
	if u.is_ranged():
		return attack(unit_id, target)
	if Hex.distance(u.coord, target) == 1:
		return attack(unit_id, target)
	var path := Pathfinder.find_attack_path(state, u, target)
	if path.size() < 2:
		return false
	path.pop_back()
	if Pathfinder.blocked_by_friend(state, u, path[-1]):
		return false
	u.fortified = false
	u.sleeping = false
	u.has_destination = false
	_follow_path(u, path)
	if u.moves_left > 0 and Hex.distance(u.coord, target) == 1:
		return attack(unit_id, target)
	return true


func _follow_path(u: Unit, path: Array) -> void:
	var traveled: Array = [u.coord]
	for i in path.size():
		if u.moves_left <= 0:
			break
		var step: Vector2i = path[i]
		var cost := Pathfinder.step_cost(state, u, state.tile(step))
		if cost >= Pathfinder.INF:
			u.has_destination = false
			break
		var remaining := maxi(0, u.moves_left - cost)
		var last := i == path.size() - 1
		if Pathfinder.blocked_by_friend(state, u, step) and (last or remaining == 0):
			break
		state.move_unit_to(u, step)
		u.moves_left = remaining
		u.acted = true
		traveled.append(step)
		_capture_civilians(u, step)
	# If the path got blocked while passing through a friend, step back off its tile.
	while traveled.size() > 1 and Pathfinder.blocked_by_friend(state, u, u.coord):
		traveled.pop_back()
		state.move_unit_to(u, traveled[-1])
	if u.has_destination and u.coord == u.destination:
		u.has_destination = false
	if traveled.size() > 1:
		Visibility.update(state, state.player(u.owner))
		unit_moved.emit(u, traveled)
		changed.emit()


func _capture_civilians(u: Unit, c: Vector2i) -> void:
	if not u.is_military():
		return
	for other in state.units_at(c):
		if other.owner != u.owner and other.is_civilian():
			var old_owner: int = other.owner
			other.owner = u.owner
			other.moves_left = 0
			other.has_destination = false
			other.ai = {}
			notify(u.owner, "Captured an enemy %s!" % other.display_name(), c)
			notify(old_owner, "Your %s was captured!" % other.display_name(), c)
			unit_created.emit(other)
			_check_elimination(old_owner)


func found_city(unit_id: int) -> bool:
	var u := _own_unit(unit_id)
	if u == null or not u.has_ability("found_city") or u.moves_left <= 0:
		return false
	if CityRules.found_blocker(state, u.owner, u.coord) != "":
		return false
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
	Visibility.update(state, player)
	notify(player.id, "%s has been founded." % city.name, city.coord)
	city_founded.emit(city)
	borders_changed.emit()
	changed.emit()
	return true


func fortify(unit_id: int) -> bool:
	var u := _own_unit(unit_id)
	if u == null or not u.is_military():
		return false
	u.fortified = true
	u.has_destination = false
	changed.emit()
	return true


func sleep(unit_id: int) -> bool:
	var u := _own_unit(unit_id)
	if u == null:
		return false
	u.sleeping = true
	u.has_destination = false
	changed.emit()
	return true


func wake(unit_id: int) -> bool:
	var u := _own_unit(unit_id)
	if u == null:
		return false
	u.sleeping = false
	u.fortified = false
	changed.emit()
	return true


func skip_unit(unit_id: int) -> bool:
	var u := _own_unit(unit_id)
	if u == null:
		return false
	u.skipped = true
	changed.emit()
	return true


func cancel_orders(unit_id: int) -> bool:
	var u := _own_unit(unit_id)
	if u == null:
		return false
	u.has_destination = false
	changed.emit()
	return true


func disband(unit_id: int) -> bool:
	var u := _own_unit(unit_id)
	if u == null:
		return false
	_remove_unit(u)
	_check_elimination(u.owner)
	changed.emit()
	return true


func _remove_unit(u: Unit) -> void:
	state.remove_unit(u)
	unit_removed.emit(u)


# --- Combat ----------------------------------------------------------------

## Attack target tile: melee units must be adjacent; ranged units within range.
func attack(unit_id: int, target: Vector2i) -> bool:
	var u := _own_unit(unit_id)
	if u == null or not u.is_military() or u.has_attacked or u.moves_left <= 0:
		return false
	var dist := Hex.distance(u.coord, target)
	if dist < 1 or dist > u.attack_range():
		return false
	var info := Combat.preview(state, u, target)
	if info.is_empty():
		return false
	var roll := Combat.roll(state, info)
	info.merge(roll)
	info.from = u.coord
	info.target = target
	u.has_attacked = true
	u.acted = true
	u.moves_left = 0
	u.fortified = false
	u.has_destination = false
	var attacker_owner := u.owner
	var defender_owner := -1
	if info.defender_kind == "city":
		var city := state.get_city(info.defender_city_id)
		defender_owner = city.owner
		var floor_hp := 1 if u.is_ranged() else 0
		city.hp = maxi(floor_hp, city.hp - int(roll.to_defender))
		u.hp -= int(roll.to_attacker)
		info.defender_hp = city.hp
		info.attacker_hp = u.hp
		if u.hp <= 0:
			_kill_unit(u, "destroyed attacking %s" % city.name)
		elif city.hp <= 0 and u.can_capture_cities():
			_capture_city(city, u)
		combat_resolved.emit(info)
		notify(defender_owner, "%s was attacked by a %s %s." % [city.name, state.player(attacker_owner).name, u.display_name()], city.coord)
	else:
		var d := state.get_unit(info.defender_unit_id)
		defender_owner = d.owner
		d.hp -= int(roll.to_defender)
		u.hp -= int(roll.to_attacker)
		info.defender_hp = d.hp
		info.attacker_hp = u.hp
		combat_resolved.emit(info)
		var d_name := d.display_name()
		if d.hp <= 0:
			_kill_unit(d, "destroyed by a %s %s" % [state.player(attacker_owner).name, u.display_name()])
			notify(attacker_owner, "Your %s destroyed an enemy %s." % [u.display_name(), d_name], target)
		else:
			notify(defender_owner, "Your %s was attacked by a %s %s (%d HP left)." % [d_name, state.player(attacker_owner).name, u.display_name(), d.hp], target)
		if u.hp <= 0:
			_kill_unit(u, "destroyed attacking a %s" % d_name)
		elif d.hp <= 0 and not u.is_ranged() and state.military_at(target) == null and state.city_at(target) == null:
			state.move_unit_to(u, target)
			_capture_civilians(u, target)
			unit_moved.emit(u, [info.from, target])
	for pid in [attacker_owner, defender_owner]:
		if pid >= 0:
			Visibility.update(state, state.player(pid))
	changed.emit()
	return true


## A city shoots at an enemy unit within range (once per turn).
func city_attack(city_id: int, target: Vector2i) -> bool:
	var city := state.get_city(city_id)
	if city == null or state.game_over or city.owner != state.current_player or city.has_attacked:
		return false
	if Hex.distance(city.coord, target) > int(Defs.rules.city.ranged_range):
		return false
	var info := Combat.preview_city_attack(state, city, target)
	if info.is_empty():
		return false
	var roll := Combat.roll(state, info)
	info.merge(roll)
	info.from = city.coord
	info.target = target
	city.has_attacked = true
	var d := state.get_unit(info.defender_unit_id)
	d.hp -= int(roll.to_defender)
	info.defender_hp = d.hp
	info.attacker_hp = city.hp
	combat_resolved.emit(info)
	if d.hp <= 0:
		_kill_unit(d, "destroyed by the city of %s" % city.name)
	else:
		notify(d.owner, "Your %s was bombarded by %s (%d HP left)." % [d.display_name(), city.name, d.hp], target)
	changed.emit()
	return true


func city_can_attack(city: City) -> bool:
	if city.has_attacked:
		return false
	for c in Hex.within(city.coord, int(Defs.rules.city.ranged_range)):
		var u := state.military_at(c)
		if u != null and u.owner != city.owner:
			return true
	return false


func _kill_unit(u: Unit, reason: String) -> void:
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
	for t in state.map.tiles:
		if t.city_id == city.id:
			t.owner = new_owner
	var from := conqueror.coord
	state.move_unit_to(conqueror, city.coord)
	_capture_civilians(conqueror, city.coord)
	unit_moved.emit(conqueror, [from, city.coord])
	CityRules.assign_work(state, city)
	if was_capital:
		_relocate_capital(old_owner)
	notify(new_owner, "You captured %s!" % city.name, city.coord)
	notify(old_owner, "%s has fallen to the %s!" % [city.name, state.player(new_owner).name], city.coord)
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


# --- Cities and research ---------------------------------------------------

func set_production(city_id: int, kind: String, id: String) -> bool:
	var city := state.get_city(city_id)
	if city == null or state.game_over or city.owner != state.current_player:
		return false
	if CityRules.build_blocker(state, city, kind, id) != "":
		return false
	city.build = {"kind": kind, "id": id}
	city_changed.emit(city)
	changed.emit()
	return true


func can_purchase(city: City, kind: String, id: String) -> bool:
	if city.owner != state.current_player or CityRules.build_blocker(state, city, kind, id) != "":
		return false
	if state.player(city.owner).gold < CityRules.purchase_cost(kind, id):
		return false
	if kind == "unit":
		var pop_cost := int(Defs.units[id].get("pop_cost", 0))
		if pop_cost > 0 and city.population <= pop_cost:
			return false
		return CityRules.spawn_tile(state, city, id) != Hex.NONE
	return true


## Buys a unit or building immediately with gold.
func purchase(city_id: int, kind: String, id: String) -> bool:
	var city := state.get_city(city_id)
	if city == null or state.game_over or not can_purchase(city, kind, id):
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
	if p == null or not TechRules.set_research(p, tech_id):
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


## Ends the human's turn, runs all AI turns, and starts the human's next turn.
func end_turn() -> void:
	if state.game_over or not current_player().is_human:
		return
	_end_player_turn(current_player())
	_advance()
	_run_until_human()


## For simulations/tests: plays AI turns until `last_turn` has finished or the game ends.
func run_ai_turns(last_turn: int) -> void:
	var guard := 0
	while not state.game_over and state.turn <= last_turn and guard < 100000:
		var p := current_player()
		AIPlayer.take_turn(self, p)
		_end_player_turn(p)
		_advance()
		guard += 1


func _run_until_human() -> void:
	var guard := 0
	while not state.game_over and guard < 1000:
		var p := current_player()
		if p.is_human:
			turn_started.emit(p)
			changed.emit()
			return
		AIPlayer.take_turn(self, p)
		_end_player_turn(p)
		_advance()
		guard += 1
	changed.emit()


func _advance() -> void:
	if state.game_over:
		return
	var n := state.players.size()
	var idx := state.current_player
	for _i in n:
		idx = (idx + 1) % n
		if idx == 0:
			state.turn += 1
			if state.turn > int(Defs.rules.victory.get("turn_limit", 100000)):
				_end_game(_leader_by_score(), "score")
				return
		if state.players[idx].alive:
			break
	state.current_player = idx
	_begin_player_turn(state.players[idx])


func _begin_player_turn(p: Player) -> void:
	var r: Dictionary = Defs.rules.units
	for u in state.player_units(p.id):
		if not u.acted:
			u.hp = mini(int(r.max_hp), u.hp + _heal_amount(u))
		u.moves_left = u.max_moves()
		u.has_attacked = false
		u.skipped = false
		u.acted = false
	for city in state.player_cities(p.id):
		city.has_attacked = false
		city.hp = mini(Combat.city_max_hp(city), city.hp + int(Defs.rules.city.heal_per_turn))
	Visibility.update(state, p)
	for u in state.player_units(p.id):
		if u.has_destination and state.units.has(u.id):
			var path := Pathfinder.find_path(state, u, u.destination)
			if path.is_empty():
				u.has_destination = false
				notify(p.id, "A %s could not reach its destination." % u.display_name(), u.coord)
			else:
				_follow_path(u, path)


func _heal_amount(u: Unit) -> int:
	var r: Dictionary = Defs.rules.units
	var city := state.city_at(u.coord)
	if city != null and city.owner == u.owner:
		return int(r.heal_city)
	if state.tile(u.coord).owner == u.owner:
		return int(r.heal_friendly)
	return int(r.heal_field)


func _end_player_turn(p: Player) -> void:
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
		units.sort_custom(func(a, b): return a.def().cost < b.def().cost)
		var u: Unit = units[0]
		notify(p.id, "Out of gold! Your %s was disbanded." % u.display_name(), u.coord)
		_remove_unit(u)
	p.gold = 0


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


func _leader_by_score() -> int:
	var best := -1
	var best_score := -1
	for p in state.players:
		if p.alive and score(p.id) > best_score:
			best_score = score(p.id)
			best = p.id
	return best


func _check_elimination(pid: int) -> void:
	var p := state.player(pid)
	if p == null or not p.alive:
		return
	if not state.player_cities(pid).is_empty():
		return
	for u in state.player_units(pid):
		if u.has_ability("found_city"):
			return
	p.alive = false
	for u in state.player_units(pid):
		_remove_unit(u)
	for t in state.map.tiles:
		if t.owner == pid:
			t.owner = -1
			t.city_id = -1
	for other in state.players:
		notify(other.id, "The %s civilization has been destroyed!" % p.name)
	borders_changed.emit()
	_check_victory()


func _check_victory() -> void:
	if state.game_over:
		return
	var human := state.human_player()
	if human != null and not human.alive:
		_end_game(_leader_by_score(), "defeat")
		return
	var alive := state.players.filter(func(p): return p.alive)
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
