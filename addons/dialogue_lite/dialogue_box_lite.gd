extends Control

# Drop-in dialogue UI. Add dialogue_box_lite.tscn to your scene and conversations
# render themselves — it just listens to the DialoguesLite autoload. No code.

@export var advance_action: StringName = &"ui_accept"

@onready var _speaker: Label = %Speaker
@onready var _text: RichTextLabel = %Text
@onready var _choices: VBoxContainer = %Choices
@onready var _hint: Label = %Hint

var _awaiting_choice: bool = false


func _ready() -> void:
	hide()
	_dialogues_lite().line_shown.connect(_on_line)
	_dialogues_lite().choices_shown.connect(_on_choices)
	_dialogues_lite().dialogue_finished.connect(_on_finished)


func _on_line(speaker: String, text: String) -> void:
	_clear_choices()
	_awaiting_choice = false
	_speaker.text = speaker
	_text.text = text
	_hint.show()
	show()


func _on_choices(choices: PackedStringArray) -> void:
	_awaiting_choice = true
	_hint.hide()
	var first: Button = null
	for i in choices.size():
		var b := Button.new()
		b.text = choices[i]
		var idx := i
		b.pressed.connect(func() -> void: _dialogues_lite().choose(idx))
		_choices.add_child(b)
		if first == null:
			first = b
	if first != null:
		# A keyboard or gamepad player needs a focused button: this node swallows
		# Enter while choices are up, so without focus only the mouse could answer.
		# The arrows then move between choices and Enter or Space picks, the way the
		# Pro box works. Deferred so it's laid out first, and by id because the
		# conversation can end, freeing the buttons, before the call runs.
		_focus_choice.call_deferred(first.get_instance_id())


func _focus_choice(id: int) -> void:
	var b: Button = instance_from_id(id) as Button
	if b != null and b.is_inside_tree() and b.is_visible_in_tree():
		b.grab_focus()


func _on_finished(_id: String) -> void:
	_clear_choices()
	hide()


func _clear_choices() -> void:
	for c in _choices.get_children():
		c.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(advance_action):
		if not _awaiting_choice:
			_dialogues_lite().advance()
		# consume it so a walk-up NPC doesn't re-trigger on the same press
		get_viewport().set_input_as_handled()


# DialoguesLite is looked up when used instead of named. A script that names an
# autoload won't compile until the plugin that adds it is switched on, so a fresh
# install printed parse errors.
const DIALOGUES_LITE := preload("res://addons/dialogue_lite/dialogue_manager_lite.gd")


static func _dialogues_lite() -> DIALOGUES_LITE:
	return (Engine.get_main_loop() as SceneTree).root.get_node(^"DialoguesLite") as DIALOGUES_LITE
