class_name TechTreePanel
extends Control
## Full-screen technology tree. Columns are tiers; click any tech to research it
## (missing prerequisites are queued automatically).

signal tech_chosen(tech_id: String)
signal closed

const CARD := Vector2(228, 96)
const COL_GAP := 284.0
const ROW_GAP := 116.0

var _canvas: TechCanvas
var _title: Label


class TechCanvas extends Control:
	var lines: Array = []   # [[from_rect, to_rect, color]]

	func _draw() -> void:
		for l in lines:
			var a: Vector2 = Vector2(l[0].end.x, l[0].get_center().y)
			var b: Vector2 = Vector2(l[1].position.x, l[1].get_center().y)
			var mid := (a.x + b.x) * 0.5
			var pts := PackedVector2Array([a, Vector2(mid, a.y), Vector2(mid, b.y), b])
			draw_polyline(pts, l[2], 3.0, true)


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 40
	panel.offset_top = 40
	panel.offset_right = -40
	panel.offset_bottom = -40
	add_child(panel)
	var col := UI.vbox(10)
	panel.add_child(col)
	var head := UI.hbox(10)
	col.add_child(head)
	_title = UI.label("Technology", 26)
	head.add_child(_title)
	head.add_child(UI.spacer())
	head.add_child(UI.button("Close (Esc)", func(): closed.emit()))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	_canvas = TechCanvas.new()
	scroll.add_child(_canvas)


func refresh(game: Game, player: Player) -> void:
	UI.clear(_canvas)
	var income := CityRules.player_income(game.state, player.id)
	var science := int(income.science)
	_title.text = "Technology — %d known, +%d science per turn" % [player.techs.size(), science]
	var by_tier := {}
	for id in Defs.techs:
		var tier := int(Defs.techs[id].tier)
		if not by_tier.has(tier):
			by_tier[tier] = []
		by_tier[tier].append(id)
	var rects := {}
	var max_rows := 0
	var tiers: Array = by_tier.keys()
	tiers.sort()
	for ti in tiers.size():
		var ids: Array = by_tier[tiers[ti]]
		max_rows = maxi(max_rows, ids.size())
		for row in ids.size():
			rects[ids[row]] = Rect2(Vector2(20 + ti * COL_GAP, 20 + row * ROW_GAP), CARD)
	_canvas.custom_minimum_size = Vector2(40 + tiers.size() * COL_GAP, 40 + max_rows * ROW_GAP)
	var queued: Array = [player.research] + player.research_queue
	_canvas.lines.clear()
	for id in Defs.techs:
		for req in Defs.techs[id].requires:
			var color := Color(0.45, 0.52, 0.6) if player.has_tech(req) else Color(0.3, 0.34, 0.4)
			_canvas.lines.append([rects[req], rects[id], color])
		_canvas.add_child(_card(player, id, rects[id], queued, science))
	_canvas.queue_redraw()


func _card(player: Player, id: String, rect: Rect2, queued: Array, science: int) -> Control:
	var def: Dictionary = Defs.techs[id]
	var known := player.has_tech(id)
	var current := player.research == id
	var queue_pos := queued.find(id)
	var available := TechRules.can_research(player, id)
	var bg := Color("#2b3645")
	var border := UITheme.PANEL_BORDER
	if known:
		bg = Color("#24452f")
		border = UITheme.GOOD
	elif current:
		bg = Color("#4a3f17")
		border = UITheme.ACCENT
	elif queue_pos > 0:
		bg = Color("#2a3550")
		border = Color("#6f8fd6")
	elif not available:
		bg = Color("#1c222b")
	var card := Button.new()
	card.position = rect.position
	card.size = rect.size
	card.focus_mode = Control.FOCUS_NONE
	card.disabled = known
	for st in ["normal", "hover", "pressed", "disabled"]:
		var sb := UITheme.box(bg.lightened(0.08) if st == "hover" else bg, border, 6, 8)
		card.add_theme_stylebox_override(st, sb)
	card.pressed.connect(func(): tech_chosen.emit(id))
	var col := UI.vbox(3)
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 10
	col.offset_top = 6
	col.offset_right = -8
	col.offset_bottom = -6
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)
	var title := UI.label(def.name, 18, UITheme.TEXT if (known or available or current) else UITheme.TEXT_DIM)
	col.add_child(title)
	var status := ""
	if known:
		status = "Researched"
	else:
		var turns := TechRules.turns_left(player, id, science)
		status = "%d / %d science" % [TechRules.progress(player, id), int(def.cost)]
		if turns > 0:
			status += "  ·  %d turns" % turns
		if queue_pos > 0:
			status = "#%d in queue · " % (queue_pos + 1) + status
	col.add_child(UI.label(status, 13, UITheme.TEXT_DIM))
	var unlocks := TechRules.unlocks(id)
	var icons := UI.hbox(4)
	var tip := PackedStringArray()
	for u in unlocks.units:
		icons.add_child(UI.icon(Tex.icon(Defs.units[u].icon), 20))
		tip.append("Unit: %s" % Defs.units[u].name)
	for b in unlocks.buildings:
		icons.add_child(UI.icon(Tex.icon(Defs.buildings[b].icon), 20))
		tip.append("Building: %s" % Defs.buildings[b].name)
	for r in unlocks.resources:
		icons.add_child(UI.icon(Tex.icon(Defs.resources[r].icon), 20, Tex.RESOURCE_COLORS.get(Defs.resources[r].category, Color.WHITE)))
		tip.append("Reveals: %s" % Defs.resources[r].name)
	for text in unlocks.bonuses:
		icons.add_child(UI.label(text, 12, UITheme.TEXT_DIM))
		tip.append(text)
	col.add_child(icons)
	card.tooltip_text = "\n".join(tip) if not tip.is_empty() else def.name
	return card
