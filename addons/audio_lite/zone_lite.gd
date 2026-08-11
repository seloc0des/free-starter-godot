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
		_prev_music = AudioLite.music_playing()
		AudioLite.play_music(music, fade)
	zone_entered.emit(body)


func _on_body_exited(body: Node) -> void:
	if not body.is_in_group(player_group):
		return
	# only restore if we still own the music
	if music != null and AudioLite.music_playing() == music:
		if _prev_music != null:
			AudioLite.play_music(_prev_music, fade)
		else:
			AudioLite.stop_music(fade)
	zone_exited.emit(body)
