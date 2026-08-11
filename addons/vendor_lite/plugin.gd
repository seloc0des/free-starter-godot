@tool
extends EditorPlugin

# The chooser is Vendor Lite's only dock: pick a shop piece → where → Apply, and
# it's dropped into the buyer's scene, baked in and re-editable.

const CHOOSER_SCRIPT := preload("res://addons/vendor_lite/editor/vendor_chooser_dock.gd")

var _chooser: Control


func _enter_tree() -> void:
	_chooser = CHOOSER_SCRIPT.new()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _chooser)


func _exit_tree() -> void:
	if _chooser:
		remove_control_from_docks(_chooser)
		_chooser.free()
		_chooser = null
