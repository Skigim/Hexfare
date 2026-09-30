class_name HexMap
extends RefCounted
## Rectangular hex map (odd-r offset storage, axial addressing).

var width: int = 0
var height: int = 0
var tiles: Array[Tile] = []


func _init(w: int = 0, h: int = 0) -> void:
	width = w
	height = h
	tiles.resize(w * h)
	for row in h:
		for col in w:
			tiles[row * w + col] = Tile.new(Hex.offset_to_axial(col, row))


func size() -> int:
	return tiles.size()


func index_of(c: Vector2i) -> int:
	var o := Hex.axial_to_offset(c)
	if o.x < 0 or o.x >= width or o.y < 0 or o.y >= height:
		return -1
	return o.y * width + o.x


func in_bounds(c: Vector2i) -> bool:
	return index_of(c) >= 0


func get_tile(c: Vector2i) -> Tile:
	var i := index_of(c)
	if i < 0:
		return null
	return tiles[i]


func neighbors(c: Vector2i) -> Array[Tile]:
	var out: Array[Tile] = []
	for n in Hex.neighbors(c):
		var t := get_tile(n)
		if t != null:
			out.append(t)
	return out


func tiles_within(c: Vector2i, radius: int) -> Array[Tile]:
	var out: Array[Tile] = []
	for n in Hex.within(c, radius):
		var t := get_tile(n)
		if t != null:
			out.append(t)
	return out


## World-space rectangle covering the whole map.
func pixel_bounds() -> Rect2:
	var top_left := Hex.to_pixel(Hex.offset_to_axial(0, 0)) - Vector2(Hex.TILE_WIDTH, Hex.TILE_HEIGHT) * 0.5
	var size := Vector2(Hex.TILE_WIDTH * (width + 0.5), Hex.ROW_HEIGHT * (height - 1) + Hex.TILE_HEIGHT)
	return Rect2(top_left, size)


func to_dict() -> Dictionary:
	var arr: Array = []
	for t in tiles:
		arr.append(t.to_dict())
	return {"width": width, "height": height, "tiles": arr}


static func from_dict(d: Dictionary) -> HexMap:
	var m := HexMap.new(int(d.width), int(d.height))
	for i in m.tiles.size():
		m.tiles[i].load_dict(d.tiles[i])
	return m
