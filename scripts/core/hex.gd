class_name Hex
extends RefCounted
## Axial hex-coordinate helpers for a pointy-top layout matching Kenney's
## 120x140 px hex tiles. Coordinates are Vector2i(q, r).

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]
## Sentinel for "no coordinate".
const NONE := Vector2i(-99999, -99999)

const TILE_WIDTH := 120.0
const TILE_HEIGHT := 140.0
const ROW_HEIGHT := 105.0
const RADIUS_X := 69.282032  # TILE_WIDTH / sqrt(3)
const RADIUS_Y := 70.0


static func neighbors(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRECTIONS:
		out.append(c + d)
	return out


static func distance(a: Vector2i, b: Vector2i) -> int:
	var d := a - b
	return (absi(d.x) + absi(d.y) + absi(d.x + d.y)) >> 1


## All coordinates within `radius` of `c` (including `c`).
static func within(c: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dq in range(-radius, radius + 1):
		for dr in range(maxi(-radius, -dq - radius), mini(radius, -dq + radius) + 1):
			out.append(c + Vector2i(dq, dr))
	return out


## Coordinates exactly `radius` away from `c`.
static func ring(c: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if radius <= 0:
		out.append(c)
		return out
	var cur := c + DIRECTIONS[4] * radius
	for side in 6:
		for _step in radius:
			out.append(cur)
			cur += DIRECTIONS[side]
	return out


## Center of the hex in world pixels.
static func to_pixel(c: Vector2i) -> Vector2:
	return Vector2(TILE_WIDTH * (c.x + c.y * 0.5), ROW_HEIGHT * c.y)


static func from_pixel(p: Vector2) -> Vector2i:
	var fr := p.y / ROW_HEIGHT
	var fq := p.x / TILE_WIDTH - fr * 0.5
	return _cube_round(fq, fr)


static func _cube_round(fq: float, fr: float) -> Vector2i:
	var fs := -fq - fr
	var q := roundf(fq)
	var r := roundf(fr)
	var s := roundf(fs)
	var dq := absf(q - fq)
	var dr := absf(r - fr)
	var ds := absf(s - fs)
	if dq > dr and dq > ds:
		q = -r - s
	elif dr > ds:
		r = -q - s
	return Vector2i(int(q), int(r))


## Hex outline around `center`. Corner 0 is upper-right, going clockwise.
static func corners(center: Vector2 = Vector2.ZERO, scale: float = 1.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * i - 30.0)
		pts.append(center + Vector2(RADIUS_X * cos(a), RADIUS_Y * sin(a)) * scale)
	return pts


## Indices of the two corners bounding the edge shared with the neighbour in direction `dir`.
static func edge_corners(dir: int) -> Vector2i:
	return Vector2i((6 - dir) % 6, (7 - dir) % 6)


## Rectangular maps are stored in "odd-r" offset coordinates (odd rows shifted right).
static func offset_to_axial(col: int, row: int) -> Vector2i:
	return Vector2i(col - ((row - (row & 1)) >> 1), row)


static func axial_to_offset(c: Vector2i) -> Vector2i:
	return Vector2i(c.x + ((c.y - (c.y & 1)) >> 1), c.y)
