extends Node

# Headless test for the Stats — Lite chooser's wiring logic (the part behind the
# Apply button). Editor-only calls (get_edited_scene_root/selection) are split
# out; this drives the pure wire_stats helper against a real scene tree and
# asserts the result is baked-in and re-entrant.
# Run: godot --headless --path . res://tools/stats_skills_lite/verify_chooser.tscn

const CHOOSER := preload("res://addons/stats_skills_lite/editor/stats-skills_chooser_dock.gd")
const COMPONENT := "res://addons/stats_skills_lite/stats_component_lite.gd"

var _passes := 0
var _failures := 0


func _ready() -> void:
	await get_tree().process_frame
	print("--- stats lite chooser verify ---")
	var dock = CHOOSER.new()  # not added to tree; we only call pure helpers
	var root := Node.new()
	root.name = "GameRoot"
	get_tree().root.add_child(root)

	# A selected child, like a Player node. Bake onto it, owned by the scene root.
	var player := Node.new()
	player.name = "Player"
	root.add_child(player); player.owner = root

	# PLAYER STATS — component lands on the target
	var comp1 = dock.wire_stats(root, player, "player")
	_assert(comp1 != null, "wire_stats created a component")
	_assert(comp1.get_script() != null and comp1.get_script().get_global_name() == "StatsComponentLite",
		"created node is a StatsComponentLite")
	_assert(comp1.get_parent() == player, "component parented under the selected node")
	_assert(comp1.owner == root, "component owned by scene root: bakes into the .tscn")
	var defs1: Array = comp1.get("definitions")
	_assert(defs1.size() == 3, "player starter seeded 3 stat definitions (got %d)" % defs1.size())
	_assert(String(defs1[0].id) == "health", "first player stat is 'health' (got '%s')" % String(defs1[0].id))

	# RE-ENTRANT — applying again reuses the same component, never a second one
	var comp2 = dock.wire_stats(root, player, "enemy")
	_assert(comp2 == comp1, "second Apply reused the same component (no duplicate)")
	var comp_count := 0
	for c in player.get_children():
		if c.get_script() != null and c.get_script().get_global_name() == "StatsComponentLite":
			comp_count += 1
	_assert(comp_count == 1, "exactly one component after two Applies (got %d)" % comp_count)

	# OPTIONS PRESERVED — the second starter swapped the definitions in place
	var defs2: Array = comp2.get("definitions")
	_assert(defs2.size() == 2, "enemy starter swapped to 2 definitions (got %d)" % defs2.size())
	_assert(absf(float(defs2[0].base_value) - 30.0) < 0.001,
		"enemy health base is 30 (got %s)" % str(defs2[0].base_value))

	# SCOPE = scene root — target IS the root; component owned by (and re-editable on) root
	var root_only := Node.new()
	get_tree().root.add_child(root_only)
	var comp_root = dock.wire_stats(root_only, root_only, "blank")
	_assert(comp_root.get_parent() == root_only, "scene-root scope parents the component on the root")
	_assert(comp_root.owner == root_only, "scene-root component is owned by the root")
	_assert((comp_root.get("definitions") as Array).is_empty(), "blank starter seeds no definitions")
	root_only.queue_free()

	# OWNERSHIP — a component inside an instanced sub-scene (owner != root) must NOT
	# be hijacked; Apply should make a fresh component the scene actually owns.
	# Fresh root so the ONLY component present is the non-owned one.
	var root2 := Node.new()
	get_tree().root.add_child(root2)
	var sub := Node.new()
	root2.add_child(sub); sub.owner = root2
	var buried = load(COMPONENT).new()
	sub.add_child(buried); buried.owner = sub  # owned by the sub-scene, not root2
	var fresh = dock.wire_stats(root2, root2, "player")
	_assert(fresh != buried, "did not hijack a component owned by a sub-scene")
	_assert(fresh.owner == root2, "made a fresh component the scene root owns")
	root2.queue_free()

	root.queue_free()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
		print("PASS: " + msg)
	else:
		_failures += 1
		printerr("FAIL: " + msg)
