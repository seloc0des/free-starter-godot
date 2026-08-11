extends Node

# Headless engine check for Combat — Lite.
#   ~/.local/bin/godot --headless --path lite/combat res://tools/combat_lite/verify.tscn

const CHECKS := preload("res://tools/combat_lite/combat_checks.gd")


func _ready() -> void:
	var r: Dictionary = CHECKS.run(self)
	for l in r["lines"]:
		print("  ", l)
	print("=== ", "PASS" if r["ok"] else "FAIL", " ===")
	get_tree().quit(0 if r["ok"] else 1)
