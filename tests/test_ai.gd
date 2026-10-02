extends TestCase
## AI decisions that can be checked without simulating a whole game.


func test_ai_builds_within_its_budget() -> void:
	var game := make_flat_game()
	var s := game.state
	var p := s.player(0)
	var settler := spawn(game, "settler", 0, 4, 4)
	var at := settler.coord
	game.found_city(settler.id)
	game.resolve_ticks()
	var city := s.city_at(at)
	city.buildings["monument"] = true
	for t in ["pottery", "writing"]:  # granary and library: 1 upkeep each
		game.learn_tech(p, t)
	# Enough settlers and warriors that the AI wants neither; 7 units with 4 free
	# (3 + 1 per city) cost exactly the palace's 3 gold.
	for i in 2:
		spawn(game, "settler", 0, 8, 2 + i)
	for i in 5:
		spawn(game, "warrior", 0, 2 + i, 7)
	assert_eq(int(CityRules.player_income(s, 0).net_gold), 0)
	assert_eq(AIPlayer._choose_build(game, p, city), {}, "broke: nothing that adds upkeep")

	city.population = 6  # +3 gold in taxes
	CityRules.assign_work(s, city)
	assert_eq(int(CityRules.player_income(s, 0).net_gold), 3)
	assert_eq(AIPlayer._choose_build(game, p, city), {"kind": "building", "id": "granary"})

	game.learn_tech(p, "currency")
	city.population = 4  # 2 net gold: the market jumps the queue
	CityRules.assign_work(s, city)
	assert_eq(AIPlayer._choose_build(game, p, city), {"kind": "building", "id": "market"})


func test_ai_considers_buildings_added_to_the_data() -> void:
	Defs.buildings["test_hall"] = {"id": "test_hall", "name": "Test Hall", "icon": "award", "cost": 500, "upkeep": 0}
	var order := AIPlayer._building_order(10)
	Defs.buildings.erase("test_hall")
	assert_eq(order.find("test_hall"), order.size() - 1, "unknown buildings go last")
	assert_eq(order.slice(0, AIPlayer.BUILDING_PRIORITY.size()), AIPlayer.BUILDING_PRIORITY)
