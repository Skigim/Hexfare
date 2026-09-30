class_name Tex
extends RefCounted
## Cached texture lookup for res://assets, plus yield icon/color conventions.

const YIELD_ICONS := {
	"food": "resource_apple", "production": "gear", "gold": "dollar",
	"science": "flask_full", "culture": "award",
}
const YIELD_COLORS := {
	"food": Color("#86dc5e"), "production": Color("#f2a553"), "gold": Color("#f6d44a"),
	"science": Color("#62c6ff"), "culture": Color("#d993ff"),
}
const RESOURCE_COLORS := {
	"bonus": Color("#b9f28f"), "strategic": Color("#ff9a8a"), "luxury": Color("#ffe07a"),
}

static var _cache: Dictionary = {}
static var _font: Font


static func load_cached(path: String) -> Texture2D:
	if not _cache.has(path):
		var tex: Texture2D = null
		if ResourceLoader.exists(path):
			tex = load(path)
		else:
			push_warning("Missing texture: %s" % path)
		_cache[path] = tex
	return _cache[path]


static func terrain(tile_name: String) -> Texture2D:
	return load_cached("res://assets/terrain/%s.png" % tile_name)


static func object(object_name: String) -> Texture2D:
	return load_cached("res://assets/objects/%s.png" % object_name)


static func icon(icon_name: String) -> Texture2D:
	return load_cached("res://assets/icons/%s.png" % icon_name)


static func yield_icon(yield_type: String) -> Texture2D:
	return icon(YIELD_ICONS[yield_type])


## Plain UI/map font (Godot's default). Kenney's display font is used only for titles.
static func font() -> Font:
	if _font == null:
		_font = ThemeDB.fallback_font
	return _font


static func title_font() -> Font:
	return load("res://assets/fonts/Kenney Future.ttf")
