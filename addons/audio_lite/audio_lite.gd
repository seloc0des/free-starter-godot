extends Node

# AudioLite autoload: a crossfading music deck + pooled SFX on runtime-created
# Music/SFX buses. The free core of Audio (Pro adds the intensity layer,
# ambience channel, positional SFX, emitters, and pack hooks).

signal music_changed(stream: AudioStream)

const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"

@export var max_sfx_players := 12

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _active_music: AudioStreamPlayer = null
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _fades := {}                             # player -> its live fade Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # music keeps playing through pause
	_ensure_buses()
	_music_a = _make_player(BUS_MUSIC)
	_music_b = _make_player(BUS_MUSIC)


# ---- music ---------------------------------------------------------------

## Crossfade to a track. Same stream twice is a no-op.
func play_music(stream: AudioStream, fade := 1.0) -> void:
	if stream == null or stream == music_playing():
		return
	var incoming := _music_b if _active_music == _music_a else _music_a
	var outgoing := _active_music
	incoming.stream = stream
	incoming.volume_db = -60.0
	incoming.play()
	_fade_player(incoming, 0.0, fade)
	if outgoing != null:
		_fade_player(outgoing, -60.0, fade, true)
	_active_music = incoming
	music_changed.emit(stream)


func stop_music(fade := 1.0) -> void:
	if _active_music == null:
		return
	_fade_player(_active_music, -60.0, fade, true)
	_active_music = null
	music_changed.emit(null)


func music_playing() -> AudioStream:
	return _active_music.stream if _active_music != null and _active_music.playing else null


# ---- sfx -----------------------------------------------------------------

## Fire-and-forget sound. Pooled; pitch_jitter humanizes repeats.
func play_sfx(stream: AudioStream, volume_db := 0.0, pitch := 1.0, pitch_jitter := 0.0) -> AudioStreamPlayer:
	if stream == null:
		return null
	var p := _grab_sfx()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = maxf(0.05, pitch + randf_range(-pitch_jitter, pitch_jitter))
	p.play()
	return p


# ---- volumes (bus helpers) -----------------------------------------------

func set_bus_volume(bus_name: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.0001)))


func get_bus_volume(bus_name: String) -> float:
	var i := AudioServer.get_bus_index(bus_name)
	return db_to_linear(AudioServer.get_bus_volume_db(i)) if i >= 0 else 0.0


# ---- internals -----------------------------------------------------------

func _ensure_buses() -> void:
	for bus_name in [BUS_MUSIC, BUS_SFX]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var i := AudioServer.bus_count
			AudioServer.add_bus(i)
			AudioServer.set_bus_name(i, bus_name)
			AudioServer.set_bus_send(i, &"Master")


func _make_player(bus_name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus_name
	add_child(p)
	return p


func _fade_player(p: AudioStreamPlayer, to_db: float, fade: float, stop_after := false) -> void:
	# kill any in-flight fade on this player — otherwise a rapid re-crossfade
	# inherits the old fade's pending stop() and kills the comeback track
	var old: Tween = _fades.get(p)
	if old != null and old.is_valid():
		old.kill()
	if fade <= 0.0:
		p.volume_db = to_db
		if stop_after:
			p.stop()
		_fades.erase(p)
		return
	var tw := create_tween()
	_fades[p] = tw
	tw.tween_property(p, "volume_db", to_db, fade)
	if stop_after:
		tw.tween_callback(p.stop)


func _grab_sfx() -> AudioStreamPlayer:
	for p in _sfx_pool:
		if not p.playing:
			return p
	if _sfx_pool.size() < max_sfx_players:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		add_child(p)
		_sfx_pool.append(p)
		return p
	_sfx_next = (_sfx_next + 1) % _sfx_pool.size()
	return _sfx_pool[_sfx_next]                  # steal the oldest slot
