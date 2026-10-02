@tool
extends EditorPlugin

# Registers the DialoguesLite autoload on enable so a buyer just ticks the plugin
# and starts authoring. Guarded so it won't clash if the project already declares
# it manually (as the bundled demo and the starter kits do), and disabling the
# plugin only removes an autoload it added itself. Removing it on every editor close
# used to strip the starter kits' own DialoguesLite line out of project.godot.

const AUTOLOAD_NAME := "DialoguesLite"
const AUTOLOAD_PATH := "res://addons/dialogue_lite/dialogue_manager_lite.gd"
const META_SECTION := "dialogue_lite"
const META_ADDED := "added_autoload"
const CHOOSER_SCRIPT := preload("res://addons/dialogue_lite/editor/dialogue_chooser_dock.gd")
const DOCK_SCRIPT := preload("res://addons/dialogue_lite/editor/dialogue_lite_dock.gd")

var _chooser: Control = null
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
	# Chooser first so it's the tab a non-coder lands on: it wires a conversation
	# into the scene. The "Dialogue" tab below is where they get written.
	_chooser = CHOOSER_SCRIPT.new()
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _chooser)
	_dock = DOCK_SCRIPT.new()
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	if _chooser != null:
		remove_control_from_docks(_chooser)
		_chooser.queue_free()
		_chooser = null
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null


func _ensure_autoload() -> void:
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
		EditorInterface.get_editor_settings().set_project_metadata(META_SECTION, META_ADDED, true)
