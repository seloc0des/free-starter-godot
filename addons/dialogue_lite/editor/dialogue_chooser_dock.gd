@tool
extends Control

# The "chooser" panel for Dialogue (Lite): pick how a conversation starts, pick
# which one, hit Apply, and it's wired into your own scene. Re-pick and Apply
# again (it updates the same trigger, never duplicates), or tweak the dropped
# nodes in the Inspector. The sibling "Dialogue" tab is where the conversations
# themselves get written.
#
# What it drops is a DialogueTriggerLite holding the conversation's .tres. It
# registers the conversation itself when it fires, so nothing needs code.

# Loaded lazily, not preloaded: the trigger and the box both name the
# DialoguesLite autoload, which doesn't exist yet on the very first plugin enable.
# A preload failure here would take the whole dock with it.
const TRIGGER_PATH := "res://addons/dialogue_lite/dialogue_trigger_lite.gd"
const BOX_SCENE := "res://addons/dialogue_lite/dialogue_box_lite.tscn"
const BOX_SCRIPT := "res://addons/dialogue_lite/dialogue_box_lite.gd"
const OWN_DIR := "res://dialogues"
# The demo's conversation, offered after the buyer's own as an example.
const EXAMPLE_DIRS := [
	"res://demo/dialogue_lite/dialogues",
	"res://demo/dialogues",  # repo layout
]
const TALK_AREA := "TalkArea"
const TALK_TRIGGER := "TalkTrigger"
const LOAD_TRIGGER := "DialogueOnLoad"
const NO_PLAYER := " Nothing in this scene is marked as the player yet, so this won't react to anything. Select your player node and press \"Make the selected node the player\"."

const OK_COLOR := Color(0.55, 0.9, 0.55)
const ERR_COLOR := Color(0.95, 0.55, 0.55)
const WARN_COLOR := Color(0.95, 0.8, 0.35)

# id -> label. Order = display order (first is the flagship outcome).
const OUTCOMES := {
	"talk": "Talk to this NPC",
	"on_load": "Start when the scene loads",
}

var _chosen := ""
var _buttons := {}
var _picker: OptionButton
var _paths := PackedStringArray()  # picker index -> .tres path
var _status: Label
var _scroll: ScrollContainer


func _ready() -> void:
	name = "Dialogue · Setup"
	# The whole tab scrolls, so a short screen or a big editor scale can't push the
	# bottom off. Sideways it wraps instead.
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.minimum_size_changed.connect(update_minimum_size)
	add_child(_scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 6)
	_scroll.add_child(root)

	root.add_child(_h("1.  How should the conversation start?"))
	for id in OUTCOMES.keys():
		var b := Button.new()
		b.text = OUTCOMES[id]
		b.toggle_mode = true
		b.pressed.connect(_on_pick.bind(id))
		root.add_child(b)
		_buttons[id] = b

	root.add_child(_h("2.  Which conversation?"))
	var prow := HBoxContainer.new()
	root.add_child(prow)
	_picker = OptionButton.new()
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker.clip_text = true
	# 4.7 sizes it to the longest conversation name even when clipped, so a long one widened the dock
	_picker.fit_to_longest_item = false
	prow.add_child(_picker)
	prow.add_child(_btn("Refresh", _refresh_dialogues))

	root.add_child(_h("3.  Apply"))
	root.add_child(_btn("Apply", _on_apply, true))

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

	var player_btn := _btn("Make the selected node the player", _on_make_player)
	player_btn.tooltip_text = "Touch triggers, doors, zones and enemies only react to the node in the \"player\" group."
	root.add_child(player_btn)

	root.add_child(HSeparator.new())
	var note := Label.new()
	note.text = "Talk to this NPC: select the NPC first. Apply gives it a talk area and a trigger, and adds a dialogue box if the scene has none. Write conversations in the Dialogue tab, then press Refresh. Re-pick and Apply to swap the conversation; it updates the same trigger."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.72, 0.75, 0.82)
	root.add_child(note)

	# long button labels wrap onto a second line instead of widening the dock
	for c in root.get_children():
		if c is Button:
			(c as Button).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_refresh_dialogues()


# A plain Control doesn't tell the dock slot how narrow its page can go, so say it
# here. Height is the scroll's job.
func _get_minimum_size() -> Vector2:
	return Vector2(_scroll.get_combined_minimum_size().x, 0.0) if _scroll != null else Vector2.ZERO


# ---- pick ----------------------------------------------------------------

func _on_pick(id: String) -> void:
	_chosen = id
	for k in _buttons.keys():
		_buttons[k].button_pressed = (k == id)
	if id == "talk":
		_say("Picked \"%s\". Select the NPC, pick a conversation, then Apply." % OUTCOMES[id], OK_COLOR)
	else:
		_say("Picked \"%s\". Pick a conversation, then Apply." % OUTCOMES[id], OK_COLOR)


# ---- apply (re-entrant) --------------------------------------------------

func _on_apply() -> void:
	if _chosen == "":
		_say("Pick how the conversation should start first.", WARN_COLOR)
		return
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		_say("Open a scene first (Scene → New/Open).", ERR_COLOR)
		return
	var dialogue := _picked()
	if dialogue == null:
		_say("Pick a conversation first. Write one in the Dialogue tab, then press Refresh.", WARN_COLOR)
		return
	match _chosen:
		"talk": _apply_talk(root, dialogue)
		"on_load": _apply_on_load(root, dialogue)


func _apply_talk(root: Node, dialogue: Resource) -> void:
	var sel := EditorInterface.get_selection().get_selected_nodes()
	if sel.is_empty():
		_say("Select the NPC in the Scene tree first.", WARN_COLOR)
		return
	var npc: Node = sel[0]
	if not (npc is Node2D or npc is Node3D):
		_say("\"%s\" isn't a 2D or 3D node, so nobody can walk up to it. Select the NPC itself." % npc.name, WARN_COLOR)
		return
	var had_box := _find_box(root) != null
	var trig := wire_talk(root, npc, dialogue)
	wire_box(root)
	_select(trig)
	var msg := "\"%s\" now starts \"%s\" when the player touches it." % [npc.name, dialogue.get("id")]
	if not had_box:
		msg += " Added a dialogue box on a UILayer too."
	if not has_player(root):
		_say(msg + NO_PLAYER, WARN_COLOR)
		return
	_say(msg + " Press Play and walk into them.", OK_COLOR)


func _apply_on_load(root: Node, dialogue: Resource) -> void:
	var had_box := _find_box(root) != null
	var trig := wire_on_load(root, dialogue)
	wire_box(root)
	_select(trig)
	var msg := "\"%s\" now starts as soon as this scene loads." % dialogue.get("id")
	if not had_box:
		msg += " Added a dialogue box on a UILayer too."
	_say(msg + " Press Play to see it.", OK_COLOR)


func _on_make_player() -> void:
	var sel := EditorInterface.get_selection().get_selected_nodes()
	if sel.is_empty():
		_say("Select your player node first.", WARN_COLOR)
		return
	var n: Node = sel[0]
	mark_player(n)
	EditorInterface.mark_scene_as_unsaved()
	_say("%s is now the player." % n.name, OK_COLOR)


# --- pure wiring (no EditorInterface, so it's headless-testable) -----------
# Each is re-entrant: it updates the existing node rather than duplicating.

## The NPC gets a talk area (unless it already is one) with a TalkTrigger inside
## that starts the conversation when the player walks in. Returns the trigger.
func wire_talk(root: Node, npc: Node, dialogue: Resource) -> Node:
	var area: Node = npc if (npc is Area2D or npc is Area3D) else _ensure_talk_area(root, npc)
	if not _has_shape(area):
		_add_talk_shape(root, area)
	var trig := _ensure_trigger(root, area, TALK_TRIGGER)
	trig.set("when", 0)                 # When.ON_TOUCH
	trig.set("require_group", "player")
	trig.set("dialogue", dialogue)
	return trig


## A trigger at the scene root that starts the conversation once, on load.
func wire_on_load(root: Node, dialogue: Resource) -> Node:
	var trig := _ensure_trigger(root, root, LOAD_TRIGGER)
	trig.set("when", 1)                 # When.ON_READY
	trig.set("dialogue", dialogue)
	return trig


## The drop-in box, on an owned UILayer. Skipped if the scene already shows one
## anywhere, instanced sub-scenes included: two boxes would both answer.
func wire_box(root: Node) -> Node:
	var box := _find_box(root)
	if box != null:
		return box
	var layer := _ui_layer(root)
	var scene: PackedScene = load(BOX_SCENE)
	# edit-state instance, same as dragging the .tscn in: it saves as a plain
	# instance instead of pinning a copy of every root property
	box = scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	layer.add_child(box, true)
	box.owner = root
	# the box lays itself out from its anchors (full screen, panel pinned to the
	# bottom), not in _ready. If a restyle dropped them it'd land at 0x0, so pin
	# them back; left alone otherwise so the instance saves clean.
	var c := box as Control
	if c.anchor_right != 1.0 or c.anchor_bottom != 1.0:
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return box


## Persistent, so the group is saved with the scene.
func mark_player(node: Node) -> void:
	# re-add rather than trust an existing membership: one added at runtime (or by
	# a live script in the editor) isn't persistent, and add_to_group() won't
	# upgrade it
	if node.is_in_group("player"):
		node.remove_from_group("player")
	node.add_to_group("player", true)


func has_player(root: Node) -> bool:
	if not root.is_inside_tree():
		# no tree to ask (a headless test built it loose), so walk it
		for n in [root] + root.find_children("*", "", true, false):
			if n.is_in_group("player"):
				return true
		return false
	for n in root.get_tree().get_nodes_in_group("player"):
		if n == root or root.is_ancestor_of(n):
			return true
	return false


## The buyer's own conversations first, then the demo's as examples.
## Each entry: {"path": String, "example": bool}. own_dir is only for tests.
func scan_dialogues(own_dir: String = OWN_DIR) -> Array:
	var out: Array = []
	for p in _dialogue_files(own_dir):
		out.append({"path": p, "example": false})
	for dir in EXAMPLE_DIRS:
		if DirAccess.dir_exists_absolute(dir):
			for p in _dialogue_files(dir):
				out.append({"path": p, "example": true})
			break
	return out


# ---- helpers -------------------------------------------------------------

func _ensure_talk_area(root: Node, npc: Node) -> Node:
	for c in npc.get_children():
		if c.name == TALK_AREA and (c is Area2D or c is Area3D) and c.owner == root:
			return c
	var area: Node = Area3D.new() if npc is Node3D else Area2D.new()
	area.name = TALK_AREA
	npc.add_child(area, true)
	area.owner = root
	return area


# Round, and a bit bigger than a typical sprite, so bumping into the NPC counts.
func _add_talk_shape(root: Node, area: Node) -> void:
	var shape: Node
	if area is Area3D:
		var sphere := SphereShape3D.new()
		sphere.radius = 1.5
		var s3 := CollisionShape3D.new()
		s3.shape = sphere
		shape = s3
	else:
		var circle := CircleShape2D.new()
		circle.radius = 40.0
		var s2 := CollisionShape2D.new()
		s2.shape = circle
		shape = s2
	shape.name = "Shape"
	area.add_child(shape, true)
	shape.owner = root


func _has_shape(area: Node) -> bool:
	for c in area.get_children():
		if c is CollisionShape2D or c is CollisionPolygon2D or c is CollisionShape3D or c is CollisionPolygon3D:
			return true
	return false


func _ensure_trigger(root: Node, parent: Node, node_name: String) -> Node:
	for c in parent.get_children():
		if c.name == node_name and c.owner == root and _is_trigger(c):
			return c
	var trig: Node = _inert(load(TRIGGER_PATH))
	trig.name = node_name
	parent.add_child(trig, true)
	trig.owner = root
	return trig


# A runtime script's .new() is a live instance, so its game code would run in the
# editor until the scene is reopened. Attach the script to a plain native node
# instead: that's the inert placeholder a hand-added node gets. Exports still save.
func _inert(script: Script) -> Node:
	var n: Node = ClassDB.instantiate(script.get_instance_base_type())
	n.set_script(script)
	return n


func _is_trigger(n: Node) -> bool:
	var scr: Script = n.get_script()
	return scr != null and scr.resource_path == TRIGGER_PATH


func _find_box(root: Node) -> Node:
	if _is_box(root):
		return root
	for n in root.find_children("*", "", true, false):
		if _is_box(n):
			return n
	return null


func _is_box(n: Node) -> bool:
	var scr: Script = n.get_script()
	return scr != null and scr.resource_path == BOX_SCRIPT


func _ui_layer(root: Node) -> Node:
	for c in root.get_children():
		if c is CanvasLayer and c.name == "UILayer" and c.owner == root:
			return c
	var layer := CanvasLayer.new()
	layer.name = "UILayer"
	root.add_child(layer, true)
	layer.owner = root
	return layer


func _dialogue_files(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir_path):
		return out
	var files := DirAccess.get_files_at(dir_path)
	files.sort()
	for f in files:
		if f.get_extension() != "tres":
			continue
		var full := dir_path.path_join(f)
		if load(full) is DialogueLite:
			out.append(full)
	return out


func _refresh_dialogues() -> void:
	var keep := _picked_path()
	_picker.clear()
	_paths = PackedStringArray()
	for d in scan_dialogues():
		var path: String = d["path"]
		var res: Resource = load(path)
		var label := String(res.get("id"))
		if label == "":
			label = path.get_file().get_basename()
		if d["example"]:
			label += "  (example)"
		_picker.add_item(label, _paths.size())
		_paths.append(path)
	_picker.disabled = _paths.is_empty()
	if _paths.is_empty():
		_picker.add_item("(no conversations yet)")
		return
	_picker.select(maxi(_paths.find(keep), 0))


func _picked_path() -> String:
	if _picker == null:
		return ""
	var i := _picker.selected
	return _paths[i] if i >= 0 and i < _paths.size() else ""


func _picked() -> Resource:
	var p := _picked_path()
	return load(p) if p != "" else null


func _select(n: Node) -> void:
	# Apply adds nodes without the undo manager, so the editor never flags the scene
	# and Play would run the saved file without them. Flag it by hand.
	EditorInterface.mark_scene_as_unsaved()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(n)
	EditorInterface.edit_node(n)


func _h(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.modulate = Color(0.8, 0.85, 0.95)
	return l


func _btn(text: String, cb: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	if primary:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	return b


func _say(text: String, color: Color) -> void:
	_status.modulate = color
	_status.text = text
