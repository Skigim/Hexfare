class_name ResourceLayer
extends Node2D
## Small badges showing map resources the viewer knows about.

var state: GameState
var viewer: Player
var show_grid := false


func _draw() -> void:
	if state == null:
		return
	if show_grid:
		var outline := Hex.corners()
		outline.append(outline[0])
		for t in state.map.tiles:
			var center := Hex.to_pixel(t.coord)
			var pts := PackedVector2Array()
			for p in outline:
				pts.append(p + center)
			draw_polyline(pts, Color(0, 0, 0, 0.18), 1.5, true)
	for t in state.map.tiles:
		if t.resource == "" or not Yields.resource_visible(t.resource, viewer):
			continue
		var res: Dictionary = Defs.resources[t.resource]
		var pos := Hex.to_pixel(t.coord) + Vector2(30, 26)
		var tint: Color = Tex.RESOURCE_COLORS.get(res.get("category", "bonus"), Color.WHITE)
		draw_circle(pos + Vector2(1, 2), 16, Color(0, 0, 0, 0.3))
		draw_circle(pos, 16, Color(0.1, 0.12, 0.15, 0.92))
		draw_arc(pos, 16, 0, TAU, 32, tint, 2.0, true)
		var icon := Tex.icon(res.icon)
		if icon != null:
			draw_texture_rect(icon, Rect2(pos - Vector2(11, 11), Vector2(22, 22)), false, tint)
