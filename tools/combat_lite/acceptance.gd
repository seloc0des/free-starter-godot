extends Control

# On-screen QA banner. Open tools/acceptance.tscn and press F6 (or Play) — a giant
# PASS/FAIL tells you the pack is healthy in this editor, with the checklist below.

const CHECKS := preload("res://tools/combat_lite/combat_checks.gd")

@onready var _banner: Label = %Banner
@onready var _detail: RichTextLabel = %Detail


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
	_banner.text = "PASS" if ok else "FAIL"
	_banner.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4) if ok else Color(0.95, 0.35, 0.35))
	for l in lines:
		_detail.append_text(l + "\n")

	# Windowed (editor F6) this is a look-at-it banner and stays open. Run headless
	# it would sit there forever, so exit with a status code instead.
	if DisplayServer.get_name() == "headless":
		for l in lines:
			print("  ", l)
		print("=== ", "PASS" if ok else "FAIL", " ===")
		get_tree().quit(0 if ok else 1)
