extends Node

# Headless engine check for Scene Flow — Lite. Sync + fade checks run here;
# the scene-swap leg runs from a /root checker because the swap destroys this
# scene.
#   ~/.local/bin/godot --headless --path lite/scene-flow res://tools/scene_flow_lite/verify.tscn

const CHECKS := preload("res://tools/scene_flow_lite/flow_checks.gd")
const CHECKER := preload("res://tools/scene_flow_lite/flow_checker.gd")


func _ready() -> void:
	var r: Dictionary = CHECKS.run(self)
	var lines: Array = r["lines"]
	var ok: bool = r["ok"]
	var rf: Dictionary = await CHECKS.run_fades(self)
	lines.append_array(rf["lines"])
	ok = ok and rf["ok"]
	var checker: Node = CHECKER.new()
	get_tree().root.add_child(checker)
	checker.done.connect(func(swap_ok: bool, swap_lines: Array) -> void:
		lines.append_array(swap_lines)
		for l in lines:
			print("  ", l)
		print("=== ", "PASS" if (ok and swap_ok) else "FAIL", " ===")
		checker.get_tree().quit(0 if (ok and swap_ok) else 1))
	checker.start()
