class_name EquippedListLite
extends PanelContainer

# What the player has on, as plain text: one "<slot>: <item>" line per slot. It
# finds the equipment itself (on the node in the "player" group) and follows its
# changes. Starts hidden; the toggle action shows and hides it. Pro's paper doll
# is the styled one: slot icons, drag and drop and stat bonuses.

## Input action that shows and hides the list. The Setup tab registers "character" on C.
@export var toggle_action: StringName = &"character"

const EquipmentLiteScript := preload("res://addons/equipment_lite/equipment_lite.gd")
const SLOT_NAMES := {"weapon_main": "Weapon", "chest": "Chest", "boots": "Boots", "ring": "Ring"}
const MARGIN := 16.0
const LIST_SIZE := Vector2(240, 150)

var _rig: Node
var _rows: VBoxContainer
var _warned := false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if _unplaced():
		# added by hand: go where the Setup tab puts it, bottom-right
		set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		offset_left = -MARGIN - LIST_SIZE.x
		offset_right = -MARGIN
		offset_top = -MARGIN - LIST_SIZE.y
		offset_bottom = -MARGIN
		grow_horizontal = Control.GROW_DIRECTION_BEGIN
		grow_vertical = Control.GROW_DIRECTION_BEGIN
	_build()
	_bind.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if toggle_action == &"" or not InputMap.has_action(toggle_action):
		return
	# not marked handled: the stats panel shares this key
	if event.is_action_pressed(toggle_action):
		visible = not visible
		if visible:
			_bind()


func _unplaced() -> bool:
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		if get_anchor(side) != 0.0 or get_offset(side) != 0.0:
			return false
	return true


func _build() -> void:
	var pad := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 8)
	add_child(pad)
	var box := VBoxContainer.new()
	pad.add_child(box)
	var title := Label.new()
	title.text = "Equipped"
	box.add_child(title)
	_rows = VBoxContainer.new()
	box.add_child(_rows)
	_refresh()


func _bind() -> void:
	if is_instance_valid(_rig):
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		_warn("Nothing is in the \"player\" group, so the equipped list has nothing to show. Select your player and apply \"Player equipment\" in the Equipment · Setup tab.")
		return
	_rig = _find_rig(player)
	if _rig == null:
		_warn("%s has no equipment for the equipped list to show. Select it and apply \"Player equipment\" in the Equipment · Setup tab." % player.name)
		return
	if _rig.has_signal("contents_changed"):
		_rig.connect("contents_changed", _refresh)
	_refresh()


func _find_rig(n: Node) -> Node:
	if n.has_method("equip") and n.has_method("unequip") and n.has_method("get_equipped"):
		return n
	for c in n.get_children():
		var f := _find_rig(c)
		if f != null:
			return f
	return null


func _refresh() -> void:
	if _rows == null:
		return
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	for slot: String in EquipmentLiteScript.SLOTS:
		var it: Variant = null
		if is_instance_valid(_rig):
			it = _rig.call("get_equipped", slot)
		var l := Label.new()
		l.text = "%s: %s" % [SLOT_NAMES.get(slot, slot.capitalize()), _name_of(it)]
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_rows.add_child(l)


func _name_of(item: Variant) -> String:
	if not (item is Object):
		return "-"
	for prop in ["name", "id"]:
		var v: Variant = (item as Object).get(prop)
		if v != null and str(v) != "":
			return str(v)
	return "?"


func _warn(msg: String) -> void:
	if not _warned:
		_warned = true
		push_warning(msg)
