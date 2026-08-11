extends Node

# Headless test for the Loot — Lite chooser's wiring (the part behind Apply).
# Editor-only calls (get_edited_scene_root/selection) are split out; this drives
# the pure wire_source / make_starter_table helpers against a real scene tree and
# asserts the result is baked-in, re-entrant, and ownership-scoped.
# Run: godot --headless --path . res://tools/loot_lite/verify_chooser.tscn

const CHOOSER := preload("res://addons/loot_lite/editor/loot_chooser_dock.gd")
const RESOURCE_SCRIPT := preload("res://addons/loot_lite/loot_table.gd")

var _passes := 0
var _failures := 0


func _ready() -> void:
	await get_tree().process_frame
	print("--- loot lite chooser verify ---")
	var dock = CHOOSER.new()  # not added to tree; we only call pure helpers
	var root := Node3D.new()
	root.name = "GameRoot"
	get_tree().root.add_child(root)
	var target := Node3D.new()
	target.name = "Bandit"
	root.add_child(target); target.owner = root

	var table := _table("bandit_drop")

	# APPLY on the selected node — bakes a LootSource carrying the table.
	dock._chosen = "monster"
	var src1 = dock.wire_source(root, target, table, 1)
	_assert(src1 != null, "wire_source created a loot source")
	_assert(src1.get_parent() == target, "source parented under the chosen node")
	_assert(src1.owner == root, "source owned by scene root: bakes into the .tscn")
	_assert(src1.get_meta("loot_kind") == "monster", "source records the picked kind")
	_assert(src1.get_meta("loot_table") == table, "source carries the chosen table")
	_assert(int(src1.get_meta("rolls")) == 1, "source records rolls per drop")

	# RE-ENTRANT — Apply again updates the same source, never a second one.
	var table2 := _table("bandit_drop_v2")
	var src2 = dock.wire_source(root, target, table2, 5)
	_assert(src2 == src1, "second Apply reused the same source (no duplicate)")
	_assert(src2.get_meta("loot_table") == table2, "re-apply swapped the table in place")
	_assert(int(src2.get_meta("rolls")) == 5, "re-apply updated rolls in place")
	var count := 0
	for c in target.get_children():
		if c.get_class() == "Node" and c.has_meta("loot_kind"):
			count += 1
	_assert(count == 1, "exactly one loot source after two Applies (got %d)" % count)

	# SCOPE variants — a chest source on the scene root itself.
	dock._chosen = "chest"
	var src_root = dock.wire_source(root, root, table, 3)
	_assert(src_root.get_parent() == root, "scene-root scope parents the source on the root")
	_assert(src_root.owner == root, "root-scoped source still owned by root (baked in)")
	_assert(src_root.get_meta("loot_kind") == "chest", "root-scoped source records its kind")

	# NO TABLE yet — Apply must not crash and must not wipe an unset table.
	var bare := Node3D.new()
	bare.name = "Crate"
	root.add_child(bare); bare.owner = root
	dock._chosen = "chest"
	var src_bare = dock.wire_source(root, bare, null, 2)
	_assert(src_bare != null and not src_bare.has_meta("loot_table"), "no-table Apply bakes a source with no table (author later)")
	_assert(int(src_bare.get_meta("rolls")) == 2, "no-table source still records rolls")

	# OWNERSHIP SKIP — a LootSource buried in an instanced sub-scene (owner != root)
	# must NOT be hijacked; Apply makes a fresh source the scene actually owns.
	# Fresh root so the ONLY source present is the non-owned one.
	var root2 := Node3D.new()
	get_tree().root.add_child(root2)
	var sub := Node3D.new()
	root2.add_child(sub); sub.owner = root2
	var buried := Node.new()
	buried.name = "LootSource"
	buried.set_meta("loot_kind", "monster")
	sub.add_child(buried); buried.owner = sub  # owned by the sub-scene, not root2
	dock._chosen = "monster"
	var fresh = dock.wire_source(root2, sub, table, 1)
	_assert(fresh != buried, "did not hijack a source owned by a sub-scene")
	_assert(fresh.owner == root2, "made a fresh source the scene root owns")
	root2.queue_free()

	# STARTER TABLE — pure factory produces a rollable LootTableLite.
	var starter := dock.make_starter_table("chest")
	_assert(starter.get_script() == RESOURCE_SCRIPT, "starter is a LootTableLite")
	_assert(starter.entries.size() == 2, "starter table has 2 entries")
	_assert(int(starter.rolls) == 3, "chest starter rolls 3× (fatter reward)")
	_assert(not starter.roll(_seeded()).is_empty(), "starter table actually rolls loot")
	var mon_starter := dock.make_starter_table("monster")
	_assert(int(mon_starter.rolls) == 1, "monster starter rolls 1× by default")

	root.queue_free()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _table(id: String) -> Resource:
	var t: Resource = RESOURCE_SCRIPT.new()
	t.id = id
	return t


func _seeded() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	return rng


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
		print("PASS: " + msg)
	else:
		_failures += 1
		printerr("FAIL: " + msg)
