class_name TilePanel
extends PanelContainer
## Hovered-tile details, or a combat forecast when hovering an attack target.

var _col: VBoxContainer


func _init() -> void:
	custom_minimum_size = Vector2(330, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_col = UI.vbox(4)
	add_child(_col)


func show_tile(game: Game, viewer: Player, c: Vector2i, reveal_all: bool) -> void:
	var s := game.state
	var t := s.tile(c)
	if t == null or not (reveal_all or Visibility.is_explored(s, viewer, c)):
		visible = false
		return
	visible = true
	UI.clear(_col)
	_col.add_child(UI.label(t.display_name(), 18))
	var y := Yields.tile_yields(t, viewer)
	if t.is_workable():
		_col.add_child(UI.yield_row(y, Yields.TYPES, 16, true))
	else:
		_col.add_child(UI.label("Impassable", 14, UITheme.BAD))
	if t.resource != "" and Yields.resource_visible(t.resource, viewer):
		var res: Dictionary = Defs.resources[t.resource]
		var row := UI.hbox(6)
		row.add_child(UI.icon(Tex.icon(res.icon), 18, Tex.RESOURCE_COLORS.get(res.category, Color.WHITE)))
		row.add_child(UI.label("%s (%s)" % [res.name, res.category], 15, Tex.RESOURCE_COLORS.get(res.category, Color.WHITE)))
		_col.add_child(row)
	var info := PackedStringArray()
	if t.is_passable_land():
		info.append("Move cost %d" % t.move_cost())
		if t.defense_bonus() > 0:
			info.append("Defense +%d" % t.defense_bonus())
	if t.owner >= 0:
		var city := s.get_city(t.city_id)
		info.append("%s%s" % [s.player(t.owner).name, " (%s)" % city.name if city != null else ""])
	if not info.is_empty():
		_col.add_child(UI.label("  ·  ".join(info), 14, UITheme.TEXT_DIM))
	if reveal_all or Visibility.is_visible(s, viewer, c):
		for u in s.units_at(c):
			var owner := s.player(u.owner)
			_col.add_child(UI.label("%s %s — %d HP" % [owner.name, u.display_name(), u.hp], 14, owner.color.lightened(0.35)))


func show_combat(game: Game, info: Dictionary) -> void:
	visible = true
	UI.clear(_col)
	var s := game.state
	var attacker := "City"
	if info.attacker_kind == "unit":
		attacker = s.get_unit(info.attacker_unit_id).display_name()
	var defender := ""
	if info.defender_kind == "city":
		defender = s.get_city(info.defender_city_id).name
	else:
		defender = s.get_unit(info.defender_unit_id).display_name()
	_col.add_child(UI.label("%s vs %s" % [attacker, defender], 18, UITheme.ACCENT))
	_col.add_child(_mods_row("Attack", info.attack, info.attack_mods))
	_col.add_child(_mods_row("Defense", info.defense, info.defense_mods))
	var dealt := int(info.damage_to_defender)
	var taken := int(info.damage_to_attacker)
	_col.add_child(UI.label("Expected: deal ~%d damage, take ~%d" % [dealt, taken], 16,
		UITheme.GOOD if dealt >= taken else UITheme.BAD))
	if info.ranged:
		_col.add_child(UI.label("Ranged attack: no retaliation.", 13, UITheme.TEXT_DIM))


func _mods_row(title: String, total: int, mods: Array) -> Label:
	var parts := PackedStringArray()
	for m in mods:
		parts.append("%s %s%d" % [m[0], "+" if int(m[1]) >= 0 and m[0] != "Base" and m[0] != "City" else "", int(m[1])])
	return UI.label("%s %d  (%s)" % [title, total, ", ".join(parts)], 14)
