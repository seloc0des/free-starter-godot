class_name SceneMusicLite
extends Node

# Level music with no code: plays its track through the AudioLite deck as soon
# as the scene starts, crossfading from whatever the last scene left playing.
# The Audio Lite dock puts one on the scene root ("Play it when the scene starts").

## The track. Import it with Loop on (Import dock) so it keeps going.
@export var music: AudioStream
## Seconds to fade it in.
@export var fade := 1.0


func _ready() -> void:
	if music == null:
		push_warning("SceneMusicLite '%s': no track picked. Drag one onto its Music field, or use \"Play it when the scene starts\" in the Audio Lite dock." % name)
		return
	var audio := get_node_or_null(^"/root/AudioLite")
	if audio == null:
		push_warning("SceneMusicLite '%s': the AudioLite autoload isn't running. Turn on Audio (Lite) in Project Settings > Plugins." % name)
		return
	# same track as the last scene is a no-op in the deck, so it doesn't restart
	audio.play_music(music, fade)
