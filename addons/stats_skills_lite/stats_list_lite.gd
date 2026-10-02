class_name StatsListLite
extends PanelContainer

# A plain list of the player's stats and their current values, kept up to date.
# Starts hidden; the character key (C) opens and closes it. The Stats Setup tab
# adds it under the HUD on the left and adds the key.

const PLAYER_GROUP := "player"

## The input action that opens and closes the list. The Stats Setup tab adds it (C).
@export var toggle_action: StringName = &"character"
## Optional. Leave empty and it finds the player's stats by itself.
@export_node_path("Node") var stats_path: NodePath

static var _said := {}
var _stats: Node = null
var _rows: VBoxContainer


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	# one added by hand has no size yet: give it the stats spot, left, under the HUD
	if _unplaced():
		set_anchors_preset(Control.PRESET_TOP_LEFT)
		offset_left = 16.0
		offset_top = 80.0
		offset_right = 276.0
		offset_bottom = 330.0
	var box := VBoxContainer.new()
	add_child(box)
	var title := Label.new()
	title.text = "Stats"
	box.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	visibility_changed.connect(_on_visibility_changed)
	if toggle_action != &"" and not InputMap.has_action(toggle_action):
		_warn("StatsListLite: there's no \"%s\" input action, so no key opens the stats list. Apply \"Player stats\" in the Stats Setup tab to add it (C)." % toggle_action)
	# deferred, so a player spawned in the same frame still counts
	_hook.call_deferred()
	get_tree().node_added.connect(_on_node_added)


func _unhandled_input(event: InputEvent) -> void:
	if toggle_action == &"" or not InputMap.has_action(toggle_action):
		return
	if event.is_action_pressed(toggle_action):
		visible = not visible


## The lines it shows right now, e.g. "Attack: 15".
func lines() -> PackedStringArray:
	var out := PackedStringArray()
	if _rows != null:
		for c in _rows.get_children():
			if c is Label:
				out.append((c as Label).text)
	return out


func _hook() -> bool:
	if is_instance_valid(_stats):
		return true
	_stats = _find_stats()
	if _stats == null:
		_refresh()
		return false
	if _stats.has_signal("stat_changed"):
		_stats.connect("stat_changed", _refresh.unbind(2))
	# a respawned player is a new node: find it again
	_stats.tree_exiting.connect(_on_stats_gone, CONNECT_ONE_SHOT)
	_refresh()
	return true


func _on_stats_gone() -> void:
	_stats = null
	_hook.call_deferred()


# a player that shows up later (a respawn) gets picked up without reopening the list
func _on_node_added(n: Node) -> void:
	if not is_instance_valid(_stats) and n.is_in_group(PLAYER_GROUP):
		_hook.call_deferred()


func _on_visibility_changed() -> void:
	if not visible:
		return
	if not _hook():
		_warn("StatsListLite: nothing in the \"player\" group has stats, so the list is empty. Apply \"Player stats\" in the Stats Setup tab on your player.")
	_refresh()


func _refresh() -> void:
	if _rows == null:
		return
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	if not is_instance_valid(_stats):
		_add_row("No player stats found.")
		return
	var defs: Variant = _stats.get("definitions")
	if not (defs is Array) or (defs as Array).is_empty():
		_add_row("No stats yet.")
		return
	for d in defs:
		if d == null:
			continue
		var sid := str(d.get("id"))
		var nm := str(d.get("display_name"))
		if nm == "":
			nm = sid.capitalize()
		_add_row("%s: %s" % [nm, _fmt(d, float(_stats.call("get_stat", sid)))])


func _add_row(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_child(l)


# The stat's own format when it has one, else 10 not 10.00.
func _fmt(def: Resource, v: float) -> String:
	if str(def.get("format_template")) != "" and def.has_method("format_value"):
		return str(def.call("format_value", v))
	if is_equal_approx(v, roundf(v)):
		return str(int(roundf(v)))
	return String.num(v, 2)


# stats_path if set, else the first node on the player that works like stats
func _find_stats() -> Node:
	if stats_path != NodePath(""):
		var s := get_node_or_null(stats_path)
		if s != null and _is_stats(s):
			return s
	var player := _first_player()
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


func _unplaced() -> bool:
	if size.x < 1.0 or size.y < 1.0:
		return true
	return anchor_left == 0.0 and anchor_top == 0.0 and anchor_right == 0.0 and anchor_bottom == 0.0 \
		and offset_left == 0.0 and offset_top == 0.0 and offset_right == 0.0 and offset_bottom == 0.0


func _warn(msg: String) -> void:
	if _said.has(msg):
		return
	_said[msg] = true
	push_warning(msg)
