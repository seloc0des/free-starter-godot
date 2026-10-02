extends Resource

# A plain item for when Inventory (Lite) isn't installed. No class_name, so it
# never clashes with ItemLite. Same fields as ItemLite, so the two swap freely:
# bags and shops only ever compare ids.

@export var id: String = ""
@export var name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var category: String = ""
@export var max_stack: int = 99
@export var metadata: Dictionary = {}
