class_name InteractableLite
extends Area2D

# "Can be interacted with" area: signs, NPCs, chests. An Interactor in reach
# focuses it; the action press calls `interact()`. The `event` string is
# mirrored on the ControllersLite bus — the no-code seam for quests/dialogue.

signal interacted(by: Node)
signal focus_entered
signal focus_exited

@export var prompt: String = "Interact"      ## for your "press E" UI
@export var event: StringName = &""          ## e.g. "open_shop", "give_quest:herbs"
@export var one_shot: bool = false
@export var enabled: bool = true


func interact(by: Node = null) -> void:
	if not enabled:
		return
	if one_shot:
		enabled = false
	interacted.emit(by)
	ControllersLite.interacted.emit(self, by)


func set_focused(focused: bool) -> void:
	if focused:
		focus_entered.emit()
	else:
		focus_exited.emit()
