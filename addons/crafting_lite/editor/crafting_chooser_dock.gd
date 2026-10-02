@tool
extends Control

# The "chooser" panel: a non-coder picks what crafting they want for THEIR game,
# picks WHERE it goes, and hits Apply — the panel drops a CraftingLite component
# into their own scene. Nothing here is a one-way street: re-pick and Apply again
# (it updates in place, never duplicates), or tweak the dropped node in the
# Inspector. The sibling "Recipes — Lite" tab authors the recipes it crafts.
#
# Each outcome also adds a plain CraftPanel: a bench's opens when the player walks
# up to it, crafting anywhere toggles with B. It crafts from the player's bag on
# Play. We show an honest one-line note on what Pro adds, never a nag.

const CRAFTING_SCRIPT := "res://addons/crafting_lite/crafting_lite.gd"
const PANEL_SCRIPT := "res://addons/crafting_lite/craft_panel_lite.gd"
const RECIPE_SCRIPT := preload("res://addons/crafting_lite/recipe.gd")
const RECIPE_DIR := "res://recipes"  # where the Recipes (Lite) tab saves recipes
const UPGRADE_URL := "https://selodev.itch.io/godot-crafting-system"
const CRAFT_AREA := "CraftArea"
const CRAFT_ACTION := "crafting"

const OK_COLOR := Color(0.55, 0.9, 0.55)
const ERR_COLOR := Color(0.95, 0.55, 0.55)
const WARN_COLOR := Color(0.95, 0.8, 0.35)
const NO_PLAYER := "Nothing in this scene is marked as the player yet, so this won't react to anything. Select your player node and press \"Make the selected node the player\"."

enum Scope { SELECTED, THIS_SCENE }

# Each outcome bakes in the same CraftingLite node — the difference is intent, so
# the buyer lands on the right mental model (a station vs. the player). The Pro
# note tells the truth about what Pro adds for that outcome.
const OUTCOMES := {
	"bench": {
		"label": "A crafting bench",
		"pro": "Pro adds a styled recipe browser with icons, timed crafts with a queue, and a station id so each bench crafts only its own recipes.",
	},
	"anywhere": {
		"label": "Player crafts anywhere",
		"pro": "Pro adds a styled recipe browser with icons, timed crafts with a queue, shaped grid recipes and recipe unlocks.",
	},
}

var _chosen := ""
var _buttons := {}
var _scope: OptionButton
var _pro_note: Label
var _status: Label


func _ready() -> void:
	name = "Crafting · Setup"
	custom_minimum_size = Vector2(0, 380)
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

	root.add_child(_h("1.  What crafting do you want?"))
	for id in OUTCOMES.keys():
		var b := Button.new()
		b.text = OUTCOMES[id]["label"]
		b.toggle_mode = true
		b.pressed.connect(_on_pick.bind(id))
		root.add_child(b)
		_buttons[id] = b

	root.add_child(_h("2.  Where should it go?"))
	_scope = OptionButton.new()
	_scope.add_item("The selected node", Scope.SELECTED)
	_scope.add_item("This scene's root", Scope.THIS_SCENE)
	root.add_child(_scope)

	var row := HBoxContainer.new()
	root.add_child(row)
	row.add_child(_btn("Apply", _on_apply, true))
	row.add_child(_btn("Author recipes…", _on_author))

	# a bench's panel only opens for the "player" group, and nothing else sets it
	# on a row of its own, so on a narrow dock it wraps its label instead of widening the tab
	var mk := _btn("Make the selected node the player", _on_make_player)
	mk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mk.tooltip_text = "Touch triggers, doors, zones and enemies only react to the node in the \"player\" group."
	root.add_child(mk)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

	# Honest funnel: what Pro adds on top of the picked outcome.
	_pro_note = Label.new()
	_pro_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pro_note.modulate = Color(0.85, 0.8, 0.55)
	root.add_child(_pro_note)

	root.add_child(HSeparator.new())
	var note := Label.new()
	note.text = "It's your game. Change it any time: re-pick and Apply, or tweak the node in the Inspector. Author the recipes it crafts in the Recipes (Lite) tab, then Apply again to hand them over. On Play it crafts from the player's bag."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.72, 0.75, 0.82)
	root.add_child(note)


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
	_pro_note.text = "🔒 " + OUTCOMES[id]["pro"]
	_say("Picked \"%s\". Choose where, then Apply." % OUTCOMES[id]["label"], OK_COLOR)


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
		if sel.is_empty():
			_say("Select a node in the scene first (or pick \"This scene's root\").", WARN_COLOR)
			return
		target = _host_of(sel[0], root)
	var comp := wire_crafting(root, target)
	var mine := _scan_recipes(RECIPE_DIR)
	wire_recipes(comp, mine)
	var bench := _chosen == "bench"
	var tagged := not bench and tag_player(root, target)
	wire_panel(root, comp, bench)
	if not bench:
		ensure_crafting_action()
	_select(comp)
	var recipes := "It has the %d recipe%s from %s." % [mine.size(), "" if mine.size() == 1 else "s", RECIPE_DIR] if not mine.is_empty() \
		else "No recipes in %s yet: author them in the Recipes (Lite) tab, then Apply again." % RECIPE_DIR
	var who := " Marked \"%s\" as the player." % target.name if tagged else ""
	var how: String
	if bench:
		how = "A CraftPanel sits top centre, hidden, and opens when the player walks into %s. Walking away or Close shuts it." % ("\"%s\"" % target.name if _touchable(target) else "its CraftArea")
	else:
		how = "A CraftPanel sits top centre, hidden: press %s in the game to open or close it." % action_keys(CRAFT_ACTION)
	# both find the player's bag on Play, and a bench needs someone to walk up
	var note := _no_player_note(root) + _bag_gap(root, comp)
	_say("Added crafting to \"%s\". %s%s %s%s" % [target.name, how, who, recipes, note], OK_COLOR if not mine.is_empty() and note == "" else WARN_COLOR)


# --- pure wiring (no EditorInterface, so it's headless-testable) -----------
# Re-entrant: reuses an existing CraftingLite under the target rather than
# duplicating. The node is owned by the SCENE ROOT so it bakes into the .tscn.

func wire_crafting(root: Node, target: Node) -> Node:
	return _ensure(root, target, "CraftingLite", CRAFTING_SCRIPT)


# Hands the component every recipe in res://recipes. Ones you added by hand from
# other folders stay; ones deleted from res://recipes drop out. Returns the count.
func wire_recipes(comp: Node, mine: Array) -> int:
	var out: Array = []
	for r in comp.get("recipes"):
		if r == null or (r is Resource and r.resource_path.begins_with(RECIPE_DIR + "/")):
			continue
		out.append(r)
	for r in mine:
		if not out.has(r):
			out.append(r)
	comp.set("recipes", out)
	return out.size()


# The on-screen window: one CraftPanel per crafting node, on the scene's UI layer,
# found again by the crafting it shows. A bench's opens when the player walks into
# its area; crafting anywhere toggles with the crafting action (B) instead.
func wire_panel(root: Node, comp: Node, walk_up: bool) -> Node:
	var host := comp.get_parent()
	var panel := _find_panel(root, root, comp)
	if panel == null:
		var layer := _ui_layer(root)
		panel = _inert(load(PANEL_SCRIPT))
		# the first keeps the plain name, more get their bench's in front
		panel.name = "CraftPanel" if layer.get_node_or_null(^"CraftPanel") == null else "%sCraftPanel" % host.name
		panel.set("visible", false)  # before it enters, so it never tries to open empty
		layer.add_child(panel, true)
		panel.owner = root
	panel.set("visible", false)  # starts hidden
	panel.set("crafting_path", panel.get_path_to(comp))
	if walk_up:
		panel.set("area_path", panel.get_path_to(_touch_area(root, host)))
		panel.set("toggle_action", &"")
	else:
		panel.set("area_path", NodePath(""))
		panel.set("toggle_action", StringName(CRAFT_ACTION))
	_place_panel(panel as Control)
	return panel


# What the player walks up to: the bench itself when it's an area with a shape
# already, else a CraftArea on it (made once, 2D or 3D to match), so it moves with
# the bench. An area with no shape can't be walked into.
func _touch_area(root: Node, host: Node) -> Node:
	if _touchable(host):
		return host
	for c in host.get_children():
		if c.name == CRAFT_AREA and (c is Area2D or c is Area3D) and c.owner == root:
			return c
	var area: Node
	var shape: Node
	if host is Node3D or (not (host is Node2D) and root is Node3D):
		area = Area3D.new()
		var s3 := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 2.0  # a couple of metres: walk up and it opens
		s3.shape = sphere
		shape = s3
	else:
		area = Area2D.new()
		var s2 := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 64.0
		s2.shape = circle
		shape = s2
	area.name = CRAFT_AREA
	host.add_child(area, true)
	area.owner = root
	shape.name = "CollisionShape"
	area.add_child(shape, true)
	shape.owner = root
	return area


func _touchable(n: Node) -> bool:
	if not (n is Area2D or n is Area3D):
		return false
	for c in n.get_children():
		if c is CollisionShape2D or c is CollisionPolygon2D or c is CollisionShape3D or c is CollisionPolygon3D:
			return true
	return false


# The owned CraftPanel already showing this crafting node, if any.
func _find_panel(node: Node, root: Node, comp: Node) -> Node:
	if (node == root or node.owner == root) and _is_cls(node, "CraftPanelLite"):
		var p: Variant = node.get("crafting_path")
		if p is NodePath and p != NodePath("") and node.get_node_or_null(p) == comp:
			return node
	for c in node.get_children():
		var f := _find_panel(c, root, comp)
		if f != null:
			return f
	return null


# An owned CanvasLayer for the panel, so it draws over the level. Exactly
# CanvasLayer: a ParallaxBackground is one too, but it draws behind the game.
func _ui_layer(root: Node) -> Node:
	var found := _find_plain_layer(root, root)
	if found != null:
		return found
	var layer := CanvasLayer.new()
	layer.name = "UILayer"
	root.add_child(layer, true)
	layer.owner = root
	return layer


func _find_plain_layer(node: Node, root: Node) -> Node:
	if node.get_class() == "CanvasLayer" and (node == root or node.owner == root):
		return node
	for c in node.get_children():
		var f := _find_plain_layer(c, root)
		if f != null:
			return f
	return null


# Top centre, 320x300: the left and right edges belong to the HUD, bag, paper
# doll and quest log, and the shop opens in the lower middle. Only while it's
# unplaced, so a spot you picked survives a re-Apply.
func _place_panel(c: Control) -> void:
	if c.anchor_left != 0.0 or c.anchor_top != 0.0 or c.anchor_right != 0.0 or c.anchor_bottom != 0.0 \
			or c.offset_left != 0.0 or c.offset_top != 0.0 or c.offset_right != 0.0 or c.offset_bottom != 0.0:
		return
	c.set_anchors_preset(Control.PRESET_CENTER_TOP)
	c.offset_left = -160.0
	c.offset_right = 160.0
	c.offset_top = 16.0
	c.offset_bottom = 316.0


# The crafting input action, on B. A binding the project already has is left
# alone. save=false only touches the in-memory settings (for tests), and even
# save=true only writes project.godot from inside the editor.
func ensure_crafting_action(save := true) -> void:
	var key := "input/" + CRAFT_ACTION
	if ProjectSettings.has_setting(key):
		return
	var b := InputEventKey.new()
	b.physical_keycode = KEY_B
	# every device, like the Input Map editor stores it: a new InputEventKey is
	# device 0 on 4.5 but 16 on 4.7, and one saved with either misses the other
	b.device = -1
	ProjectSettings.set_setting(key, {"deadzone": 0.5, "events": [b]})
	if save and Engine.is_editor_hint():
		ProjectSettings.save()


# The key(s) an action is bound to, for the status line ("B").
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


# Apply selects the component it made, so a second Apply straight after would
# land inside it. Step up to the node it sits on, the one you meant.
# Also keeps the player tag off the component itself. A selected CraftPanel or
# CraftArea means its crafting node too.
func _host_of(n: Node, root: Node) -> Node:
	if _is_cls(n, "CraftPanelLite"):
		var c: Node = n.get_node_or_null(n.get("crafting_path")) if n.get("crafting_path") is NodePath else null
		if c != null and c.get_parent() != null:
			n = c
	elif n != root and n.name == CRAFT_AREA and (n is Area2D or n is Area3D):
		n = n.get_parent()
	while n != root and _is_cls(n, "CraftingLite"):
		n = n.get_parent()
	return n


# Crafting on the player: tag it so touch triggers and zones from other packs find
# it. Not a level's root though, that's where it lands with "This scene's root".
func tag_player(root: Node, target: Node) -> bool:
	if target == root and not (target is CollisionObject2D or target is CollisionObject3D):
		return false
	target.add_to_group("player", true)  # persistent, so it saves with the scene
	return true


# ---- author hand-off -----------------------------------------------------

func _on_author() -> void:
	# The Recipes — Lite tab is the sibling; nudge them there for recipe CRUD.
	_say("Open the \"Recipes (Lite)\" tab to author the recipes this crafts, then Apply again to hand them over.", OK_COLOR)


# ---- helpers -------------------------------------------------------------

func _scan_recipes(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.get_extension() == "tres":
			var res := load(dir_path.path_join(f))
			if res != null and res.get_script() == RECIPE_SCRIPT:
				out.append(res)
		f = dir.get_next()
	dir.list_dir_end()
	return out


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


# Re-entrancy search: the target's own children only, and only ones THIS scene
# owns. A parent (a "Town") gets crafting of its own instead of taking over its
# Forge's, and one inside an instanced child scene (owner != root) wouldn't
# serialize into the buyer's scene anyway.
func _find(node: Node, root: Node, cls: String) -> Node:
	for c in node.get_children():
		if c.owner == root and _is_cls(c, cls):
			return c
	return null


func _is_cls(node: Node, cls: String) -> bool:
	if node.is_class(cls):
		return true  # native class
	var scr := node.get_script()
	return scr != null and scr.get_global_name() == cls  # class_name script


func _select(n: Node) -> void:
	# Apply adds nodes without the undo manager, so the editor never flags the scene
	# and Play would run the saved file without them. Flag it by hand.
	EditorInterface.mark_scene_as_unsaved()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(n)
	EditorInterface.edit_node(n)


func _on_make_player() -> void:
	var sel := EditorInterface.get_selection().get_selected_nodes()
	if sel.is_empty():
		_say("Select your player node first.", WARN_COLOR)
		return
	var n: Node = sel[0]
	n.add_to_group("player", true)  # persistent, so the group saves with the scene
	EditorInterface.mark_scene_as_unsaved()
	_say("%s is now the player." % n.name, OK_COLOR)


# Only nodes in this scene count: the editor's tree holds more than the scene.
func _scene_player(root: Node) -> Node:
	if not root.is_inside_tree():
		return null
	for n in root.get_tree().get_nodes_in_group("player"):
		if n == root or root.is_ancestor_of(n):
			return n
	return null


func _no_player_note(root: Node) -> String:
	return " " + NO_PLAYER if root.is_inside_tree() and _scene_player(root) == null else ""


# Said while there's still time to add one: the panel crafts from the player's bag.
func _bag_gap(root: Node, comp: Node) -> String:
	var p: Variant = comp.get("inventory_path")
	if p is NodePath and p != NodePath("") and comp.get_node_or_null(p) != null:
		return ""  # pointed at a bag by hand
	var player := _scene_player(root)
	if player == null or _find_bag(player, root) != null:
		return ""
	return " \"%s\" has no bag yet, so there's nothing to craft from: add one (the Setup tab of Inventory (Lite) does it)." % player.name


# Duck-typed, the way the crafting finds it at runtime. Scripts are inert in the
# editor but still answer has_method.
func _find_bag(node: Node, root: Node) -> Node:
	if (node == root or node.owner == root) and node.has_method("add_item") \
			and node.has_method("remove_item") and node.has_method("count_item"):
		return node
	for c in node.get_children():
		var f := _find_bag(c, root)
		if f != null:
			return f
	return null


func _h(text: String) -> Label:
	var l := Label.new()
	l.text = text
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
