extends RefCounted

# The Audio Lite dock's outcomes, built the way its buttons build them (the
# headless wire_* half), packed into a scene, loaded back and played: music for
# the scene, a sound when the player touches something, zones in 2D and 3D.
# Bodies walk in through real physics, nothing calls a signal by hand. The
# buttons themselves need the editor, so the journey probe clicks those.

const DOCK := preload("res://addons/audio_lite/editor/audio_chooser_dock.gd")
const CHECKS := preload("res://tools/audio_lite/audio_checks.gd")
const SCENE_MUSIC := preload("res://addons/audio_lite/scene_music_lite.gd")
const TOUCH_SOUND := preload("res://addons/audio_lite/sound_on_touch_lite.gd")
const ZONE := preload("res://addons/audio_lite/zone_lite.gd")
const ZONE_3D := preload("res://addons/audio_lite/zone_lite_3d.gd")


static func run(host: Node) -> Dictionary:
	var lines: Array[String] = []
	var ok := true
	var dock: Control = DOCK.new()  # never enters the tree, only its wire_* half runs
	_quiet()
	ok = await _scene_music(host, dock, lines) and ok
	ok = await _touch_sound(host, dock, lines) and ok
	ok = await _zones(host, dock, lines) and ok
	ok = await _odd_setups(host, lines) and ok
	_quiet()
	_audio_lite().stop_music(0.0)
	dock.free()
	return {"ok": ok, "lines": lines}


# ---- music for this scene ------------------------------------------------

static func _scene_music(host: Node, dock: Control, lines: Array[String]) -> bool:
	var ok := true
	var tree := host.get_tree()
	var town: AudioStream = CHECKS._tone(262)
	var forest: AudioStream = CHECKS._tone(294)

	var level := Node2D.new()
	level.name = "Level"
	var m: Node = dock.wire_scene_music(level, town)
	ok = _chk(lines, m.get_script() == SCENE_MUSIC and m.name == "SceneMusic" and m.get_parent() == level and m.owner == level,
		"scene music: the dock puts a SceneMusic on the scene root, saved with the scene") and ok
	var m2: Node = dock.wire_scene_music(level, forest)
	ok = _chk(lines, m2 == m and m.name == "SceneMusic" and m.get("music") == forest and _count(level, SCENE_MUSIC) == 1,
		"scene music: pressing again swaps the track on the same node, no SceneMusic2") and ok

	_audio_lite().stop_music(0.0)
	var copy := _reload(level)
	host.add_child(copy)
	ok = _chk(lines, _audio_lite().music_playing() == forest, "scene music: loading the saved scene starts its track") and ok
	await CHECKS._wait(tree, 0.3)
	ok = _chk(lines, _audio_lite().music_playing() == forest and _audio_lite()._active_music.volume_db > -60.0,
		"scene music: still playing a moment later, fading in") and ok

	# the next level crossfades to its own track; one with the same track leaves it be
	var changes := {"n": 0}
	var on_change := func(_s: AudioStream) -> void: changes["n"] += 1
	_audio_lite().music_changed.connect(on_change)
	copy.queue_free()
	var next := Node2D.new()
	dock.wire_scene_music(next, town)
	var next_copy := _reload(next)
	host.add_child(next_copy)
	ok = _chk(lines, _audio_lite().music_playing() == town and changes["n"] == 1,
		"scene music: the next scene's track crossfades over the last one") and ok
	next_copy.queue_free()
	var same := Node2D.new()
	dock.wire_scene_music(same, town)
	var same_copy := _reload(same)
	host.add_child(same_copy)
	ok = _chk(lines, _audio_lite().music_playing() == town and changes["n"] == 1,
		"scene music: a scene with the same track keeps it going, no restart") and ok
	_audio_lite().music_changed.disconnect(on_change)
	same_copy.queue_free()

	# control: without one, loading a scene leaves the deck silent
	_audio_lite().stop_music(0.0)
	var empty := Node2D.new()
	var bare := _reload(empty)
	host.add_child(bare)
	ok = _chk(lines, _audio_lite().music_playing() == null, "control: a scene without SceneMusic starts no music") and ok
	bare.queue_free()

	# the status line's Loop tip: a track that ends gets it, a looping one doesn't
	var once := AudioStreamWAV.new()
	var ogg := AudioStreamOggVorbis.new()
	var ogg_loop := AudioStreamOggVorbis.new()
	ogg_loop.loop = true
	ok = _chk(lines, dock.loops(town) and not dock.loops(once) and not dock.loops(ogg) and dock.loops(ogg_loop)
		and dock.loops(AudioStreamRandomizer.new()),
		"scene music: the dock tells a looping track from one that plays once") and ok
	for n in [level, next, same, empty]:
		n.free()
	await tree.process_frame
	return ok


# ---- a sound when the player touches this --------------------------------

static func _touch_sound(host: Node, dock: Control, lines: Array[String]) -> bool:
	var ok := true
	var tree := host.get_tree()
	var ding: AudioStream = CHECKS._tone(988)
	var chime: AudioStream = CHECKS._tone(1319)

	var room := Node2D.new()
	room.name = "Room"
	var sign_post: Node = _own(room, room, Node2D.new(), "Sign", Vector2(5000, 5000))
	var t: Node = dock.wire_touch_sound(room, sign_post, chime)
	var area := sign_post.get_node_or_null("SoundArea")
	ok = _chk(lines, area is Area2D and _shape_of(area) is CircleShape2D and area.owner == room
		and t.get_parent() == area and t.name == "SoundOnTouch" and t.owner == room and t.get_script() == TOUCH_SOUND,
		"touch sound: a plain 2D node gets a SoundArea (a circle) with a SoundOnTouch in it") and ok
	var t2: Node = dock.wire_touch_sound(room, sign_post, ding)
	ok = _chk(lines, t2 == t and t.get("sound") == ding and _count(room, TOUCH_SOUND) == 1 and sign_post.get_child_count() == 1,
		"touch sound: pressing again swaps the sound, no second SoundOnTouch or SoundArea") and ok

	# an area the buyer already shaped is used as it is
	var chest: Node = _own(room, room, Area2D.new(), "Chest", Vector2(6000, 5000))
	var box := CollisionShape2D.new()
	box.shape = RectangleShape2D.new()
	_own(room, chest, box, "Box", Vector2.ZERO)
	var tc: Node = dock.wire_touch_sound(room, chest, ding)
	ok = _chk(lines, tc.get_parent() == chest and chest.get_node_or_null("SoundArea") == null,
		"touch sound: an Area2D with a shape takes the SoundOnTouch itself") and ok
	var shapeless: Node = _own(room, room, Area2D.new(), "Shapeless", Vector2(7000, 5000))
	var ts: Node = dock.wire_touch_sound(room, shapeless, ding)
	var inner := shapeless.get_node_or_null("SoundArea")
	ok = _chk(lines, inner is Area2D and ts.get_parent() == inner and _shape_of(inner) is CircleShape2D,
		"touch sound: an Area2D with no shape gets a SoundArea to be touched through") and ok

	# played: the saved scene, bodies walking in through physics
	_quiet()
	var copy := _reload(room)
	host.add_child(copy)
	var stranger := _walker_2d(Vector2(5000, 4000), false)
	var hero := _walker_2d(Vector2(5000, 4200), true)
	copy.add_child(stranger)
	copy.add_child(hero)
	await _frames(tree, 3)
	stranger.global_position = Vector2(5000, 5000)
	await _frames(tree, 6)
	ok = _chk(lines, _plays(ding) == 0, "touch sound: a body not in the player group walking in stays quiet") and ok
	hero.global_position = Vector2(5000, 5000)
	await _frames(tree, 6)
	ok = _chk(lines, _plays(ding) == 1, "touch sound: the player walking in plays it (%d)" % _plays(ding)) and ok
	await _frames(tree, 20)
	ok = _chk(lines, _plays(ding) == 1, "touch sound: standing inside doesn't repeat it") and ok
	hero.global_position = Vector2(5000, 4200)
	await _frames(tree, 6)
	hero.global_position = Vector2(5000, 5000)
	await _frames(tree, 6)
	ok = _chk(lines, _plays(ding) == 2, "touch sound: walking out and back in plays it once more (%d)" % _plays(ding)) and ok
	ok = _chk(lines, _pool_bus_ok(ding), "touch sound: it plays through the AudioLite pool on the SFX bus") and ok

	copy.queue_free()
	room.free()
	await tree.process_frame
	return ok


# ---- zones: a circle in 2D, a sphere in 3D --------------------------------

static func _zones(host: Node, dock: Control, lines: Array[String]) -> bool:
	var ok := true
	var tree := host.get_tree()
	var calm: AudioStream = CHECKS._tone(196)
	var cave: AudioStream = CHECKS._tone(147)
	var drip: AudioStream = CHECKS._tone(1760)

	var flat := Node2D.new()
	var spot: Node = _own(flat, flat, Node2D.new(), "Spot", Vector2(10, 10))
	var z2: Node = dock.wire_zone(flat, spot, cave)
	ok = _chk(lines, z2 is Area2D and z2.get_script() == ZONE and z2.name == "AudioZone" and _shape_of(z2) is CircleShape2D
		and z2.get("music") == cave and z2.owner == flat,
		"2D: Add Audio Zone in a 2D scene makes an Area2D zone with a circle and the picked track") and ok
	flat.free()

	var level := Node3D.new()
	level.name = "Level3D"
	var crate: Node = _own(level, level, Node3D.new(), "Crate", Vector3(300, 0, 300))
	var z: Node = dock.wire_zone(level, crate, cave)
	ok = _chk(lines, z is Area3D and z.get_script() == ZONE_3D and z.name == "AudioZone3D" and _shape_of(z) is SphereShape3D
		and z.owner == level and _shape_owner(z) == level,
		"3D: Add Audio Zone in a 3D scene makes an Area3D zone with a sphere") and ok
	var t: Node = dock.wire_touch_sound(level, crate, drip)
	var area := crate.get_node_or_null("SoundArea")
	ok = _chk(lines, area is Area3D and _shape_of(area) is SphereShape3D and t.get_parent() == area,
		"3D: a sound on touch in a 3D scene gets a SoundArea (an Area3D sphere)") and ok
	# a plain Node has no position of its own, so the level decides
	var holder: Node = _own(level, level, Node.new(), "Holder", null)
	var zh: Node = dock.wire_zone(level, holder, cave)
	ok = _chk(lines, zh is Area3D and zh.get_script() == ZONE_3D, "3D: a plain Node picked in a 3D level still gets a 3D zone") and ok
	# the picked node's own kind comes first: a 3D world under a plain Node root is
	# 3D, a 2D overlay inside a 3D level is 2D
	var main := Node.new()
	var world: Node = _own(main, main, Node3D.new(), "World", Vector3.ZERO)
	var overlay: Node = _own(level, level, Node2D.new(), "Overlay", Vector2.ZERO)
	ok = _chk(lines, dock.wire_zone(main, world, cave) is Area3D and dock.wire_zone(level, overlay, cave) is Area2D,
		"zones: the selected node's own kind wins over the scene root's") and ok
	main.free()
	level.remove_child(overlay)
	overlay.free()
	# a zone that's selected itself takes the new track instead of growing a zone inside it
	var again: Node = dock.wire_zone(level, z, calm)
	ok = _chk(lines, again == z and z.get("music") == calm and _count(z, ZONE_3D) == 1,
		"zones: adding on a selected zone swaps its track, no zone inside a zone") and ok
	z.set("music", cave)
	dock.wire_scene_music(level, calm)

	# played: the saved level, a 3D player walking through
	_audio_lite().stop_music(0.0)
	_quiet()
	var copy := _reload(level)
	host.add_child(copy)
	ok = _chk(lines, _audio_lite().music_playing() == calm, "3D: the level's SceneMusic starts on load") and ok
	var ghost := _walker_3d(Vector3(300, 0, 280), false)
	var hero := _walker_3d(Vector3(300, 0, 270), true)
	copy.add_child(ghost)
	copy.add_child(hero)
	await _frames(tree, 3)
	ghost.global_position = Vector3(300, 0, 300)
	await _frames(tree, 6)
	ok = _chk(lines, _audio_lite().music_playing() == calm and _plays(drip) == 0,
		"3D: a body not in the player group walking in changes nothing") and ok
	hero.global_position = Vector3(300, 0, 300)
	await _frames(tree, 6)
	ok = _chk(lines, _audio_lite().music_playing() == cave, "3D: the player walking into the zone swaps the music") and ok
	ok = _chk(lines, _plays(drip) == 1, "3D: and the SoundArea around the crate plays its sound once (%d)" % _plays(drip)) and ok
	hero.global_position = Vector3(300, 0, 270)
	await _frames(tree, 6)
	ok = _chk(lines, _audio_lite().music_playing() == calm, "3D: walking out brings the level's music back") and ok
	copy.queue_free()
	level.free()
	await tree.process_frame

	# control: the Area2D zone the dock used to add everywhere never hears a 3D player
	var old_level := Node3D.new()
	var old_zone := Area2D.new()
	old_zone.set_script(ZONE)
	old_zone.set("music", cave)
	var big := CircleShape2D.new()
	big.radius = 100000.0
	var col := CollisionShape2D.new()
	col.shape = big
	old_zone.add_child(col)
	old_level.add_child(old_zone)
	host.add_child(old_level)
	_audio_lite().play_music(calm, 0.0)
	var walker := _walker_3d(Vector3(0, 0, 0), true)
	old_level.add_child(walker)
	await _frames(tree, 6)
	ok = _chk(lines, _audio_lite().music_playing() == calm, "control: an Area2D zone in a 3D level stays silent for a 3D player") and ok
	old_level.queue_free()
	await tree.process_frame
	return ok


# ---- setups a buyer can end up with by hand -------------------------------

static func _odd_setups(host: Node, lines: Array[String]) -> bool:
	var ok := true
	var tree := host.get_tree()
	var tick: AudioStream = CHECKS._tone(700)
	_quiet()
	_audio_lite().stop_music(0.0)
	var room := Node2D.new()
	host.add_child(room)
	# no track: warns, leaves the music alone
	var m := Node.new()
	m.name = "SceneMusic"
	m.set_script(SCENE_MUSIC)
	room.add_child(m)
	# nothing to touch: warns, never plays
	var loose := Node2D.new()
	loose.position = Vector2(-5000, 5000)
	room.add_child(loose)
	var t_loose := Node.new()
	t_loose.name = "LooseSound"
	t_loose.set_script(TOUCH_SOUND)
	t_loose.set("sound", tick)
	loose.add_child(t_loose)
	# a sound dropped in after the scene started still plays
	var area := Area2D.new()
	area.position = Vector2(-6000, 5000)
	var circle := CircleShape2D.new()
	circle.radius = 40.0
	var col := CollisionShape2D.new()
	col.shape = circle
	area.add_child(col)
	var late := Node.new()
	late.name = "LateSound"
	late.set_script(TOUCH_SOUND)
	area.add_child(late)
	room.add_child(area)
	late.set("sound", tick)
	var hero := _walker_2d(Vector2(-5000, 5000), true)
	room.add_child(hero)
	await _frames(tree, 6)
	ok = _chk(lines, _audio_lite().music_playing() == null and _plays(tick) == 0,
		"odd setups: a SceneMusic with no track and a SoundOnTouch with nothing to touch stay quiet") and ok
	hero.global_position = Vector2(-6000, 5000)
	await _frames(tree, 6)
	ok = _chk(lines, _plays(tick) == 1, "odd setups: a sound given to a SoundOnTouch after the scene started plays") and ok
	room.queue_free()
	await tree.process_frame
	return ok


# ---- helpers -------------------------------------------------------------

# the saved-and-reopened copy of a scene, like pressing Play on it
static func _reload(root: Node) -> Node:
	var ps := PackedScene.new()
	ps.pack(root)
	return ps.instantiate()


static func _own(root: Node, parent: Node, n: Node, n_name: String, at: Variant) -> Node:
	n.name = n_name
	if at is Vector2:
		(n as Node2D).position = at
	elif at is Vector3:
		(n as Node3D).position = at
	parent.add_child(n)
	n.owner = root
	return n


static func _shape_of(area: Node) -> Resource:
	if area == null:
		return null
	for c in area.get_children():
		if c is CollisionShape2D or c is CollisionShape3D:
			return c.get("shape")
	return null


static func _shape_owner(area: Node) -> Node:
	for c in area.get_children():
		if c is CollisionShape2D or c is CollisionShape3D:
			return c.owner
	return null


static func _count(root: Node, script: Script) -> int:
	var n := 1 if root.get_script() == script else 0
	for c in root.get_children():
		n += _count(c, script)
	return n


static func _walker_2d(at: Vector2, is_player: bool) -> CharacterBody2D:
	var body := CharacterBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16, 16)
	shape.shape = rect
	body.add_child(shape)
	body.position = at
	if is_player:
		body.add_to_group("player")
	return body


static func _walker_3d(at: Vector3, is_player: bool) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var ball := SphereShape3D.new()
	ball.radius = 0.5
	shape.shape = ball
	body.add_child(shape)
	body.position = at
	if is_player:
		body.add_to_group("player")
	return body


# how many pool players are playing this sound right now
static func _plays(stream: AudioStream) -> int:
	var n := 0
	for p in _audio_lite()._sfx_pool:
		if p.stream == stream and p.playing:
			n += 1
	return n


static func _pool_bus_ok(stream: AudioStream) -> bool:
	for p in _audio_lite()._sfx_pool:
		if p.stream == stream and p.playing:
			return p.bus == "SFX"
	return false


# the pool checks before this leave every SFX player looping, which would hide a play
static func _quiet() -> void:
	for p in _audio_lite()._sfx_pool:
		p.stop()


static func _frames(tree: SceneTree, n: int) -> void:
	for i in n:
		await tree.physics_frame


static func _chk(lines: Array[String], cond: bool, label: String) -> bool:
	lines.append(("[ok] " if cond else "[XX] ") + label)
	return cond


# AudioLite is looked up when used instead of named. A script that names an autoload
# won't compile until the plugin that adds it is switched on, so a fresh install
# printed parse errors.
const AUDIO_LITE := preload("res://addons/audio_lite/audio_lite.gd")


static func _audio_lite() -> AUDIO_LITE:
	return (Engine.get_main_loop() as SceneTree).root.get_node(^"AudioLite") as AUDIO_LITE
