extends TestCase
## Whole-game smoke tests: AI-only games exercise every rule path.


func _check_invariants(game: Game, label: String) -> void:
	var s := game.state
	var military_tiles := {}
	var civilian_tiles := {}
	for u in s.units.values():
		var t := s.tile(u.coord)
		assert_true(t != null and t.is_passable_land(), "%s: unit %d on passable land" % [label, u.id])
		assert_true(u.hp > 0 and u.hp <= 100, "%s: unit hp %d" % [label, u.hp])
		assert_true(s.players[u.owner].alive, "%s: unit of dead player" % label)
		assert_true(u in s.units_at(u.coord), "%s: unit index" % label)
		var bucket := military_tiles if u.is_military() else civilian_tiles
		if bucket.has(u.coord):
			var who := PackedStringArray()
			for o in s.units_at(u.coord):
				who.append("%s(p%d)" % [o.type, o.owner])
			assert_true(false, "%s: stacked units at %s: %s" % [label, u.coord, ", ".join(who)])
		bucket[u.coord] = true
	for city in s.cities.values():
		assert_eq(s.tile(city.coord).owner, city.owner, "%s: city tile owner" % label)
		assert_eq(s.tile(city.coord).city_id, city.id, "%s: city tile city" % label)
		assert_true(city.worked.size() <= city.population, "%s: worked <= pop" % label)
		for c in city.worked:
			assert_eq(s.tile(c).city_id, city.id, "%s: worked tile belongs to city" % label)
		var enemy := s.military_at(city.coord)
		assert_true(enemy == null or enemy.owner == city.owner, "%s: enemy inside city" % label)


func _summary(game: Game) -> String:
	var parts := PackedStringArray()
	for p in game.state.players:
		var mil := 0
		for u in game.state.player_units(p.id):
			if u.is_military():
				mil += 1
		parts.append("%s[%s] cities=%d pop=%d techs=%d army=%d gold=%d" % [
			p.name, "alive" if p.alive else "dead", game.state.player_cities(p.id).size(),
			game.state.player_cities(p.id).reduce(func(acc, c): return acc + c.population, 0),
			p.techs.size(), mil, p.gold])
	return "turn %d: %s" % [game.state.turn, " | ".join(parts)]


func test_ai_game_runs_and_develops() -> void:
	var game := Game.new_game({"width": 32, "height": 20, "players": 3, "seed": 7, "human": false})
	var combats := [0]
	game.combat_resolved.connect(func(_r): combats[0] += 1)
	game.start()
	var started := Time.get_ticks_msec()
	for checkpoint in [20, 40, 60, 80, 100, 120, 150]:
		game.run_ai_turns(checkpoint)
		_check_invariants(game, "t%d" % checkpoint)
		print("    " + _summary(game))
		if game.state.game_over:
			break
	var elapsed := Time.get_ticks_msec() - started
	print("    %d turns in %d ms (%.1f ms/turn), %d combats, result: %s %s" % [
		game.state.turn, elapsed, float(elapsed) / game.state.turn, combats[0],
		game.state.victory_type, game.state.winner])
	var total_cities := game.state.cities.size()
	assert_true(total_cities >= 5, "AIs expanded (cities=%d)" % total_cities)
	var max_techs := 0
	for p in game.state.players:
		max_techs = maxi(max_techs, p.techs.size())
	assert_true(max_techs >= 6, "AIs researched (max techs=%d)" % max_techs)
	assert_true(combats[0] > 0, "AIs fought")


func test_invariants_hold_across_seeds() -> void:
	for seed_value in [11, 12, 13, 14, 15]:
		var game := Game.new_game({"width": 32, "height": 20, "players": 4, "seed": seed_value, "human": false})
		game.start()
		for checkpoint in range(10, 121, 10):
			game.run_ai_turns(checkpoint)
			_check_invariants(game, "seed %d t%d" % [seed_value, checkpoint])
			if game.state.game_over:
				break
		print("    seed %d: %s (%s)" % [seed_value, _summary(game), game.state.victory_type])


func test_simulation_is_deterministic() -> void:
	var a := Game.new_game({"width": 32, "height": 20, "players": 3, "seed": 21, "human": false})
	var b := Game.new_game({"width": 32, "height": 20, "players": 3, "seed": 21, "human": false})
	a.start()
	b.start()
	a.run_ai_turns(40)
	b.run_ai_turns(40)
	assert_eq(JSON.stringify(a.state.to_dict()), JSON.stringify(b.state.to_dict()))


func test_medium_map_performance() -> void:
	var game := Game.new_game({"width": 44, "height": 28, "players": 4, "seed": 3, "human": false})
	game.start()
	var started := Time.get_ticks_msec()
	game.run_ai_turns(80)
	var elapsed := Time.get_ticks_msec() - started
	_check_invariants(game, "medium")
	print("    " + _summary(game))
	print("    medium map: %d turns in %d ms (%.1f ms/turn)" % [game.state.turn, elapsed, float(elapsed) / game.state.turn])
	assert_true(float(elapsed) / game.state.turn < 400.0, "AI turn time reasonable")
