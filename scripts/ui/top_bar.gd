class_name TopBar
extends PanelContainer
## Civ name, turn, treasury, science and current research.

signal tech_pressed
signal menu_pressed

var _swatch: ColorRect
var _civ: Label
var _turn: Label
var _gold: Label
var _science: Label
var _research: Label
var _progress: ProgressBar


func _init() -> void:
	add_theme_stylebox_override("panel", UITheme.box(UITheme.PANEL, UITheme.PANEL_BORDER, 0, 10))
	var row := UI.hbox(14)
	add_child(row)
	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(18, 18)
	_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_swatch)
	_civ = UI.label("", 20)
	row.add_child(_civ)
	_turn = UI.label("", 18, UITheme.TEXT_DIM)
	row.add_child(_turn)
	row.add_child(VSeparator.new())
	row.add_child(UI.icon(Tex.yield_icon("gold"), 22, Tex.YIELD_COLORS.gold))
	_gold = UI.label("", 18, Tex.YIELD_COLORS.gold)
	_gold.tooltip_text = "Treasury (net income per turn). Spend it to buy units and buildings in cities."
	_gold.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(_gold)
	row.add_child(UI.icon(Tex.yield_icon("science"), 22, Tex.YIELD_COLORS.science))
	_science = UI.label("", 18, Tex.YIELD_COLORS.science)
	row.add_child(_science)
	_research = UI.label("", 17)
	row.add_child(_research)
	_progress = UI.progress(0, 1, Tex.YIELD_COLORS.science, 10)
	_progress.custom_minimum_size = Vector2(170, 10)
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_progress)
	row.add_child(UI.spacer())
	row.add_child(UI.button("Technology (T)", func(): tech_pressed.emit(), "Open the technology tree"))
	row.add_child(UI.button("Menu (Esc)", func(): menu_pressed.emit()))


func refresh(game: Game, player: Player) -> void:
	var s := game.state
	_swatch.color = player.color
	_civ.text = player.name
	_turn.text = "Turn %d" % s.turn
	var income := CityRules.player_income(s, player.id)
	var net := int(income.net_gold)
	_gold.text = "%d (%s%d)" % [player.gold, "+" if net >= 0 else "", net]
	_science.text = "+%d" % int(income.science)
	if player.research != "":
		var cost := int(Defs.techs[player.research].cost)
		var prog := TechRules.progress(player, player.research)
		var turns := TechRules.turns_left(player, player.research, int(income.science))
		_research.text = "%s  %d/%d  (%s)" % [Defs.techs[player.research].name, prog, cost,
			"%d turns" % turns if turns > 0 else "stalled"]
		_research.add_theme_color_override("font_color", UITheme.TEXT)
		_progress.max_value = cost
		_progress.value = prog
		_progress.visible = true
	elif TechRules.available(player).is_empty():
		_research.text = "All technologies researched"
		_progress.visible = false
	else:
		_research.text = "Choose a research project!"
		_research.add_theme_color_override("font_color", UITheme.ACCENT)
		_progress.visible = false
