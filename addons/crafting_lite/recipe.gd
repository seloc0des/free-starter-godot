class_name RecipeLite
extends Resource

# Shapeless recipe. Inputs are consumed; outputs are produced. No grid
# placement, no station id, no time, no level requirement.

@export var id: String = ""
@export var title: String = ""
@export var icon: Texture2D

## Each input: {item: Resource, count: int}
@export var inputs: Array = []
## Each output: {item: Resource, count: int}
@export var outputs: Array = []


static func io(item: Resource, count: int) -> Dictionary:
	return {"item": item, "count": count}
