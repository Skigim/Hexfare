class_name Yields
extends RefCounted
## Yield bookkeeping: food, production, gold, science, culture.

const TYPES: Array[String] = ["food", "production", "gold", "science", "culture"]


static func empty() -> Dictionary:
	return {"food": 0, "production": 0, "gold": 0, "science": 0, "culture": 0}


static func add(into: Dictionary, other: Dictionary) -> void:
	for k in other:
		into[k] = into.get(k, 0) + other[k]


## Whether `player` can see/use `resource_id` (null player = only always-visible ones).
static func resource_visible(resource_id: String, player: Player) -> bool:
	var tech: String = Defs.resources[resource_id].get("reveal_tech", "")
	if tech == "":
		return true
	return player != null and player.has_tech(tech)


## What a tile yields when worked by `player`'s city.
static func tile_yields(tile: Tile, player: Player) -> Dictionary:
	var y := empty()
	if not tile.is_workable():
		return y
	add(y, Defs.terrains[tile.terrain].get("yields", {}))
	add(y, Defs.elevations[tile.elevation].get("yields", {}))
	if tile.feature != "":
		add(y, Defs.features[tile.feature].get("yields", {}))
	if tile.resource != "" and resource_visible(tile.resource, player):
		add(y, Defs.resources[tile.resource].get("yields", {}))
	if player != null:
		for tech_id in player.techs:
			for bonus in Defs.techs[tech_id].get("tile_bonuses", []):
				if _bonus_applies(bonus, tile):
					add(y, bonus.get("yields", {}))
	return y


static func _bonus_applies(bonus: Dictionary, tile: Tile) -> bool:
	if bonus.has("terrain") and bonus.terrain != tile.terrain:
		return false
	if bonus.has("elevation") and bonus.elevation != tile.elevation:
		return false
	if bonus.has("feature") and bonus.feature != tile.feature:
		return false
	if bonus.has("resource") and bonus.resource != tile.resource:
		return false
	return true


## Short text like "2F 1P 1G".
static func short_text(y: Dictionary) -> String:
	var parts := PackedStringArray()
	var letters := {"food": "F", "production": "P", "gold": "G", "science": "S", "culture": "C"}
	for k in TYPES:
		if int(y.get(k, 0)) != 0:
			parts.append("%d%s" % [int(y[k]), letters[k]])
	return " ".join(parts) if not parts.is_empty() else "-"
