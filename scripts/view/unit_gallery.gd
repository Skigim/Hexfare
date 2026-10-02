extends Node2D
## Dev scene for reviewing unit art: every unit with a sprite sheet in a column and each role in a
## row (idle, walk, attack, hit, death; a settler's build in the attack row), all looping on grass
## tiles at the game's scale, on the civ-coloured stand the map draws.
##   godot --path . res://scenes/unit_gallery.tscn -- [--dir=se] [--units=archer,warrior]
##   [--zoom=1.0] [--pause | --frame=4] [--screenshot=out.png --delay=1.0]
## --dir picks the facing (e, ne, nw, w, sw, se) and --units the columns (default: every unit with a
## sheet, in data order). --pause freezes each cell on its key frame (the shot's release or the
## blow, the flinch, the body lying); --frame=N freezes every cell on frame N (or a role's last).

const ROWS := ["idle", "walk", "attack", "hit", "death"]
const FACINGS := ["e", "ne", "nw", "w", "sw", "se"]   # Hex.DIRECTIONS order
const COLUMN := 214.0
const ROW := 162.0
const HOLD := 0.7   # seconds a one-shot role rests before it plays again

var _args: Dictionary = {}


func _ready() -> void:
	Defs.ensure_loaded()
	_args = DevTools.args()
	var facing := maxi(FACINGS.find(_args.get("dir", "se")), 0)
	var wanted := String(_args.get("units", "")).split(",", false)
	var units: Array[String] = []
	for id in Defs.units:
		if UnitSprite.has_sheet(id) and (wanted.is_empty() or id in wanted):
			units.append(id)
	for c in units.size():
		var id := units[c]
		var color := Color.html(Defs.civs[Defs.units.keys().find(id) % Defs.civs.size()].color)
		_label(Defs.units[id].get("name", id), Vector2(c * COLUMN, -ROW * 0.5 - 40), true)
		for r in ROWS.size():
			_cell(id, ROWS[r], Vector2(c * COLUMN, r * ROW), color, facing)
	for r in ROWS.size():
		_label(ROWS[r], Vector2(-COLUMN * 0.5 - 30, r * ROW), false)

	# Centred on the grid, its labels and the tallest figures (a rider's head rises above its row).
	var top_left := Vector2(-COLUMN * 0.5 - 60, -ROW * 0.5 - 56)
	var bottom_right := Vector2((units.size() - 0.5) * COLUMN, (ROWS.size() - 1) * ROW + 76)
	var camera := Camera2D.new()
	var zoom := float(_args.get("zoom", 1.0))
	camera.zoom = Vector2(zoom, zoom)
	camera.position = (top_left + bottom_right) * 0.5
	add_child(camera)
	if _args.has("screenshot"):
		DevTools.capture_and_quit(self, _args.screenshot, float(_args.get("delay", 1.0)))


## One unit playing one role on a grass tile. A role the unit lacks leaves the tile empty, except
## that a unit that never attacks shows its build there.
func _cell(id: String, role: String, at: Vector2, color: Color, facing: int) -> void:
	var tile := Sprite2D.new()
	tile.texture = Tex.terrain("grass_05")
	tile.position = at
	add_child(tile)
	var sprite := UnitSprite.create(id, color, false)
	if role == "attack" and not sprite.has_role(role) and sprite.has_role("build"):
		role = "build"
	if not sprite.has_role(role):
		sprite.free()
		return
	sprite.scale = Vector2.ONE * UnitView.SPRITE_SCALE
	var stand := _Stand.new()
	stand.radii = sprite.base_size * UnitView.SPRITE_SCALE if sprite.base_size != Vector2.ZERO \
			else Vector2(UnitView.BASE_RX, UnitView.BASE_RY)
	stand.color = color
	stand.position = at
	add_child(stand)
	sprite.position = at
	sprite.face(facing)
	add_child(sprite)
	if _args.has("pause") or _args.has("frame"):
		sprite.act(role)
		var last := sprite.sprite_frames.get_frame_count(sprite.animation) - 1
		sprite.frame = mini(int(_args.frame), last) if _args.has("frame") else _key_frame(sprite, role, last)
		sprite.pause()
	elif role in ["idle", "walk"]:
		sprite.act(role)
	else:
		_replay(sprite, role)


## The frame that best shows a role in a still.
func _key_frame(sprite: UnitSprite, role: String, last: int) -> int:
	var fps := sprite.sprite_frames.get_animation_speed(sprite.animation)
	match role:
		"walk":
			return 2
		"attack":
			var release := sprite.mark_time(role, "release")
			return roundi(release * fps) if release >= 0.0 else 4
		"build":
			return roundi(maxf(sprite.mark_time(role, "strike"), 0.0) * fps)
		"hit":
			return 1
		"death":
			return last
	return 0


func _replay(sprite: UnitSprite, role: String) -> void:
	while is_inside_tree():
		sprite.act(role)
		await get_tree().create_timer(sprite.role_time(role) + HOLD).timeout


func _label(text: String, center: Vector2, title: bool) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Tex.font())
	l.add_theme_font_size_override("font_size", 22 if title else 18)
	l.add_theme_color_override("font_color", Color.WHITE if title else Color(0.8, 0.84, 0.9))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(160, 30)
	l.position = center - l.size * 0.5
	add_child(l)


## The civ-coloured oval with a white rim that UnitView draws under a figure.
class _Stand extends Node2D:
	var radii := Vector2(24, 10)
	var color := Color.WHITE

	func _draw() -> void:
		draw_colored_polygon(_oval(radii + Vector2(3, 2), Vector2(2, 3)), Color(0, 0, 0, 0.35))
		draw_colored_polygon(_oval(radii + Vector2(3, 2)), Color.WHITE)
		draw_colored_polygon(_oval(radii), color.darkened(0.1))

	func _oval(r: Vector2, center: Vector2 = Vector2.ZERO) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 28:
			var a := TAU * i / 28.0
			pts.append(center + Vector2(cos(a) * r.x, sin(a) * r.y))
		return pts
