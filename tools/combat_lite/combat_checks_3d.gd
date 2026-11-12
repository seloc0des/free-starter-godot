extends RefCounted

# Checks for the 3D half of Combat (Lite): HitboxLite3D, HurtboxLite3D and the
# HealthLite flash on a 3D body. Async (physics frames), so call it with `await`.
# `host` must be in the SceneTree. Everything sits far from the origin so it can't
# touch the 2D checks, and no input action is driven, so a real gamepad changes nothing.

static func run(host: Node) -> Dictionary:
	var lines: Array[String] = []
	var ok := true
	var tree := host.get_tree()

	# --- team gating by real overlap, and the bus position ---
	var foe := _dummy(host, Vector3(1000, 0, 0), 1, 40.0)
	var friend := _dummy(host, Vector3(1010, 0, 0), 0, 40.0)
	var sword := _hitbox(host, Vector3(0, 0, 0), 0, 15.0)
	var seen := {"n": 0, "pos": null}
	var on_hit := func(p, _a: float, _s: Node) -> void:
		seen["n"] += 1
		seen["pos"] = p
	_combat_lite().hit_landed.connect(on_hit)
	await tree.physics_frame
	ok = _chk(lines, is_equal_approx(foe["hp"].current, 40.0), "3D hitbox: no damage while apart") and ok
	sword.global_position = Vector3(1000, 0, 0)
	for i in 10:
		await tree.physics_frame
	ok = _chk(lines, is_equal_approx(foe["hp"].current, 25.0),
		"3D hitbox: a player side hitbox overlapping an enemy side hurtbox deals its damage (40 -> %.0f)" % foe["hp"].current) and ok
	ok = _chk(lines, seen["n"] == 1 and typeof(seen["pos"]) == TYPE_VECTOR3 and (seen["pos"] as Vector3).is_equal_approx(Vector3(1000, 0, 0)),
		"3D hurtbox: hit_landed on the bus carries a Vector3 position (%s)" % str(seen["pos"])) and ok
	sword.global_position = Vector3(1010, 0, 0)
	for i in 10:
		await tree.physics_frame
	ok = _chk(lines, is_equal_approx(friend["hp"].current, 40.0), "3D hitbox: a hitbox on the same team does nothing to the hurtbox") and ok
	_combat_lite().hit_landed.disconnect(on_hit)

	# --- the hit shows on the body, not at the feet ---
	var tall := _dummy(host, Vector3(2000, 0, 0), 1, 40.0)
	(tall["hurt"].get_child(0) as Node3D).position = Vector3(0, 0.9, 0)
	var seen_at := {"p": null}
	var on_tall := func(p, _a: float, _s: Node) -> void: seen_at["p"] = p
	_combat_lite().hit_landed.connect(on_tall)
	(tall["hurt"] as HurtboxLite3D).receive_hit(5.0, null)
	ok = _chk(lines, seen_at["p"] is Vector3 and (seen_at["p"] as Vector3).is_equal_approx(Vector3(2000, 0.9, 0)),
		"3D hurtbox: the bus position is the middle of its shape (0.9 m up), not the feet (%s)" % str(seen_at["p"])) and ok
	_combat_lite().hit_landed.disconnect(on_tall)
	tall["root"].free()

	# --- one_shot ---
	var once := _hitbox(host, Vector3(3000, 0, 0), 0, 10.0)
	once.one_shot = true
	var q := _dummy(host, Vector3(3000, 0, 0), 1, 40.0)
	for i in 8:
		await tree.physics_frame
	ok = _chk(lines, is_equal_approx(q["hp"].current, 30.0) and not once.monitoring,
		"3D hitbox: one_shot lands once, then stops watching (%.0f)" % q["hp"].current) and ok

	# --- death reports on the bus, with the body ---
	var reported := {"who": null}
	var on_dead := func(e: Node) -> void: reported["who"] = e
	_combat_lite().entity_died.connect(on_dead)
	var doomed := _dummy(host, Vector3(4000, 0, 0), 1, 10.0)
	(doomed["hurt"] as HurtboxLite3D).receive_hit(50.0, null)
	ok = _chk(lines, reported["who"] == doomed["root"] and not doomed["hp"].is_alive(), "3D hurtbox: a killing hit reports entity_died with the body") and ok
	_combat_lite().entity_died.disconnect(on_dead)

	# --- the Health flash on a 3D body ---
	var fb := Node3D.new()
	fb.position = Vector3(8000, 0, 0)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	var own_overlay := StandardMaterial3D.new()
	mesh.material_overlay = own_overlay            # a character with its own overlay keeps it
	fb.add_child(mesh)
	var bare := MeshInstance3D.new()
	bare.mesh = BoxMesh.new()
	fb.add_child(bare)
	var fhp := HealthLite.new()
	fhp.max_health = 30.0
	fb.add_child(fhp)
	host.add_child(fb)
	await tree.process_frame
	fhp.take_damage(5.0)
	var lit := mesh.material_overlay as StandardMaterial3D
	ok = _chk(lines, lit != null and lit != own_overlay and lit.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and bare.material_overlay == lit,
		"3D flash: a hit that hurts puts an unshaded overlay on every mesh under the body") and ok
	await tree.create_timer(0.1).timeout
	fhp.take_damage(5.0)                           # lands mid-flash
	ok = _chk(lines, mesh.material_overlay is StandardMaterial3D and mesh.material_overlay.albedo_color.a > 0.5,
		"3D flash: a second hit mid-flash lights it up again") and ok
	await tree.create_timer(0.45).timeout
	ok = _chk(lines, mesh.material_overlay == own_overlay and bare.material_overlay == null,
		"3D flash: it fades away and every mesh gets back the overlay it had (its own, or none)") and ok
	fhp.take_damage(999.0)
	ok = _chk(lines, mesh.material_overlay == own_overlay and bare.material_overlay == null, "3D flash: the killing hit doesn't flash") and ok
	var fb2 := Node3D.new()
	fb2.position = Vector3(8100, 0, 0)
	var m2 := MeshInstance3D.new()
	fb2.add_child(m2)
	var fhp2 := HealthLite.new()
	fhp2.max_health = 30.0
	fhp2.flash_on_hit = false
	fb2.add_child(fhp2)
	host.add_child(fb2)
	await tree.process_frame
	fhp2.take_damage(5.0)
	ok = _chk(lines, m2.material_overlay == null, "3D flash: flash_on_hit off, no flash") and ok

	# --- flat things are tinted, not overlaid; a Health leaving the tree ends the flash ---
	var sb := Node3D.new()
	sb.position = Vector3(8200, 0, 0)
	var spr := Sprite3D.new()
	var lab := Label3D.new()
	var sm := MeshInstance3D.new()
	sm.mesh = BoxMesh.new()
	var gpu := GPUParticles3D.new()
	var cpu := CPUParticles3D.new()
	sb.add_child(gpu)
	sb.add_child(cpu)
	sb.add_child(spr)
	sb.add_child(lab)
	sb.add_child(sm)
	var shp := HealthLite.new()
	shp.max_health = 50.0
	sb.add_child(shp)
	host.add_child(sb)
	await tree.process_frame
	shp.take_damage(5.0)
	ok = _chk(lines, spr.material_overlay == null and lab.material_overlay == null and sm.material_overlay != null,
		"3D flash: a Sprite3D and a Label3D get no overlay box, a mesh does") and ok
	ok = _chk(lines, gpu.material_overlay == null and cpu.material_overlay == null, "3D flash: GPU and CPU particles are left alone, not turned into white boxes") and ok
	ok = _chk(lines, spr.modulate.r > 1.5 and lab.modulate.r > 1.5, "3D flash: the Sprite3D and the Label3D are tinted bright for the flash") and ok
	await tree.create_timer(0.45).timeout
	ok = _chk(lines, spr.modulate.is_equal_approx(Color.WHITE) and lab.modulate.is_equal_approx(Color.WHITE) and sm.material_overlay == null,
		"3D flash: the sprite and label fade back to their own colour and the mesh to its own overlay") and ok
	shp.take_damage(5.0)
	sb.remove_child(shp)
	ok = _chk(lines, sm.material_overlay == null and spr.modulate.is_equal_approx(Color.WHITE),
		"3D flash: a Health taken out mid-flash puts everything back at once") and ok
	shp.free()

	# --- a 2D body hit, then out of the tree and back within the flash, still fades to its own colour ---
	var fbody := Node2D.new()
	fbody.modulate = Color(0.8, 0.9, 1.0)
	fbody.position = Vector2(42000, 0)
	var fhp3 := HealthLite.new()
	fhp3.max_health = 50.0
	fbody.add_child(fhp3)
	host.add_child(fbody)
	await tree.process_frame
	fhp3.take_damage(5.0)
	fbody.remove_child(fhp3)
	await tree.create_timer(0.05).timeout
	fbody.add_child(fhp3)
	await tree.create_timer(0.5).timeout
	ok = _chk(lines, fbody.modulate.is_equal_approx(Color(0.8, 0.9, 1.0)),
		"flash on hit: a 2D body hit and then removed and re-added mid-flash still fades back to its own colour (%s)" % str(fbody.modulate)) and ok
	fbody.free()

	# --- the shipped 3D demo (starter kits ship the tools but no demo) ---
	var demo_path := "res://demo/combat_lite/combat_demo_3d.tscn"
	if not ResourceLoader.exists(demo_path):
		lines.append("[--] 3D demo: skipped, no demo/ folder here")
	else:
		var demo: Node3D = (load(demo_path) as PackedScene).instantiate()
		demo.position = Vector3(20000, 0, 0)
		host.add_child(demo)
		var dummy := demo.get_node("Dummy") as Node3D
		var dhp := demo.get_node("%DummyHealth") as HealthLite
		for i in 3:
			await tree.physics_frame
		(demo.get_node("%Player") as Node3D).global_position = dummy.global_position + Vector3(0, 0, 1.0)
		var swing := demo.get_node("%Sword") as HitboxLite3D
		swing.monitoring = true
		for i in 10:
			await tree.physics_frame
		ok = _chk(lines, is_equal_approx(dhp.current, 35.0), "3D demo: a swing near the dummy hurts it (60 -> %.0f)" % dhp.current) and ok
		await tree.create_timer(0.4).timeout     # let the hit flash end first
		# freed child by child: the headless dummy renderer logs an error when the whole
		# demo (sky, meshes, shared materials) goes in one free(). Nothing in the pack does.
		for c in demo.get_children():
			c.free()
		demo.free()

	for n in [foe["root"], friend["root"], sword, once, q["root"], doomed["root"], fb, fb2, sb]:
		if is_instance_valid(n):
			n.free()
	return {"ok": ok, "lines": lines}


# A body with HealthLite and a hurtbox (1 m box) on `team`.
static func _dummy(host: Node, at: Vector3, team: int, hp: float) -> Dictionary:
	var root := Node3D.new()
	root.position = at
	var h := HealthLite.new()
	h.max_health = hp
	root.add_child(h)
	var hurt := HurtboxLite3D.new()
	hurt.team = team
	hurt.add_child(_shape3(Vector3(1, 1, 1)))
	root.add_child(hurt)
	host.add_child(root)
	return {"root": root, "hp": h, "hurt": hurt}


static func _hitbox(host: Node, at: Vector3, team: int, dmg: float) -> HitboxLite3D:
	var hb := HitboxLite3D.new()
	hb.team = team
	hb.damage = dmg
	hb.position = at
	hb.add_child(_shape3(Vector3(1, 1, 1)))
	host.add_child(hb)
	return hb


static func _shape3(size: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	return cs


static func _chk(lines: Array[String], cond: bool, label: String) -> bool:
	lines.append(("[ok] " if cond else "[XX] ") + label)
	return cond


# CombatLite is looked up when used instead of named. A script that names an autoload
# won't compile until the plugin that adds it is switched on, so a fresh install
# printed parse errors.
const COMBAT_LITE := preload("res://addons/combat_lite/combat_events_lite.gd")


static func _combat_lite() -> COMBAT_LITE:
	return (Engine.get_main_loop() as SceneTree).root.get_node(^"CombatLite") as COMBAT_LITE
