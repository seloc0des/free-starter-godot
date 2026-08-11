extends Node

# Headless test for Equipment — Lite.
# Run: godot --headless --path . res://tools/equipment_lite/verify.tscn

const ItemLiteScript := preload("res://addons/equipment_lite/item_resource.gd")

var _passes := 0
var _failures := 0
var _log: Array = []  # [ [bool passed, String msg], ... ] — for the windowed report


func _ready() -> void:
	await get_tree().process_frame
	print("--- equipment lite verify ---")
	await _run_equip_returns_prior()
	await _run_try_equip_uses_metadata()
	await _run_try_equip_missing_metadata_safe()
	await _run_unequip_clears_slot()
	await _run_unknown_slot_rejected()
	await _run_signals_fire()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	# Headless (CI/build) keeps the exit-code behavior. In a window (editor F6) show a
	# visual PASS/FAIL banner instead — the load-and-look buyer QA scene.
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0 if _failures == 0 else 1)
	else:
		# untyped on purpose: `:=` on load().new() is a Variant → parse-hang; class_name
		# would need a project rescan to register. Plain dynamic dispatch dodges both.
		var report = load("res://tools/equipment_lite/acceptance_report.gd").new()
		get_tree().root.add_child(report)
		report.render(_passes, _failures, _log)


func _assert(cond: bool, msg: String) -> void:
	_log.append([cond, msg])
	if cond:
		_passes += 1
		print("PASS: " + msg)
	else:
		_failures += 1
		printerr("FAIL: " + msg)


# ---- helpers -------------------------------------------------------------

func _item(id: String, slot: String = "") -> Resource:
	var it: Resource = ItemLiteScript.new()
	it.id = id
	it.name = id.capitalize()
	if slot != "":
		it.metadata = {"equip_slot": slot}
	return it


func _make_eq() -> EquipmentLite:
	var eq := EquipmentLite.new()
	add_child(eq)
	return eq


# ---- tests ---------------------------------------------------------------

func _run_equip_returns_prior() -> void:
	await get_tree().process_frame
	var eq := _make_eq()
	var sword := _item("sword", "weapon_main")
	var axe := _item("axe", "weapon_main")
	var prior := eq.equip("weapon_main", sword)
	_assert(prior == null, "Equip: first equip returns null prior")
	prior = eq.equip("weapon_main", axe)
	_assert(prior == sword, "Equip: second equip returns prior sword")
	_assert(eq.get_equipped("weapon_main") == axe, "Equip: axe now occupies slot")
	eq.queue_free()


func _run_try_equip_uses_metadata() -> void:
	await get_tree().process_frame
	var eq := _make_eq()
	var boots := _item("boots", "boots")
	var slot := eq.try_equip(boots)
	_assert(slot == "boots", "TryEquip: routed to 'boots' (got '%s')" % slot)
	_assert(eq.get_equipped("boots") == boots, "TryEquip: boots in slot")
	eq.queue_free()


func _run_try_equip_missing_metadata_safe() -> void:
	await get_tree().process_frame
	# Regression: duck-typed item without a `metadata` Dictionary must not
	# crash try_equip. The lite addon was vulnerable before the fix.
	var eq := _make_eq()
	var bare := Resource.new()   # no metadata field at all
	var slot := eq.try_equip(bare)
	_assert(slot == "", "MetaSafe: missing metadata returns '' (no crash)")
	var also_safe := ItemLiteScript.new()  # has metadata={} by default
	also_safe.id = "x"
	slot = eq.try_equip(also_safe)
	_assert(slot == "", "MetaSafe: empty metadata returns ''")
	eq.queue_free()


func _run_unequip_clears_slot() -> void:
	await get_tree().process_frame
	var eq := _make_eq()
	var ring := _item("ring", "ring")
	eq.equip("ring", ring)
	_assert(eq.is_equipped("ring"), "Unequip: pre-condition (ring equipped)")
	var removed := eq.unequip("ring")
	_assert(removed == ring, "Unequip: returns removed ring")
	_assert(not eq.is_equipped("ring"), "Unequip: slot now empty")
	_assert(eq.unequip("ring") == null, "Unequip: second unequip returns null")
	eq.queue_free()


func _run_unknown_slot_rejected() -> void:
	await get_tree().process_frame
	var eq := _make_eq()
	var thing := _item("thing")
	var prior := eq.equip("nonsense_slot", thing)
	_assert(prior == null, "UnknownSlot: equip returns null (slot not in SLOTS)")
	_assert(not eq.is_equipped("nonsense_slot"), "UnknownSlot: nothing stored")
	eq.queue_free()


func _run_signals_fire() -> void:
	await get_tree().process_frame
	var eq := _make_eq()
	var chest := _item("chest", "chest")
	var equipped_events: Array = []
	var unequipped_events: Array = []
	eq.item_equipped.connect(func(sid, item): equipped_events.append([sid, item.id]))
	eq.item_unequipped.connect(func(sid, item): unequipped_events.append([sid, item.id]))
	eq.equip("chest", chest)
	eq.unequip("chest")
	_assert(equipped_events.size() == 1 and equipped_events[0][1] == "chest",
		"Signals: item_equipped fired with chest")
	_assert(unequipped_events.size() == 1 and unequipped_events[0][1] == "chest",
		"Signals: item_unequipped fired with chest")
	eq.queue_free()
