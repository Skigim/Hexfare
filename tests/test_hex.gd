extends TestCase


func test_distance_and_neighbors() -> void:
	var c := Vector2i(3, -2)
	for n in Hex.neighbors(c):
		assert_eq(Hex.distance(c, n), 1)
	assert_eq(Hex.distance(Vector2i(0, 0), Vector2i(3, -3)), 3)
	assert_eq(Hex.distance(Vector2i(0, 0), Vector2i(-2, 5)), 5)


func test_within_and_ring_sizes() -> void:
	assert_eq(Hex.within(Vector2i.ZERO, 1).size(), 7)
	assert_eq(Hex.within(Vector2i.ZERO, 2).size(), 19)
	assert_eq(Hex.within(Vector2i.ZERO, 3).size(), 37)
	assert_eq(Hex.ring(Vector2i.ZERO, 2).size(), 12)
	for c in Hex.ring(Vector2i(1, 1), 3):
		assert_eq(Hex.distance(Vector2i(1, 1), c), 3)


func test_pixel_round_trip() -> void:
	for q in range(-6, 7):
		for r in range(-6, 7):
			var c := Vector2i(q, r)
			assert_eq(Hex.from_pixel(Hex.to_pixel(c)), c)
			# Points well inside the hex map back to it too.
			assert_eq(Hex.from_pixel(Hex.to_pixel(c) + Vector2(25, -20)), c)


func test_offset_round_trip() -> void:
	for row in 8:
		for col in 8:
			var a := Hex.offset_to_axial(col, row)
			assert_eq(Hex.axial_to_offset(a), Vector2i(col, row))
	# Odd rows are shifted half a tile to the right.
	assert_eq(Hex.to_pixel(Hex.offset_to_axial(0, 1)).x, 60.0)
	assert_eq(Hex.to_pixel(Hex.offset_to_axial(2, 2)).x, 240.0)


func test_edge_corners_face_neighbor() -> void:
	var pts := Hex.corners()
	for dir in 6:
		var e := Hex.edge_corners(dir)
		var mid := (pts[e.x] + pts[e.y]) * 0.5
		var toward := Hex.to_pixel(Hex.DIRECTIONS[dir])
		assert_true(mid.normalized().dot(toward.normalized()) > 0.99, "dir %d" % dir)


func test_min_heap_orders() -> void:
	var h := MinHeap.new()
	for v in [5, 3, 9, 1, 7, 2, 8]:
		h.push(v, v)
	var out: Array = []
	while not h.is_empty():
		out.append(h.pop())
	assert_eq(out, [1, 2, 3, 5, 7, 8, 9])
