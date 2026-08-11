extends Node

# Headless test for the Crafting — Lite chooser's wiring logic (the part behind
# the Apply button). Editor-only calls (get_edited_scene_root/selection) are split
# out; this drives the pure wire_* helper against a real scene tree and asserts the
# result is baked-in (owner == root), re-entrant, and ownership-scoped.
# Run: godot --headless --path . res://tools/crafting_lite/verify_chooser.tscn

const CHOOSER := preload("res://addons/crafting_lite/editor/crafting_chooser_dock.gd")
const CRAFTING := preload("res://addons/crafting_lite/crafting_lite.gd")

var _passes := 0
var _failures := 0


func _ready() -> void:
	await get_tree().process_frame
	print("--- crafting chooser verify ---")
	var dock = CHOOSER.new()  # not added to tree; we only call pure helpers
	var root := Node.new()
	root.name = "GameRoot"
	get_tree().root.add_child(root)

	# SELECTED node — the component lands under the chosen target, owned by root
	var target := Node.new()
	target.name = "Bench"
	root.add_child(target); target.owner = root
	var comp1 = dock.wire_crafting(root, target)
	_assert(comp1 != null, "wire_crafting created a component")
	_assert(comp1.get_script() == CRAFTING, "spawned node is a CraftingLite")
	_assert(comp1.get_parent() == target, "component parented under the selected node")
	_assert(comp1.owner == root, "component owned by scene root: bakes into the .tscn")

	# RE-ENTRANT — applying again on the same target reuses the same component
	var comp2 = dock.wire_crafting(root, target)
	_assert(comp2 == comp1, "second Apply reused the same component (no duplicate)")
	var count := 0
	for c in target.get_children():
		if c.get_script() == CRAFTING:
			count += 1
	_assert(count == 1, "exactly one CraftingLite under the target after two Applies (got %d)" % count)

	# SCENE ROOT scope — targeting root itself finds/creates a root-owned component
	var root2 := Node.new()
	get_tree().root.add_child(root2)
	var rc = dock.wire_crafting(root2, root2)
	_assert(rc.get_parent() == root2, "scene-root scope parents the component under root")
	_assert(rc.owner == root2, "scene-root component is owned by root")
	var rc2 = dock.wire_crafting(root2, root2)
	_assert(rc2 == rc, "scene-root scope is re-entrant too")
	root2.queue_free()

	# OWNERSHIP — a component inside an instanced sub-scene (owner != root) must NOT
	# be hijacked; Apply should make a fresh component the scene actually owns. Fresh
	# root so the ONLY CraftingLite present is the buried, non-owned one.
	var root3 := Node.new()
	get_tree().root.add_child(root3)
	var sub := Node.new()
	root3.add_child(sub); sub.owner = root3
	var buried = CRAFTING.new()
	sub.add_child(buried); buried.owner = sub  # owned by the sub-scene, not root3
	var fresh = dock.wire_crafting(root3, root3)
	_assert(fresh != buried, "did not hijack a component owned by a sub-scene")
	_assert(fresh.owner == root3, "made a fresh component the scene root owns")
	root3.queue_free()

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
