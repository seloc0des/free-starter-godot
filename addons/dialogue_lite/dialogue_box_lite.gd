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
	DialoguesLite.line_shown.connect(_on_line)
	DialoguesLite.choices_shown.connect(_on_choices)
	DialoguesLite.dialogue_finished.connect(_on_finished)


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
	for i in choices.size():
		var b := Button.new()
		b.text = choices[i]
		var idx := i
		b.pressed.connect(func() -> void: DialoguesLite.choose(idx))
		_choices.add_child(b)


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
			DialoguesLite.advance()
		# consume it so a walk-up NPC doesn't re-trigger on the same press
		get_viewport().set_input_as_handled()
