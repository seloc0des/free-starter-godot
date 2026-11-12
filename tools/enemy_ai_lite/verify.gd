extends Node

# Headless engine check for Enemy AI — Lite.
#   ~/.local/bin/godot --headless --path lite/enemy-ai res://tools/enemy_ai_lite/verify.tscn

const CHECKS := preload("res://tools/enemy_ai_lite/enemy_checks.gd")
const CHECKS_3D := preload("res://tools/enemy_ai_lite/enemy_checks_3d.gd")
const DOCK_CHECKS := preload("res://tools/enemy_ai_lite/dock_checks.gd")


func _ready() -> void:
	var r: Dictionary = CHECKS.run(self)
	var lines: Array = r["lines"]
	var ok: bool = r["ok"]
	var rp: Dictionary = await CHECKS.run_physics(self)
	lines.append_array(rp["lines"])
	ok = ok and rp["ok"]
	var r3: Dictionary = CHECKS_3D.run(self)
	lines.append_array(r3["lines"])
	ok = ok and r3["ok"]
	var rp3: Dictionary = await CHECKS_3D.run_physics(self)
	lines.append_array(rp3["lines"])
	ok = ok and rp3["ok"]
	var rd: Dictionary = await DOCK_CHECKS.run(self)
	lines.append_array(rd["lines"])
	ok = ok and rd["ok"]
	for l in lines:
		print("  ", l)
	print("=== ", "PASS" if ok else "FAIL", " ===")
	get_tree().quit(0 if ok else 1)
