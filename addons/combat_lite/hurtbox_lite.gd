class_name HurtboxLite
extends Area2D

# The "can be hit" area. Sits on a body next to a HealthLite. When a HitboxLite of
# a different team overlaps, it takes the hit and forwards the damage to Health.

signal hit(amount: float, source: Node)

@export var team: int = 0
## Optional explicit HealthLite; if empty, the first HealthLite among siblings is used.
@export var health_path: NodePath

var _health: HealthLite = null


func _ready() -> void:
	if health_path != NodePath():
		_health = get_node_or_null(health_path) as HealthLite
	if _health == null:
		_health = _find_sibling_health()
	if _health != null:
		_health.died.connect(func() -> void: CombatLite.entity_died.emit(_owner_node()))


func receive_hit(amount: float, source: Node) -> void:
	hit.emit(amount, source)
	if _health != null:
		_health.take_damage(amount, source)
	CombatLite.hit_landed.emit(global_position, amount, source)


func _find_sibling_health() -> HealthLite:
	var p := get_parent()
	if p != null:
		for c in p.get_children():
			if c is HealthLite:
				return c
	return null


func _owner_node() -> Node:
	return get_parent() if get_parent() != null else self
