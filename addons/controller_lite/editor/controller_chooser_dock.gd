@tool
extends Control

# No-code chooser dock (Lite). Select a node, one click makes it a playable
# top-down character or an interactable prop. Pro adds the platformer mover and
# the follow camera. Open a scene whose root is a Node3D and the same buttons
# build the 3D versions instead (a CharacterBody3D, a capsule, the 3D mover and
# a follow camera).

const MOVER: Script = preload("res://addons/controller_lite/top_down_mover_lite.gd")
const INTERACTOR: Script = preload("res://addons/controller_lite/interactor_lite.gd")
const INTERACTABLE: Script = preload("res://addons/controller_lite/interactable_lite.gd")
const BUS: Script = preload("res://addons/controller_lite/controllers_bus_lite.gd")
const MOVER_3D: Script = preload("res://addons/controller_lite/top_down_mover_lite_3d.gd")
const INTERACTOR_3D: Script = preload("res://addons/controller_lite/interactor_lite_3d.gd")
const INTERACTABLE_3D: Script = preload("res://addons/controller_lite/interactable_lite_3d.gd")
const CAMERA_3D: Script = preload("res://addons/controller_lite/follow_camera_lite_3d.gd")

var _speed: SpinBox
var _speed_label: Label
var _td_btn: Button
var _mode_3d: bool = false
var _speeds: Dictionary = {false: 200.0, true: 5.0}  # what was typed, per mode
var _prompt: LineEdit
var _message: LineEdit
var _status: Label
var _scroll: ScrollContainer


func _ready() -> void:
	name = "Controller Lite"
	_build()
	# picking a prop that's already interactable shows its prompt and message in
	# the fields, so a second click edits them instead of blanking them
	EditorInterface.get_selection().selection_changed.connect(_on_selection_changed)


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

	v.add_child(_header("Controller Lite: bake onto the selected node"))
	_speed = _num(10, 2000, 200)
	var speed_box: Control = _labeled("Move speed", _speed)
	_speed_label = speed_box.get_child(0) as Label
	v.add_child(speed_box)

	_td_btn = Button.new()
	_td_btn.text = "Make Top-Down Player"
	_td_btn.pressed.connect(func() -> void:
		if _in_3d():
			_make_player_3d()
		else:
			_make_player())
	v.add_child(_td_btn)

	var ir_btn := Button.new()
	ir_btn.text = "Add Interactor (press E reach)"
	ir_btn.pressed.connect(_add_interactor)
	v.add_child(ir_btn)

	_prompt = LineEdit.new()
	_prompt.text = "Use"
	_prompt.tooltip_text = "Shown above it while the player is in reach, after the key: \"E  Use\"."
	v.add_child(_labeled("Prompt text", _prompt))
	_message = LineEdit.new()
	_message.placeholder_text = "Optional, e.g. \"The door is locked.\""
	_message.tooltip_text = "Shown on screen for a moment when the player presses E at it. Empty shows nothing."
	v.add_child(_labeled("Message when used", _message))

	var ia_btn := Button.new()
	ia_btn.text = "Make Interactable"
	ia_btn.pressed.connect(_add_interactable)
	v.add_child(ia_btn)

	v.add_child(HSeparator.new())
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Select a node, click a button."
	v.add_child(_status)

	var pro := Label.new()
	pro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pro.text = "Pro unlocks: platformer mover and third-person mover (coyote time, jump buffer, variable jump), follow camera (deadzone, look-ahead, shake, orbit), button prompts that switch between keyboard and pad, touch-input methods."
	pro.add_theme_color_override("font_color", Color(0.62, 0.66, 0.78))
	v.add_child(pro)

	# long button labels wrap onto a second line instead of widening the dock
	for c in v.get_children():
		if c is Button:
			(c as Button).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	refresh_mode()


# The open scene's root decides 2D or 3D. A root that is neither (a plain Node)
# follows the node the click works on. Anything else, or no scene open, keeps
# today's 2D behaviour.
func _in_3d() -> bool:
	return is_3d_scene(EditorInterface.get_edited_scene_root(), _selected())


static func is_3d_scene(root: Node, target: Node = null) -> bool:
	if root is Node3D:
		return true
	if root == null or root is Node2D:
		return false
	return target is Node3D


# Relabels the buttons for the open scene. The plugin calls this when the scene
# changes, and a selection change catches the rest.
func refresh_mode() -> void:
	if _speed == null:
		return
	var three: bool = _in_3d()
	if three == _mode_3d:
		return
	_speeds[_mode_3d] = _speed.value
	_mode_3d = three
	_td_btn.text = "Make Player" if three else "Make Top-Down Player"
	_speed_label.text = "Move speed (m/s)" if three else "Move speed"
	# a speed typed for pixels would be a rocket in metres, so the box swaps ranges too
	_speed.min_value = 0.5 if three else 10.0
	_speed.max_value = 40.0 if three else 2000.0
	_speed.step = 0.5 if three else 1.0
	_speed.value = float(_speeds[three])


func _make_player() -> void:
	var target := _selected()
	if target == null:
		_say("Select a node in the open scene first.")
		return
	var root := EditorInterface.get_edited_scene_root()
	# a picture goes inside a new body, anything else gets one baked on or under it
	var body: CharacterBody2D = body_for(target)
	if body == null and is_picture(target):
		_wrap_player(root, target)
		return
	if body == null:
		body = CharacterBody2D.new()
		body.name = "Player"
		_own(target, body)
		_add_shape(body, Vector2(20, 20))
	elif not _has_shape(body):
		_add_shape(body, Vector2(20, 20))
	# One mover per body: clicking again retunes the one that's there. Extras
	# stacked by an older version of this dock go, as long as this scene owns them.
	var movers := _movers(body)
	var mover: Node = movers[0] if not movers.is_empty() else null
	for m in movers:
		if m != mover and m.owner == root:
			body.remove_child(m)
			m.queue_free()
	# The mover only joins "player" once the game runs, and other packs' docks
	# look for that group in the editor. Tag it for keeps so it saves with the
	# scene. add_to_group() on a node already in the group changes nothing, not
	# even persistence, so drop a runtime-only membership first.
	if body.is_in_group("player"):
		body.remove_from_group("player")
	body.add_to_group("player", true)
	var msg := ""
	if mover != null:
		mover.set("speed", float(_speed.value))
		# no node added, so nothing else flags the scene
		EditorInterface.mark_scene_as_unsaved()
		msg = "'%s' already had a TopDownMover. Set it to %d px/s. It's marked as the player." % [body.name, int(_speed.value)]
	else:
		mover = _inert(MOVER)
		mover.name = "TopDownMover"
		mover.set("speed", float(_speed.value))
		_own(body, mover)
		msg = "Baked a top-down player (%d px/s) and marked it as the player. Arrows move it. Press Play." % int(_speed.value)
	if not _has_visual(body):
		msg += " It has no picture yet, so it'll be invisible when you press Play. Drop your picture onto '%s' in the Scene list (or select the picture first next time and it's wrapped for you)." % body.name
	_say(msg)


# A selected picture goes inside a new Player that takes its place, so the two
# move together in the game. A body made inside the picture walked off and left
# the picture standing there. One undo step, so Ctrl+Z puts the picture back.
func _wrap_player(root: Node, picture: Node) -> void:
	var why: String = wrap_refusal(root, picture)
	if why != "":
		_say(why)
		return
	var body: CharacterBody2D = new_player(float(_speed.value))
	wrap_picture(EditorInterface.get_editor_undo_redo(), root, picture, body)
	# the undo manager flags it too, this just matches the other buttons
	EditorInterface.mark_scene_as_unsaved()
	var sel: EditorSelection = EditorInterface.get_selection()
	sel.clear()
	sel.add_node(body)
	_say("Put your picture inside a new Player so they move together. Baked a top-down player (%d px/s) and marked it as the player. Arrows move it. Press Play." % int(_speed.value))


func _add_interactor() -> void:
	var target := _selected()
	if target == null:
		_say("Select your player body first.")
		return
	# a second click reuses the one that's there (and gives back a shape if it lost it)
	var three: bool = _in_3d()
	var ir := _child_with(target, INTERACTOR_3D if three else INTERACTOR)
	if ir != null:
		_say("'%s' already has an Interactor, so nothing new was added.%s" % [target.name, _reshape_3d(ir) if three else _reshape(ir, Vector2(48, 48))])
		return
	ir = _inert(INTERACTOR_3D if three else INTERACTOR)
	ir.name = "Interactor"
	_own(target, ir)
	if three:
		_reach_shape_3d(ir, EditorInterface.get_edited_scene_root())
	else:
		_add_shape(ir, Vector2(48, 48))
	_say("Added Interactor to '%s'. The player presses E (or Enter) to use the nearest Interactable." % target.name)


func _add_interactable() -> void:
	var target := _selected()
	if target == null:
		_say("Select the prop/NPC node first.")
		return
	var root := EditorInterface.get_edited_scene_root()
	var existing := _interactable_of(target)
	var lost_shape := existing != null and not _has_shape(existing)
	var ia := wire_interactable(root, target, _prompt.text, _message.text)
	# adding and editing both skip the undo manager, so flag the scene either way
	EditorInterface.mark_scene_as_unsaved()
	_say(interactable_status(root, target, ia, existing == null, lost_shape))


# Headless-safe, so the suite can check it. One Interactable per prop: a second
# click updates its prompt and message instead of adding another.
func wire_interactable(root: Node, target: Node, prompt_text: String, message: String) -> Node:
	var three: bool = is_3d_scene(root, target)
	var ia := _interactable_of(target)
	if ia == null:
		ia = _inert(INTERACTABLE_3D if three else INTERACTABLE)
		ia.name = "Interactable"
		target.add_child(ia, true)
		ia.owner = root
	if not _has_shape(ia):
		if three:
			_box_shape_3d(ia, Vector3(1.5, 1.5, 1.5), Vector3(0.0, 0.75, 0.0), root)
		else:
			_shape_under(ia, Vector2(40, 40), root)
	ia.set("prompt_text", prompt_text.strip_edges() if prompt_text.strip_edges() != "" else "Use")
	ia.set("message", message.strip_edges())
	return ia


func interactable_status(root: Node, target: Node, ia: Node, added: bool, reshaped: bool) -> String:
	var key: String = BUS.key_label(&"interact")
	var msg := ("Made '%s' interactable." % target.name) if added else ("Updated the prompt and message on '%s'." % target.name)
	msg += " In reach, the player sees \"%s  %s\" above it" % [key, str(ia.get("prompt_text"))]
	var said := str(ia.get("message"))
	if said != "":
		msg += ", and pressing %s shows \"%s\"" % [key, said]
		msg += "" if said.right(1) in [".", "!", "?"] else "."
	else:
		msg += ". Type a message to show one when they press %s." % key
	if reshaped:
		msg += " Gave it back a collision shape."
	if not _has_interactor(root):
		msg += " Nothing in this scene has an Interactor yet: select your player and press \"Add Interactor\"."
	return msg


func _on_selection_changed() -> void:
	refresh_mode()
	var sel := EditorInterface.get_selection().get_selected_nodes()
	if sel.is_empty() or _prompt == null:
		return
	var ia := _interactable_of(sel[0])
	if ia == null:
		return
	var p: Variant = ia.get("prompt_text")
	var m: Variant = ia.get("message")
	_prompt.text = str(p) if p != null else "Use"
	_message.text = str(m) if m != null else ""


# ---- editor helpers ------------------------------------------------------

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
	child.owner = EditorInterface.get_edited_scene_root()
	# no undo manager here, so flag the scene or Play runs the old file without this node
	EditorInterface.mark_scene_as_unsaved()


func _add_shape(parent: Node, size: Vector2) -> void:
	_shape_under(parent, size, EditorInterface.get_edited_scene_root())
	EditorInterface.mark_scene_as_unsaved()


func _shape_under(parent: Node, size: Vector2, root: Node) -> void:
	var shape := CollisionShape2D.new()
	shape.name = "Shape"
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	parent.add_child(shape, true)
	shape.owner = root


func _has_shape(node: Node) -> bool:
	for c in node.get_children():
		if c is CollisionShape2D or c is CollisionPolygon2D or c is CollisionShape3D or c is CollisionPolygon3D:
			return true
	return false


# The child running this script, if an earlier click already made one
# (placeholders report their script too).
func _child_with(target: Node, script: Script) -> Node:
	for c in target.get_children():
		if c.get_script() == script:
			return c
	return null


# The Interactable on this prop: the prop itself when it already is one (so it's
# never nested inside itself), else its child.
func _interactable_of(target: Node) -> Node:
	if target.get_script() == INTERACTABLE or target.get_script() == INTERACTABLE_3D:
		return target
	var found := _child_with(target, INTERACTABLE)
	return found if found != null else _child_with(target, INTERACTABLE_3D)


func _has_interactor(root: Node) -> bool:
	for n in root.find_children("*", "", true, false):
		if n.get_script() == INTERACTOR or n.get_script() == INTERACTOR_3D:
			return true
	return false


# A reused area that lost its shape gets one back. Returns the status note.
func _reshape(area: Node, size: Vector2) -> String:
	if _has_shape(area):
		return ""
	_add_shape(area, size)  # _own() flags the scene
	return " Gave it back a collision shape."


# The movers sitting on this body (placeholders report their script too).
func _movers(body: Node) -> Array:
	var out: Array = []
	for c in body.get_children():
		if c.get_script() == MOVER or c.get_script() == MOVER_3D:
			out.append(c)
	return out


# A plain node that was wrapped once already has its Player body, mover and all.
func _wrapped_body(target: Node) -> CharacterBody2D:
	for c in target.get_children():
		if c is CharacterBody2D and not _movers(c).is_empty():
			return c
	return null


# Anything under the body that draws, however deep (a Visuals node, an instanced
# sprite scene). A shape alone draws nothing once the game runs.
func _has_visual(body: Node) -> bool:
	for n in body.find_children("*", "", true, false):
		if (n is Sprite2D or n is AnimatedSprite2D or n is Polygon2D or n is MeshInstance2D
				or n is MultiMeshInstance2D or n is Line2D or n is ColorRect or n is TextureRect
				or n is NinePatchRect or n is GeometryInstance3D):
			return true
	return false


# ---- a picture selected (headless-safe, the suite calls these) -----------

# The body Make Player works on: the selection itself, the one an earlier click
# made under it, or the body a selected picture already sits in. null: none yet.
func body_for(target: Node) -> CharacterBody2D:
	var body: CharacterBody2D = target as CharacterBody2D
	if body == null:
		body = _wrapped_body(target)  # a second click reuses the body the first made
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


# Why this picture can't go inside a new Player here, or "" when it can.
func wrap_refusal(root: Node, picture: Node) -> String:
	if picture == root:
		return "Your picture is the top of this scene, so there's nowhere beside it to put a Player. Open your level, drag this scene into it from the FileSystem dock, select it there and click again."
	if picture.owner != root:
		return "'%s' belongs to another scene, so it can't be moved from here. Open that scene and click again." % picture.name
	return ""


# A whole new Player (shape, mover, player tag) built before it goes in, so
# putting it in is one undo step.
func new_player(speed: float) -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.name = "Player"
	body.add_to_group("player", true)
	_shape_under(body, Vector2(20, 20), null)
	var mover: Node = _inert(MOVER)
	mover.name = "TopDownMover"
	mover.set("speed", speed)
	body.add_child(mover, true)
	return body


# The body takes the picture's place (same parent, same spot in the Scene list,
# same position) and the picture goes inside it at 0,0, so nothing moves on
# screen. Its turn and size stay on the picture. One undo step through `ur`:
# the editor's undo manager, or a plain UndoRedo from the suite.
# `extra` is more nodes the same click adds, as [parent, node] pairs (the 3D
# build puts its camera in the same undo step).
func wrap_picture(ur: Object, root: Node, picture: Node, body: Node, extra: Array = []) -> void:
	var parent: Node = picture.get_parent()
	var at: int = picture.get_index()
	var was: Variant = picture.get("position")
	var zero: Variant = Vector3.ZERO if was is Vector3 else Vector2.ZERO
	body.set("position", was)
	var made: Array[Node] = [body]
	made.append_array(body.find_children("*", "", true, false))
	for pair in extra:
		made.append(pair[1])
		made.append_array((pair[1] as Node).find_children("*", "", true, false))
	var what: String = "Put the picture inside a new %s" % body.name
	if ur is UndoRedo:
		ur.create_action(what)
	else:
		ur.create_action(what, UndoRedo.MERGE_DISABLE, root)
	_undo_step(ur, true, parent, &"add_child", [body, true])
	_undo_step(ur, true, parent, &"move_child", [body, at])
	# reparent keeps the owner on the picture and everything under it
	_undo_step(ur, true, picture, &"reparent", [body, false])
	ur.add_do_property(picture, "position", zero)
	for pair in extra:
		_undo_step(ur, true, pair[0], &"add_child", [pair[1], true])
	# a node that leaves the scene loses its owner, and redo brings these back
	for n in made:
		_undo_step(ur, true, n, &"set_owner", [root])
	ur.add_do_reference(body)
	for pair in extra:
		ur.add_do_reference(pair[1])
	_undo_step(ur, false, picture, &"reparent", [parent, false])
	_undo_step(ur, false, parent, &"move_child", [picture, at])
	ur.add_undo_property(picture, "position", was)
	_undo_step(ur, false, parent, &"remove_child", [body])
	for pair in extra:
		_undo_step(ur, false, pair[0], &"remove_child", [pair[1]])
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


# ---- 3D builds (headless-safe, the suite calls these) --------------------
#
# Metres, not pixels: a 1.8 m capsule, a reach about a metre out. Nothing here
# reuses the 2D sizes.

const BODY_HEIGHT: float = 1.8
const BODY_RADIUS: float = 0.35


func _make_player_3d() -> void:
	var target := _selected()
	if target == null:
		_say("Select a node in the open scene first.")
		return
	var root := EditorInterface.get_edited_scene_root()
	var built: Dictionary = build_player_3d(EditorInterface.get_editor_undo_redo(), root, target, float(_speed.value))
	var body := built.get("body") as Node
	if body != null:
		# the undo manager flags the scene too, this just matches the other buttons
		EditorInterface.mark_scene_as_unsaved()
		var sel: EditorSelection = EditorInterface.get_selection()
		sel.clear()
		sel.add_node(body)
	_say(str(built["status"]))


## Make Player in a 3D scene, as one undo step. A selected CharacterBody3D is
## baked onto, a selected mesh or model goes inside a new body, anything else
## gets a new capsule Player under it. A follow camera goes in when the scene has
## no camera. Returns the status line and the body (null when nothing was done).
func build_player_3d(ur: Object, root: Node, target: Node, speed: float) -> Dictionary:
	var body: CharacterBody3D = body_for_3d(target, root)
	var steps: Array = []
	var wrapped: bool = false
	var where: String = ""
	var verb: String = "Built a Player with a"
	if body == null and is_picture_3d(target, root):
		var why: String = wrap_refusal(root, target)
		if why != "":
			return {"status": why, "body": null}
		body = new_player_3d(speed, false)
		wrapped = true
		where = "around your '%s'" % target.name
	elif body == null:
		body = new_player_3d(speed, true)
		var parent: Node = target if target is Node3D else root
		steps.append([&"add", parent, body])
		where = "under '%s'" % parent.name
	else:
		bake_onto_3d(root, body, speed, steps)
		verb = "Baked a"
		where = "onto '%s'" % body.name
	var cam_note: String = ""
	if not root.find_children("*", "Camera3D", true, false).is_empty() or root is Camera3D:
		cam_note = " Your scene already has a camera, so no follow camera was added."
	else:
		steps.append([&"add", root, new_camera_3d()])
		cam_note = " Added a FollowCamera."
	if wrapped:
		var extra: Array = []
		for st in steps:
			extra.append([st[1], st[2]])
		wrap_picture(ur, root, target, body, extra)
	else:
		_commit(ur, root, "Make Player", steps)
	var notes: String = " Tune feel in the Inspector. It needs something to stand on, such as a StaticBody3D with a collision shape."
	if not _has_visual(body):
		notes += " It has no mesh yet, so it will be invisible when you press Play."
	return {"status": "%s top-down mover (%s m/s) %s and marked it as the player, with an Interactor in front of it. WASD or the arrows move it, relative to the camera.%s%s" % [verb, str(snappedf(speed, 0.1)), where, cam_note, notes], "body": body}


# Adds what an existing body is missing (shape, mover, Interactor, player tag), as steps.
func bake_onto_3d(root: Node, body: Node, speed: float, steps: Array) -> void:
	if not _has_shape(body):
		steps.append([&"add", body, _new_shape_3d(_capsule_3d(), Vector3(0.0, BODY_HEIGHT * 0.5, 0.0))])
	var mover: Node = null
	for m in _movers(body):
		if m.get_script() == MOVER_3D and mover == null:
			mover = m
		elif m.owner == root:
			# a 2D mover left on this body fights the 3D one, so it goes (an instanced scene's stays)
			steps.append([&"remove", body, m])
	if mover != null:
		steps.append([&"prop", mover, "speed", speed, mover.get("speed")])
	else:
		steps.append([&"add", body, _new_mover_3d(speed)])
	if not body.is_in_group("player"):
		steps.append([&"call", body, &"add_to_group", [&"player", true], &"remove_from_group", [&"player"]])
	if _child_with(body, INTERACTOR_3D) == null:
		steps.append([&"add", body, _new_interactor_3d()])


func new_camera_3d() -> Node:
	var cam: Node = _inert(CAMERA_3D)
	cam.name = "FollowCamera"
	return cam


# A whole new Player (shape, mover, Interactor, player tag, and with `with_art` a
# capsule with a nose so the way it faces shows) built before it goes in.
func new_player_3d(speed: float, with_art: bool) -> CharacterBody3D:
	var body: CharacterBody3D = CharacterBody3D.new()
	body.name = "Player"
	body.add_to_group("player", true)
	body.add_child(_new_shape_3d(_capsule_3d(), Vector3(0.0, BODY_HEIGHT * 0.5, 0.0)), true)
	if with_art:
		var capsule: CapsuleMesh = CapsuleMesh.new()
		capsule.radius = BODY_RADIUS
		capsule.height = BODY_HEIGHT
		body.add_child(_new_mesh_3d("Body", capsule, Vector3(0.0, BODY_HEIGHT * 0.5, 0.0), Color(0.25, 0.5, 0.9)), true)
		var nose: BoxMesh = BoxMesh.new()
		nose.size = Vector3(0.16, 0.16, 0.3)
		body.add_child(_new_mesh_3d("Nose", nose, Vector3(0.0, BODY_HEIGHT * 0.78, -BODY_RADIUS - 0.05), Color(1.0, 0.6, 0.15)), true)
	body.add_child(_new_mover_3d(speed), true)
	body.add_child(_new_interactor_3d(), true)
	return body


func _new_mover_3d(speed: float) -> Node:
	var mover: Node = _inert(MOVER_3D)
	mover.name = "TopDownMover"
	mover.set("speed", speed)
	return mover


# Reach: a ball a little ahead of the body, so it swings with the body as it turns.
func _new_interactor_3d() -> Node:
	var ir: Node = _inert(INTERACTOR_3D)
	ir.name = "Interactor"
	var ball: SphereShape3D = SphereShape3D.new()
	ball.radius = 1.1
	ir.add_child(_new_shape_3d(ball, Vector3(0.0, BODY_HEIGHT * 0.5, -0.6)), true)
	return ir


func _capsule_3d() -> CapsuleShape3D:
	var c: CapsuleShape3D = CapsuleShape3D.new()
	c.radius = BODY_RADIUS
	c.height = BODY_HEIGHT
	return c


func _new_shape_3d(shape: Shape3D, at: Vector3) -> CollisionShape3D:
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = shape
	cs.position = at
	return cs


func _new_mesh_3d(mesh_name: String, mesh: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = mesh_name
	mi.mesh = mesh
	mi.position = at
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	return mi


func _box_shape_3d(parent: Node, size: Vector3, at: Vector3, root: Node) -> void:
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	var cs: CollisionShape3D = _new_shape_3d(box, at)
	parent.add_child(cs, true)
	cs.owner = root


func _reach_shape_3d(parent: Node, root: Node) -> void:
	var ball: SphereShape3D = SphereShape3D.new()
	ball.radius = 1.1
	var cs: CollisionShape3D = _new_shape_3d(ball, Vector3(0.0, BODY_HEIGHT * 0.5, -0.6))
	parent.add_child(cs, true)
	cs.owner = root


# A reused area that lost its shape gets one back. Returns the status note.
func _reshape_3d(area: Node) -> String:
	if _has_shape(area):
		return ""
	_reach_shape_3d(area, EditorInterface.get_edited_scene_root())
	EditorInterface.mark_scene_as_unsaved()
	return " Gave it back a collision shape."


# The body Make Player works on in a 3D scene: the selection itself, the one an
# earlier click made under it, or the body a selected mesh already sits in.
func body_for_3d(target: Node, root: Node) -> CharacterBody3D:
	var body: CharacterBody3D = target as CharacterBody3D
	if body == null:
		for c in target.get_children():
			if c is CharacterBody3D and not _movers(c).is_empty():
				body = c as CharacterBody3D
				break
	if body == null and is_picture_3d(target, root):
		body = target.get_parent() as CharacterBody3D
	return body


# Draws on its own: a mesh, a sprite, or a model scene dropped into this one.
# A plain Node3D is not, so a new Player still goes under it.
func is_picture_3d(n: Node, root: Node) -> bool:
	if n is GeometryInstance3D:
		return true
	return (n is Node3D and n.scene_file_path != "" and n != root
			and not (n is CollisionObject3D or n is Camera3D or n is Light3D))


# One undo step for everything a click changes. `steps` entries:
#   [&"add", parent, node]   add a node (and everything under it), owned by the scene
#   [&"remove", parent, node]
#   [&"prop", object, name, new, old]
#   [&"call", object, do_method, do_args, undo_method, undo_args]
# `ur` is the editor's undo manager or a plain UndoRedo from the suite.
func _commit(ur: Object, root: Node, what: String, steps: Array) -> void:
	if ur is UndoRedo:
		ur.create_action(what)
	else:
		ur.create_action(what, UndoRedo.MERGE_DISABLE, root)
	var made: Array[Node] = []
	for st in steps:
		match st[0]:
			&"add":
				_undo_step(ur, true, st[1], &"add_child", [st[2], true])
				made.append(st[2])
				made.append_array((st[2] as Node).find_children("*", "", true, false))
			&"remove":
				_undo_step(ur, true, st[1], &"remove_child", [st[2]])
			&"prop":
				ur.add_do_property(st[1], st[2], st[3])
			&"call":
				_undo_step(ur, true, st[1], st[2], st[3])
	# a node that leaves the scene loses its owner, and redo brings these back
	for n in made:
		_undo_step(ur, true, n, &"set_owner", [root])
	for st in steps:
		if st[0] == &"add":
			ur.add_do_reference(st[2])
	for i in range(steps.size() - 1, -1, -1):
		var st: Array = steps[i]
		match st[0]:
			&"add":
				_undo_step(ur, false, st[1], &"remove_child", [st[2]])
			&"remove":
				# once redone, the removed node belongs to the history, which frees it
				ur.add_undo_reference(st[2])
				_undo_step(ur, false, st[1], &"add_child", [st[2], true])
				_undo_step(ur, false, st[2], &"set_owner", [root])
			&"prop":
				ur.add_undo_property(st[1], st[2], st[4])
			&"call":
				_undo_step(ur, false, st[1], st[4], st[5])
	ur.commit_action()


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
