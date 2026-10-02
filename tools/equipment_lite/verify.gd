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
	await _run_equip_pickup_equips()
	await _run_equip_pickup_replaces()
	await _run_equip_pickup_needs_slot()
	await _run_equip_pickup_ignores_strangers()
	await _run_equipped_list_toggles()
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


# ---- equip pickups + the equipped list (what the Setup tab builds, by hand) ----

# A level with a player (in the "player" group, with slots) and a sword lying
# somewhere else: a Node2D holding a PickupArea and an EquipPickupLite.
func _level(item: Resource) -> Dictionary:
	var level := Node2D.new()
	var player := CharacterBody2D.new()
	player.name = "Player"
	player.add_to_group("player")
	player.add_child(_shape(10.0))
	var eq := EquipmentLite.new()
	player.add_child(eq)
	level.add_child(player)
	var thing := Node2D.new()
	thing.name = "Sword"
	thing.position = Vector2(400, 100)
	var area := Area2D.new()
	area.name = "PickupArea"
	area.add_child(_shape(24.0))
	thing.add_child(area)
	var pickup := EquipPickupLite.new()
	pickup.item = item
	thing.add_child(pickup)
	level.add_child(thing)
	add_child(level)
	return {"level": level, "player": player, "eq": eq, "thing": thing, "pickup": pickup}


func _shape(r: float) -> CollisionShape2D:
	var col := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = r
	col.shape = c
	return col


func _walk_in(body: Node2D, to: Node2D) -> void:
	body.global_position = to.global_position
	for i in 6:
		await get_tree().physics_frame
	await get_tree().process_frame


func _toast_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for t in get_tree().get_nodes_in_group("lite_toast"):
		if not t.is_queued_for_deletion():
			out.append(String(t.text))
	return out


func _clear_toasts() -> void:
	for t in get_tree().get_nodes_in_group("lite_toast"):
		t.get_parent().queue_free()
	await get_tree().process_frame


func _press(key: Key) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = key
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	await get_tree().process_frame
	var up := InputEventKey.new()
	up.physical_keycode = key
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _run_equip_pickup_equips() -> void:
	await _clear_toasts()
	var sword := _item("sword", "weapon_main")
	sword.name = "Iron Sword"
	var l := _level(sword)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_assert(not l.eq.is_equipped("weapon_main") and is_instance_valid(l.thing), "EquipPickup: nothing happens before the player touches it")
	await _walk_in(l.player, l.thing)
	_assert(l.eq.get_equipped("weapon_main") == sword, "EquipPickup: walking into it equips the sword in its own slot")
	_assert(not is_instance_valid(l.thing), "EquipPickup: the sword on the ground is gone")
	_assert(_toast_texts().has("Equipped Iron Sword"), "EquipPickup: a toast says Equipped Iron Sword (got %s)" % str(_toast_texts()))
	l.level.queue_free()


func _run_equip_pickup_replaces() -> void:
	await _clear_toasts()
	var axe := _item("axe", "weapon_main")
	var sword := _item("sword", "weapon_main")
	var l := _level(sword)
	l.eq.equip("weapon_main", axe)
	await _walk_in(l.player, l.thing)
	_assert(l.eq.get_equipped("weapon_main") == sword, "EquipPickup: it replaces what was in that slot")
	l.level.queue_free()


func _run_equip_pickup_needs_slot() -> void:
	await _clear_toasts()
	var odd := _item("odd")  # no equip_slot
	var l := _level(odd)
	await _walk_in(l.player, l.thing)
	_assert(l.eq.all_equipped().is_empty() and is_instance_valid(l.thing), "EquipPickup: an item with no slot isn't equipped and stays on the ground")
	_assert(_toast_texts().is_empty(), "EquipPickup: and it doesn't claim it was equipped")
	l.level.queue_free()


func _run_equip_pickup_ignores_strangers() -> void:
	await _clear_toasts()
	var sword := _item("sword", "weapon_main")
	var l := _level(sword)
	var goblin := CharacterBody2D.new()
	goblin.add_child(_shape(10.0))
	var its_rig := EquipmentLite.new()  # slots of its own, so only the group keeps it out
	goblin.add_child(its_rig)
	l.level.add_child(goblin)
	await _walk_in(goblin, l.thing)
	_assert(is_instance_valid(l.thing) and not l.eq.is_equipped("weapon_main") and not its_rig.is_equipped("weapon_main"), "EquipPickup: a body outside the player group doesn't take it, even with slots")
	l.level.queue_free()


func _run_equipped_list_toggles() -> void:
	await _clear_toasts()
	var fresh := EquippedListLite.new()
	_assert(fresh.toggle_action == &"character", "EquippedList: it toggles on the \"character\" action unless told otherwise")
	fresh.free()
	# its own action on C, so a project that already binds "character" elsewhere
	# still passes (the Setup tab's real action is covered in verify_chooser)
	InputMap.add_action(&"verify_list_toggle")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_C
	ev.device = -1
	InputMap.action_add_event(&"verify_list_toggle", ev)
	var sword := _item("sword", "weapon_main")
	sword.name = "Iron Sword"
	var boots := _item("boots", "boots")
	boots.name = "Leather Boots"
	var l := _level(sword)
	l.eq.equip("weapon_main", sword)
	var layer := CanvasLayer.new()
	var list := EquippedListLite.new()
	list.toggle_action = &"verify_list_toggle"
	list.visible = false
	layer.add_child(list)
	l.level.add_child(layer)
	await get_tree().process_frame
	await get_tree().process_frame
	var vp := get_viewport().get_visible_rect().size
	var r := list.get_global_rect()
	_assert(r.size.x > 0 and r.size.y > 0 and is_equal_approx(r.end.x, vp.x - 16.0) and is_equal_approx(r.end.y, vp.y - 16.0),
		"EquippedList: a hand-added list places itself bottom-right (%s in %s)" % [str(r), str(vp)])
	await _press(KEY_C)
	_assert(list.visible, "EquippedList: C opens it")
	var want := PackedStringArray(["Weapon: Iron Sword", "Chest: -", "Boots: -", "Ring: -"])
	_assert(_rows(list) == want, "EquippedList: one line per slot (got %s)" % str(_rows(list)))
	l.eq.equip("boots", boots)
	await get_tree().process_frame
	_assert(_rows(list)[2] == "Boots: Leather Boots", "EquippedList: it follows the equipment's changes (got %s)" % str(_rows(list)))
	await _press(KEY_C)
	_assert(not list.visible, "EquippedList: C again closes it")
	l.level.queue_free()
	InputMap.erase_action(&"verify_list_toggle")


func _rows(list: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for n in list._rows.get_children():
		if not n.is_queued_for_deletion():
			out.append(String(n.text))
	return out
