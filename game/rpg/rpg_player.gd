extends CharacterBody2D

# Town adventurer. The Controller Lite mover walks, this script faces and bobs
# the sprite, and when Equipment Lite reports a weapon equipped it shows the
# sword, raises the Attack stat, and tells the quest you're geared up.

@onready var _sprite: Sprite2D = $Sprite
@onready var _sword: Sprite2D = $Sword
@onready var _equipment: EquipmentLite = $Equipment
@onready var _stats: StatsComponentLite = $Stats

# One fixed source for the weapon-slot bonus. add_modifier appends and never
# replaces, so anything per-item here stacks forever.
const ATTACK_SOURCE := "weapon_main_attack"

var _bob := 0.0


func _ready() -> void:
	_sword.visible = false
	_equipment.item_equipped.connect(_on_equipped)
	_equipment.item_unequipped.connect(_on_unequipped)
	# freeze at the stall while the shopkeeper is talking
	DialoguesLite.dialogue_started.connect(func(_id: String) -> void: ControllersLite.lock_movement(&"dialogue"))
	DialoguesLite.dialogue_finished.connect(func(_id: String) -> void: ControllersLite.unlock_movement(&"dialogue"))


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


func _on_equipped(slot_id: String, _item: Resource) -> void:
	if slot_id != "weapon_main":
		return
	_sword.visible = true
	# Clear ours first: re-equipping used to pile on another +5 Attack every
	# single time, and nothing ever took it back off when the sword came out.
	_stats.remove_modifier(ATTACK_SOURCE)
	_stats.add_modifier({"stat": "attack", "op": "flat", "amount": 5.0, "source_id": ATTACK_SOURCE})
	GameEvents.item_collected.emit("geared", 1)


func _on_unequipped(slot_id: String, _item: Resource) -> void:
	if slot_id != "weapon_main":
		return
	_sword.visible = false
	_stats.remove_modifier(ATTACK_SOURCE)
