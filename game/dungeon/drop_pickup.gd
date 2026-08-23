class_name CryptDrop
extends Area2D

# A loot drop lying where a monster fell. Builds its own sprite from the item's
# icon, heals on touch, then vanishes. Drops are of the moment: they don't save,
# and that's on purpose — grab it or lose it to the reload.

@export var item: ItemLite


func _ready() -> void:
	var sprite := Sprite2D.new()
	sprite.texture = item.icon if item != null else null
	add_child(sprite)
	var shape := CircleShape2D.new()
	shape.radius = 9.0
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)
	body_entered.connect(_on_body_entered)


func _on_body_entered(b: Node) -> void:
	if not b.is_in_group("player") or not b.has_node("Health"):
		return
	var health := b.get_node("Health") as HealthLite
	# metadata is a free-form Dictionary the buyer edits in the inspector, so a
	# null or a word in "heal" has to read as no heal. float() throws on those,
	# and the throw skipped the queue_free below, leaving a drop that could never
	# be picked up and re-threw every time the player brushed it.
	var raw: Variant = item.metadata.get("heal", 0.0) if item != null else 0.0
	var amount := float(raw) if (raw is float or raw is int) else 0.0
	if amount > 0.0:
		health.heal(amount)
	queue_free()
