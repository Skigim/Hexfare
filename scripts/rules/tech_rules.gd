class_name TechRules
extends RefCounted
## Research: availability, queued paths, progress, and what each tech unlocks.


static func can_research(player: Player, tech_id: String) -> bool:
	if player.techs.has(tech_id):
		return false
	for req in Defs.techs[tech_id].get("requires", []):
		if not player.techs.has(req):
			return false
	return true


static func available(player: Player) -> Array:
	var out: Array = []
	for id in Defs.techs:
		if can_research(player, id):
			out.append(id)
	return out


static func has_all(player: Player) -> bool:
	return player.techs.size() >= Defs.techs.size()


## Unresearched techs needed to reach `tech_id`, in a valid research order (ending with it).
static func path_to(player: Player, tech_id: String) -> Array:
	var out: Array = []
	_collect(player, tech_id, out)
	return out


static func _collect(player: Player, tech_id: String, out: Array) -> void:
	if player.techs.has(tech_id) or tech_id in out:
		return
	for req in Defs.techs[tech_id].get("requires", []):
		_collect(player, req, out)
	out.append(tech_id)


## Sets research to `tech_id`, queueing any missing prerequisites first.
static func set_research(player: Player, tech_id: String) -> bool:
	if not Defs.techs.has(tech_id) or player.techs.has(tech_id):
		return false
	var path := path_to(player, tech_id)
	player.research = path[0]
	player.research_queue = path.slice(1)
	if player.science_overflow > 0:
		player.research_progress[player.research] = int(player.research_progress.get(player.research, 0)) + player.science_overflow
		player.science_overflow = 0
	return true


static func progress(player: Player, tech_id: String) -> int:
	return int(player.research_progress.get(tech_id, 0))


static func turns_left(player: Player, tech_id: String, science_per_turn: int) -> int:
	if science_per_turn <= 0:
		return -1
	var remaining := int(Defs.techs[tech_id].cost) - progress(player, tech_id)
	return maxi(1, int(ceil(float(remaining) / science_per_turn)))


## Adds a turn's science; completes techs (possibly several) and advances the queue.
static func add_science(game: Game, player: Player, amount: int) -> void:
	if player.research == "":
		player.science_overflow += amount
		return
	player.research_progress[player.research] = progress(player, player.research) + amount
	while player.research != "" and not game.state.game_over:
		var tech := player.research
		var cost := int(Defs.techs[tech].cost)
		if progress(player, tech) < cost:
			return
		var extra := progress(player, tech) - cost
		player.research_progress.erase(tech)
		player.research = ""
		game.learn_tech(player, tech)
		while not player.research_queue.is_empty():
			var next: String = player.research_queue.pop_front()
			if can_research(player, next):
				player.research = next
				break
		if player.research == "":
			player.science_overflow += extra
		else:
			player.research_progress[player.research] = progress(player, player.research) + extra


## {"units": [...], "buildings": [...], "resources": [...], "bonuses": [text]}
static func unlocks(tech_id: String) -> Dictionary:
	var out := {"units": [], "buildings": [], "resources": [], "bonuses": []}
	for id in Defs.units:
		if Defs.units[id].get("tech", "") == tech_id:
			out.units.append(id)
	for id in Defs.buildings:
		if Defs.buildings[id].get("tech", "") == tech_id:
			out.buildings.append(id)
	for id in Defs.resources:
		if Defs.resources[id].get("reveal_tech", "") == tech_id:
			out.resources.append(id)
	for bonus in Defs.techs[tech_id].get("tile_bonuses", []):
		var where := PackedStringArray()
		for key in ["terrain", "elevation", "feature", "resource"]:
			if bonus.has(key):
				where.append(String(bonus[key]).capitalize())
		out.bonuses.append("+%s on %s" % [Yields.short_text(bonus.yields), " ".join(where)])
	return out
