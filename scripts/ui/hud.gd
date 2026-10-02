class_name HUD
extends CanvasLayer
## Screen-space UI. Owns the panels and re-emits their signals for GameScene.

signal end_turn_pressed
signal next_unit_pressed
signal unit_action(action_name: String)
signal production_chosen(city_id: int, kind: String, id: String)
signal purchase_chosen(city_id: int, kind: String, id: String)
signal bombard_pressed(city_id: int)
signal city_closed
signal research_chosen(tech_id: String)
signal tech_tree_requested
signal notification_clicked(coord: Vector2i)
signal menu_action(action_name: String)

var root: Control
var top_bar: TopBar
var feed: NotificationFeed
var unit_panel: UnitPanel
var tile_panel: TilePanel
var city_panel: CityPanel
var tech_tree: TechTreePanel
var menu: GameMenu
var _end_turn: Button
var _end_hint: Label
var _next_unit: Button
var _banner: Label
var _city_id := -1


func _init() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)

	top_bar = TopBar.new()
	top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_bar.tech_pressed.connect(func(): tech_tree_requested.emit())
	top_bar.menu_pressed.connect(func(): menu_action.emit("open"))
	root.add_child(top_bar)

	feed = NotificationFeed.new()
	feed.position = Vector2(12, 64)
	feed.custom_minimum_size = Vector2(430, 0)
	feed.entry_clicked.connect(func(c): notification_clicked.emit(c))
	root.add_child(feed)

	# Unit panel, then the hovered-tile panel right after it (whatever the unit panel's width).
	var bottom_left := UI.hbox(12)
	bottom_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor_bottom_left(bottom_left, 12)
	root.add_child(bottom_left)
	unit_panel = UnitPanel.new()
	unit_panel.size_flags_vertical = Control.SIZE_SHRINK_END
	unit_panel.action.connect(func(a): unit_action.emit(a))
	bottom_left.add_child(unit_panel)
	tile_panel = TilePanel.new()
	tile_panel.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom_left.add_child(tile_panel)

	var end_box := UI.vbox(6)
	end_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	end_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	end_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	end_box.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(end_box)
	_end_hint = UI.label("", 15, UITheme.TEXT)
	_end_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_end_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_end_hint.add_theme_constant_override("outline_size", 5)
	end_box.add_child(_end_hint)
	_next_unit = UI.button("Next Unit (Tab)", func(): next_unit_pressed.emit(), "Select the next unit that needs orders")
	end_box.add_child(_next_unit)
	_end_turn = UI.button("End Turn", func(): end_turn_pressed.emit(), "End your turn (Enter)")
	_end_turn.custom_minimum_size = Vector2(250, 58)
	_end_turn.add_theme_font_size_override("font_size", 22)
	end_box.add_child(_end_turn)

	city_panel = CityPanel.new()
	city_panel.anchor_left = 1.0
	city_panel.anchor_right = 1.0
	city_panel.anchor_top = 0.0
	city_panel.anchor_bottom = 1.0
	city_panel.offset_left = -440
	city_panel.offset_right = -12
	city_panel.offset_top = 64
	city_panel.offset_bottom = -170
	city_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	city_panel.visible = false
	city_panel.closed.connect(func(): city_closed.emit())
	city_panel.production_chosen.connect(func(k, id): production_chosen.emit(_city_id, k, id))
	city_panel.purchase_chosen.connect(func(k, id): purchase_chosen.emit(_city_id, k, id))
	city_panel.bombard_pressed.connect(func(): bombard_pressed.emit(_city_id))
	root.add_child(city_panel)

	_banner = UI.label("", 22, UITheme.ACCENT)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_top = 70
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.add_theme_constant_override("outline_size", 6)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.add_child(_banner)

	tech_tree = TechTreePanel.new()
	tech_tree.visible = false
	tech_tree.tech_chosen.connect(func(id): research_chosen.emit(id))
	tech_tree.closed.connect(func(): tech_tree.visible = false)
	root.add_child(tech_tree)

	menu = GameMenu.new()
	menu.visible = false
	menu.action.connect(func(a): menu_action.emit(a))
	root.add_child(menu)


static func _anchor_bottom_left(c: Control, x: float) -> void:
	c.anchor_left = 0.0
	c.anchor_right = 0.0
	c.anchor_top = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = x
	c.offset_bottom = -12
	c.offset_top = -12
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN


## True while a full-screen overlay should swallow map input.
func is_modal() -> bool:
	return tech_tree.visible or menu.visible


## ctx: {unit: Unit|null, city: City|null, hover: Vector2i, combat: Dictionary, reveal_all: bool, targeting: String}
func refresh(game: Game, human: Player, ctx: Dictionary) -> void:
	var my_turn := game.is_human_turn()
	top_bar.refresh(game, human)
	feed.refresh(game, human.id)
	var u: Unit = ctx.get("unit")
	if u != null:
		unit_panel.show_unit(game, u, u.owner == human.id, my_turn)
	else:
		unit_panel.visible = false
	var city: City = ctx.get("city")
	if city != null:
		_city_id = city.id
		city_panel.show_city(game, city, city.owner == human.id, my_turn)
	else:
		_city_id = -1
		city_panel.visible = false
	refresh_hover(game, human, ctx)
	_refresh_end_turn(game, human, my_turn, ctx.get("skipped", {}))
	match ctx.get("targeting", ""):
		"ranged":
			_banner.text = "Choose a target (Esc to cancel)"
		"city":
			_banner.text = "Choose a target for the city (Esc to cancel)"
		_:
			_banner.text = ""
	if tech_tree.visible:
		tech_tree.refresh(game, human)


## Only the hover-dependent panel (cheap; called on mouse movement).
func refresh_hover(game: Game, human: Player, ctx: Dictionary) -> void:
	var combat: Dictionary = ctx.get("combat", {})
	if not combat.is_empty():
		tile_panel.show_combat(game, combat)
	elif ctx.get("hover", Hex.NONE) != Hex.NONE:
		tile_panel.show_tile(game, human, ctx.hover, ctx.get("reveal_all", false))
	else:
		tile_panel.visible = false


func _refresh_end_turn(game: Game, human: Player, my_turn: bool, skipped: Dictionary) -> void:
	if game.state.game_over:
		_end_turn.text = "Game Over"
		_end_turn.disabled = true
		_end_hint.text = ""
		_next_unit.visible = false
		return
	_end_turn.disabled = not my_turn
	var pending := game.pending_decision(human.id)
	var waiting := 0
	for u in game.state.player_units(human.id):
		if game.needs_orders(u) and not skipped.has(u.id):
			waiting += 1
	_next_unit.visible = waiting > 0
	match pending.get("kind", ""):
		"research":
			_end_turn.text = "Choose Research"
		"production":
			_end_turn.text = "Choose Production"
		_:
			_end_turn.text = "End Turn"
	_end_hint.text = "%d unit%s waiting for orders" % [waiting, "" if waiting == 1 else "s"] if waiting > 0 else "Turn %d" % game.state.turn


func open_tech_tree(game: Game, human: Player) -> void:
	tech_tree.visible = true
	tech_tree.refresh(game, human)
