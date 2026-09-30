class_name Player
extends RefCounted
## A civilization: treasury, research, and what it has seen of the map.

var id: int = 0
var name: String = ""
var color: Color = Color.WHITE
var civ_index: int = 0
var is_human: bool = false
var alive: bool = true
var gold: int = 0
var techs: Dictionary = {}              # tech id -> true
var research: String = ""               # tech currently being researched
var research_queue: Array = []          # techs to research after the current one
var research_progress: Dictionary = {}  # tech id -> accumulated science
var science_overflow: int = 0
var city_name_index: int = 0
var explored := PackedByteArray()       # per tile: 1 once seen
var visible := PackedByteArray()        # per tile: 1 while currently in sight


func has_tech(tech_id: String) -> bool:
	return tech_id == "" or techs.has(tech_id)


func civ() -> Dictionary:
	return Defs.civs[civ_index % Defs.civs.size()]


func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "color": color.to_html(false), "civ_index": civ_index,
		"is_human": is_human, "alive": alive, "gold": gold, "techs": techs.keys(),
		"research": research, "research_queue": research_queue,
		"research_progress": research_progress, "science_overflow": science_overflow,
		"city_name_index": city_name_index,
		"explored": Marshalls.raw_to_base64(explored),
	}


static func from_dict(d: Dictionary) -> Player:
	var p := Player.new()
	p.id = int(d.id)
	p.name = d.name
	p.color = Color.html(d.color)
	p.civ_index = int(d.civ_index)
	p.is_human = d.is_human
	p.alive = d.alive
	p.gold = int(d.gold)
	for t in d.techs:
		p.techs[t] = true
	p.research = d.research
	p.research_queue = d.research_queue.duplicate()
	for t in d.research_progress:
		p.research_progress[t] = int(d.research_progress[t])
	p.science_overflow = int(d.science_overflow)
	p.city_name_index = int(d.city_name_index)
	p.explored = Marshalls.base64_to_raw(d.explored)
	p.visible.resize(p.explored.size())
	return p
