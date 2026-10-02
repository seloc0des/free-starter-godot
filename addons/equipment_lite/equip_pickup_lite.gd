class_name EquipPickupLite
extends Node

# Walk into it and the player puts the item on, in the slot the item names,
# then the thing it sits on (this node's parent) goes away. The parent is the
# Area2D/Area3D that gets touched, or it holds one named PickupArea (the Setup
# tab adds that for you). Whatever was in that slot before is replaced.

## Any item with a slot (metadata "equip_slot"). The Equipment · Setup tab sets it for you.
@export var item: Resource
## Show "Equipped Iron Sword" at the top of the screen.
@export var show_messages := true

var _done := false
var _warned := false


func _ready() -> void:
	var area := _area()
	if area == null:
		push_warning("%s has nothing to touch. Put it under an Area2D or Area3D, or use \"Equip it when the player picks it up\" in the Equipment · Setup tab." % name)
		return
	area.connect("body_entered", _on_touched)
	area.connect("area_entered", _on_touched)


func _area() -> Node:
	var p := get_parent()
	if p is Area2D or p is Area3D:
		return p
	var a := p.get_node_or_null(^"PickupArea")
	if a is Area2D or a is Area3D:
		return a
	return null


func _on_touched(body: Node) -> void:
	if _done or item == null:
		return
	var who := _player_of(body)
	if who == null:
		if get_tree().get_first_node_in_group("player") == null:
			_warn("Nothing is in the \"player\" group, so %s can't tell who touched it. Select your player and press \"Make the selected node the player\" in the Equipment · Setup tab." % name)
		return
	var rig := _rig(who)
	if rig == null:
		_warn("%s has no equipment, so %s can't be put on. Select it and apply \"Player equipment\" in the Equipment · Setup tab." % [who.name, _item_name()])
		return
	var slot := _slot()
	if slot == "":
		_warn("%s has no slot, so it can't be equipped. Pick one for it in the Equipment · Setup tab." % _item_name())
		return
	rig.call("equip", slot, item)
	if rig.call("get_equipped", slot) != item:
		_warn("%s doesn't fit the \"%s\" slot of %s." % [_item_name(), slot, who.name])
		return
	_toast("Equipped %s" % _item_name())
	_done = true
	var holder := get_parent()
	# never take the whole level with it (someone ran the pickup's own scene)
	if holder == get_tree().current_scene:
		queue_free()
	else:
		holder.queue_free()


# The toucher, or the tagged node it belongs to (a hitbox inside the player).
func _player_of(body: Node) -> Node:
	var n := body
	while n != null:
		if n.is_in_group("player"):
			return n
		n = n.get_parent()
	return null


# Anything on the player that works like an equipment rig. Duck typed.
func _rig(n: Node) -> Node:
	if n.has_method("equip") and n.has_method("unequip") and n.has_method("get_equipped"):
		return n
	for c in n.get_children():
		var f := _rig(c)
		if f != null:
			return f
	return null


func _slot() -> String:
	var md: Variant = item.get("metadata")
	if md is Dictionary:
		return String((md as Dictionary).get("equip_slot", ""))
	return ""


func _item_name() -> String:
	for prop in ["name", "id"]:
		var v: Variant = item.get(prop)
		if v != null and str(v) != "":
			return str(v)
	return "item"


func _warn(msg: String) -> void:
	if not _warned:
		_warned = true
		push_warning(msg)


# Lites don't share code, so each one carries this: a Label on its own
# CanvasLayer, top centre, under any toast still showing, gone after 2 seconds.
func _toast(text: String) -> void:
	if not show_messages:
		return
	var host: Node = get_tree().current_scene
	if host == null:
		host = get_tree().root
	var y := 16.0
	for t in get_tree().get_nodes_in_group("lite_toast"):
		if t is Control and not t.is_queued_for_deletion():
			var r := (t as Control).get_global_rect()
			y = maxf(y, r.position.y + maxf(r.size.y, 24.0) + 4.0)
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.name = "LiteToast"
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_to_group("lite_toast")
	layer.add_child(label)
	host.add_child(layer, true)
	label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.offset_left = 0.0
	label.offset_right = 0.0
	label.offset_top = y
	label.offset_bottom = y
	get_tree().create_timer(2.0).timeout.connect(layer.queue_free)
