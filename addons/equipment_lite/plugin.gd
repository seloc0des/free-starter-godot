@tool
extends EditorPlugin

# Ships the "add equipment" chooser (leftmost) + the compact no-code authoring
# dock. The Pro tier adds full fields + one-click wiring.

const CHOOSER_SCRIPT := preload("res://addons/equipment_lite/editor/equipment_chooser_dock.gd")
const DOCK_SCRIPT := preload("res://addons/equipment_lite/editor/lite_dock.gd")

var _chooser: Control = null
var _dock: Control = null


func _enter_tree() -> void:
	# Chooser first so a non-coder lands on "pick what you want → Apply". The
	# "Equippables — Lite" tab beside it is where they author the item resources.
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
