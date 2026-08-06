@tool
extends EditorPlugin

# Registers the DialoguesLite autoload on enable so a buyer just ticks the plugin
# and starts authoring. Guarded so it won't clash if the project already declares
# it manually (as the bundled demo does).

const AUTOLOAD_NAME := "DialoguesLite"
const AUTOLOAD_PATH := "res://addons/dialogue_lite/dialogue_manager_lite.gd"


func _enter_tree() -> void:
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _exit_tree() -> void:
	if ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		remove_autoload_singleton(AUTOLOAD_NAME)
