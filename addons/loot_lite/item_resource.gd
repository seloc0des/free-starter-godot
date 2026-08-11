extends Resource

# Minimal item Resource for Loot — Lite. NO `class_name`. Duck-compatible on
# `id`, `name`. Point your project's own item type at LootTableLite entries
# instead of using this if you already have one.

@export var id: String = ""
@export var name: String = ""
@export var icon: Texture2D
