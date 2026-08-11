extends Node

# Headless test for the Equipment — Lite chooser's wiring logic (the part behind
# the Apply button). Editor-only calls (get_edited_scene_root/selection) are split
# out; this drives the pure wire_* helpers against a real scene tree and asserts
# the result is baked-in, re-entrant, and ownership-scoped.
# Run: godot --headless --path . res://tools/equipment_lite/verify_chooser.tscn

const CHOOSER := preload("res://addons/equipment_lite/editor/equipment_chooser_dock.gd")
const COMPONENT_SCRIPT := "res://addons/equipment_lite/equipment_lite.gd"

var _passes := 0
var _failures := 0


func _ready() -> void:
	await get_tree().process_frame
	print("--- equipment chooser verify ---")
	var dock: Object = CHOOSER.new()  # not added to tree; we only call pure helpers
	var root := Node.new()
	root.name = "GameRoot"
	get_tree().root.add_child(root)

	# SCENE ROOT scope — component lands on the root itself, baked into the .tscn
	var comp1: Node = dock.wire_component(root, root)
	_assert(comp1 != null, "wire_component created a component")
	_assert(comp1.get_script() != null and comp1.get_script().get_global_name() == "EquipmentLite",
		"created node is an EquipmentLite")
	_assert(comp1.owner == root, "component owned by scene root: bakes into the .tscn")

	# RE-ENTRANT — applying again to the same target reuses it, never a second one
	var comp2: Node = dock.wire_component(root, root)
	_assert(comp2 == comp1, "second Apply reused the same component (no duplicate)")
	var root_count := _count_owned(root, root)
	_assert(root_count == 1, "exactly one EquipmentLite on the root after two Applies (got %d)" % root_count)

	# SELECTED-NODE scope — component parents under the chosen child, still owned
	# by the scene root so it serializes. Independent of the root's own component.
	var child := Node.new()
	child.name = "Player"
	root.add_child(child); child.owner = root
	var comp3: Node = dock.wire_component(root, child)
	_assert(comp3 != null and comp3 != comp1, "selected-node scope made a distinct component")
	_assert(comp3.get_parent() == child, "component parented under the selected node")
	_assert(comp3.owner == root, "selected-node component still owned by root (serializes)")
	# re-entrant on the child target too
	var comp4: Node = dock.wire_component(root, child)
	_assert(comp4 == comp3, "re-apply on the selected node reused its component")

	# OWNERSHIP — a component buried in an instanced sub-scene (owner != root) must
	# NOT be hijacked; Apply makes a fresh one the scene root actually owns. Fresh
	# root so the ONLY component present is the non-owned one.
	var root2 := Node.new()
	get_tree().root.add_child(root2)
	var sub := Node.new()
	root2.add_child(sub); sub.owner = root2
	var buried: Node = load(COMPONENT_SCRIPT).new()
	sub.add_child(buried); buried.owner = sub  # owned by the sub-scene, not root2
	var fresh: Node = dock.wire_component(root2, root2)
	_assert(fresh != buried, "did not hijack a component owned by a sub-scene")
	_assert(fresh.owner == root2, "made a fresh component the scene root owns")
	root2.queue_free()

	root.queue_free()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


# Count EquipmentLite nodes owned by `root` (mirrors the chooser's ownership scope).
func _count_owned(node: Node, root: Node) -> int:
	var n := 0
	if (node == root or node.owner == root):
		var scr: Script = node.get_script()
		if scr != null and scr.get_global_name() == "EquipmentLite":
			n += 1
	for c in node.get_children():
		n += _count_owned(c, root)
	return n


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
		print("PASS: " + msg)
	else:
		_failures += 1
		printerr("FAIL: " + msg)
