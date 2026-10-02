class_name SoundOnTouchLite
extends Node

# Plays a sound once each time the player walks into my parent Area2D/Area3D,
# through the AudioLite SFX pool. The Audio Lite dock drops me in, with a
# SoundArea to touch when the node had nothing.

## The sound. Short one-shots work best.
@export var sound: AudioStream
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var volume_db := 0.0
## Random pitch spread so repeats don't sound copy-pasted. 0.1 = up to 10% either way.
@export_range(0.0, 0.5, 0.01) var pitch_jitter := 0.0
## Only a body in this group sets it off.
@export var player_group: StringName = &"player"

var _audio: Node = null


func _ready() -> void:
	var area := get_parent()
	if area == null or not area.has_signal("body_entered"):
		push_warning("SoundOnTouchLite '%s': nothing to touch. Put it under an Area2D or Area3D, or add it again from the Audio Lite dock to get a SoundArea." % name)
		return
	if sound == null:
		push_warning("SoundOnTouchLite '%s': no sound picked. Drag one onto its Sound field." % name)
	_audio = get_node_or_null(^"/root/AudioLite")
	if _audio == null:
		push_warning("SoundOnTouchLite '%s': the AudioLite autoload isn't running. Turn on Audio (Lite) in Project Settings > Plugins." % name)
		return
	area.connect("body_entered", _on_body_entered)


func _on_body_entered(body: Node) -> void:
	if sound != null and body.is_in_group(player_group):
		_audio.play_sfx(sound, volume_db, 1.0, pitch_jitter)
