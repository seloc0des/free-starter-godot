@tool
extends EditorPlugin

# Registers the AudioLite autoload on enable. Guarded so it won't clash if the
# project already declares it manually (as the bundled demo does).

const AUTOLOAD_NAME := "AudioLite"
const AUTOLOAD_PATH := "res://addons/audio_lite/audio_lite.gd"
const META_SECTION := "audio_lite"
const META_ADDED := "added_autoload"
const DOCK_SCRIPT := preload("res://addons/audio_lite/editor/audio_chooser_dock.gd")

var _dock: Control = null


func _enable_plugin() -> void:
	_ensure_autoload()


# Only take away an autoload this plugin put there. A project that declares it
# itself (the starter kits do, their game needs it) keeps it.
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
