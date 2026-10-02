@tool
extends EditorPlugin

const SAVE_NAME := "SaveLite"
const SAVE_PATH := "res://addons/save_load_lite/save_lite.gd"
const META_SECTION := "save_load_lite"
const META_ADDED := "added_autoload"
const CHOOSER_SCRIPT := preload("res://addons/save_load_lite/editor/save-load_chooser_dock.gd")

var _chooser: Control


# The autoload is added once and only removed when the plugin is switched off, and
# only if we added it. Removing it on every editor close took the starter kits' own
# SaveLite line out of project.godot, and their game needs it.
func _enable_plugin() -> void:
	_ensure_autoload()


func _disable_plugin() -> void:
	var es := EditorInterface.get_editor_settings()
	if es.get_project_metadata(META_SECTION, META_ADDED, false) and ProjectSettings.has_setting("autoload/" + SAVE_NAME):
		remove_autoload_singleton(SAVE_NAME)
	es.set_project_metadata(META_SECTION, META_ADDED, false)


func _enter_tree() -> void:
	_ensure_autoload()
	# The chooser: pick what saves → where → Apply. Lite's only dock: a non-coder
	# lands here to make a node saveable and add quick save keys without touching code.
	_chooser = CHOOSER_SCRIPT.new()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _chooser)


func _exit_tree() -> void:
	if _chooser:
		remove_control_from_docks(_chooser)
		_chooser.free()
		_chooser = null


func _ensure_autoload() -> void:
	if not ProjectSettings.has_setting("autoload/" + SAVE_NAME):
		add_autoload_singleton(SAVE_NAME, SAVE_PATH)
		EditorInterface.get_editor_settings().set_project_metadata(META_SECTION, META_ADDED, true)
