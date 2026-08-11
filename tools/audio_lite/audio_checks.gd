extends RefCounted

# Shared checks for Audio — Lite. Streams are generated in code
# (AudioStreamWAV sine data) so the pack ships no audio assets. Works headless:
# player/volume state is engine-side.

static func run(host: Node) -> Dictionary:
	var lines: Array[String] = []
	var ok := true

	# --- buses ---
	ok = _chk(lines, AudioServer.get_bus_index("Music") >= 0, "Music bus exists") and ok
	ok = _chk(lines, AudioServer.get_bus_index("SFX") >= 0, "SFX bus exists") and ok
	var count := AudioServer.bus_count
	AudioLite._ensure_buses()
	ok = _chk(lines, AudioServer.bus_count == count, "re-ensuring buses adds no duplicates") and ok
	AudioLite.set_bus_volume("Music", 0.5)
	ok = _chk(lines, absf(AudioLite.get_bus_volume("Music") - 0.5) < 0.01, "bus volume set/get roundtrip") and ok
	AudioLite.set_bus_volume("Music", 1.0)

	# --- sfx pool ---
	ok = _chk(lines, AudioLite.play_sfx(null) == null, "null sfx is a safe no-op") and ok
	var blip := _tone(880)
	var p: AudioStreamPlayer = AudioLite.play_sfx(blip)
	ok = _chk(lines, p != null and p.playing and p.bus == "SFX", "play_sfx: pooled player fires on the SFX bus") and ok
	var jittered: AudioStreamPlayer = AudioLite.play_sfx(blip, 0.0, 1.0, 0.3)
	ok = _chk(lines, jittered.pitch_scale >= 0.7 and jittered.pitch_scale <= 1.3, "pitch jitter stays in range") and ok
	for i in 16:
		AudioLite.play_sfx(blip)
	ok = _chk(lines, AudioLite._sfx_pool.size() == AudioLite.max_sfx_players, "pool caps at max_sfx_players") and ok

	# --- music immediate state ---
	var track_a := _tone(220)
	var track_b := _tone(330)
	var changes := {"n": 0}
	var on_music := func(_s: AudioStream) -> void: changes["n"] += 1
	AudioLite.music_changed.connect(on_music)
	AudioLite.play_music(track_a, 0.05)
	ok = _chk(lines, AudioLite.music_playing() == track_a, "play_music: track A is the active track") and ok
	AudioLite.play_music(track_a, 0.05)
	ok = _chk(lines, changes["n"] == 1, "same track again is a no-op") and ok
	AudioLite.music_changed.disconnect(on_music)
	host.set_meta("track_a", track_a)
	host.set_meta("track_b", track_b)

	return {"ok": ok, "lines": lines}


static func run_async(host: Node) -> Dictionary:
	var lines: Array[String] = []
	var ok := true
	var tree: SceneTree = host.get_tree()
	var track_a: AudioStream = host.get_meta("track_a")
	var track_b: AudioStream = host.get_meta("track_b")

	# --- crossfade ---
	AudioLite.play_music(track_b, 0.05)
	await _wait(tree, 0.3)
	ok = _chk(lines, AudioLite.music_playing() == track_b, "crossfade: B is now the active track") and ok
	ok = _chk(lines, AudioLite._active_music.volume_db > -3.0, "crossfade: B faded up to full") and ok
	var other: AudioStreamPlayer = AudioLite._music_a if AudioLite._active_music == AudioLite._music_b else AudioLite._music_b
	ok = _chk(lines, not other.playing, "crossfade: A faded out and stopped") and ok
	AudioLite.stop_music(0.05)
	await _wait(tree, 0.3)
	ok = _chk(lines, AudioLite.music_playing() == null, "stop_music silences the deck") and ok

	# --- rapid re-crossfade: the comeback track must survive the old fade's stop ---
	AudioLite.play_music(track_a, 0.1)
	AudioLite.play_music(track_b, 0.3)
	AudioLite.play_music(track_a, 0.05)
	await _wait(tree, 0.5)
	ok = _chk(lines, AudioLite.music_playing() == track_a and AudioLite._active_music.playing, "rapid re-crossfade keeps the comeback track alive") and ok

	# --- audio zone: enter swaps, exit restores ---
	var zone := AudioZoneLite.new()
	zone.music = track_b
	zone.fade = 0.05
	host.add_child(zone)
	var body := CharacterBody2D.new()
	body.add_to_group("player")
	host.add_child(body)
	zone._on_body_entered(body)
	ok = _chk(lines, AudioLite.music_playing() == track_b, "walking into a zone swaps the music") and ok
	await _wait(tree, 0.2)
	zone._on_body_exited(body)
	ok = _chk(lines, AudioLite.music_playing() == track_a, "walking out restores what played before") and ok
	zone.queue_free()
	body.queue_free()

	AudioLite.stop_music(0.05)
	return {"ok": ok, "lines": lines}


# ---- helpers -------------------------------------------------------------

static func _tone(freq: int) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = 8000
	var frames := 1600
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		data.encode_s16(i * 2, int(sin(TAU * freq * i / 8000.0) * 8000.0))
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = frames
	return s


static func _wait(tree: SceneTree, seconds: float) -> void:
	await tree.create_timer(seconds, true, false, true).timeout
	await tree.process_frame


static func _chk(lines: Array[String], cond: bool, label: String) -> bool:
	lines.append(("[ok] " if cond else "[XX] ") + label)
	return cond
