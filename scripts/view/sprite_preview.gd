extends Node2D
## Dev scene for sprite-sheet units on real hex tiles:
##   - the centre unit cycles idle, attack, hit and death;
##   - one unit on each neighbouring hex faces away from the centre (guide lines show the hex axes);
##   - a patrol walks the outer ring, turning to face each step.
##   godot --path . res://scenes/sprite_preview.tscn -- [--unit=warrior] [--anim=walk]
##   [--zoom=1.25] [--screenshot=out.png --delay=1.0]

const SCALE := 0.8

var unit := "warrior"
var center: UnitSprite
var patrol: UnitSprite
var _ring: Array[Vector2i] = []
var _args: Dictionary = {}


func _ready() -> void:
	Defs.ensure_loaded()
	_args = DevTools.args()
	unit = _args.get("unit", "warrior")
	for c in Hex.within(Vector2i.ZERO, 2):
		var tile := Sprite2D.new()
		tile.texture = Tex.terrain("grass_05")
		tile.position = Hex.to_pixel(c)
		add_child(tile)
	var guides := _Guides.new()
	add_child(guides)

	center = _spawn(Vector2i.ZERO, 0, 5)
	for d in Hex.DIRECTIONS.size():
		var s := _spawn(Hex.DIRECTIONS[d], d + 1, d)
		s.act(_args.get("anim", "walk"))
	_ring = Hex.ring(Vector2i.ZERO, 2)
	patrol = _spawn(_ring[0], 4, 5)

	var camera := Camera2D.new()
	var zoom := float(_args.get("zoom", 1.25))
	camera.zoom = Vector2(zoom, zoom)
	add_child(camera)

	if _args.has("anim"):
		center.act(_args.anim)
		patrol.act(_args.anim)
	else:
		_cycle_center()
		_walk_patrol()
	if _args.has("screenshot"):
		DevTools.capture_and_quit(self, _args.screenshot, float(_args.get("delay", 1.0)))


func _spawn(c: Vector2i, civ: int, dir: int) -> UnitSprite:
	var s := UnitSprite.create(unit, Color.html(Defs.civs[civ % Defs.civs.size()].color))
	s.position = Hex.to_pixel(c)
	s.scale = Vector2.ONE * SCALE
	s.face(dir)
	add_child(s)
	return s


func _cycle_center() -> void:
	while true:
		for r in ["idle", "attack", "idle", "hit", "idle", "death"]:
			center.act(r)
			await get_tree().create_timer(2.0 if r == "idle" or r == "death" else 1.0).timeout


func _walk_patrol() -> void:
	var i := 0
	patrol.act("walk")
	while true:
		var from := _ring[i % _ring.size()]
		var to := _ring[(i + 1) % _ring.size()]
		patrol.face(Hex.DIRECTIONS.find(to - from))
		var tween := create_tween()
		tween.tween_property(patrol, "position", Hex.to_pixel(to), UnitView.SPRITE_STEP_TIME)
		await tween.finished
		i += 1


## Lines from the centre hex through each neighbour: the axes the six facings follow.
class _Guides extends Node2D:
	func _draw() -> void:
		for d in Hex.DIRECTIONS:
			draw_dashed_line(Vector2.ZERO, Hex.to_pixel(d * 2), Color(1, 1, 1, 0.45), 2.0, 8.0)
