@tool
extends Control

# The "chooser" panel: pick what you want for YOUR game, pick WHERE, hit Apply —
# it drops the Lite stats component onto your node, baked into your .tscn and still
# editable in the Inspector (or re-pick and Apply again; it updates in place, never
# duplicates). The sibling "Stats — Lite" tab is the resource authoring (StatSets).
#
# LITE SCOPE: player stats (plus a plain stats list on C), enemy stats, and
# pickups that boost a stat. No skill-tree runtime, no XP/level wiring, no
# EventTrigger: those are Pro. Where Pro would auto-wire, we show one honest line.

const COMPONENT_SCRIPT := "res://addons/stats_skills_lite/stats_component_lite.gd"
const DEF_SCRIPT := "res://addons/stats_skills_lite/stat_definition_lite.gd"
const LIST_SCRIPT := "res://addons/stats_skills_lite/stats_list_lite.gd"
const PICKUP_SCRIPT := "res://addons/stats_skills_lite/stat_pickup_lite.gd"
const TOGGLE_ACTION := "character"  # C, shared with the paper doll
const AREA_NAME := "PickupArea"
const NO_PLAYER := "Nothing in this scene is marked as the player yet, so this won't react to anything. Select your player node and press \"Make the selected node the player\"."
const UPGRADE_URL := "https://selodev.itch.io/stats-skill-trees-no-code-character-progression-for-godot-4"

const OK_COLOR := Color(0.55, 0.9, 0.55)
const ERR_COLOR := Color(0.95, 0.55, 0.55)
const WARN_COLOR := Color(0.95, 0.8, 0.35)

enum Scope { SELECTED, SCENE_ROOT }

# Starter stat sets baked into a new component so it works the moment it lands.
# id -> Array of {id, name, base, min, max}. Buyers re-tune these in the Inspector
# or author their own in the "Stats — Lite" tab.
const STARTERS := {
	"player": [
		{"id": "health", "name": "Health", "base": 100.0, "min": 0.0, "max": 100.0},
		{"id": "attack", "name": "Attack", "base": 10.0, "min": 0.0, "max": 1.0e9},
		{"id": "defense", "name": "Defense", "base": 5.0, "min": 0.0, "max": 1.0e9},
	],
	"enemy": [
		{"id": "health", "name": "Health", "base": 30.0, "min": 0.0, "max": 30.0},
		{"id": "attack", "name": "Attack", "base": 6.0, "min": 0.0, "max": 1.0e9},
	],
	"blank": [],
}

var _chosen := ""
var _buttons := {}
var _scope: OptionButton
var _status: Label
var _boost_box: VBoxContainer
var _stat_pick: OptionButton
var _amount: SpinBox
var _duration: SpinBox


func _ready() -> void:
	name = "Stats · Setup"
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

	root.add_child(_h("1.  What do you want to add?"))
	var col := VBoxContainer.new()
	root.add_child(col)
	_add_choice(col, "player", "Player stats (health, attack, defense)")
	_add_choice(col, "enemy", "Enemy stats (health, attack)")
	_add_choice(col, "blank", "Empty stats component (author your own)")
	_add_choice(col, "boost", "Boost a stat when the player touches this")

	# only shown for the boost
	_boost_box = VBoxContainer.new()
	_boost_box.visible = false
	root.add_child(_boost_box)
	var stat_row := HBoxContainer.new()
	_boost_box.add_child(stat_row)
	stat_row.add_child(_h("Stat"))
	_stat_pick = OptionButton.new()
	# its longest entry used to set the width of the whole tab; the open list still shows every name in full
	_stat_pick.fit_to_longest_item = false
	_stat_pick.clip_text = true
	_stat_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stat_row.add_child(_stat_pick)
	# the player's stats as they are now, each time the list opens
	_stat_pick.get_popup().about_to_popup.connect(_refresh_stat_choices)
	var amount_row := HBoxContainer.new()
	_boost_box.add_child(amount_row)
	amount_row.add_child(_h("Amount"))
	_amount = SpinBox.new()
	_amount.min_value = -9999
	_amount.max_value = 9999
	_amount.value = 5
	_amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	amount_row.add_child(_amount)
	var time_row := VBoxContainer.new()  # its label is too long to share a line with the box
	_boost_box.add_child(time_row)
	time_row.add_child(_h("For (seconds, 0 = for good)"))
	_duration = SpinBox.new()
	_duration.min_value = 0
	_duration.max_value = 3600
	_duration.value = 0
	_duration.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_row.add_child(_duration)

	root.add_child(_h("2.  Where should it go?"))
	_scope = OptionButton.new()
	_scope.add_item("The selected node", Scope.SELECTED)
	_scope.add_item("This scene's root", Scope.SCENE_ROOT)
	root.add_child(_scope)

	var row := HBoxContainer.new()
	root.add_child(row)
	row.add_child(_btn("Apply", _on_apply, true))
	row.add_child(_btn("Author stats…", _on_customize))

	# boosts only react to the "player" group, and only Player stats sets it
	# on a row of its own, so on a narrow dock it wraps its label instead of widening the tab
	var mk := _btn("Make the selected node the player", _on_make_player)
	mk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mk.tooltip_text = "Touch triggers, doors, zones and enemies only react to the node in the \"player\" group."
	root.add_child(mk)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

	root.add_child(HSeparator.new())
	var note := Label.new()
	note.text = "It's your game. Change it any time: re-pick and Apply (it updates in place), or tweak the component in the Inspector. Author custom stat sets in the 'Stats (Lite)' tab."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.72, 0.75, 0.82)
	root.add_child(note)

	# Honest Pro line: what the paid tier adds on top.
	var up := Label.new()
	up.text = "🔒 Pro adds skill trees, XP and levels, enemies that grant XP when they die, a styled stats panel with breakdowns, equipment bonuses and saving."
	up.modulate = Color(0.85, 0.8, 0.55)
	up.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(up)


# As wide as what's in it and no wider. The old fixed width pushed a laptop's
# default dock (270 px) wider whenever this tab was open.
func _get_minimum_size() -> Vector2:
	if get_child_count() == 0 or not (get_child(0) is Control):
		return Vector2.ZERO
	return Vector2((get_child(0) as Control).get_combined_minimum_size().x, 0.0)


# ---- pick ----------------------------------------------------------------

func _add_choice(parent: Node, id: String, label: String) -> void:
	var b := Button.new()
	b.text = label
	b.toggle_mode = true
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.pressed.connect(_on_pick.bind(id))
	parent.add_child(b)
	_buttons[id] = b


func _on_pick(id: String) -> void:
	_chosen = id
	for k in _buttons.keys():
		_buttons[k].button_pressed = (k == id)
	_boost_box.visible = id == "boost"
	if id == "boost":
		var from_starter := _refresh_stat_choices()
		var note := " Your player's stats aren't in this scene, so these are the Player stats starter's." if from_starter else ""
		_say("Picked the boost. Pick a stat and an amount, select the pickup, then Apply.%s" % note, OK_COLOR)
		return
	_say("Picked %s. Choose where, then Apply." % _pretty(id), OK_COLOR)


# ---- apply (re-entrant) --------------------------------------------------

func _on_apply() -> void:
	if _chosen == "":
		_say("Pick what to add first.", WARN_COLOR)
		return
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		_say("Open a scene first (Scene → New/Open).", ERR_COLOR)
		return
	var target: Node = root
	if _scope.get_selected_id() == Scope.SELECTED:
		var sel := EditorInterface.get_selection().get_selected_nodes()
		if sel.is_empty():
			_say("Select a node in the scene tree first, or pick 'This scene's root'.", WARN_COLOR)
			return
		target = _host_of(sel[0], root)
	if _chosen == "boost":
		_apply_boost(root, target)
		return
	var comp := wire_stats(root, target, _chosen)
	_select(comp)
	var tagged := " and marked it as the player" if _chosen == "player" else ""
	var list_note := ""
	if _chosen == "player":
		list_note = " A stats list sits on the left, under the HUD. It starts hidden: press %s in the game to open it." % action_keys(TOGGLE_ACTION)
	_say("Added a stats component to %s (%s)%s. Tweak its definitions in the Inspector, or re-pick here.%s" % [target.name, _pretty(_chosen), tagged, list_note], OK_COLOR)


func _apply_boost(root: Node, target: Node) -> void:
	_refresh_stat_choices()
	var sid := _picked_stat()
	if sid == "":
		_say("Pick a stat to boost first.", WARN_COLOR)
		return
	# it removes what it sits on when touched, so never the player itself
	if target.is_in_group("player"):
		_say("\"%s\" is the player. Select the pickup (a potion, a shrine) instead." % target.name, WARN_COLOR)
		return
	# where the player has to walk, worked out before Apply adds a PickupArea
	var zone := "\"%s\"" % target.name if _is_touch_ready(target) else "the PickupArea around \"%s\"" % target.name
	var p := wire_pickup(root, target, sid, _amount.value, _duration.value)
	_select(p)
	var what := "%s%s %s" % ["+" if _amount.value >= 0.0 else "-", _num(absf(_amount.value)), _stat_pick.get_item_text(_stat_pick.selected)]
	var how_long := " for %s seconds" % _num(_duration.value) if _duration.value > 0.0 else " for good"
	var note := no_player_note(root)
	_say("\"%s\" gives the player %s%s when they walk into %s, then disappears (tick Stay in the Inspector to keep it).%s" % [target.name, what, how_long, zone, note], WARN_COLOR if note != "" else OK_COLOR)


func _on_make_player() -> void:
	var sel := EditorInterface.get_selection().get_selected_nodes()
	if sel.is_empty():
		_say("Select your player node first.", WARN_COLOR)
		return
	var n: Node = sel[0]
	n.add_to_group("player", true)  # persistent, so the group saves with the scene
	EditorInterface.mark_scene_as_unsaved()
	_say("%s is now the player." % n.name, OK_COLOR)


# --- pure wiring (no EditorInterface, so it's headless-testable) -----------
# Re-entrant: reuses an existing component on the target rather than duplicating.

func wire_stats(root: Node, target: Node, starter: String) -> Node:
	var comp := _ensure(root, target, "StatsComponentLite", COMPONENT_SCRIPT)
	comp.set("definitions", _build_defs(STARTERS.get(starter, [])))
	# Touch triggers, doors and enemies look for the "player" group; persistent so
	# it saves with the scene.
	if starter == "player":
		target.add_to_group("player", true)
		# and the player gets a list to see them in game, on C
		wire_stats_list(root)
		ensure_character_action()
	return comp


# One StatsListLite per scene, left under the HUD, hidden until C.
func wire_stats_list(root: Node) -> Node:
	var list := _find_script(root, root, LIST_SCRIPT)
	if list != null:
		_place(list, 16, 80, 276, 330)
		return list
	list = _inert(load(LIST_SCRIPT))
	list.name = "StatsList"
	list.set("visible", false)  # opens with the key, like the other packs' panels
	_place(list, 16, 80, 276, 330)
	_ui_layer(root).add_child(list, true)
	list.owner = root
	return list


# A pickup on `target` that gives stat_id +amount, for `duration` seconds (0 =
# for good). Re-entrant: reuses the StatPickup (and PickupArea) already there.
func wire_pickup(root: Node, target: Node, stat_id: String, amount: float, duration: float) -> Node:
	_touch_area(root, target)
	var p: Node = null
	for c in target.get_children():
		if c.owner == root and c.get_script() != null and c.get_script().resource_path == PICKUP_SCRIPT:
			p = c
			break
	var fresh := p == null
	if fresh:
		p = _inert(load(PICKUP_SCRIPT))
		p.name = "StatPickup"
	p.set("stat_id", stat_id)
	p.set("amount", amount)
	p.set("duration", maxf(0.0, duration))
	if fresh:
		target.add_child(p, true)
		p.owner = root
	return p


# The character input action, on C. A binding the project already has is left
# alone. Safe from a test: save=false only touches the in-memory ProjectSettings,
# and even save=true only writes project.godot from inside the editor (a headless
# save rewrites its engine version line).
func ensure_character_action(save := true) -> void:
	var key := "input/" + TOGGLE_ACTION
	if ProjectSettings.has_setting(key):
		return
	var c := InputEventKey.new()
	c.physical_keycode = KEY_C
	# every device, like the Input Map editor stores it. A new InputEventKey is
	# device 0 on 4.5 but 16 (the keyboard id) on 4.7, and a key saved with one
	# never matches presses on the other.
	c.device = -1
	ProjectSettings.set_setting(key, {"deadzone": 0.5, "events": [c]})
	if save and Engine.is_editor_hint():
		ProjectSettings.save()


# The key(s) an action is bound to, for the status line ("C").
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


# The stats on whatever this scene marks as the player, as [{id, name}]. Empty
# when there's no player with stats in it.
func player_stat_rows(root: Node) -> Array:
	var out: Array = []
	if not root.is_inside_tree():
		return out
	for n in root.get_tree().get_nodes_in_group("player"):
		if not (n == root or root.is_ancestor_of(n)):
			continue
		var comp := _find_script(n, root, COMPONENT_SCRIPT, false)
		if comp == null:
			continue
		for d in comp.get("definitions"):
			if d != null and str(d.id) != "":
				out.append({"id": str(d.id), "name": str(d.display_name) if str(d.display_name) != "" else str(d.id).capitalize()})
		return out
	return out


# Fills the stat dropdown. Returns true when it fell back to the starter's stats.
func _refresh_stat_choices() -> bool:
	var keep := _picked_stat()
	var root := EditorInterface.get_edited_scene_root()
	var rows: Array = player_stat_rows(root) if root != null else []
	var from_starter := rows.is_empty()
	if from_starter:
		for r in STARTERS["player"]:
			rows.append({"id": r["id"], "name": r["name"]})
	_stat_pick.clear()
	for r in rows:
		_stat_pick.add_item(str(r["name"]))
		_stat_pick.set_item_metadata(_stat_pick.item_count - 1, str(r["id"]))
		if str(r["id"]) == keep:
			_stat_pick.select(_stat_pick.item_count - 1)
	return from_starter


func _picked_stat() -> String:
	if _stat_pick == null or _stat_pick.selected < 0:
		return ""
	return str(_stat_pick.get_item_metadata(_stat_pick.selected))


# Touch listens to an Area's body_entered, so on a sprite or a body it never
# fired. Your own Area with a shape works as is; anything else gets a PickupArea.
func _touch_area(root: Node, target: Node) -> Node:
	if _is_touch_ready(target):
		return target
	for c in target.get_children():
		if c.name == AREA_NAME and (c is Area2D or c is Area3D) and c.owner == root:
			return c  # from an earlier Apply
	var area: Node
	var shape: Node
	if target is Node3D or (not (target is Node2D) and root is Node3D):
		area = Area3D.new()
		var s3 := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 1.0
		s3.shape = sphere
		shape = s3
	else:
		area = Area2D.new()
		var s2 := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 24.0
		s2.shape = circle
		shape = s2
	area.name = AREA_NAME
	target.add_child(area, true)
	area.owner = root
	shape.name = "CollisionShape"
	area.add_child(shape, true)
	shape.owner = root
	return area


# An Area that already has a shape to touch. An Area with no shape never
# reports a body entering, so it gets a PickupArea like anything else.
func _is_touch_ready(node: Node) -> bool:
	if not (node is Area2D or node is Area3D):
		return false
	for c in node.get_children():
		if (c is CollisionShape2D or c is CollisionShape3D) and c.get("shape") != null:
			return true
		if (c is CollisionPolygon2D or c is CollisionPolygon3D) and c.get("polygon").size() > 0:
			return true
	return false


# Only nodes in this scene count: the editor's tree holds more than the scene.
func no_player_note(root: Node) -> String:
	if not root.is_inside_tree():
		return ""
	for n in root.get_tree().get_nodes_in_group("player"):
		if n == root or root.is_ancestor_of(n):
			return ""
	return " " + NO_PLAYER


# The CanvasLayer our UI goes in, so it stays on screen when a camera moves.
func _ui_layer(root: Node) -> Node:
	for c in root.get_children():
		if c is CanvasLayer and c.owner == root and String(c.name) == "UILayer":
			return c
	var layer := CanvasLayer.new()
	layer.name = "UILayer"
	root.add_child(layer, true)
	layer.owner = root
	return layer


# Pin it top left where Play shows it. One the buyer already moved stays put.
func _place(c: Node, l: float, t: float, r: float, b: float) -> void:
	if not (c is Control):
		return
	var ctl: Control = c
	if not _unplaced(ctl):
		return
	ctl.set_anchors_preset(Control.PRESET_TOP_LEFT)
	ctl.offset_left = l
	ctl.offset_top = t
	ctl.offset_right = r
	ctl.offset_bottom = b


func _unplaced(c: Control) -> bool:
	if c.size.x < 1.0 or c.size.y < 1.0:
		return true
	return c.anchor_left == 0.0 and c.anchor_top == 0.0 and c.anchor_right == 0.0 and c.anchor_bottom == 0.0 \
		and c.offset_left == 0.0 and c.offset_top == 0.0 and c.offset_right == 0.0 and c.offset_bottom == 0.0


# Apply selects the node it made, so a second Apply straight after would land
# inside it (and tag a component as the player). Step up to the node it sits on.
func _host_of(n: Node, root: Node) -> Node:
	while n != root and n.get_parent() != null and (_is_ours(n) or String(n.name) == AREA_NAME \
			or String(n.get_parent().name) == AREA_NAME):
		n = n.get_parent()
	return n


func _is_ours(n: Node) -> bool:
	var scr: Script = n.get_script()
	return scr != null and scr.resource_path in [COMPONENT_SCRIPT, PICKUP_SCRIPT]


# First owned node under `node` (itself too) running `script_path`.
func _find_script(node: Node, root: Node, script_path: String, owned := true) -> Node:
	if (not owned or node == root or node.owner == root) and node.get_script() != null \
			and node.get_script().resource_path == script_path:
		return node
	for c in node.get_children():
		var f := _find_script(c, root, script_path, owned)
		if f != null:
			return f
	return null


# Build a typed Array[StatDefinitionLite] from a starter table. A plain Array
# won't assign to the typed @export, so build the typed array explicitly.
func _build_defs(rows: Array) -> Array:
	var def_script: Script = load(DEF_SCRIPT)
	var out: Array[StatDefinitionLite] = []
	for r in rows:
		var d: StatDefinitionLite = def_script.new()
		d.id = String(r["id"])
		d.display_name = String(r["name"])
		d.base_value = float(r["base"])
		d.min_value = float(r["min"])
		d.max_value = float(r["max"])
		out.append(d)
	return out


# ---- customize -----------------------------------------------------------

func _on_customize() -> void:
	_say("Open the 'Stats (Lite)' tab to author your own stat sets, then Apply here or wire them in the Inspector.", OK_COLOR)


# ---- helpers -------------------------------------------------------------

func _ensure(root: Node, target: Node, cls: String, script_path: String) -> Node:
	var found := _find(root, target, cls)
	if found != null:
		return found  # re-entrant: reuse the existing one, never duplicate
	var n := _inert(load(script_path))
	n.name = "StatsLite"
	target.add_child(n, true)
	n.owner = root  # bakes into the buyer's .tscn
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
# serialize into the buyer's scene, so we'd silently no-op. Only the target's
# own children: searching its whole subtree let enemy stats applied to the scene
# root overwrite the player's component further down.
func _find(root: Node, target: Node, cls: String) -> Node:
	for c in target.get_children():
		if (c == root or c.owner == root) and _is_cls(c, cls):
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


func _num(v: float) -> String:
	return str(int(roundf(v))) if is_equal_approx(v, roundf(v)) else String.num(v, 2)


func _pretty(id: String) -> String:
	if id == "boost":
		return "Boost a stat when the player touches this"
	return id.replace("_", " ").capitalize()


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
