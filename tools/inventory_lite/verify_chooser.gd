extends Node

# Headless test for the Inventory — Lite chooser's wiring logic (the part behind the
# Apply button). Editor-only calls (get_edited_scene_root/selection) are split out;
# this drives the pure wire_inventory helper against a real scene tree and asserts
# the result is baked-in and re-entrant.
# Run: godot --headless --path . res://tools/inventory_lite/verify_chooser.tscn

const CHOOSER := preload("res://addons/inventory_lite/editor/inventory_chooser_dock.gd")

var _passes := 0
var _failures := 0


func _ready() -> void:
	await get_tree().process_frame
	print("--- inventory lite chooser verify ---")
	var dock = CHOOSER.new()  # not added to tree; we only call pure helpers
	var root := Node.new()
	root.name = "GameRoot"
	get_tree().root.add_child(root)

	# PLAYER on the root — adds an InventoryLite baked into the scene
	var inv1 = dock.wire_inventory(root, root, "player")
	_assert(inv1 != null, "wire_inventory created an InventoryLite")
	_assert(inv1.get_script() != null and inv1.get_script().get_global_name() == "InventoryLite", "spawned node is an InventoryLite")
	_assert(int(inv1.get("capacity")) == 24, "player outcome set capacity 24 (got %d)" % int(inv1.get("capacity")))
	_assert(inv1.owner == root, "component owned by scene root: bakes into the .tscn")

	# RE-ENTRANT — a second Apply on the same target reuses the node, never a second
	var inv2 = dock.wire_inventory(root, root, "container")
	_assert(inv2 == inv1, "second Apply reused the same component (no duplicate)")
	_assert(int(inv2.get("capacity")) == 16, "container outcome updated capacity in place to 16 (got %d)" % int(inv2.get("capacity")))
	var inv_count := 0
	for c in root.get_children():
		if c.get_script() != null and c.get_script().get_global_name() == "InventoryLite":
			inv_count += 1
	_assert(inv_count == 1, "exactly one InventoryLite on the root after two Applies (got %d)" % inv_count)

	# SCOPE: a selected child gets its OWN component, independent of the root's
	var child := Node.new()
	child.name = "Chest"
	root.add_child(child)
	child.owner = root
	var inv_child = dock.wire_inventory(root, child, "small")
	_assert(inv_child != inv1, "selected-child scope made a distinct component under the child")
	_assert(inv_child.get_parent() == child, "child component parented under the selected node")
	_assert(inv_child.owner == root, "child component still owned by the scene root (bakes in)")
	_assert(int(inv_child.get("capacity")) == 6, "small outcome set capacity 6 (got %d)" % int(inv_child.get("capacity")))

	# OWNERSHIP — a component inside an instanced sub-scene (owner != root) must NOT
	# be hijacked; Apply should make a fresh one the scene actually owns. Fresh root
	# so the ONLY InventoryLite present is the buried, non-owned one.
	var root2 := Node.new()
	get_tree().root.add_child(root2)
	var sub := Node.new()
	root2.add_child(sub)
	sub.owner = root2
	var buried = load("res://addons/inventory_lite/inventory_lite.gd").new()
	sub.add_child(buried)
	buried.owner = sub  # owned by the sub-scene, not root2
	var fresh = dock.wire_inventory(root2, root2, "player")
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
