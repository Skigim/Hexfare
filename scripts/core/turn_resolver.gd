class_name TurnResolver
extends RefCounted
## Resolves every player's planned orders at once. Used only through Game.resolve_turn().
##
## A turn is a series of ticks. A tick is one step per unit:
##   1. Ranged attacks and city bombardments (tick 1 only) are computed from the tick-start
##      snapshot, applied together, and only then are the dead removed.
##   2. Moves: units are processed in (priority desc, id asc) order, repeating passes until nothing
##      more can move, so columns and rotations of units resolve. A melee unit whose next step
##      enters a tile held by an enemy attacks it instead (whatever its order was); this also covers
##      head-on swaps and two enemies entering one tile. After attacking, or when blocked, a unit
##      stops for the rest of the turn and keeps its order. There is no waiting or retrying.
##   3. Post-move: settlers found cities, fog is refreshed once, eliminations are applied.
## Every tick a unit either spends movement or stops, so the loop always ends.
##
## After the ticks come the economy phase (disbands, purchases, then each player's cities, income
## and research), healing, and the turn rollover. Victory is decided once, at the very end.
## Everything is ordered by (priority, id) or by hash, never by insertion order, so a resolution
## is deterministic for a given state (combat rolls come from state.rng in that fixed order).

var game: Game
var state: GameState

# Per moving unit: {"path": Array, "idx": int, "kind": "move"|"found_city", "at": Vector2i,
#                   "owner": int, "stopped": bool, "done": bool}
var _rt: Dictionary = {}


func _init(g: Game) -> void:
	game = g
	state = g.state


# --- Ticks -------------------------------------------------------------------

func run_ticks() -> void:
	_apply_stances()
	_prepare_paths()
	var cap := 1
	for uid in _rt:
		var u := state.get_unit(uid)
		if u != null:
			cap = maxi(cap, u.max_moves())
	for tick in range(1, cap + 1):
		game._tick = tick
		game._dirty = false
		if tick == 1:
			_ranged_phase()
		_move_phase()
		_post_move()
		if game._dirty:
			for p in state.players:
				if p.alive:
					Visibility.update(state, p)
		game._process_eliminations()
		if not _any_active():
			break
	_cleanup_orders()


## Unit orders of living players, in (player id, unit id) order. Drops orders of vanished units.
func _unit_orders() -> Array:
	var out: Array = []
	for p in state.players:
		if not p.alive:
			continue
		for o in p.sorted_orders():
			if o.kind != Orders.KIND_UNIT:
				continue
			var u := state.get_unit(int(o.id))
			if u == null or u.owner != p.id:
				p.remove_order(o.kind, int(o.id), o.slot)
				continue
			out.append({"p": p, "o": o, "u": u})
	return out


static func _unit_before(a: Unit, b: Unit) -> bool:
	if a.priority != b.priority:
		return a.priority > b.priority
	return a.id < b.id


## Tick 0: stances take effect, and moving units give up fortifying.
func _apply_stances() -> void:
	for e in _unit_orders():
		var u: Unit = e.u
		var p: Player = e.p
		match e.o.type:
			"fortify":
				u.fortified = true
				u.sleeping = false
				p.remove_order(Orders.KIND_UNIT, u.id, Orders.SLOT_ACT)
			"sleep":
				u.sleeping = true
				u.fortified = false
				p.remove_order(Orders.KIND_UNIT, u.id, Orders.SLOT_ACT)
			"wake":
				u.sleeping = false
				u.fortified = false
				p.remove_order(Orders.KIND_UNIT, u.id, Orders.SLOT_ACT)
			"move", "found_city":
				u.fortified = false
				u.sleeping = false


## Plans each mover's path from where it stands now. Orders that can no longer be carried out are dropped.
func _prepare_paths() -> void:
	for e in _unit_orders():
		var o: Dictionary = e.o
		var u: Unit = e.u
		var p: Player = e.p
		if o.type != "move" and o.type != "found_city":
			continue
		var at := Orders.coord(o, "to" if o.type == "move" else "at")
		if o.type == "move" and u.coord == at:
			p.remove_order(Orders.KIND_UNIT, u.id, Orders.SLOT_ACT)
			continue
		var path: Array = []
		if u.coord != at:
			path = game.plan_path(u, at)
			if path.is_empty():
				p.remove_order(Orders.KIND_UNIT, u.id, Orders.SLOT_ACT)
				game.notify(p.id, "Your %s could not reach its destination." % u.display_name(), u.coord)
				continue
		_rt[u.id] = {"path": path, "idx": 0, "kind": o.type, "at": at, "owner": u.owner, "stopped": false, "done": false}


# --- Ranged ------------------------------------------------------------------

func _ranged_phase() -> void:
	var shooters: Array = []
	for e in _unit_orders():
		if e.o.type == "attack":
			shooters.append(e)
	shooters.sort_custom(func(a, b): return _unit_before(a.u, b.u))
	var shots: Array = []
	for e in shooters:
		var u: Unit = e.u
		var at := Orders.coord(e.o, "at")
		var dist := Hex.distance(u.coord, at)
		if dist < 1 or dist > u.attack_range():
			continue
		var info := Combat.preview(state, u, at)
		if info.is_empty():
			continue
		info.merge(Combat.roll(state, info))
		info.from = u.coord
		info.target = at
		shots.append({"unit": u, "info": info})
	var bombards: Array = []
	for p in state.players:
		if not p.alive:
			continue
		for o in p.sorted_orders():
			if o.kind == Orders.KIND_CITY and o.type == "bombard":
				var city := state.get_city(int(o.id))
				if city != null and city.owner == p.id:
					bombards.append({"city": city, "o": o})
	bombards.sort_custom(func(a, b): return a.city.id < b.city.id)
	for e in bombards:
		var city: City = e.city
		var at := Orders.coord(e.o, "at")
		if Hex.distance(city.coord, at) > int(Defs.rules.city.ranged_range):
			continue
		var info := Combat.preview_city_attack(state, city, at)
		if info.is_empty():
			continue
		info.merge(Combat.roll(state, info))
		info.from = city.coord
		info.target = at
		shots.append({"city": city, "info": info})
	_apply_shots(shots)


## Applies all computed shots, then removes whatever died, so simultaneous kills are possible.
func _apply_shots(shots: Array) -> void:
	var dead: Dictionary = {}  # unit id -> {reason, attacker, name, at}
	for s in shots:
		var info: Dictionary = s.info
		var attacker_owner: int
		var attacker_desc: String
		if s.has("unit"):
			var a: Unit = s.unit
			attacker_owner = a.owner
			attacker_desc = Game.article("%s %s" % [state.player(a.owner).name, a.display_name()])
			a.acted = true
			a.fortified = false
			a.moves_left = 0
			info.attacker_hp = a.hp
		else:
			var c: City = s.city
			attacker_owner = c.owner
			attacker_desc = "the city of %s" % c.name
			c.has_attacked = true
			info.attacker_hp = c.hp
		var defender_owner := -1
		if info.defender_kind == "city":
			var dc := state.get_city(info.defender_city_id)
			if dc == null:
				continue
			defender_owner = dc.owner
			dc.hp = maxi(1, dc.hp - int(info.to_defender))
			info.defender_hp = dc.hp
			game.notify(defender_owner, "%s was attacked by %s." % [dc.name, attacker_desc], dc.coord)
		else:
			var d := state.get_unit(info.defender_unit_id)
			if d == null:
				continue
			defender_owner = d.owner
			d.hp -= int(info.to_defender)
			info.defender_hp = d.hp
			if d.hp <= 0:
				dead[d.id] = {"reason": "destroyed by %s" % attacker_desc, "attacker": attacker_owner,
						"name": d.display_name(), "at": info.target}
			else:
				game.notify(defender_owner, "Your %s was attacked by %s (%d HP left)." % [d.display_name(), attacker_desc, d.hp], info.target)
		game._record_attack(info, attacker_owner, defender_owner)
		game.combat_resolved.emit(info)
		game._dirty = true
	var ids: Array = dead.keys()
	ids.sort()
	for uid in ids:
		var d := state.get_unit(uid)
		if d == null:
			continue
		var rec: Dictionary = dead[uid]
		game._kill_unit(d, rec.reason)
		game.notify(rec.attacker, "Your ranged attack destroyed an enemy %s." % rec.name, rec.at)


# --- Movement ----------------------------------------------------------------

func _move_phase() -> void:
	var movers: Array = []
	for uid in _rt:
		var u := state.get_unit(uid)
		if u != null and not _rt[uid].stopped and not _rt[uid].done:
			movers.append(u)
	movers.sort_custom(_unit_before)
	var done: Dictionary = {}
	var progress := true
	while progress:
		progress = false
		for u in movers:
			if done.has(u.id):
				continue
			if not state.units.has(u.id):
				done[u.id] = true
				continue
			var rt: Dictionary = _rt[u.id]
			if u.owner != rt.owner or rt.stopped or u.moves_left <= 0 or rt.idx >= rt.path.size():
				done[u.id] = true
				continue
			match _try_step(u, rt):
				"moved", "fought":
					done[u.id] = true
					progress = true
				"stopped":
					done[u.id] = true
					rt.stopped = true
				# "blocked": a friend is in the way; try again next pass in case it moves on
	for u in movers:
		if state.units.has(u.id) and not done.has(u.id):
			_rt[u.id].stopped = true


## One step of `u` along its path. Returns "moved", "fought", "stopped" or "blocked".
func _try_step(u: Unit, rt: Dictionary) -> String:
	var target: Vector2i = rt.path[rt.idx]
	var tile := state.tile(target)
	if tile == null or not tile.is_passable_land():
		return "stopped"
	var city := state.city_at(target)
	var occupant := state.military_at(target)
	var enemy_city := city != null and state.is_enemy(city.owner, u.owner)
	var enemy_unit := occupant != null and state.is_enemy(occupant.owner, u.owner)
	if enemy_city or enemy_unit:
		if not u.can_attack_on_contact():
			return "stopped"
		if not game._resolve_attack(u, target):
			return "stopped"
		rt.stopped = true
		if state.units.has(u.id) and u.coord == target:
			rt.idx += 1  # advanced into the emptied tile
		return "fought"
	var cost := Pathfinder.step_cost(state, u, tile)
	if cost >= Pathfinder.INF:
		return "stopped"
	if Pathfinder.blocked_by_friend(state, u, target):
		return "blocked"
	var from := u.coord
	u.moves_left = maxi(0, u.moves_left - cost)
	state.move_unit_to(u, target)
	u.acted = true
	rt.idx += 1
	game._dirty = true
	game._ev("move", {"unit": u.id, "owner": u.owner, "from": Game._arr(from), "to": Game._arr(target)})
	game._capture_civilians(u, target)
	return "moved"


func _post_move() -> void:
	var founders: Array = []
	for uid in _rt:
		var rt: Dictionary = _rt[uid]
		if rt.kind != "found_city" or rt.done:
			continue
		var u := state.get_unit(uid)
		if u == null or u.owner != rt.owner or rt.idx < rt.path.size() or u.coord != rt.at or u.moves_left <= 0:
			continue
		founders.append(u)
	founders.sort_custom(_unit_before)
	for u in founders:
		_rt[u.id].done = true
		var reason := CityRules.found_blocker(state, u.owner, u.coord)
		if reason == "":
			game._found_city_now(u)
		else:
			game.notify(u.owner, "Your %s could not found a city: %s." % [u.display_name(), reason.to_lower()], u.coord)
			state.player(u.owner).remove_order(Orders.KIND_UNIT, u.id, Orders.SLOT_ACT)


func _any_active() -> bool:
	for uid in _rt:
		var rt: Dictionary = _rt[uid]
		if rt.stopped or rt.done:
			continue
		var u := state.get_unit(uid)
		if u != null and u.owner == rt.owner and u.moves_left > 0 and rt.idx < rt.path.size():
			return true
	return false


## One-shot orders are spent; movement orders that finished are removed; the rest carry over.
func _cleanup_orders() -> void:
	for p in state.players:
		if not p.alive:
			continue
		for o in p.sorted_orders():
			if o.type == "attack" or o.type == "bombard":
				p.remove_order(o.kind, int(o.id), o.slot)
			elif o.type == "move":
				var u := state.get_unit(int(o.id))
				if u == null or u.coord == Orders.coord(o, "to"):
					p.remove_order(o.kind, int(o.id), o.slot)


# --- Economy phase -----------------------------------------------------------

func run_economy() -> void:
	game._tick = 0
	for e in _unit_orders():
		if e.o.type == "disband":
			var u: Unit = e.u
			game._ev("unit_died", {"unit": u.id, "owner": u.owner, "type": u.type, "coord": Game._arr(u.coord)})
			game._remove_unit(u)
			game._check_elimination(u.owner)
	var seq := _player_sequence()
	for p in seq:
		for o in p.sorted_orders():
			if o.kind != Orders.KIND_CITY or o.type != "purchase":
				continue
			p.remove_order(o.kind, int(o.id), o.slot)
			var city := state.get_city(int(o.id))
			if city == null or city.owner != p.id:
				continue
			if not game._do_purchase(city, o.item_kind, o.item_id):
				game.notify(p.id, "Could not buy %s in %s." % [CityRules.item_name(o.item_kind, o.item_id), city.name], city.coord)
	for p in seq:
		game._economy_for(p)
	game._process_eliminations()


## Living players in a per-turn hashed order, so no player always goes first when they compete
## for the same tile or spawn spot.
func _player_sequence() -> Array:
	var seq: Array = []
	for p in state.players:
		if p.alive:
			seq.append(p)
	seq.sort_custom(func(a, b):
		var ha := Orders.mix(state.turn, a.id)
		var hb := Orders.mix(state.turn, b.id)
		return ha < hb or (ha == hb and a.id < b.id))
	return seq
