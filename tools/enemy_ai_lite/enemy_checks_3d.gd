extends RefCounted

# Checks for the 3D class (EnemyBrainLite3D), used by the headless
# verify and the on-screen acceptance banner next to enemy_checks.gd. `host` must
# be in the SceneTree. Sections use distinct target groups so brains never see
# another section's stand-in player. Lengths are metres.

const ALIVE_HEALTH := preload("res://tools/enemy_ai_lite/fixtures/alive_health.gd")


static func run(host: Node) -> Dictionary:
	var lines: Array[String] = []
	var ok := true

	# --- brain wiring ---
	var orphan_parent := Node3D.new()
	var orphan := EnemyBrainLite3D.new()
	orphan_parent.add_child(orphan)
	host.add_child(orphan_parent)
	ok = _chk(lines, not orphan.is_physics_processing(), "3D: brain on a non-CharacterBody3D parent turns itself off") and ok

	var idle_body := _enemy_body()
	var idle_brain := EnemyBrainLite3D.new()
	idle_body.add_child(idle_brain)
	host.add_child(idle_body)
	ok = _chk(lines, idle_brain.state == EnemyBrainLite3D.IDLE, "3D: starts idle") and ok

	for n in [orphan_parent, idle_body]:
		n.queue_free()

	return {"ok": ok, "lines": lines}


# Async checks: the state machine over physics frames.
static func run_physics(host: Node) -> Dictionary:
	var lines: Array[String] = []
	var ok := true
	var tree := host.get_tree()
	var ground := _floor(host)

	# --- gravity ---
	var drop := _enemy_body()
	drop.position = Vector3(0, 3, 600)
	host.add_child(drop)
	var drop_brain := EnemyBrainLite3D.new()
	drop_brain.target_group = &"test3_none"
	drop.add_child(drop_brain)
	await _wait(tree, 1.5)
	ok = _chk(lines, drop.is_on_floor() and absf(drop.global_position.y) < 0.05, "3D: gravity drops the body onto the floor and it stays there (y %.3f)" % drop.global_position.y) and ok
	drop_brain.apply_gravity = false
	drop.global_position.y = 3.0
	await _wait(tree, 0.3)
	ok = _chk(lines, is_equal_approx(drop.global_position.y, 3.0), "3D: apply_gravity off -> the body hangs where it is") and ok
	drop.queue_free()

	# --- chase -> attack -> cooldown (no leash: huge give_up) ---
	var player_a := _stub_player(host, &"test3_a", Vector3(10, 0, 0))
	var body_a := _enemy_body()
	body_a.position = Vector3.ZERO
	host.add_child(body_a)
	var brain_a := EnemyBrainLite3D.new()
	brain_a.target_group = &"test3_a"
	brain_a.detect_radius = 12.0
	brain_a.attack_radius = 2.0
	brain_a.give_up_radius = 1.0e9
	brain_a.attack_cooldown = 1.0
	body_a.add_child(brain_a)
	var acquired := {"n": 0}
	var attacks := {"n": 0, "bus": 0}
	brain_a.target_acquired.connect(func(_t: Node3D) -> void: acquired["n"] += 1)
	brain_a.attacked.connect(func(_t: Node3D) -> void: attacks["n"] += 1)
	var on_bus_attack := func(_e: Node, _t: Node) -> void: attacks["bus"] += 1
	_enemy_ai_lite().attack_started.connect(on_bus_attack)

	await _frames(tree, 3)
	ok = _chk(lines, brain_a.state == EnemyBrainLite3D.CHASE, "3D: player in detect radius -> chase") and ok
	ok = _chk(lines, acquired["n"] == 1, "3D: target_acquired fired") and ok
	ok = _chk(lines, body_a.velocity.x > 0.0 and is_zero_approx(body_a.velocity.z), "3D: chasing moves toward the player along the ground") and ok
	await _frames(tree, 20)
	ok = _chk(lines, _forward(body_a).dot(Vector3.RIGHT) > 0.95, "3D: the body turns to face where it runs (forward %s)" % str(_forward(body_a))) and ok
	ok = _chk(lines, is_zero_approx(body_a.rotation.x) and is_zero_approx(body_a.rotation.z), "3D: turning is yaw only") and ok

	player_a.global_position = body_a.global_position + Vector3(0, 0, 1.2)
	await _frames(tree, 3)
	ok = _chk(lines, brain_a.state == EnemyBrainLite3D.ATTACK, "3D: in attack radius -> attack state") and ok
	ok = _chk(lines, attacks["n"] == 1 and attacks["bus"] == 1, "3D: attack fired once (signal + bus)") and ok
	await _frames(tree, 20)
	ok = _chk(lines, _forward(body_a).dot(Vector3.BACK) > 0.95, "3D: while attacking it faces the target, not where it was heading") and ok
	await _wait(tree, 0.15)
	ok = _chk(lines, attacks["n"] == 1, "3D: cooldown holds: no second attack yet") and ok

	_enemy_ai_lite().attack_started.disconnect(on_bus_attack)
	player_a.queue_free()
	body_a.queue_free()

	# --- targets are Node3D members of the group ---
	var player_h := _stub_player(host, &"test3_h", Vector3(0, 0, 0))
	player_h.global_position = Vector3(200, 0, 0)
	var body_h := _enemy_body()
	body_h.position = Vector3(190, 0, 0)
	host.add_child(body_h)
	var brain_h := EnemyBrainLite3D.new()
	brain_h.target_group = &"test3_h"
	body_h.add_child(brain_h)
	await _frames(tree, 3)
	ok = _chk(lines, brain_h.state == EnemyBrainLite3D.CHASE and brain_h.target == player_h, "3D: a Node3D in target_group is the target") and ok
	player_h.queue_free()
	body_h.queue_free()


	# --- facing and moving under a parent turned 90 degrees ---
	var yawed := Node3D.new()
	yawed.rotation.y = PI / 2.0
	yawed.position = Vector3(1600, 0, 0)
	host.add_child(yawed)
	var player_y := _stub_player(host, &"test3_y", Vector3(1610, 0, 0))
	var body_y := _enemy_body()
	yawed.add_child(body_y)
	var brain_y := EnemyBrainLite3D.new()
	brain_y.target_group = &"test3_y"
	body_y.add_child(brain_y)
	await _frames(tree, 30)
	ok = _chk(lines, _forward(body_y).dot(Vector3.RIGHT) > 0.95 and body_y.global_position.x > 1600.5,
		"3D: under a parent turned 90 degrees it still runs at the player and faces it (forward %s)" % str(_forward(body_y))) and ok
	player_y.queue_free()
	yawed.queue_free()

	# --- a target freed mid-chase or mid-attack is let go ---
	for mode in ["chase", "attack"]:
		var grp := StringName("test3_free_" + mode)
		var gap := 8.0 if mode == "chase" else 1.2
		var victim := _stub_player(host, grp, Vector3(1800 + gap, 0, 0))
		var body_f := _enemy_body()
		body_f.position = Vector3(1800, 0, 0)
		host.add_child(body_f)
		var brain_f := EnemyBrainLite3D.new()
		brain_f.target_group = grp
		body_f.add_child(brain_f)
		var lost := {"n": 0}
		brain_f.target_lost.connect(func() -> void: lost["n"] += 1)
		await _frames(tree, 4)
		var engaged: bool = brain_f.state == EnemyBrainLite3D.CHASE if mode == "chase" else brain_f.state == EnemyBrainLite3D.ATTACK
		victim.queue_free()
		await _frames(tree, 4)
		ok = _chk(lines, engaged and lost["n"] == 1 and brain_f.target == null and brain_f.state != EnemyBrainLite3D.CHASE and brain_f.state != EnemyBrainLite3D.ATTACK,
			"3D: a target freed mid-%s fires target_lost and the brain lets go (state %s)" % [mode, brain_f.state]) and ok
		ok = _chk(lines, absf(body_f.velocity.x) < 0.01 or brain_f.state == EnemyBrainLite3D.RETURN,
			"3D: after the target is freed mid-%s the brain does not run on at its old speed" % mode) and ok
		body_f.queue_free()

	# --- leash -> return -> re-aggro ---
	var player_b := _stub_player(host, &"test3_b", Vector3(800 + 5, 0, 0))
	var body_b := _enemy_body()
	body_b.position = Vector3(800, 0, 0)
	host.add_child(body_b)
	var brain_b := EnemyBrainLite3D.new()
	brain_b.target_group = &"test3_b"
	brain_b.detect_radius = 12.0
	brain_b.give_up_radius = 4.0
	brain_b.move_speed = 6.0
	body_b.add_child(brain_b)
	await _frames(tree, 3)
	ok = _chk(lines, brain_b.state == EnemyBrainLite3D.CHASE, "3D: leash test: chasing first") and ok
	body_b.global_position = Vector3(806, 0, 0)                # dragged past the leash
	player_b.global_position = Vector3(808, 0, 0)              # camper right there
	await _frames(tree, 3)
	ok = _chk(lines, brain_b.state == EnemyBrainLite3D.RETURN, "3D: past give_up_radius -> walks home") and ok
	ok = _chk(lines, brain_b.target == null, "3D: leash dropped the target") and ok
	ok = _chk(lines, body_b.velocity.x < 0.0, "3D: returning moves toward home") and ok
	var settled := 0
	while brain_b.state == EnemyBrainLite3D.RETURN and settled < _n(400):
		await tree.physics_frame
		settled += 1
	await _frames(tree, 3)
	ok = _chk(lines, brain_b.state == EnemyBrainLite3D.CHASE, "3D: home again -> re-aggros the camper") and ok
	player_b.queue_free()
	body_b.queue_free()


	# --- a corpse that stays in the scene stops fighting, and resumes on revive ---
	var grp := &"test3_dead"
	var gx := 2200.0
	var mark := _stub_player(host, grp, Vector3(gx, 0, 1.2))
	var body_k := _enemy_body()
	body_k.position = Vector3(gx, 0, 0)
	host.add_child(body_k)
	var hp_k: Node = ALIVE_HEALTH.new()
	body_k.add_child(hp_k)
	var brain_k := EnemyBrainLite3D.new()
	brain_k.target_group = grp
	brain_k.attack_cooldown = 0.2
	body_k.add_child(brain_k)
	var swings := {"n": 0}
	brain_k.attacked.connect(func(_t: Node3D) -> void: swings["n"] += 1)
	await _frames(tree, 6)
	var fought: bool = brain_k.state == EnemyBrainLite3D.ATTACK and swings["n"] >= 1
	hp_k.alive = false
	await _frames(tree, 4)
	var frozen: int = swings["n"]
	await _wait(tree, 0.8)
	ok = _chk(lines, fought and brain_k.state == EnemyBrainLite3D.IDLE and brain_k.target == null and swings["n"] == frozen and is_zero_approx(body_k.velocity.x),
		"3D: a dead enemy that stays in the scene stops attacking and goes idle (%d swings, state %s)" % [swings["n"], brain_k.state]) and ok
	hp_k.alive = true
	await _wait(tree, 0.6)
	ok = _chk(lines, brain_k.state == EnemyBrainLite3D.ATTACK and swings["n"] > frozen,
		"3D: when it revives it hunts and attacks again") and ok
	mark.queue_free()
	body_k.queue_free()


	# --- a freed target with another one in range: it switches, it does not walk home ---
	var two_a := _stub_player(host, &"two3", Vector3(3003, 0, 3000))
	var two_b := _stub_player(host, &"two3", Vector3(3005, 0, 3000))
	var body_t := _enemy_body()
	body_t.position = Vector3(3000, 0, 3000)
	host.add_child(body_t)
	var brain_t := EnemyBrainLite3D.new()
	brain_t.target_group = &"two3"
	brain_t.give_up_radius = 1.0e9
	body_t.add_child(brain_t)
	var lost_t := {"n": 0}
	brain_t.target_lost.connect(func() -> void: lost_t["n"] += 1)
	await _frames(tree, 4)
	var first_ok: bool = brain_t.target == two_a
	two_a.queue_free()
	await _frames(tree, 3)
	ok = _chk(lines, first_ok and lost_t["n"] == 1 and brain_t.target == two_b and (brain_t.state == EnemyBrainLite3D.CHASE or brain_t.state == EnemyBrainLite3D.ATTACK),
		"3D: a target freed with another one in range: the brain switches to it instead of walking home (state %s)" % brain_t.state) and ok
	two_b.queue_free()
	body_t.queue_free()

	# --- an enemy that falls well below home does not flicker: the leash is on the ground ---
	var mark_f := _stub_player(host, &"fall3", Vector3(3300, 0, 3303))
	var body_f2 := _enemy_body()
	body_f2.position = Vector3(3300, 12, 3300)
	host.add_child(body_f2)
	var brain_f2 := EnemyBrainLite3D.new()
	brain_f2.target_group = &"fall3"
	brain_f2.give_up_radius = 10.0
	body_f2.add_child(brain_f2)
	var changes := {"n": 0, "trail": ""}
	brain_f2.state_changed.connect(func(a: StringName, b: StringName) -> void:
		changes["n"] += 1
		changes["trail"] += "%s>%s@%d " % [a, b, Engine.get_physics_frames()])
	await _wait(tree, 2.5)
	ok = _chk(lines, changes["n"] < 6 and (brain_f2.state == EnemyBrainLite3D.CHASE or brain_f2.state == EnemyBrainLite3D.ATTACK) and absf(body_f2.global_position.y) < 0.1,
		"3D: an enemy that falls 12 m below home with the player nearby settles instead of flickering (%d state changes, state %s, %s)" % [changes["n"], brain_f2.state, changes["trail"]]) and ok
	mark_f.queue_free()
	body_f2.queue_free()

	ground.queue_free()

	return {"ok": ok, "lines": lines}


# ---- helpers -------------------------------------------------------------

# a 1.8 m capsule with its feet at the body's origin, like the dock builds
static func _enemy_body() -> CharacterBody3D:
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	shape.shape = cap
	shape.position = Vector3(0, 0.9, 0)
	body.add_child(shape)
	return body


# a floor wide enough that every section's rig stands on it
static func _floor(host: Node) -> StaticBody3D:
	var f := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12000, 1, 12000)
	cs.shape = box
	f.add_child(cs)
	f.position = Vector3(0, -0.5, 0)
	host.add_child(f)
	return f


static func _stub_player(host: Node, group: StringName, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	host.add_child(p)
	p.global_position = pos
	p.add_to_group(group)
	return p


static func _forward(n: Node3D) -> Vector3:
	return -n.global_transform.basis.z


static func _frames(tree: SceneTree, n: int) -> void:
	for i in _n(n):
		await tree.physics_frame


# Frame counts in these checks are written for 60 physics ticks a second and scaled to
# the project's rate, so a project at 120 gets the same time to settle.
static func _n(frames: int) -> int:
	return ceili(frames * Engine.physics_ticks_per_second / 60.0)


static func _wait(tree: SceneTree, seconds: float) -> void:
	await tree.create_timer(seconds, true, false, true).timeout
	await tree.process_frame
	await tree.physics_frame


static func _chk(lines: Array[String], cond: bool, label: String) -> bool:
	lines.append(("[ok] " if cond else "[XX] ") + label)
	return cond


# EnemyAILite is looked up when used instead of named. A script that names an autoload
# won't compile until the plugin that adds it is switched on, so a fresh install
# printed parse errors.
const ENEMY_AI_LITE := preload("res://addons/enemy_ai_lite/enemy_ai_bus_lite.gd")


static func _enemy_ai_lite() -> ENEMY_AI_LITE:
	return (Engine.get_main_loop() as SceneTree).root.get_node(^"EnemyAILite") as ENEMY_AI_LITE
