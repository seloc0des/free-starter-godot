@tool
extends EditorPlugin

# Adds the Start Here panel. This is the one plugin the buyer should never need to
# switch off, so it carries no autoload and touches nothing in their project.
#
# Bottom panel, not a dock, and that's deliberate. Every Lite pack docks beside
# the Inspector; put a fifteenth panel there and Godot pushes it behind the tab
# overflow arrows, which is precisely where a first-time buyer will never look.
# Bottom panel entries stay as named buttons in a row that doesn't collapse, so
# "Start Here" is readable the moment the project opens.

const DOCK_SCRIPT := preload("res://addons/starter_kit/editor/start_here_dock.gd")

var _panel: Control = null


func _enter_tree() -> void:
	_panel = DOCK_SCRIPT.new()
	add_control_to_bottom_panel(_panel, "Start Here")


func _exit_tree() -> void:
	if _panel != null:
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
		_panel = null
