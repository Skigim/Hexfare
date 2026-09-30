extends Control
## Title screen: new game settings, continue from quicksave, quit.

var _size: OptionButton
var _opponents: SpinBox
var _seed: LineEdit
var _size_keys: Array = []


func _ready() -> void:
	Defs.ensure_loaded()
	theme = UITheme.get_theme()
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := UI.vbox(14)
	col.custom_minimum_size = Vector2(440, 0)
	center.add_child(col)

	var title := UI.label("HEXFARE", 72, UITheme.ACCENT)
	title.add_theme_font_override("font", Tex.title_font())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := UI.label("A generic hex strategy framework", 18, UITheme.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	var panel := PanelContainer.new()
	col.add_child(panel)
	var form := UI.vbox(10)
	panel.add_child(form)
	form.add_child(UI.header("New Game"))

	_size = OptionButton.new()
	_size.focus_mode = Control.FOCUS_NONE
	var sizes: Dictionary = Defs.rules.map.sizes
	for key in sizes:
		_size_keys.append(key)
		_size.add_item("%s (%dx%d)" % [sizes[key].name, sizes[key].width, sizes[key].height])
	_size.selected = maxi(0, _size_keys.find("medium"))
	_size.item_selected.connect(_on_size_selected)
	form.add_child(_row("Map size", _size))

	_opponents = SpinBox.new()
	_opponents.min_value = 1
	_opponents.max_value = Defs.civs.size() - 1
	form.add_child(_row("AI opponents", _opponents))

	_seed = LineEdit.new()
	_seed.placeholder_text = "random"
	form.add_child(_row("Map seed", _seed))
	_on_size_selected(_size.selected)

	var start := UI.button("Start New Game", _on_start)
	start.custom_minimum_size.y = 46
	start.add_theme_font_size_override("font_size", 20)
	form.add_child(start)

	var cont := UI.button("Continue (Quick Save)", _on_continue)
	cont.disabled = not SaveLoad.exists()
	cont.custom_minimum_size.y = 40
	col.add_child(cont)
	var quit := UI.button("Quit", func(): get_tree().quit())
	quit.custom_minimum_size.y = 40
	col.add_child(quit)

	var credit := UI.label("Art: Kenney (kenney.nl, CC0)  ·  Built with Godot", 13, UITheme.TEXT_DIM)
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(credit)

	var args := DevTools.args()
	if args.has("screenshot"):
		DevTools.capture_and_quit(self, String(args.screenshot), 0.5)


func _row(title: String, field: Control) -> HBoxContainer:
	var row := UI.hbox(10)
	var l := UI.label(title, 17)
	l.custom_minimum_size.x = 150
	row.add_child(l)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	return row


func _on_size_selected(index: int) -> void:
	var size: Dictionary = Defs.rules.map.sizes[_size_keys[index]]
	_opponents.value = int(size.players) - 1


func _on_start() -> void:
	var size: Dictionary = Defs.rules.map.sizes[_size_keys[_size.selected]]
	var seed_text := _seed.text.strip_edges()
	var seed_value := seed_text.to_int() if seed_text.is_valid_int() else (seed_text.hash() if seed_text != "" else randi() % 1000000)
	Session.settings = {
		"width": size.width, "height": size.height, "players": int(_opponents.value) + 1,
		"seed": absi(seed_value), "human": true, "size": _size_keys[_size.selected],
	}
	Session.load_path = ""
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _on_continue() -> void:
	Session.load_path = SaveLoad.QUICKSAVE
	get_tree().change_scene_to_file("res://scenes/game.tscn")
