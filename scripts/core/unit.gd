class_name Unit
extends RefCounted
## A unit on the map. Static stats live in Defs.units[type].

var id: int = 0
var type: String = ""
var owner: int = 0
var coord: Vector2i
var hp: int = 100
var moves_left: int = 0
var fortified := false
var sleeping := false
var skipped := false        # "skip turn" pressed; cleared at turn start
var acted := false          # moved or attacked this turn (blocks healing next turn)
var has_attacked := false
var has_destination := false
var destination := Vector2i.ZERO
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


func max_moves() -> int:
	return int(def().get("moves", 2))


func sight() -> int:
	return int(def().get("sight", 2))


func has_ability(ability: String) -> bool:
	return ability in def().get("abilities", [])


## True when the unit is idle and the player should give it an order this turn.
func needs_orders() -> bool:
	return moves_left > 0 and not fortified and not sleeping and not skipped and not has_destination


func to_dict() -> Dictionary:
	return {
		"id": id, "type": type, "owner": owner, "coord": [coord.x, coord.y], "hp": hp,
		"moves_left": moves_left, "fortified": fortified, "sleeping": sleeping, "skipped": skipped,
		"acted": acted, "has_attacked": has_attacked, "has_destination": has_destination,
		"destination": [destination.x, destination.y], "ai": ai,
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
	u.skipped = d.skipped
	u.acted = d.acted
	u.has_attacked = d.has_attacked
	u.has_destination = d.has_destination
	u.destination = Vector2i(int(d.destination[0]), int(d.destination[1]))
	u.ai = Defs.normalize(d.ai)
	return u
