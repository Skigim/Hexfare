class_name TerrainLayer
extends Node2D
## One Sprite2D per tile, chosen from the terrain "art" table in terrain.json.
## Art entries look like "stone_07" or "stone_07+rockGrey_large" (tile + overlay objects).

var _sprites: Dictionary = {}  # coord -> Sprite2D


func build(map: HexMap) -> void:
	for c in get_children():
		c.queue_free()
	_sprites.clear()
	for t in map.tiles:
		refresh_tile(t)


func refresh_tile(t: Tile) -> void:
	if _sprites.has(t.coord):
		_sprites[t.coord].queue_free()
	var art := _art_entry(t).split("+")
	var sprite := Sprite2D.new()
	sprite.texture = Tex.terrain(art[0])
	sprite.position = Hex.to_pixel(t.coord)
	var tint: String = Defs.terrains[t.terrain].get("tint", "")
	if tint != "":
		sprite.modulate = Color.html(tint)
	for i in range(1, art.size()):
		var obj := Sprite2D.new()
		obj.texture = Tex.object(art[i])
		obj.position = Vector2(-6 + 22 * (i - 1), -14 + 16 * (i - 1))
		sprite.add_child(obj)
	add_child(sprite)
	_sprites[t.coord] = sprite


static func _art_entry(t: Tile) -> String:
	var art: Dictionary = Defs.terrains[t.terrain].get("art", {})
	var key := "flat"
	if t.elevation == "mountains":
		key = "mountains"
	elif t.elevation == "hills":
		key = "hills_forest" if t.feature == "forest" else "hills"
	elif t.feature == "forest":
		key = "forest"
	if not art.has(key):
		key = "hills" if key == "hills_forest" and art.has("hills") else "flat"
	var options: Array = art.get(key, ["grass_05"])
	return options[t.variant % options.size()]
