class_name LootDropLite
extends Node

# Rolls a loot table when the player touches it or when the thing it sits on
# dies, puts the loot in the player's bag and says what dropped. The Loot Setup
# tab adds and wires this; every field is plain Inspector stuff.

signal dropped(drops: Array)

enum Trigger { TOUCH, DIES }

const AREA_NAME := "LootArea"
const PLAYER_GROUP := "player"

## The loot table it rolls.
@export var table: LootTableLite
## When it drops. Touch uses the Area it sits on, or the LootArea next to it.
@export_enum("When the player touches it", "When it dies") var trigger: int = Trigger.TOUCH
## Drop only the first time.
@export var once := true
## Show a short "Found: ..." message on screen.
@export var show_messages := true
## Optional. Leave empty and it finds the player's bag by itself.
@export_node_path("Node") var bag_path: NodePath

# one warning per problem, not one per frame or per chest
static var _said := {}
var _done := false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if trigger == Trigger.DIES:
		var src := _died_source()
		if src == null:
			_warn("LootDropLite on \"%s\" drops when it dies, but nothing there has a \"died\" signal. Give it a Health, such as the Combat pack's." % _host_name())
			return
		var argc := _arg_count(src, "died")
		src.connect("died", _on_died if argc == 0 else _on_died.unbind(argc))
		return
	var area := _touch_area()
	if area == null:
		_warn("LootDropLite on \"%s\" drops on touch but has no Area to touch. Apply \"Drops when the player touches this\" in the Loot Setup tab to add one." % _host_name())
		return
	area.connect("body_entered", _on_touched)
	area.connect("area_entered", _on_touched)


## Rolls the table and hands out the loot. Returns the drops as [{item, count}, ...].
func drop(player: Node = null) -> Array:
	if once and _done:
		return []
	if table == null:
		_warn("LootDropLite on \"%s\" has no loot table. Pick one in the Loot Setup tab, or in its Table slot in the Inspector." % _host_name())
		return []
	var drops: Array = table.roll()
	if drops.is_empty():
		_warn("LootDropLite on \"%s\" rolled nothing: its table has no entries with any weight." % _host_name())
		return []
	_done = true
	var lost: Array = []
	var bag := _find_bag(player)
	if bag != null:
		for d in drops:
			var item: Variant = d.get("item")
			if not (item is Resource):
				continue
			var left: Variant = bag.call("add_item", item, int(d.get("count", 1)))
			if left is int and int(left) > 0:
				lost.append({"item": item, "count": int(left)})
	_toast("Found: " + describe(drops))
	if not lost.is_empty():
		_toast("No room in the bag for " + describe(lost))
	dropped.emit(drops)
	return drops


## "Gold x5, Gem". The same item rolled twice shows once, added up.
static func describe(drops: Array) -> String:
	var order: Array = []
	var counts := {}
	for d in drops:
		var n := _item_name(d.get("item"))
		if n == "":
			continue
		if not counts.has(n):
			order.append(n)
			counts[n] = 0
		counts[n] += int(d.get("count", 1))
	var parts := PackedStringArray()
	for n in order:
		parts.append(n if int(counts[n]) == 1 else "%s x%d" % [n, int(counts[n])])
	return ", ".join(parts)


static func _item_name(item: Variant) -> String:
	if not (item is Resource):
		return ""
	var r: Resource = item
	for key in ["name", "display_name", "id"]:
		var v: Variant = r.get(key)
		if v != null and str(v) != "":
			return str(v)
	return r.resource_path.get_file().get_basename()


func _on_touched(other: Node) -> void:
	if other.is_in_group(PLAYER_GROUP):
		drop(other)


func _on_died() -> void:
	drop()


# The LootArea the Setup tab put next to this wins, since an Area with no shape
# of its own gets one too. Else the Area this sits on.
func _touch_area() -> Node:
	var host := get_parent()
	if host == null:
		return null
	var a := host.get_node_or_null(AREA_NAME)
	if a is Area2D or a is Area3D:
		return a
	if host is Area2D or host is Area3D:
		return host
	return null


# died usually lives on a Health child (Combat pack), not on the body itself
func _died_source() -> Node:
	var host := get_parent()
	if host == null:
		return null
	if host.has_signal("died"):
		return host
	for n in host.find_children("*", "", true, false):
		if n != self and n.has_signal("died"):
			return n
	return null


# so a died(killer) style signal still reaches the no-argument handler
func _arg_count(src: Object, sig: String) -> int:
	for s in src.get_signal_list():
		if s.name == sig:
			return (s.args as Array).size()
	return 0


# bag_path if set, else the first node on the player that works like a bag
func _find_bag(player: Node) -> Node:
	if bag_path != NodePath(""):
		var b := get_node_or_null(bag_path)
		if b != null and b.has_method("add_item"):
			return b
	if player == null:
		player = _first_player()
	if player == null:
		_warn("Nothing is in the \"player\" group, so loot only shows as a message. Select your player and press \"Make the selected node the player\" in the Loot Setup tab.")
		return null
	if _is_bag(player):
		return player
	for n in player.find_children("*", "", true, false):
		if _is_bag(n):
			return n
	_warn("The player has no bag, so loot only shows as a message. Give the player an inventory, such as Inventory (Lite)'s, to keep it.")
	return null


func _is_bag(n: Node) -> bool:
	return n.has_method("add_item") and n.has_method("remove_item") and n.has_method("count_item")


# The player the game has now. One on its way out doesn't count: its level was
# freed this frame but it's still in the group until the frame ends.
func _first_player() -> Node:
	for n in get_tree().get_nodes_in_group(PLAYER_GROUP):
		if not _leaving(n):
			return n
	return null


func _leaving(n: Node) -> bool:
	while n != null:
		if n.is_queued_for_deletion():
			return true
		n = n.get_parent()
	return false


func _host_name() -> String:
	var host := get_parent()
	return String(host.name) if host != null else String(name)


func _warn(msg: String) -> void:
	if _said.has(msg):
		return
	_said[msg] = true
	push_warning(msg)


# Lite toast: a Label on its own CanvasLayer, top centre, under any toast
# already showing, gone after about 2 seconds.
func _toast(text: String) -> void:
	if not show_messages or text == "" or not is_inside_tree():
		return
	var host: Node = get_tree().current_scene
	if host == null:
		host = get_tree().root
	var y := 16.0
	for t in get_tree().get_nodes_in_group("lite_toast"):
		if t is Control and not t.is_queued_for_deletion():
			var c: Control = t
			y = maxf(y, c.position.y + maxf(c.size.y, 24.0) + 4.0)
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.offset_left = -300.0
	label.offset_right = 300.0
	label.offset_top = y
	label.offset_bottom = y + 24.0
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_to_group("lite_toast")
	layer.add_child(label)
	host.add_child(layer)
	var tw := layer.create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(label, "modulate:a", 0.0, 0.4)
	tw.tween_callback(layer.queue_free)
