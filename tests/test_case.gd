class_name TestCase
extends RefCounted
## Minimal assertion helpers. Test methods are any method named test_*.

var failures: Array[String] = []
var checks := 0
var current_test := ""


func assert_true(cond: bool, msg: String = "") -> void:
	checks += 1
	if not cond:
		failures.append("%s: expected true. %s" % [current_test, msg])


func assert_false(cond: bool, msg: String = "") -> void:
	assert_true(not cond, msg)


func assert_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	checks += 1
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("%s: expected <%s> got <%s>. %s" % [current_test, str(expected), str(actual), msg])


func assert_between(value: float, lo: float, hi: float, msg: String = "") -> void:
	checks += 1
	if value < lo or value > hi:
		failures.append("%s: %s not in [%s, %s]. %s" % [current_test, str(value), str(lo), str(hi), msg])


## Builds a small all-grassland map with the given players (no AI turn run).
func make_flat_game(width: int = 12, height: int = 10, player_count: int = 2) -> Game:
	Defs.ensure_loaded()
	var game := Game.new()
	var s := GameState.new()
	game.state = s
	s.rng.seed = 42
	s.map = HexMap.new(width, height)
	for t in s.map.tiles:
		t.terrain = "grassland"
	for i in player_count:
		var p := Player.new()
		p.id = i
		p.civ_index = i
		p.name = Defs.civs[i].name
		p.color = Color.html(Defs.civs[i].color)
		p.is_human = i == 0
		s.players.append(p)
		Visibility.update(s, p)
	return game


## Places a unit ready to act (full moves) at an offset (col,row) position.
func spawn(game: Game, unit_type: String, owner: int, col: int, row: int) -> Unit:
	var u := game.create_unit(unit_type, owner, Hex.offset_to_axial(col, row))
	u.moves_left = u.max_moves()
	return u
