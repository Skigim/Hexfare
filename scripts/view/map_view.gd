class_name MapView
extends Node2D
## Renders the GameState from one player's point of view. It never changes the game;
## sync() reconciles the scene with the state, and game signals trigger animations.

var game: Game
var viewer: Player
var reveal_all := false
var animate := true                 # off while fast-forwarding turns (automation)

var terrain: TerrainLayer
var borders: BorderLayer
var overlays: ResourceLayer
var highlights: HighlightLayer
var city_layer: Node2D
var unit_layer: Node2D
var fog: FogLayer
var banner_layer: Node2D
var path: PathLayer
var effects: Node2D

var _unit_views: Dictionary = {}    # unit id -> UnitView
var _city_views: Dictionary = {}    # city id -> CityView
var _banners: Dictionary = {}       # city id -> CityBanner
var _banner_scale := 1.0
var _unit_scale := 1.0
var _reveal_delay: Dictionary = {}  # city id -> seconds before a just-founded city appears


func setup(g: Game, viewing_player: Player) -> void:
	game = g
	viewer = viewing_player
	terrain = TerrainLayer.new()
	borders = BorderLayer.new()
	overlays = ResourceLayer.new()
	highlights = HighlightLayer.new()
	city_layer = Node2D.new()
	unit_layer = Node2D.new()
	fog = FogLayer.new()
	banner_layer = Node2D.new()
	path = PathLayer.new()
	effects = Node2D.new()
	unit_layer.y_sort_enabled = true   # figures lower on screen stand in front
	for layer in [terrain, borders, overlays, highlights, city_layer, unit_layer, fog, banner_layer, path, effects]:
		add_child(layer)
	for layer in [borders, fog]:
		layer.state = game.state
		layer.viewer = viewer
	overlays.state = game.state
	overlays.viewer = viewer
	terrain.build(game.state.map)
	game.turn_resolved.connect(play_events)
	game.combat_resolved.connect(_on_combat)
	game.city_founded.connect(_on_city_founded)
	sync()


func set_reveal_all(on: bool) -> void:
	reveal_all = on
	borders.reveal_all = on
	fog.reveal_all = on
	sync()


func set_grid(on: bool) -> void:
	overlays.show_grid = on
	overlays.queue_redraw()


## Keeps banners and unit tokens readable when zoomed out.
func set_camera_zoom(z: float) -> void:
	_banner_scale = clampf(0.85 / z, 1.0, 2.4)
	_unit_scale = clampf(0.7 / z, 1.0, 1.8)
	for b in _banners.values():
		b.scale = Vector2.ONE * _banner_scale
	for v in _unit_views.values():
		v.scale = Vector2.ONE * _unit_scale


func is_visible_to_viewer(c: Vector2i) -> bool:
	return reveal_all or viewer == null or Visibility.is_visible(game.state, viewer, c)


func is_explored_by_viewer(c: Vector2i) -> bool:
	return reveal_all or viewer == null or Visibility.is_explored(game.state, viewer, c)


## Rebuilds everything that depends on game state (cheap enough to call after every action).
func sync() -> void:
	var s := game.state
	borders.queue_redraw()
	fog.queue_redraw()
	overlays.queue_redraw()
	_sync_cities(s)
	_sync_units(s)


func _sync_cities(s: GameState) -> void:
	for cid in _city_views.keys():
		if not s.cities.has(cid):
			_city_views[cid].queue_free()
			_banners[cid].queue_free()
			_city_views.erase(cid)
			_banners.erase(cid)
	for city in s.cities.values():
		if not _city_views.has(city.id):
			var v := CityView.new()
			city_layer.add_child(v)
			_city_views[city.id] = v
			var b := CityBanner.new()
			b.scale = Vector2.ONE * _banner_scale
			banner_layer.add_child(b)
			_banners[city.id] = b
			if _reveal_delay.has(city.id):   # the settler is still building it
				_fade_in([v, b], _reveal_delay[city.id])
				_reveal_delay.erase(city.id)
		var explored := is_explored_by_viewer(city.coord)
		_city_views[city.id].visible = explored
		_banners[city.id].visible = explored
		_city_views[city.id].sync_from(city)
		_banners[city.id].sync_from(s, city, viewer != null and city.owner == viewer.id)


func _sync_units(s: GameState) -> void:
	for uid in _unit_views.keys():
		if not s.units.has(uid):
			_unit_views[uid].remove(animate)
			_unit_views.erase(uid)
	for u in s.units.values():
		var v: UnitView = _unit_views.get(u.id)
		if v == null:
			v = UnitView.new()
			v.scale = Vector2.ONE * _unit_scale
			unit_layer.add_child(v)
			_unit_views[u.id] = v
			v.position = unit_position(u)
			v.coord = u.coord
		v.sync_from(u, s.player(u.owner).color, viewer != null and u.owner == viewer.id,
				s.player(u.owner).unit_order(u.id).get("type", ""))
		v.visible = is_visible_to_viewer(u.coord)
		if not v.is_animating() and (v.coord != u.coord or v.position != unit_position(u)):
			v.position = unit_position(u)
		v.coord = u.coord


## Where a unit's token sits: centered, or offset when sharing a tile / inside a city.
func unit_position(u: Unit) -> Vector2:
	var s := game.state
	var base := Hex.to_pixel(u.coord)
	var in_city := s.city_at(u.coord) != null
	var shared := s.units_at(u.coord).size() > 1
	var figure := UnitSprite.has_sheet(u.type)
	if u.is_military():
		if in_city:   # figures stand lower so their heads clear the city banner
			return base + (Vector2(-22, 40) if figure else Vector2(-20, 26))
		return base + (Vector2(-20, -12) if figure and shared else Vector2(-14, -8) if shared else Vector2.ZERO)
	if in_city:
		return base + (Vector2(22, 40) if figure else Vector2(24, 28))
	# Figures on a shared hex step far enough apart that their stands don't overlap.
	return base + (Vector2(18, 16) if figure and shared else Vector2(20, 18) if shared else Vector2.ZERO)


func unit_view(uid: int) -> UnitView:
	return _unit_views.get(uid)


# --- Animations ------------------------------------------------------------

## Plays a resolved turn's movement: every unit walks its recorded route at the same time.
## (The turn has already been resolved; this only animates the views from where they stood.)
func play_events(events: Array) -> void:
	if not animate:
		return
	var routes: Dictionary = {}  # unit id -> world points, in the order the unit moved
	for e in events:
		if e.type != "move":
			continue
		var pts: Array = routes.get(e.unit, [])
		pts.append(Hex.to_pixel(Vector2i(int(e.to[0]), int(e.to[1]))))
		routes[e.unit] = pts
	for uid in routes:
		var u := game.state.get_unit(uid)
		var v: UnitView = _unit_views.get(uid)
		if u == null or v == null or not is_visible_to_viewer(u.coord):
			continue
		var route: Array = routes[uid]
		route[route.size() - 1] = unit_position(u)
		v.coord = u.coord
		v.animate_path(route, 0.09, UnitView.DEATH_TIME if _body_at(u.coord, v) else 0.0)


## True if a unit killed in this fight is lying on the hex (its view is removed only after the
## move is announced, so it is still in _unit_views, marked dying).
func _body_at(c: Vector2i, mover: UnitView) -> bool:
	for other in _unit_views.values():
		if other != mover and other.dying and other.coord == c:
			return true
	return false


## A settler figure founding a city hammers the ground first; the city, its borders and the
## cleared tile appear on its last blow.
func _on_city_founded(city: City) -> void:
	var delay := 0.0
	if animate and is_visible_to_viewer(city.coord):
		for v in _unit_views.values():
			if v.coord == city.coord and not game.state.units.has(v.unit_id) and v.founding_time() > 0.0:
				v.founding = true
				delay = v.founding_time()
				break
	if delay <= 0.0:
		terrain.refresh_tile(game.state.tile(city.coord))
		return
	_reveal_delay[city.id] = delay
	borders.hidden_cities[city.id] = true
	var tile := game.state.tile(city.coord)
	get_tree().create_timer(delay).timeout.connect(func():
		terrain.refresh_tile(tile)
		borders.hidden_cities.erase(city.id)
		borders.queue_redraw())


func _fade_in(nodes: Array, delay: float) -> void:
	for n in nodes:
		n.modulate.a = 0.0
		var t: Tween = n.create_tween()
		t.tween_interval(delay)
		t.tween_property(n, "modulate:a", 1.0, 0.35)


func _on_combat(info: Dictionary) -> void:
	var target: Vector2i = info.target
	var from: Vector2i = info.from
	if not animate or not (is_visible_to_viewer(target) or is_visible_to_viewer(from)):
		return
	var to_pos := Hex.to_pixel(target)
	var from_pos := Hex.to_pixel(from)
	if info.ranged:
		_projectile(from_pos, to_pos)
	elif info.has("attacker_unit_id"):
		var v: UnitView = _unit_views.get(info.attacker_unit_id)
		if v != null:
			v.lunge(to_pos)
	if info.get("defender_kind", "") == "unit":
		var d: UnitView = _unit_views.get(info.defender_unit_id)
		if d != null:
			d.dying = int(info.defender_hp) <= 0
			d.struck(from_pos)
	if info.has("attacker_unit_id") and int(info.get("attacker_hp", 1)) <= 0:
		var a: UnitView = _unit_views.get(info.attacker_unit_id)
		if a != null:
			a.dying = true
	float_text(to_pos + Vector2(0, -30), "-%d" % info.to_defender, UITheme.BAD)
	if int(info.get("to_attacker", 0)) > 0:
		float_text(from_pos + Vector2(0, -30), "-%d" % info.to_attacker, Color("#ffb35e"))


func _projectile(from_pos: Vector2, to_pos: Vector2) -> void:
	var dot := Polygon2D.new()
	dot.polygon = PackedVector2Array([Vector2(-5, -5), Vector2(5, -5), Vector2(5, 5), Vector2(-5, 5)])
	dot.color = Color(1, 0.9, 0.6)
	dot.position = from_pos
	effects.add_child(dot)
	var t := dot.create_tween()
	t.tween_property(dot, "position", to_pos, 0.22)
	t.tween_callback(dot.queue_free)


func float_text(pos: Vector2, text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Tex.font())
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	l.position = pos - Vector2(24, 20)
	effects.add_child(l)
	var t := l.create_tween()
	t.set_parallel(true)
	t.tween_property(l, "position:y", l.position.y - 50, 1.0)
	t.tween_property(l, "modulate:a", 0.0, 1.0).set_delay(0.4)
	t.chain().tween_callback(l.queue_free)
