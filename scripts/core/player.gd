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
var orders: Array = []                  # planned orders (see Orders); resolved when the turn resolves
var ready := false                      # has submitted its orders for this turn

var _order_index: Dictionary = {}       # Orders.key -> order; derived, never saved


# --- Orders ----------------------------------------------------------------

func order_for(kind: String, id: int, slot: String) -> Dictionary:
	return _order_index.get(Orders.key_of(kind, id, slot), {})


## The unit's "act" order, or {} when idle.
func unit_order(unit_id: int) -> Dictionary:
	return order_for(Orders.KIND_UNIT, unit_id, Orders.SLOT_ACT)


## Stores `o`, replacing any order with the same actor and slot.
func set_order(o: Dictionary) -> void:
	var k := Orders.key(o)
	if _order_index.has(k):
		orders[orders.find(_order_index[k])] = o
	else:
		orders.append(o)
	_order_index[k] = o


func remove_order(kind: String, id: int, slot: String) -> bool:
	var k := Orders.key_of(kind, id, slot)
	if not _order_index.has(k):
		return false
	orders.erase(_order_index[k])
	_order_index.erase(k)
	return true


func clear_orders() -> void:
	orders.clear()
	_order_index.clear()


## Orders in resolution order (never rely on insertion order).
func sorted_orders() -> Array:
	var out := orders.duplicate()
	out.sort_custom(Orders.less)
	return out


func rebuild_order_index() -> void:
	_order_index.clear()
	for o in orders:
		_order_index[Orders.key(o)] = o


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
		"orders": sorted_orders(), "ready": ready,
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
	p.orders = Defs.normalize(d.get("orders", []))
	p.ready = d.get("ready", false)
	p.rebuild_order_index()
	return p
