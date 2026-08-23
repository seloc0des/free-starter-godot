extends CharacterBody2D

# A crypt monster. The Enemy AI Lite brain does the thinking, Combat Lite does
# the hurting; this script just animates, flashes on hit, and reports its own
# death so the kill quest can count it.

@export var enemy_id: String = "goblin"
## What this monster leaves behind, rolled by Loot Lite. Empty = never drops.
@export var loot_table: LootTableLite

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _health: HealthLite = $Health
@onready var _brain: EnemyBrainLite = $Brain

var _dead := false


func _ready() -> void:
	_health.died.connect(_on_died)
	$Hurt.hit.connect(func(_amount: float, _source: Node) -> void: _flash())


func _physics_process(_delta: float) -> void:
	if _dead:
		return
	if velocity.length_squared() > 1.0:
		_sprite.play("run")
		if absf(velocity.x) > 0.0:
			_sprite.flip_h = velocity.x < 0.0
	else:
		_sprite.play("idle")


func _on_died() -> void:
	if _dead:
		return
	_dead = true
	GameEvents.enemy_defeated.emit(enemy_id)
	_drop_loot()
	_brain.enabled = false
	$Col.set_deferred("disabled", true)
	$Hurt.set_deferred("monitorable", false)
	$Touch.set_deferred("monitoring", false)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.tween_callback(func() -> void: visible = false)


func _drop_loot() -> void:
	if loot_table == null:
		return
	for rolled in loot_table.roll():
		var dropped: Variant = rolled.get("item")
		if dropped == null:
			continue
		var drop := CryptDrop.new()
		drop.item = dropped
		# Place it AFTER it lands in the tree. global_position on a node with no
		# parent is just its local transform, so setting it first means the drop
		# picks up the parent's offset on add_child and lands somewhere else.
		# Deferred calls run in the order queued, so this follows the add_child.
		get_parent().add_child.call_deferred(drop)
		drop.set_deferred("global_position", global_position)


func _flash() -> void:
	_sprite.modulate = Color(3, 3, 3)
	_spark()
	get_tree().create_timer(0.1).timeout.connect(func() -> void:
		_sprite.modulate = Color.WHITE)


func _spark() -> void:
	var spark := HitSpark.new()
	get_parent().add_child.call_deferred(spark)
	spark.set_deferred("global_position", global_position)
