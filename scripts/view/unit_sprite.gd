class_name UnitSprite
extends AnimatedSprite2D
## A unit drawn from a pre-rendered sprite sheet (made in Blender, see art/<unit>/build_<unit>.py):
## six facings that line up with the hex neighbours, team colour from a mask, a ground shadow.
## Sheets live in res://assets/units/<id>/<id>.png with <id>_mask.png and <id>.json beside them.
##   var s := UnitSprite.create("warrior", civ_color)
##   s.face(Hex.DIRECTIONS.find(step)); s.act("walk")

const ROOT := "res://assets/units/%s/%s"
const ROLES := ["idle", "walk", "attack", "hit", "death"]
const SHADER := preload("res://scripts/view/team_sprite.gdshader")

static var _sheets: Dictionary = {}   # id -> {frames: SpriteFrames, mask: Texture2D, meta: Dictionary}

var unit_type := ""
var direction := 5           # index into Hex.DIRECTIONS; 5 (south-east) faces the viewer
var role := "idle"
var _directions: Array = []


static var _has_sheet: Dictionary = {}


static func has_sheet(id: String) -> bool:
	if not _has_sheet.has(id):
		_has_sheet[id] = FileAccess.file_exists((ROOT % [id, id]) + ".json")
	return _has_sheet[id]


static func create(id: String, team_color: Color, with_shadow: bool = true) -> UnitSprite:
	var sheet := _sheet(id)
	if sheet.is_empty():
		return null
	var s := UnitSprite.new()
	s.unit_type = id
	s.sprite_frames = sheet.frames
	s._directions = sheet.meta.directions
	var meta: Dictionary = sheet.meta
	s.centered = true
	s.offset = Vector2(meta.cell[0] * 0.5 - meta.anchor[0], meta.cell[1] * 0.5 - meta.anchor[1])
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("mask_tex", sheet.mask)
	mat.set_shader_parameter("team_color", team_color)
	s.material = mat
	s.animation_finished.connect(s._on_finished)
	if with_shadow:
		var shadow := _Shadow.new()
		shadow.show_behind_parent = true
		s.add_child(shadow)
	s.act("idle")
	return s


## Index into Hex.DIRECTIONS (0 = east, counter-clockwise) for a screen-space step.
static func direction_toward(step: Vector2) -> int:
	return posmod(roundi(atan2(-step.y, step.x) / (PI / 3.0)), 6)


func face(dir: int) -> void:
	if dir == direction or dir < 0:
		return
	direction = dir
	_play_keeping_frame()


## Plays a role ("idle", "walk", "attack", "hit", "death"). Attack and hit fall back to idle;
## death holds its last frame.
func act(new_role: String) -> void:
	role = new_role
	play(_name())
	(material as ShaderMaterial).set_shader_parameter("flash", 0.6 if role == "hit" else 0.0)
	if role == "hit":
		create_tween().tween_method(func(v: float) -> void: (material as ShaderMaterial).set_shader_parameter("flash", v), 0.6, 0.0, 0.25)


func set_team_color(c: Color) -> void:
	(material as ShaderMaterial).set_shader_parameter("team_color", c)


func _name() -> String:
	return "%s_%s" % [role, _directions[direction]]


func _play_keeping_frame() -> void:
	var f := frame
	var p := frame_progress
	play(_name())
	set_frame_and_progress(f, p)


func _on_finished() -> void:
	if role == "attack" or role == "hit":
		act("idle")


static func _sheet(id: String) -> Dictionary:
	if _sheets.has(id):
		return _sheets[id]
	var base := ROOT % [id, id]
	var text := FileAccess.get_file_as_string(base + ".json")
	if text.is_empty():
		push_warning("UnitSprite: no sheet for %s" % id)
		return {}
	var meta: Dictionary = Defs.normalize(JSON.parse_string(text))
	var dir := base.get_base_dir() + "/"
	var tex: Texture2D = load(dir + meta.sheet)
	var w: int = meta.cell[0]
	var h: int = meta.cell[1]
	var columns: int = meta.columns
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for anim in meta.animations:
		var info: Dictionary = meta.animations[anim]
		var count: int = info.frames
		for d in meta.directions.size():
			var anim_name := "%s_%s" % [anim, meta.directions[d]]
			frames.add_animation(anim_name)
			frames.set_animation_loop(anim_name, info.loop)
			frames.set_animation_speed(anim_name, meta.fps)
			for f in count:
				var index: int = info.first + d * count + f
				var cell := AtlasTexture.new()
				cell.atlas = tex
				cell.region = Rect2((index % columns) * w, (index / columns) * h, w, h)
				frames.add_frame(anim_name, cell)
	_sheets[id] = {"frames": frames, "mask": load(dir + meta.mask), "meta": meta}
	return _sheets[id]


## Soft ellipse under the feet, drawn behind the sprite.
class _Shadow extends Node2D:
	func _draw() -> void:
		var pts := PackedVector2Array()
		for i in 24:
			var a := TAU * i / 24.0
			pts.append(Vector2(cos(a) * 26.0, sin(a) * 10.0))
		draw_colored_polygon(pts, Color(0, 0, 0, 0.28))
