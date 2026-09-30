class_name UITheme
extends RefCounted
## Builds the (deliberately plain) dark UI theme used by all screens.

const TEXT := Color("#e8eef5")
const TEXT_DIM := Color("#9aa7b6")
const PANEL := Color(0.075, 0.095, 0.125, 0.94)
const PANEL_BORDER := Color("#3b4859")
const BUTTON := Color("#2b3645")
const BUTTON_HOVER := Color("#3a4a5f")
const BUTTON_PRESSED := Color("#1f2833")
const ACCENT := Color("#e3b21f")
const GOOD := Color("#7ed957")
const BAD := Color("#ff6b5e")

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func box(color: Color, border: Color = Color.TRANSPARENT, radius: int = 6, margin: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(1)
	return sb


static func _build() -> Theme:
	var t := Theme.new()
	t.default_font = Tex.font()
	t.default_font_size = 16
	var panel := box(PANEL, PANEL_BORDER, 8, 12)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	t.set_stylebox("panel", "PopupMenu", box(PANEL, PANEL_BORDER, 4, 6))
	t.set_stylebox("panel", "TooltipPanel", box(Color(0.05, 0.06, 0.08, 0.97), PANEL_BORDER, 4, 8))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_color("font_color", "Label", TEXT)

	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var color: Color = {"normal": BUTTON, "hover": BUTTON_HOVER, "pressed": BUTTON_PRESSED,
			"disabled": Color(0.13, 0.15, 0.18, 0.8), "focus": Color.TRANSPARENT}[state]
		var sb := box(color, PANEL_BORDER if state != "focus" else Color.TRANSPARENT, 5, 8)
		sb.content_margin_top = 5
		sb.content_margin_bottom = 5
		if state == "focus":
			sb.draw_center = false
		t.set_stylebox(state, "Button", sb)
		t.set_stylebox(state, "OptionButton", sb)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", Color(0.55, 0.6, 0.66, 0.7))
	t.set_constant("icon_max_width", "Button", 22)
	t.set_constant("h_separation", "Button", 6)

	var field := box(Color(0.05, 0.06, 0.08, 1), PANEL_BORDER, 4, 6)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", box(Color(0.05, 0.06, 0.08, 1), ACCENT, 4, 6))
	t.set_color("font_color", "LineEdit", TEXT)

	t.set_stylebox("background", "ProgressBar", box(Color(0.03, 0.04, 0.05, 1), Color.TRANSPARENT, 3, 0))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, Color.TRANSPARENT, 3, 0))
	t.set_stylebox("separator", "HSeparator", _line())
	t.set_constant("separation", "HSeparator", 10)
	t.set_constant("separation", "HBoxContainer", 6)
	t.set_constant("separation", "VBoxContainer", 6)
	return t


static func _line() -> StyleBoxLine:
	var sb := StyleBoxLine.new()
	sb.color = PANEL_BORDER
	sb.thickness = 1
	return sb
