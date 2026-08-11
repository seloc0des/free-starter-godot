@tool
extends EditorPlugin

# Registers the DialoguesLite autoload on enable so a buyer just ticks the plugin
# and starts authoring. Guarded so it won't clash if the project already declares
# it manually (as the bundled demo does).

const AUTOLOAD_NAME := "DialoguesLite"
const AUTOLOAD_PATH := "res://addons/dialogue_lite/dialogue_manager_lite.gd"
const DOCK_SCRIPT := preload("res://addons/dialogue_lite/editor/dialogue_lite_dock.gd")

var _dock: Control = null


func _enter_tree() -> void:
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
	_dock = DOCK_SCRIPT.new()
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
	if ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		remove_autoload_singleton(AUTOLOAD_NAME)
