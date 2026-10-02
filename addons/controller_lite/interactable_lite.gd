class_name InteractableLite
extends Area2D

# "Can be interacted with" area: signs, NPCs, chests. An Interactor in reach
# focuses it; the action press calls `interact()`. The `event` string is
# mirrored on the ControllersLite bus — the no-code seam for quests/dialogue.
# While it has the focus it shows a small "E  Use" prompt above itself, and
# `message` pops up on screen when the player uses it.

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
## The 1.1 name for this text. Kept so older scenes and scripts still load; the prompt uses prompt_text.
@export_storage var prompt: String = "Interact"

var _prompt_label: Label = null
var _focused := false


func _ready() -> void:
	set_process(false)  # only watches for a conversation while the prompt is up
	if Engine.is_editor_hint():
		return
	# built here and never owned, so it's never saved into the buyer's scene
	_prompt_label = Label.new()
	_prompt_label.name = "Prompt"
	_prompt_label.visible = false
	_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 14)
	_prompt_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt_label.add_theme_constant_override("outline_size", 4)
	_prompt_label.z_index = 100  # over the sprites around it
	add_child(_prompt_label)


func interact(by: Node = null) -> void:
	if not enabled:
		return
	if one_shot:
		enabled = false
	interacted.emit(by)
	_controllers_lite().interacted.emit(self, by)
	if message != "":
		_toast(message)


## Called by the Interactor that picks this as the nearest thing in reach.
func set_focused(focused: bool, by: Node = null) -> void:
	_focused = focused
	if _prompt_label != null:
		if focused:
			var action: Variant = by.get("action") if by != null else null
			var key: String = BUS.key_label(action if action is StringName else &"interact")
			_prompt_label.text = (key + "  " + prompt_text) if key != "" else prompt_text
			_place_prompt()
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
		_prompt_label.visible = _focused and not _controllers_lite().in_dialogue()


# centred just above my collision shape
func _place_prompt() -> void:
	_prompt_label.reset_size()
	var sz := _prompt_label.get_combined_minimum_size()
	_prompt_label.size = sz
	var top := -24.0
	for c in get_children():
		var cs := c as CollisionShape2D
		if cs != null and cs.shape != null:
			top = cs.position.y + cs.shape.get_rect().position.y
			break
	_prompt_label.position = Vector2(-sz.x * 0.5, top - sz.y - 4.0)


# Lites are standalone, so this carries its own little toast, the same one the
# other lites use: a label at the top centre, under any toast that's already up,
# gone after 2 seconds.
func _toast(text: String) -> void:
	if not is_inside_tree():
		return
	var host: Node = get_tree().current_scene
	if host == null:
		host = get_tree().root
	var shown := 0
	for t in get_tree().get_nodes_in_group("lite_toast"):
		if not t.is_queued_for_deletion():
			shown += 1
	var layer := CanvasLayer.new()
	layer.layer = 100
	var label := Label.new()
	label.text = text
	label.add_to_group("lite_toast")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.offset_top = 16 + shown * 32
	label.offset_bottom = label.offset_top + 28
	# an outline keeps it readable on any background
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	layer.add_child(label)
	host.add_child(layer)
	get_tree().create_timer(2.0).timeout.connect(layer.queue_free)


# ControllersLite is looked up when used instead of named. A script that names an
# autoload won't compile until the plugin that adds it is switched on, so a fresh
# install printed parse errors.
const CONTROLLERS_LITE := preload("res://addons/controller_lite/controllers_bus_lite.gd")


static func _controllers_lite() -> CONTROLLERS_LITE:
	return (Engine.get_main_loop() as SceneTree).root.get_node(^"ControllersLite") as CONTROLLERS_LITE
