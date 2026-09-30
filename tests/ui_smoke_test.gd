extends Node
## End-to-end UI test: boots the real game scene, drives it with injected mouse/keyboard
## events, and checks the resulting game state. Run windowed:
##   godot --path . res://tests/ui_smoke_test.tscn

var scene: GameScene
var failures: Array[String] = []


func _ready() -> void:
	Defs.ensure_loaded()
	Session.settings = {"width": 32, "height": 20, "players": 3, "seed": 5, "human": true}
	Session.load_path = ""
	scene = load("res://scenes/game.tscn").instantiate()
	add_child(scene)
	await _frames(3)
	await _run()
	for f in failures:
		printerr("UI FAIL: " + f)
	print("UI smoke test: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	get_tree().quit(1 if not failures.is_empty() else 0)


func _run() -> void:
	var game := scene.game
	var s := game.state
	var human := scene.human
	var settler: Unit = null
	var warrior: Unit = null
	for u in s.player_units(human.id):
		if u.has_ability("found_city"):
			settler = u
		else:
			warrior = u
	_check(settler != null and warrior != null, "start units exist")

	# 1. Click the start tile until the settler is selected (tile cycles warrior -> settler).
	for i in 3:
		if scene.selected_unit_id == settler.id:
			break
		await _click_world(Hex.to_pixel(settler.coord), MOUSE_BUTTON_LEFT)
	_check(scene.selected_unit_id == settler.id, "clicking cycles to the settler")

	# 2. Found a city with the B hotkey.
	var home := settler.coord
	await _key(KEY_B)
	var city := s.city_at(home)
	_check(city != null, "B founds a city")
	_check(scene.selected_city_id == (city.id if city != null else -2), "city panel opens after founding")
	_check(scene.hud.city_panel.visible, "city panel visible")

	# 3. Choose production by clicking the Warrior button in the city panel.
	var warrior_button := _find_button(scene.hud.city_panel, "Warrior")
	_check(warrior_button != null, "Warrior build button exists")
	if warrior_button != null:
		await _click_control(warrior_button)
	_check(city != null and city.build.get("id", "") == "warrior", "clicking Warrior sets production")

	# 4. End Turn button first asks for research; the tech tree opens.
	await _click_control(scene.hud._end_turn)
	_check(scene.hud.tech_tree.visible, "End Turn opens the tech tree when research is unset")
	var pottery := _find_button(scene.hud.tech_tree, "Pottery")
	_check(pottery != null, "Pottery card exists")
	if pottery != null:
		await _click_control(pottery)
	_check(human.research == "pottery", "clicking a tech card sets research")
	await _key(KEY_ESCAPE)
	_check(not scene.hud.tech_tree.visible, "Esc closes the tech tree")

	# 5. Select the warrior with Tab and right-click to move it two tiles away.
	await _key(KEY_TAB)
	_check(scene.selected_unit_id == warrior.id, "Tab selects the idle warrior")
	await get_tree().create_timer(0.5).timeout  # let the camera finish centering
	var target := Hex.NONE
	for c in Hex.ring(warrior.coord, 2):
		var t := s.tile(c)
		if t != null and t.is_passable_land() and t.move_cost() == 1 and s.units_at(c).is_empty() and not Pathfinder.find_path(s, warrior, c).is_empty():
			target = c
			break
	_check(target != Hex.NONE, "found a destination for the warrior")
	if target != Hex.NONE:
		await _move_mouse_world(Hex.to_pixel(target))
		_check(not scene.map_view.path.steps.is_empty(), "hovering shows a path preview")
		await _click_world(Hex.to_pixel(target), MOUSE_BUTTON_RIGHT)
		_check(warrior.coord != home, "right-click moves the warrior")

	# 6. End the turn with Enter; AI players move; it's our turn 2.
	await _key(KEY_ENTER)
	_check(s.turn == 2, "Enter ends the turn (turn is %d)" % s.turn)
	_check(game.is_human_turn(), "control returns to the human")

	# 7. Quick save and the pause menu.
	await _key(KEY_F5)
	_check(SaveLoad.exists(), "F5 writes a quicksave")
	# Esc first clears the selection, then opens the menu.
	for i in 4:
		if scene.hud.menu.visible:
			break
		await _key(KEY_ESCAPE)
	_check(scene.hud.menu.visible, "Esc opens the pause menu")
	await _key(KEY_ESCAPE)
	_check(not scene.hud.menu.visible, "Esc closes the pause menu")


# --- Input helpers ---------------------------------------------------------

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _world_to_screen(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * p


func _move_mouse_world(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = _world_to_screen(p)
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	await _frames(2)


func _click_world(p: Vector2, button: MouseButton) -> void:
	await _move_mouse_world(p)
	await _click_screen(_world_to_screen(p), button)


func _click_control(c: Control) -> void:
	await _click_screen(c.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)


func _click_screen(pos: Vector2, button: MouseButton) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		Input.parse_input_event(ev)
		await _frames(1)
	await _frames(2)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await _frames(1)
	await _frames(2)


func _find_button(root: Node, prefix: String) -> Button:
	for child in root.find_children("*", "Button", true, false):
		var b := child as Button
		if b.is_visible_in_tree() and b.text.begins_with(prefix):
			return b
		# Tech cards keep their title in a child label.
		for l in b.find_children("*", "Label", true, false):
			if (l as Label).text == prefix and b.is_visible_in_tree():
				return b
	return null


func _check(cond: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if cond else "FAIL", what])
	if not cond:
		failures.append(what)
