class_name CraftPanelLite
extends Control

# Plain crafting window for one CraftingLite: every recipe with what it needs and
# a Craft button that lights up when the player's bag has it all. At a bench the
# Setup tab points area_path at the bench's CraftArea, so it opens when the player
# walks up and closes when they leave (or press Close). Crafting anywhere uses
# toggle_action instead (B). The bag is found on the "player" group's node.
# Crafting (Pro) has the styled CraftingUI: icons, timed crafts, a queue.

## The CraftingLite whose recipes this shows. The Setup tab fills it in.
@export_node_path("Node") var crafting_path: NodePath
## Opens when a node in the "player" group walks into this area, closes when it leaves.
@export_node_path("Area2D", "Area3D") var area_path: NodePath
## An Input Map action that opens and closes it, like "crafting". Empty for none.
@export var toggle_action: StringName = &""
## Short messages like "+1 Stick" at the top of the screen.
@export var show_messages := true

const GROUP := &"craft_panel_lite"
const REASONS := {
	"missing_inputs": "You don't have everything for that yet.",
	"no_inventory_bound": "The player has no bag to craft from.",
	"no_player": "Nothing is marked as the player.",
}

var _crafting: Node
var _bag: Node  # what we listen to, so a swap gets rewired
var _title: Label
var _list: VBoxContainer
var _status: Label
var _warned := {}
var _dirty := false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if _unplaced():
		_place()
	_build()
	add_to_group(GROUP)
	visibility_changed.connect(_on_visibility_changed)
	var area := get_node_or_null(area_path) if area_path != NodePath("") else null
	if area != null and area.has_signal("body_entered"):
		area.body_entered.connect(_on_body_entered)
		area.body_exited.connect(_on_body_exited)
	if is_visible_in_tree():
		_on_visibility_changed()


func _unhandled_input(event: InputEvent) -> void:
	if toggle_action == &"" or not InputMap.has_action(toggle_action):
		return
	if event.is_action_pressed(toggle_action):
		visible = not visible
		get_viewport().set_input_as_handled()


func open() -> void:
	show()


func close() -> void:
	hide()


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		open()


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		close()


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		return
	# a bench's and the B panel share the top centre: one at a time
	for p in get_tree().get_nodes_in_group(GROUP):
		if p != self and p.visible:
			p.hide()
	_status.text = ""
	_link()
	_refresh()


# ---- linking -------------------------------------------------------------

func _link() -> void:
	if not is_instance_valid(_crafting):
		_crafting = get_node_or_null(crafting_path) if crafting_path != NodePath("") else null
		if _crafting == null or not _crafting.has_method("link_player"):
			_crafting = null
			_warn_once("crafting", "Craft panel \"%s\" has no crafting to show. Select your bench or player and Apply in the Crafting · Setup tab." % name)
			return
		_crafting.recipes_changed.connect(_queue_refresh)
		_crafting.craft_completed.connect(_on_crafted)
		_crafting.craft_failed.connect(_on_failed)
	var why: String = _crafting.link_player()
	match why:
		"no_player":
			_warn_once(why, "Craft panel: nothing in the scene is marked as the player, so it can't find a bag to craft from. Select your player and press \"Make the selected node the player\" in the Crafting · Setup tab.")
		"no_inventory_bound":
			_warn_once(why, "Craft panel: the player has no bag to craft from. Add one to your player, for example with the Setup tab of Inventory (Lite).")
	var bag: Node = _crafting.get_inventory()
	if bag != _bag:
		if is_instance_valid(_bag) and _bag.has_signal("contents_changed") and _bag.is_connected("contents_changed", _queue_refresh):
			_bag.disconnect("contents_changed", _queue_refresh)
		_bag = bag
		if _bag != null and _bag.has_signal("contents_changed"):
			_bag.connect("contents_changed", _queue_refresh)


func _warn_once(key: String, text: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(text)


# ---- craft ---------------------------------------------------------------

func _on_craft(recipe: Resource) -> void:
	if _crafting == null:
		return
	_status.text = ""
	_crafting.craft(recipe)


func _on_crafted(recipe: Resource, outputs: Array) -> void:
	_status.text = "Made %s." % _title_of(recipe)
	for o in outputs:
		if o is Dictionary and o.get("item") is Resource:
			_toast("+%d %s" % [int(o.get("count", 1)), _name_of(o.get("item"))])
	_queue_refresh()


func _on_failed(_recipe: Resource, reason: String) -> void:
	_status.text = REASONS.get(reason, "Can't craft that (%s)." % reason)
	_queue_refresh()


# ---- view ----------------------------------------------------------------

func _queue_refresh() -> void:
	# one rebuild per frame: a craft changes the bag several times
	if _dirty:
		return
	_dirty = true
	_refresh.call_deferred()


func _refresh() -> void:
	_dirty = false
	if _list == null:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	if _crafting == null:
		_note("(no crafting linked)")
		return
	var host: Node = _crafting.get_parent()
	_title.text = String(host.name) if host != null and host != get_tree().current_scene else "Crafting"
	var bag: Node = _crafting.get_inventory()
	if bag == null and _status.text == "":
		_status.text = "The player has no bag, so nothing can be crafted."
	var recipes: Variant = _crafting.get("recipes")
	var shown := 0
	for r in (recipes if recipes is Array else []):
		if not (r is Resource):
			continue
		shown += 1
		var block := VBoxContainer.new()
		_list.add_child(block)
		var head := HBoxContainer.new()
		block.add_child(head)
		var t := Label.new()
		t.text = _title_of(r)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		head.add_child(t)
		var b := Button.new()
		b.text = "Craft"
		b.disabled = not bool(_crafting.can_craft(r))
		b.pressed.connect(_on_craft.bind(r))
		head.add_child(b)
		var needs := PackedStringArray()
		for i in r.get("inputs"):
			if i is Dictionary and i.get("item") is Resource:
				var have := int(bag.count_item(i.item)) if bag != null else 0
				needs.append("%d %s (have %d)" % [int(i.get("count", 1)), _name_of(i.item), have])
		var makes := PackedStringArray()
		for o in r.get("outputs"):
			if o is Dictionary and o.get("item") is Resource:
				makes.append("%d %s" % [int(o.get("count", 1)), _name_of(o.item)])
		var info := Label.new()
		info.text = "Needs: %s\nMakes: %s" % [", ".join(needs) if not needs.is_empty() else "nothing", ", ".join(makes) if not makes.is_empty() else "nothing"]
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.modulate = Color(1, 1, 1, 0.8)
		block.add_child(info)
	if shown == 0:
		_note("No recipes yet.")


func _title_of(recipe: Resource) -> String:
	for p in ["title", "id"]:
		var v: Variant = recipe.get(p)
		if v != null and str(v) != "":
			return str(v)
	return recipe.resource_path.get_file().get_basename()


func _name_of(item: Resource) -> String:
	for p in ["name", "display_name", "title", "id"]:
		var v: Variant = item.get(p)
		if v != null and str(v) != "":
			return str(v)
	return item.resource_path.get_file().get_basename()


func _note(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.modulate = Color(1, 1, 1, 0.6)
	_list.add_child(l)


# ---- layout --------------------------------------------------------------

func _unplaced() -> bool:
	return anchor_left == 0.0 and anchor_top == 0.0 and anchor_right == 0.0 and anchor_bottom == 0.0 \
		and offset_left == 0.0 and offset_top == 0.0 and offset_right == 0.0 and offset_bottom == 0.0


# Top centre, 320x300: the HUD strip and panels own the left, the paper doll and
# quest log the right, and the shop opens in the lower middle.
func _place() -> void:
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_left = -160.0
	offset_right = 160.0
	offset_top = 16.0
	offset_bottom = 316.0


func _build() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var pad := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(pad)
	var col := VBoxContainer.new()
	pad.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	_title = Label.new()
	_title.text = "Crafting"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var shut := Button.new()
	shut.text = "Close"
	shut.pressed.connect(close)
	head.add_child(shut)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)


# ---- toast ---------------------------------------------------------------

# A short line top centre for about two seconds, stacked under any other lite's.
func _toast(text: String) -> void:
	if not show_messages or not is_inside_tree():
		return
	var y := 16.0
	for t in get_tree().get_nodes_in_group("lite_toast"):
		if t is Control and not t.is_queued_for_deletion():
			y = maxf(y, (t as Control).offset_bottom + 4.0)
	var layer := CanvasLayer.new()
	layer.layer = 100
	var l := Label.new()
	l.text = text
	l.add_to_group("lite_toast")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.anchor_left = 0.5
	l.anchor_right = 0.5
	l.offset_left = -240.0
	l.offset_right = 240.0
	l.offset_top = y
	l.offset_bottom = y + 24.0
	layer.add_child(l)
	var scene := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	scene.add_child(layer)
	get_tree().create_timer(2.0).timeout.connect(layer.queue_free)
