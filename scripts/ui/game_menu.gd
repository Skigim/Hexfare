class_name GameMenu
extends Control
## Pause menu and game-over screen (same overlay, different buttons).

signal action(action_name: String)

var _title: Label
var _subtitle: Label
var _buttons: VBoxContainer


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	center.add_child(panel)
	var col := UI.vbox(12)
	panel.add_child(col)
	_title = UI.label("", 30)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	_subtitle = UI.wrap_label("", 16)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_subtitle)
	_buttons = UI.vbox(8)
	col.add_child(_buttons)


func open_pause(can_load: bool) -> void:
	_title.text = "Paused"
	_subtitle.text = "WASD/arrows pan, wheel zooms. Left-click selects, right-click moves/attacks."
	_set_buttons([["Resume", "resume", true], ["Quick Save (F5)", "save", true], ["Quick Load (F9)", "load", can_load],
		["Main Menu", "menu", true], ["Quit", "quit", true]])
	visible = true


func open_game_over(title: String, subtitle: String) -> void:
	_title.text = title
	_subtitle.text = subtitle
	_set_buttons([["Keep Looking", "resume", true], ["Main Menu", "menu", true], ["Quit", "quit", true]])
	visible = true


func _set_buttons(defs: Array) -> void:
	UI.clear(_buttons)
	for d in defs:
		var b := UI.button(d[0], func(): action.emit(d[1]))
		b.disabled = not d[2]
		b.custom_minimum_size.y = 40
		_buttons.add_child(b)
