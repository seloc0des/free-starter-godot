extends Node

# Headless test for Stats / Skills — Lite.
# Run: godot --headless --path . res://tools/stats_skills_lite/verify.tscn

const PickupScript := preload("res://addons/stats_skills_lite/stat_pickup_lite.gd")
const ListScript := preload("res://addons/stats_skills_lite/stats_list_lite.gd")

var _passes := 0
var _failures := 0
var _log: Array = []  # [ [bool passed, String msg], ... ] — for the windowed report


func _ready() -> void:
	await get_tree().process_frame
	print("--- stats lite verify ---")
	await _run_base_value()
	await _run_set_base_override()
	await _run_flat_modifier()
	await _run_percent_add_modifier()
	await _run_percent_mult_modifier()
	await _run_combined_modifiers()
	await _run_clamp_min_max()
	await _run_remove_modifier_by_source_id()
	await _run_signal_fires()
	# pickups and the stats list in a played scene: the player walks in, presses C
	await _run_pickup_raises_stat()
	await _run_pickup_ignores_non_player()
	await _run_timed_boost_wears_off()
	await _run_staying_pickups()
	await _run_pickup_needs_a_real_stat()
	await _run_pickup_on_player_keeps_player()
	await _run_list_shows_and_updates()
	await _run_list_follows_new_player()
	await _run_list_toggles_on_c()
	await _run_list_lays_itself_out()
	_clear_toasts()  # the test messages would sit on top of the banner
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	# Headless (CI/build) keeps the exit-code behavior. In a window (editor F6) show a
	# visual PASS/FAIL banner instead — the load-and-look buyer QA scene.
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0 if _failures == 0 else 1)
	else:
		# untyped on purpose: `:=` on load().new() is a Variant → parse-hang; class_name
		# would need a project rescan to register. Plain dynamic dispatch dodges both.
		var report = load("res://tools/stats_skills_lite/acceptance_report.gd").new()
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

func _approx(a: float, b: float, eps: float = 0.001) -> bool:
	return abs(a - b) < eps


func _def(id: String, base: float, mn: float = -1.0e9, mx: float = 1.0e9) -> StatDefinitionLite:
	var d := StatDefinitionLite.new()
	d.id = id
	d.display_name = id.capitalize()
	d.base_value = base
	d.min_value = mn
	d.max_value = mx
	return d


func _make_stats(defs: Array) -> StatsComponentLite:
	var s := StatsComponentLite.new()
	# Typed Array[StatDefinitionLite] doesn't accept a plain Array; build the
	# typed array explicitly.
	var typed: Array[StatDefinitionLite] = []
	for d in defs:
		typed.append(d)
	s.definitions = typed
	add_child(s)
	return s


# ---- tests ---------------------------------------------------------------

func _run_base_value() -> void:
	await get_tree().process_frame
	var s := _make_stats([_def("strength", 10.0)])
	_assert(_approx(s.get_stat("strength"), 10.0), "Base: strength = 10")
	_assert(_approx(s.get_stat("unknown"), 0.0), "Base: missing def returns 0")
	s.queue_free()


func _run_set_base_override() -> void:
	await get_tree().process_frame
	var s := _make_stats([_def("hp", 100.0)])
	s.set_base("hp", 75.0)
	_assert(_approx(s.get_stat("hp"), 75.0), "Override: base override applied")
	s.queue_free()


func _run_flat_modifier() -> void:
	await get_tree().process_frame
	var s := _make_stats([_def("damage", 5.0)])
	s.add_modifier({"stat": "damage", "op": "flat", "amount": 8.0, "source_id": "sword"})
	_assert(_approx(s.get_stat("damage"), 13.0), "Flat: 5 + 8 = 13 (got %f)" % s.get_stat("damage"))
	s.queue_free()


func _run_percent_add_modifier() -> void:
	await get_tree().process_frame
	var s := _make_stats([_def("damage", 10.0)])
	s.add_modifier({"stat": "damage", "op": "percent_add", "amount": 25.0, "source_id": "buff"})
	_assert(_approx(s.get_stat("damage"), 12.5),
		"PercentAdd: 10 × (1 + 0.25) = 12.5 (got %f)" % s.get_stat("damage"))
	s.queue_free()


func _run_percent_mult_modifier() -> void:
	await get_tree().process_frame
	var s := _make_stats([_def("damage", 10.0)])
	s.add_modifier({"stat": "damage", "op": "percent_mult", "amount": 50.0, "source_id": "rage"})
	s.add_modifier({"stat": "damage", "op": "percent_mult", "amount": 20.0, "source_id": "haste"})
	# 10 × 1.5 × 1.2 = 18.0
	_assert(_approx(s.get_stat("damage"), 18.0),
		"PercentMult: 10 × 1.5 × 1.2 = 18 (got %f)" % s.get_stat("damage"))
	s.queue_free()


func _run_combined_modifiers() -> void:
	await get_tree().process_frame
	var s := _make_stats([_def("damage", 10.0)])
	s.add_modifier({"stat": "damage", "op": "flat", "amount": 5.0, "source_id": "a"})
	s.add_modifier({"stat": "damage", "op": "percent_add", "amount": 20.0, "source_id": "b"})
	s.add_modifier({"stat": "damage", "op": "percent_mult", "amount": 10.0, "source_id": "c"})
	# (10 + 5) × (1 + 0.20) × 1.10 = 19.8
	_assert(_approx(s.get_stat("damage"), 19.8),
		"Combo: (10+5)*1.2*1.1 = 19.8 (got %f)" % s.get_stat("damage"))
	s.queue_free()


func _run_clamp_min_max() -> void:
	await get_tree().process_frame
	var s := _make_stats([_def("hp", 50.0, 0.0, 100.0)])
	s.add_modifier({"stat": "hp", "op": "flat", "amount": 999.0, "source_id": "heal"})
	_assert(_approx(s.get_stat("hp"), 100.0), "Clamp: hp caps at max (got %f)" % s.get_stat("hp"))
	s.add_modifier({"stat": "hp", "op": "flat", "amount": -9999.0, "source_id": "wipe"})
	_assert(_approx(s.get_stat("hp"), 0.0), "Clamp: hp floors at min (got %f)" % s.get_stat("hp"))
	s.queue_free()


func _run_remove_modifier_by_source_id() -> void:
	await get_tree().process_frame
	var s := _make_stats([_def("damage", 10.0)])
	s.add_modifier({"stat": "damage", "op": "flat", "amount": 5.0, "source_id": "sword"})
	s.add_modifier({"stat": "damage", "op": "flat", "amount": 3.0, "source_id": "ring"})
	_assert(_approx(s.get_stat("damage"), 18.0), "RemovePre: 10+5+3 = 18")
	var n := s.remove_modifier("sword")
	_assert(n == 1, "Remove: 1 entry removed (got %d)" % n)
	_assert(_approx(s.get_stat("damage"), 13.0), "Remove: 10+3 = 13 after sword off")
	s.queue_free()


func _run_signal_fires() -> void:
	await get_tree().process_frame
	var s := _make_stats([_def("hp", 50.0)])
	var seen: Array = []
	var cb := func(stat_id: String, v: float):
		if stat_id == "hp":
			seen.append(v)
	s.stat_changed.connect(cb)
	s.add_modifier({"stat": "hp", "op": "flat", "amount": 25.0, "source_id": "buff"})
	s.stat_changed.disconnect(cb)
	_assert(seen.size() >= 1 and _approx(float(seen[seen.size() - 1]), 75.0),
		"Signal: stat_changed fired with 75 (got %s)" % str(seen))
	s.queue_free()


# ---- StatPickupLite + StatsListLite: played scenes -------------------------

# The player: a body in the "player" group with Attack 10 and Speed 100.
func _player(parent: Node, pos: Vector2, is_player: bool = true) -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.name = "Player"
	body.position = pos
	if is_player:
		body.add_to_group("player")
	var cs := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(16, 16)
	cs.shape = box
	body.add_child(cs)
	var stats := StatsComponentLite.new()
	stats.name = "Stats"
	var attack := _def("attack", 10.0)
	attack.display_name = "Attack"
	var speed := _def("speed", 100.0)
	speed.display_name = "Speed"
	var typed: Array[StatDefinitionLite] = [attack, speed]
	stats.definitions = typed
	body.add_child(stats)
	parent.add_child(body)
	return body


# A potion you can walk into: an Area2D with a shape, holding a StatPickupLite.
func _potion(parent: Node, pos: Vector2, stat: String, amount: float, duration: float = 0.0) -> Area2D:
	var potion := Area2D.new()
	potion.name = "Potion"
	potion.position = pos
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 24.0
	cs.shape = circle
	potion.add_child(cs)
	var p: Node = PickupScript.new()
	p.name = "StatPickup"
	p.stat_id = stat
	p.amount = amount
	p.duration = duration
	potion.add_child(p)
	parent.add_child(potion)
	return potion


func _physics(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _walk(body: Node2D, to: Vector2) -> void:
	body.position = to
	await _physics(4)


func _toast_has(text: String) -> bool:
	for t in get_tree().get_nodes_in_group("lite_toast"):
		if t is Label and not t.is_queued_for_deletion() and (t as Label).text.contains(text):
			return true
	return false


func _clear_toasts() -> void:
	for t in get_tree().get_nodes_in_group("lite_toast"):
		t.remove_from_group("lite_toast")
		t.get_parent().queue_free()


func _attack(player: Node) -> float:
	return (player.get_node("Stats") as StatsComponentLite).get_stat("attack")


func _run_pickup_raises_stat() -> void:
	_clear_toasts()
	var lvl := Node2D.new()
	get_tree().root.add_child(lvl)
	var player := _player(lvl, Vector2(40, 40))
	var potion := _potion(lvl, Vector2(400, 200), "attack", 5.0)
	await _physics(2)
	_assert(_approx(_attack(player), 10.0), "Pickup: Attack is 10 before the player gets there")
	await _walk(player, potion.position)
	_assert(_approx(_attack(player), 15.0), "Pickup: walking into it raises Attack to 15 (got %s)" % _attack(player))
	_assert(_toast_has("+5 Attack"), "Pickup: a message says +5 Attack")
	await get_tree().process_frame
	_assert(not is_instance_valid(potion), "Pickup: the potion is gone once it's used")
	lvl.queue_free()


# control for the check above: the same walk-in by a body that isn't the player
func _run_pickup_ignores_non_player() -> void:
	_clear_toasts()
	var lvl := Node2D.new()
	get_tree().root.add_child(lvl)
	var npc := _player(lvl, Vector2(40, 40), false)
	var potion := _potion(lvl, Vector2(400, 200), "attack", 5.0)
	await _physics(2)
	await _walk(npc, potion.position)
	_assert(_approx(_attack(npc), 10.0) and is_instance_valid(potion) and not _toast_has("Attack"), "Pickup: a body that isn't the player gets nothing and leaves it there")
	lvl.queue_free()


func _run_timed_boost_wears_off() -> void:
	_clear_toasts()
	var lvl := Node2D.new()
	get_tree().root.add_child(lvl)
	var player := _player(lvl, Vector2(40, 40))
	var potion := _potion(lvl, Vector2(400, 200), "attack", 5.0, 0.5)
	await _physics(2)
	await _walk(player, potion.position)
	_assert(_approx(_attack(player), 15.0), "Timed: Attack is 15 while the boost lasts")
	_assert(_toast_has("+5 Attack for 0.5s"), "Timed: the message says how long")
	await get_tree().create_timer(0.8).timeout
	_assert(_approx(_attack(player), 10.0), "Timed: back to 10 when it wears off, with the potion long gone (got %s)" % _attack(player))
	lvl.queue_free()


func _run_staying_pickups() -> void:
	_clear_toasts()
	var lvl := Node2D.new()
	get_tree().root.add_child(lvl)
	var player := _player(lvl, Vector2(40, 40))
	var shrine := _potion(lvl, Vector2(400, 200), "attack", 5.0)
	shrine.get_node("StatPickup").stay = true
	var pad := _potion(lvl, Vector2(800, 200), "speed", 20.0, 0.6)
	pad.get_node("StatPickup").stay = true
	await _physics(2)
	for i in 2:
		await _walk(player, shrine.position)
		await _walk(player, Vector2(40, 40))
	_assert(is_instance_valid(shrine) and _approx(_attack(player), 15.0), "Stay: it stays, and a permanent boost is given once (Attack %s)" % _attack(player))
	var stats: StatsComponentLite = player.get_node("Stats")
	await _walk(player, pad.position)
	await _walk(player, Vector2(40, 40))
	await get_tree().create_timer(0.3).timeout
	await _walk(player, pad.position)
	_assert(_approx(stats.get_stat("speed"), 120.0), "Stay: touching a timed one again refreshes it, no stacking (Speed %s)" % stats.get_stat("speed"))
	await get_tree().create_timer(0.45).timeout
	_assert(_approx(stats.get_stat("speed"), 120.0), "Stay: the first touch's timer doesn't cut the refreshed boost short")
	await get_tree().create_timer(0.4).timeout
	_assert(_approx(stats.get_stat("speed"), 100.0), "Stay: the refreshed boost still wears off (Speed %s)" % stats.get_stat("speed"))
	lvl.queue_free()


func _run_pickup_needs_a_real_stat() -> void:
	_clear_toasts()
	var lvl := Node2D.new()
	get_tree().root.add_child(lvl)
	var player := _player(lvl, Vector2(40, 40))
	var potion := _potion(lvl, Vector2(400, 200), "mana", 5.0)
	await _physics(2)
	await _walk(player, potion.position)
	_assert(is_instance_valid(potion) and not _toast_has("Mana"), "Pickup: a stat the player doesn't have does nothing (and warns)")
	lvl.queue_free()


# it removes what it sits on, so on the player itself it must stop short of that
func _run_pickup_on_player_keeps_player() -> void:
	_clear_toasts()
	var lvl := Node2D.new()
	get_tree().root.add_child(lvl)
	var player := _player(lvl, Vector2(200, 200))
	var area := Area2D.new()
	area.name = "PickupArea"
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 24.0
	cs.shape = circle
	area.add_child(cs)
	player.add_child(area)
	var p: Node = PickupScript.new()
	p.stat_id = "attack"
	p.amount = 1.0
	player.add_child(p)
	await _physics(4)
	await get_tree().process_frame
	_assert(is_instance_valid(player) and not player.is_queued_for_deletion(), "Pickup: one put on the player itself never removes the player")
	lvl.queue_free()


# The list and a potion in one played scene, the way Setup builds it.
func _list_level() -> Node2D:
	var lvl := Node2D.new()
	var layer := CanvasLayer.new()
	layer.name = "UILayer"
	lvl.add_child(layer)
	var list: Control = ListScript.new()
	list.name = "StatsList"
	list.visible = false
	list.set_anchors_preset(Control.PRESET_TOP_LEFT)
	list.offset_left = 16
	list.offset_top = 80
	list.offset_right = 276
	list.offset_bottom = 330
	layer.add_child(list)
	return lvl


func _run_list_shows_and_updates() -> void:
	_clear_toasts()
	var lvl := _list_level()
	var player := _player(lvl, Vector2(40, 40))
	var potion := _potion(lvl, Vector2(400, 200), "attack", 5.0, 0.5)
	get_tree().root.add_child(lvl)
	await _physics(2)
	var list: Node = lvl.get_node("UILayer/StatsList")
	var lines: PackedStringArray = list.lines()
	_assert("Attack: 10" in lines and "Speed: 100" in lines, "List: shows the player's stats and values (%s)" % ", ".join(lines))
	await _walk(player, potion.position)
	lines = list.lines()
	_assert("Attack: 15" in lines, "List: updates when a pickup raises Attack (%s)" % ", ".join(lines))
	await get_tree().create_timer(0.8).timeout
	lines = list.lines()
	_assert("Attack: 10" in lines, "List: and again when the boost wears off (%s)" % ", ".join(lines))
	lvl.queue_free()


# a respawned player is a new node: the list has to find it again
func _run_list_follows_new_player() -> void:
	var lvl := _list_level()
	var first := _player(lvl, Vector2(40, 40))
	get_tree().root.add_child(lvl)
	await _physics(2)
	var list: Node = lvl.get_node("UILayer/StatsList")
	first.queue_free()
	await get_tree().process_frame
	var second := _player(lvl, Vector2(40, 40))
	second.name = "Player2"
	(second.get_node("Stats") as StatsComponentLite).set_base("attack", 30.0)
	await _physics(2)
	(second.get_node("Stats") as StatsComponentLite).add_modifier({"stat": "attack", "amount": 2.0, "source_id": "t"})
	_assert("Attack: 32" in list.lines(), "List: follows the new player once the old one is gone (%s)" % ", ".join(list.lines()))
	lvl.queue_free()


func _run_list_toggles_on_c() -> void:
	var lvl := _list_level()
	_player(lvl, Vector2(40, 40))
	get_tree().root.add_child(lvl)
	await get_tree().process_frame
	var list: Control = lvl.get_node("UILayer/StatsList")
	var had := InputMap.has_action("character")
	if not had:
		# what the Setup tab adds to the project: physical C, any device
		InputMap.add_action("character")
		var c := InputEventKey.new()
		c.physical_keycode = KEY_C
		c.device = -1
		InputMap.action_add_event("character", c)
	_assert(not list.visible, "Key: the list starts hidden")
	await _key(KEY_C)
	_assert(list.visible, "Key: C opens it")
	await _key(KEY_X)
	_assert(list.visible, "Key: another key leaves it alone")
	await _key(KEY_C)
	_assert(not list.visible, "Key: C closes it again")
	list.toggle_action = &"no_such_action"
	await _key(KEY_C)
	_assert(not list.visible, "Key: with no such action nothing opens it, and nothing breaks")
	if not had:
		InputMap.erase_action("character")
	lvl.queue_free()


# SPEC C: one added by hand with no size still shows up, in the stats spot.
func _run_list_lays_itself_out() -> void:
	var frame := Control.new()
	frame.size = Vector2(1152, 648)
	get_tree().root.add_child(frame)
	var list: Control = ListScript.new()
	frame.add_child(list)
	await get_tree().process_frame
	var r := list.get_rect()
	_assert(r.size.x > 100 and r.size.y > 100, "Layout: a hand-added list sizes itself (%s)" % r)
	_assert(r.position.x >= 16 and r.position.y >= 80 and r.end.y <= 340, "Layout: left, under the HUD strip at 1152x648 (%s)" % r)
	frame.queue_free()


# One key press the way the game gets it: through Input, then the window.
func _key(code: Key) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = code
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	await get_tree().process_frame
	var up := InputEventKey.new()
	up.physical_keycode = code
	Input.parse_input_event(up)
	await get_tree().process_frame
