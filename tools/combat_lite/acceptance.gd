extends Control

# On-screen QA banner. Open tools/acceptance.tscn and press F6 (or Play) — a giant
# PASS/FAIL tells you the pack is healthy in this editor, with the checklist below.

const CHECKS := preload("res://tools/combat_lite/combat_checks.gd")

@onready var _banner: Label = %Banner
@onready var _detail: RichTextLabel = %Detail


func _ready() -> void:
	var r: Dictionary = CHECKS.run(self)
	var ok: bool = r["ok"]
	_banner.text = "PASS" if ok else "FAIL"
	_banner.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4) if ok else Color(0.95, 0.35, 0.35))
	for l in r["lines"]:
		_detail.append_text(l + "\n")
