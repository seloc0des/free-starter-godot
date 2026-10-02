extends RefCounted

# The Combat (Lite) dock's defaults decide whether a buyer's first fight works: bake
# Health + Hurtbox on the enemy, a Hitbox on the weapon, touch no field, press
# Play, and the hit has to land. The buttons need the editor (the journey probe
# clicks those), so this reads the defaults off a real dock and plays them out
# with real overlap instead of a hand-called signal.

const DOCK := preload("res://addons/combat_lite/editor/combat_chooser_dock.gd")
const BRAIN := preload("res://tools/combat_lite/fixtures/stand_in_brain.gd")
const BRAIN_LITE := preload("res://tools/combat_lite/fixtures/stand_in_brain_lite.gd")


static func run(host: Node) -> Dictionary:
	var lines: Array[String] = []
	var ok := true
	var tree := host.get_tree()

	var dock: Control = DOCK.new()
	host.add_child(dock)  # _ready builds the fields
	var hurt_pick: OptionButton = dock._hurt_side
	var hit_pick: OptionButton = dock._hit_side
	var hurt_team := hurt_pick.get_selected_id()
	var hit_team := hit_pick.get_selected_id()
	var max_hp: float = dock._hp.value
	var dmg: float = dock._dmg.value
	ok = _chk(lines, hurt_team == DOCK.TEAM_ENEMY, "dock: Health + Hurtbox defaults to the enemy side (team %d)" % hurt_team) and ok
	ok = _chk(lines, hit_team == DOCK.TEAM_PLAYER, "dock: Hitbox defaults to the player side (team %d)" % hit_team) and ok
	ok = _chk(lines, _ids(hurt_pick) == [1, 0] and _ids(hit_pick) == [0, 1],
		"dock: both side picks offer both sides, as teams 0 and 1") and ok
	ok = _chk(lines, DOCK.TEAM_PLAYER == 0 and DOCK.TEAM_ENEMY == 1,
		"dock: player side is team 0 and enemy side team 1, like the demo and the script defaults") and ok
	dock.free()

	# the fight the defaults bake: 32x32 shapes, like the dock's
	var enemy := Node2D.new()
	enemy.position = Vector2(600, 400)
	host.add_child(enemy)
	var hp := HealthLite.new()
	hp.max_health = max_hp
	enemy.add_child(hp)
	var hurt := HurtboxLite.new()
	hurt.team = hurt_team
	_add_shape(hurt)
	enemy.add_child(hurt)
	var sword := Node2D.new()
	sword.position = Vector2(-600, -400)
	host.add_child(sword)
	var hit := HitboxLite.new()
	hit.team = hit_team
	hit.damage = dmg
	_add_shape(hit)
	sword.add_child(hit)

	for i in 3:
		await tree.physics_frame
	ok = _chk(lines, is_equal_approx(hp.current, max_hp), "defaults: no damage while apart") and ok
	sword.global_position = enemy.global_position
	for i in 30:
		await tree.physics_frame
		if hp.current < max_hp:
			break
	ok = _chk(lines, is_equal_approx(hp.current, max_hp - dmg),
		"defaults: the baked hitbox hurts the baked hurtbox on overlap (%.0f -> %.0f)" % [max_hp, hp.current]) and ok

	enemy.free()
	sword.free()

	# --- Add Hitbox on an Enemy AI enemy fits the brain's attack radius ---
	# The brain stops at attack_radius, and at its own 40 two of this dock's 32x32
	# boxes never touch. fit_enemy_reach is the button's headless half.
	var reach = DOCK.new()
	var said: String = ""
	ok = _chk(lines, is_equal_approx(reach.reach_for(16.0, 16.0), 24.0), "reach: two 32x32 boxes -> 24") and ok
	ok = _chk(lines, is_equal_approx(reach.reach_for(16.0, 16.0, 25.0), 27.0), "reach: bodies touching at 25 (a 32x32 player) push it out to 25 + 2 = 27") and ok
	ok = _chk(lines, is_equal_approx(reach.reach_for(16.0, 16.0, 33.0), 30.0), "reach: bodies touching at 33, past the boxes' reach: capped at 32 - 2 = 30") and ok

	var dflt := _reach_rig(host, Vector2(-9000, 0), _rect(32, 32), _rect(32, 32), BRAIN)
	said = reach.fit_enemy_reach(dflt["enemy"], dflt["hit"], dflt["root"])
	ok = _chk(lines, _radius(dflt) == 24.0 and said.contains("attack radius to 24 ") and said.contains("measured from both boxes"),
		"reach: this dock's boxes (32x32 each) -> the brain's attack radius is 24, and the status says so (%.1f)" % _radius(dflt)) and ok
	ok = _chk(lines, not said.contains("same side"), "reach: an enemy side hitbox and a player side hurtbox get no side warning") and ok
	ok = _chk(lines, dflt["brain"].attack_node_path == dflt["brain"].get_path_to(dflt["hit"]) and said.contains("switches this hitbox on for each attack"),
		"swing: a Pro brain gets attack_node_path pointed at the hitbox, and the status says it keeps hitting [%s]" % str(dflt["brain"].attack_node_path)) and ok

	var custom := _reach_rig(host, Vector2(-8500, 0), _circle(24), _rect(20, 20), BRAIN)
	said = reach.fit_enemy_reach(custom["enemy"], custom["hit"], custom["root"])
	ok = _chk(lines, _radius(custom) == 25.5 and said.contains("attack radius to 25.5 "),
		"reach: circle r24 hitbox + 20 wide hurtbox -> 0.75 x (24 + 10) = 25.5 (%.1f)" % _radius(custom)) and ok

	var bare := _reach_rig(host, Vector2(-8000, 0), _circle(20), null, BRAIN)
	said = reach.fit_enemy_reach(bare["enemy"], bare["hit"], bare["root"])
	ok = _chk(lines, _radius(bare) == 27.0 and said.contains("player's hurtbox counted as this dock's 32x32 box"),
		"reach: player without a hurtbox yet counts as a 32x32 box -> 0.75 x (20 + 16) = 27 (%.1f)" % _radius(bare)) and ok

	# clicking again after the hitbox was resized measures again
	(dflt["hit"].get_child(0) as CollisionShape2D).shape = _rect(48, 48)
	said = reach.fit_enemy_reach(dflt["enemy"], dflt["hit"], dflt["root"])
	ok = _chk(lines, _radius(dflt) == 30.0, "reach: clicking again after the hitbox grew to 48 wide -> 30 (%.1f)" % _radius(dflt)) and ok

	var same := _reach_rig(host, Vector2(-7500, 0), _rect(32, 32), _rect(32, 32), BRAIN)
	same["hit"].team = DOCK.TEAM_PLAYER
	said = reach.fit_enemy_reach(same["enemy"], same["hit"], same["root"])
	ok = _chk(lines, said.contains("same side") and not said.contains("keeps hurting"), "reach: a player side hitbox on the enemy gets a warning that it can't hurt the player, and no claim that it keeps hurting") and ok

	var weapon := _reach_rig(host, Vector2(-7000, 0), _rect(32, 32), _rect(32, 32), null)
	said = reach.fit_enemy_reach(weapon["enemy"], weapon["hit"], weapon["root"])
	ok = _chk(lines, said == "", "reach: a hitbox on something with no brain (a weapon, a spike) changes nothing and says nothing") and ok

	# the bodies: a 32x32 player and an 18x18 enemy touch at 25
	var big := _reach_rig(host, Vector2(-6500, 0), _rect(32, 32), _rect(32, 32), BRAIN, 32.0)
	said = reach.fit_enemy_reach(big["enemy"], big["hit"], big["root"])
	ok = _chk(lines, _radius(big) == 27.0 and said.contains("where the two bodies touch (25 px)"),
		"reach: 32x32 player body + 18x18 enemy body touch at 25 -> 27, and the status says why (%.1f)" % _radius(big)) and ok
	var huge := _reach_rig(host, Vector2(-6000, 0), _rect(32, 32), _rect(32, 32), BRAIN, 48.0)
	said = reach.fit_enemy_reach(huge["enemy"], huge["hit"], huge["root"])
	ok = _chk(lines, _radius(huge) == 30.0 and said.contains("they touch at 33 px") and said.contains("Make the hitbox bigger"),
		"reach: 48x48 player body touches at 33, past the boxes' 32 -> 30 and a plain 'make the hitbox bigger' (%.1f)" % _radius(huge)) and ok

	# swinging: one already pointed elsewhere keeps it; a Lite brain swings on its own
	var blade := Area2D.new()
	blade.name = "Sword"
	custom["enemy"].add_child(blade)
	custom["brain"].attack_node_path = custom["brain"].get_path_to(blade)
	said = reach.fit_enemy_reach(custom["enemy"], custom["hit"], custom["root"])
	ok = _chk(lines, custom["brain"].get_node_or_null(custom["brain"].attack_node_path) == blade and said.contains("already swings 'Sword'"),
		"swing: a Pro brain already pointed at something else keeps it, and the status says so") and ok
	var lite := _reach_rig(host, Vector2(-5500, 0), _rect(32, 32), _rect(32, 32), BRAIN_LITE)
	said = reach.fit_enemy_reach(lite["enemy"], lite["hit"], lite["root"])
	ok = _chk(lines, _radius(lite) == 24.0 and said.contains("switches this hitbox on for each attack"),
		"swing: a Lite brain gets the radius and the note that it switches the hitbox on for each attack") and ok
	for r in [dflt, custom, bare, same, weapon, big, huge, lite]:
		r["root"].free()

	# Played with real overlap: each enemy parked where its brain can end up. A
	# fitted brain stops at 24 at the farthest; one left at 40 gets no closer than
	# about 35.3 (it takes one more 140 px/s step after it arrives).
	var fit := _reach_rig(host, Vector2(-3000, 0), _rect(32, 32), _rect(32, 32), BRAIN)
	reach.fit_enemy_reach(fit["enemy"], fit["hit"], fit["root"])
	(fit["enemy"] as Node2D).position = Vector2(_radius(fit), 0)
	var old := _reach_rig(host, Vector2(-1500, 3000), _rect(32, 32), _rect(32, 32), BRAIN)
	(old["enemy"] as Node2D).position = Vector2(_radius(old) - 2.0 * 140.0 / 60.0 + 0.1, 0)
	# A brain switches its hitbox off after each swing and on for the next one;
	# that's what lets a hitbox that stays in reach hit again. One left on the
	# whole time hits once.
	var swung := _reach_rig(host, Vector2(0, 3000), _rect(32, 32), _rect(32, 32), BRAIN)
	(swung["enemy"] as Node2D).position = Vector2(24, 0)
	var left_on := _reach_rig(host, Vector2(1500, 3000), _rect(32, 32), _rect(32, 32), BRAIN)
	(left_on["enemy"] as Node2D).position = Vector2(24, 0)
	for i in 10:
		await tree.physics_frame
	var fit_hp: float = fit["hp"].current
	var old_hp: float = old["hp"].current
	ok = _chk(lines, fit_hp < max_hp, "reach, played: at the fitted radius the enemy's hitbox hurts the player (%.0f -> %.0f)" % [max_hp, fit_hp]) and ok
	ok = _chk(lines, is_equal_approx(old_hp, max_hp), "reach, played, control: at the brain's own 40 it never touches the player (%.0f)" % old_hp) and ok
	var sw: HitboxLite = swung["hit"]
	for n in 3:
		# what a brain does at the end of a swing and the start of the next
		sw.set_deferred("monitoring", false)
		for i in 5:
			await tree.physics_frame
		sw.set_deferred("monitoring", true)
		for i in 5:
			await tree.physics_frame
	var swung_hp: float = swung["hp"].current
	var left_hp: float = left_on["hp"].current
	ok = _chk(lines, is_equal_approx(swung_hp, max_hp - 4.0 * dmg),
		"swing, played: switched off and on three times while touching, it hits each time (%.0f -> %.0f, 4 hits)" % [max_hp, swung_hp]) and ok
	ok = _chk(lines, is_equal_approx(left_hp, max_hp - dmg),
		"swing, played, control: left on the whole time it hits once (%.0f -> %.0f)" % [max_hp, left_hp]) and ok
	for r in [fit, old, swung, left_on]:
		r["root"].free()
	reach.free()

	var rt: Dictionary = await run_remove_tick(host)
	lines.append_array(rt["lines"])
	ok = ok and rt["ok"]
	return {"ok": ok, "lines": lines}


# "Remove it when it dies": the tick's default for what's selected, and the
# button writing it. refresh_remove_tick is what selecting a node does, and
# bake_hurtable is Add Health + Hurtbox minus the selection. Looked up by name,
# so an older dock fails here instead of stopping the suite.
static func run_remove_tick(host: Node) -> Dictionary:
	var lines: Array[String] = []
	var ok := true
	var tree := host.get_tree()
	var td = DOCK.new()
	host.add_child(td)
	var tick: CheckBox = td.get("_remove")
	var why: Label = td.get("_remove_why")
	if tick == null or why == null or not td.has_method("bake_hurtable"):
		ok = _chk(lines, false, "remove tick: the dock has a \"Remove it when it dies\" tick next to Add Health + Hurtbox") and ok
		td.free()
		return {"ok": ok, "lines": lines}

	var foe := _spot(host, CharacterBody2D.new(), "Goblin", Vector2(20000, 0))
	var hero := _spot(host, CharacterBody2D.new(), "Hero", Vector2(20500, 0))
	hero.add_to_group("player")
	var art := Sprite2D.new()
	hero.add_child(art)
	var yard := _spot(host, Node2D.new(), "Yard", Vector2(21000, 0))
	var guest := Node2D.new()
	guest.add_to_group("player")
	yard.add_child(guest)

	ok = _chk(lines, tick.button_pressed and not why.visible, "remove tick: ticked when the dock opens") and ok
	td.refresh_remove_tick(foe)
	ok = _chk(lines, tick.button_pressed and not why.visible, "remove tick: ticked for an enemy") and ok
	td.refresh_remove_tick(hero)
	ok = _chk(lines, not tick.button_pressed and why.visible and why.text.contains("your player"),
		"remove tick: unticked for the node in the player group, and it says why [%s]" % why.text) and ok
	td.refresh_remove_tick(art)
	ok = _chk(lines, not tick.button_pressed and why.visible, "remove tick: unticked for part of the player (its picture)") and ok
	td.refresh_remove_tick(yard)
	ok = _chk(lines, not tick.button_pressed and why.text.contains("inside it"),
		"remove tick: unticked for a node with the player inside it [%s]" % why.text) and ok
	td.refresh_remove_tick(null)
	ok = _chk(lines, tick.button_pressed and not why.visible, "remove tick: ticked when nothing is selected") and ok

	td.refresh_remove_tick(foe)
	var said: String = td.bake_hurtable(foe)
	var fh: Array[Node] = _healths(foe)
	ok = _chk(lines, fh.size() == 1 and fh[0].get("remove_on_death") == true and said.contains("It disappears when its health runs out."),
		"remove tick: Add Health + Hurtbox on an enemy switches its Health's Remove On Death on, and says so [%s]" % said) and ok
	tick.button_pressed = false            # a click on the tick
	said = td.bake_hurtable(foe)
	fh = _healths(foe)
	ok = _chk(lines, fh.size() == 1 and fh[0].get("remove_on_death") == false and said.contains("already had Health") and said.contains("It stays in the game"),
		"remove tick: unticked and clicked again, the same Health gets it off, with no second Health [%s]" % said) and ok
	td.refresh_remove_tick(hero)
	said = td.bake_hurtable(hero)
	var hh: Array[Node] = _healths(hero)
	ok = _chk(lines, hh.size() == 1 and hh[0].get("remove_on_death") == false and said.contains("It stays in the game"),
		"remove tick: Add Health + Hurtbox on the player leaves it off [%s]" % said) and ok
	tick.button_pressed = true             # the buyer wants it anyway
	td.bake_hurtable(hero)
	ok = _chk(lines, hh.size() == 1 and hh[0].get("remove_on_death") == true, "remove tick: ticked by hand for the player, the click wins") and ok

	# picked first and made the player after (Controller's Make Player, say): the
	# button works it out again
	var late := _spot(host, CharacterBody2D.new(), "Late", Vector2(21500, 0))
	td.refresh_remove_tick(late)
	late.add_to_group("player")
	td.bake_hurtable(late)
	var lh: Array[Node] = _healths(late)
	ok = _chk(lines, lh.size() == 1 and lh[0].get("remove_on_death") == false and not tick.button_pressed and why.visible,
		"remove tick: a node that became the player after it was selected still gets it off") and ok

	# played: made with the defaults, killed, gone a frame later
	var mob := _spot(host, CharacterBody2D.new(), "Mob", Vector2(22000, 0))
	td.refresh_remove_tick(mob)
	td.bake_hurtable(mob)
	var mh: Array[Node] = _healths(mob)
	if mh.size() == 1:
		mh[0].call("take_damage", 99999.0)
	await tree.process_frame
	ok = _chk(lines, not is_instance_valid(mob), "remove tick, played: an enemy made with the defaults is gone a frame after its health runs out") and ok
	if is_instance_valid(mob):
		mob.free()

	for n in [foe, hero, yard, late]:
		if is_instance_valid(n):
			n.free()
	td.free()
	return {"ok": ok, "lines": lines}


static func _spot(host: Node, n: Node2D, n_name: String, at: Vector2) -> Node2D:
	n.name = n_name
	n.position = at
	host.add_child(n)
	return n


static func _healths(n: Node) -> Array[Node]:
	var out: Array[Node] = []
	for c in n.get_children():
		if c is HealthLite:
			out.append(c)
	return out


# A player in group "player" with Health + a player side hurtbox (and a body
# body_w wide, if asked), and an enemy 130 px away with an 18x18 body, an enemy
# side hitbox and a stand-in Enemy AI brain from `brain_script` (null: none). A
# null hurt shape leaves the hurtbox out.
static func _reach_rig(host: Node, at: Vector2, hit_shape: Shape2D, hurt_shape: Shape2D, brain_script: Script, body_w := 0.0) -> Dictionary:
	var root := Node2D.new()
	root.position = at
	host.add_child(root)
	var player := CharacterBody2D.new()
	player.add_to_group("player")
	if body_w > 0.0:
		player.add_child(_shape(_rect(body_w, body_w)))
	var hp := HealthLite.new()
	player.add_child(hp)
	if hurt_shape != null:
		var hurt := HurtboxLite.new()
		hurt.team = DOCK.TEAM_PLAYER
		hurt.add_child(_shape(hurt_shape))
		player.add_child(hurt)
	root.add_child(player)
	var enemy := CharacterBody2D.new()
	enemy.position = Vector2(130, 0)
	enemy.add_child(_shape(_rect(18, 18)))
	var hit := HitboxLite.new()
	hit.name = "HitboxLite"
	hit.team = DOCK.TEAM_ENEMY
	hit.add_child(_shape(hit_shape))
	enemy.add_child(hit)
	var brain: Node = null
	if brain_script != null:
		brain = brain_script.new()
		enemy.add_child(brain)
	root.add_child(enemy)
	return {"root": root, "enemy": enemy, "hit": hit, "hp": hp, "brain": brain}


static func _radius(rig: Dictionary) -> float:
	return float(rig["brain"].attack_radius)


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


static func _ids(o: OptionButton) -> Array:
	var out: Array = []
	for i in o.item_count:
		out.append(o.get_item_id(i))
	return out


static func _add_shape(area: Node) -> void:
	var rect := RectangleShape2D.new()
	rect.size = Vector2(32, 32)
	var cs := CollisionShape2D.new()
	cs.shape = rect
	area.add_child(cs)


static func _chk(lines: Array[String], cond: bool, label: String) -> bool:
	lines.append(("[ok] " if cond else "[XX] ") + label)
	return cond
