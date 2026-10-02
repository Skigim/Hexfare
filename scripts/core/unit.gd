class_name Unit
extends RefCounted
## A unit on the map. Static stats live in Defs.units[type].

var id: int = 0
var type: String = ""
var owner: int = 0
var coord: Vector2i
var hp: int = 100
var moves_left: int = 0     # movement budget; spent while a turn resolves, refilled when it ends
var fortified := false
var sleeping := false
var acted := false          # moved or attacked this turn (blocks healing)
var priority: int = 0       # movement priority: higher acts first when orders resolve
var ai: Dictionary = {}     # scratch memory for the AI


func def() -> Dictionary:
	return Defs.units[type]


func display_name() -> String:
	return def().name


func is_civilian() -> bool:
	return def().get("class", "") == "civilian"


func is_military() -> bool:
	return not is_civilian()


func is_ranged() -> bool:
	return int(def().get("range", 0)) > 0


func attack_range() -> int:
	return int(def().get("range", 1 if is_military() else 0))


## Melee units can take cities; ranged/siege and civilians cannot.
func can_capture_cities() -> bool:
	return is_military() and not is_ranged()


## Melee military units fight any enemy they run into while moving.
func can_attack_on_contact() -> bool:
	return is_military() and not is_ranged()


func max_moves() -> int:
	return int(def().get("moves", 2))


func sight() -> int:
	return int(def().get("sight", 2))


func has_ability(ability: String) -> bool:
	return ability in def().get("abilities", [])


func to_dict() -> Dictionary:
	return {
		"id": id, "type": type, "owner": owner, "coord": [coord.x, coord.y], "hp": hp,
		"moves_left": moves_left, "fortified": fortified, "sleeping": sleeping,
		"acted": acted, "ai": ai, "priority": priority,
	}


static func from_dict(d: Dictionary) -> Unit:
	var u := Unit.new()
	u.id = int(d.id)
	u.type = d.type
	u.owner = int(d.owner)
	u.coord = Vector2i(int(d.coord[0]), int(d.coord[1]))
	u.hp = int(d.hp)
	u.moves_left = int(d.moves_left)
	u.fortified = d.fortified
	u.sleeping = d.sleeping
	u.acted = d.acted
	u.ai = Defs.normalize(d.ai)
	u.priority = int(d.get("priority", 0))
	return u
