class_name CityPanel
extends PanelContainer
## City screen: yields, growth, production choice, purchase, buildings.

signal closed
signal production_chosen(kind: String, id: String)
signal purchase_chosen(kind: String, id: String)
signal bombard_pressed

var _content: VBoxContainer
var _scroll: ScrollContainer


func _init() -> void:
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_content = UI.vbox(8)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)


func show_city(game: Game, city: City, own: bool, my_turn: bool) -> void:
	visible = true
	var scroll_pos := _scroll.scroll_vertical
	UI.clear(_content)
	var s := game.state
	var owner := s.player(city.owner)

	var head := UI.hbox(8)
	var swatch := ColorRect.new()
	swatch.color = owner.color
	swatch.custom_minimum_size = Vector2(8, 28)
	head.add_child(swatch)
	head.add_child(UI.label(city.name, 26))
	head.add_child(UI.spacer())
	head.add_child(UI.button("X", func(): closed.emit(), "Close (Esc)"))
	_content.add_child(head)

	var sub := PackedStringArray(["Size %d" % city.population, owner.name])
	if city.is_capital():
		sub.append("Capital")
	sub.append("HP %d/%d" % [city.hp, Combat.city_max_hp(city)])
	sub.append("Defense %d" % Combat.city_strength(s, city))
	_content.add_child(UI.wrap_label("  ·  ".join(sub), 15))
	if not own:
		_content.add_child(UI.wrap_label("A foreign city. Capture it with a melee unit once its HP reaches 0."))
		_scroll.scroll_vertical = scroll_pos
		return

	var y := CityRules.city_yields(s, city)
	_content.add_child(UI.yield_row(y, Yields.TYPES, 22))

	# Growth
	var surplus := int(y.food) - CityRules.food_upkeep(city)
	var threshold := CityRules.growth_threshold(city.population)
	var grow := CityRules.turns_to_grow(s, city)
	var grow_text := "grows in %d turns" % grow if grow > 0 else ("starving!" if surplus < 0 else "stagnant")
	_content.add_child(UI.label("Food %d/%d (%s%d) — %s" % [city.food, threshold, "+" if surplus >= 0 else "", surplus, grow_text], 15))
	_content.add_child(UI.progress(city.food, threshold, Tex.YIELD_COLORS.food))

	# Borders
	var need := CityRules.border_threshold(city)
	var culture := int(y.culture)
	var border_turns := int(ceil(float(need - city.culture) / culture)) if culture > 0 else -1
	_content.add_child(UI.label("Culture %d/%d — %s" % [city.culture, need,
		"borders grow in %d turns" % maxi(1, border_turns) if border_turns >= 0 else "no culture"], 15))
	_content.add_child(UI.progress(city.culture, need, Tex.YIELD_COLORS.culture))

	# Production
	if city.build.is_empty():
		_content.add_child(UI.label("Producing nothing — choose below!", 16, UITheme.ACCENT))
		_content.add_child(UI.label("Stored production: %d" % city.production, 14, UITheme.TEXT_DIM))
	else:
		var cost := CityRules.item_cost(city.build.kind, city.build.id)
		var turns := CityRules.turns_to_build(s, city, city.build.kind, city.build.id)
		_content.add_child(UI.label("Producing %s  %d/%d — %s" % [CityRules.item_name(city.build.kind, city.build.id),
			city.production, cost, "%d turns" % turns if turns > 0 else "never"], 16))
		_content.add_child(UI.progress(city.production, cost, Tex.YIELD_COLORS.production))

	var queued := s.player(city.owner).order_for(Orders.KIND_CITY, city.id, "purchase")
	if not queued.is_empty():
		_content.add_child(UI.label("Buying %s when the turn resolves" % CityRules.item_name(queued.item_kind, queued.item_id), 15, UITheme.ACCENT))
	if not s.player(city.owner).order_for(Orders.KIND_CITY, city.id, "bombard").is_empty():
		_content.add_child(UI.label("Bombardment planned", 15, UITheme.ACCENT))
	if my_turn and game.city_can_attack(city):
		_content.add_child(UI.button("Bombard (city attack)", func(): bombard_pressed.emit(),
			"The city can shoot an enemy unit within %d tiles." % int(Defs.rules.city.ranged_range)))

	# Build options
	_content.add_child(UI.header("Build"))
	var player := s.player(city.owner)
	for option in CityRules.build_options(s, city):
		_content.add_child(_build_row(game, city, player, option.kind, option.id, my_turn))
	var locked := PackedStringArray()
	for id in Defs.units:
		var why := CityRules.build_blocker(s, city, "unit", id)
		if why.begins_with("Requires") and Defs.units[id].has("requires_resource") and player.has_tech(Defs.units[id].get("tech", "")):
			locked.append("%s (%s)" % [Defs.units[id].name, why.to_lower()])
	if not locked.is_empty():
		_content.add_child(UI.wrap_label("Unavailable: " + ", ".join(locked), 13, UITheme.BAD))

	# Buildings
	_content.add_child(UI.header("Buildings"))
	if city.buildings.is_empty():
		_content.add_child(UI.label("None yet", 14, UITheme.TEXT_DIM))
	for b in city.buildings:
		var row := UI.hbox(8)
		row.add_child(UI.icon(Tex.icon(Defs.buildings[b].icon), 22))
		var info := UI.vbox(0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UI.label(Defs.buildings[b].name, 15))
		info.add_child(UI.wrap_label(_effects_text(Defs.buildings[b]), 13))
		row.add_child(info)
		_content.add_child(row)
	_scroll.scroll_vertical = scroll_pos


func _build_row(game: Game, city: City, player: Player, kind: String, id: String, my_turn: bool) -> Control:
	var s := game.state
	var def: Dictionary = Defs.units[id] if kind == "unit" else Defs.buildings[id]
	var row := UI.hbox(6)
	var turns := CityRules.turns_to_build(s, city, kind, id)
	var text := "%s   %d   %s" % [def.name, CityRules.item_cost(kind, id), "%dt" % turns if turns > 0 else "-"]
	var current: bool = not city.build.is_empty() and city.build.kind == kind and city.build.id == id
	var b := UI.button(text, func(): production_chosen.emit(kind, id), _tooltip(kind, def), Tex.icon(def.get("icon", "pawn")))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.disabled = not my_turn
	if current:
		b.add_theme_color_override("font_color", UITheme.ACCENT)
		b.add_theme_stylebox_override("normal", UITheme.box(UITheme.BUTTON, UITheme.ACCENT, 5, 8))
	row.add_child(b)
	var price := CityRules.purchase_cost(kind, id)
	var buy := UI.button("%dg" % price, func(): purchase_chosen.emit(kind, id), "Buy when the turn resolves, for %d gold." % price, Tex.yield_icon("gold"))
	buy.custom_minimum_size.x = 86
	buy.disabled = not my_turn or not game.can_purchase(city, kind, id)
	row.add_child(buy)
	return row


static func _tooltip(kind: String, def: Dictionary) -> String:
	if kind == "unit":
		var lines := PackedStringArray()
		if def.get("class", "") == "civilian":
			lines.append("Civilian. Moves %d." % int(def.moves))
			if "found_city" in def.get("abilities", []):
				lines.append("Founds a new city. Costs %d population." % int(def.get("pop_cost", 0)))
		else:
			lines.append("Strength %d, moves %d." % [int(def.strength), int(def.moves)])
			if def.has("ranged_strength"):
				lines.append("Ranged strength %d, range %d." % [int(def.ranged_strength), int(def.range)])
			for cls in def.get("bonus_vs", {}):
				lines.append("+%d vs %s." % [int(def.bonus_vs[cls]), cls])
		if def.has("requires_resource"):
			lines.append("Needs %s in your territory." % Defs.resources[def.requires_resource].name)
		return "\n".join(lines)
	return _effects_text(def)


static func _effects_text(def: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in def.get("yields", {}):
		parts.append("+%d %s" % [int(def.yields[k]), k])
	for k in def.get("yield_percent", {}):
		parts.append("+%d%% %s" % [int(def.yield_percent[k]), k])
	if def.has("defense"):
		parts.append("+%d defense" % int(def.defense))
	if def.has("hp"):
		parts.append("+%d HP" % int(def.hp))
	if int(def.get("upkeep", 0)) > 0:
		parts.append("%d upkeep" % int(def.upkeep))
	return ", ".join(parts)
