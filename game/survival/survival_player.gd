extends CharacterBody2D

# Forest wanderer. The Controller Lite mover child does the walking; this
# script faces the sprite and step-bobs it, and when the rake is equipped it
# shows the tool and raises Foraging so every gather brings back more.

@onready var _sprite: Sprite2D = $Sprite
@onready var _tool: Sprite2D = $Tool
@onready var _equipment: EquipmentLite = $Equipment
@onready var _stats: StatsComponentLite = $Stats

# One fixed source for the weapon-slot bonus. add_modifier appends and never
# replaces, so anything per-item here stacks forever.
const FORAGE_SOURCE := "weapon_main_forage"

var _bob := 0.0


func _ready() -> void:
	_tool.visible = false
	_equipment.item_equipped.connect(_on_equipped)
	_equipment.item_unequipped.connect(_on_unequipped)


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


func _on_equipped(slot_id: String, _item: Resource) -> void:
	if slot_id != "weapon_main":
		return
	_tool.visible = true
	# a full extra unit per gather while the rake is in hand. Clear ours first:
	# re-equipping used to pile on another +1 every single time, and nothing ever
	# took the bonus back off when the tool came out of the slot.
	_stats.remove_modifier(FORAGE_SOURCE)
	_stats.add_modifier({"stat": "foraging", "op": "flat", "amount": 1.0, "source_id": FORAGE_SOURCE})


func _on_unequipped(slot_id: String, _item: Resource) -> void:
	if slot_id != "weapon_main":
		return
	_tool.visible = false
	_stats.remove_modifier(FORAGE_SOURCE)
