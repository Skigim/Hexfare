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


func test_unit_models_build() -> void:
	for id in Defs.units:
		var model: Dictionary = Defs.units[id].get("model", {})
		if model.is_empty():
			continue
		var rig: String = model.get("rig", "Medium")
		assert_true(ResourceLoader.exists(UnitModel.CHARACTER % rig), "%s rig %s" % [id, rig])
		for hand in UnitModel.HAND_SLOTS:
			if model.has(hand):
				assert_true(ResourceLoader.exists(UnitModel.WEAPON % model[hand].scene), "%s %s %s" % [id, hand, model[hand].scene])
		var unit := UnitModel.create(model)
		assert_true(unit != null, "%s builds" % id)
		if unit == null:
			continue
		for role in unit.clips:
			assert_true(unit.has_clip(unit.clips[role]), "%s %s clip %s" % [id, role, unit.clips[role]])
		unit.free()


## The hand slots must turn KayKit weapons the way the animations expect: a stab drives the
## blade forward and the guard pose holds a shield upright, facing forward (the rig faces +Z).
func test_hand_slots_follow_the_animations() -> void:
	var unit := UnitModel.create({"right": {"scene": "sword_A"}, "left": {"scene": "shield_A", "rotation": [0, 90, 0]}})
	var blade := _held_axis(unit, "right", "Melee_1H_Attack_Stab", 0.72, Vector3.UP)
	assert_true(blade.z > 0.8, "stab drives the blade forward: %s" % blade)
	var face := _held_axis(unit, "left", "Melee_Blocking", 0.0, Vector3.BACK)
	var up := _held_axis(unit, "left", "Melee_Blocking", 0.0, Vector3.UP)
	assert_true(face.z > 0.8 and up.y > 0.9, "guard holds the shield up and forward: face %s up %s" % [face, up])
	var layered := UnitModel.layered("Medium", {"clip": "Walking_A", "left_arm": "Melee_Blocking"})
	assert_true(_held_axis(unit, "left", layered, 0.5, Vector3.BACK).z > 0.8, "guarded walk keeps the shield forward")
	unit.free()


## Poses the skeleton from a clip at time t and returns where a held piece's local axis points.
func _held_axis(unit: UnitModel, hand: String, clip: String, t: float, axis: Vector3) -> Vector3:
	var anim := unit.player.get_animation(clip)
	var sk := unit.skeleton
	for i in anim.get_track_count():
		var bone := sk.find_bone(anim.track_get_path(i).get_concatenated_subnames())
		if bone < 0:
			continue
		match anim.track_get_type(i):
			Animation.TYPE_ROTATION_3D:
				sk.set_bone_pose_rotation(bone, anim.rotation_track_interpolate(i, t))
			Animation.TYPE_POSITION_3D:
				sk.set_bone_pose_position(bone, anim.position_track_interpolate(i, t))
	var slot: Dictionary = UnitModel.HAND_SLOTS[hand]
	var item: Node3D = unit.find_child(hand.capitalize() + "Hand", true, false).get_child(0).get_child(0)
	var hand_basis := sk.get_bone_global_pose(sk.find_bone(slot.bone)).basis
	return (hand_basis * slot.basis * item.basis * axis).normalized()


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
		for role in UnitSprite.ROLES:
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
	var views: Array[UnitView] = []
	for type in ["warrior", "settler"]:
		var v := UnitView.new()
		v.sync_from(spawn(game, type, 0, 2 + views.size() * 2, 2), Color.BLUE, true)
		views.append(v)
	assert_true(views[0].sprite != null, "a warrior is drawn as a figure")
	assert_true(views[1].sprite == null, "a settler keeps its token")
	for v in views:
		v.free()


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
