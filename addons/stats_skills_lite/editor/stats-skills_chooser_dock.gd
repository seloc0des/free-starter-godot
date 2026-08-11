@tool
extends Control

# The "chooser" panel: pick what you want for YOUR game, pick WHERE, hit Apply —
# it drops the Lite stats component onto your node, baked into your .tscn and still
# editable in the Inspector (or re-pick and Apply again; it updates in place, never
# duplicates). The sibling "Stats — Lite" tab is the resource authoring (StatSets).
#
# LITE SCOPE: outcomes only add the StatsComponentLite to a node. No skill-tree
# runtime, no XP/level wiring, no auto-bound UI, no EventTrigger — those are Pro.
# Where Pro would auto-wire, we show one honest line instead of a nag.

const COMPONENT_SCRIPT := "res://addons/stats_skills_lite/stats_component_lite.gd"
const DEF_SCRIPT := "res://addons/stats_skills_lite/stat_definition_lite.gd"
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


func _ready() -> void:
	name = "Stats · Setup"
	custom_minimum_size = Vector2(320, 420)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	root.add_child(_h("1.  What do you want to add?"))
	var col := VBoxContainer.new()
	root.add_child(col)
	_add_choice(col, "player", "Player stats (health, attack, defense)")
	_add_choice(col, "enemy", "Enemy stats (health, attack)")
	_add_choice(col, "blank", "Empty stats component (author your own)")

	root.add_child(_h("2.  Where should it go?"))
	_scope = OptionButton.new()
	_scope.add_item("The selected node", Scope.SELECTED)
	_scope.add_item("This scene's root", Scope.SCENE_ROOT)
	root.add_child(_scope)

	var row := HBoxContainer.new()
	root.add_child(row)
	row.add_child(_btn("Apply", _on_apply, true))
	row.add_child(_btn("Author stats…", _on_customize))

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

	root.add_child(HSeparator.new())
	var note := Label.new()
	note.text = "It's your game. Change it any time: re-pick and Apply (it updates in place), or tweak the component in the Inspector. Author custom stat sets in the 'Stats (Lite)' tab."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.72, 0.75, 0.82)
	root.add_child(note)

	# Honest Pro line — Lite only drops the component; wiring is the paid tier.
	var up := Label.new()
	up.text = "🔒 Pro unlocks no-code wiring: skill trees, XP/levels, enemies granting XP on death, bound StatsPanelUI, and the EventTrigger node."
	up.modulate = Color(0.85, 0.8, 0.55)
	up.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(up)


# ---- pick ----------------------------------------------------------------

func _add_choice(parent: Node, id: String, label: String) -> void:
	var b := Button.new()
	b.text = label
	b.toggle_mode = true
	b.pressed.connect(_on_pick.bind(id))
	parent.add_child(b)
	_buttons[id] = b


func _on_pick(id: String) -> void:
	_chosen = id
	for k in _buttons.keys():
		_buttons[k].button_pressed = (k == id)
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
		target = sel[0]
	var comp := wire_stats(root, target, _chosen)
	_select(comp)
	_say("Added a stats component to %s (%s). Tweak its definitions in the Inspector, or re-pick here." % [target.name, _pretty(_chosen)], OK_COLOR)


# --- pure wiring (no EditorInterface, so it's headless-testable) -----------
# Re-entrant: reuses an existing component on the target rather than duplicating.

func wire_stats(root: Node, target: Node, starter: String) -> Node:
	var comp := _ensure(root, target, "StatsComponentLite", COMPONENT_SCRIPT)
	comp.set("definitions", _build_defs(STARTERS.get(starter, [])))
	return comp


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
	var n: Node = load(script_path).new()
	n.name = "StatsLite"
	target.add_child(n)
	n.owner = root  # bakes into the buyer's .tscn
	return n


# Re-entrancy search, scoped to nodes THIS scene owns. A component inside an
# instanced child scene (owner != root) is skipped — updating it wouldn't
# serialize into the buyer's scene, so we'd silently no-op. Search under the
# target but always test ownership against the real scene root.
func _find(root: Node, target: Node, cls: String) -> Node:
	return _find_owned(target, root, cls)


func _find_owned(node: Node, root: Node, cls: String) -> Node:
	if (node == root or node.owner == root) and _is_cls(node, cls):
		return node
	for c in node.get_children():
		var f := _find_owned(c, root, cls)
		if f != null:
			return f
	return null


func _is_cls(node: Node, cls: String) -> bool:
	if node.is_class(cls):
		return true  # native class
	var scr := node.get_script()
	return scr != null and scr.get_global_name() == cls  # class_name script


func _select(n: Node) -> void:
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(n)
	EditorInterface.edit_node(n)


func _pretty(id: String) -> String:
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
