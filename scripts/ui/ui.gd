class_name UI
extends RefCounted
## Small helpers for building Control trees in code.


static func label(text: String = "", font_size: int = 16, color: Color = UITheme.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


static func wrap_label(text: String = "", font_size: int = 15, color: Color = UITheme.TEXT_DIM) -> Label:
	var l := label(text, font_size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 120
	return l


static func icon(tex: Texture2D, px: int = 20, color: Color = Color.WHITE) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(px, px)
	r.modulate = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func button(text: String, callback: Callable, tooltip: String = "", tex: Texture2D = null) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	if tex != null:
		b.icon = tex
		b.expand_icon = false
	b.pressed.connect(callback)
	return b


static func hbox(separation: int = 6) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", separation)
	return b


static func vbox(separation: int = 6) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", separation)
	return b


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func progress(value: float, max_value: float, color: Color, height: int = 8) -> ProgressBar:
	var p := ProgressBar.new()
	p.max_value = maxf(1.0, max_value)
	p.value = clampf(value, 0.0, p.max_value)
	p.show_percentage = false
	p.custom_minimum_size = Vector2(60, height)
	p.add_theme_stylebox_override("fill", UITheme.box(color, Color.TRANSPARENT, 3, 0))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Row of yield icons with numbers, e.g. food 4, production 3...
static func yield_row(y: Dictionary, keys: Array = Yields.TYPES, px: int = 18, skip_zero: bool = false) -> HBoxContainer:
	var row := hbox(4)
	for k in keys:
		var v := int(y.get(k, 0))
		if skip_zero and v == 0:
			continue
		row.add_child(icon(Tex.yield_icon(k), px, Tex.YIELD_COLORS[k]))
		var l := label(str(v), px - 2, Tex.YIELD_COLORS[k])
		l.custom_minimum_size.x = 18
		row.add_child(l)
	return row


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


static func header(text: String) -> HBoxContainer:
	var row := hbox(8)
	var l := label(text.to_upper(), 13, UITheme.TEXT_DIM)
	row.add_child(l)
	var sep := HSeparator.new()
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sep)
	return row
