class_name DialogueLite
extends Resource

## One conversation. `entry` is the id of the first node to play.
@export var id: String = ""
@export var title: String = ""
@export var entry: String = ""
@export var nodes: Array[DialogueNodeLite] = []
