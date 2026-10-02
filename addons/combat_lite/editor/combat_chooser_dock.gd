@tool
extends Control

# No-code chooser. Select a node in your scene, set values, and one click bakes the
# combat components onto it — with a CollisionShape2D so it works immediately.

const HEALTH := preload("res://addons/combat_lite/health_lite.gd")
const HURTBOX := preload("res://addons/combat_lite/hurtbox_lite.gd")
const HITBOX := preload("res://addons/combat_lite/hitbox_lite.gd")
# The two sides, as the team numbers the demo and docs use. A hitbox only hurts
# hurtboxes on the other team, so each button gets its own side pick, and the
# defaults work untouched: an enemy you can hit, a weapon that hits it.
const TEAM_PLAYER := 0
const TEAM_ENEMY := 1
# An Enemy AI brain stops at its attack radius, and its own 40 stops just short
# of two 32x32 boxes touching. Stopping at 3/4 of the two half-widths leaves the
# hitbox overlapping the player's hurtbox with room to spare.
const BOX_HALF := 16.0
const REACH := 0.75

var _hp: SpinBox
var _hurt_side: OptionButton
var _remove: CheckBox
var _remove_why: Label
var _remove_touched := false
var _dmg: SpinBox
var _hit_side: OptionButton
var _status: Label
var _scroll: ScrollContainer


func _ready() -> void:
	name = "Combat"
	_build()
	# the remove tick's default depends on what's selected (off for the player)
	if Engine.is_editor_hint():
		EditorInterface.get_selection().selection_changed.connect(_on_selection_changed)
		refresh_remove_tick(_selected())


# A plain Control doesn't tell the dock slot how narrow its page can go, so say it
# here. Height is the scroll's job.
func _get_minimum_size() -> Vector2:
	if _scroll == null:
		return Vector2.ZERO
	return Vector2(_scroll.get_combined_minimum_size().x, 0.0)


func _build() -> void:
	# The whole tab scrolls, so a short screen or a big editor scale can't push the
	# status line off the bottom. Sideways it wraps instead.
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.minimum_size_changed.connect(update_minimum_size)
	add_child(_scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(v)

	v.add_child(_header("Combat: bake onto the selected node"))
	_hp = _num(1, 9999, 100)
	v.add_child(_labeled("Max health", _hp))
	_hurt_side = _side_pick([["Enemy side (the player can hurt it)", TEAM_ENEMY], ["Player side (enemies can hurt it)", TEAM_PLAYER]])
	v.add_child(_labeled("Side", _hurt_side))
	_remove = CheckBox.new()
	_remove.text = "Remove it when it dies"
	_remove.button_pressed = true
	_remove.tooltip_text = "When its health runs out it's taken out of the game. Its death is announced first, so anything listening for it still hears it."
	_remove.toggled.connect(_on_remove_toggled)
	v.add_child(_remove)
	_remove_why = Label.new()
	_remove_why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_remove_why.visible = false
	v.add_child(_remove_why)
	var enemy_btn := Button.new()
	enemy_btn.text = "Add Health + Hurtbox"
	enemy_btn.pressed.connect(_add_hurtable)
	v.add_child(enemy_btn)

	v.add_child(HSeparator.new())

	_dmg = _num(0, 9999, 10)
	v.add_child(_labeled("Damage", _dmg))
	_hit_side = _side_pick([["Player side (hurts enemies)", TEAM_PLAYER], ["Enemy side (hurts the player)", TEAM_ENEMY]])
	v.add_child(_labeled("Side", _hit_side))
	var hit_btn := Button.new()
	hit_btn.text = "Add Hitbox"
	hit_btn.pressed.connect(_add_hitbox)
	v.add_child(hit_btn)

	v.add_child(HSeparator.new())
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Select a node, set values, click a button."
	v.add_child(_status)

	# long button labels (and the tick) wrap onto a second line instead of widening the dock
	for c in v.get_children():
		if c is Button and not (c is OptionButton):
			(c as Button).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _add_hurtable() -> void:
	var target := _selected()
	if target == null:
		_say("Select a node in the open scene first.")
		return
	_say(bake_hurtable(target))


# The button minus the selection, so the verify can press it headless. Returns
# the status line.
func bake_hurtable(target: Node) -> String:
	var team := _hurt_side.get_selected_id()
	var side := "player side" if team == TEAM_PLAYER else "enemy side"
	# Clicking twice used to stack a second Health + Hurtbox. Retune the ones that
	# are there instead, like the Pro dock does.
	var h := _find_health(target)
	if h != null:
		h.set("max_health", float(_hp.value))
		var after := apply_remove_tick(target, h)
		var existing := _find_child_named(target, "HurtboxLite")
		if existing != null:
			existing.set("team", team)
		# no node added, so nothing else flags the scene for Play
		_mark_unsaved()
		return "'%s' already had Health. Set it to %d hp, %s.%s" % [target.name, int(_hp.value), side, after]
	h = _inert(HEALTH)
	h.name = "HealthLite"
	h.set("max_health", float(_hp.value))
	var gone := apply_remove_tick(target, h)
	_own(target, h)
	var hb: Node = _inert(HURTBOX)
	hb.name = "HurtboxLite"
	hb.set("team", team)
	_own(target, hb)
	_add_shape(hb)
	return "Added Health + Hurtbox (%s) to '%s'.%s" % [side, target.name, gone]


func _add_hitbox() -> void:
	var target := _selected()
	if target == null:
		_say("Select a node in the open scene first.")
		return
	var team := _hit_side.get_selected_id()
	var hits := "player side, hurts enemies" if team == TEAM_PLAYER else "enemy side, hurts the player"
	var hb := _find_child_named(target, "HitboxLite")
	if hb != null:
		hb.set("damage", float(_dmg.value))
		hb.set("team", team)
		# no node added, so nothing else flags the scene for Play
		EditorInterface.mark_scene_as_unsaved()
		_say("'%s' already had a Hitbox. Set it to %d dmg, %s.%s" % [target.name, int(_dmg.value), hits, fit_enemy_reach(target, hb, EditorInterface.get_edited_scene_root())])
		return
	hb = _inert(HITBOX)
	hb.name = "HitboxLite"
	hb.set("damage", float(_dmg.value))
	hb.set("team", team)
	_own(target, hb)
	_add_shape(hb)
	_say("Added Hitbox (%d dmg, %s) to '%s'.%s" % [int(_dmg.value), hits, target.name, fit_enemy_reach(target, hb, EditorInterface.get_edited_scene_root())])


# The HealthLite on the node or among its children (placeholders report their
# script too, so this finds ones the dock just baked).
func _find_health(target: Node) -> Node:
	if target.get_script() == HEALTH:
		return target
	for c in target.get_children():
		if c.get_script() == HEALTH:
			return c
	return null


func _find_child_named(target: Node, n: String) -> Node:
	for c in target.get_children():
		if c.name == n:
			return c
	return null


func _selected() -> Node:
	var sel := EditorInterface.get_selection().get_selected_nodes()
	return sel[0] if sel.size() > 0 else null


# A runtime script's .new() is a live instance, so its game code would run in the
# editor until the scene is reopened. Attach the script to a plain native node
# instead: that's the inert placeholder a hand-added node gets. Exports still save.
func _inert(script: Script) -> Node:
	var n: Node = ClassDB.instantiate(script.get_instance_base_type())
	n.set_script(script)
	return n


func _own(parent: Node, child: Node) -> void:
	parent.add_child(child, true)
	if not Engine.is_editor_hint():
		return  # the verify pressing a button headless: no open scene to own it
	child.owner = EditorInterface.get_edited_scene_root()
	# no undo manager here, so flag the scene or Play runs the old file without this node
	EditorInterface.mark_scene_as_unsaved()


func _mark_unsaved() -> void:
	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()


func _add_shape(area: Node) -> void:
	var shape := CollisionShape2D.new()
	shape.name = "Shape"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(32, 32)
	shape.shape = rect
	_own(area, shape)


# ---- remove on death (headless-safe, the verify calls these) -------------

# Why "Remove it when it dies" starts unticked for this node, "" when it starts
# ticked. A player that vanishes on death leaves nothing on screen, and so does
# anything the player sits inside. Nothing selected: ticked.
func keep_reason(target: Node) -> String:
	if target == null:
		return ""
	var n: Node = target
	while n != null:
		if n.is_in_group("player"):
			return "Unticked for your player. If it vanished when it died, there'd be nothing left on screen."
		n = n.get_parent()
	if target.is_inside_tree():
		for p in target.get_tree().get_nodes_in_group("player"):
			if target.is_ancestor_of(p):
				return "Unticked because your player is inside it. Removing it would take the player too."
	return ""


# The tick's default for this node, with the reason under it when that's off. A
# click on the tick itself counts until the selection changes.
func refresh_remove_tick(target: Node) -> void:
	var why: String = keep_reason(target)
	_remove.set_pressed_no_signal(why == "")
	_remove_why.text = why
	_remove_why.visible = why != ""
	_remove_touched = false


# Writes the tick onto a Health. Returns the end of the status line.
func apply_remove_tick(target: Node, h: Node) -> String:
	# untouched, it's worked out again: the node may have become the player
	# since it was selected
	if not _remove_touched:
		refresh_remove_tick(target)
	var on: bool = _remove.button_pressed
	h.set("remove_on_death", on)
	if on:
		return " It disappears when its health runs out."
	return " It stays in the game when its health runs out."


func _on_remove_toggled(_on: bool) -> void:
	_remove_touched = true
	_remove_why.visible = false


func _on_selection_changed() -> void:
	refresh_remove_tick(_selected())


# ---- enemy reach (headless-safe, the verify calls these) -----------------

# A hitbox on an Enemy AI enemy (Pro or Lite brain on the node or one of its
# children) only lands if the brain walks close enough, so give each brain the
# attack radius that lets this hitbox overlap the player's hurtbox, and make it
# swing the hitbox. Returns what it did for the status line, "" when there's no
# brain here.
func fit_enemy_reach(body: Node, hitbox: Node, root: Node) -> String:
	var brains: Array[Node] = []
	for n in [body] + body.get_children():
		if _is_brain(n):
			brains.append(n)
	if brains.is_empty():
		return ""
	var hurt := _player_hurtbox(root)
	var hit_half := _half_width(hitbox)
	var hurt_half := _half_width(hurt)
	var touch := _touch(body, root)
	var r := reach_for(hit_half, hurt_half, touch)
	var opened := ""
	var swing := ""
	for b in brains:
		b.set("attack_radius", r)
		swing = _swing(b, hitbox)
		# a Brain inside an instanced enemy scene only saves with Editable Children on
		if root != null and b.owner != null and b.owner != root and not root.is_editable_instance(b.owner):
			root.set_editable_instance(b.owner, true)
			opened = " Turned on Editable Children for '%s' so the level saves its Brain." % b.owner.name
	var reach := _reach(hit_half, hurt_half)
	var msg := ""
	if touch + 2.0 > reach - 2.0:
		msg = " Set its Brain's attack radius to %s, as close as this hitbox reaches (%s). It can't reach far enough past the two bodies though: they touch at %s px and the boxes only overlap closer than %s px. Make the hitbox bigger." % [_px(r), _reach_why(hit_half, hurt_half, 0.0), _px(touch), _px(reach)]
		swing = ""   # it's wired, but it won't be hurting anyone from there
	else:
		msg = " Set its Brain's attack radius to %s so this hitbox overlaps the player's hurtbox (%s)." % [_px(r), _reach_why(hit_half, hurt_half, touch)]
	var side := ""
	if hurt != null and int(hitbox.get("team")) == int(hurt.get("team")):
		swing = ""
		side = " This hitbox and the player's hurtbox are on the same side though, so it can't hurt the player: pick Enemy side (hurts the player) here and give the player Player side health."
	return msg + swing + opened + side


# A hitbox only hits when something starts touching it, so a brain has to switch
# it back on for every attack to keep hurting a player who stays in reach. Pro
# brains swing whatever attack_node_path points at: point it here, unless the
# buyer already pointed it somewhere else. Lite brains do it on their own.
func _swing(brain: Node, hitbox: Node) -> String:
	var every := " Its Brain switches this hitbox on for each attack, so it keeps hurting the player every %s s while in reach." % _px(float(brain.get("attack_cooldown")))
	if "attack_node_path" in brain:
		var now: NodePath = brain.get("attack_node_path")
		var current: Node = brain.get_node_or_null(now) if not now.is_empty() else null
		if current != null and current != hitbox:
			return " Its Brain already swings '%s', so that was left as it is." % current.name
		brain.set("attack_node_path", brain.get_path_to(hitbox))
		return every
	if "attack_duration" in brain:
		return every
	return ""


# 3/4 of the reach (the two half-widths added, a box that isn't there counting
# as this dock's 32x32 one), but at least 2 px past where the two bodies touch,
# or they stop the brain before it ever attacks, and at most 2 px inside the reach.
func reach_for(hit_half: float, hurt_half: float, touch: float = 0.0) -> float:
	var reach := _reach(hit_half, hurt_half)
	var r := minf(maxf(REACH * reach, touch + 2.0), reach - 2.0)
	return maxf(1.0, floorf(r * 10.0) / 10.0)


func _reach(hit_half: float, hurt_half: float) -> float:
	return (hit_half if hit_half >= 0.0 else BOX_HALF) + (hurt_half if hurt_half >= 0.0 else BOX_HALF)


func _reach_why(hit_half: float, hurt_half: float, touch: float) -> String:
	var why := "sized for this dock's 32x32 boxes"
	if hit_half >= 0.0 and hurt_half >= 0.0:
		why = "measured from both boxes"
	elif hit_half >= 0.0:
		why = "measured from this hitbox, with the player's hurtbox counted as this dock's 32x32 box"
	elif hurt_half >= 0.0:
		why = "measured from the player's hurtbox, with this hitbox counted as this dock's 32x32 box"
	if touch + 2.0 > REACH * _reach(hit_half, hurt_half):
		why += ", and 2 px past where the two bodies touch (%s px) so they can't stop it short of attacking" % _px(touch)
	return why


# Enemy AI's brains, Pro or Lite, by their exports, so this dock loads without Enemy AI
func _is_brain(n: Node) -> bool:
	return "attack_radius" in n and "detect_radius" in n and "target_group" in n


# the first hurtbox (Pro or Lite) on whatever this scene marks as the player
func _player_hurtbox(root: Node) -> Node:
	for p in _scene_players(root):
		for n in [p] + p.find_children("*", "", true, false):
			if (n is Area2D or n is Area3D) and "team" in n and "health_path" in n:
				return n
	return null


# the physics body of whatever this scene marks as the player
func _player_body(root: Node) -> Node:
	for p in _scene_players(root):
		for n in [p] + p.find_children("*", "", true, false):
			if n is PhysicsBody2D or n is PhysicsBody3D:
				return n
	return null


func _scene_players(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	if root == null or not root.is_inside_tree():
		return out
	for p in root.get_tree().get_nodes_in_group("player"):
		if p == root or root.is_ancestor_of(p):
			out.append(p)
	return out


# Where the enemy's body and the player's body stop against each other, from
# their own collision shapes. 0 when they can't block each other: a shape
# missing, no player yet, or layers that don't collide.
func _touch(body: Node, root: Node) -> float:
	var player := _player_body(root)
	if player == null or player == body or not (body is CollisionObject2D or body is CollisionObject3D):
		return 0.0
	if (int(body.get("collision_mask")) & int(player.get("collision_layer"))) == 0:
		return 0.0
	var a := _half_width(body)
	var b := _half_width(player)
	if a < 0.0 or b < 0.0:
		return 0.0
	return a + b


# Rectangles and boxes by half their width, round shapes by their radius, in
# the pixels the brain measures in (so a scaled node counts). -1: nothing to read.
func _half_width(area: Node) -> float:
	if area == null:
		return -1.0
	for c in area.get_children():
		var half := -1.0
		if c is CollisionShape2D:
			var s2: Shape2D = (c as CollisionShape2D).shape
			if s2 is RectangleShape2D:
				half = (s2 as RectangleShape2D).size.x / 2.0
			elif s2 is CircleShape2D:
				half = (s2 as CircleShape2D).radius
			elif s2 is CapsuleShape2D:
				half = (s2 as CapsuleShape2D).radius
		elif c is CollisionShape3D:
			var s3: Shape3D = (c as CollisionShape3D).shape
			if s3 is BoxShape3D:
				half = (s3 as BoxShape3D).size.x / 2.0
			elif s3 is SphereShape3D:
				half = (s3 as SphereShape3D).radius
			elif s3 is CapsuleShape3D:
				half = (s3 as CapsuleShape3D).radius
			elif s3 is CylinderShape3D:
				half = (s3 as CylinderShape3D).radius
		if half >= 0.0:
			return half * _scale_x(c)
	return -1.0


func _scale_x(n: Node) -> float:
	if n is Node2D and n.is_inside_tree():
		return (n as Node2D).global_transform.x.length()
	if n is Node3D and n.is_inside_tree():
		return (n as Node3D).global_transform.basis.x.length()
	return 1.0


func _px(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v


func _num(min_v: float, max_v: float, value: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.value = value
	return s


# [label, team] pairs; the first one is the default
func _side_pick(items: Array) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(it[0], it[1])
	o.select(0)
	# the long side names end in "…" in a narrow dock; the open list shows them whole
	o.fit_to_longest_item = false
	o.clip_text = true
	o.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return o


func _labeled(text: String, field: Control) -> Control:
	var box := VBoxContainer.new()
	var l := Label.new()
	l.text = text
	box.add_child(l)
	box.add_child(field)
	return box


func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	return l


func _say(msg: String) -> void:
	if _status != null:
		_status.text = msg
