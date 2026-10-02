@tool
extends Control

# No-code chooser dock (Lite). Select a node, one click makes it a playable
# top-down character or an interactable prop. Pro adds the platformer mover and
# the follow camera.

const MOVER: Script = preload("res://addons/controller_lite/top_down_mover_lite.gd")
const INTERACTOR: Script = preload("res://addons/controller_lite/interactor_lite.gd")
const INTERACTABLE: Script = preload("res://addons/controller_lite/interactable_lite.gd")
const BUS: Script = preload("res://addons/controller_lite/controllers_bus_lite.gd")

var _speed: SpinBox
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
	v.add_child(_labeled("Move speed", _speed))

	var td_btn := Button.new()
	td_btn.text = "Make Top-Down Player"
	td_btn.pressed.connect(_make_player)
	v.add_child(td_btn)

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
	pro.text = "Pro unlocks: platformer mover (coyote time, jump buffer, variable jump), follow camera (deadzone, look-ahead, shake), button prompts that switch between keyboard and pad, touch-input methods."
	pro.add_theme_color_override("font_color", Color(0.62, 0.66, 0.78))
	v.add_child(pro)

	# long button labels wrap onto a second line instead of widening the dock
	for c in v.get_children():
		if c is Button:
			(c as Button).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


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
	var ir := _child_with(target, INTERACTOR)
	if ir != null:
		_say("'%s' already has an Interactor, so nothing new was added.%s" % [target.name, _reshape(ir, Vector2(48, 48))])
		return
	ir = _inert(INTERACTOR)
	ir.name = "Interactor"
	_own(target, ir)
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
	var ia := _interactable_of(target)
	if ia == null:
		ia = _inert(INTERACTABLE)
		ia.name = "Interactable"
		target.add_child(ia, true)
		ia.owner = root
	if not _has_shape(ia):
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
		if c is CollisionShape2D or c is CollisionPolygon2D:
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
	if target.get_script() == INTERACTABLE:
		return target
	return _child_with(target, INTERACTABLE)


func _has_interactor(root: Node) -> bool:
	for n in root.find_children("*", "", true, false):
		if n.get_script() == INTERACTOR:
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
		if c.get_script() == MOVER:
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
				or n is NinePatchRect):
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
