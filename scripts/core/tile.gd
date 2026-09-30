class_name Tile
extends RefCounted
## One map hex. Terrain/elevation/feature/resource are ids into Defs tables.

var coord: Vector2i
var terrain: String = "ocean"
var elevation: String = "flat"   # flat | hills | mountains
var feature: String = ""         # "" | forest
var resource: String = ""
var owner: int = -1              # player id owning this tile (borders)
var city_id: int = -1            # city whose borders contain this tile
var variant: int = 0             # stable random number used to pick art variants


func _init(c: Vector2i = Vector2i.ZERO) -> void:
	coord = c


func is_water() -> bool:
	return Defs.terrains[terrain].get("water", false)


func is_mountain() -> bool:
	return not Defs.elevations[elevation].get("passable", true)


## Land units may stand here.
func is_passable_land() -> bool:
	return not is_water() and not is_mountain()


func is_workable() -> bool:
	return Defs.elevations[elevation].get("workable", true)


func move_cost() -> int:
	var cost: int = Defs.terrains[terrain].get("move_cost", 1)
	cost += int(Defs.elevations[elevation].get("move_cost", 0))
	if feature != "":
		cost += int(Defs.features[feature].get("move_cost", 0))
	return cost


## Flat combat-strength bonus for units defending on this tile.
func defense_bonus() -> int:
	var bonus: int = Defs.elevations[elevation].get("defense", 0)
	if feature != "":
		bonus += int(Defs.features[feature].get("defense", 0))
	return bonus


func display_name() -> String:
	var parts := PackedStringArray([Defs.terrains[terrain].name])
	if elevation != "flat":
		parts.append(Defs.elevations[elevation].name)
	if feature != "":
		parts.append(Defs.features[feature].name)
	return ", ".join(parts)


func to_dict() -> Dictionary:
	return {"t": terrain, "e": elevation, "f": feature, "r": resource, "o": owner, "c": city_id, "v": variant}


func load_dict(d: Dictionary) -> void:
	terrain = d.t
	elevation = d.e
	feature = d.f
	resource = d.r
	owner = int(d.o)
	city_id = int(d.c)
	variant = int(d.v)
