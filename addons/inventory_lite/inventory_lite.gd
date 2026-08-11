class_name InventoryLite
extends Node

# Single-container inventory. Stacks items by id, respects max_stack, fixed
# capacity in number of *slots* (not weight). No categories enforcement, no
# themes, no UI — wire your own list view to the signals below.
#
# This is the **working core** of the selodev Inventory addon. Features
# cut from the paid Pro tier:
#
#   * Weight limits + category gating
#   * InventoryTheme + drop-in grid UI
#   * Drag-and-drop item slots
#   * HotbarUI
#   * Per-item tooltips
#   * Save-contract opt-in
#   * Shared Events bus for cross-system integration
#
# See docs/upgrade.md.

signal contents_changed
signal item_added(item: Resource, amount: int)
signal item_removed(item: Resource, amount: int)
signal slot_full(item: Resource)  # add returned non-zero leftover

@export var capacity: int = 16  # slot count

var _slots: Array = []  # Array of {item, count}


func add_item(item: Resource, amount: int = 1) -> int:
	# Returns leftover that didn't fit.
	if item == null or amount <= 0:
		return amount
	var max_stack: int = max(1, int(item.max_stack)) if "max_stack" in item else 99
	var remaining := amount
	# Top up existing stacks of the same item.
	for s in _slots:
		if remaining <= 0:
			break
		if s.item == null or String(s.item.id) != String(item.id):
			continue
		var space: int = max_stack - int(s.count)
		if space <= 0:
			continue
		var take: int = min(space, remaining)
		s.count += take
		remaining -= take
	# Open new slots while capacity remains.
	while remaining > 0 and _slots.size() < capacity:
		var take: int = min(max_stack, remaining)
		_slots.append({"item": item, "count": take})
		remaining -= take
	if remaining < amount:
		item_added.emit(item, amount - remaining)
		contents_changed.emit()
	if remaining > 0:
		slot_full.emit(item)
	return remaining


func remove_item(item: Resource, amount: int = 1) -> int:
	# Returns the number actually removed.
	if item == null or amount <= 0:
		return 0
	var removed := 0
	var i := _slots.size() - 1
	while i >= 0 and removed < amount:
		var s = _slots[i]
		if s.item != null and String(s.item.id) == String(item.id):
			var take: int = min(int(s.count), amount - removed)
			s.count -= take
			removed += take
			if int(s.count) <= 0:
				_slots.remove_at(i)
		i -= 1
	if removed > 0:
		item_removed.emit(item, removed)
		contents_changed.emit()
	return removed


func count_item(item: Resource) -> int:
	if item == null:
		return 0
	var total := 0
	for s in _slots:
		if s.item != null and String(s.item.id) == String(item.id):
			total += int(s.count)
	return total


func has_item(item: Resource, amount: int = 1) -> bool:
	return count_item(item) >= amount


func clear() -> void:
	_slots.clear()
	contents_changed.emit()


## Snapshot for custom save systems. Each entry is {item_path, count}.
func snapshot() -> Array:
	var out: Array = []
	for s in _slots:
		if s.item == null:
			continue
		out.append({"item_path": String(s.item.resource_path), "count": int(s.count)})
	return out


func restore(data: Array) -> void:
	_slots.clear()
	for entry in data:
		if not (entry is Dictionary):
			continue
		var path := String(entry.get("item_path", ""))
		if path == "" or not ResourceLoader.exists(path):
			continue
		var item: Resource = load(path)
		if item != null:
			_slots.append({"item": item, "count": int(entry.get("count", 1))})
	contents_changed.emit()


## List view: returns Array of {item, count} dictionaries in slot order.
func slots() -> Array:
	return _slots.duplicate(true)


func slot_count() -> int:
	return _slots.size()
