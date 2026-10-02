class_name AudioZoneLite
extends Area2D

# Walk-in music zone: entering swaps the music, leaving restores what played
# before (unless another zone took over meanwhile). Player-group gated.
# Pro zones also carry ambience.

signal zone_entered(by: Node)
signal zone_exited(by: Node)

@export var music: AudioStream
@export var fade := 1.5
@export var player_group: StringName = &"player"

var _prev_music: AudioStream = null


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group(player_group):
		return
	if music != null:
		_prev_music = _audio_lite().music_playing()
		_audio_lite().play_music(music, fade)
	zone_entered.emit(body)


func _on_body_exited(body: Node) -> void:
	if not body.is_in_group(player_group):
		return
	# only restore if we still own the music
	if music != null and _audio_lite().music_playing() == music:
		if _prev_music != null:
			_audio_lite().play_music(_prev_music, fade)
		else:
			_audio_lite().stop_music(fade)
	zone_exited.emit(body)


# AudioLite is looked up when used instead of named. A script that names an autoload
# won't compile until the plugin that adds it is switched on, so a fresh install
# printed parse errors.
const AUDIO_LITE := preload("res://addons/audio_lite/audio_lite.gd")


static func _audio_lite() -> AUDIO_LITE:
	return (Engine.get_main_loop() as SceneTree).root.get_node(^"AudioLite") as AUDIO_LITE
