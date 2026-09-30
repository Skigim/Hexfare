class_name Visibility
extends RefCounted
## Fog of war: which tiles a player currently sees and has ever seen.


static func update(state: GameState, player: Player) -> void:
	var n := state.map.size()
	if player.explored.size() != n:
		player.explored.resize(n)
	player.visible.resize(n)
	player.visible.fill(0)
	for u in state.player_units(player.id):
		_reveal(state, player, u.coord, u.sight())
	var city_sight: int = Defs.rules.city.sight
	for city in state.player_cities(player.id):
		_reveal(state, player, city.coord, city_sight)
	for i in n:
		if state.map.tiles[i].owner == player.id:
			player.visible[i] = 1
			player.explored[i] = 1


static func is_visible(state: GameState, player: Player, c: Vector2i) -> bool:
	var i := state.map.index_of(c)
	return i >= 0 and i < player.visible.size() and player.visible[i] == 1


static func is_explored(state: GameState, player: Player, c: Vector2i) -> bool:
	var i := state.map.index_of(c)
	return i >= 0 and i < player.explored.size() and player.explored[i] == 1


static func reveal_all(state: GameState, player: Player) -> void:
	player.explored.resize(state.map.size())
	player.explored.fill(1)
	player.visible.resize(state.map.size())
	player.visible.fill(1)


static func _reveal(state: GameState, player: Player, center: Vector2i, radius: int) -> void:
	for c in Hex.within(center, radius):
		var i := state.map.index_of(c)
		if i >= 0:
			player.visible[i] = 1
			player.explored[i] = 1
