@tool
extends Control

# The "chooser" panel: a non-coder picks what kind of inventory they want, picks
# WHERE it goes, and hits Apply — it drops an InventoryLite onto their own node.
# Nothing is a one-way street: re-pick and Apply again (it updates in place, never
# duplicates), or tweak the node in the Inspector. The sibling "Items — Lite" tab
# is the item authoring dock (the .tres your inventory holds).
#
# Lite scope: the bag, a plain text list of it (key I) and pickups that fill it.
# The styled bag with icons and drag and drop, chests that open on touch and the
# hotbar are the Pro tier. We say so honestly, we don't nag.

const INVENTORY_SCRIPT := "res://addons/inventory_lite/inventory_lite.gd"
const PICKUP_SCRIPT := "res://addons/inventory_lite/pickup_lite.gd"
const BAG_LIST_SCRIPT := "res://addons/inventory_lite/bag_list_lite.gd"
const ITEM_SCRIPT := "res://addons/inventory_lite/item_resource.gd"
const UPGRADE_URL := "https://selodev.itch.io/godot-inventory-system"
const ITEM_DIR := "res://items"  # where the buyer's own items live (the Items tab saves there too)
# The demo's items, offered as examples. The build nests the demo under the
# addon's name, so the zip has them somewhere else than this repo.
const DEMO_ITEM_DIRS := [
	"res://demo/inventory_lite/items",
	"res://demo/items",  # repo layout
]
const BAG_ACTION := "inventory"
const UI_MARGIN := 16.0
const BAG_SIZE := Vector2(240, 260)
const NO_PLAYER_MSG := "Nothing in this scene is marked as the player yet, so this won't react to anything. Select your player node and press \"Make the selected node the player\"."

# The first three are all "add InventoryLite": they differ only by a sensible
# starting capacity so a non-coder isn't guessing a number. Everything stays
# editable. A pickup is the odd one out: it goes on the thing lying on the ground.
const OUTCOMES := {
	"player": {"label": "Player inventory", "capacity": 24},
	"container": {"label": "A container / chest", "capacity": 16},
	"small": {"label": "A small pouch", "capacity": 6},
	"pickup": {"label": "A pickup", "capacity": 0},
}
const OUTCOME_IDS := ["player", "container", "small", "pickup"]

const OK_COLOR := Color(0.55, 0.9, 0.55)
const ERR_COLOR := Color(0.95, 0.55, 0.55)
const WARN_COLOR := Color(0.95, 0.8, 0.35)

enum Scope { SELECTED, THIS_SCENE }

var _chosen := ""
var _buttons := {}
var _scope: OptionButton
var _status: Label
var _pickup_box: VBoxContainer
var _item_pick: OptionButton
var _amount: SpinBox
var _item_paths: PackedStringArray = PackedStringArray()


func _ready() -> void:
	name = "Inventory · Setup"
	custom_minimum_size = Vector2(0, 420)
	# Taller than the dock, the tab scrolls. Nothing in it is wider than a default
	# dock at 100% or 125%, so it never has to scroll sideways.
	var page := ScrollContainer.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.minimum_size_changed.connect(update_minimum_size)
	add_child(page)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 6)
	page.add_child(root)

	root.add_child(_h("1.  What do you want?"))
	for id in OUTCOME_IDS:
		var b := Button.new()
		b.text = OUTCOMES[id]["label"]
		b.toggle_mode = true
		b.pressed.connect(_on_pick.bind(id))
		root.add_child(b)
		_buttons[id] = b

	# only a pickup needs these, so they show when it's picked
	_pickup_box = VBoxContainer.new()
	_pickup_box.visible = false
	root.add_child(_pickup_box)
	# items made in the other tab show up when you come back to this one
	visibility_changed.connect(_on_shown)
	var item_row := HBoxContainer.new()
	item_row.add_child(_lbl("Item"))
	_item_pick = OptionButton.new()
	_item_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_pick.clip_text = true
	# its longest entry used to set the width of the whole tab; the open list still shows every name in full
	_item_pick.fit_to_longest_item = false
	item_row.add_child(_item_pick)
	item_row.add_child(_btn("New item", _on_new_item))
	_pickup_box.add_child(item_row)
	# and whenever the list opens, even with both tabs on screen at once
	_item_pick.get_popup().about_to_popup.connect(_refresh_items)
	var amt_row := HBoxContainer.new()
	amt_row.add_child(_lbl("Amount"))
	_amount = SpinBox.new()
	_amount.min_value = 1
	_amount.max_value = 999
	_amount.value = 1
	amt_row.add_child(_amount)
	_pickup_box.add_child(amt_row)

	root.add_child(_h("2.  Where should it go?"))
	_scope = OptionButton.new()
	_scope.add_item("The selected node", Scope.SELECTED)
	_scope.add_item("This scene (its root)", Scope.THIS_SCENE)
	root.add_child(_scope)

	var row := HBoxContainer.new()
	root.add_child(row)
	row.add_child(_btn("Apply", _on_apply, true))

	# pickups only fill the bag of the node in the "player" group
	# on a row of its own, so on a narrow dock it wraps its label instead of widening the tab
	var who := _btn("Make the selected node the player", _on_make_player)
	who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	who.tooltip_text = "Touch triggers, doors, zones and enemies only react to the node in the \"player\" group."
	root.add_child(who)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

	root.add_child(HSeparator.new())
	var note := Label.new()
	note.text = "It's your game. Change it any time: re-pick and Apply, or tweak capacity in the Inspector. Author the items it holds in the Items (Lite) tab."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.72, 0.75, 0.82)
	root.add_child(note)

	# Honest funnel, not a nag: say what Pro adds on top of what Lite does.
	var up := Label.new()
	up.text = "🔒 Pro adds a styled bag with icons, drag and drop and tooltips, a hotbar, chests that open on touch with their own panel, weight and category limits, and wiring to the Save, Quests, Crafting, Vendor and Loot packs."
	up.modulate = Color(0.85, 0.8, 0.55)
	up.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(up)
	root.add_child(_btn("Upgrade to Pro →", func(): OS.shell_open(UPGRADE_URL)))


# As wide as what's in it and no wider. The old fixed width pushed a laptop's
# default dock (270 px) wider whenever this tab was open.
func _get_minimum_size() -> Vector2:
	if get_child_count() == 0 or not (get_child(0) is Control):
		return Vector2.ZERO
	return Vector2((get_child(0) as Control).get_combined_minimum_size().x, 0.0)


# ---- pick ----------------------------------------------------------------

func _on_pick(id: String) -> void:
	_chosen = id
	for k in _buttons.keys():
		_buttons[k].button_pressed = (k == id)
	_pickup_box.visible = id == "pickup"
	if id == "pickup":
		_refresh_items()
		_say("Picked A pickup. Select the node lying on the ground (its sprite or Area), pick the item, then Apply.", OK_COLOR)
		return
	_say("Picked %s. Choose where, then Apply." % OUTCOMES[id]["label"], OK_COLOR)


# ---- apply (re-entrant) --------------------------------------------------

func _on_apply() -> void:
	if _chosen == "":
		_say("Pick what you want first.", WARN_COLOR)
		return
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		_say("Open a scene first (Scene → New/Open).", ERR_COLOR)
		return
	var target: Node = root
	if _scope.get_selected_id() == Scope.SELECTED:
		var sel := EditorInterface.get_selection().get_selected_nodes()
		# Only trust a selection that actually belongs to this scene, else fall
		# back to the root — never bake onto a node that won't serialize.
		if sel.size() > 0 and (sel[0] == root or sel[0].owner == root):
			target = sel[0]
	if _chosen == "pickup":
		_apply_pickup(root, target)
		return
	var inv := wire_inventory(root, target, _chosen)
	var bag_note := ""
	if _chosen == "player":
		wire_bag_list(root)
		bag_note = " The bag list sits bottom-left, hidden until you press %s in game." % action_keys(BAG_ACTION)
	_select(inv)
	var tagged := " (now marked as the player)" if _chosen == "player" and target.is_in_group("player") else ""
	_say("%s → added InventoryLite (capacity %d) on '%s'%s.%s Tweak it in the Inspector, or re-pick here." % [OUTCOMES[_chosen]["label"], int(inv.get("capacity")), target.name, tagged, bag_note], OK_COLOR)


func _apply_pickup(root: Node, target: Node) -> void:
	if not (target is Node2D or target is Node3D):
		_say("A pickup goes on a 2D or 3D node. Select the thing lying on the ground (its sprite, mesh or Area), then Apply.", WARN_COLOR)
		return
	# a level root would vanish with the pickup; an Area root is a pickup scene of its own
	if target == root and not (target is Area2D or target is Area3D):
		_say("That's the whole scene. Select the node that should become the pickup (its sprite, mesh or Area), then Apply.", WARN_COLOR)
		return
	var item := _selected_item()
	if item == null:
		_say("Pick the item it gives, or press New item to make one.", WARN_COLOR)
		return
	var had_area := target is Area2D or target is Area3D or target.get_node_or_null(^"PickupArea") != null
	var pickup := wire_pickup(root, target, item, int(_amount.value))
	_select(pickup)
	var msg := "'%s' is now a pickup: %d x %s. Walking into it puts it in the player's bag." % [target.name, int(pickup.get("amount")), _item_name(item)]
	if not had_area:
		msg += " It got a PickupArea to touch. Resize its shape in the Inspector if it's too big or small."
	if ProjectSettings.has_setting("input/" + BAG_ACTION):
		msg += " Press %s in game to see the bag." % action_keys(BAG_ACTION)
	else:
		msg += " Give your player a bag with \"Player inventory\" so it has somewhere to go."
	if _has_player(root):
		_say(msg, OK_COLOR)
	else:
		_say("%s %s" % [msg, NO_PLAYER_MSG], WARN_COLOR)


# --- pure wiring (no EditorInterface, so it's headless-testable) -----------
# Re-entrant: updates the existing InventoryLite under `target` rather than
# duplicating. `root` is the scene root every spawned node must be owned by so
# it bakes into the buyer's .tscn.

func wire_inventory(root: Node, target: Node, outcome: String) -> Node:
	var inv := _ensure(root, target, "InventoryLite", INVENTORY_SCRIPT)
	inv.set("capacity", int(OUTCOMES[outcome]["capacity"]))
	if outcome == "player":
		_tag_player(root, target)
	return inv


# The player's bag as a plain list, bottom-left and hidden until the bag key.
# One per scene: it finds the player's bag by itself once the game runs.
func wire_bag_list(root: Node) -> Node:
	var list := _find(root, root, "BagListLite")
	if list == null:
		list = _inert(load(BAG_LIST_SCRIPT))
		list.name = "BagList"
		_ui_layer(root).add_child(list, true)
		list.owner = root
		# opened by a key, so it starts closed, and that's saved with the scene
		(list as Control).visible = false
	_pin(list as Control)
	ensure_action(BAG_ACTION, KEY_I)
	return list


# Turns `target` (the thing lying on the ground) into a pickup. One per holder:
# Apply again on it updates the item and amount instead of stacking a second.
func wire_pickup(root: Node, target: Node, item: Resource, amount: int) -> Node:
	# the area first, so the pickup finds it the moment it's ready
	if target is Area2D or target is Area3D:
		_ensure_shape(root, target)  # an area without a shape touches nothing
	else:
		_ensure_area(root, target)
	var pickup := _own_child(target, root, "PickupLite")
	if pickup == null:
		pickup = _inert(load(PICKUP_SCRIPT))
		pickup.name = "Pickup"
		target.add_child(pickup, true)
		pickup.owner = root
	pickup.set("item", item)
	pickup.set("amount", maxi(1, amount))
	return pickup


# The inventory input action, on `key`. A binding the project already has is
# left alone. save=false only touches the in-memory settings, and even save=true
# only writes project.godot from inside the editor (a headless save rewrites its
# engine version line).
func ensure_action(action: String, key: Key, save := true) -> void:
	var setting := "input/" + action
	if ProjectSettings.has_setting(setting):
		return
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	# every device, like the Input Map editor stores it: a new key event is
	# device 0 on 4.5 but 16 on 4.7, and one saved with either misses the other
	ev.device = -1
	ProjectSettings.set_setting(setting, {"deadzone": 0.5, "events": [ev]})
	if save and Engine.is_editor_hint():
		ProjectSettings.save()


# The key(s) an action is bound to, for the status line ("I").
func action_keys(action: String) -> String:
	var names := PackedStringArray()
	var cfg: Variant = ProjectSettings.get_setting("input/" + action, null)
	if cfg is Dictionary:
		for e in (cfg as Dictionary).get("events", []):
			if e is InputEventKey:
				var k: InputEventKey = e
				var code: Key = k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
				names.append(OS.get_keycode_string(code))
	if names.is_empty():
		return "the \"%s\" key" % action
	return " or ".join(names)


# A new item with a name already filled in: new_item.tres, new_item_2.tres, ...
# Returns its path, or "" if it couldn't be written.
func make_item(dir := ITEM_DIR) -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("new_item.tres")
	var n := 1
	while FileAccess.file_exists(path):
		n += 1
		path = dir.path_join("new_item_%d.tres" % n)
	var stem := path.get_file().get_basename()
	var it: Resource = load(ITEM_SCRIPT).new()
	it.set("id", stem)
	it.set("name", stem.capitalize())
	if ResourceSaver.save(it, path) != OK:
		return ""
	_register_uid(path)
	return path


# ---- helpers -------------------------------------------------------------

func _ensure(root: Node, target: Node, cls: String, script_path: String) -> Node:
	var found := _find(target, root, cls)
	if found != null:
		return found  # re-entrant: reuse the existing one, never duplicate
	var n: Node = _inert(load(script_path))
	n.name = cls
	target.add_child(n, true)
	n.owner = root
	return n


# A runtime script's .new() is a live instance, so its game code would run in the
# editor until the scene is reopened. Attach the script to a plain native node instead:
# that's the inert placeholder a hand-added node gets.
func _inert(script: Script) -> Node:
	var n: Node = ClassDB.instantiate(script.get_instance_base_type())
	n.set_script(script)
	return n


# Re-entrancy search, scoped to nodes THIS scene owns. A component inside an
# instanced child scene (owner != root) is skipped — updating it wouldn't
# serialize into the buyer's scene, so we'd silently no-op. (Same trap the save
# dock's CanvasLayer search and the visuals _find had.)
func _find(node: Node, root: Node, cls: String) -> Node:
	if (node == root or node.owner == root) and _is_cls(node, cls):
		return node
	for c in node.get_children():
		var f := _find(c, root, cls)
		if f != null:
			return f
	return null


# Touch triggers in the other packs only answer to the "player" group, so a player
# inventory tags its holder (persistently, so it saves with the scene). Not a plain
# level root though: that's the fallback when nothing's selected.
func _tag_player(root: Node, holder: Node) -> void:
	if holder == root and not (holder is CollisionObject2D or holder is CollisionObject3D):
		return
	holder.add_to_group("player", true)


func _is_cls(node: Node, cls: String) -> bool:
	if node.is_class(cls):
		return true  # native class
	var scr := node.get_script()
	return scr != null and scr.get_global_name() == cls  # class_name script


# Only the target's own children: a pickup nested deeper belongs to something else.
func _own_child(target: Node, root: Node, cls: String) -> Node:
	for c in target.get_children():
		if c.owner == root and _is_cls(c, cls):
			return c
	return null


# The thing on the ground isn't an area itself, so it gets one to be touched through.
func _ensure_area(root: Node, holder: Node) -> Node:
	var area := holder.get_node_or_null(^"PickupArea")
	if area == null:
		if holder is Node3D:
			area = Area3D.new()
		else:
			area = Area2D.new()
		area.name = "PickupArea"
		holder.add_child(area, true)
		area.owner = root
	_ensure_shape(root, area)
	return area


func _ensure_shape(root: Node, area: Node) -> void:
	for c in area.get_children():
		if (c is CollisionShape2D or c is CollisionShape3D) and c.get("shape") != null:
			return
		if c is CollisionPolygon2D or c is CollisionPolygon3D:
			return
	var col: Node
	if area is Area3D:
		var s3 := SphereShape3D.new()
		s3.radius = 0.75
		col = CollisionShape3D.new()
		col.set("shape", s3)
	else:
		var s2 := CircleShape2D.new()
		s2.radius = 24.0
		col = CollisionShape2D.new()
		col.set("shape", s2)
	col.name = "PickupShape"
	area.add_child(col, true)
	col.owner = root


# UI goes on a CanvasLayer the scene owns so it draws over the game. A layer
# below the game (a parallax background) doesn't count.
func _ui_layer(root: Node) -> CanvasLayer:
	var found := _find_layer(root, root)
	if found != null:
		return found
	var layer := CanvasLayer.new()
	layer.name = "UILayer"
	root.add_child(layer, true)
	layer.owner = root
	return layer


func _find_layer(node: Node, root: Node) -> CanvasLayer:
	if node is CanvasLayer and (node == root or node.owner == root) and (node as CanvasLayer).layer >= 1:
		return node as CanvasLayer
	for c in node.get_children():
		var f := _find_layer(c, root)
		if f != null:
			return f
	return null


# Bottom-left, inset from the edges, so Play shows it in the right place. One the
# buyer already moved keeps its spot.
func _pin(c: Control) -> void:
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		if c.get_anchor(side) != 0.0 or c.get_offset(side) != 0.0:
			return
	c.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	c.offset_left = UI_MARGIN
	c.offset_right = UI_MARGIN + BAG_SIZE.x
	c.offset_top = -UI_MARGIN - BAG_SIZE.y
	c.offset_bottom = -UI_MARGIN
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN


# Only count player nodes in THIS scene, not whatever else the editor has loaded.
func _has_player(root: Node) -> bool:
	for n in root.get_tree().get_nodes_in_group("player"):
		if n == root or root.is_ancestor_of(n):
			return true
	return false


func _on_make_player() -> void:
	var sel := EditorInterface.get_selection().get_selected_nodes()
	if sel.is_empty():
		_say("Select your player node first.", WARN_COLOR)
		return
	var n: Node = sel[0]
	n.add_to_group("player", true)  # persistent, so it's saved with the scene
	EditorInterface.mark_scene_as_unsaved()
	_say("%s is now the player." % n.name, OK_COLOR)


# ---- items ---------------------------------------------------------------

func _on_new_item() -> void:
	var path := make_item()
	if path == "":
		_say("Couldn't write a new item into %s." % ITEM_DIR, ERR_COLOR)
		return
	EditorInterface.get_resource_filesystem().update_file(path)
	_refresh_items()
	var idx := _item_paths.find(path)
	if idx >= 0:
		_item_pick.select(idx)
	EditorInterface.edit_resource(load(path))
	_say("Made %s. Name it and pick an icon in the Inspector." % path, OK_COLOR)


# The buyer's own items first, then the demo's as examples. Only this pack's
# items: the pickup's item slot takes nothing else.
func _refresh_items() -> void:
	var keep := ""
	var cur := _item_pick.get_selected()
	if cur >= 0 and cur < _item_paths.size():
		keep = _item_paths[cur]
	_item_pick.clear()
	_item_paths = _scan_items(ITEM_DIR)
	for d: String in DEMO_ITEM_DIRS:
		if DirAccess.dir_exists_absolute(d):
			_item_paths.append_array(_scan_items(d))
			break
	for p in _item_paths:
		# marked the way Loot (Lite) and Inventory Pro mark theirs, so a demo item
		# isn't mistaken for one of yours
		var tag := "" if p.begins_with(ITEM_DIR + "/") else "  (example)"
		_item_pick.add_item(_item_name(load(p)) + tag)
	var idx := _item_paths.find(keep)
	if idx >= 0:
		_item_pick.select(idx)


func _scan_items(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	var script: Script = load(ITEM_SCRIPT)
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.get_extension() == "tres":
			var res := load(dir_path.path_join(f))
			if res != null and res.get_script() == script:
				out.append(dir_path.path_join(f))
		f = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


func _on_shown() -> void:
	if is_visible_in_tree() and _pickup_box.visible:
		_refresh_items()


func _selected_item() -> Resource:
	var idx := _item_pick.get_selected()
	if idx < 0 or idx >= _item_paths.size():
		return null
	return load(_item_paths[idx])


func _item_name(item: Resource) -> String:
	if item == null:
		return "(item)"
	for prop in ["name", "id"]:
		var v: Variant = item.get(prop)
		if v != null and str(v) != "":
			return str(v)
	return item.resource_path.get_file().get_basename()


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
	l.modulate = Color(0.8, 0.85, 0.95)
	return l


func _lbl(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(60, 0)
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


# A file written into a folder made this session isn't in the editor's file list
# yet, so its UID stayed unknown and the first Play of a scene using it warned
# "invalid UID" (a yellow Debugger badge). Register it the moment it's written.
static func _register_uid(path: String) -> void:
	var uid := ResourceLoader.get_resource_uid(path)
	if uid != ResourceUID.INVALID_ID and not ResourceUID.has_id(uid):
		ResourceUID.add_id(uid, path)
