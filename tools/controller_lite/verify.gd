extends Node

# Headless engine check for Controller — Lite.
#   ~/.local/bin/godot --headless --path lite/controller res://tools/controller_lite/verify.tscn

const CHECKS := preload("res://tools/controller_lite/controller_checks.gd")
const DOCK_CHECKS := preload("res://tools/controller_lite/dock_checks.gd")
const CHECKS_3D := preload("res://tools/controller_lite/controller_checks_3d.gd")


func _ready() -> void:
	var r: Dictionary = CHECKS.run(self)
	var lines: Array = r["lines"]
	var ok: bool = r["ok"]
	var rp: Dictionary = await CHECKS.run_physics(self)
	lines.append_array(rp["lines"])
	ok = ok and rp["ok"]
	var ri: Dictionary = await CHECKS.run_interaction(self)
	lines.append_array(ri["lines"])
	ok = ok and ri["ok"]
	var r3: Dictionary = CHECKS_3D.run(self)
	lines.append_array(r3["lines"])
	ok = ok and r3["ok"]
	var r3p: Dictionary = await CHECKS_3D.run_physics(self)
	lines.append_array(r3p["lines"])
	ok = ok and r3p["ok"]
	var rd: Dictionary = DOCK_CHECKS.run(self)
	lines.append_array(rd["lines"])
	ok = ok and rd["ok"]
	var rdp: Dictionary = await DOCK_CHECKS.run_played(self)
	lines.append_array(rdp["lines"])
	ok = ok and rdp["ok"]
	for l in lines:
		print("  ", l)
	print("=== ", "PASS" if ok else "FAIL", " ===")
	get_tree().quit(0 if ok else 1)
