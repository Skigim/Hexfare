class_name NotificationFeed
extends VBoxContainer
## Recent messages for the human player; click one to jump to its location.

signal entry_clicked(coord: Vector2i)

const MAX_ENTRIES := 6


func _init() -> void:
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func refresh(game: Game, pid: int) -> void:
	UI.clear(self)
	var shown := 0
	var entries := game.log_entries
	for i in range(entries.size() - 1, -1, -1):
		var e: Dictionary = entries[i]
		if e.player != pid:
			continue
		if e.turn < game.state.turn - 1 or shown >= MAX_ENTRIES:
			break
		var b := Button.new()
		b.text = e.text
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_stylebox_override("normal", UITheme.box(Color(0.05, 0.06, 0.08, 0.8 if e.turn == game.state.turn else 0.55), Color.TRANSPARENT, 4, 6))
		b.add_theme_color_override("font_color", UITheme.TEXT if e.turn == game.state.turn else UITheme.TEXT_DIM)
		var coord: Vector2i = e.coord
		b.disabled = coord == Hex.NONE
		b.add_theme_color_override("font_disabled_color", UITheme.TEXT if e.turn == game.state.turn else UITheme.TEXT_DIM)
		b.add_theme_stylebox_override("disabled", b.get_theme_stylebox("normal"))
		b.pressed.connect(func(): entry_clicked.emit(coord))
		add_child(b)
		shown += 1
