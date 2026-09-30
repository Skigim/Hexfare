class_name MinHeap
extends RefCounted
## Binary min-heap of items keyed by a numeric priority.

var _prio: Array = []
var _items: Array = []


func is_empty() -> bool:
	return _prio.is_empty()


func size() -> int:
	return _prio.size()


func push(item: Variant, priority: float) -> void:
	_prio.append(priority)
	_items.append(item)
	var i := _prio.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if _prio[parent] <= _prio[i]:
			break
		_swap(i, parent)
		i = parent


func pop() -> Variant:
	var top: Variant = _items[0]
	var last := _prio.size() - 1
	_swap(0, last)
	_prio.pop_back()
	_items.pop_back()
	var n := _prio.size()
	var i := 0
	while true:
		var left := i * 2 + 1
		var right := left + 1
		var smallest := i
		if left < n and _prio[left] < _prio[smallest]:
			smallest = left
		if right < n and _prio[right] < _prio[smallest]:
			smallest = right
		if smallest == i:
			break
		_swap(i, smallest)
		i = smallest
	return top


func _swap(a: int, b: int) -> void:
	var p: Variant = _prio[a]
	_prio[a] = _prio[b]
	_prio[b] = p
	var it: Variant = _items[a]
	_items[a] = _items[b]
	_items[b] = it
