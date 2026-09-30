class_name City
extends RefCounted
## A city. Economy rules live in CityRules; this is just state.

var id: int = 0
var name: String = ""
var owner: int = 0
var original_owner: int = 0
var coord: Vector2i
var population: int = 1
var food: int = 0              # stored food towards next pop
var production: int = 0        # stored production towards current build
var culture: int = 0           # stored culture towards next border tile
var border_growths: int = 0    # tiles gained through culture so far
var build: Dictionary = {}     # {"kind": "unit"|"building", "id": String}, or empty
var buildings: Dictionary = {} # building id -> true
var worked: Array = []         # Vector2i coords of worked tiles (city center excluded)
var hp: int = 200
var has_attacked := false
var founded_turn: int = 0


func is_capital() -> bool:
	return buildings.has("palace")


func has_building(building_id: String) -> bool:
	return buildings.has(building_id)


func to_dict() -> Dictionary:
	var w: Array = []
	for c in worked:
		w.append([c.x, c.y])
	return {
		"id": id, "name": name, "owner": owner, "original_owner": original_owner,
		"coord": [coord.x, coord.y], "population": population, "food": food,
		"production": production, "culture": culture, "border_growths": border_growths,
		"build": build, "buildings": buildings.keys(), "worked": w, "hp": hp,
		"has_attacked": has_attacked, "founded_turn": founded_turn,
	}


static func from_dict(d: Dictionary) -> City:
	var c := City.new()
	c.id = int(d.id)
	c.name = d.name
	c.owner = int(d.owner)
	c.original_owner = int(d.original_owner)
	c.coord = Vector2i(int(d.coord[0]), int(d.coord[1]))
	c.population = int(d.population)
	c.food = int(d.food)
	c.production = int(d.production)
	c.culture = int(d.culture)
	c.border_growths = int(d.border_growths)
	c.build = d.build
	for b in d.buildings:
		c.buildings[b] = true
	for w in d.worked:
		c.worked.append(Vector2i(int(w[0]), int(w[1])))
	c.hp = int(d.hp)
	c.has_attacked = d.has_attacked
	c.founded_turn = int(d.founded_turn)
	return c
