extends Control

const DEMO := preload("res://tools/dialogue_lite/demo/demo_dialogue.gd")


func _ready() -> void:
	DialoguesLite.register(DEMO.healer_intro())
	DialoguesLite.event_fired.connect(func(e: String) -> void: print("[demo] event fired: ", e))


func _on_talk_pressed() -> void:
	if not DialoguesLite.is_active():
		DialoguesLite.start("healer_intro")
