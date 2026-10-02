extends Node

# Headless engine check for Combat — Lite.
#   ~/.local/bin/godot --headless --path lite/combat res://tools/combat_lite/verify.tscn

const CHECKS := preload("res://tools/combat_lite/combat_checks.gd")
const DOCK_CHECKS := preload("res://tools/combat_lite/dock_checks.gd")


func _ready() -> void:
	var r: Dictionary = CHECKS.run(self)
	var lines: Array = r["lines"]
	var ok: bool = r["ok"]
	var rr: Dictionary = await CHECKS.run_death(self)
	lines.append_array(rr["lines"])
	ok = ok and rr["ok"]
	var rf: Dictionary = await CHECKS.run_flash(self)
	lines.append_array(rf["lines"])
	ok = ok and rf["ok"]
	var rd: Dictionary = await DOCK_CHECKS.run(self)
	lines.append_array(rd["lines"])
	ok = ok and rd["ok"]
	for l in lines:
		print("  ", l)
	print("=== ", "PASS" if ok else "FAIL", " ===")
	get_tree().quit(0 if ok else 1)
