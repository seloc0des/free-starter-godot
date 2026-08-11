extends CharacterBody2D

# Town adventurer. The Controller Lite mover walks, this script faces and bobs
# the sprite, and when Equipment Lite reports a weapon equipped it shows the
# sword, raises the Attack stat, and tells the quest you're geared up.

@onready var _sprite: Sprite2D = $Sprite
@onready var _sword: Sprite2D = $Sword
@onready var _equipment: EquipmentLite = $Equipment
@onready var _stats: StatsComponentLite = $Stats

var _bob := 0.0


func _ready() -> void:
	_sword.visible = false
	_equipment.item_equipped.connect(_on_equipped)


func _physics_process(delta: float) -> void:
	if velocity.length_squared() > 1.0:
		if absf(velocity.x) > 0.0:
			_sprite.flip_h = velocity.x < 0.0
			_sword.flip_h = _sprite.flip_h
		_bob += delta * 14.0
		_sprite.offset.y = -2.0 - (1.0 if int(_bob) % 2 == 0 else 0.0)
	else:
		_bob = 0.0
		_sprite.offset.y = -2.0


func _on_equipped(slot_id: String, item: Resource) -> void:
	if slot_id != "weapon_main":
		return
	_sword.visible = true
	_stats.add_modifier({"stat": "attack", "op": "flat", "amount": 5.0, "source_id": String(item.get("id"))})
	GameEvents.item_collected.emit("geared", 1)
