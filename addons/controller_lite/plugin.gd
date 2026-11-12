@tool
extends EditorPlugin

# Registers the ControllersLite bus autoload on enable. Guarded so it won't
# clash if the project already declares it manually (as the bundled demo does).

const AUTOLOAD_NAME := "ControllersLite"
const AUTOLOAD_PATH := "res://addons/controller_lite/controllers_bus_lite.gd"
const META_SECTION := "controller_lite"
const META_ADDED := "added_autoload"
const DOCK_SCRIPT := preload("res://addons/controller_lite/editor/controller_chooser_dock.gd")

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
	# Named here, not only in the dock's _ready: Godot 4.5 reads the tab title
	# the moment the dock is added, before _ready has run.
	_dock.name = "Controller Lite"
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _dock)
	scene_changed.connect(_on_scene_changed)


# The dock offers 3D or 2D builds by the open scene's root.
func _on_scene_changed(_root: Node) -> void:
	if _dock != null:
		_dock.call("refresh_mode")


func _exit_tree() -> void:
	if scene_changed.is_connected(_on_scene_changed):
		scene_changed.disconnect(_on_scene_changed)
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null


func _ensure_autoload() -> void:
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
		EditorInterface.get_editor_settings().set_project_metadata(META_SECTION, META_ADDED, true)
