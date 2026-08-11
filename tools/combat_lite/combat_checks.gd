extends RefCounted

# Shared checks for Combat — Lite, used by both the headless verify and the
# on-screen acceptance banner. `host` must be in the SceneTree so node _ready
# wiring (hurtbox finding its health) runs.

static func run(host: Node) -> Dictionary:
	var lines: Array[String] = []
	var ok := true

	# --- Health logic ---
	var h := HealthLite.new()
	h.max_health = 100.0
	var died := {"v": false}
	h.died.connect(func() -> void: died["v"] = true)
	h.take_damage(30.0)
	ok = _chk(lines, is_equal_approx(h.current, 70.0), "take_damage 30 -> 70 hp") and ok
	h.heal(10.0)
	ok = _chk(lines, is_equal_approx(h.current, 80.0), "heal 10 -> 80 hp") and ok
	h.take_damage(999.0)
	ok = _chk(lines, is_equal_approx(h.current, 0.0), "overkill clamps to 0") and ok
	ok = _chk(lines, died["v"], "died signal fired at 0 hp") and ok
	ok = _chk(lines, not h.is_alive(), "not alive at 0 hp") and ok
	h.free()

	# --- Hitbox / Hurtbox team gating (needs the tree for _ready wiring) ---
	var hits := {"n": 0}
	var relay := func(_p: Vector2, _a: float, _s: Node) -> void: hits["n"] += 1
	CombatLite.hit_landed.connect(relay)

	var enemy := Node2D.new()
	var eh := HealthLite.new()
	eh.max_health = 50.0
	var hurt := HurtboxLite.new()
	hurt.team = 1
	enemy.add_child(eh)
	enemy.add_child(hurt)
	host.add_child(enemy)                       # _ready -> hurt binds to eh

	var hb_enemy := HitboxLite.new()
	hb_enemy.team = 0
	hb_enemy.damage = 20.0
	host.add_child(hb_enemy)
	hb_enemy._on_area_entered(hurt)             # simulate overlap, different team
	ok = _chk(lines, is_equal_approx(eh.current, 30.0), "diff-team hit dealt 20 (50 -> 30)") and ok
	ok = _chk(lines, hits["n"] == 1, "hit_landed bus fired once") and ok

	var hb_friend := HitboxLite.new()
	hb_friend.team = 1
	hb_friend.damage = 20.0
	host.add_child(hb_friend)
	hb_friend._on_area_entered(hurt)            # same team -> ignored
	ok = _chk(lines, is_equal_approx(eh.current, 30.0), "same-team hit ignored (no friendly fire)") and ok

	CombatLite.hit_landed.disconnect(relay)
	enemy.queue_free()
	hb_enemy.queue_free()
	hb_friend.queue_free()

	return {"ok": ok, "lines": lines}


static func _chk(lines: Array[String], cond: bool, label: String) -> bool:
	lines.append(("[ok] " if cond else "[XX] ") + label)
	return cond
