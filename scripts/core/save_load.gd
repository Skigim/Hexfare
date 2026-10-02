class_name SaveLoad
extends RefCounted
## JSON save games in user://saves.

const SAVE_DIR := "user://saves/"
const QUICKSAVE := "user://saves/quicksave.json"


static func save(game: Game, path: String = QUICKSAVE) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var data := {"state": game.state.to_dict(), "log": _log_to_json(game.log_entries)}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("SaveLoad: cannot write %s" % path)
		return false
	f.store_string(JSON.stringify(data))
	return true


static func exists(path: String = QUICKSAVE) -> bool:
	return FileAccess.file_exists(path)


## Returns null if the file is missing or invalid.
static func load_game(path: String = QUICKSAVE) -> Game:
	Defs.ensure_loaded()
	if not FileAccess.file_exists(path):
		return null
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or not data.has("state"):
		push_error("SaveLoad: %s is not a valid save" % path)
		return null
	var game := Game.new()
	game.state = GameState.from_dict(data.state)
	if game.state == null:
		return null
	for e in data.get("log", []):
		game.log_entries.append({
			"turn": int(e.turn), "player": int(e.player), "text": e.text,
			"coord": Vector2i(int(e.coord[0]), int(e.coord[1])),
		})
	for p in game.state.players:
		Visibility.update(game.state, p)
	return game


static func _log_to_json(entries: Array) -> Array:
	var out: Array = []
	for e in entries.slice(-100):
		out.append({"turn": e.turn, "player": e.player, "text": e.text, "coord": [e.coord.x, e.coord.y]})
	return out
