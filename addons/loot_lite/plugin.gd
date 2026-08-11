@tool
extends EditorPlugin

# Ships a compact no-code authoring dock (the Pro tier adds full fields + wiring)
# plus the "chooser" — pick what drops loot → Apply → baked onto your node.

const CHOOSER_SCRIPT := preload("res://addons/loot_lite/editor/loot_chooser_dock.gd")
const DOCK_SCRIPT := preload("res://addons/loot_lite/editor/lite_dock.gd")

var _chooser: Control = null
var _dock: Control = null


func _enter_tree() -> void:
	# Chooser first so it's the tab a non-coder lands on; the "Loot Tables — Lite"
	# tab below is the reflective authoring dock.
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
