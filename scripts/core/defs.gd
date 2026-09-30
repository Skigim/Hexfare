class_name Defs
extends RefCounted
## Static access to the JSON game data in res://data. Call ensure_loaded() once at startup.
## Every definition dictionary gets an "id" field equal to its key.

const DATA_DIR := "res://data/"

static var terrains: Dictionary = {}
static var elevations: Dictionary = {}
static var features: Dictionary = {}
static var resources: Dictionary = {}
static var units: Dictionary = {}
static var buildings: Dictionary = {}
static var techs: Dictionary = {}
static var civs: Array = []
static var rules: Dictionary = {}
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	var terrain: Dictionary = _load_json("terrain.json")
	terrains = _with_ids(terrain.get("terrains", {}))
	elevations = _with_ids(terrain.get("elevations", {}))
	features = _with_ids(terrain.get("features", {}))
	resources = _with_ids(_load_json("resources.json"))
	units = _with_ids(_load_json("units.json"))
	buildings = _with_ids(_load_json("buildings.json"))
	techs = _with_ids(_load_json("techs.json"))
	civs = _load_json("civs.json")
	rules = _load_json("rules.json")
	_loaded = true


## Forces a re-read of the data files (useful while tweaking balance).
static func reload() -> void:
	_loaded = false
	ensure_loaded()


## Returns a list of human-readable problems with cross references in the data.
static func validate() -> Array:
	ensure_loaded()
	var problems: Array = []
	for id in techs:
		for req in techs[id].get("requires", []):
			if not techs.has(req):
				problems.append("tech %s requires unknown tech %s" % [id, req])
	for table in [units, buildings]:
		for id in table:
			var tech: String = table[id].get("tech", "")
			if tech != "" and not techs.has(tech):
				problems.append("%s needs unknown tech %s" % [id, tech])
	for id in units:
		var res: String = units[id].get("requires_resource", "")
		if res != "" and not resources.has(res):
			problems.append("unit %s needs unknown resource %s" % [id, res])
	for id in resources:
		var tech: String = resources[id].get("reveal_tech", "")
		if tech != "" and not techs.has(tech):
			problems.append("resource %s revealed by unknown tech %s" % [id, tech])
		for t in resources[id].get("terrains", []):
			if not terrains.has(t):
				problems.append("resource %s placed on unknown terrain %s" % [id, t])
	return problems


static func _load_json(file: String) -> Variant:
	var path := DATA_DIR + file
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("Defs: could not read %s" % path)
		return {}
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("Defs: %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	return normalize(json.data)


## JSON numbers arrive as floats; turn whole numbers back into ints.
static func normalize(v: Variant) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			for k in v.keys():
				v[k] = normalize(v[k])
		TYPE_ARRAY:
			for i in v.size():
				v[i] = normalize(v[i])
		TYPE_FLOAT:
			if v == floorf(v):
				return int(v)
	return v


static func _with_ids(table: Dictionary) -> Dictionary:
	for id in table:
		table[id]["id"] = id
	return table
