class_name PathLayer
extends Node2D
## Movement path preview with end-of-turn markers (drawn above units).

var start := Hex.NONE
var steps: Array = []        # [{coord, turn}] from Pathfinder.annotate
var attack_target := Hex.NONE


func clear() -> void:
	start = Hex.NONE
	steps = []
	attack_target = Hex.NONE
	queue_redraw()


func _draw() -> void:
	if start == Hex.NONE or (steps.is_empty() and attack_target == Hex.NONE):
		return
	var pts := PackedVector2Array([Hex.to_pixel(start)])
	for s in steps:
		pts.append(Hex.to_pixel(s.coord))
	if pts.size() > 1:
		draw_polyline(pts, Color(0, 0, 0, 0.45), 9.0, true)
		draw_polyline(pts, Color(1, 1, 1, 0.9), 5.0, true)
	if attack_target != Hex.NONE:
		var from := pts[pts.size() - 1]
		var to := Hex.to_pixel(attack_target)
		draw_line(from, from.lerp(to, 0.75), Color(1, 0.3, 0.25, 0.95), 6.0, true)
		draw_circle(to, 10, Color(1, 0.3, 0.25, 0.95))
	var font := Tex.font()
	for i in steps.size():
		var s: Dictionary = steps[i]
		var ends_turn: bool = i == steps.size() - 1 or steps[i + 1].turn != s.turn
		if not ends_turn:
			continue
		var p := Hex.to_pixel(s.coord)
		draw_circle(p, 15, Color(0.1, 0.12, 0.15, 0.95))
		draw_arc(p, 15, 0, TAU, 32, Color.WHITE, 2.0, true)
		var text := str(s.turn + 1)
		var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
		draw_string(font, p + Vector2(-size.x * 0.5, 7), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
