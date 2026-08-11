extends CanvasLayer
# Visual PASS/FAIL banner for the pack's runtime self-test. verify.gd hands us its
# results when it's run in a window (editor F6); headless keeps its old exit-code path.
# No emoji — Godot's default font renders them as tofu; we lean on color + words.

const GREEN := Color(0.29, 0.82, 0.47)
const RED := Color(0.92, 0.33, 0.33)
const DIM := Color(0.72, 0.74, 0.78)


func render(passes: int, failures: int, log_lines: Array) -> void:
	var ok := failures == 0

	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.10, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 28
	root.offset_top = 24
	root.offset_right = -28
	root.offset_bottom = -24
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var banner := Label.new()
	banner.text = "PASS:  %d / %d checks" % [passes, passes] if ok \
		else "FAIL:  %d of %d checks failed" % [failures, passes + failures]
	banner.add_theme_font_size_override("font_size", 40)
	banner.add_theme_color_override("font_color", GREEN if ok else RED)
	root.add_child(banner)

	var sub := Label.new()
	sub.text = "Runtime self-test for this pack. Green = the feature works. Re-run repeats it."
	sub.add_theme_color_override("font_color", DIM)
	root.add_child(sub)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for entry in log_lines:
		var passed: bool = entry[0]
		var row := Label.new()
		row.text = ("PASS   " if passed else "FAIL   ") + str(entry[1])
		row.add_theme_color_override("font_color", GREEN if passed else RED)
		list.add_child(row)

	var rerun := Button.new()
	rerun.text = "Re-run"
	rerun.custom_minimum_size = Vector2(120, 36)
	rerun.pressed.connect(func() -> void: get_tree().reload_current_scene())
	root.add_child(rerun)
