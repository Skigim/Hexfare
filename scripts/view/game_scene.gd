class_name GameScene
extends Node2D
## The game screen. Owns the Game (rules), MapView (world rendering), CameraRig and HUD,
## and translates player input into Game actions.
##
## Command-line options (after "--"), handy for automated screenshots:
##   --seed=N --size=small|medium|large --players=N --autoplay=TURNS --reveal
##   --select=city|unit --tech --zoom=0.6 --screenshot=out.png --delay=1.0

var game: Game
var human: Player
var map_view: MapView
var camera: CameraRig
var hud: HUD

var selected_unit_id := -1
var selected_city_id := -1
var targeting := ""          # "", "ranged" (selected unit), "city" (selected city)
var hover := Hex.NONE
var show_grid := false
var _combat_preview: Dictionary = {}
var _dirty := true
var _args: Dictionary = {}
var _last_zoom := 0.0


func _ready() -> void:
	Defs.ensure_loaded()
	_args = DevTools.args()
	var is_new := true
	if Session.load_path != "":
		game = SaveLoad.load_game(Session.load_path)
		Session.load_path = ""
		is_new = game == null
	if game == null:
		game = Game.new_game(_new_game_settings())
	human = game.state.human_player()
	if human == null:
		human = game.state.players[0]

	map_view = MapView.new()
	add_child(map_view)
	map_view.setup(game, human)
	camera = CameraRig.new()
	add_child(camera)
	camera.make_current()
	camera.bounds = game.state.map.pixel_bounds()
	camera.set_zoom_level(0.8)
	hud = HUD.new()
	add_child(hud)
	_connect_signals()

	if is_new:
		game.start()
	_focus_on_start()
	_mark_dirty()
	if not _args.is_empty():
		_run_automation()


func _new_game_settings() -> Dictionary:
	var settings: Dictionary = Session.settings.duplicate() if not Session.settings.is_empty() else Session.default_settings()
	if _args.has("size") and Defs.rules.map.sizes.has(_args.size):
		var size: Dictionary = Defs.rules.map.sizes[_args.size]
		settings.width = size.width
		settings.height = size.height
		settings.players = size.players
	if _args.has("seed"):
		settings.seed = int(_args.seed)
	if _args.has("players"):
		settings.players = int(_args.players)
	return settings


func _connect_signals() -> void:
	game.changed.connect(_mark_dirty)
	game.borders_changed.connect(_mark_dirty)
	game.turn_started.connect(_on_turn_started)
	game.game_ended.connect(_on_game_ended)
	hud.end_turn_pressed.connect(_on_end_turn)
	hud.next_unit_pressed.connect(func(): _select_next_unit(true))
	hud.unit_action.connect(_on_unit_action)
	hud.production_chosen.connect(func(cid, kind, id): game.set_production(cid, kind, id))
	hud.purchase_chosen.connect(func(cid, kind, id): game.purchase(cid, kind, id))
	hud.bombard_pressed.connect(func(_cid): _set_targeting("city"))
	hud.city_closed.connect(_clear_selection)
	hud.research_chosen.connect(_on_research_chosen)
	hud.tech_tree_requested.connect(_toggle_tech_tree)
	hud.notification_clicked.connect(func(c): camera.focus_on(Hex.to_pixel(c)))
	hud.menu_action.connect(_on_menu_action)


func _mark_dirty() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if not is_equal_approx(camera.zoom.x, _last_zoom):
		_last_zoom = camera.zoom.x
		map_view.set_camera_zoom(_last_zoom)
	if _dirty:
		_refresh()


# --- Refresh ---------------------------------------------------------------

func _refresh() -> void:
	_dirty = false
	var s := game.state
	if selected_unit_id != -1:
		var u := s.get_unit(selected_unit_id)
		if u == null or not map_view.is_visible_to_viewer(u.coord):
			selected_unit_id = -1
			if targeting == "ranged":
				targeting = ""
	if selected_city_id != -1 and s.get_city(selected_city_id) == null:
		selected_city_id = -1
	map_view.sync()
	_update_highlights()
	_update_hover()
	hud.refresh(game, human, _hud_context())


func _hud_context() -> Dictionary:
	return {
		"unit": game.state.get_unit(selected_unit_id), "city": game.state.get_city(selected_city_id),
		"hover": hover, "combat": _combat_preview, "reveal_all": map_view.reveal_all, "targeting": targeting,
	}


func _update_highlights() -> void:
	var hl := map_view.highlights
	hl.reachable = {}
	hl.targets = []
	hl.selected = Hex.NONE
	hl.range_center = Hex.NONE
	hl.worked = []
	var u := _selected_own_unit()
	var any_unit := game.state.get_unit(selected_unit_id)
	if any_unit != null:
		hl.selected = any_unit.coord
	if u != null and game.is_human_turn():
		if not (u.fortified or u.sleeping):
			hl.reachable = Pathfinder.reachable(game.state, u)
		hl.targets = _attack_targets(u)
		if targeting == "ranged":
			hl.range_center = u.coord
			hl.range_radius = u.attack_range()
	var city := game.state.get_city(selected_city_id)
	if city != null:
		hl.selected = city.coord
		if city.owner == human.id:
			hl.worked = city.worked.duplicate()
		if targeting == "city":
			hl.range_center = city.coord
			hl.range_radius = int(Defs.rules.city.ranged_range)
			hl.targets = _city_targets(city)
	hl.queue_redraw()


## Hover-dependent UI: tile info, path preview, combat forecast.
func _update_hover() -> void:
	var hl := map_view.highlights
	hl.hover = hover
	hl.queue_redraw()
	map_view.path.clear()
	_combat_preview = {}
	var s := game.state
	if hover == Hex.NONE or not s.map.in_bounds(hover) or not map_view.is_explored_by_viewer(hover):
		return
	var city := s.get_city(selected_city_id)
	if targeting == "city" and city != null and hover in _city_targets(city):
		_combat_preview = Combat.preview_city_attack(s, city, hover)
		return
	var u := _selected_own_unit()
	if u == null or not game.is_human_turn() or hover == u.coord:
		return
	if _is_enemy_target(hover) and u.is_military():
		_combat_preview = Combat.preview(s, u, hover)
		map_view.path.start = u.coord
		map_view.path.attack_target = hover
		if not u.is_ranged() and Hex.distance(u.coord, hover) > 1:
			var p := Pathfinder.find_attack_path(s, u, hover)
			if p.size() >= 2:
				p.pop_back()
				map_view.path.steps = Pathfinder.annotate(s, u, p)
	else:
		var p := Pathfinder.find_path(s, u, hover)
		if not p.is_empty():
			map_view.path.start = u.coord
			map_view.path.steps = Pathfinder.annotate(s, u, p)
	map_view.path.queue_redraw()


func _is_enemy_target(c: Vector2i) -> bool:
	if not map_view.is_visible_to_viewer(c):
		return false
	var s := game.state
	var city := s.city_at(c)
	if city != null and city.owner != human.id:
		return true
	var m := s.military_at(c)
	return m != null and m.owner != human.id


func _attack_targets(u: Unit) -> Array:
	var out: Array = []
	if not u.is_military() or u.has_attacked or u.moves_left <= 0:
		return out
	var reach := u.attack_range() if u.is_ranged() else u.moves_left + 1
	var reachable := {} if u.is_ranged() else Pathfinder.reachable(game.state, u)
	for c in Hex.within(u.coord, reach):
		if c == u.coord or not _is_enemy_target(c):
			continue
		if u.is_ranged():
			out.append(c)
			continue
		var adjacent := Hex.distance(c, u.coord) == 1
		if not adjacent:
			for n in Hex.neighbors(c):
				if reachable.has(n) and reachable[n] < u.max_moves():
					adjacent = true
					break
		if adjacent:
			out.append(c)
	return out


func _city_targets(city: City) -> Array:
	var out: Array = []
	if city.has_attacked:
		return out
	for c in Hex.within(city.coord, int(Defs.rules.city.ranged_range)):
		var m := game.state.military_at(c)
		if m != null and m.owner != city.owner and map_view.is_visible_to_viewer(c):
			out.append(c)
	return out


# --- Selection -------------------------------------------------------------

func _selected_own_unit() -> Unit:
	var u := game.state.get_unit(selected_unit_id)
	if u == null or u.owner != human.id:
		return null
	return u


func _select_unit(uid: int) -> void:
	selected_unit_id = uid
	selected_city_id = -1
	targeting = ""
	_mark_dirty()


func _select_city(cid: int) -> void:
	selected_city_id = cid
	selected_unit_id = -1
	targeting = ""
	_mark_dirty()


func _clear_selection() -> void:
	selected_unit_id = -1
	selected_city_id = -1
	targeting = ""
	_mark_dirty()


## Clicking a tile cycles through: own units (military first), the city, other units.
func _select_at(c: Vector2i) -> void:
	var s := game.state
	if s.tile(c) == null or not map_view.is_explored_by_viewer(c):
		_clear_selection()
		return
	var options: Array = []
	var visible := map_view.is_visible_to_viewer(c)
	var units := s.units_at(c)
	units.sort_custom(func(a, b): return int(a.owner != human.id) * 2 + int(a.is_civilian()) < int(b.owner != human.id) * 2 + int(b.is_civilian()))
	for u in units:
		if u.owner == human.id:
			options.append(["unit", u.id])
	var city := s.city_at(c)
	if city != null:
		options.append(["city", city.id])
	if visible:
		for u in units:
			if u.owner != human.id:
				options.append(["unit", u.id])
	if options.is_empty():
		_clear_selection()
		return
	var current := -1
	for i in options.size():
		if (options[i][0] == "unit" and options[i][1] == selected_unit_id) or (options[i][0] == "city" and options[i][1] == selected_city_id):
			current = i
	var pick: Array = options[(current + 1) % options.size()]
	if pick[0] == "unit":
		_select_unit(pick[1])
	else:
		_select_city(pick[1])


func _select_next_unit(center: bool) -> void:
	var waiting := game.state.player_units(human.id).filter(func(u): return u.needs_orders())
	if waiting.is_empty():
		if selected_unit_id != -1 and _selected_own_unit() != null and not _selected_own_unit().needs_orders():
			_clear_selection()
		return
	waiting.sort_custom(func(a, b): return a.id < b.id)
	var pick: Unit = waiting[0]
	for u in waiting:
		if u.id > selected_unit_id:
			pick = u
			break
	_select_unit(pick.id)
	if center:
		camera.focus_on(Hex.to_pixel(pick.coord))


func _after_unit_action(uid: int) -> void:
	var u := game.state.get_unit(uid)
	if u == null or not u.needs_orders():
		_select_next_unit(true)
	_mark_dirty()


# --- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_on_key(event as InputEventKey)
		return
	if hud.is_modal():
		return
	if event is InputEventMouseMotion:
		var c := _event_coord(event)
		if c != hover:
			hover = c
			_update_hover()
			hud.refresh_hover(game, human, _hud_context())
	elif event is InputEventMouseButton and event.pressed:
		var c := _event_coord(event)
		if event.button_index == MOUSE_BUTTON_LEFT:
			_on_left_click(c)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_on_right_click(c)


## Hex under a mouse event (uses the event's own position, not the OS cursor).
func _event_coord(event: InputEventMouse) -> Vector2i:
	var world := get_viewport().get_canvas_transform().affine_inverse() * event.position
	return Hex.from_pixel(world - map_view.global_position)


func _on_left_click(c: Vector2i) -> void:
	if targeting != "":
		_try_target(c)
		return
	_select_at(c)


func _on_right_click(c: Vector2i) -> void:
	if not game.is_human_turn() or not game.state.map.in_bounds(c):
		return
	if targeting != "":
		_try_target(c)
		return
	var city := game.state.get_city(selected_city_id)
	if city != null and city.owner == human.id:
		if c in _city_targets(city):
			game.city_attack(city.id, c)
		return
	var u := _selected_own_unit()
	if u == null or c == u.coord:
		return
	if u.is_military() and _is_enemy_target(c):
		if u.is_ranged():
			if Hex.distance(u.coord, c) <= u.attack_range():
				game.attack(u.id, c)
		else:
			game.move_and_attack(u.id, c)
	else:
		game.move_unit(u.id, c)
	_after_unit_action(u.id)


func _try_target(c: Vector2i) -> void:
	if targeting == "ranged":
		var u := _selected_own_unit()
		if u != null and c in _attack_targets(u):
			game.attack(u.id, c)
			targeting = ""
			_after_unit_action(u.id)
			return
	elif targeting == "city":
		var city := game.state.get_city(selected_city_id)
		if city != null and c in _city_targets(city):
			game.city_attack(city.id, c)
	targeting = ""
	_mark_dirty()


func _set_targeting(mode: String) -> void:
	targeting = mode
	_mark_dirty()


func _on_key(e: InputEventKey) -> void:
	if hud.menu.visible:
		if e.keycode == KEY_ESCAPE:
			hud.menu.visible = false
		return
	match e.keycode:
		KEY_ESCAPE:
			if hud.tech_tree.visible:
				hud.tech_tree.visible = false
			elif targeting != "":
				targeting = ""
				_mark_dirty()
			elif selected_unit_id != -1 or selected_city_id != -1:
				_clear_selection()
			else:
				_on_menu_action("open")
		KEY_T:
			_toggle_tech_tree()
		KEY_F5:
			_on_menu_action("save")
		KEY_F9:
			_on_menu_action("load")
		KEY_F10:
			map_view.set_reveal_all(not map_view.reveal_all)
			_mark_dirty()
		KEY_G:
			show_grid = not show_grid
			map_view.set_grid(show_grid)
	if hud.is_modal():
		return
	var u := _selected_own_unit()
	match e.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			_on_end_turn()
		KEY_TAB, KEY_PERIOD:
			_select_next_unit(true)
		KEY_C:
			if u != null:
				camera.focus_on(Hex.to_pixel(u.coord))
			elif selected_city_id != -1:
				camera.focus_on(Hex.to_pixel(game.state.get_city(selected_city_id).coord))
		KEY_SPACE:
			if u != null:
				_on_unit_action("skip")
		KEY_F:
			if u != null:
				_on_unit_action("fortify" if u.is_military() else "sleep")
		KEY_B:
			if u != null:
				_on_unit_action("found")
		KEY_R:
			if u != null and u.is_ranged():
				_on_unit_action("ranged")


func _on_unit_action(action_name: String) -> void:
	var u := _selected_own_unit()
	if u == null or not game.is_human_turn():
		return
	var uid := u.id
	match action_name:
		"found":
			var at := u.coord
			if game.found_city(uid):
				var city := game.state.city_at(at)
				_select_city(city.id)
				return
		"fortify":
			game.fortify(uid)
		"sleep":
			game.sleep(uid)
		"wake":
			game.wake(uid)
		"skip":
			game.skip_unit(uid)
		"cancel":
			game.cancel_orders(uid)
		"disband":
			game.disband(uid)
		"ranged":
			_set_targeting("ranged")
			return
	_after_unit_action(uid)


# --- Turn flow -------------------------------------------------------------

func _on_end_turn() -> void:
	if not game.is_human_turn():
		return
	var pending := game.pending_decision(human.id)
	match pending.get("kind", ""):
		"research":
			hud.open_tech_tree(game, human)
			return
		"production":
			var city := game.state.get_city(pending.city_id)
			_select_city(city.id)
			camera.focus_on(Hex.to_pixel(city.coord))
			return
	targeting = ""
	game.end_turn()


func _on_turn_started(_player: Player) -> void:
	selected_unit_id = -1
	_select_next_unit(true)
	_mark_dirty()


func _on_research_chosen(tech_id: String) -> void:
	game.set_research(human.id, tech_id)
	if hud.tech_tree.visible:
		hud.tech_tree.refresh(game, human)


func _toggle_tech_tree() -> void:
	if hud.tech_tree.visible:
		hud.tech_tree.visible = false
	else:
		hud.open_tech_tree(game, human)


func _on_game_ended(winner: int, victory_type: String) -> void:
	var won := winner == human.id
	var winner_name := game.state.player(winner).name if winner >= 0 else "Nobody"
	var title := "Victory!" if won else "Defeat"
	var subtitle := ""
	match victory_type:
		"domination":
			subtitle = "You conquered every rival." if won else "%s conquered the world." % winner_name
		"science":
			subtitle = "Your scholars mastered every technology." if won else "%s mastered every technology first." % winner_name
		"score":
			title = "Time's Up"
			subtitle = "%s leads on score (%d)." % [winner_name, game.score(winner)]
		"defeat":
			subtitle = "Your civilization has been destroyed."
	hud.menu.open_game_over(title, subtitle)
	_mark_dirty()


func _on_menu_action(action_name: String) -> void:
	match action_name:
		"open":
			hud.menu.open_pause(SaveLoad.exists())
		"resume":
			hud.menu.visible = false
		"save":
			if game.is_human_turn() and SaveLoad.save(game):
				game.notify(human.id, "Game saved.")
			hud.menu.visible = false
		"load":
			if SaveLoad.exists():
				Session.load_path = SaveLoad.QUICKSAVE
				get_tree().reload_current_scene()
		"menu":
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		"quit":
			get_tree().quit()


func _nearest_enemy_to_selection() -> Vector2i:
	var u := _selected_own_unit()
	if u == null:
		return Hex.NONE
	var best := Hex.NONE
	var best_d := 1 << 20
	for other in game.state.units.values():
		if other.owner != human.id and other.is_military() and map_view.is_visible_to_viewer(other.coord):
			var d := Hex.distance(u.coord, other.coord)
			if d < best_d:
				best_d = d
				best = other.coord
	return best


func _focus_on_start() -> void:
	var units := game.state.player_units(human.id)
	var cities := game.state.player_cities(human.id)
	if not units.is_empty():
		camera.focus_on(Hex.to_pixel(units[0].coord), false)
	elif not cities.is_empty():
		camera.focus_on(Hex.to_pixel(cities[0].coord), false)
	_select_next_unit(false)


# --- Automation (screenshots / demos) --------------------------------------

func _run_automation() -> void:
	if _args.has("reveal"):
		map_view.set_reveal_all(true)
	map_view.animate = false
	for i in int(_args.get("autoplay", "0")):
		if game.state.game_over or not game.is_human_turn():
			break
		AIPlayer.take_turn(game, human)
		game.end_turn()
	map_view.animate = true
	match _args.get("select", ""):
		"city":
			var cities := game.state.player_cities(human.id)
			if not cities.is_empty():
				_select_city(cities[0].id)
				camera.focus_on(Hex.to_pixel(cities[0].coord), false)
		"unit":
			var units := game.state.player_units(human.id)
			if not units.is_empty():
				_select_unit(units[0].id)
				camera.focus_on(Hex.to_pixel(units[0].coord), false)
		"military":
			# The own military unit closest to a visible enemy (for combat previews).
			var best: Unit = null
			var best_d := 1 << 20
			for u in game.state.player_units(human.id):
				if not u.is_military():
					continue
				for other in game.state.units.values():
					if other.owner != human.id and other.is_military() and map_view.is_visible_to_viewer(other.coord):
						var d := Hex.distance(u.coord, other.coord)
						if d < best_d:
							best_d = d
							best = u
			if best != null:
				_select_unit(best.id)
				camera.focus_on(Hex.to_pixel(best.coord), false)
	if _args.has("zoom"):
		camera.set_zoom_level(float(_args.zoom))
	if _args.has("tech"):
		hud.open_tech_tree(game, human)
	if _args.has("hover"):
		var parts: PackedStringArray = String(_args.hover).split(",")
		hover = Hex.offset_to_axial(int(parts[0]), int(parts[1]))
	if _args.has("hover-enemy"):
		hover = _nearest_enemy_to_selection()
	if _args.has("hover-rel") and _selected_own_unit() != null:
		var parts: PackedStringArray = String(_args["hover-rel"]).split(",")
		hover = _selected_own_unit().coord + Vector2i(int(parts[0]), int(parts[1]))
	_refresh()
	if _args.has("screenshot"):
		DevTools.capture_and_quit(self, String(_args.screenshot), float(_args.get("delay", "1.0")))
