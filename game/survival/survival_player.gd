extends CharacterBody2D

# Forest wanderer. The Controller Lite mover child does the walking; this
# script faces the sprite and step-bobs it, and when the rake is equipped it
# shows the tool and raises Foraging so every gather brings back more.

@onready var _sprite: Sprite2D = $Sprite
@onready var _tool: Sprite2D = $Tool
@onready var _equipment: EquipmentLite = $Equipment
@onready var _stats: StatsComponentLite = $Stats

var _bob := 0.0


func _ready() -> void:
	_tool.visible = false
	_equipment.item_equipped.connect(_on_equipped)


func _physics_process(delta: float) -> void:
	if velocity.length_squared() > 1.0:
		if absf(velocity.x) > 0.0:
			_sprite.flip_h = velocity.x < 0.0
			_tool.flip_h = _sprite.flip_h
		_bob += delta * 14.0
		_sprite.offset.y = -2.0 - (1.0 if int(_bob) % 2 == 0 else 0.0)
	else:
		_bob = 0.0
		_sprite.offset.y = -2.0


func _on_equipped(slot_id: String, item: Resource) -> void:
	if slot_id != "weapon_main":
		return
	_tool.visible = true
	# a full extra unit per gather while the rake is in hand
	_stats.add_modifier({"stat": "foraging", "op": "flat", "amount": 1.0, "source_id": String(item.get("id"))})
