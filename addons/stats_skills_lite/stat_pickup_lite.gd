class_name StatPickupLite
extends Node

# Boosts one of the player's stats when the player touches it: a flat amount,
# for good or for a few seconds, then the thing it sits on disappears. The Stats
# Setup tab adds and wires this; every field is plain Inspector stuff.

signal picked_up(player: Node)

const AREA_NAME := "PickupArea"
const PLAYER_GROUP := "player"

## The stat it boosts, by id. The Stats Setup tab picks it from your player's stats.
@export var stat_id: String = ""
## Added to the stat. A negative amount lowers it.
@export var amount: float = 5.0
## How long the boost lasts, in seconds. 0 keeps it for good.
@export var duration: float = 0.0
## Keep the pickup after it's used. Off: the node it sits on is removed.
@export var stay := false
## Show "+5 Attack" on screen.
@export var show_messages := true
## Optional. Leave empty and it finds the player's stats by itself.
@export_node_path("Node") var stats_path: NodePath

static var _said := {}
var _given := false
var _uses := 0
var _last_sid := ""


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var area := _touch_area()
	if area == null:
		_warn("StatPickupLite on \"%s\" has no Area to touch. Apply \"Boost a stat when the player touches this\" in the Stats Setup tab to add one." % _host_name())
		return
	area.connect("body_entered", _on_touched)
	area.connect("area_entered", _on_touched)


## Gives the boost to this player's stats. Returns true when it did.
func pick_up(player: Node) -> bool:
	# a pickup that stays gives a permanent boost once; a timed one refreshes
	if _given and stay and duration <= 0.0:
		return false
	var stats := _find_stats(player)
	if stats == null:
		_warn("StatPickupLite on \"%s\": the player has no stats to boost. Apply \"Player stats\" in the Stats Setup tab on your player." % _host_name())
		return false
	if stat_id == "":
		_warn("StatPickupLite on \"%s\" has no stat picked. Pick one in the Stats Setup tab." % _host_name())
		return false
	if stats.has_method("find") and stats.call("find", stat_id) == null:
		_warn("StatPickupLite on \"%s\" boosts \"%s\", but the player's stats have no such stat. Pick one of theirs in the Stats Setup tab." % [_host_name(), stat_id])
		return false
	# each use gets its own id, so an old timer can't cut a refreshed boost short
	if duration > 0.0 and _last_sid != "":
		stats.call("remove_modifier", _last_sid)
	_uses += 1
	var sid := "pickup:%d:%d" % [get_instance_id(), _uses]
	_last_sid = sid
	stats.call("add_modifier", {"stat": stat_id, "op": "flat", "amount": amount, "source_id": sid})
	if duration > 0.0:
		# the timer belongs to the tree, so it still wears off after the pickup is gone
		get_tree().create_timer(duration, false).timeout.connect(Callable(stats, "remove_modifier").bind(sid))
	_given = true
	_toast(_message(stats))
	picked_up.emit(player)
	if not stay:
		_remove_host()
	return true


func _on_touched(other: Node) -> void:
	if other.is_in_group(PLAYER_GROUP):
		pick_up(other)


# "+5 Attack", or "+5 Attack for 10s" when it wears off
func _message(stats: Node) -> String:
	var nm := stat_id.capitalize()
	if stats.has_method("find"):
		var d: Variant = stats.call("find", stat_id)
		if d is Resource and str((d as Resource).get("display_name")) != "":
			nm = str((d as Resource).get("display_name"))
	var text := "%s%s %s" % ["+" if amount >= 0.0 else "-", _num(absf(amount)), nm]
	if duration > 0.0:
		text += " for %ss" % _num(duration)
	return text


func _num(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(roundf(v)))
	return String.num(v, 2)


func _remove_host() -> void:
	var host := get_parent()
	# on the level or the player there's nothing sensible to remove, so just stop
	if host == null or host == get_tree().current_scene or host.is_in_group(PLAYER_GROUP):
		_warn("StatPickupLite on \"%s\" can't remove the scene or the player. Put it on the pickup's own node." % _host_name())
		queue_free()
		return
	host.queue_free()


# The PickupArea the Setup tab put next to this wins, since an Area with no shape
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


# stats_path if set, else the first node on the player that works like stats
func _find_stats(player: Node) -> Node:
	if stats_path != NodePath(""):
		var s := get_node_or_null(stats_path)
		if s != null and _is_stats(s):
			return s
	if player == null:
		player = _first_player()
	if player == null:
		return null
	if _is_stats(player):
		return player
	for n in player.find_children("*", "", true, false):
		if _is_stats(n):
			return n
	return null


func _is_stats(n: Node) -> bool:
	return n.has_method("get_stat") and n.has_method("add_modifier") and n.has_method("remove_modifier")


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
