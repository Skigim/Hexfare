class_name HighlightLayer
extends Node2D
## Selection, hover, movement range and attack-target overlays (drawn under units).

var reachable: Dictionary = {}   # coord -> g
var targets: Array = []          # coords that can be attacked
var selected := Hex.NONE
var hover := Hex.NONE
var range_center := Hex.NONE     # draw a range ring (city bombard / ranged)
var range_radius := 0
var worked: Array = []           # tiles worked by the selected city (citizen markers)


func _draw() -> void:
	var hexagon := Hex.corners(Vector2.ZERO, 0.97)
	for c in reachable:
		_fill(c, hexagon, Color(1, 1, 1, 0.1))
		_outline(c, Color(1, 1, 1, 0.3), 2.0)
	if range_center != Hex.NONE:
		for c in Hex.within(range_center, range_radius):
			_fill(c, hexagon, Color(1, 0.45, 0.35, 0.08))
	for c in targets:
		_fill(c, hexagon, Color(1, 0.2, 0.15, 0.28))
		_outline(c, Color(1, 0.3, 0.25, 0.95), 4.0)
	var citizen := Tex.icon("character")
	for c in worked:
		var p := Hex.to_pixel(c) + Vector2(-30, 26)
		draw_circle(p, 15, Color(0.1, 0.12, 0.15, 0.92))
		draw_arc(p, 15, 0, TAU, 32, Tex.YIELD_COLORS.food, 2.0, true)
		if citizen != null:
			draw_texture_rect(citizen, Rect2(p - Vector2(10, 10), Vector2(20, 20)), false)
	if hover != Hex.NONE:
		_outline(hover, Color(1, 1, 1, 0.8), 3.0)
	if selected != Hex.NONE:
		_outline(selected, Color(1, 0.85, 0.2, 1.0), 4.5)


func _fill(c: Vector2i, hexagon: PackedVector2Array, color: Color) -> void:
	var center := Hex.to_pixel(c)
	var pts := PackedVector2Array()
	for p in hexagon:
		pts.append(p + center)
	draw_colored_polygon(pts, color)


func _outline(c: Vector2i, color: Color, width: float) -> void:
	var pts := Hex.corners(Hex.to_pixel(c), 0.94)
	pts.append(pts[0])
	draw_polyline(pts, color, width, true)
