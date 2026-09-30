extends TestCase


func test_references_are_valid() -> void:
	var problems := Defs.validate()
	assert_eq(problems.size(), 0, str(problems))


func test_art_and_icons_exist() -> void:
	for id in Defs.terrains:
		for key in Defs.terrains[id].art:
			for entry in Defs.terrains[id].art[key]:
				var parts: PackedStringArray = String(entry).split("+")
				assert_true(FileAccess.file_exists("res://assets/terrain/%s.png" % parts[0]), entry)
				for i in range(1, parts.size()):
					assert_true(FileAccess.file_exists("res://assets/objects/%s.png" % parts[i]), entry)
	for table in [Defs.units, Defs.resources, Defs.buildings]:
		for id in table:
			var icon: String = table[id].get("icon", "")
			assert_true(FileAccess.file_exists("res://assets/icons/%s.png" % icon), "%s icon %s" % [id, icon])


func test_every_tech_reachable() -> void:
	var p := Player.new()
	for id in Defs.techs:
		var path := TechRules.path_to(p, id)
		assert_eq(path[-1], id)
		for i in path.size():
			for req in Defs.techs[path[i]].requires:
				assert_true(path.find(req) < i, "%s before %s" % [req, path[i]])


func test_map_generation_is_deterministic_and_sane() -> void:
	var a := MapGenerator.generate(44, 28, 1234, 4)
	var b := MapGenerator.generate(44, 28, 1234, 4)
	assert_eq(a.starts, b.starts)
	var sig_a := ""
	var sig_b := ""
	for i in a.map.size():
		sig_a += a.map.tiles[i].terrain[0] + a.map.tiles[i].elevation[0]
		sig_b += b.map.tiles[i].terrain[0] + b.map.tiles[i].elevation[0]
	assert_eq(sig_a, sig_b)
	assert_eq(a.starts.size(), 4)
	var land := 0
	for t in a.map.tiles:
		if not t.is_water():
			land += 1
	assert_between(float(land) / a.map.size(), 0.35, 0.55, "land ratio")
	for i in a.starts.size():
		var t: Tile = a.map.get_tile(a.starts[i])
		assert_true(t.is_passable_land(), "start on land")
		for j in range(i + 1, a.starts.size()):
			assert_true(Hex.distance(a.starts[i], a.starts[j]) >= 4, "starts spread out")


func test_many_seeds_place_all_starts() -> void:
	for seed_value in range(1, 13):
		var g := MapGenerator.generate(32, 20, seed_value, 3)
		assert_eq(g.starts.size(), 3, "seed %d" % seed_value)
