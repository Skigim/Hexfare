class_name BorderLayer
extends Node2D
## Civilization borders: a light tint over owned tiles plus a colored edge line.

var state: GameState
var viewer: Player
var reveal_all := false


func _draw() -> void:
	if state == null:
		return
	var inset := Hex.corners(Vector2.ZERO, 0.93)
	var full := Hex.corners(Vector2.ZERO, 1.0)
	for i in state.map.size():
		var t := state.map.tiles[i]
		if t.owner < 0 or not _seen(i):
			continue
		var color := state.players[t.owner].color
		var center := Hex.to_pixel(t.coord)
		var fill := PackedVector2Array()
		for p in full:
			fill.append(p + center)
		draw_colored_polygon(fill, Color(color, 0.13))
		for dir in 6:
			var n := state.map.get_tile(t.coord + Hex.DIRECTIONS[dir])
			if n != null and n.owner == t.owner:
				continue
			var e := Hex.edge_corners(dir)
			var a := inset[e.x] + center
			var b := inset[e.y] + center
			draw_line(a, b, Color(0, 0, 0, 0.35), 7.0, true)
			draw_line(a, b, color.lightened(0.15), 4.0, true)


func _seen(i: int) -> bool:
	return reveal_all or viewer == null or (i < viewer.explored.size() and viewer.explored[i] == 1)
