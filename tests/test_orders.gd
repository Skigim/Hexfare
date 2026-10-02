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
