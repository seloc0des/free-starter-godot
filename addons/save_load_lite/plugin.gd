@tool
extends EditorPlugin

const SAVE_NAME := "SaveLite"
const SAVE_PATH := "res://addons/save_load_lite/save_lite.gd"
const CHOOSER_SCRIPT := preload("res://addons/save_load_lite/editor/save-load_chooser_dock.gd")

var _chooser: Control


func _enter_tree() -> void:
	add_autoload_singleton(SAVE_NAME, SAVE_PATH)
	# The chooser: pick what saves → where → Apply. Lite's only dock — a non-coder
	# lands here to make a node saveable without touching code.
	_chooser = CHOOSER_SCRIPT.new()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _chooser)


func _exit_tree() -> void:
	remove_autoload_singleton(SAVE_NAME)
	if _chooser:
		remove_control_from_docks(_chooser)
		_chooser.free()
		_chooser = null
