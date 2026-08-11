@tool
extends EditorPlugin

# Registers the CombatLite bus autoload on enable. Guarded so it won't clash if the
# project already declares it manually (as the bundled demo does).

const AUTOLOAD_NAME := "CombatLite"
const AUTOLOAD_PATH := "res://addons/combat_lite/combat_events_lite.gd"
const DOCK_SCRIPT := preload("res://addons/combat_lite/editor/combat_chooser_dock.gd")

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
