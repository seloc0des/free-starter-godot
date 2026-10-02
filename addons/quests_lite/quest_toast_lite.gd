extends RefCounted

# The short messages at the top of the screen ("Quest started: Gather herbs").
# Lites are standalone, so Quests carries its own copy: a Label on a CanvasLayer
# made at runtime, in group "lite_toast" so toasts from every lite stack instead
# of landing on top of each other.

const GROUP := "lite_toast"
const LIFE := 2.0
const WIDTH := 400.0  # clear of the tracker's column at the top right, even at 1152 wide


static func show_toast(from: Node, text: String) -> void:
	if from == null or not from.is_inside_tree():
		return
	var tree := from.get_tree()
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	# below whatever's already showing, ours or another lite's
	var y := 16.0
	for n in tree.get_nodes_in_group(GROUP):
		if n is Control and (n as Control).is_visible_in_tree():
			y = maxf(y, (n as Control).get_global_rect().end.y + 4.0)
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS  # still fades out behind a pause menu
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label.offset_left = -WIDTH * 0.5
	label.offset_right = WIDTH * 0.5
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH  # a long one widens both ways, still centred
	label.offset_top = y
	label.offset_bottom = y + label.get_combined_minimum_size().y
	label.add_to_group(GROUP)
	layer.add_child(label)
	host.add_child(layer)
	var tw := label.create_tween()
	tw.tween_interval(LIFE - 0.4)
	tw.tween_property(label, "modulate:a", 0.0, 0.4)
	tw.tween_callback(layer.queue_free)
