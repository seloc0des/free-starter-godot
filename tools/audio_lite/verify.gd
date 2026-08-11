extends Node

# Headless engine check for Audio — Lite.
#   ~/.local/bin/godot --headless --path lite/audio res://tools/audio_lite/verify.tscn

const CHECKS := preload("res://tools/audio_lite/audio_checks.gd")


func _ready() -> void:
	var r: Dictionary = CHECKS.run(self)
	var lines: Array = r["lines"]
	var ok: bool = r["ok"]
	var ra: Dictionary = await CHECKS.run_async(self)
	lines.append_array(ra["lines"])
	ok = ok and ra["ok"]
	for l in lines:
		print("  ", l)
	print("=== ", "PASS" if ok else "FAIL", " ===")
	get_tree().quit(0 if ok else 1)
