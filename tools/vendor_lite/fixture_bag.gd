extends Node

# Test fixture: a bag that fills up, stacking by id like Inventory (Lite). The
# pack's _demo_bag never runs out of room, so it can't test a full bag.

signal contents_changed

@export var capacity := 16

var _slots: Array = []


func add_item(item: Resource, amount: int = 1) -> int:
	if item == null or amount <= 0:
		return amount
	for s in _slots:
		if String(s.item.id) == String(item.id):
			s.count += amount
			contents_changed.emit()
			return 0
	if _slots.size() >= capacity:
		return amount
	_slots.append({"item": item, "count": amount})
	contents_changed.emit()
	return 0


func remove_item(item: Resource, amount: int = 1) -> int:
	for i in range(_slots.size()):
		var s = _slots[i]
		if String(s.item.id) == String(item.id):
			var take: int = mini(int(s.count), amount)
			s.count -= take
			if s.count <= 0:
				_slots.remove_at(i)
			contents_changed.emit()
			return take
	return 0


func count_item(item: Resource) -> int:
	for s in _slots:
		if String(s.item.id) == String(item.id):
			return int(s.count)
	return 0


func has_item(item: Resource, amount: int = 1) -> bool:
	return count_item(item) >= amount


func slots() -> Array:
	return _slots.duplicate(true)
