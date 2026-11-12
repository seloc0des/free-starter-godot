extends RefCounted

# The chooser's Make Enemy sets the brain's attack radius so a Combat contact
# hitbox on the enemy reaches the player's hurtbox, and the brain switches that
# hitbox back on for every attack. At the brain's own 40 the Combat dock's 32x32
# boxes never touch, and a hitbox that's never switched off and on hits once per
# contact. The button needs the editor (the journey probe clicks it), so this
# calls the dock's headless half, fit_reach, on stand-in boxes and plays the
# fight with real physics. Combat isn't in this project, so the stand-ins play
# its boxes; where Combat is installed the no-box check expects 24 instead.

const DOCK := preload("res://addons/enemy_ai_lite/editor/enemy_chooser_dock.gd")
const HITBOX := preload("res://tools/enemy_ai_lite/fixtures/stand_in_hitbox.gd")
const HURTBOX := preload("res://tools/enemy_ai_lite/fixtures/stand_in_hurtbox.gd")
const HITBOX_3D := preload("res://tools/enemy_ai_lite/fixtures/stand_in_hitbox_3d.gd")
const HURTBOX_3D := preload("res://tools/enemy_ai_lite/fixtures/stand_in_hurtbox_3d.gd")


static func run(host: Node) -> Dictionary:
	var lines: Array[String] = []
	var ok := true
	var tree := host.get_tree()
	var dock = DOCK.new()  # never added to the tree, only its headless helpers run
	var said: String = ""

	# --- the rule ---
	ok = _chk(lines, is_equal_approx(dock.reach_for(16.0, 16.0, true), 24.0), "reach: two 32x32 boxes -> 24") and ok
	ok = _chk(lines, is_equal_approx(dock.reach_for(-1.0, -1.0, true), 24.0), "reach: Combat installed but no boxes yet -> 24") and ok
	ok = _chk(lines, dock.reach_for(-1.0, -1.0, false) < 0.0, "reach: no Combat and no boxes -> the brain keeps its own radius") and ok
	ok = _chk(lines, is_equal_approx(dock.reach_for(16.0, 16.0, true, 19.0), 24.0), "reach: bodies touching at 19 (Controller 20x20 + dock 18x18) leave it at 24") and ok
	ok = _chk(lines, is_equal_approx(dock.reach_for(16.0, 16.0, true, 25.0), 27.0), "reach: bodies touching at 25 (a 32x32 player) push it out to 25 + 2 = 27") and ok
	ok = _chk(lines, is_equal_approx(dock.reach_for(16.0, 16.0, true, 33.0), 30.0), "reach: bodies touching at 33, past the boxes' reach: capped at 32 - 2 = 30") and ok

	# --- measured off real shapes ---
	var dflt := _rig(host, Vector2(-9000, 0), _rect(32, 32), _rect(32, 32))
	said = dock.fit_reach(dflt["brain"], dflt["enemy"], dflt["root"])
	ok = _chk(lines, _radius(dflt) == 24.0 and said.contains("set to 24 ") and said.contains("measured from both boxes") and not said.contains("bodies"),
		"Combat dock boxes (32x32 each), 20x20 player body -> attack radius 24, and the status says so (%.1f)" % _radius(dflt)) and ok
	ok = _chk(lines, not said.contains("same side"), "a hitbox and hurtbox on different sides get no side warning") and ok

	var custom := _rig(host, Vector2(-8500, 0), _circle(20), _rect(40, 24))
	said = dock.fit_reach(custom["brain"], custom["enemy"], custom["root"])
	ok = _chk(lines, _radius(custom) == 30.0 and said.contains("set to 30 "),
		"circle r20 hitbox + 40 wide hurtbox -> 0.75 x (20 + 20) = 30 (%.1f)" % _radius(custom)) and ok

	var scaled := _rig(host, Vector2(-8000, 0), _capsule(12, 40), _rect(16, 16))
	(scaled["hurt"].get_child(0) as Node2D).scale = Vector2(2, 2)   # 16 wide, drawn twice the size
	said = dock.fit_reach(scaled["brain"], scaled["enemy"], scaled["root"])
	ok = _chk(lines, _radius(scaled) == 21.0,
		"capsule r12 hitbox + a 16 wide hurtbox scaled x2 -> 0.75 x (12 + 16) = 21 (%.1f)" % _radius(scaled)) and ok

	var bare := _rig(host, Vector2(-7500, 0), _circle(20), null)
	said = dock.fit_reach(bare["brain"], bare["enemy"], bare["root"])
	ok = _chk(lines, _radius(bare) == 27.0 and said.contains("player's hurtbox counted as the Combat dock's 32x32 box"),
		"player without a hurtbox yet: it counts as a 32x32 box -> 0.75 x (20 + 16) = 27 (%.1f)" % _radius(bare)) and ok

	# clicking again after resizing the hitbox measures again
	(dflt["hit"].get_child(0) as CollisionShape2D).shape = _rect(48, 48)
	said = dock.fit_reach(dflt["brain"], dflt["enemy"], dflt["root"])
	ok = _chk(lines, _radius(dflt) == 30.0, "clicking again after the hitbox grew to 48 wide -> 30 (%.1f)" % _radius(dflt)) and ok

	var same := _rig(host, Vector2(-7000, 0), _rect(32, 32), _rect(32, 32))
	same["hit"].set("team", 0)
	said = dock.fit_reach(same["brain"], same["enemy"], same["root"])
	ok = _chk(lines, said.contains("same side"), "a hitbox on the player's own side gets a warning that it can't hurt the player") and ok

	# the bodies: a 32x32 player and the dock's 18x18 enemy touch at 25
	var big := _rig(host, Vector2(-6500, 0), _rect(32, 32), _rect(32, 32), false, 32.0)
	said = dock.fit_reach(big["brain"], big["enemy"], big["root"])
	ok = _chk(lines, _radius(big) == 27.0 and said.contains("where the two bodies touch (25 px)"),
		"32x32 player body + 18x18 enemy body touch at 25 -> 27, and the status says why (%.1f)" % _radius(big)) and ok
	var huge := _rig(host, Vector2(-6000, 0), _rect(32, 32), _rect(32, 32), false, 48.0)
	said = dock.fit_reach(huge["brain"], huge["enemy"], huge["root"])
	ok = _chk(lines, _radius(huge) == 30.0 and said.contains("they touch at 33 px") and said.contains("Make the hitbox bigger"),
		"48x48 player body: the bodies touch at 33, past the boxes' 32 -> 30 and a plain 'make the hitbox bigger' (%.1f)" % _radius(huge)) and ok
	var apart := _rig(host, Vector2(-5500, 0), _rect(32, 32), _rect(32, 32), false, 48.0)
	(apart["player"] as CharacterBody2D).collision_layer = 2    # not in the enemy's mask
	said = dock.fit_reach(apart["brain"], apart["enemy"], apart["root"])
	ok = _chk(lines, _radius(apart) == 24.0, "bodies on layers that don't collide can't stop it, so they don't count (%.1f)" % _radius(apart)) and ok

	# no boxes at all: nothing to measure, so it's down to whether Combat is installed
	var none := _rig(host, Vector2(-5000, 0), null, null)
	said = dock.fit_reach(none["brain"], none["enemy"], none["root"])
	if dock._combat_installed():
		ok = _chk(lines, _radius(none) == 24.0, "no boxes yet, Combat installed here -> 24 (%.1f)" % _radius(none)) and ok
	else:
		ok = _chk(lines, _radius(none) == 40.0 and said == "",
			"no boxes and no Combat pack -> attack radius untouched at 40, nothing said (%.1f)" % _radius(none)) and ok

	# --- the status says the hitbox is swung ---
	said = dock.swing_note(custom["brain"], custom["enemy"])
	ok = _chk(lines, said.contains("switches that hitbox on for each attack") and said.contains("every 1 s"),
		"with a hitbox on the enemy the status says the brain swings it every attack_cooldown [%s]" % said.strip_edges()) and ok
	ok = _chk(lines, dock.swing_note(none["brain"], none["enemy"]) == "", "no hitbox on the enemy: nothing said about swinging") and ok
	ok = _chk(lines, dock.swing_note(same["brain"], same["enemy"], same["root"]) == "", "a hitbox on the player's side: no claim that it keeps hurting the player") and ok

	# 3D shapes read the same way
	var halves: Array = []
	for s in [_box3(Vector3(2, 1, 1)), _sphere3(0.5), _capsule3(0.25, 1.0), _cylinder3(0.75)]:
		var a := Area3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = s
		a.add_child(cs)
		host.add_child(a)
		halves.append(float(dock._half_width(a)))
		a.queue_free()
	ok = _chk(lines, halves == [1.0, 0.5, 0.25, 0.75], "3D: box by half its width, sphere / capsule / cylinder by radius %s" % str(halves)) and ok

	for r in [dflt, custom, scaled, bare, same, big, huge, apart, none]:
		r["brain"].free()
		r["root"].queue_free()

	# --- the fight, played with real physics ---
	# Enemies set up the way the chooser leaves them, each pair far from the others.
	var hits := _rig(host, Vector2(-4000, 0), _rect(32, 32), _rect(32, 32))        # fitted
	dock.fit_reach(hits["brain"], hits["enemy"], hits["root"])
	var once := _rig(host, Vector2(-3000, 0), _rect(32, 32), _rect(32, 32))        # fitted, hitbox never switched off
	dock.fit_reach(once["brain"], once["enemy"], once["root"])
	once["brain"].attack_duration = 0.0
	var old := _rig(host, Vector2(-2000, 0), _rect(32, 32), _rect(32, 32))         # nothing set: 40
	var wide := _rig(host, Vector2(-1000, 3000), _rect(32, 32), _rect(32, 32), false, 32.0)  # 32x32 player, fitted
	dock.fit_reach(wide["brain"], wide["enemy"], wide["root"])
	var short := _rig(host, Vector2(0, 3000), _rect(32, 32), _rect(32, 32), false, 32.0)  # 32x32 player at the boxes-only 24
	short["brain"].attack_radius = 24.0
	for r in [hits, once, old, wide, short]:
		r["enemy"].add_child(r["brain"])
	for i in 192:
		await tree.physics_frame
	var f: Array[int] = hits["hurt"].hit_frames
	ok = _chk(lines, f.size() >= 3 and hits["brain"].state == EnemyBrainLite.ATTACK,
		"played: fitted, it walks up and keeps hitting while the player stays in reach (%d hits in 3.2 s, stopped %.1f px away)" % [f.size(), _gap(hits)]) and ok
	ok = _chk(lines, f.size() >= 3 and absi(f[2] - f[1] - 60) <= 3,
		"played: the hits come one attack_cooldown (1 s, 60 frames) apart (%s)" % str(_spacing(f))) and ok
	ok = _chk(lines, once["hurt"].hit_frames.size() == 1,
		"played, control: a hitbox the brain never switches off (attack_duration 0) lands once per contact (%d hit)" % once["hurt"].hit_frames.size()) and ok
	ok = _chk(lines, old["hurt"].hit_frames.is_empty() and old["brain"].state == EnemyBrainLite.ATTACK,
		"played, control: at the brain's own 40 it stops short and never lands a hit (stopped %.1f px away)" % _gap(old)) and ok
	ok = _chk(lines, wide["brain"].state == EnemyBrainLite.ATTACK and wide["hurt"].hit_frames.size() >= 3,
		"played: a 32x32 player body stops it at %.1f px, inside the fitted 27, so it attacks and keeps hitting (%d hits)" % [_gap(wide), wide["hurt"].hit_frames.size()]) and ok
	ok = _chk(lines, short["brain"].state == EnemyBrainLite.CHASE and short["hurt"].hit_frames.size() == 1,
		"played, control: at 24 the same bodies stop it at %.1f px, so it never attacks and lands one contact hit (%d)" % [_gap(short), short["hurt"].hit_frames.size()]) and ok
	# the player walks off: no more hits
	(hits["player"] as Node2D).global_position += Vector2(0, -600)
	var before := f.size()
	for i in 90:
		await tree.physics_frame
	ok = _chk(lines, hits["hurt"].hit_frames.size() == before, "played: once the player leaves, the hits stop (%d -> %d)" % [before, hits["hurt"].hit_frames.size()]) and ok
	# switched off mid-swing (death, a cutscene): the hitbox mustn't stay live
	for i in 90:
		if float(wide["brain"]._swing_left) > 0.1:
			break
		await tree.physics_frame
	var mid_swing := float(wide["brain"]._swing_left) > 0.1
	wide["brain"].enabled = false
	for i in 30:
		await tree.physics_frame
	ok = _chk(lines, mid_swing and not (wide["hit"] as Area2D).monitoring, "a brain switched off mid-swing switches its hitbox off too") and ok
	for r in [hits, once, old, wide, short]:
		r["root"].queue_free()
	ok = _picture_wrap(host, dock, lines) and ok
	ok = await _dock_3d(host, dock, lines) and ok
	dock.free()
	return {"ok": ok, "lines": lines}


# Make Enemy with the enemy's picture selected. The new Enemy takes the
# picture's place and the picture goes inside it, so they move together in the
# game (a body made inside the picture walked off without it). The button reads
# the selection and hands its halves the editor's undo manager; here they get a
# plain UndoRedo, so undo and redo are checked too.
static func _picture_wrap(host: Node, dock: Control, lines: Array[String]) -> bool:
	if not dock.has_method("wrap_picture"):
		return _chk(lines, false, "wrap: Make Enemy can put a selected picture inside a new Enemy")
	var ok := true
	var level := Node2D.new()
	level.name = "Level"
	host.add_child(level)  # in the tree like an open scene, so a node taken out really loses its owner
	var ground := _owned(level, level, Node2D.new(), "Ground")
	var slime := _owned(level, level, AnimatedSprite2D.new(), "Slime") as AnimatedSprite2D
	slime.position = Vector2(120, 80)
	slime.rotation = 0.5
	slime.scale = Vector2(2, 2)
	var eye := _owned(level, slime, Sprite2D.new(), "Eye") as Sprite2D
	eye.position = Vector2(0, -10)
	var rock := _owned(level, level, Node2D.new(), "Rock")
	var drawn := slime.global_transform
	var eye_drawn := eye.global_transform

	ok = _chk(lines, dock.is_picture(slime) and dock.body_for(slime) == null and dock.wrap_refusal(level, slime) == "", "wrap: a selected AnimatedSprite2D with no body around it gets wrapped") and ok
	var ur := UndoRedo.new()
	var body: CharacterBody2D = dock.new_enemy(222.0, 111.0)
	dock.wrap_picture(ur, level, slime, body)
	ok = _chk(lines, slime.get_parent() == body and body.get_parent() == level, "wrap: the picture is inside the new body, and the body is in the level") and ok
	ok = _chk(lines, body.get_index() == 1 and level.get_child(0) == ground and level.get_child(2) == rock and level.get_child_count() == 3,
		"wrap: the body takes the picture's spot in the Scene list (%d)" % body.get_index()) and ok
	ok = _chk(lines, body.position == Vector2(120, 80) and slime.position == Vector2.ZERO,
		"wrap: the body stands where the picture stood, the picture sits at 0,0 inside it (%s, %s)" % [body.position, slime.position]) and ok
	ok = _chk(lines, slime.global_transform.is_equal_approx(drawn) and eye.global_transform.is_equal_approx(eye_drawn), "wrap: nothing moves on screen, turn and size included") and ok
	ok = _chk(lines, String(body.name) == "Enemy" and String(slime.name) == "Slime" and eye.get_parent() == slime, "wrap: the body is called Enemy, the picture keeps its name and what's under it") and ok
	var brain: Node = dock._find_brain(body)
	var shape := body.get_node_or_null("Shape") as CollisionShape2D
	ok = _chk(lines, brain != null and float(brain.get("detect_radius")) == 222.0 and float(brain.get("chase_speed")) == 111.0
		and shape != null and (shape.shape as RectangleShape2D).size == Vector2(18, 18),
		"wrap: the body gets its 18x18 shape and a Brain at the dock's detect radius and chase speed") and ok
	var everything: Array = [body, slime, eye]
	everything.append_array(body.get_children())
	ok = _chk(lines, _all_owned(level, everything), "wrap: the body, its shape and Brain, the picture and what's under it all save with the scene") and ok
	var ps := PackedScene.new()
	ps.pack(level)
	var copy := ps.instantiate()
	ok = _chk(lines, copy.get_node_or_null("Enemy/Slime/Eye") != null and copy.get_node_or_null("Enemy/Brain") != null and copy.get_node_or_null("Enemy/Shape") != null,
		"wrap: the saved scene has Enemy > Slime > Eye, the Brain and the shape") and ok
	copy.free()

	ur.undo()
	ok = _chk(lines, slime.get_parent() == level and slime.get_index() == 1 and level.get_child_count() == 3 and slime.position == Vector2(120, 80) and slime.global_transform.is_equal_approx(drawn),
		"wrap: undo puts the picture back exactly where it was") and ok
	ok = _chk(lines, slime.owner == level and eye.owner == level and not body.is_inside_tree(), "wrap: after undo the picture still saves with the scene, and the body is gone") and ok
	ur.redo()
	ok = _chk(lines, slime.get_parent() == body and body.get_index() == 1 and slime.position == Vector2.ZERO and _all_owned(level, everything), "wrap: redo puts it back inside, all of it saved with the scene") and ok

	# anything that isn't a picture keeps what the button did before
	var npc := _owned(level, level, Node2D.new(), "NPC")
	ok = _chk(lines, not dock.is_picture(npc) and dock.body_for(npc) == null, "wrap: a plain node isn't a picture, so a new Enemy still goes under it") and ok
	ok = _chk(lines, not dock.is_picture(level) and dock.body_for(body) == body, "wrap: the level isn't either, and a selected body is baked onto as before") and ok
	ok = _chk(lines, dock.body_for(slime) == body, "wrap: a picture already inside a body means that body, so no second body goes in") and ok
	var menu := _owned(level, level, Control.new(), "Menu")
	var in_menu := _owned(level, menu, ColorRect.new(), "Box")
	var in_level := _owned(level, level, ColorRect.new(), "Crate")
	ok = _chk(lines, dock.is_picture(in_level) and not dock.is_picture(in_menu), "wrap: a colour box out in the level is a picture, one laid out in a menu isn't") and ok
	var solo := Sprite2D.new()
	ok = _chk(lines, dock.wrap_refusal(solo, solo).begins_with("Your picture is the top of this scene"), "wrap: a picture at the top of its own scene is refused, with what to do instead") and ok
	solo.free()
	var other := _owned(level, level, Node2D.new(), "House")
	var inner := _owned(level, other, Sprite2D.new(), "Window")
	inner.owner = other  # as if it came in with an instanced scene
	ok = _chk(lines, dock.wrap_refusal(level, inner).contains("belongs to another scene"), "wrap: a picture inside another scene is refused, with what to do instead") and ok
	ur.free()
	level.free()
	return ok


# The 3D builds. The buttons need the editor, so these call their headless halves
# the way the 2D checks do: the reach rule in metres, the enemy the dock builds,
# a mesh wrapped in a new Enemy (with undo), and a played fight in 3D.
static func _dock_3d(host: Node, dock: Control, lines: Array[String]) -> bool:
	var ok := true
	var tree := host.get_tree()

	# --- the rule, in metres ---
	ok = _chk(lines, is_equal_approx(dock.reach_for_3d(0.75, 0.45, true), 0.9), "3D reach: Combat dock's 1.5 m hitbox and 0.9 m hurtbox -> 0.9, not 0.89") and ok
	ok = _chk(lines, is_equal_approx(dock.reach_for_3d(-1.0, -1.0, true), 0.9), "3D reach: Combat installed but no boxes yet counts the same boxes -> 0.9") and ok
	ok = _chk(lines, dock.reach_for_3d(-1.0, -1.0, false) < 0.0, "3D reach: no Combat and no boxes -> the brain keeps its own radius") and ok
	ok = _chk(lines, is_equal_approx(dock.reach_for_3d(0.75, 0.45, true, 1.0), 1.06), "3D reach: bodies touching at 1.0 push it to 1.0625, floored to 1.06") and ok
	ok = _chk(lines, is_equal_approx(dock.reach_for_3d(0.75, 0.45, true, 2.0), 1.13), "3D reach: bodies touching past the boxes' reach: capped at 1.2 - 0.0625, floored to 1.13") and ok

	# --- what Make Enemy builds in a 3D scene ---
	var made: CharacterBody3D = dock.new_enemy_3d(9.0, 3.0, true)
	var shape := made.get_node_or_null("Shape") as CollisionShape3D
	var cap := shape.shape as CapsuleShape3D if shape != null else null
	ok = _chk(lines, String(made.name) == "Enemy" and cap != null and is_equal_approx(cap.radius, 0.4) and is_equal_approx(cap.height, 1.8) and is_equal_approx(shape.position.y, 0.9),
		"3D build: a CharacterBody3D 'Enemy' with a 1.8 m capsule standing on its origin") and ok
	var visual := made.get_node_or_null("Visual") as MeshInstance3D
	var nose := made.get_node_or_null("Nose") as MeshInstance3D
	ok = _chk(lines, visual != null and visual.mesh is CapsuleMesh and nose != null and nose.position.z < 0.0,
		"3D build: a capsule mesh plus a nose on the -Z side so the facing shows with no art") and ok
	var brain: Node = dock._find_brain(made)
	ok = _chk(lines, brain != null and brain.get_script() == dock.BRAIN_3D and float(brain.get("detect_radius")) == 9.0 and float(brain.get("chase_speed")) == 3.0,
		"3D build: an EnemyBrainLite3D at the dock's detect radius and chase speed") and ok
	var bare: CharacterBody3D = dock.new_enemy_3d(9.0, 3.0, false)
	ok = _chk(lines, bare.get_node_or_null("Visual") == null and bare.get_node_or_null("Shape") != null and dock._has_shape(bare),
		"3D build: with a mesh of the buyer's own to wrap, no mesh is added") and ok
	made.free()
	bare.free()

	# --- a mesh selected: wrapped in a new Enemy, undo and redo ---
	var level := Node3D.new()
	level.name = "Level3"
	host.add_child(level)
	var ground := _owned(level, level, Node3D.new(), "Ground")
	var slime := _owned(level, level, MeshInstance3D.new(), "Slime") as MeshInstance3D
	slime.position = Vector3(4, 0, -3)
	slime.rotation.y = 0.5
	slime.scale = Vector3(2, 2, 2)
	var eye := _owned(level, slime, MeshInstance3D.new(), "Eye") as MeshInstance3D
	eye.position = Vector3(0, 1, -0.5)
	var rock := _owned(level, level, Node3D.new(), "Rock")
	var drawn := slime.global_transform
	var eye_drawn := eye.global_transform
	ok = _chk(lines, dock.is_picture_3d(slime) and not dock.is_picture_3d(rock) and dock.body_for_3d(slime) == null and dock.wrap_refusal(level, slime) == "",
		"3D wrap: a selected MeshInstance3D with no body around it gets wrapped, a plain Node3D does not") and ok
	var ur := UndoRedo.new()
	var body: CharacterBody3D = dock.new_enemy_3d(12.0, 4.0, false)
	dock.wrap_picture(ur, level, slime, body)
	ok = _chk(lines, slime.get_parent() == body and body.get_parent() == level and body.get_index() == 1 and level.get_child_count() == 3,
		"3D wrap: the mesh is inside the new body, which takes its spot in the Scene list") and ok
	ok = _chk(lines, body.position == Vector3(4, 0, -3) and slime.position == Vector3.ZERO,
		"3D wrap: the body stands where the mesh stood, the mesh sits at 0,0,0 inside it (%s, %s)" % [body.position, slime.position]) and ok
	ok = _chk(lines, slime.global_transform.is_equal_approx(drawn) and eye.global_transform.is_equal_approx(eye_drawn), "3D wrap: nothing moves in the scene, turn and size included") and ok
	var everything: Array = [body, slime, eye]
	everything.append_array(body.get_children())
	ok = _chk(lines, _all_owned(level, everything), "3D wrap: the body, its shape and Brain, the mesh and what's under it all save with the scene") and ok
	var ps := PackedScene.new()
	ps.pack(level)
	var copy := ps.instantiate()
	ok = _chk(lines, copy.get_node_or_null("Enemy/Slime/Eye") != null and copy.get_node_or_null("Enemy/Brain") != null and copy.get_node_or_null("Enemy/Shape") != null,
		"3D wrap: the saved scene has Enemy > Slime > Eye, the Brain and the shape") and ok
	copy.free()
	ur.undo()
	ok = _chk(lines, slime.get_parent() == level and slime.get_index() == 1 and slime.position == Vector3(4, 0, -3) and slime.global_transform.is_equal_approx(drawn) and not body.is_inside_tree(),
		"3D wrap: undo puts the mesh back exactly where it was") and ok
	ur.redo()
	ok = _chk(lines, slime.get_parent() == body and slime.position == Vector3.ZERO and _all_owned(level, everything), "3D wrap: redo puts it back inside, all of it saved with the scene") and ok
	ok = _chk(lines, dock.body_for_3d(slime) == body and dock.body_for_3d(body) == body,
		"3D wrap: a mesh already inside a body means that body, so no second body goes in") and ok
	var wrapper := _owned(level, level, Node3D.new(), "Group")
	var inner: CharacterBody3D = dock.new_enemy_3d(12.0, 4.0, true)
	wrapper.add_child(inner)
	ok = _chk(lines, dock.body_for_3d(wrapper) == inner, "3D: a second click on the node an enemy went under reuses that enemy") and ok
	ur.free()
	level.free()

	# --- reach fitted from real 3D boxes ---
	var fit := _rig3(host, Vector3(0, 0, 5000), true)
	var said: String = dock.fit_reach_3d(fit["brain"], fit["enemy"], fit["root"])
	ok = _chk(lines, is_equal_approx(fit["brain"].attack_radius, 0.9) and said.contains("set to 0.9 m"),
		"3D: Combat's built boxes (1.5 m and 0.9 m) on capsule bodies touching at 0.8 -> attack radius 0.9, and the status says so (%.2f)" % fit["brain"].attack_radius) and ok
	var same := _rig3(host, Vector3(0, 0, 6000), true)
	same["hit"].set("team", 0)
	said = dock.fit_reach_3d(same["brain"], same["enemy"], same["root"])
	ok = _chk(lines, said.contains("same side"), "3D: a hitbox on the player's own side gets a warning that it can't hurt the player") and ok
	var none := _rig3(host, Vector3(0, 0, 7000), false)
	said = dock.fit_reach_3d(none["brain"], none["enemy"], none["root"])
	if dock._combat_installed():
		ok = _chk(lines, is_equal_approx(none["brain"].attack_radius, 0.9), "3D: no boxes yet, Combat installed here -> 0.9, the same as built (%.2f)" % none["brain"].attack_radius) and ok
	else:
		ok = _chk(lines, none["brain"].attack_radius == 1.8 and said == "", "3D: no boxes and no Combat pack -> attack radius untouched at 1.8, nothing said (%.2f)" % none["brain"].attack_radius) and ok
	said = dock.swing_note(fit["brain"], fit["enemy"])
	ok = _chk(lines, said.contains("switches that hitbox on for each attack") and said.contains("every 1 s"),
		"3D: with a 3D hitbox on the enemy the status says the brain swings it every attack_cooldown [%s]" % said.strip_edges()) and ok
	ok = _chk(lines, dock.swing_note(none["brain"], none["enemy"]) == "", "3D: no hitbox on the enemy: nothing said about swinging") and ok
	said = dock.swing_note(fit["brain"], fit["enemy"], fit["root"])
	ok = _chk(lines, said.contains("switches that hitbox on for each attack"),
		"3D: given the scene root, the status still says the brain swings the hitbox when bodies and boxes reach (metre margins) [%s]" % said.strip_edges()) and ok
	ok = _chk(lines, dock.swing_note(same["brain"], same["enemy"], same["root"]) == "", "3D: a hitbox on the player's own side: no claim that it keeps hurting the player") and ok
	for r in [fit, same, none]:
		r["brain"].free()
		r["root"].queue_free()

	# --- the fight, played with real 3D physics ---
	var hits := _rig3(host, Vector3(0, 0, 1000), true)          # fitted
	dock.fit_reach_3d(hits["brain"], hits["enemy"], hits["root"])
	var once := _rig3(host, Vector3(0, 0, 2000), true)          # fitted, hitbox never switched off
	dock.fit_reach_3d(once["brain"], once["enemy"], once["root"])
	once["brain"].attack_duration = 0.0
	var old := _rig3(host, Vector3(0, 0, 3000), true)           # nothing set: 1.8
	for r in [hits, once, old]:
		r["enemy"].add_child(r["brain"])
	for i in _n(300):
		await tree.physics_frame
	var f: Array[int] = hits["hurt"].hit_frames
	ok = _chk(lines, f.size() >= 3 and hits["brain"].state == EnemyBrainLite3D.ATTACK,
		"3D played: fitted, it walks up and keeps hitting while the player stays in reach (%d hits in 5 s, stopped %.2f m away)" % [f.size(), _gap3(hits)]) and ok
	ok = _chk(lines, f.size() >= 3 and absi(f[2] - f[1] - Engine.physics_ticks_per_second) <= _n(3),
		"3D played: the hits come one attack_cooldown (1 s, 60 frames) apart (%s)" % str(_spacing(f))) and ok
	ok = _chk(lines, once["hurt"].hit_frames.size() == 1,
		"3D played, control: a hitbox the brain never switches off (attack_duration 0) lands once per contact (%d hit)" % once["hurt"].hit_frames.size()) and ok
	ok = _chk(lines, old["hurt"].hit_frames.is_empty() and old["brain"].state == EnemyBrainLite3D.ATTACK,
		"3D played, control: at the brain's own 1.8 m it stops short and never lands a hit (stopped %.2f m away)" % _gap3(old)) and ok
	(hits["player"] as Node3D).global_position += Vector3(0, 0, -60)
	var before := f.size()
	for i in _n(90):
		await tree.physics_frame
	ok = _chk(lines, hits["hurt"].hit_frames.size() == before, "3D played: once the player leaves, the hits stop (%d -> %d)" % [before, hits["hurt"].hit_frames.size()]) and ok
	# the player comes back, then the brain is switched off mid-swing (death, a
	# cutscene): the hitbox mustn't stay live
	(hits["player"] as Node3D).global_position += Vector3(0, 0, 60)
	for i in _n(300):
		if float(hits["brain"]._swing_left) > 0.1:
			break
		await tree.physics_frame
	var mid_swing := float(hits["brain"]._swing_left) > 0.1
	hits["brain"].enabled = false
	for i in _n(30):
		await tree.physics_frame
	ok = _chk(lines, mid_swing and not (hits["hit"] as Area3D).monitoring, "3D: a brain switched off mid-swing switches its hitbox off too") and ok

	# --- which mode a scene gets ---
	var plain := Node.new()
	var kid3 := Node3D.new()
	var kid2 := Node2D.new()
	ok = _chk(lines, dock.mode_for(plain, kid3) and not dock.mode_for(plain, kid2) and not dock.mode_for(plain, null),
		"3D mode: a plain Node root follows the selection (a Node3D means 3D, a Node2D or nothing means 2D)") and ok
	ok = _chk(lines, dock.mode_for(kid3, kid2) and not dock.mode_for(kid2, kid3) and not dock.mode_for(null, kid3),
		"3D mode: a Node3D root is 3D, a Node2D root is 2D, no scene is 2D, whatever is selected") and ok
	plain.free()
	kid3.free()
	kid2.free()

	# --- each mode keeps its own field values ---
	var d2: Control = DOCK.new()
	d2._build()
	d2._detect.value = 200.0
	d2._speed.value = 150.0
	d2._apply_mode(true)
	ok = _chk(lines, d2._detect.value == 12.0 and d2._speed.value == 4.0 and d2._detect_label.text.contains("(m)") and d2._brain_btn.text == "Make 3D Enemy (brain)",
		"3D: a 3D scene switches the fields to metres (12 m, 4 m/s) and the button to its 3D name") and ok
	d2._detect.value = 9.0
	d2._apply_mode(false)
	ok = _chk(lines, d2._detect.value == 200.0 and d2._speed.value == 150.0 and d2._detect_label.text == "Detect radius" and d2._brain_btn.text == "Make Enemy (brain)",
		"3D: back in a 2D scene the 2D values (200, 150) and labels are as they were, not reset") and ok
	d2._apply_mode(true)
	ok = _chk(lines, d2._detect.value == 9.0, "3D: and the 3D value (9 m) is remembered too") and ok
	d2.free()
	for r in [hits, once, old]:
		r["root"].queue_free()
	return ok


# A 100 m floor, a player (a capsule body in group "player" with a 0.9 m hurtbox) and
# an enemy 8 m away (the dock's capsule body) with a 1.5 m hitbox and a brain. A false
# `boxes` leaves both boxes out. The brain is not added: the caller adds it last.
static func _rig3(host: Node, at: Vector3, boxes: bool) -> Dictionary:
	var root := Node3D.new()
	root.position = at
	host.add_child(root)
	var floor_body := StaticBody3D.new()
	floor_body.add_child(_shape3(_box3(Vector3(100, 1, 100)), 0.0))
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.add_child(_shape3(_capsule3(0.4, 1.8), 0.9))
	root.add_child(player)
	var hurt: Area3D = null
	var hit: Area3D = null
	if boxes:
		hurt = HURTBOX_3D.new()
		hurt.add_child(_shape3(_box3(Vector3(0.9, 0.9, 0.9)), 0.9))
		player.add_child(hurt)
	var enemy := CharacterBody3D.new()
	enemy.position = Vector3(8, 0, 0)
	enemy.add_child(_shape3(_capsule3(0.4, 1.8), 0.9))
	if boxes:
		hit = HITBOX_3D.new()
		hit.name = "Hitbox"
		hit.add_child(_shape3(_box3(Vector3(1.5, 1.5, 1.5)), 0.9))
		enemy.add_child(hit)
	root.add_child(enemy)
	return {"root": root, "player": player, "enemy": enemy, "brain": EnemyBrainLite3D.new(), "hit": hit, "hurt": hurt}


static func _gap3(rig: Dictionary) -> float:
	return (rig["enemy"] as Node3D).global_position.distance_to((rig["player"] as Node3D).global_position)


static func _shape3(s: Shape3D, y: float) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.shape = s
	cs.position = Vector3(0, y, 0)
	return cs


static func _capsule3(radius: float, height: float) -> CapsuleShape3D:
	var c := CapsuleShape3D.new()
	c.radius = radius
	c.height = height
	return c


# ---- helpers -------------------------------------------------------------

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

# A player (a body_w square body, 20 like the Controller pack's) in group
# "player" with a hurtbox, and an enemy 130 px away (the dock's 18x18 body)
# with a hitbox and a brain. A null shape leaves that box out. Rigs sit far
# apart so no brain sees another rig's player.
static func _rig(host: Node, at: Vector2, hit_shape: Shape2D, hurt_shape: Shape2D, live := false, body_w := 20.0) -> Dictionary:
	var root := Node2D.new()
	root.position = at
	host.add_child(root)
	var player := CharacterBody2D.new()
	player.add_to_group("player")
	player.add_child(_shape(_rect(body_w, body_w)))
	root.add_child(player)
	var hurt: Area2D = null
	if hurt_shape != null:
		hurt = HURTBOX.new()
		hurt.add_child(_shape(hurt_shape))
		player.add_child(hurt)
	var enemy := CharacterBody2D.new()
	enemy.position = Vector2(130, 0)
	enemy.add_child(_shape(_rect(18, 18)))
	var hit: Area2D = null
	if hit_shape != null:
		hit = HITBOX.new()
		hit.name = "Hitbox"
		hit.add_child(_shape(hit_shape))
		enemy.add_child(hit)
	root.add_child(enemy)
	var brain := EnemyBrainLite.new()
	if live:
		enemy.add_child(brain)
	return {"root": root, "player": player, "enemy": enemy, "brain": brain, "hit": hit, "hurt": hurt}


static func _radius(rig: Dictionary) -> float:
	return float(rig["brain"].attack_radius)


static func _gap(rig: Dictionary) -> float:
	return (rig["enemy"] as Node2D).global_position.distance_to((rig["player"] as Node2D).global_position)


static func _spacing(frames: Array[int]) -> Array:
	var out: Array = []
	for i in range(1, frames.size()):
		out.append(frames[i] - frames[i - 1])
	return out


static func _shape(s: Shape2D) -> CollisionShape2D:
	var cs := CollisionShape2D.new()
	cs.shape = s
	return cs


static func _rect(w: float, h: float) -> RectangleShape2D:
	var r := RectangleShape2D.new()
	r.size = Vector2(w, h)
	return r


static func _circle(radius: float) -> CircleShape2D:
	var c := CircleShape2D.new()
	c.radius = radius
	return c


static func _capsule(radius: float, height: float) -> CapsuleShape2D:
	var c := CapsuleShape2D.new()
	c.radius = radius
	c.height = height
	return c


static func _box3(size: Vector3) -> BoxShape3D:
	var b := BoxShape3D.new()
	b.size = size
	return b


static func _sphere3(radius: float) -> SphereShape3D:
	var s := SphereShape3D.new()
	s.radius = radius
	return s


static func _cylinder3(radius: float) -> CylinderShape3D:
	var c := CylinderShape3D.new()
	c.radius = radius
	return c


# Frame counts in the 3D checks are written for 60 physics ticks a second and
# scaled to the project's rate.
static func _n(frames: int) -> int:
	return ceili(frames * Engine.physics_ticks_per_second / 60.0)


static func _chk(lines: Array[String], cond: bool, label: String) -> bool:
	lines.append(("[ok] " if cond else "[XX] ") + label)
	return cond
