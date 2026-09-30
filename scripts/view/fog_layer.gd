class_name FogLayer
extends Node2D
## Fog of war: unexplored tiles are hidden; explored-but-unseen tiles are dimmed.

const UNEXPLORED := Color(0.06, 0.07, 0.09, 1.0)
const DIMMED := Color(0.02, 0.03, 0.05, 0.5)

var state: GameState
var viewer: Player
var reveal_all := false


func _draw() -> void:
	if state == null or viewer == null or reveal_all:
		return
	var hexagon := Hex.corners(Vector2.ZERO, 1.025)
	for i in state.map.size():
		var seen := i < viewer.visible.size() and viewer.visible[i] == 1
		if seen:
			continue
		var explored := i < viewer.explored.size() and viewer.explored[i] == 1
		var center := Hex.to_pixel(state.map.tiles[i].coord)
		var pts := PackedVector2Array()
		for p in hexagon:
			pts.append(p + center)
		draw_colored_polygon(pts, DIMMED if explored else UNEXPLORED)
