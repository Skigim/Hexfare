class_name GameState
extends RefCounted
## All mutable game data. Pure data + lookup helpers; rules live elsewhere.

## Save format version. 2 added orders, unit priority and game time.
const VERSION := 2

var map: HexMap
var players: Array[Player] = []
var units: Dictionary = {}    # id -> Unit
var cities: Dictionary = {}   # id -> City
var turn: int = 1
var time: int = 0             # game seconds elapsed (advances per resolved turn; economy uses it later)
var next_id: int = 1
var rng := RandomNumberGenerator.new()
var settings: Dictionary = {}
var game_over := false
var winner: int = -1
var victory_type: String = ""

var _units_at: Dictionary = {}  # Vector2i -> Array of unit ids
var _city_at: Dictionary = {}   # Vector2i -> city id


func new_id() -> int:
	next_id += 1
	return next_id - 1


func player(pid: int) -> Player:
	if pid < 0 or pid >= players.size():
		return null
	return players[pid]


## True if players `a` and `b` are hostile. Alliances will plug in here.
func is_enemy(a: int, b: int) -> bool:
	return a != b


func human_player() -> Player:
	for p in players:
		if p.is_human:
			return p
	return null


func tile(c: Vector2i) -> Tile:
	return map.get_tile(c)


# --- Units -----------------------------------------------------------------

func add_unit(u: Unit) -> void:
	units[u.id] = u
	_index_unit(u)


func remove_unit(u: Unit) -> void:
	_unindex_unit(u)
	units.erase(u.id)


func move_unit_to(u: Unit, c: Vector2i) -> void:
	_unindex_unit(u)
	u.coord = c
	_index_unit(u)


func get_unit(uid: int) -> Unit:
	return units.get(uid)


func units_at(c: Vector2i) -> Array:
	var out: Array = []
	for uid in _units_at.get(c, []):
		out.append(units[uid])
	return out


func military_at(c: Vector2i) -> Unit:
	for u in units_at(c):
		if u.is_military():
			return u
	return null


func civilian_at(c: Vector2i) -> Unit:
	for u in units_at(c):
		if u.is_civilian():
			return u
	return null


func player_units(pid: int) -> Array:
	var out: Array = []
	for u in units.values():
		if u.owner == pid:
			out.append(u)
	return out


func has_enemy_unit(c: Vector2i, pid: int) -> bool:
	for u in units_at(c):
		if u.owner != pid:
			return true
	return false


func _index_unit(u: Unit) -> void:
	if not _units_at.has(u.coord):
		_units_at[u.coord] = []
	_units_at[u.coord].append(u.id)


func _unindex_unit(u: Unit) -> void:
	var ids: Array = _units_at.get(u.coord, [])
	ids.erase(u.id)
	if ids.is_empty():
		_units_at.erase(u.coord)


# --- Cities ----------------------------------------------------------------

func add_city(city: City) -> void:
	cities[city.id] = city
	_city_at[city.coord] = city.id


func remove_city(city: City) -> void:
	cities.erase(city.id)
	_city_at.erase(city.coord)


func city_at(c: Vector2i) -> City:
	if not _city_at.has(c):
		return null
	return cities[_city_at[c]]


func get_city(cid: int) -> City:
	return cities.get(cid)


func player_cities(pid: int) -> Array:
	var out: Array = []
	for c in cities.values():
		if c.owner == pid:
			out.append(c)
	return out


func capital_of(pid: int) -> City:
	for c in player_cities(pid):
		if c.is_capital():
			return c
	return null


# --- Serialization ---------------------------------------------------------

func to_dict() -> Dictionary:
	var ps: Array = []
	for p in players:
		ps.append(p.to_dict())
	var us: Array = []
	for u in units.values():
		us.append(u.to_dict())
	var cs: Array = []
	for c in cities.values():
		cs.append(c.to_dict())
	return {
		"version": VERSION, "map": map.to_dict(), "players": ps, "units": us, "cities": cs,
		"turn": turn, "time": time, "next_id": next_id,
		"rng_seed": str(rng.seed), "rng_state": str(rng.state), "settings": settings,
		"game_over": game_over, "winner": winner, "victory_type": victory_type,
	}


## Returns null if the save was written by a newer version of the game.
static func from_dict(d: Dictionary) -> GameState:
	if int(d.get("version", 1)) > VERSION:
		push_error("GameState: save version %s is newer than %d" % [str(d.get("version")), VERSION])
		return null
	var s := GameState.new()
	s.map = HexMap.from_dict(d.map)
	for pd in d.players:
		s.players.append(Player.from_dict(pd))
	for ud in d.units:
		s.add_unit(Unit.from_dict(ud))
		# Saves from before planned orders kept a multi-turn destination on the unit.
		if ud.get("has_destination", false):
			var owner := s.player(int(ud.owner))
			var dest := Vector2i(int(ud.destination[0]), int(ud.destination[1]))
			if owner != null and dest != s.get_unit(int(ud.id)).coord and owner.unit_order(int(ud.id)).is_empty():
				owner.set_order(Orders.move(int(ud.id), dest))
	for cd in d.cities:
		s.add_city(City.from_dict(cd))
	s.turn = int(d.turn)
	s.time = int(d.get("time", 0))
	s.next_id = int(d.next_id)
	s.rng.seed = String(d.rng_seed).to_int()
	s.rng.state = String(d.rng_state).to_int()
	s.settings = Defs.normalize(d.settings)
	s.game_over = d.game_over
	s.winner = int(d.winner)
	s.victory_type = d.victory_type
	return s
