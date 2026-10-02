class_name DialogueTriggerLite
extends Node

# Starts a conversation with no code: when the player walks into my parent
# Area2D/Area3D, or as soon as the scene loads. The Dialogue · Setup tab drops
# these in for you. It registers the conversation itself, so a .tres from any
# folder plays.

enum When {
	ON_TOUCH,  ## the player walks into my parent Area2D/Area3D
	ON_READY,  ## as soon as the scene starts
}

## The conversation to start (a DialogueLite .tres).
@export var dialogue: DialogueLite
@export var when: When = When.ON_TOUCH
## On Touch: only a node in this group counts. Empty = anything that walks in.
@export var require_group: String = "player"


func _ready() -> void:
	if when == When.ON_READY:
		# deferred so the dialogue box is ready to listen first
		start.call_deferred()
		return
	var area := get_parent()
	if area == null or not area.has_signal("body_entered"):
		push_warning("DialogueTriggerLite '%s': On Touch needs an Area2D or Area3D parent." % name)
		return
	area.connect("body_entered", _on_touched)
	area.connect("area_entered", _on_touched)


func _on_touched(other: Node) -> void:
	if require_group != "" and not other.is_in_group(require_group):
		return
	start()


## Start it now, whatever the trigger. Does nothing while a conversation runs.
func start() -> void:
	if dialogue == null:
		push_warning("DialogueTriggerLite '%s': no dialogue picked." % name)
		return
	_dialogues_lite().start_dialogue(dialogue)


# DialoguesLite is looked up when used instead of named. A script that names an
# autoload won't compile until the plugin that adds it is switched on, so a fresh
# install printed parse errors.
const DIALOGUES_LITE := preload("res://addons/dialogue_lite/dialogue_manager_lite.gd")


static func _dialogues_lite() -> DIALOGUES_LITE:
	return (Engine.get_main_loop() as SceneTree).root.get_node(^"DialoguesLite") as DIALOGUES_LITE
