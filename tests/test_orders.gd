extends TestCase
## Planned orders: validation, storage and the planning rules. Resolution tests are further down.


func _setup(width := 12, height := 10) -> Game:
	return make_flat_game(width, height, 2)


func test_orders_roundtrip_and_sorting() -> void:
	var game := _setup()
	var a := spawn(game, "warrior", 0, 2, 2)
	var b := spawn(game, "warrior", 0, 3, 3)
	# Issue out of id order: sorted_orders must not depend on insertion order.
	assert_true(game.issue_order(0, Orders.fortify(b.id)).ok)
	assert_true(game.issue_order(0, Orders.sleep(a.id)).ok)
	var p := game.state.player(0)
	assert_eq(p.sorted_orders()[0].id, a.id)
	assert_eq(p.sorted_orders()[1].id, b.id)
	# Survives a state round trip, including the lookup index.
	var s2 := GameState.from_dict(JSON.parse_string(JSON.stringify(game.state.to_dict())))
	assert_eq(s2.player(0).unit_order(a.id).type, "sleep")
	assert_eq(JSON.stringify(s2.to_dict()), JSON.stringify(game.state.to_dict()))


func test_one_order_per_slot_and_cancel() -> void:
	var game := _setup()
	var u := spawn(game, "warrior", 0, 2, 2)
	game.issue_order(0, Orders.move(u.id, Hex.offset_to_axial(5, 2)))
	game.issue_order(0, Orders.move(u.id, Hex.offset_to_axial(6, 2)))
	var p := game.state.player(0)
	assert_eq(p.orders.size(), 1, "second order replaces the first")
	assert_eq(Orders.coord(p.unit_order(u.id), "to"), Hex.offset_to_axial(6, 2))
	assert_true(game.cancel_order(0, Orders.KIND_UNIT, u.id))
	assert_eq(p.orders.size(), 0)
	assert_false(game.cancel_order(0, Orders.KIND_UNIT, u.id), "nothing left to cancel")


func test_players_cannot_order_each_others_units() -> void:
	var game := _setup()
	var mine := spawn(game, "warrior", 0, 2, 2)
	var theirs := spawn(game, "warrior", 1, 8, 8)
	assert_false(game.issue_order(1, Orders.fortify(mine.id)).ok)
	assert_true(game.issue_order(1, Orders.fortify(theirs.id)).ok)
	assert_eq(game.orders_of(0, 1).size(), 0, "a player cannot read another player's orders")
	assert_eq(game.orders_of(1, 1).size(), 1)


func test_planning_has_no_side_effects() -> void:
	var game := _setup()
	var u := spawn(game, "warrior", 0, 2, 2)
	var rng_before := game.state.rng.state
	var before := JSON.stringify(_world(game.state))
	game.issue_order(0, Orders.move(u.id, Hex.offset_to_axial(6, 2)))
	game.issue_order(0, Orders.fortify(u.id))
	game.cancel_order(0, Orders.KIND_UNIT, u.id)
	assert_eq(game.state.rng.state, rng_before, "planning never draws random numbers")
	assert_eq(JSON.stringify(_world(game.state)), before, "planning leaves the world untouched")


func test_move_validation() -> void:
	var game := _setup()
	var u := spawn(game, "warrior", 0, 2, 2)
	assert_false(game.issue_order(0, Orders.move(u.id, u.coord)).ok, "already there")
	assert_false(game.issue_order(0, Orders.move(u.id, Vector2i(-50, -50))).ok, "off the map")
	assert_true(game.issue_order(0, Orders.move(u.id, Hex.offset_to_axial(6, 2))).ok)
	# Planning uses a full movement budget even when the unit has none left.
	u.moves_left = 0
	assert_true(game.issue_order(0, Orders.move(u.id, Hex.offset_to_axial(7, 2))).ok)


func test_ranged_attack_order_rules() -> void:
	var game := _setup()
	var archer := spawn(game, "archer", 0, 2, 2)
	var warrior := spawn(game, "warrior", 0, 3, 2)
	var target := spawn(game, "warrior", 1, 4, 2)
	assert_true(game.issue_order(0, Orders.attack(archer.id, target.coord)).ok)
	assert_false(game.issue_order(0, Orders.attack(archer.id, Hex.offset_to_axial(9, 8))).ok, "out of range")
	assert_false(game.issue_order(0, Orders.attack(archer.id, Hex.offset_to_axial(0, 0))).ok, "empty tile")
	assert_false(game.issue_order(0, Orders.attack(warrior.id, target.coord)).ok, "melee units have no attack order")


func test_assault_move_onto_enemy_is_melee_only() -> void:
	var game := _setup()
	var warrior := spawn(game, "warrior", 0, 2, 2)
	var archer := spawn(game, "archer", 0, 2, 4)
	var enemy := spawn(game, "warrior", 1, 6, 3)
	assert_true(game.issue_order(0, Orders.move(warrior.id, enemy.coord)).ok, "melee may assault")
	assert_false(game.issue_order(0, Orders.move(archer.id, enemy.coord)).ok, "ranged may not")


func test_found_city_order_checks_the_site() -> void:
	var game := _setup()
	var settler := spawn(game, "settler", 0, 4, 4)
	assert_true(game.issue_order(0, Orders.found_city(settler.id, settler.coord)).ok)
	assert_true(game.issue_order(0, Orders.found_city(settler.id, Hex.offset_to_axial(7, 4))).ok)
	var warrior := spawn(game, "warrior", 0, 2, 2)
	assert_false(game.issue_order(0, Orders.found_city(warrior.id, warrior.coord)).ok, "warriors cannot found cities")


func test_purchase_orders_reserve_gold() -> void:
	var game := _setup()
	var settler := spawn(game, "settler", 0, 4, 4)
	game.issue_order(0, Orders.found_city(settler.id, settler.coord))
	var city := _city(game, 0, 4, 4)
	game.state.player(0).gold = CityRules.purchase_cost("unit", "warrior") + 1
	var other := _city(game, 0, 8, 8)
	game.state.player(0).set_order(Orders.purchase(other.id, "unit", "warrior"))
	assert_false(game.issue_order(0, Orders.purchase(city.id, "unit", "warrior")).ok,
			"gold is already committed to the other city's purchase")
	game.state.player(0).gold *= 2
	assert_true(game.issue_order(0, Orders.purchase(city.id, "unit", "warrior")).ok)


func test_unit_priority_is_stable_and_stored() -> void:
	var game := _setup()
	var a := spawn(game, "warrior", 0, 2, 2)
	var b := spawn(game, "warrior", 0, 3, 3)
	assert_between(a.priority, 0, 99)
	assert_true(a.priority != b.priority or a.id != b.id)
	var again := make_flat_game(12, 10, 2)
	assert_eq(spawn(again, "warrior", 0, 2, 2).priority, a.priority, "same seed and id give the same priority")
	var s2 := GameState.from_dict(JSON.parse_string(JSON.stringify(game.state.to_dict())))
	assert_eq(s2.get_unit(a.id).priority, a.priority)


func test_newer_save_versions_are_rejected() -> void:
	var game := _setup()
	var d: Dictionary = JSON.parse_string(JSON.stringify(game.state.to_dict()))
	d.version = GameState.VERSION + 1
	assert_eq(GameState.from_dict(d), null)


# --- Resolution --------------------------------------------------------------

func test_ranged_fires_before_anyone_moves() -> void:
	var game := _setup()
	var archer := spawn(game, "archer", 0, 4, 4)
	var target := spawn(game, "warrior", 1, 6, 4)
	var away := Hex.offset_to_axial(8, 4)
	assert_true(game.attack(archer.id, target.coord))
	assert_true(game.move_unit(target.id, away))
	game.resolve_ticks()
	assert_true(target.hp < 100, "the shot hit the tile the target started on")
	assert_eq(target.coord, away, "and the target still got away")


func test_priority_decides_a_contested_tile() -> void:
	var game := _setup()
	var a := spawn(game, "warrior", 0, 3, 4)
	var b := spawn(game, "warrior", 1, 5, 4)
	a.priority = 90
	b.priority = 10
	var middle := Hex.offset_to_axial(4, 4)
	assert_true(game.move_unit(a.id, middle))
	assert_true(game.move_unit(b.id, middle))
	game.resolve_ticks()
	assert_eq(a.coord, middle, "the higher priority unit arrived first")
	assert_eq(b.coord, Hex.offset_to_axial(5, 4), "the other found it occupied and attacked instead")
	assert_true(a.hp < 100 and b.hp < 100, "the fight hurt both")


func test_head_on_enemy_swap_is_a_fight() -> void:
	var game := _setup()
	var a := spawn(game, "warrior", 0, 3, 4)
	var b := spawn(game, "warrior", 1, 4, 4)
	a.priority = 90
	b.priority = 10
	var fights := [0]
	game.combat_resolved.connect(func(_r): fights[0] += 1)
	assert_true(game.move_unit(a.id, b.coord))
	assert_true(game.move_unit(b.id, a.coord))
	game.resolve_ticks()
	assert_eq(fights[0], 2, "each side struck the other")
	assert_eq(a.coord, Hex.offset_to_axial(3, 4))
	assert_eq(b.coord, Hex.offset_to_axial(4, 4))


func test_friendly_swap_stays_blocked_and_keeps_orders() -> void:
	var game := _setup()
	var a := spawn(game, "warrior", 0, 3, 4)
	var b := spawn(game, "warrior", 0, 4, 4)
	# Each unit looks stationary to the other until it has an order, so build the swap up in steps.
	assert_false(game.move_unit(a.id, b.coord), "b is not leaving yet")
	assert_true(game.move_unit(b.id, Hex.offset_to_axial(8, 4)))
	assert_true(game.move_unit(a.id, b.coord), "now b is leaving")
	assert_true(game.move_unit(b.id, a.coord), "and a is leaving too")
	game.resolve_ticks()
	assert_eq(a.coord, Hex.offset_to_axial(3, 4))
	assert_eq(b.coord, Hex.offset_to_axial(4, 4))
	var p := game.state.player(0)
	assert_eq(p.unit_order(a.id).get("type"), "move", "a blocked unit keeps its order")
	assert_eq(p.unit_order(b.id).get("type"), "move")


func test_a_column_advances_in_one_turn() -> void:
	var game := _setup(14, 8)
	var a := spawn(game, "warrior", 0, 2, 4)
	var b := spawn(game, "warrior", 0, 3, 4)
	var c := spawn(game, "warrior", 0, 4, 4)
	a.priority = 90   # the rear unit goes first, and has to wait for the others to clear the way
	b.priority = 50
	c.priority = 10
	assert_true(game.move_unit(c.id, Hex.offset_to_axial(6, 4)))
	assert_true(game.move_unit(b.id, Hex.offset_to_axial(5, 4)))
	assert_true(game.move_unit(a.id, Hex.offset_to_axial(4, 4)))
	game.resolve_ticks()
	assert_eq(c.coord, Hex.offset_to_axial(6, 4))
	assert_eq(b.coord, Hex.offset_to_axial(5, 4))
	assert_eq(a.coord, Hex.offset_to_axial(4, 4))


func test_melee_contact_table() -> void:
	var game := _setup()
	var enemy := spawn(game, "warrior", 1, 5, 4)
	var melee := spawn(game, "warrior", 0, 4, 4)
	var archer := spawn(game, "archer", 0, 4, 3)
	var settler := spawn(game, "settler", 0, 4, 5)
	var resolver := TurnResolver.new(game)
	var make_rt := func(u: Unit) -> Dictionary:
		return {"path": [enemy.coord], "idx": 0, "kind": "move", "at": enemy.coord, "owner": u.owner, "stopped": false, "done": false}
	game._resolving = true
	assert_eq(resolver._try_step(archer, make_rt.call(archer)), "stopped", "ranged units never attack on contact")
	assert_eq(resolver._try_step(settler, make_rt.call(settler)), "stopped", "civilians never do")
	assert_eq(enemy.hp, 100)
	assert_eq(resolver._try_step(melee, make_rt.call(melee)), "fought", "melee units do, whatever their order was")
	assert_true(enemy.hp < 100)
	assert_eq(melee.moves_left, 0, "and stop for the turn")
	game._resolving = false


func test_capturing_a_civilian_on_entry() -> void:
	var game := _setup()
	var warrior := spawn(game, "warrior", 0, 3, 4)
	var settler := spawn(game, "settler", 1, 5, 4)
	assert_true(game.move_unit(warrior.id, settler.coord))
	game.resolve_ticks()
	assert_eq(settler.owner, 0, "walked onto it and captured it")
	assert_eq(warrior.coord, settler.coord)


func test_simultaneous_ranged_kills() -> void:
	var game := _setup()
	var a := spawn(game, "archer", 0, 3, 4)
	var b := spawn(game, "archer", 1, 5, 4)
	a.hp = 1
	b.hp = 1
	assert_true(game.attack(a.id, b.coord))
	assert_true(game.attack(b.id, a.coord))
	game.resolve_ticks()
	assert_false(game.state.units.has(a.id), "both shots landed before anyone was removed")
	assert_false(game.state.units.has(b.id))


func test_city_bombard_order() -> void:
	var game := _setup()
	var city := _city(game, 0, 4, 4)
	var enemy := spawn(game, "warrior", 1, 5, 4)
	assert_true(game.city_attack(city.id, enemy.coord))
	game.resolve_ticks()
	assert_true(enemy.hp < 100)
	assert_true(game.state.player(0).orders.is_empty(), "the bombard order is spent")


func test_wake_clears_a_stance() -> void:
	var game := _setup()
	var u := spawn(game, "warrior", 0, 4, 4)
	assert_true(game.fortify(u.id))
	game.resolve_ticks()
	assert_true(u.fortified)
	assert_true(game.wake(u.id))
	game.resolve_ticks()
	assert_false(u.fortified)


func test_founding_conflict_is_rechecked_at_resolution() -> void:
	var game := _setup()
	var first := spawn(game, "settler", 0, 4, 4)
	var second := spawn(game, "settler", 0, 6, 4)
	first.priority = 90
	second.priority = 10
	assert_true(game.issue_order(0, Orders.found_city(first.id, first.coord)).ok)
	var site := Hex.offset_to_axial(5, 4)
	assert_true(game.issue_order(0, Orders.found_city(second.id, site)).ok, "legal while planning")
	game.resolve_ticks()
	assert_eq(game.state.cities.size(), 1, "only one city fits")
	assert_true(game.state.units.has(second.id), "the loser keeps its settler")
	assert_true(game.state.player(0).unit_order(second.id).is_empty(), "and its order is dropped")


func test_disband_runs_in_the_economy_phase() -> void:
	var game := _setup()
	var u := spawn(game, "warrior", 0, 4, 4)
	assert_true(game.disband(u.id))
	assert_true(game.state.units.has(u.id), "planning removes nothing")
	game.resolve_turn()
	assert_false(game.state.units.has(u.id))


func test_resolution_does_not_depend_on_the_order_orders_were_issued() -> void:
	var results: Array = []
	for reverse in [false, true]:
		var game := _setup(14, 8)
		var units: Array = []
		for i in 4:
			units.append(spawn(game, "warrior", i % 2, 2 + i, 3 + (i % 2)))
		var orders: Array = []
		for u in units:
			orders.append(Orders.move(u.id, Hex.offset_to_axial(7, 4)))
		if reverse:
			orders.reverse()
		for o in orders:
			game.issue_order(game.state.get_unit(o.id).owner, o)
		game.resolve_ticks()
		results.append(JSON.stringify(game.state.to_dict()))
	assert_eq(results[0], results[1])


func test_random_orders_keep_the_world_consistent() -> void:
	var game := make_flat_game(14, 10, 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 123
	for pid in 2:
		for i in 6:
			var kind: String = ["warrior", "archer", "settler"][i % 3]
			spawn(game, kind, pid, 2 + i + pid * 4, 2 + pid * 5 + (i % 2))
	for turn in 25:
		for u in game.state.units.values().duplicate():
			if not game.state.units.has(u.id):
				continue
			match rng.randi() % 4:
				0:
					game.issue_order(u.owner, Orders.move(u.id, Hex.offset_to_axial(rng.randi() % 14, rng.randi() % 10)))
				1:
					game.fortify(u.id)
				2:
					if u.is_ranged():
						for c in Hex.within(u.coord, u.attack_range()):
							if game.attack(u.id, c):
								break
				_:
					game.cancel_orders(u.id)
		game.resolve_ticks()
		var seen := {}
		for u in game.state.units.values():
			var t := game.state.tile(u.coord)
			assert_true(t != null and t.is_passable_land(), "turn %d: unit on land" % turn)
			assert_true(u.hp > 0, "turn %d: unit alive" % turn)
			var key := "%s:%s" % [u.coord, u.is_military()]
			assert_false(seen.has(key), "turn %d: two same-kind units on %s" % [turn, u.coord])
			seen[key] = true


# --- Turn flow and victory ---------------------------------------------------

func test_submit_turn_resolves_when_everyone_has_submitted() -> void:
	var game := _setup()
	game.state.player(1).is_human = true
	var u := spawn(game, "warrior", 0, 4, 4)
	assert_true(game.submit_turn(0))
	assert_eq(game.state.turn, 1, "still waiting for the other human")
	assert_false(game.issue_order(0, Orders.fortify(u.id)).ok, "a submitted turn is locked")
	assert_true(game.unsubmit_turn(0))
	assert_true(game.issue_order(0, Orders.fortify(u.id)).ok)
	assert_true(game.submit_turn(0))
	assert_true(game.submit_turn(1))
	assert_eq(game.state.turn, 2, "both submitted: the turn resolved")
	assert_true(u.fortified)
	assert_false(game.state.player(0).ready, "submissions reset for the next turn")
	assert_eq(game.state.time, int(Defs.rules.turn.seconds))


func test_ai_planning_ignores_other_players_orders() -> void:
	var game := make_flat_game(16, 12, 2)
	spawn(game, "warrior", 0, 3, 3)
	spawn(game, "settler", 1, 10, 8)
	game.state.player(0).orders = ["poison"]  # anything that reads player 0's orders will choke on this
	AIPlayer.plan_turn(game, game.state.player(1))
	assert_eq(game.state.player(0).orders, ["poison"])
	assert_false(game.state.player(1).orders.is_empty(), "the AI planned something")


func test_simultaneous_science_victory_goes_to_the_higher_score() -> void:
	var game := _setup()
	game.state.player(1).techs["pottery"] = true  # a higher score
	game._science_winners = [0, 1]
	game._decide_victory()
	assert_true(game.state.game_over)
	assert_eq(game.state.winner, 1)
	assert_eq(game.state.victory_type, "science")


func test_equal_scores_go_to_the_lower_player_id() -> void:
	var game := _setup()
	game._science_winners = [1, 0]
	game._decide_victory()
	assert_eq(game.state.winner, 0)


func test_mutual_elimination_is_a_draw() -> void:
	var game := _setup()
	game.state.player(0).alive = false
	game.state.player(1).alive = false
	game._decide_victory()
	assert_true(game.state.game_over)
	assert_eq(game.state.winner, -1)
	assert_eq(game.state.victory_type, "draw")


# --- helpers ---------------------------------------------------------------

## Everything about the world that planning must not change (orders and ready flags excluded).
func _world(s: GameState) -> Dictionary:
	var d := s.to_dict()
	for p in d.players:
		p.erase("orders")
		p.erase("ready")
	return d


func _city(game: Game, owner: int, col: int, row: int) -> City:
	var city := City.new()
	city.id = game.state.new_id()
	city.owner = owner
	city.coord = Hex.offset_to_axial(col, row)
	city.name = "Testville"
	city.population = 3
	city.hp = Combat.city_max_hp(city)
	game.state.add_city(city)
	game.state.tile(city.coord).owner = owner
	game.state.tile(city.coord).city_id = city.id
	return city
