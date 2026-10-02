extends RefCounted

# The Controller (Lite) dock's "no picture yet" hint. A baked player with nothing to draw
# runs fine but is invisible when you press Play, which reads as "it's broken".
# The buttons need the editor (the journey probe clicks those); the check that
# decides the hint doesn't, so it's tested here against real node trees.

const DOCK := preload("res://addons/controller_lite/editor/controller_chooser_dock.gd")
const INTERACTABLE := preload("res://addons/controller_lite/interactable_lite.gd")
const INTERACTOR := preload("res://addons/controller_lite/interactor_lite.gd")
const MOVER := preload("res://addons/controller_lite/top_down_mover_lite.gd")


static func run(host: Node) -> Dictionary:
	var lines: Array[String] = []
	var ok := true
	var dock: Control = DOCK.new()

	var body := CharacterBody2D.new()
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	body.add_child(shape)
	body.add_child(Node.new())  # a mover
	ok = _chk(lines, not dock._has_visual(body), "dock: a body with only a shape and a mover counts as invisible") and ok

	var sprite := Sprite2D.new()
	body.add_child(sprite)
	ok = _chk(lines, dock._has_visual(body), "dock: a Sprite2D under it counts as a visual") and ok
	sprite.free()

	# the demo's player draws with a ColorRect, and art often sits a level down
	var rect_body := CharacterBody2D.new()
	var rect := ColorRect.new()
	rect_body.add_child(rect)
	ok = _chk(lines, dock._has_visual(rect_body), "dock: a ColorRect counts as a visual") and ok
	var nested := CharacterBody2D.new()
	var visuals := Node2D.new()
	nested.add_child(visuals)
	visuals.add_child(AnimatedSprite2D.new())
	ok = _chk(lines, dock._has_visual(nested), "dock: an AnimatedSprite2D inside a Visuals node counts") and ok
	var poly := CharacterBody2D.new()
	poly.add_child(Polygon2D.new())
	ok = _chk(lines, dock._has_visual(poly), "dock: a Polygon2D counts") and ok

	for n in [body, rect_body, nested, poly]:
		n.free()
	_interactable_wiring(dock, lines)
	_picture_wrap(host, dock, lines)
	ok = ok and not lines.any(func(l: String) -> bool: return l.begins_with("[XX]"))
	dock.free()
	return {"ok": ok, "lines": lines}


# Make Top-Down Player with your character's picture selected. The new Player
# takes the picture's place and the picture goes inside it, so they move together
# in the game (a body made inside the picture walked off without it). The button
# reads the selection and hands its halves the editor's undo manager; here they
# get a plain UndoRedo, so undo and redo are checked too.
static func _picture_wrap(host: Node, dock: Control, lines: Array[String]) -> void:
	if not dock.has_method("wrap_picture"):
		_chk(lines, false, "wrap: Make Top-Down Player can put a selected picture inside a new Player")
		return
	var level := Node2D.new()
	level.name = "Level"
	host.add_child(level)  # in the tree like an open scene, so a node taken out really loses its owner
	var ground := _owned(level, level, Node2D.new(), "Ground")
	var hero := _owned(level, level, Sprite2D.new(), "Hero") as Sprite2D
	hero.position = Vector2(120, 80)
	hero.rotation = 0.5
	hero.scale = Vector2(2, 2)
	var hat := _owned(level, hero, Sprite2D.new(), "Hat") as Sprite2D
	hat.position = Vector2(0, -10)
	var rock := _owned(level, level, Node2D.new(), "Rock")
	var drawn := hero.global_transform
	var hat_drawn := hat.global_transform

	_chk(lines, dock.is_picture(hero) and dock.body_for(hero) == null and dock.wrap_refusal(level, hero) == "", "wrap: a selected Sprite2D with no body around it gets wrapped")
	var ur := UndoRedo.new()
	var body: CharacterBody2D = dock.new_player(250.0)
	dock.wrap_picture(ur, level, hero, body)
	_chk(lines, hero.get_parent() == body and body.get_parent() == level, "wrap: the picture is inside the new body, and the body is in the level")
	_chk(lines, body.get_index() == 1 and level.get_child(0) == ground and level.get_child(2) == rock and level.get_child_count() == 3,
		"wrap: the body takes the picture's spot in the Scene list (%d)" % body.get_index())
	_chk(lines, body.position == Vector2(120, 80) and hero.position == Vector2.ZERO,
		"wrap: the body stands where the picture stood, the picture sits at 0,0 inside it (%s, %s)" % [body.position, hero.position])
	_chk(lines, hero.global_transform.is_equal_approx(drawn) and hat.global_transform.is_equal_approx(hat_drawn), "wrap: nothing moves on screen, turn and size included")
	_chk(lines, String(body.name) == "Player" and String(hero.name) == "Hero" and hat.get_parent() == hero, "wrap: the body is called Player, the picture keeps its name and what's under it")
	var movers: Array = dock._movers(body)
	_chk(lines, body.is_in_group("player") and dock._has_shape(body) and movers.size() == 1 and movers[0].get_script() == MOVER and float(movers[0].get("speed")) == 250.0,
		"wrap: the body gets its shape, one TopDownMover at the dock's speed, and the player tag")
	var everything: Array = [body, hero, hat]
	everything.append_array(body.get_children())
	_chk(lines, _all_owned(level, everything), "wrap: the body, its shape and mover, the picture and what's under it all save with the scene")
	var ps := PackedScene.new()
	ps.pack(level)
	var copy := ps.instantiate()
	_chk(lines, copy.get_node_or_null("Player/Hero/Hat") != null and copy.get_node_or_null("Player/TopDownMover") != null and copy.get_node("Player").is_in_group("player"),
		"wrap: the saved scene has Player > Hero > Hat, the mover and the player tag")
	copy.free()

	ur.undo()
	_chk(lines, hero.get_parent() == level and hero.get_index() == 1 and level.get_child_count() == 3 and hero.position == Vector2(120, 80) and hero.global_transform.is_equal_approx(drawn),
		"wrap: undo puts the picture back exactly where it was")
	_chk(lines, hero.owner == level and hat.owner == level and not body.is_inside_tree(), "wrap: after undo the picture still saves with the scene, and the body is gone")
	ur.redo()
	_chk(lines, hero.get_parent() == body and body.get_index() == 1 and hero.position == Vector2.ZERO and _all_owned(level, everything), "wrap: redo puts it back inside, all of it saved with the scene")

	# anything that isn't a picture keeps what the button did before
	var npc := _owned(level, level, Node2D.new(), "NPC")
	_chk(lines, not dock.is_picture(npc) and dock.body_for(npc) == null, "wrap: a plain node isn't a picture, so a new Player still goes under it")
	_chk(lines, not dock.is_picture(level) and dock.body_for(body) == body, "wrap: the level isn't either, and a selected body is baked onto as before")
	_chk(lines, dock.body_for(hero) == body, "wrap: a picture already inside a body means that body, so no second body goes in")
	var menu := _owned(level, level, Control.new(), "Menu")
	var in_menu := _owned(level, menu, ColorRect.new(), "Box")
	var in_level := _owned(level, level, ColorRect.new(), "Crate")
	_chk(lines, dock.is_picture(in_level) and not dock.is_picture(in_menu), "wrap: a colour box out in the level is a picture, one laid out in a menu isn't")
	var solo := Sprite2D.new()
	_chk(lines, dock.wrap_refusal(solo, solo).begins_with("Your picture is the top of this scene"), "wrap: a picture at the top of its own scene is refused, with what to do instead")
	solo.free()
	var other := _owned(level, level, Node2D.new(), "House")
	var inner := _owned(level, other, Sprite2D.new(), "Window")
	inner.owner = other  # as if it came in with an instanced scene
	_chk(lines, dock.wrap_refusal(level, inner).contains("belongs to another scene"), "wrap: a picture inside another scene is refused, with what to do instead")

	# the live mover told the bus about its body, and the body's going away
	var bus := host.get_tree().root.get_node_or_null("ControllersLite")
	if bus != null and is_same(bus.get("player"), body):
		bus.set("player", null)
	ur.free()
	level.free()


static func _owned(root: Node, parent: Node, n: Node, n_name: String) -> Node:
	n.name = n_name
	parent.add_child(n)
	n.owner = root
	return n


static func _all_owned(root: Node, nodes: Array) -> bool:
	for n in nodes:
		if (n as Node).owner != root:
			return false
	return true


# "Make Interactable" with the prompt and message fields, as the button's pure half.
static func _interactable_wiring(dock: Control, lines: Array[String]) -> void:
	var level := Node2D.new()
	level.name = "Level"
	var sign_node := Node2D.new()
	sign_node.name = "Sign"
	level.add_child(sign_node)
	sign_node.owner = level

	var ia: Node = dock.wire_interactable(level, sign_node, "Read", "Welcome to town.")
	_chk(lines, ia != null and ia.get_script() == INTERACTABLE, "dock: Make Interactable adds an InteractableLite")
	_chk(lines, ia.get_parent() == sign_node and ia.owner == level and String(ia.name) == "Interactable", "dock: under the prop, named Interactable, owned by the scene")
	var shapes: Array = ia.get_children().filter(func(c: Node) -> bool: return c is CollisionShape2D)
	_chk(lines, shapes.size() == 1 and shapes[0].owner == level, "dock: it gets one collision shape, saved with the scene")
	_chk(lines, ia.get("prompt_text") == "Read" and ia.get("message") == "Welcome to town.", "dock: the prompt text and message fields land on the node")
	var st: String = dock.interactable_status(level, sign_node, ia, true, false)
	_chk(lines, st.begins_with("Made 'Sign' interactable.") and st.contains("\"E  Read\"") and st.contains("\"Welcome to town.\""), "dock: status says what the player sees (%s)" % st)
	_chk(lines, st.ends_with("select your player and press \"Add Interactor\"."), "dock: status says when nothing has an Interactor yet")

	# second click: same node, new texts, no second shape
	var again: Node = dock.wire_interactable(level, sign_node, "  ", "The sign is blank now.")
	var count := 0
	for c in sign_node.get_children():
		if c.get_script() == INTERACTABLE:
			count += 1
	_chk(lines, again == ia and count == 1, "dock: a second click updates the same Interactable (%d)" % count)
	_chk(lines, again.get("prompt_text") == "Use" and again.get("message") == "The sign is blank now.", "dock: an empty prompt falls back to \"Use\" and the message updates")
	_chk(lines, ia.get_children().filter(func(c: Node) -> bool: return c is CollisionShape2D).size() == 1, "dock: still one shape after the second click")
	_chk(lines, dock.interactable_status(level, sign_node, again, false, false).begins_with("Updated the prompt and message on 'Sign'."), "dock: status says it updated")

	# the Interactable itself selected: edit it, don't nest a second one inside it
	var direct: Node = dock.wire_interactable(level, ia, "Open", "")
	_chk(lines, direct == ia and ia.get_children().filter(func(c: Node) -> bool: return c.get_script() == INTERACTABLE).is_empty(), "dock: selecting the Interactable itself edits it")

	# with an Interactor in the scene the hint goes away
	var player := CharacterBody2D.new()
	level.add_child(player)
	player.owner = level
	var reach: Node = INTERACTOR.new()
	player.add_child(reach)
	reach.owner = level
	_chk(lines, not dock.interactable_status(level, sign_node, ia, false, false).contains("Add Interactor"), "dock: no Interactor hint once the player has one")

	# what's saved with the scene
	var ps := PackedScene.new()
	ps.pack(level)
	var copy := ps.instantiate()
	var saved: Node = copy.get_node_or_null("Sign/Interactable")
	_chk(lines, saved != null and saved.get("prompt_text") == "Open" and saved.get("message") == "", "dock: the prompt and message are saved with the scene")
	copy.free()
	level.free()


# Async: the scene the dock builds, packed, then played with real physics and a real key.
static func run_played(host: Node) -> Dictionary:
	var lines: Array[String] = []
	var tree: SceneTree = host.get_tree()
	var dock: Control = DOCK.new()
	var level := Node2D.new()
	level.name = "Level"
	host.add_child(level)
	var player := CharacterBody2D.new()
	player.name = "Player"
	level.add_child(player)
	player.owner = level
	var reach: Node = INTERACTOR.new()
	reach.name = "Interactor"
	player.add_child(reach)
	reach.owner = level
	dock._shape_under(reach, Vector2(48, 48), level)
	var sign_node := Node2D.new()
	sign_node.name = "Sign"
	sign_node.position = Vector2(400, 0)
	level.add_child(sign_node)
	sign_node.owner = level
	var ia: Node = dock.wire_interactable(level, sign_node, "Read", "Welcome to town.")
	_chk(lines, ia.get_node_or_null("Prompt") != null, "played: a live Interactable builds its prompt label")
	var ps := PackedScene.new()
	ps.pack(level)
	level.free()
	dock.free()
	var state := ps.get_state()
	var labels := 0
	for i in state.get_node_count():
		if state.get_node_type(i) == &"Label":
			labels += 1
	_chk(lines, labels == 0, "played: that label is never saved into the scene")

	var game: Node = ps.instantiate()
	host.add_child(game)
	for i in 4:
		await tree.physics_frame
	var label := game.get_node_or_null("Sign/Interactable/Prompt") as Label
	_chk(lines, label != null and not label.visible, "played: no prompt while the player is away")
	(game.get_node("Player") as Node2D).global_position = Vector2(370, 0)
	for i in 4:
		await tree.physics_frame
	_chk(lines, label != null and label.visible and label.text == "E  Read", "played: walking up shows \"E  Read\" (got %s)" % (label.text if label != null else "no label"))
	for t in tree.get_nodes_in_group("lite_toast"):
		t.get_parent().free()
	var down := InputEventKey.new()
	down.physical_keycode = KEY_E
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.physical_keycode = KEY_E
	Input.parse_input_event(up)
	await tree.process_frame
	await tree.process_frame
	var texts := PackedStringArray()
	for t in tree.get_nodes_in_group("lite_toast"):
		texts.append(String(t.get("text")))
	_chk(lines, texts == PackedStringArray(["Welcome to town."]), "played: pressing E shows the message (got %s)" % str(texts))
	for t in tree.get_nodes_in_group("lite_toast"):
		t.get_parent().free()
	game.queue_free()
	return {"ok": not lines.any(func(l: String) -> bool: return l.begins_with("[XX]")), "lines": lines}


static func _chk(lines: Array[String], cond: bool, label: String) -> bool:
	lines.append(("[ok] " if cond else "[XX] ") + label)
	return cond
