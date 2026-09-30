class_name UnitView
extends Node2D
## A unit token: civ-colored disc (military) or diamond (civilian) with a white icon,
## plus health bar and status pips.

const RADIUS := 23.0

var unit_id: int = -1
var coord := Hex.NONE
var color := Color.WHITE
var icon: Texture2D
var civilian := false
var hp_ratio := 1.0
var exhausted := false
var status := ""        # "", "fortified", "sleeping", "moving"
var _tween: Tween


func sync_from(u: Unit, player_color: Color, own: bool) -> void:
	unit_id = u.id
	color = player_color
	icon = Tex.icon(u.def().get("icon", "pawn"))
	civilian = u.is_civilian()
	hp_ratio = float(u.hp) / float(Defs.rules.units.max_hp)
	exhausted = own and u.moves_left <= 0
	status = "fortified" if u.fortified else ("sleeping" if u.sleeping else ("moving" if u.has_destination else ""))
	queue_redraw()


func is_animating() -> bool:
	return _tween != null and _tween.is_running()


## Moves along world-space points; returns the tween.
func animate_path(points: Array, step_time: float = 0.09) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	for p in points:
		_tween.tween_property(self, "position", p, step_time)


func lunge(toward: Vector2) -> void:
	if _tween != null and _tween.is_running():
		return
	var home := position
	_tween = create_tween()
	_tween.tween_property(self, "position", home.lerp(toward, 0.35), 0.08)
	_tween.tween_property(self, "position", home, 0.12)


func _draw() -> void:
	var r := RADIUS
	var ring := Color(0.55, 0.58, 0.62) if exhausted else Color.WHITE
	if civilian:
		r = RADIUS * 0.85
		var d := _diamond(r + 3)
		draw_colored_polygon(_offset(d, Vector2(2, 3)), Color(0, 0, 0, 0.35))
		draw_colored_polygon(d, ring)
		draw_colored_polygon(_diamond(r), color)
	else:
		draw_circle(Vector2(2, 3), r + 3, Color(0, 0, 0, 0.35))
		draw_circle(Vector2.ZERO, r + 3, ring)
		draw_circle(Vector2.ZERO, r, color)
	if icon != null:
		var s := r * 1.15
		draw_texture_rect(icon, Rect2(-s * 0.5, -s * 0.5, s, s), false, Color(1, 1, 1, 0.75 if exhausted else 1.0))
	if hp_ratio < 1.0:
		var w := 44.0
		var y := r + 6
		draw_rect(Rect2(-w * 0.5 - 1, y - 1, w + 2, 7), Color(0, 0, 0, 0.8))
		var hp_color := Color("#7ed957") if hp_ratio > 0.6 else (Color("#f6d44a") if hp_ratio > 0.3 else Color("#ff6b5e"))
		draw_rect(Rect2(-w * 0.5, y, w * hp_ratio, 5), hp_color)
	if status != "":
		var pip := Vector2(r * 0.75, -r * 0.75)
		draw_circle(pip, 9, Color(0.1, 0.12, 0.15, 0.95))
		var letter: String = {"fortified": "F", "sleeping": "Z", "moving": ">"}[status]
		draw_string(Tex.font(), pip + Vector2(-5, 6), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)


static func _diamond(r: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, -r), Vector2(r, 0), Vector2(0, r), Vector2(-r, 0)])


static func _offset(pts: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + by)
	return out
