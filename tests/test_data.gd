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


## Sprite-sheet units: every role exists in all six facings, frames lie inside the sheet, the mask
## matches it, and a step toward each hex neighbour picks that neighbour's facing.
func test_unit_sprite_sheets() -> void:
	for d in Hex.DIRECTIONS.size():
		assert_eq(UnitSprite.direction_toward(Hex.to_pixel(Hex.DIRECTIONS[d])), d, "facing for direction %d" % d)
	for id in Defs.units:
		if not UnitSprite.has_sheet(id):
			continue
		var s := UnitSprite.create(id, Color.WHITE)
		assert_true(s != null, "%s sheet loads" % id)
		if s == null:
			continue
		assert_eq(s._directions.size(), Hex.DIRECTIONS.size(), "%s facings" % id)
		var sheet: Texture2D = (s.sprite_frames.get_frame_texture("idle_se", 0) as AtlasTexture).atlas
		var mask: Texture2D = (s.material as ShaderMaterial).get_shader_parameter("mask_tex")
		assert_eq(mask.get_size(), sheet.get_size(), "%s mask matches its sheet" % id)
		var bounds := Rect2(Vector2.ZERO, sheet.get_size())
		# Units that fight need every role; civilians (captured, never killed) just stand and walk.
		var roles: Array = UnitSprite.BASIC_ROLES if Defs.units[id].get("class", "") == "civilian" else UnitSprite.ROLES
		for role in roles:
			for dir in s._directions:
				var anim := "%s_%s" % [role, dir]
				assert_true(s.sprite_frames.has_animation(anim), "%s %s" % [id, anim])
				var last := s.sprite_frames.get_frame_count(anim) - 1
				var region := (s.sprite_frames.get_frame_texture(anim, last) as AtlasTexture).region
				assert_true(bounds.encloses(region), "%s %s last frame inside the sheet" % [id, anim])
		s.free()


## On the map, units with a sprite sheet are animated figures; the rest keep their tokens.
func test_unit_views_use_sprite_sheets() -> void:
	var game := make_flat_game()
	# Every unit in the data has a sheet; a unit added without one (a mod) is drawn as a token.
	Defs.units["sheetless"] = Defs.units.warrior.duplicate()
	var views: Array[UnitView] = []
	for type in ["warrior", "settler", "sheetless", "archer"]:
		var v := UnitView.new()
		v.sync_from(spawn(game, type, 0, 2 + views.size() * 2, 2), Color.BLUE, true)
		views.append(v)
	Defs.units.erase("sheetless")
	assert_true(views[0].sprite != null, "a warrior is drawn as a figure")
	assert_true(views[1].sprite != null, "a settler is drawn as a figure")
	assert_true(views[2].sprite == null, "a unit without a sheet keeps its token")
	assert_true(views[1].base_radii().x > views[0].base_radii().x, "the settler pair stands on a wider base")
	views[1].sprite.act("attack")
	assert_eq(views[1].sprite.role, "idle", "a role the sheet lacks plays idle")
	var strike := views[1].founding_time()
	assert_true(strike > 0.0 and strike < views[1].sprite.role_time("build"), "the settler's last blow lands inside its build")
	assert_eq(views[0].founding_time(), 0.0, "a warrior has no build")
	# A ranged figure shoots on its attack's "release" mark; a token shoots at once.
	var release := views[3].shoot(Vector2(300, 0))
	assert_true(release > 0.0 and release < views[3].sprite.role_time("attack"), "the archer looses inside its attack")
	assert_eq(views[3].sprite.role, "attack", "the archer plays its attack when it shoots")
	assert_eq(views[2].shoot(Vector2(300, 0)), 0.0, "a token shoots at once")
	for v in views:
		v.free()


## Every ranged unit with a sheet marks when its shot leaves, so the projectile and the hit line up.
func test_ranged_sheets_mark_their_release() -> void:
	for id in Defs.units:
		if not UnitSprite.has_sheet(id) or int(Defs.units[id].get("range", 0)) <= 0:
			continue
		var s := UnitSprite.create(id, Color.WHITE)
		var release := s.mark_time("attack", "release")
		assert_true(release > 0.0 and release < s.role_time("attack"), "%s releases inside its attack" % id)
		s.free()


## While a settler is still building a city, the map leaves its territory unclaimed.
func test_borders_wait_for_a_city_being_built() -> void:
	var game := make_flat_game()
	var u := spawn(game, "settler", 0, 4, 3)
	assert_true(game.found_city(u.id), "city founded")
	var city: City = game.state.cities.values()[0]
	var layer := BorderLayer.new()
	layer.state = game.state
	var tile := game.state.tile(city.coord)
	assert_true(layer._claimed(tile), "a shown city's tile has a border")
	layer.hidden_cities[city.id] = true
	assert_true(not layer._claimed(tile), "a city still being built has none yet")
	layer.free()


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


func test_resource_mix_follows_weights() -> void:
	var counts := {}
	var placed := 0
	for seed_value in range(1, 6):
		var g := MapGenerator.generate(44, 28, seed_value, 4)
		for t in g.map.tiles:
			if t.resource != "":
				counts[t.resource] = counts.get(t.resource, 0) + 1
				placed += 1
	var weight_sum := 0
	for id in Defs.resources:
		weight_sum += int(Defs.resources[id].weight)
	for id in Defs.resources:
		var expected := float(Defs.resources[id].weight) / weight_sum
		assert_between(float(counts.get(id, 0)) / placed, expected * 0.5, expected * 1.6, "share of %s" % id)


func test_many_seeds_place_all_starts() -> void:
	for seed_value in range(1, 13):
		var g := MapGenerator.generate(32, 20, seed_value, 3)
		assert_eq(g.starts.size(), 3, "seed %d" % seed_value)
