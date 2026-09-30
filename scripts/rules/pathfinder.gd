class_name Pathfinder
extends RefCounted
## Turn-aware A* for land units.
##
## Cost model ("g") counts movement points spent, where ending a turn early
## wastes the unused points: g = turns_elapsed * max_moves + (max_moves - moves_left).
## Like Civ V, a unit with any movement left may enter any passable tile; doing so
## costs min(tile_cost, moves_left). Every step raises g by >= 1, so hex distance is
## an admissible, consistent heuristic.

const INF := 1 << 30


## Cost for `unit` to step onto `tile`, or INF if it can't move there.
## Enemy units/cities block movement (attacking is a separate action), except that
## military units may walk onto tiles holding only enemy civilians (capturing them).
static func step_cost(state: GameState, unit: Unit, tile: Tile) -> int:
	if tile == null or not tile.is_passable_land():
		return INF
	var city := state.city_at(tile.coord)
	if city != null and city.owner != unit.owner:
		return INF
	for other in state.units_at(tile.coord):
		if other.owner != unit.owner and (other.is_military() or unit.is_civilian()):
			return INF
	return tile.move_cost()


## True if another friendly unit of the same kind (military/civilian) is on `c`.
static func blocked_by_friend(state: GameState, unit: Unit, c: Vector2i) -> bool:
	for other in state.units_at(c):
		if other != unit and other.owner == unit.owner and other.is_military() == unit.is_military():
			return true
	return false


## Movement points the unit would have left when standing somewhere with cost `g`.
static func moves_at(g: int, max_moves: int) -> int:
	var r := g % max_moves
	return max_moves if r == 0 else max_moves - r


## Starting cost for the unit's current state.
static func start_g(unit: Unit) -> int:
	return unit.max_moves() - unit.moves_left


## 0 = arrives this turn, 1 = next turn, ... for a tile reached with cost `g`.
static func turns_for(unit: Unit, g: int) -> int:
	var mp := unit.max_moves()
	if g <= mp:
		return 0
	return int(ceil(float(g) / mp)) - 1


## Explores from the unit. Returns {"g": {coord: cost}, "came": {coord: prev}}.
## Stops early at `target` if given (not Hex.NONE). Tiles with g > max_g are not expanded.
## `attack_target` allows the final step onto an enemy-held tile (for move-and-attack).
static func search(state: GameState, unit: Unit, target: Vector2i = Hex.NONE, max_g: int = INF, attack_target := false) -> Dictionary:
	var mp := unit.max_moves()
	var g0 := start_g(unit)
	var g := {unit.coord: g0}
	var came := {}
	var closed := {}
	var heap := MinHeap.new()
	heap.push(unit.coord, g0)
	var has_target := target != Hex.NONE
	while not heap.is_empty():
		var cur: Vector2i = heap.pop()
		if closed.has(cur):
			continue
		closed[cur] = true
		if has_target and cur == target:
			break
		var cur_g: int = g[cur]
		var moves_now := moves_at(cur_g, mp)
		for n in Hex.neighbors(cur):
			if closed.has(n):
				continue
			var t := state.map.get_tile(n)
			if t == null:
				continue
			var cost := step_cost(state, unit, t)
			if cost >= INF:
				if not (attack_target and n == target and t.is_passable_land()):
					continue
				cost = 1
			var ng := cur_g + mini(cost, moves_now)
			if ng > max_g:
				continue
			if not g.has(n) or ng < g[n]:
				g[n] = ng
				came[n] = cur
				var h := Hex.distance(n, target) if has_target else 0
				heap.push(n, ng + h)
	return {"g": g, "came": came}


## Path (excluding the start) to `target`, or [] if unreachable / not a legal end tile.
static func find_path(state: GameState, unit: Unit, target: Vector2i) -> Array:
	if target == unit.coord or not state.map.in_bounds(target):
		return []
	if blocked_by_friend(state, unit, target):
		return []
	var result := search(state, unit, target)
	return _reconstruct(result.came, unit.coord, target)


## Path to a tile adjacent to `target` (an enemy), ending with `target` itself.
static func find_attack_path(state: GameState, unit: Unit, target: Vector2i) -> Array:
	var result := search(state, unit, target, INF, true)
	return _reconstruct(result.came, unit.coord, target)


## Tiles the unit can reach this turn: {coord: g}.
static func reachable(state: GameState, unit: Unit) -> Dictionary:
	var out := {}
	if unit.moves_left <= 0:
		return out
	var result := search(state, unit, Hex.NONE, unit.max_moves())
	for c in result.g:
		if c != unit.coord and not blocked_by_friend(state, unit, c):
			out[c] = result.g[c]
	return out


## Cost of each step along `path` for display: [{coord, g, turn}].
static func annotate(state: GameState, unit: Unit, path: Array) -> Array:
	var out: Array = []
	var mp := unit.max_moves()
	var g := start_g(unit)
	for c in path:
		var t := state.map.get_tile(c)
		var cost := step_cost(state, unit, t)
		if cost >= INF:
			cost = 1
		g += mini(cost, moves_at(g, mp))
		out.append({"coord": c, "g": g, "turn": turns_for(unit, g)})
	return out


static func _reconstruct(came: Dictionary, start: Vector2i, target: Vector2i) -> Array:
	if not came.has(target):
		return []
	var path: Array = []
	var cur := target
	while cur != start:
		path.push_front(cur)
		cur = came[cur]
	return path
