class_name ItemLite
extends Resource

# Minimal item Resource for Inventory — Lite. Duck-compatible with the Pro
# `ItemResource` on the shared fields (id, name, icon, max_stack, category)
# so upgrading is a straight swap.

@export var id: String = ""
@export var name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var category: String = ""
@export var max_stack: int = 99
@export var metadata: Dictionary = {}
