extends Node

# Headless engine check for Controller — Lite.
#   ~/.local/bin/godot --headless --path lite/controller res://tools/controller_lite/verify.tscn

const CHECKS := preload("res://tools/controller_lite/controller_checks.gd")


func _ready() -> void:
	var r: Dictionary = CHECKS.run(self)
	var lines: Array = r["lines"]
	var ok: bool = r["ok"]
	var rp: Dictionary = await CHECKS.run_physics(self)
	lines.append_array(rp["lines"])
	ok = ok and rp["ok"]
	for l in lines:
		print("  ", l)
	print("=== ", "PASS" if ok else "FAIL", " ===")
	get_tree().quit(0 if ok else 1)
