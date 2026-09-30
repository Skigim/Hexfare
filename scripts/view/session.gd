class_name Session
extends RefCounted
## Hand-off between the main menu and the game scene.

## Settings for Game.new_game(); empty = defaults.
static var settings: Dictionary = {}
## If set, the game scene loads this save instead of starting a new game.
static var load_path: String = ""


static func default_settings() -> Dictionary:
	Defs.ensure_loaded()
	var size: Dictionary = Defs.rules.map.sizes.medium
	return {
		"width": size.width, "height": size.height, "players": size.players,
		"seed": randi() % 1000000, "human": true, "size": "medium",
	}
