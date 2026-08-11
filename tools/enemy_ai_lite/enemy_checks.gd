extends RefCounted

# Shared checks for Enemy AI — Lite, used by the headless verify and the
# acceptance banner. Sections use distinct target groups so brains never see
# another section's stand-in player. Everything explicitly typed.

static func run(host: Node) -> Dictionary:
	var lines: Array[String] = []
	var ok := true

	var orphan_parent := Node.new()
	var orphan := EnemyBrainLite.new()
	orphan_parent.add_child(orphan)
	host.add_child(orphan_parent)
	ok = _chk(lines, not orphan.is_physics_processing(), "brain on a non-body parent turns itself off") and ok

	var idle_body := _enemy_body()
	var idle_brain := EnemyBrainLite.new()
	idle_body.add_child(idle_brain)
	host.add_child(idle_body)
	ok = _chk(lines, idle_brain.state == EnemyBrainLite.IDLE, "starts idle") and ok

	for n in [orphan_parent, idle_body]:
		n.queue_free()

	return {"ok": ok, "lines": lines}


static func run_physics(host: Node) -> Dictionary:
	var lines: Array[String] = []
	var ok := true
	var tree: SceneTree = host.get_tree()

	# --- chase -> attack -> cooldown (no leash: huge give_up) ---
	var player_a := _stub_player(host, &"lite_a", Vector2(100, 0))
	var body_a := _enemy_body()
	body_a.global_position = Vector2.ZERO
	host.add_child(body_a)
	var brain_a := EnemyBrainLite.new()
	brain_a.target_group = &"lite_a"
	brain_a.detect_radius = 160.0
	brain_a.attack_radius = 30.0
	brain_a.give_up_radius = 1.0e9
	brain_a.attack_cooldown = 0.3
	body_a.add_child(brain_a)
	var acquired := {"n": 0}
	var attacks := {"n": 0, "bus": 0}
	brain_a.target_acquired.connect(func(_t: Node2D) -> void: acquired["n"] += 1)
	brain_a.attacked.connect(func(_t: Node2D) -> void: attacks["n"] += 1)
	var on_bus := func(_e: Node, _t: Node) -> void: attacks["bus"] += 1
	EnemyAILite.attack_started.connect(on_bus)

	await _frames(tree, 3)
	ok = _chk(lines, brain_a.state == EnemyBrainLite.CHASE, "player in detect radius -> chase") and ok
	ok = _chk(lines, acquired["n"] == 1, "target_acquired fired") and ok
	ok = _chk(lines, body_a.velocity.x > 0.0, "chasing moves toward the player") and ok

	player_a.global_position = body_a.global_position + Vector2(10, 0)
	await _frames(tree, 3)
	ok = _chk(lines, brain_a.state == EnemyBrainLite.ATTACK, "in attack radius -> attack state") and ok
	ok = _chk(lines, attacks["n"] == 1 and attacks["bus"] == 1, "attack fired once (signal + bus)") and ok
	await _wait(tree, 0.15)
	ok = _chk(lines, attacks["n"] == 1, "cooldown holds: no second attack yet") and ok
	EnemyAILite.attack_started.disconnect(on_bus)
	player_a.queue_free()
	body_a.queue_free()

	# --- leash -> return -> re-aggro ---
	var player_b := _stub_player(host, &"lite_b", Vector2(70, 0))
	var body_b := _enemy_body()
	body_b.global_position = Vector2.ZERO
	host.add_child(body_b)
	var brain_b := EnemyBrainLite.new()
	brain_b.target_group = &"lite_b"
	brain_b.detect_radius = 160.0
	brain_b.give_up_radius = 60.0
	brain_b.move_speed = 300.0
	body_b.add_child(brain_b)
	await _frames(tree, 3)
	ok = _chk(lines, brain_b.state == EnemyBrainLite.CHASE, "leash test: chasing first") and ok
	body_b.global_position = Vector2(100, 0)
	player_b.global_position = Vector2(90, 0)
	await _frames(tree, 3)
	ok = _chk(lines, brain_b.state == EnemyBrainLite.RETURN, "past give_up_radius -> walks home") and ok
	ok = _chk(lines, brain_b.target == null, "leash dropped the target") and ok
	ok = _chk(lines, body_b.velocity.x < 0.0, "returning moves toward home") and ok
	var settled := 0
	while brain_b.state == EnemyBrainLite.RETURN and settled < 240:
		await tree.physics_frame
		settled += 1
	await _frames(tree, 3)
	ok = _chk(lines, brain_b.state == EnemyBrainLite.CHASE, "home again -> re-aggros the camper") and ok
	player_b.queue_free()
	body_b.queue_free()

	return {"ok": ok, "lines": lines}


# ---- helpers -------------------------------------------------------------

static func _enemy_body() -> CharacterBody2D:
	var body := CharacterBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(18, 18)
	shape.shape = rect
	body.add_child(shape)
	return body


static func _stub_player(host: Node, group: StringName, pos: Vector2) -> Node2D:
	var p := Node2D.new()
	p.global_position = pos
	p.add_to_group(group)
	host.add_child(p)
	return p


static func _frames(tree: SceneTree, n: int) -> void:
	for i in n:
		await tree.physics_frame


static func _wait(tree: SceneTree, seconds: float) -> void:
	await tree.create_timer(seconds, true, false, true).timeout
	await tree.physics_frame


static func _chk(lines: Array[String], cond: bool, label: String) -> bool:
	lines.append(("[ok] " if cond else "[XX] ") + label)
	return cond
