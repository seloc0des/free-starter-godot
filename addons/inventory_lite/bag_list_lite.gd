class_name BagListLite
extends PanelContainer

# The player's bag as plain text, one "<name> x<count>" line per slot. It finds
# the bag itself (on the node in the "player" group) and follows its changes.
# Starts hidden; the toggle action shows and hides it. Pro's bag is the styled
# one: icons, drag and drop, tooltips and a hotbar.

## Input action that shows and hides the list. The Setup tab registers "inventory" on I.
@export var toggle_action: StringName = &"inventory"

const MARGIN := 16.0
const LIST_SIZE := Vector2(240, 260)

var _bag: Node
var _title: Label
var _rows: VBoxContainer
var _warned := false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if _unplaced():
		# added by hand: go where the Setup tab puts it, bottom-left
		set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		offset_left = MARGIN
		offset_right = MARGIN + LIST_SIZE.x
		offset_top = -MARGIN - LIST_SIZE.y
		offset_bottom = -MARGIN
		grow_vertical = Control.GROW_DIRECTION_BEGIN
	_build()
	_bind.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if toggle_action == &"" or not InputMap.has_action(toggle_action):
		return
	# not marked handled: other panels can share the key
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
	_title = Label.new()
	_title.text = "Bag"
	box.add_child(_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	_refresh()


func _bind() -> void:
	if is_instance_valid(_bag):
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		_warn("Nothing is in the \"player\" group, so the bag list has no bag to show. Select your player and apply \"Player inventory\" in the Inventory · Setup tab.")
		return
	_bag = _find_bag(player)
	if _bag == null:
		_warn("%s has no bag for the bag list to show. Select it and apply \"Player inventory\" in the Inventory · Setup tab." % player.name)
		return
	if _bag.has_signal("contents_changed"):
		_bag.connect("contents_changed", _refresh)
	_refresh()


func _find_bag(n: Node) -> Node:
	if n.has_method("add_item") and n.has_method("remove_item") and n.has_method("count_item"):
		return n
	for c in n.get_children():
		var f := _find_bag(c)
		if f != null:
			return f
	return null


func _refresh() -> void:
	if _rows == null:
		return
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	var slots: Array = []
	if is_instance_valid(_bag) and _bag.has_method("slots"):
		slots = _bag.call("slots")
	_title.text = "Bag"
	if is_instance_valid(_bag):
		var cap: Variant = _bag.get("capacity")
		if cap is int:
			_title.text = "Bag (%d/%d)" % [slots.size(), cap]
	for s in slots:
		_add_row("%s x%d" % [_name_of(s.get("item")), int(s.get("count", 0))])
	if slots.is_empty():
		_add_row("(empty)")


func _add_row(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_rows.add_child(l)


func _name_of(item: Variant) -> String:
	if not (item is Object):
		return "?"
	for prop in ["name", "id"]:
		var v: Variant = (item as Object).get(prop)
		if v != null and str(v) != "":
			return str(v)
	return "?"


func _warn(msg: String) -> void:
	if not _warned:
		_warned = true
		push_warning(msg)
