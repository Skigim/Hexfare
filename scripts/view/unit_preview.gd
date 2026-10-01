extends Node2D
## Dev scene: shows a unit's 3D model as the map would and cycles through its roles
## (idle, walk, attack, hit, death).
##   godot --path . res://scenes/unit_preview.tscn -- --unit=warrior [--anim=Walking_A]
##   --screenshot=out.png [--delay=1.0]   save one frame and quit
##   --sheet=out.png [--clips=a,b] [--frames=6]   save a contact sheet (one row per clip, frames
##       evenly spaced through it; roles or clip names) and quit
##   --right-rot=x,y,z / --left-rot=x,y,z (and -pos)   try a piece transform without editing data
##   --facing=DEG   turn the model (0 faces the camera, 90 shows its right side)

const SHEET_CELL := 256
const ROLES := ["idle", "walk", "attack", "hit", "death"]

var portrait: UnitPortrait
var label: Label


func _ready() -> void:
	Defs.ensure_loaded()
	var args := DevTools.args()
	var id: String = args.get("unit", "warrior")
	var model: Dictionary = Defs.units.get(id, {}).get("model", {}).duplicate(true)
	for hand in UnitModel.HAND_SLOTS:
		for key in ["rot", "pos"]:
			var arg := "%s-%s" % [hand, key]
			if args.has(arg) and model.has(hand):
				model[hand]["rotation" if key == "rot" else "position"] = Array(args[arg].split_floats(","))
	if args.has("facing"):
		model.facing = float(args.facing)
	portrait = UnitPortrait.create(model, 512)
	if portrait == null:
		push_error("unit_preview: %s has no usable model" % id)
		get_tree().quit(1)
		return
	add_child(portrait)
	var sprite := Sprite2D.new()
	sprite.texture = portrait.texture()
	sprite.position = Vector2(800, 450)
	add_child(sprite)
	label = Label.new()
	label.position = Vector2(20, 20)
	add_child(label)

	if args.has("sheet"):
		var clips: Array = Array(args.get("clips", ",".join(ROLES)).split(","))
		await _save_sheet(clips, int(args.get("frames", 6)), args.sheet)
		get_tree().quit()
	elif args.has("anim"):
		_show(args.anim)
		if args.has("screenshot"):
			DevTools.capture_and_quit(self, args.screenshot, float(args.get("delay", 0.6)))
	elif args.has("screenshot"):
		_show("idle")
		DevTools.capture_and_quit(self, args.screenshot, float(args.get("delay", 0.6)))
	else:
		_cycle()


## Shows each role in turn: looping roles for a few seconds, one-shots for their length.
func _cycle() -> void:
	while true:
		for role in ROLES:
			_show(role)
			var clip: String = portrait.model.clips[role]
			var hold := 3.0 if role in UnitModel.LOOPING_ROLES else portrait.model.clip_length(clip) + 0.8
			await get_tree().create_timer(hold).timeout


func _show(role_or_clip: String) -> void:
	var model := portrait.model
	var clip: String = model.clips.get(role_or_clip, role_or_clip)
	label.text = "%s (%s)" % [role_or_clip, clip] if clip != role_or_clip else clip
	model.act(role_or_clip)


## Renders `frames` evenly spaced poses of each clip into one image, one row per clip.
func _save_sheet(names: Array, frames: int, path: String) -> void:
	var model := portrait.model
	var sheet := Image.create(SHEET_CELL * frames, SHEET_CELL * names.size(), false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.06, 0.07, 0.09))
	model.player.speed_scale = 0.0
	for row in names.size():
		var clip: String = model.clips.get(names[row], names[row])
		if not model.has_clip(clip):
			push_warning("unit_preview: no clip %s" % clip)
			continue
		var length := model.clip_length(clip)
		var loops: bool = model.player.get_animation(clip).loop_mode != Animation.LOOP_NONE
		print("row %d: %s (%.2fs)" % [row, clip, length])
		for f in frames:
			var t := length * f / (frames if loops else maxi(frames - 1, 1))
			model.play(clip, 0.0)
			model.player.seek(t, true)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var cell := portrait.get_texture().get_image()
			cell.resize(SHEET_CELL, SHEET_CELL, Image.INTERPOLATE_LANCZOS)
			cell.convert(Image.FORMAT_RGBA8)
			sheet.blend_rect(cell, Rect2i(Vector2i.ZERO, cell.get_size()), Vector2i(f * SHEET_CELL, row * SHEET_CELL))
	sheet.save_png(path)
	print("Saved sheet to ", path)
