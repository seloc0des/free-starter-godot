@tool
extends Control

# No-code chooser dock (Lite). Select a node, one click makes it an enemy that
# chases the "player" group. Pro adds patrol routes, flee, swinging any node,
# and the wave spawner.

const BRAIN: Script = preload("res://addons/enemy_ai_lite/brain_lite.gd")
const NO_PLAYER := "Nothing in this scene is marked as the player yet, so this won't react to anything. Select your player node and press \"Make the selected node the player\"."
# Combat's docks bake 32x32 hitboxes and hurtboxes. The brain's own 40 stops it
# just short of touching with those, so contact hits never landed. Stopping at
# 3/4 of the two half-widths leaves them overlapping with room to spare.
const BOX_HALF := 16.0
const REACH := 0.75
const COMBAT_CFGS := ["res://addons/combat/plugin.cfg", "res://addons/combat_lite/plugin.cfg"]

var _detect: SpinBox
var _speed: SpinBox
var _status: Label
var _scroll: ScrollContainer


func _ready() -> void:
	name = "Enemy AI Lite"
	_build()


# A plain Control doesn't tell the dock slot how narrow its page can go, so say it
# here. Height is the scroll's job.
func _get_minimum_size() -> Vector2:
	return Vector2(_scroll.get_combined_minimum_size().x, 0.0) if _scroll != null else Vector2.ZERO


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

	v.add_child(_header("Enemy AI Lite: bake onto the selected node"))
	_detect = _num(20, 2000, 160)
	v.add_child(_labeled("Detect radius", _detect))
	_speed = _num(10, 1000, 140)
	v.add_child(_labeled("Chase speed", _speed))

	var brain_btn := Button.new()
	brain_btn.text = "Make Enemy (brain)"
	brain_btn.pressed.connect(_make_enemy)
	v.add_child(brain_btn)

	var player_btn := Button.new()
	player_btn.text = "Make the selected node the player"
	player_btn.tooltip_text = "Touch triggers, doors, zones and enemies only react to the node in the \"player\" group."
	player_btn.pressed.connect(_make_player)
	v.add_child(player_btn)

	v.add_child(HSeparator.new())
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Select a node, click a button."
	v.add_child(_status)

	var pro := Label.new()
	pro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pro.text = "Pro unlocks: waypoint patrol routes, flee at low health, swinging any node you point the brain at (a sword arc, a spell area), and the spawner (endless + waves)."
	pro.add_theme_color_override("font_color", Color(0.62, 0.66, 0.78))
	v.add_child(pro)

	# long button labels wrap onto a second line instead of widening the dock
	for c in v.get_children():
		if c is Button:
			(c as Button).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _make_enemy() -> void:
	var target := _selected()
	if target == null:
		_say("Select a node in the open scene first.")
		return
	# a picture goes inside a new body, anything else gets one baked on or under it
	var body: CharacterBody2D = body_for(target)
	if body == null and is_picture(target):
		_wrap_enemy(target)
		return
	if body == null:
		body = CharacterBody2D.new()
		body.name = "Enemy"
		_own(target, body)
		_add_shape(body, Vector2(18, 18))
	elif not _has_shape(body):
		_add_shape(body, Vector2(18, 18))
	# one brain per body, two would both drive it. Clicking again retunes this one.
	var brain := _find_brain(body)
	var had := brain != null
	if not had:
		brain = _inert(Node.new(), BRAIN)
		brain.name = "Brain"
	brain.set("detect_radius", float(_detect.value))
	brain.set("chase_speed", float(_speed.value))
	var root := EditorInterface.get_edited_scene_root()
	var reach := fit_reach(brain, body, root) + swing_note(brain, body, root)
	if had:
		var opened := _open_instance(brain)
		# nothing added, so nothing else flags the scene, and Play would run the old values
		EditorInterface.mark_scene_as_unsaved()
		_say("'%s' already had a Brain, so it was retuned: detect radius %d, chase speed %d.%s%s%s" % [body.name, int(_detect.value), int(_speed.value), reach, opened, _player_note()])
		return
	_own(body, brain)
	_say("Baked a Brain. It hunts the 'player' group; tune radii in the Inspector.%s%s" % [reach, _player_note()])


# A selected picture goes inside a new Enemy that takes its place, so the two
# move together in the game. A body made inside the picture walked off and left
# the picture standing there. One undo step, so Ctrl+Z puts the picture back.
func _wrap_enemy(picture: Node) -> void:
	var root: Node = EditorInterface.get_edited_scene_root()
	var why: String = wrap_refusal(root, picture)
	if why != "":
		_say(why)
		return
	var body: CharacterBody2D = new_enemy(float(_detect.value), float(_speed.value))
	wrap_picture(EditorInterface.get_editor_undo_redo(), root, picture, body)
	# the undo manager flags it too, this just matches the other buttons
	EditorInterface.mark_scene_as_unsaved()
	var sel: EditorSelection = EditorInterface.get_selection()
	sel.clear()
	sel.add_node(body)
	# measured once it's in the scene, same as a brain baked the usual way
	var brain: Node = _find_brain(body)
	var reach: String = fit_reach(brain, body, root) + swing_note(brain, body, root)
	_say("Put your picture inside a new Enemy so they move together. Baked a Brain onto it. It hunts the 'player' group; tune radii in the Inspector.%s%s" % [reach, _player_note()])


# ---- editor helpers ------------------------------------------------------

func _selected() -> Node:
	var sel := EditorInterface.get_selection().get_selected_nodes()
	return sel[0] if sel.size() > 0 else null


func _own(parent: Node, child: Node) -> void:
	# readable, so a second route or door is Door2 rather than @Area2D@1234
	parent.add_child(child, true)
	child.owner = EditorInterface.get_edited_scene_root()
	# no undo manager here, so flag the scene or Play runs the old file without this node
	EditorInterface.mark_scene_as_unsaved()


# BRAIN.new() from a tool script is a live instance that runs its game code in
# the editor (it chased the player right there). set_script gives the same inert
# placeholder a hand-added node gets, and saves the same.
func _inert(node: Node, script: Script) -> Node:
	node.set_script(script)
	return node


func _add_shape(parent: Node, size: Vector2) -> void:
	_own(parent, _shape(size))


func _shape(size: Vector2) -> CollisionShape2D:
	var shape := CollisionShape2D.new()
	shape.name = "Shape"
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	return shape


func _has_shape(node: Node) -> bool:
	for c in node.get_children():
		if c is CollisionShape2D or c is CollisionPolygon2D:
			return true
	return false


# placeholders report their script too, so this finds brains the dock just baked
func _find_brain(body: Node) -> Node:
	for c in body.get_children():
		if c.get_script() == BRAIN:
			return c
	return null


# the enemy an earlier click made under this node, if any
func _wrapped_enemy(target: Node) -> CharacterBody2D:
	for c in target.get_children():
		if c is CharacterBody2D and _find_brain(c) != null:
			return c
	return null


# A Brain inside an instanced enemy scene isn't saved with the level unless
# Editable Children is on, so its new values would vanish on save.
func _open_instance(node: Node) -> String:
	var root := EditorInterface.get_edited_scene_root()
	if node.owner == null or node.owner == root or root.is_editable_instance(node.owner):
		return ""
	root.set_editable_instance(node.owner, true)
	return " Turned on Editable Children for '%s' so the level saves its Brain." % node.owner.name


# ---- a picture selected (headless-safe, the suite calls these) -----------

# The body Make Enemy works on: the selection itself, the enemy an earlier click
# made under it, or the body a selected picture already sits in. null: none yet.
func body_for(target: Node) -> CharacterBody2D:
	var body: CharacterBody2D = target as CharacterBody2D
	if body == null:
		body = _wrapped_enemy(target)  # a second click reuses the enemy the first one made
	if body == null and is_picture(target):
		body = target.get_parent() as CharacterBody2D  # a body's picture means that body
	return body


# Draws on its own: a sprite, a polygon, a mesh, a line, or a colour box out in
# the level. A box laid out by a menu isn't one, it'd lose its place.
func is_picture(n: Node) -> bool:
	if (n is Sprite2D or n is AnimatedSprite2D or n is Polygon2D or n is MeshInstance2D
			or n is MultiMeshInstance2D or n is Line2D):
		return true
	return (n is ColorRect or n is TextureRect or n is NinePatchRect) and not (n.get_parent() is Control)


# Why this picture can't go inside a new Enemy here, or "" when it can.
func wrap_refusal(root: Node, picture: Node) -> String:
	if picture == root:
		return "Your picture is the top of this scene, so there's nowhere beside it to put an Enemy. Open your level, drag this scene into it from the FileSystem dock, select it there and click again."
	if picture.owner != root:
		return "'%s' belongs to another scene, so it can't be moved from here. Open that scene and click again." % picture.name
	return ""


# A whole new Enemy (shape, inert Brain) built before it goes in, so putting it
# in is one undo step.
func new_enemy(detect: float, chase: float) -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.name = "Enemy"
	body.add_child(_shape(Vector2(18, 18)), true)
	var brain: Node = _inert(Node.new(), BRAIN)
	brain.name = "Brain"
	brain.set("detect_radius", detect)
	brain.set("chase_speed", chase)
	body.add_child(brain, true)
	return body


# The body takes the picture's place (same parent, same spot in the Scene list,
# same position) and the picture goes inside it at 0,0, so nothing moves on
# screen. Its turn and size stay on the picture. One undo step through `ur`:
# the editor's undo manager, or a plain UndoRedo from the suite.
func wrap_picture(ur: Object, root: Node, picture: Node, body: Node) -> void:
	var parent: Node = picture.get_parent()
	var at: int = picture.get_index()
	var was: Vector2 = picture.get("position")
	body.set("position", was)
	var made: Array[Node] = [body]
	made.append_array(body.find_children("*", "", true, false))
	var what: String = "Put the picture inside a new %s" % body.name
	if ur is UndoRedo:
		ur.create_action(what)
	else:
		ur.create_action(what, UndoRedo.MERGE_DISABLE, root)
	_undo_step(ur, true, parent, &"add_child", [body, true])
	_undo_step(ur, true, parent, &"move_child", [body, at])
	# reparent keeps the owner on the picture and everything under it
	_undo_step(ur, true, picture, &"reparent", [body, false])
	ur.add_do_property(picture, "position", Vector2.ZERO)
	# a node that leaves the scene loses its owner, and redo brings these back
	for n in made:
		_undo_step(ur, true, n, &"set_owner", [root])
	ur.add_do_reference(body)
	_undo_step(ur, false, picture, &"reparent", [parent, false])
	_undo_step(ur, false, parent, &"move_child", [picture, at])
	ur.add_undo_property(picture, "position", was)
	_undo_step(ur, false, parent, &"remove_child", [body])
	ur.commit_action()


# The editor's undo manager takes the object, the method and its arguments, a
# plain UndoRedo takes a Callable.
func _undo_step(ur: Object, is_do: bool, obj: Object, method: StringName, args: Array) -> void:
	if ur is UndoRedo:
		var step: Callable = Callable(obj, method).bindv(args)
		if is_do:
			ur.add_do_method(step)
		else:
			ur.add_undo_method(step)
	else:
		ur.callv("add_do_method" if is_do else "add_undo_method", [obj, method] + args)


# ---- contact reach (headless-safe, the verify calls these) ---------------

# Gives the brain the attack radius that lets a Combat contact hitbox on `body`
# overlap the player's hurtbox, and says why. No boxes and no Combat pack: the
# brain keeps its own radius and nothing is said.
func fit_reach(brain: Node, body: Node, root: Node) -> String:
	var hit := _enemy_hitbox(body)
	var hurt := _player_hurtbox(root)
	var hit_half := _half_width(hit)
	var hurt_half := _half_width(hurt)
	var touch := _touch(body, root)
	var r := reach_for(hit_half, hurt_half, _combat_installed(), touch)
	if r < 0.0:
		return ""
	brain.set("attack_radius", r)
	var reach := _reach(hit_half, hurt_half)
	var msg := ""
	if touch + 2.0 > reach - 2.0:
		msg = " Attack radius set to %s, as close as its Combat hitbox reaches (%s). It can't reach far enough past the two bodies though: they touch at %s px and the boxes only overlap closer than %s px. Make the hitbox bigger." % [_px(r), _reach_why(hit_half, hurt_half, 0.0), _px(touch), _px(reach)]
	else:
		msg = " Attack radius set to %s so its Combat hitbox overlaps the player's hurtbox (%s)." % [_px(r), _reach_why(hit_half, hurt_half, touch)]
	if hit != null and hurt != null and int(hit.get("team")) == int(hurt.get("team")):
		msg += " Its hitbox and the player's hurtbox are on the same side though, so it can't hurt the player: in the Combat dock give the player Player side health and this enemy an Enemy side hitbox."
	return msg


# 3/4 of the reach (the two half-widths added, a box that isn't there yet
# counting as the Combat dock's 32x32 one), but at least 2 px past where the two
# bodies touch, or they stop it before it ever attacks, and at most 2 px inside
# the reach. -1 means leave the brain alone.
func reach_for(hit_half: float, hurt_half: float, combat: bool, touch: float = 0.0) -> float:
	if hit_half < 0.0 and hurt_half < 0.0 and not combat:
		return -1.0
	var reach := _reach(hit_half, hurt_half)
	var r := minf(maxf(REACH * reach, touch + 2.0), reach - 2.0)
	return maxf(1.0, floorf(r * 10.0) / 10.0)


func _reach(hit_half: float, hurt_half: float) -> float:
	return (hit_half if hit_half >= 0.0 else BOX_HALF) + (hurt_half if hurt_half >= 0.0 else BOX_HALF)


func _reach_why(hit_half: float, hurt_half: float, touch: float) -> String:
	var why := "sized for the Combat dock's 32x32 boxes"
	if hit_half >= 0.0 and hurt_half >= 0.0:
		why = "measured from both boxes"
	elif hit_half >= 0.0:
		why = "measured from its hitbox, with the player's hurtbox counted as the Combat dock's 32x32 box"
	elif hurt_half >= 0.0:
		why = "measured from the player's hurtbox, with its hitbox counted as the Combat dock's 32x32 box"
	if touch + 2.0 > REACH * _reach(hit_half, hurt_half):
		why += ", and 2 px past where the two bodies touch (%s px) so they can't stop it short of attacking" % _px(touch)
	return why


# The brain switches a Combat hitbox on its body back on for every attack (a
# hitbox only hits when something starts touching it), so say so when there's
# one, unless it can't hurt the player anyway.
func swing_note(brain: Node, body: Node, root: Node = null) -> String:
	for c in body.get_children():
		if _is_hitbox(c):
			if root != null and _wont_hurt(body, root):
				return ""
			return " It switches that hitbox on for each attack, so it keeps hurting the player every %s s while in reach." % _px(float(brain.get("attack_cooldown")))
	return ""


# the bodies hold it off, or its hitbox is on the player's own side
func _wont_hurt(body: Node, root: Node) -> bool:
	var hit := _enemy_hitbox(body)
	var hurt := _player_hurtbox(root)
	if hit != null and hurt != null and int(hit.get("team")) == int(hurt.get("team")):
		return true
	return _touch(body, root) + 2.0 > _reach(_half_width(hit), _half_width(hurt)) - 2.0


func _combat_installed() -> bool:
	for p in COMBAT_CFGS:
		if FileAccess.file_exists(p):
			return true
	return false


func _enemy_hitbox(body: Node) -> Node:
	for n in body.find_children("*", "", true, false):
		if _is_hitbox(n):
			return n
	return null


# the first hurtbox on whatever this scene marks as the player
func _player_hurtbox(root: Node) -> Node:
	for p in _scene_players(root):
		if _is_hurtbox(p):
			return p
		for n in p.find_children("*", "", true, false):
			if _is_hurtbox(n):
				return n
	return null


# the physics body of whatever this scene marks as the player
func _player_body(root: Node) -> Node:
	for p in _scene_players(root):
		if p is PhysicsBody2D or p is PhysicsBody3D:
			return p
		for n in p.find_children("*", "", true, false):
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




# Combat Pro and Lite boxes, told apart by their exports so neither pack has to
# be installed for this dock to load.
func _is_hitbox(n: Node) -> bool:
	return (n is Area2D or n is Area3D) and "team" in n and ("base_damage" in n or "damage" in n)


func _is_hurtbox(n: Node) -> bool:
	return (n is Area2D or n is Area3D) and "team" in n and "health_path" in n


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


# ---- player group --------------------------------------------------------

func _player_note() -> String:
	var root := EditorInterface.get_edited_scene_root()
	if root == null or not root.is_inside_tree():
		return ""
	for n in root.get_tree().get_nodes_in_group("player"):
		if n == root or root.is_ancestor_of(n):
			return ""
	return " " + NO_PLAYER


func _make_player() -> void:
	var target := _selected()
	if target == null:
		_say("Select your player node first.")
		return
	# persistent, so the group saves with the scene. Re-added because a
	# membership from a live script isn't persistent and add_to_group() won't
	# upgrade it.
	if target.is_in_group("player"):
		target.remove_from_group("player")
	target.add_to_group("player", true)
	EditorInterface.mark_scene_as_unsaved()
	_say("%s is now the player." % target.name)


# ---- ui helpers ----------------------------------------------------------

func _num(min_v: float, max_v: float, value: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.value = value
	return s


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
