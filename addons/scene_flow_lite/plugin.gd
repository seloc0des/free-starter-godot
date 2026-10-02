@tool
extends EditorPlugin

# Registers the SceneFlowLite autoload on enable. Guarded so it won't clash if
# the project already declares it manually (as the bundled demo and the starter kits
# do), and switching the plugin off only removes an autoload it added itself.

const AUTOLOAD_NAME := "SceneFlowLite"
const AUTOLOAD_PATH := "res://addons/scene_flow_lite/scene_flow_lite.gd"
const META_SECTION := "scene_flow_lite"
const META_ADDED := "added_autoload"
const DOCK_SCRIPT := preload("res://addons/scene_flow_lite/editor/scene_flow_chooser_dock.gd")

var _dock: Control = null


func _enable_plugin() -> void:
	_ensure_autoload()


func _disable_plugin() -> void:
	var es := EditorInterface.get_editor_settings()
	if es.get_project_metadata(META_SECTION, META_ADDED, false) and ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		remove_autoload_singleton(AUTOLOAD_NAME)
	es.set_project_metadata(META_SECTION, META_ADDED, false)


func _enter_tree() -> void:
	_ensure_autoload()
	_dock = DOCK_SCRIPT.new()
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null


func _ensure_autoload() -> void:
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
		EditorInterface.get_editor_settings().set_project_metadata(META_SECTION, META_ADDED, true)
