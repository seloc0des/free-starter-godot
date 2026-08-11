extends Node

# Headless engine check for Dialogue — Lite.
#   ~/.local/bin/godot --headless --path lite/dialogue res://tools/dialogue_lite/verify.tscn

const CHECKS := preload("res://tools/dialogue_lite/dialogue_checks.gd")


func _ready() -> void:
	var r: Dictionary = CHECKS.run(self)
	for l in r["lines"]:
		print("  ", l)
	print("=== ", "PASS" if r["ok"] else "FAIL", " ===")
	get_tree().quit(0 if r["ok"] else 1)
