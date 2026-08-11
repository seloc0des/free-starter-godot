extends Control

# On-screen QA banner: door guards, spawn lookup + a visible fade roundtrip.
# The scene-swap travel leg is covered by the headless verify (a swap would
# destroy this banner).

const CHECKS := preload("res://tools/scene_flow_lite/flow_checks.gd")

@onready var _banner: Label = %Banner
@onready var _detail: RichTextLabel = %Detail


func _ready() -> void:
	var r: Dictionary = CHECKS.run(self)
	var lines: Array = r["lines"]
	var ok: bool = r["ok"]
	var rf: Dictionary = await CHECKS.run_fades(self)
	lines.append_array(rf["lines"])
	ok = ok and rf["ok"]
	lines.append("[--] scene-swap travel: covered by tools/verify.tscn (headless)")
	_banner.text = "PASS" if ok else "FAIL"
	_banner.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4) if ok else Color(0.95, 0.35, 0.35))
	for l in lines:
		_detail.append_text(l + "\n")
