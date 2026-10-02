extends Node

# Headless engine check for Dialogue (Lite), plus the Setup chooser's wiring and
# the authoring dock's node ids.
#   ~/.local/bin/godot --headless --path lite/dialogue res://tools/dialogue_lite/verify.tscn

const CHECKS := preload("res://tools/dialogue_lite/dialogue_checks.gd")
const CHOOSER_CHECKS := preload("res://tools/dialogue_lite/verify_chooser.gd")
const DOCK_CHECKS := preload("res://tools/dialogue_lite/dock_checks.gd")


func _ready() -> void:
	var r: Dictionary = CHECKS.run(self)
	var lines: Array = r["lines"]
	var ok: bool = r["ok"]
	var rc: Dictionary = await CHOOSER_CHECKS.run(self)
	lines.append_array(rc["lines"])
	ok = ok and rc["ok"]
	var rd: Dictionary = DOCK_CHECKS.run(self)
	lines.append_array(rd["lines"])
	ok = ok and rd["ok"]
	for l in lines:
		print("  ", l)
	print("=== ", "PASS" if ok else "FAIL", " ===")
	get_tree().quit(0 if ok else 1)
