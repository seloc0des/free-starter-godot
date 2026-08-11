extends Node

# Tiny duck-typed inventory bag shipped with this addon's demo. Mirrors the
# methods CraftingLite needs (has_item / remove_item / add_item / count_item).
# Your project will use Inventory — Lite or your own bag instead; this is
# here purely so the demo runs standalone.

signal contents_changed

var _slots: Array = []  # Array of {item, count}


func add_item(item: Resource, amount: int = 1) -> int:
	if item == null or amount <= 0:
		return amount
	for s in _slots:
		if String(s.item.id) == String(item.id):
			s.count += amount
			contents_changed.emit()
			return 0
	_slots.append({"item": item, "count": amount})
	contents_changed.emit()
	return 0


func remove_item(item: Resource, amount: int = 1) -> int:
	if item == null or amount <= 0:
		return 0
	for i in range(_slots.size()):
		var s = _slots[i]
		if String(s.item.id) == String(item.id):
			var take: int = min(int(s.count), amount)
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


func snapshot() -> Array:
	return _slots.duplicate(true)
