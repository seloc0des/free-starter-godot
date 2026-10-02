@tool
extends EditorPlugin

# Ships a compact no-code authoring dock (the Pro tier adds full fields + wiring)
# plus the "chooser" — pick what gives out quests → Apply → baked onto your node.
# Registers the QuestsLite autoload too, so ticking the plugin is the whole install.

const AUTOLOAD_NAME := "QuestsLite"
const AUTOLOAD_PATH := "res://addons/quests_lite/quest_manager_lite.gd"
const META_SECTION := "quests_lite"
const META_ADDED := "added_autoload"
const CHOOSER_SCRIPT := preload("res://addons/quests_lite/editor/quests_chooser_dock.gd")
const DOCK_SCRIPT := preload("res://addons/quests_lite/editor/lite_dock.gd")

var _chooser: Control = null
var _dock: Control = null


func _enable_plugin() -> void:
	_ensure_autoload()


func _disable_plugin() -> void:
	# Only take away an autoload this plugin put there. A project that declares
	# QuestsLite itself (the starter kits do, their game needs it) keeps it, and so
	# does one pointing somewhere else.
	var es := EditorInterface.get_editor_settings()
	var key := "autoload/" + AUTOLOAD_NAME
	if es.get_project_metadata(META_SECTION, META_ADDED, false) and ProjectSettings.has_setting(key) \
			and _is_ours(String(ProjectSettings.get_setting(key))):
		remove_autoload_singleton(AUTOLOAD_NAME)
	es.set_project_metadata(META_SECTION, META_ADDED, false)


func _enter_tree() -> void:
	# 1.2 and older never registered it, so a project that ticked the plugin back
	# then has no autoload. _enable_plugin won't run again for them; this does.
	_ensure_autoload()
	# Chooser first so it's the tab a non-coder lands on; the "Quests — Lite" tab
	# below is the reflective authoring dock.
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


# Guarded so it won't clash with a project that declares it by hand (the demo does).
# Remembers that we added it, per project and outside project.godot, so disabling
# the plugin removes only what it added.
func _ensure_autoload() -> void:
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
		EditorInterface.get_editor_settings().set_project_metadata(META_SECTION, META_ADDED, true)


# 4.7 saves the autoload as "*uid://...", 4.5 as "*res://...".
func _is_ours(value: String) -> bool:
	var p := value.trim_prefix("*")
	if p.begins_with("uid://"):
		var id := ResourceUID.text_to_id(p)
		p = ResourceUID.get_id_path(id) if ResourceUID.has_id(id) else ""
	return p == AUTOLOAD_PATH
