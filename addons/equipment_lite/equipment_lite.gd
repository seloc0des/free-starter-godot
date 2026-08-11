class_name EquipmentLite
extends Node

# Fixed 4-slot equipment: weapon_main, chest, boots, ring. Equip an item by
# slot id; the previous occupant (if any) is returned. No two-handed
# conflicts, no modifier aggregation — just slot bookkeeping.
#
# Items must declare their target slot via `metadata.equip_slot`. The Lite
# tier doesn't enforce categories — any item can go in any matching-name
# slot; if you need stricter rules, that lives in the Pro tier.
#
# Cut from Pro:
#   * Customizable EquipmentLayout (any slot ids, categories per slot)
#   * Two-handed conflicts
#   * Modifier aggregation (`get_modifier_sum`, `apply_modifiers`)
#   * Paper-doll UI Control + drag-drop slot widgets
#   * Save-contract auto-join
#   * Inventory addon bridge (auto-return on unequip)

signal item_equipped(slot_id: String, item: Resource)
signal item_unequipped(slot_id: String, item: Resource)
signal contents_changed

const SLOTS: Array = ["weapon_main", "chest", "boots", "ring"]

var _equipped: Dictionary = {}  # slot_id -> Resource


func equip(slot_id: String, item: Resource) -> Resource:
	# Returns whatever was previously equipped (null if empty / failed).
	if not SLOTS.has(slot_id):
		return null
	if item == null:
		return unequip(slot_id)
	var prev: Resource = _equipped.get(slot_id, null)
	_equipped[slot_id] = item
	if prev != null:
		item_unequipped.emit(slot_id, prev)
	item_equipped.emit(slot_id, item)
	contents_changed.emit()
	return prev


## Auto-detect the slot from `metadata.equip_slot`. Returns the slot used,
## or "" if the item doesn't declare one or the slot doesn't exist.
func try_equip(item: Resource) -> String:
	if item == null:
		return ""
	# Duck-typed: tolerate items that don't carry a `metadata` Dictionary
	# (a third-party Resource with the same id/name fields).
	var md: Variant = item.get("metadata")
	if not (md is Dictionary):
		return ""
	var slot_id := String(md.get("equip_slot", ""))
	if slot_id == "" or not SLOTS.has(slot_id):
		return ""
	equip(slot_id, item)
	return slot_id


func unequip(slot_id: String) -> Resource:
	if not _equipped.has(slot_id):
		return null
	var prev: Resource = _equipped[slot_id]
	_equipped.erase(slot_id)
	item_unequipped.emit(slot_id, prev)
	contents_changed.emit()
	return prev


func get_equipped(slot_id: String) -> Resource:
	return _equipped.get(slot_id, null)


func is_equipped(slot_id: String) -> bool:
	return _equipped.has(slot_id)


func all_equipped() -> Dictionary:
	return _equipped.duplicate()


func clear() -> void:
	_equipped.clear()
	contents_changed.emit()
