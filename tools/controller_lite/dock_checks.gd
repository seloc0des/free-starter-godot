extends RefCounted

# The Controller (Lite) dock's "no picture yet" hint. A baked player with nothing to draw
# runs fine but is invisible when you press Play, which reads as "it's broken".
# The buttons need the editor (the journey probe clicks those); the check that
# decides the hint doesn't, so it's tested here against real node trees.

const DOCK := preload("res://addons/controller_lite/editor/controller_chooser_dock.gd")
const INTERACTABLE := preload("res://addons/controller_lite/interactable_lite.gd")
const INTERACTOR := preload("res://addons/controller_lite/interactor_lite.gd")
const MOVER := preload("res://addons/controller_lite/top_down_mover_lite.gd")
const MOVER_3D := preload("res://addons/controller_lite/top_down_mover_lite_3d.gd")
const INTERACTABLE_3D := preload("res://addons/controller_lite/interactable_lite_3d.gd")
const INTERACTOR_3D := preload("res://addons/controller_lite/interactor_lite_3d.gd")
const CAMERA_3D := preload("res://addons/controller_lite/follow_camera_lite_3d.gd")


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
	_builds_3d(host, dock, lines)
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


# The 3D half of the dock: what each button builds when the open scene's root is a
# Node3D. Undo and redo go through a plain UndoRedo here; the editor's takes the
# same calls.
static func _builds_3d(host: Node, dock: Control, lines: Array[String]) -> void:
	var probes: Array[Node] = [Node3D.new(), Node2D.new(), Control.new()]
	_chk(lines, dock.is_3d_scene(probes[0]) and not dock.is_3d_scene(probes[1]) and not dock.is_3d_scene(probes[2]) and not dock.is_3d_scene(null),
		"dock 3D: only a Node3D root counts as a 3D scene, so 2D, Control and empty scenes keep today's behaviour")
	for n: Node in probes:
		n.free()

	var level: Node3D = Node3D.new()
	level.name = "Level"
	host.add_child(level)
	var ur: UndoRedo = UndoRedo.new()

	# Make Player on a plain node: a whole new capsule Player and a camera
	var spot: Node = _owned(level, level, Node3D.new(), "Spot")
	_chk(lines, not dock.is_picture_3d(spot, level) and dock.body_for_3d(spot, level) == null, "dock 3D: a plain Node3D is not a picture, so a new Player goes under it")
	var made: Dictionary = dock.build_player_3d(ur, level, spot, 6.0)
	var body: CharacterBody3D = made["body"]
	_chk(lines, body != null and body.get_parent() == spot and String(body.name) == "Player" and body.is_in_group("player"), "dock 3D: Make Player builds a CharacterBody3D called Player under the selection, tagged as the player")
	var parts: Dictionary = {}
	for c in body.get_children():
		parts[String(c.name)] = c
	_chk(lines, parts.has("Shape") and parts.has("Body") and parts.has("Nose") and parts.has("TopDownMover") and parts.has("Interactor") and body.get_child_count() == 5,
		"dock 3D: with a collision shape, a capsule, a nose, the mover and an Interactor")
	var shape: CapsuleShape3D = (parts["Shape"] as CollisionShape3D).shape as CapsuleShape3D
	_chk(lines, shape != null and is_equal_approx(shape.height, 1.8) and shape.radius < 0.5 and is_equal_approx((parts["Shape"] as Node3D).position.y, 0.9), "dock 3D: the capsule is a 1.8 m person standing on its origin, not pixels")
	_chk(lines, (parts["Body"] as MeshInstance3D).mesh is CapsuleMesh and (parts["Nose"] as MeshInstance3D).position.z < -0.3, "dock 3D: the nose sits on the -Z side, so facing shows")
	_chk(lines, (parts["TopDownMover"] as Node).get_script() == MOVER_3D and is_equal_approx(float((parts["TopDownMover"] as Node).get("speed")), 6.0), "dock 3D: the mover is the 3D one at the dock's speed in m/s")
	var reach: Area3D = parts["Interactor"] as Area3D
	_chk(lines, reach.get_script() == INTERACTOR_3D and (reach.get_child(0) as CollisionShape3D).shape is SphereShape3D and (reach.get_child(0) as Node3D).position.z < 0.0, "dock 3D: the Interactor is a ball in front of the body")
	var cam: Node = _find_script(level, CAMERA_3D)
	_chk(lines, cam != null and cam.get_parent() == level, "dock 3D: a FollowCameraLite3D went in at the scene root")
	var all_nodes: Array = [body, cam]
	all_nodes.append_array(body.find_children("*", "", true, false))
	_chk(lines, _all_owned(level, all_nodes), "dock 3D: everything it built saves with the scene")
	var ps: PackedScene = PackedScene.new()
	ps.pack(level)
	var copy: Node = ps.instantiate()
	_chk(lines, copy.get_node_or_null("Spot/Player/TopDownMover") != null and copy.get_node_or_null("Spot/Player/Interactor/Shape") != null and copy.get_node("Spot/Player").is_in_group("player") and _find_script(copy, CAMERA_3D) != null,
		"dock 3D: the saved scene has the player, its mover, its Interactor and the camera")
	copy.free()
	_chk(lines, String(made["status"]).contains("StaticBody3D") and String(made["status"]).contains("6.0 m/s"), "dock 3D: the status says it needs a floor and gives m/s (%s)" % made["status"])

	ur.undo()
	_chk(lines, body.get_parent() == null and _find_script(level, CAMERA_3D) == null, "dock 3D: one undo removes the player and the camera together")
	ur.redo()
	_chk(lines, body.get_parent() == spot and cam.get_parent() == level and _all_owned(level, all_nodes), "dock 3D: redo brings both back, all saved with the scene")

	# the same button again retunes the mover it finds
	var again: Dictionary = dock.build_player_3d(ur, level, body, 3.0)
	_chk(lines, again["body"] == body and (parts["TopDownMover"] as Node).get("speed") == 3.0 and dock._movers(body).size() == 1 and _count_script(level, CAMERA_3D) == 1 and _count_script(body, INTERACTOR_3D) == 1,
		"dock 3D: the same button again retunes the mover, adding no second mover, Interactor or camera")

	# a scene that already has its own camera is left alone
	var level2: Node3D = Node3D.new()
	level2.name = "Level2"
	host.add_child(level2)
	var theirs: Node = _owned(level2, level2, Camera3D.new(), "MyCamera")
	var made2: Dictionary = dock.build_player_3d(ur, level2, level2, 5.0)
	_chk(lines, _find_script(level2, CAMERA_3D) == null and level2.find_children("*", "Camera3D", true, false).size() == 1 and theirs.owner == level2 and String(made2["status"]).contains("already has a camera") and (made2["body"] as Node).get_parent() == level2,
		"dock 3D: a scene with its own camera does not get a second one, and the status says so")

	# a mesh selected goes inside a new body that takes its place
	var hero: MeshInstance3D = _owned(level, level, MeshInstance3D.new(), "Hero") as MeshInstance3D
	hero.position = Vector3(3, 0, 2)
	hero.rotation.y = 0.5
	hero.scale = Vector3(1.5, 1.5, 1.5)
	var hat: MeshInstance3D = _owned(level, hero, MeshInstance3D.new(), "Hat") as MeshInstance3D
	hat.position = Vector3(0, 1, 0)
	var drawn: Transform3D = hero.global_transform
	var hat_drawn: Transform3D = hat.global_transform
	_chk(lines, dock.is_picture_3d(hero, level) and dock.body_for_3d(hero, level) == null, "dock 3D: a selected mesh with no body around it counts as a picture")
	var wrapped: Dictionary = dock.build_player_3d(ur, level, hero, 5.0)
	var wbody: CharacterBody3D = wrapped["body"]
	_chk(lines, hero.get_parent() == wbody and wbody.get_parent() == level and wbody.position.is_equal_approx(Vector3(3, 0, 2)) and hero.position == Vector3.ZERO,
		"dock 3D: the body stands where the mesh stood and the mesh sits at 0,0,0 inside it")
	_chk(lines, hero.global_transform.is_equal_approx(drawn) and hat.global_transform.is_equal_approx(hat_drawn), "dock 3D: nothing moves on screen, turn and size included")
	_chk(lines, wbody.get_node_or_null("Body") == null and wbody.get_node_or_null("TopDownMover") != null and wbody.get_node_or_null("Interactor") != null and wbody.is_in_group("player"),
		"dock 3D: your mesh is the art, so no capsule is added, but the mover, Interactor and player tag are")
	_chk(lines, hero.owner == level and hat.owner == level and wbody.owner == level and _count_script(level, CAMERA_3D) == 1, "dock 3D: all of it saves with the scene, and the scene still has its one camera")
	ur.undo()
	_chk(lines, hero.get_parent() == level and hero.position == Vector3(3, 0, 2) and hero.global_transform.is_equal_approx(drawn) and hero.owner == level and not wbody.is_inside_tree(), "dock 3D: undo puts the mesh back where it was")
	ur.redo()
	_chk(lines, hero.get_parent() == wbody and hero.position == Vector3.ZERO, "dock 3D: redo wraps it again")

	# a wrap in a scene with no camera puts the camera in the same undo step
	var level3: Node3D = Node3D.new()
	level3.name = "Level3"
	host.add_child(level3)
	var statue: Node = _owned(level3, level3, MeshInstance3D.new(), "Statue")
	var w3: Dictionary = dock.build_player_3d(ur, level3, statue, 5.0)
	_chk(lines, w3["body"] != null and _count_script(level3, CAMERA_3D) == 1, "dock 3D: wrapping in a scene with no camera also adds one")
	ur.undo()
	_chk(lines, statue.get_parent() == level3 and _count_script(level3, CAMERA_3D) == 0, "dock 3D: and one undo takes both away")

	var solo: MeshInstance3D = MeshInstance3D.new()
	var refused: Dictionary = dock.build_player_3d(ur, solo, solo, 5.0)
	_chk(lines, refused["body"] == null and String(refused["status"]).begins_with("Your picture is the top of this scene"), "dock 3D: a mesh at the top of its own scene is refused, with what to do instead")
	solo.free()

	# an existing body is baked onto: shape, mover, Interactor, tag
	var bare: CharacterBody3D = _owned(level, level, CharacterBody3D.new(), "Hero2") as CharacterBody3D
	var baked: Dictionary = dock.build_player_3d(ur, level, bare, 4.0)
	_chk(lines, baked["body"] == bare and dock._has_shape(bare) and dock._movers(bare).size() == 1 and _count_script(bare, INTERACTOR_3D) == 1 and bare.is_in_group("player") and _all_owned(level, bare.find_children("*", "", true, false)),
		"dock 3D: a selected CharacterBody3D gets a shape, the mover, an Interactor and the player tag")
	_chk(lines, String(baked["status"]).contains("no mesh yet"), "dock 3D: and the status warns it has nothing to draw")
	ur.undo()
	_chk(lines, bare.get_child_count() == 0 and not bare.is_in_group("player"), "dock 3D: one undo takes all of that off again")


	# a plain-Node root follows the node the click works on
	var plain: Node = Node.new()
	plain.name = "PlainRoot"
	host.add_child(plain)
	var plain3: Node = _owned(plain, plain, Node3D.new(), "Thing3D")
	var plain_other: Node = _owned(plain, plain, Node.new(), "Other")
	_chk(lines, dock.is_3d_scene(plain, plain3) and not dock.is_3d_scene(plain, plain_other) and not dock.is_3d_scene(plain), "dock 3D: under a plain-Node root a Node3D selection means 3D, anything else means 2D")
	var mixed_3d: Node = dock.wire_interactable(plain, plain3, "Use", "Hi.")
	var mixed_2d: Node = dock.wire_interactable(plain, plain_other, "Use", "Hi.")
	_chk(lines, mixed_3d.get_script() == INTERACTABLE_3D and mixed_2d.get_script() == INTERACTABLE, "dock 3D: so Make Interactable under a plain-Node root builds a 3D one on a Node3D and a 2D one on anything else")
	var mixed_made: Dictionary = dock.build_player_3d(ur, plain, plain3, 5.0)
	_chk(lines, mixed_made["body"] != null and (mixed_made["body"] as Node).get_parent() == plain3 and _find_script(plain, CAMERA_3D) != null and _find_script(plain, CAMERA_3D).get_parent() == plain, "dock 3D: Make Player under a plain-Node root puts the body under the Node3D and the camera at the root")
	var node2d_root: Node2D = Node2D.new()
	var child3: Node3D = Node3D.new()
	node2d_root.add_child(child3)
	_chk(lines, not dock.is_3d_scene(node2d_root, child3), "dock 3D: a Node2D root is 2D even with a Node3D selected")
	node2d_root.free()

	# a 2D lite mover left on a 3D body fights the 3D one, so it is swapped out
	var mixed_body: CharacterBody3D = _owned(level, level, CharacterBody3D.new(), "Mixed") as CharacterBody3D
	var stray: Node = _owned(level, mixed_body, Node.new(), "OldMover")
	stray.set_script(MOVER)
	var swap: Dictionary = dock.build_player_3d(ur, level, mixed_body, 4.0)
	var swapped_movers: Array = dock._movers(mixed_body)
	_chk(lines, swap["body"] == mixed_body and swapped_movers.size() == 1 and swapped_movers[0].get_script() == MOVER_3D and stray.get_parent() == null,
		"dock 3D: a 2D lite mover on a 3D body is swapped for the 3D one")
	ur.undo()
	_chk(lines, dock._movers(mixed_body).size() == 1 and dock._movers(mixed_body)[0] == stray and stray.owner == level, "dock 3D: and undo puts it back")
	ur.redo()

	# Make Interactable in 3D
	var crate: Node = _owned(level, level, Node3D.new(), "Crate")
	var ia: Node = dock.wire_interactable(level, crate, "Open", "It is locked.")
	_chk(lines, ia != null and ia.get_script() == INTERACTABLE_3D and ia.get_parent() == crate and ia.owner == level and String(ia.name) == "Interactable", "dock 3D: Make Interactable adds an InteractableLite3D under the prop")
	var ia_shapes: Array = ia.get_children().filter(func(c: Node) -> bool: return c is CollisionShape3D and c.owner == level)
	var ia_box: BoxShape3D = (ia_shapes[0] as CollisionShape3D).shape as BoxShape3D if ia_shapes.size() == 1 else null
	_chk(lines, ia_box != null and ia_box.size.x > 1.0 and ia_box.size.x < 3.0, "dock 3D: with one box shape a metre and a half wide, not 40 pixels")
	_chk(lines, ia.get("message") == "It is locked." and ia.get("prompt_text") == "Open", "dock 3D: the prompt and message fields land on the node")
	var said: String = dock.interactable_status(level, crate, ia, true, false)
	_chk(lines, said.begins_with("Made 'Crate' interactable.") and said.contains("\"E  Open\""), "dock 3D: the status names the prompt (%s)" % said)
	var ia2: Node = dock.wire_interactable(level, crate, "Take", "  Open.  ")
	_chk(lines, ia2 == ia and _count_script(crate, INTERACTABLE_3D) == 1 and ia.get("message") == "Open." and ia.get("prompt_text") == "Take", "dock 3D: a second click updates the same Interactable")
	_chk(lines, dock.wire_interactable(level, ia, "Use", "") == ia and _count_script(ia, INTERACTABLE_3D) == 0, "dock 3D: selecting the Interactable itself edits it")
	_chk(lines, dock._has_interactor(level), "dock 3D: an Interactor under the player counts as the scene having one")

	var packed: PackedScene = PackedScene.new()
	packed.pack(level)
	var played: Node = packed.instantiate()
	_chk(lines, played.get_node_or_null("Crate/Interactable") != null and played.get_node("Crate/Interactable").get_script() == INTERACTABLE_3D, "dock 3D: the interactable is saved with the scene")
	played.free()

	for n: Node in [level, level2, level3, plain]:
		n.free()
	ur.free()
	var bus: Node = host.get_tree().root.get_node_or_null("ControllersLite")
	if bus != null and not is_instance_valid(bus.get("player")):
		bus.set("player", null)


static func _find_script(root: Node, script: Script) -> Node:
	if root.get_script() == script:
		return root
	for n in root.find_children("*", "", true, false):
		if n.get_script() == script:
			return n
	return null


static func _count_script(root: Node, script: Script) -> int:
	var count: int = 0
	for n in root.find_children("*", "", true, false):
		if n.get_script() == script:
			count += 1
	return count


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
