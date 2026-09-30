extends TestCase


# --- Movement --------------------------------------------------------------

func test_reachable_on_flat_ground() -> void:
	var game := make_flat_game()
	var u := spawn(game, "warrior", 0, 4, 4)
	assert_eq(Pathfinder.reachable(game.state, u).size(), 18, "2 moves on flat = radius 2")


func test_hills_cost_more_and_mountains_block() -> void:
	var game := make_flat_game()
	var s := game.state
	var u := spawn(game, "warrior", 0, 4, 4)
	var east := u.coord + Vector2i(1, 0)
	s.tile(east).elevation = "hills"
	s.tile(east + Vector2i(1, 0)).elevation = "mountains"
	var reach := Pathfinder.reachable(s, u)
	assert_eq(reach.get(east), 2, "hills cost 2")
	assert_false(reach.has(east + Vector2i(1, 0)), "mountain impassable")
	assert_true(Pathfinder.find_path(s, u, east + Vector2i(1, 0)).is_empty())


func test_any_remaining_move_enters_rough_tile() -> void:
	var game := make_flat_game()
	var s := game.state
	var u := spawn(game, "warrior", 0, 4, 4)
	var a := u.coord + Vector2i(1, 0)
	var b := a + Vector2i(1, 0)
	s.tile(b).feature = "forest"
	s.tile(b).elevation = "hills"   # cost 3
	assert_true(game.move_unit(u.id, b))
	assert_eq(u.coord, b, "moved 1 then entered cost-3 tile with 1 move left")
	assert_eq(u.moves_left, 0)


func test_multi_turn_path_annotation() -> void:
	var game := make_flat_game(14, 6)
	var u := spawn(game, "warrior", 0, 1, 2)
	var target := Hex.offset_to_axial(6, 2)
	var path := Pathfinder.find_path(game.state, u, target)
	assert_eq(path.size(), 5)
	var turns: Array = Pathfinder.annotate(game.state, u, path).map(func(s): return s.turn)
	assert_eq(turns, [0, 0, 1, 1, 2])


func test_move_orders_continue_next_turn() -> void:
	var game := make_flat_game(14, 6)
	var u := spawn(game, "warrior", 0, 1, 2)
	var target := Hex.offset_to_axial(6, 2)
	assert_true(game.move_unit(u.id, target))
	assert_eq(Hex.distance(u.coord, target), 3)
	assert_true(u.has_destination)
	game._begin_player_turn(game.state.player(0))
	assert_eq(Hex.distance(u.coord, target), 1)
	game._begin_player_turn(game.state.player(0))
	assert_eq(u.coord, target)
	assert_false(u.has_destination)


func test_no_stacking_military_units() -> void:
	var game := make_flat_game()
	var a := spawn(game, "warrior", 0, 4, 4)
	var b := spawn(game, "warrior", 0, 5, 4)
	assert_false(game.move_unit(a.id, b.coord))
	var settler := spawn(game, "settler", 0, 3, 4)
	assert_true(game.move_unit(settler.id, a.coord), "civilian may share with military")


func test_enemy_units_block_movement() -> void:
	var game := make_flat_game()
	var a := spawn(game, "warrior", 0, 4, 4)
	var e := spawn(game, "warrior", 1, 5, 4)
	assert_false(game.move_unit(a.id, e.coord))


# --- Combat ----------------------------------------------------------------

func test_equal_units_trade_expected_damage() -> void:
	var game := make_flat_game()
	var a := spawn(game, "warrior", 0, 4, 4)
	var d := spawn(game, "warrior", 1, 5, 4)
	var info := Combat.preview(game.state, a, d.coord)
	assert_eq(info.attack, 20)
	assert_eq(info.defense, 20)
	assert_eq(info.damage_to_defender, 30)
	assert_eq(info.damage_to_attacker, 30)
	assert_true(game.attack(a.id, d.coord))
	assert_between(d.hp, 100 - 36, 100 - 24)
	assert_between(a.hp, 100 - 36, 100 - 24)
	assert_eq(a.moves_left, 0)
	assert_false(game.attack(a.id, d.coord), "one attack per turn")


func test_terrain_and_fortify_help_defender() -> void:
	var game := make_flat_game()
	var a := spawn(game, "warrior", 0, 4, 4)
	var d := spawn(game, "warrior", 1, 5, 4)
	game.state.tile(d.coord).elevation = "hills"
	d.fortified = true
	var info := Combat.preview(game.state, a, d.coord)
	assert_eq(info.defense, 20 + 3 + 4)
	assert_true(info.damage_to_defender < 30)
	assert_true(info.damage_to_attacker > 30)


func test_spearman_bonus_vs_mounted() -> void:
	var game := make_flat_game()
	var h := spawn(game, "horseman", 0, 4, 4)
	var sp := spawn(game, "spearman", 1, 5, 4)
	var info := Combat.preview(game.state, h, sp.coord)
	assert_eq(info.defense, 35, "25 + 10 vs mounted")


func test_ranged_attack_takes_no_damage() -> void:
	var game := make_flat_game()
	var a := spawn(game, "archer", 0, 4, 4)
	var d := spawn(game, "warrior", 1, 6, 4)
	assert_eq(Hex.distance(a.coord, d.coord), 2)
	assert_true(game.attack(a.id, d.coord))
	assert_eq(a.hp, 100)
	assert_true(d.hp < 100)


func test_melee_kill_advances_and_captures_civilian() -> void:
	var game := make_flat_game()
	var a := spawn(game, "warrior", 0, 4, 4)
	var d := spawn(game, "warrior", 1, 5, 4)
	var civ := spawn(game, "settler", 1, 5, 4)
	d.hp = 1
	var target := d.coord
	assert_true(game.attack(a.id, target))
	assert_false(game.state.units.has(d.id), "defender destroyed")
	assert_eq(a.coord, target, "attacker advanced")
	assert_eq(civ.owner, 0, "settler captured")


func test_wounded_units_fight_worse() -> void:
	var game := make_flat_game()
	var a := spawn(game, "warrior", 0, 4, 4)
	var d := spawn(game, "warrior", 1, 5, 4)
	a.hp = 50
	assert_eq(Combat.preview(game.state, a, d.coord).attack, 15)


# --- Cities ----------------------------------------------------------------

func test_found_city_claims_tiles() -> void:
	var game := make_flat_game()
	var s := game.state
	var settler := spawn(game, "settler", 0, 4, 4)
	var at := settler.coord
	assert_true(game.found_city(settler.id))
	var city := s.city_at(at)
	assert_true(city != null)
	assert_true(city.is_capital(), "first city gets the palace")
	assert_false(s.units.has(settler.id), "settler consumed")
	var owned := 0
	for t in s.map.tiles:
		if t.city_id == city.id:
			owned += 1
	assert_eq(owned, 7)
	assert_eq(city.worked.size(), 1)
	var second := spawn(game, "settler", 0, 6, 4)
	assert_true(CityRules.found_blocker(s, 0, second.coord) != "", "too close")
	assert_false(game.found_city(second.id))


func test_city_yields_growth_and_production() -> void:
	var game := make_flat_game()
	var s := game.state
	var settler := spawn(game, "settler", 0, 4, 4)
	var at := settler.coord
	game.found_city(settler.id)
	var city := s.city_at(at)
	var y := CityRules.city_yields(s, city)
	# center 2F1P + worked grass 2F + base (1S 1C) + palace (3P 2S 3G 1C)
	assert_eq(y, {"food": 4, "production": 4, "gold": 3, "science": 3, "culture": 2})
	assert_true(game.set_production(city.id, "unit", "warrior"))
	var turns := 0
	while s.player_units(0).is_empty() and turns < 20:
		CityRules.process_turn(game, city)
		turns += 1
	assert_eq(turns, 8, "30 production at 4/turn")
	assert_eq(city.population, 2, "grew after 8 turns of +2 food")
	assert_true(city.build.is_empty(), "production slot cleared after completion")


func test_settler_needs_population() -> void:
	var game := make_flat_game()
	var s := game.state
	var settler := spawn(game, "settler", 0, 4, 4)
	var at := settler.coord
	game.found_city(settler.id)
	var city := s.city_at(at)
	game.set_production(city.id, "unit", "settler")
	city.production = 100
	city.food = -1000  # prevent growth this turn
	CityRules.process_turn(game, city)
	assert_eq(s.player_units(0).size(), 0, "size-1 city can't finish a settler")
	assert_eq(city.build.get("id", ""), "settler")
	city.population = 2
	CityRules.process_turn(game, city)
	assert_eq(s.player_units(0).size(), 1)
	assert_eq(city.population, 1)


func test_borders_grow_with_culture() -> void:
	var game := make_flat_game()
	var s := game.state
	var settler := spawn(game, "settler", 0, 4, 4)
	var at := settler.coord
	game.found_city(settler.id)
	var city := s.city_at(at)
	for i in 10:
		CityRules.process_turn(game, city)
	assert_true(city.border_growths >= 1, "10 turns at 2 culture passes the first threshold")
	for t in s.map.tiles:
		if t.city_id == city.id:
			assert_true(Hex.distance(t.coord, city.coord) <= 3)


func test_capture_city() -> void:
	var game := make_flat_game()
	var s := game.state
	var settler := spawn(game, "settler", 1, 5, 4)
	var at := settler.coord
	s.current_player = 1
	game.found_city(settler.id)
	s.current_player = 0
	var city := s.city_at(at)
	city.population = 3
	city.hp = 1
	var w := spawn(game, "warrior", 0, 4, 4)
	assert_true(game.attack(w.id, at))
	assert_eq(city.owner, 0, "captured")
	assert_eq(city.population, 2)
	assert_false(city.is_capital())
	assert_eq(w.coord, at)
	assert_eq(s.tile(at).owner, 0)
	assert_false(s.player(1).alive, "player 1 eliminated")


func test_strategic_resource_gates_units() -> void:
	var game := make_flat_game()
	var s := game.state
	var p := s.player(0)
	p.techs["horseback_riding"] = true
	p.techs["animal_husbandry"] = true
	var settler := spawn(game, "settler", 0, 4, 4)
	var at := settler.coord
	game.found_city(settler.id)
	var city := s.city_at(at)
	assert_true(CityRules.build_blocker(s, city, "unit", "horseman") != "")
	s.tile(at + Vector2i(1, 0)).resource = "horses"
	assert_eq(CityRules.build_blocker(s, city, "unit", "horseman"), "")


func test_purchase() -> void:
	var game := make_flat_game()
	var s := game.state
	var settler := spawn(game, "settler", 0, 4, 4)
	var at := settler.coord
	game.found_city(settler.id)
	var city := s.city_at(at)
	s.player(0).gold = 1000
	assert_true(game.purchase(city.id, "unit", "warrior"))
	assert_eq(s.player(0).gold, 1000 - 90)
	assert_true(s.military_at(at) != null)
	assert_true(game.purchase(city.id, "building", "monument"))
	assert_true(city.has_building("monument"))


# --- Research --------------------------------------------------------------

func test_research_path_and_overflow() -> void:
	var game := make_flat_game()
	var p := game.state.player(0)
	assert_true(game.set_research(0, "mathematics"))
	assert_eq(p.research, "pottery")
	assert_eq(p.research_queue, ["writing", "archery", "mathematics"])
	TechRules.add_science(game, p, 30)
	assert_true(p.has_tech("pottery"))
	assert_eq(p.research, "writing")
	assert_eq(TechRules.progress(p, "writing"), 5)
	TechRules.add_science(game, p, 80)  # 85 total: writing (50) then archery (25), 10 left
	assert_true(p.has_tech("writing"))
	assert_true(p.has_tech("archery"))
	assert_eq(p.research, "mathematics")
	assert_eq(TechRules.progress(p, "mathematics"), 10)


func test_tech_unlocks_listed() -> void:
	var u := TechRules.unlocks("bronze_working")
	assert_true("spearman" in u.units)
	assert_true("iron" in u.resources)
	assert_eq(TechRules.unlocks("mining").bonuses.size(), 1)


# --- Save / load -----------------------------------------------------------

func test_save_load_round_trip() -> void:
	var game := Game.new_game({"width": 32, "height": 20, "players": 3, "seed": 99, "human": true})
	game.start()
	for i in 3:
		game.end_turn()
	var path := "user://test_roundtrip.json"
	assert_true(SaveLoad.save(game, path))
	var loaded := SaveLoad.load_game(path)
	assert_true(loaded != null)
	assert_eq(JSON.stringify(loaded.state.to_dict()), JSON.stringify(game.state.to_dict()))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# --- Messages --------------------------------------------------------------

func test_article() -> void:
	assert_eq(Game.article("Warrior"), "a Warrior")
	assert_eq(Game.article("Archer"), "an Archer")
	assert_eq(Game.article("Eskar Horseman"), "an Eskar Horseman")
