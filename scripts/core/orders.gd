class_name Orders
extends RefCounted
## Planned orders: the only way a player changes the world between turns.
##
## An order is a JSON-safe Dictionary
##   {"kind": "unit"|"city", "id": int, "slot": String, "type": String, ...fields}
## with coordinates stored as [x, y] arrays. A unit has one "act" slot; a city has one slot
## per order type. Orders are validated by Game.issue_order and carried out by TurnResolver.
##
##   unit:  move {to}, attack {at} (ranged units only), found_city {at}, fortify, sleep, disband
##   city:  bombard {at}, purchase {item_kind, item_id}
##
## There is no melee attack order: melee units fight whatever enemy they meet while moving.

const KIND_UNIT := "unit"
const KIND_CITY := "city"
const SLOT_ACT := "act"


# --- Constructors ------------------------------------------------------------

static func move(unit_id: int, to: Vector2i) -> Dictionary:
	return _unit(unit_id, "move", {"to": _arr(to)})


static func attack(unit_id: int, at: Vector2i) -> Dictionary:
	return _unit(unit_id, "attack", {"at": _arr(at)})


static func found_city(unit_id: int, at: Vector2i) -> Dictionary:
	return _unit(unit_id, "found_city", {"at": _arr(at)})


static func fortify(unit_id: int) -> Dictionary:
	return _unit(unit_id, "fortify")


static func sleep(unit_id: int) -> Dictionary:
	return _unit(unit_id, "sleep")


static func disband(unit_id: int) -> Dictionary:
	return _unit(unit_id, "disband")


static func bombard(city_id: int, at: Vector2i) -> Dictionary:
	return {"kind": KIND_CITY, "id": city_id, "slot": "bombard", "type": "bombard", "at": _arr(at)}


static func purchase(city_id: int, item_kind: String, item_id: String) -> Dictionary:
	return {
		"kind": KIND_CITY, "id": city_id, "slot": "purchase", "type": "purchase",
		"item_kind": item_kind, "item_id": item_id,
	}


static func _unit(unit_id: int, type: String, fields: Dictionary = {}) -> Dictionary:
	var o := {"kind": KIND_UNIT, "id": unit_id, "slot": SLOT_ACT, "type": type}
	o.merge(fields)
	return o


static func _arr(c: Vector2i) -> Array:
	return [c.x, c.y]


# --- Accessors ---------------------------------------------------------------

static func key(o: Dictionary) -> String:
	return "%s:%d:%s" % [o.kind, int(o.id), o.slot]


static func key_of(kind: String, id: int, slot: String) -> String:
	return "%s:%d:%s" % [kind, id, slot]


## Coordinate stored in `field`, or Hex.NONE if missing.
static func coord(o: Dictionary, field: String) -> Vector2i:
	var a: Variant = o.get(field)
	if a is Array and a.size() == 2:
		return Vector2i(int(a[0]), int(a[1]))
	return Hex.NONE


## Stable ordering for resolution and saving: unit orders before city orders, then id, then slot.
static func less(a: Dictionary, b: Dictionary) -> bool:
	var ra := 0 if a.kind == KIND_UNIT else 1
	var rb := 0 if b.kind == KIND_UNIT else 1
	if ra != rb:
		return ra < rb
	if int(a.id) != int(b.id):
		return int(a.id) < int(b.id)
	return String(a.slot) < String(b.slot)


## True for orders that keep running over several turns until they complete.
static func persists(o: Dictionary) -> bool:
	return o.kind == KIND_UNIT and (o.type == "move" or o.type == "found_city")


# --- Deterministic hashing ---------------------------------------------------

## Small integer mixer (no RNG state, same result on every platform). Returns 0..2^31-1.
static func mix(a: int, b: int, c: int = 0) -> int:
	var x := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	x = (x ^ (x >> 15)) * 2246822519
	x = (x ^ (x >> 13)) * 3266489917
	x = x ^ (x >> 16)
	return x & 0x7fffffff
