class_name UnitPanel
extends PanelContainer
## Selected unit: stats and order buttons.

signal action(action_name: String)

var _badge: TextureRect
var _name: Label
var _owner: Label
var _stats: Label
var _buttons: HFlowContainer
var _hint: Label


func _init() -> void:
	custom_minimum_size = Vector2(400, 0)
	var col := UI.vbox(8)
	add_child(col)
	var head := UI.hbox(10)
	col.add_child(head)
	_badge = UI.icon(null, 34)
	head.add_child(_badge)
	_name = UI.label("", 22)
	head.add_child(_name)
	head.add_child(UI.spacer())
	_owner = UI.label("", 15, UITheme.TEXT_DIM)
	head.add_child(_owner)
	_stats = UI.label("", 16)
	col.add_child(_stats)
	_buttons = HFlowContainer.new()
	_buttons.add_theme_constant_override("h_separation", 6)
	_buttons.add_theme_constant_override("v_separation", 6)
	col.add_child(_buttons)
	_hint = UI.wrap_label("", 14)
	col.add_child(_hint)


func show_unit(game: Game, u: Unit, own: bool, my_turn: bool) -> void:
	var s := game.state
	visible = true
	var owner := s.player(u.owner)
	_badge.texture = Tex.icon(u.def().get("icon", "pawn"))
	_badge.modulate = owner.color.lightened(0.25)
	_name.text = u.display_name()
	_owner.text = owner.name
	var parts := PackedStringArray()
	if u.is_military():
		parts.append("Strength %d" % int(u.def().strength))
		if u.is_ranged():
			parts.append("Ranged %d (range %d)" % [int(u.def().ranged_strength), u.attack_range()])
	parts.append("Moves %d/%d" % [u.moves_left, u.max_moves()])
	parts.append("HP %d/%d" % [u.hp, int(Defs.rules.units.max_hp)])
	_stats.text = "   ".join(parts)
	UI.clear(_buttons)
	if own and my_turn:
		_add_buttons(game, u)
	_hint.text = _status_text(game, u, own)


func _add_buttons(game: Game, u: Unit) -> void:
	var s := game.state
	if u.has_ability("found_city"):
		var blocker := CityRules.found_blocker(s, u.owner, u.coord)
		var b := _button("Found City (B)", "found", blocker if blocker != "" else "Found a new city on this tile.")
		b.disabled = blocker != "" or u.moves_left <= 0
	if u.is_ranged():
		var b := _button("Ranged Attack (R)", "ranged", "Choose a target within range %d." % u.attack_range())
		b.disabled = u.has_attacked or u.moves_left <= 0
	if u.is_military() and not u.fortified:
		_button("Fortify (F)", "fortify", "+%d defense until moved. Heals if left alone." % int(Defs.rules.combat.fortify_bonus))
	if u.is_civilian() and not u.sleeping:
		_button("Sleep", "sleep", "Stop asking for orders until woken.")
	if u.fortified or u.sleeping:
		_button("Wake", "wake", "Resume asking for orders.")
	if u.has_destination:
		_button("Cancel Move", "cancel", "Clear the current movement order.")
	if u.moves_left > 0:
		_button("Skip (Space)", "skip", "Do nothing this turn.")
	_button("Disband", "disband", "Delete this unit (saves upkeep).")


func _button(text: String, action_name: String, tooltip: String) -> Button:
	var b := UI.button(text, func(): action.emit(action_name), tooltip)
	_buttons.add_child(b)
	return b


func _status_text(game: Game, u: Unit, own: bool) -> String:
	if not own:
		return "Enemy unit."
	if u.fortified:
		return "Fortified."
	if u.sleeping:
		return "Sleeping."
	if u.has_destination:
		return "Moving to a destination."
	if u.moves_left <= 0:
		return "No moves left this turn."
	if u.has_ability("found_city"):
		return "Right-click to move. Found cities on good land (min. %d tiles apart)." % int(Defs.rules.city.min_distance)
	return "Right-click a tile to move, or an enemy to attack."
