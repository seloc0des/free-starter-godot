extends Node

# Headless test for the Save/Load Lite chooser's wiring logic (the part behind the
# Apply button). Editor-only calls (get_edited_scene_root/selection) are split out;
# this drives the pure wire_saveable helper against a real scene tree and asserts
# the result is baked-in, re-entrant, property-prefilled, and ownership-scoped.
# Run: godot --headless --path . res://tools/save_load_lite/verify_chooser.tscn

const CHOOSER := preload("res://addons/save_load_lite/editor/save-load_chooser_dock.gd")
const SAVEABLE_SCRIPT := preload("res://addons/save_load_lite/saveable.gd")
const KEYS_SCRIPT := preload("res://addons/save_load_lite/save_keys_lite.gd")

var _passes := 0
var _failures := 0


# A minimal node with a storable export (position-ish int) plus a Node ref that
# must be skipped by the prefill (Objects don't survive the JSON round-trip).
class _Actor extends Node:
	@export var hp: int = 100
	@export var display_name: String = "Hero"
	@export var buddy: Node = null


func _ready() -> void:
	await get_tree().process_frame
	print("--- save/load lite chooser verify ---")
	var dock = CHOOSER.new()  # not added to tree; we only call pure helpers
	var root := Node.new()
	root.name = "GameRoot"
	get_tree().root.add_child(root)
	var actor := _Actor.new()
	actor.name = "Player"
	root.add_child(actor); actor.owner = root
	# give the Node export a real reference so the prefill skip is actually exercised
	var pal := Node.new()
	root.add_child(pal); pal.owner = root
	actor.buddy = pal

	# CREATE + BAKED IN — a SaveableLite child owned by the scene root
	var sv1 = dock.wire_saveable(root, actor)
	_assert(sv1 != null, "wire_saveable created a Saveable node")
	_assert(sv1.get_script() == SAVEABLE_SCRIPT, "created node is a SaveableLite")
	_assert(sv1.get_parent() == actor, "Saveable parented under the chosen target")
	_assert(sv1.owner == root, "Saveable owned by scene root: bakes into the .tscn")

	# PREFILL — storable exports listed, Node ref skipped (won't round-trip)
	var props: PackedStringArray = sv1.get("save_properties")
	_assert("hp" in props, "prefilled save_properties includes the int export")
	_assert("display_name" in props, "prefilled save_properties includes the string export")
	_assert(not ("buddy" in props), "prefill skipped the Node export (won't survive JSON)")

	# RE-ENTRANT — applying again reuses the same node, never a second one
	var sv2 = dock.wire_saveable(root, actor)
	_assert(sv2 == sv1, "second Apply reused the same Saveable (no duplicate)")
	var count := 0
	for c in actor.get_children():
		if c.get_script() == SAVEABLE_SCRIPT:
			count += 1
	_assert(count == 1, "exactly one Saveable on the target after two Applies (got %d)" % count)

	# RE-ENTRANT PRESERVES EDITS — a buyer-edited property list survives re-Apply
	sv1.set("save_properties", PackedStringArray(["hp"]))
	var sv3 = dock.wire_saveable(root, actor)
	_assert(sv3 == sv1 and PackedStringArray(sv3.get("save_properties")) == PackedStringArray(["hp"]),
		"re-Apply kept the buyer's edited save_properties (didn't re-prefill)")

	# SCOPE: THIS SCENE — a distinct target (the root) gets its own Saveable
	var sv_root = dock.wire_saveable(root, root)
	_assert(sv_root != sv1, "scoping to a different target makes a separate Saveable")
	_assert(sv_root.get_parent() == root and sv_root.owner == root, "scene-scope Saveable parented+owned by root")

	# OWNERSHIP — a Saveable buried in an instanced sub-scene (owner != root) must
	# NOT be hijacked; Apply makes a fresh one the scene actually owns. Fresh root so
	# the ONLY Saveable on the target is the non-owned one.
	var root2 := Node.new()
	root2.name = "GameRoot2"
	get_tree().root.add_child(root2)
	# target2 stands in for an instanced sub-scene: it owns its own inner nodes, so
	# a Saveable already inside it has owner == target2, not root2.
	var target2 := Node.new()
	root2.add_child(target2); target2.owner = root2
	var buried = SAVEABLE_SCRIPT.new()
	target2.add_child(buried); buried.owner = target2  # owned by the sub-scene, NOT root2
	var fresh = dock.wire_saveable(root2, target2)
	_assert(fresh != buried, "did not hijack a Saveable owned by a sub-scene")
	_assert(fresh.owner == root2, "made a fresh Saveable the scene root owns")

	_quick_keys_checks(dock)

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


func _count_keys(root: Node) -> int:
	var n := 0
	for c in root.find_children("*", "", true, false):
		if c.get_script() == KEYS_SCRIPT:
			n += 1
	return n


# "Quick save and load keys": one SaveKeys on the root, re-entrant, and the
# "Save this node's state" status points at it instead of at code.
func _quick_keys_checks(dock) -> void:
	var level := Node2D.new()
	level.name = "Level"
	var hero := CharacterBody2D.new()
	hero.name = "Player"
	level.add_child(hero); hero.owner = level

	var sv = dock.wire_saveable(level, hero)
	var props: PackedStringArray = sv.get("save_properties")
	_assert("position" in props, "a 2D body's position is prefilled, so a script-less player still saves")
	var st: String = dock.save_node_status(level, hero, props)
	_assert(not st.contains("SaveLite") and not st.contains("()"), "save status never sends the buyer to code (%s)" % st)
	_assert(st.contains("Add \"Quick save and load keys\" so the player can save (F5) and load (F9)."), "no keys yet: save status says to add them")

	var k1 = dock.wire_keys(level, false)
	_assert(k1 != null and k1.get_script() == KEYS_SCRIPT, "wire_keys added a SaveKeysLite")
	_assert(k1.get_parent() == level, "SaveKeys sits on the scene root")
	_assert(k1.owner == level, "SaveKeys owned by the root: bakes into the .tscn")
	_assert(String(k1.name) == "SaveKeys", "named SaveKeys (got %s)" % k1.name)
	_assert(k1.get("load_on_start") == false, "checkbox off: load_on_start stays off")
	_assert(dock.find_keys(level) == k1, "find_keys finds it")
	_assert(dock.keys_status(level, k1, true) == "Added quick save: F5 saves, F9 loads.", "status: %s" % dock.keys_status(level, k1, true))
	_assert(dock.save_node_status(level, hero, props).ends_with(" F5 saves it and F9 loads it."), "with keys: save status says F5 saves it and F9 loads it")

	# the buyer picks another save key in the Inspector, then ticks the box and re-Applies
	k1.set("save_key", KEY_F6)
	var k2 = dock.wire_keys(level, true)
	_assert(k2 == k1, "second Apply reuses the same SaveKeys")
	_assert(_count_keys(level) == 1, "exactly one SaveKeys after two Applies (got %d)" % _count_keys(level))
	_assert(k2.get("load_on_start") == true, "second Apply takes the ticked checkbox")
	_assert(k2.get("save_key") == KEY_F6, "second Apply keeps the key the buyer picked")
	_assert(dock.keys_status(level, k2, false) == "Updated quick save: F6 saves, F9 loads. It loads the save when the scene starts.", "status: %s" % dock.keys_status(level, k2, false))

	# what gets saved with the scene
	var ps := PackedScene.new()
	ps.pack(level)
	var copy := ps.instantiate()
	var saved_keys := copy.get_node_or_null("SaveKeys")
	_assert(saved_keys != null and saved_keys.get("load_on_start") == true and saved_keys.get("save_key") == KEY_F6, "the ticked box and the picked key are saved with the scene")
	copy.free()

	# a node of the buyer's already called SaveKeys: ours gets a readable name, not @Node@123
	var other := Node2D.new()
	other.name = "Other"
	var mine := Node.new()
	mine.name = "SaveKeys"
	other.add_child(mine); mine.owner = other
	var k3 = dock.wire_keys(other, false)
	_assert(k3 != mine and not String(k3.name).contains("@"), "a name clash still gives a readable name (got %s)" % k3.name)
	_assert(dock.keys_status(other, k3, true).ends_with("Nothing in this scene is saveable yet: select a node and use \"Save this node's state\"."), "keys status says when nothing is saveable yet")
	other.free()

	# one inside an instanced sub-scene isn't reused, but still counts for the status
	var host := Node2D.new()
	var sub := Node2D.new()
	host.add_child(sub); sub.owner = host
	var inner = dock.wire_keys(sub, false)  # owned by the sub-scene, not host
	_assert(dock.find_keys(host) == null and dock.find_keys(host, false) == inner, "a sub-scene's SaveKeys isn't hijacked but is seen")
	host.free()
	level.free()
