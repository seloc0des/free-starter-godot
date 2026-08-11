extends Resource

# Standalone item Resource for Equipment — Lite. NO `class_name` so it
# doesn't collide with Inventory Lite's `ItemLite`. Duck-typed on
# `id`, `name`, `icon`, `metadata`. The `metadata.equip_slot` field carries
# the slot id this item targets ("weapon_main", "chest", "boots", "ring").

@export var id: String = ""
@export var name: String = ""
@export var icon: Texture2D
@export var metadata: Dictionary = {}  # supports "equip_slot": "<slot_id>"
