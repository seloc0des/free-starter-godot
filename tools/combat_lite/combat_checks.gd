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
	_combat_lite().hit_landed.connect(relay)

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

	_combat_lite().hit_landed.disconnect(relay)
	enemy.queue_free()
	hb_enemy.queue_free()
	hb_friend.queue_free()

	return {"ok": ok, "lines": lines}


# The dock's "Remove it when it dies" tick sets remove_on_death. The character
# goes once died has gone out: listeners still hear the death with the body
# there, and a frame later it's gone. Off, the script default, it stays like it
# always did. Needs frames, so call it with await.
static func run_death(host: Node) -> Dictionary:
	var lines: Array[String] = []
	var ok := true
	var tree := host.get_tree()

	var goner := _body_rig(host, true)
	var stayer := _body_rig(host, false)
	var twice := _body_rig(host, true)
	var gh := goner.get_node("HealthLite") as HealthLite
	var heard := {"n": 0, "there": false}
	gh.died.connect(func() -> void:
		heard["n"] += 1
		heard["there"] = goner.is_inside_tree() and not goner.is_queued_for_deletion())
	var reported := {"who": null}
	var on_dead := func(e: Node) -> void: reported["who"] = e
	_combat_lite().entity_died.connect(on_dead)
	var th := twice.get_node("HealthLite") as HealthLite
	th.died.connect(twice.queue_free)       # older scenes did this by hand
	await tree.process_frame
	gh.take_damage(9999.0)
	ok = _chk(lines, heard["n"] == 1 and heard["there"], "remove on death: a listener on died still runs, with the character still there") and ok
	ok = _chk(lines, reported["who"] == goner, "remove on death: the CombatLite bus still reports the death with the character") and ok
	ok = _chk(lines, is_instance_valid(goner) and goner.is_inside_tree(), "remove on death: the character isn't taken out in the middle of the hit") and ok
	(stayer.get_node("HealthLite") as HealthLite).take_damage(9999.0)
	th.take_damage(9999.0)
	await tree.process_frame
	ok = _chk(lines, not is_instance_valid(goner), "remove on death: the character is gone a frame later") and ok
	ok = _chk(lines, is_instance_valid(stayer) and stayer.is_inside_tree(), "remove on death off (the default): the character stays") and ok
	ok = _chk(lines, not is_instance_valid(twice), "remove on death: a died listener that frees the character as well does no harm") and ok
	_combat_lite().entity_died.disconnect(on_dead)
	# a broken build may have removed it already, and that should read as a fail, not a crash
	if is_instance_valid(stayer):
		stayer.queue_free()
	return {"ok": ok, "lines": lines}


# flash_on_hit, on by default: a hit that hurts but doesn't kill tints the character
# and it fades back; a second hit mid-flash still fades back to the colour it had
# before; the killing hit doesn't flash; off means no flash. Needs frames, so await it.
static func run_flash(host: Node) -> Dictionary:
	var lines: Array[String] = []
	var ok := true
	var tree := host.get_tree()

	var body := _body_rig(host, false)
	body.modulate = Color(0.8, 0.9, 1.0)       # a character tinted on purpose keeps its tint
	var hp := body.get_node("HealthLite") as HealthLite
	ok = _chk(lines, bool(hp.get("flash_on_hit")), "flash on hit: on by default") and ok
	await tree.process_frame
	hp.take_damage(5.0)
	ok = _chk(lines, not body.modulate.is_equal_approx(Color(0.8, 0.9, 1.0)), "flash on hit: a hit that hurts tints the character") and ok
	await tree.create_timer(0.1).timeout
	hp.take_damage(5.0)                         # lands mid-flash
	await tree.create_timer(0.45).timeout
	ok = _chk(lines, body.modulate.is_equal_approx(Color(0.8, 0.9, 1.0)), "flash on hit: it fades back to the colour it had, even after a hit mid-flash") and ok
	hp.take_damage(999.0)
	ok = _chk(lines, body.modulate.is_equal_approx(Color(0.8, 0.9, 1.0)), "flash on hit: the killing hit doesn't flash") and ok

	var plain := _body_rig(host, false)
	var php := plain.get_node("HealthLite") as HealthLite
	php.set("flash_on_hit", false)
	await tree.process_frame
	php.take_damage(5.0)
	ok = _chk(lines, plain.modulate.is_equal_approx(Color.WHITE), "flash on hit off: no flash") and ok

	body.queue_free()
	plain.queue_free()
	return {"ok": ok, "lines": lines}


# A character with Health + Hurtbox, the way the dock bakes it. remove_on_death
# by name, so an older health_lite.gd fails these checks instead of failing to
# load them.
static func _body_rig(host: Node, remove: bool) -> Node2D:
	var n := Node2D.new()
	var hp := HealthLite.new()
	hp.name = "HealthLite"
	hp.max_health = 30.0
	hp.set("remove_on_death", remove)
	n.add_child(hp)
	var hurt := HurtboxLite.new()
	hurt.team = 1
	n.add_child(hurt)
	host.add_child(n)
	return n


static func _chk(lines: Array[String], cond: bool, label: String) -> bool:
	lines.append(("[ok] " if cond else "[XX] ") + label)
	return cond


# CombatLite is looked up when used instead of named. A script that names an autoload
# won't compile until the plugin that adds it is switched on, so a fresh install
# printed parse errors.
const COMBAT_LITE := preload("res://addons/combat_lite/combat_events_lite.gd")


static func _combat_lite() -> COMBAT_LITE:
	return (Engine.get_main_loop() as SceneTree).root.get_node(^"CombatLite") as COMBAT_LITE
