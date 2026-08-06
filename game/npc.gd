extends Area2D

# Walk-up-and-talk NPC. Shows a prompt when the player is in range; Space starts
# the conversation (which the chassis turns into a quest via the dialogue event).

@export var dialogue_id: String = "healer_intro"

@onready var _prompt: Label = $Prompt

var _near: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_prompt.visible = false


func _on_body_entered(b: Node) -> void:
	if b.is_in_group("player"):
		_near = true
		_prompt.visible = true


func _on_body_exited(b: Node) -> void:
	if b.is_in_group("player"):
		_near = false
		_prompt.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if _near and not DialoguesLite.is_active() and event.is_action_pressed("ui_accept"):
		DialoguesLite.start(dialogue_id)
		get_viewport().set_input_as_handled()
