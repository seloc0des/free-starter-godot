class_name InteractableLite3D
extends Area3D

# "Can be interacted with" area for 3D: signs, NPCs, chests. The Area3D twin of
# InteractableLite, with the same fields and the same on-screen message. An
# Interactor in reach focuses it; the action press calls `interact()`. The
# `event` string is mirrored on the ControllersLite bus. While it has the focus
# it floats a small "E  Use" prompt above itself.

const BUS := preload("res://addons/controller_lite/controllers_bus_lite.gd")

signal interacted(by: Node)
signal focus_entered
signal focus_exited

## The word after the key in the prompt above it while the player is in reach: "E  Use".
@export var prompt_text: String = "Use"
## Shown on screen for a moment when the player uses it. Leave it empty to show nothing.
@export var message: String = ""
@export var event: StringName = &""          ## e.g. "open_shop", "give_quest:herbs"
@export var one_shot: bool = false
@export var enabled: bool = true
## Height of the prompt above this node's origin, in metres.
@export var prompt_height: float = 1.6

var _prompt_label: Label3D = null
var _focused: bool = false


func _ready() -> void:
	set_process(false)  # only watches for a conversation while the prompt is up
	if Engine.is_editor_hint():
		return
	# built here and never owned, so it's never saved into the buyer's scene
	_prompt_label = Label3D.new()
	_prompt_label.name = "Prompt"
	_prompt_label.visible = false
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.no_depth_test = true
	_prompt_label.shaded = false
	# constant on-screen size, so the prompt reads at any camera distance
	_prompt_label.fixed_size = true
	_prompt_label.pixel_size = 0.0012
	_prompt_label.font_size = 48
	_prompt_label.outline_size = 12
	_prompt_label.position = Vector3(0.0, prompt_height, 0.0)
	add_child(_prompt_label)


func interact(by: Node = null) -> void:
	if not enabled:
		return
	if one_shot:
		enabled = false
	interacted.emit(by)
	_controllers_lite().interacted.emit(self, by)
	if message != "" and is_inside_tree():
		InteractableLite.show_toast(get_tree(), message)


## Called by the Interactor that picks this as the nearest thing in reach.
func set_focused(focused: bool, by: Node = null) -> void:
	_focused = focused
	if _prompt_label != null:
		if focused:
			var action: Variant = by.get("action") if by != null else null
			var key: String = BUS.key_label(action if action is StringName else &"interact")
			_prompt_label.text = (key + "  " + prompt_text) if key != "" else prompt_text
		_show_prompt()
		set_process(focused)
	if focused:
		focus_entered.emit()
	else:
		focus_exited.emit()


func _process(_delta: float) -> void:
	_show_prompt()


# Up while it has the focus, but not over a conversation: E does nothing until
# the conversation ends, so there's nothing to offer.
func _show_prompt() -> void:
	if _prompt_label != null:
		_prompt_label.visible = _focused and enabled and not _controllers_lite().in_dialogue()


# ControllersLite is looked up when used instead of named. A script that names an
# autoload won't compile until the plugin that adds it is switched on, so a fresh
# install printed parse errors.
const CONTROLLERS_LITE := preload("res://addons/controller_lite/controllers_bus_lite.gd")


static func _controllers_lite() -> CONTROLLERS_LITE:
	return (Engine.get_main_loop() as SceneTree).root.get_node(^"ControllersLite") as CONTROLLERS_LITE
