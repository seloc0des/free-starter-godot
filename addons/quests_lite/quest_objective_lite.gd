class_name QuestObjectiveLite
extends Resource

enum Type { COLLECT, KILL }

@export var id: String = ""
@export var type: Type = Type.COLLECT
## For COLLECT: the item id (string) to match.
## For KILL: the enemy id (string) to match.
@export var target_id: String = ""
@export var required: int = 1
