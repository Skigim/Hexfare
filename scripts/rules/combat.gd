class_name Combat
extends RefCounted
## Civ VI-style combat math. Damage = base * e^((attack - defense) / scale) * random.
## Strengths are built from additive modifiers so the UI can show a breakdown.


## Everything needed to show or resolve an attack by `attacker` on `target`.
## Returns {} if there is nothing to attack there.
## Keys: attacker_kind ("unit"/"city"), defender_kind ("unit"/"city"), ranged (bool),
## attack (int), defense (int), attack_mods/defense_mods ([[label, value]]),
## damage_to_defender / damage_to_attacker (expected, before randomness),
## defender_unit_id / defender_city_id.
static func preview(state: GameState, attacker: Unit, target: Vector2i) -> Dictionary:
	var city := state.city_at(target)
	var defender := state.military_at(target)
	if city != null and city.owner == attacker.owner:
		return {}
	if city == null and (defender == null or defender.owner == attacker.owner):
		return {}
	var ranged := attacker.is_ranged()
	var attack_mods: Array = []
	var base: int = attacker.def().get("ranged_strength", 0) if ranged else attacker.def().get("strength", 0)
	attack_mods.append(["Base", base])
	_add_wounded(attack_mods, attacker.hp)
	var bonus_vs: Dictionary = attacker.def().get("bonus_vs", {})
	var result := {"attacker_kind": "unit", "ranged": ranged, "attacker_unit_id": attacker.id}
	if city != null:
		if bonus_vs.has("city"):
			attack_mods.append(["vs. City", int(bonus_vs.city)])
		result.defender_kind = "city"
		result.defender_city_id = city.id
		result.defense_mods = city_defense_mods(state, city)
	else:
		var cls: String = defender.def().get("class", "")
		if bonus_vs.has(cls):
			attack_mods.append(["vs. %s" % cls.capitalize(), int(bonus_vs[cls])])
		result.defender_kind = "unit"
		result.defender_unit_id = defender.id
		result.defense_mods = unit_defense_mods(state, defender, attacker)
	result.attack_mods = attack_mods
	return _finish(result)


## City bombarding a unit.
static func preview_city_attack(state: GameState, city: City, target: Vector2i) -> Dictionary:
	var defender := state.military_at(target)
	if defender == null or defender.owner == city.owner:
		return {}
	var result := {
		"attacker_kind": "city", "attacker_city_id": city.id, "ranged": true,
		"defender_kind": "unit", "defender_unit_id": defender.id,
		"attack_mods": city_defense_mods(state, city),
		"defense_mods": unit_defense_mods(state, defender, null),
	}
	return _finish(result)


static func unit_defense_mods(state: GameState, defender: Unit, attacker: Unit) -> Array:
	var mods: Array = [["Base", int(defender.def().get("strength", 0))]]
	_add_wounded(mods, defender.hp)
	var t := state.tile(defender.coord)
	var terrain := t.defense_bonus()
	if terrain != 0:
		mods.append(["Terrain", terrain])
	if defender.fortified:
		mods.append(["Fortified", int(Defs.rules.combat.fortify_bonus)])
	if attacker != null:
		var bonus_vs: Dictionary = defender.def().get("bonus_vs", {})
		var cls: String = attacker.def().get("class", "")
		if bonus_vs.has(cls):
			mods.append(["vs. %s" % cls.capitalize(), int(bonus_vs[cls])])
	return mods


static func city_defense_mods(state: GameState, city: City) -> Array:
	var r: Dictionary = Defs.rules.city
	var mods: Array = [["City", int(r.base_strength)]]
	mods.append(["Population", int(r.strength_per_pop) * city.population])
	for b in city.buildings:
		var d := int(Defs.buildings[b].get("defense", 0))
		if d != 0:
			mods.append([Defs.buildings[b].name, d])
	var garrison := state.military_at(city.coord)
	if garrison != null and garrison.owner == city.owner:
		var g := int(garrison.def().get("strength", 0) * float(r.garrison_strength_ratio))
		if g > 0:
			mods.append(["Garrison", g])
	return mods


static func city_strength(state: GameState, city: City) -> int:
	return sum_mods(city_defense_mods(state, city))


static func city_max_hp(city: City) -> int:
	var hp: int = Defs.rules.city.base_hp
	for b in city.buildings:
		hp += int(Defs.buildings[b].get("hp", 0))
	return hp


static func sum_mods(mods: Array) -> int:
	var total := 0
	for m in mods:
		total += int(m[1])
	return maxi(1, total)


## Expected damage (no randomness) dealt by strength `a` against strength `d`.
static func expected_damage(a: int, d: int) -> int:
	var c: Dictionary = Defs.rules.combat
	return int(round(c.base_damage * exp(float(a - d) / c.strength_scale)))


## Rolls the actual damage for a preview using the game's RNG.
static func roll(state: GameState, info: Dictionary) -> Dictionary:
	var c: Dictionary = Defs.rules.combat
	var to_def := _rolled(state, info.attack, info.defense, c)
	var to_att := 0
	if not info.ranged:
		to_att = _rolled(state, info.defense, info.attack, c)
	return {"to_defender": to_def, "to_attacker": to_att}


static func _rolled(state: GameState, a: int, d: int, c: Dictionary) -> int:
	var mult := state.rng.randf_range(c.random_min, c.random_max)
	return clampi(int(round(c.base_damage * exp(float(a - d) / c.strength_scale) * mult)), 1, 100)


static func _finish(result: Dictionary) -> Dictionary:
	result.attack = sum_mods(result.attack_mods)
	result.defense = sum_mods(result.defense_mods)
	result.damage_to_defender = mini(100, expected_damage(result.attack, result.defense))
	result.damage_to_attacker = 0 if result.ranged else mini(100, expected_damage(result.defense, result.attack))
	return result


static func _add_wounded(mods: Array, hp: int) -> void:
	var per: int = Defs.rules.combat.wounded_penalty_per_10hp
	var penalty := ((int(Defs.rules.units.max_hp) - hp) / 10) * per
	if penalty > 0:
		mods.append(["Wounded", -penalty])
