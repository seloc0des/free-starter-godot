class_name DialogueNodeLite
extends Resource

## A single beat of conversation. If `choices` is empty the box waits for the
## player to advance and then jumps to `next` (empty `next` ends the dialogue).
## `event` (optional) is a plain string fired when this node shows — the seam
## other systems listen on, e.g. "give_quest:gather_herbs". Lite keeps it a bare
## string; the Pro tier wires it to quests/inventory/flags directly.
@export var id: String = ""
@export var speaker: String = ""
@export_multiline var text: String = ""
@export var next: String = ""
@export var event: String = ""
@export var choices: Array[DialogueChoiceLite] = []
