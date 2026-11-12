class_name HurtboxLite3D
extends Area3D

# 3D twin of HurtboxLite. The "can be hit" area. Sits on a body next to a HealthLite.
# When a HitboxLite3D of a different team overlaps, it takes the hit and forwards the
# damage to Health. The hit on the bus carries a Vector3 position.

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
		_health.died.connect(func() -> void: _combat_lite().entity_died.emit(_owner_node()))


func receive_hit(amount: float, source: Node) -> void:
	hit.emit(amount, source)
	if _health != null:
		_health.take_damage(amount, source)
	_combat_lite().hit_landed.emit(_hit_point(), amount, source)


# Where the hit shows: the middle of the first collision shape, because a character's
# hurtbox sits at its feet and sparks belong on the body. Falls back to the node itself.
func _hit_point() -> Vector3:
	for c in get_children():
		if c is CollisionShape3D:
			return (c as CollisionShape3D).global_position
	return global_position


func _find_sibling_health() -> HealthLite:
	var p := get_parent()
	if p != null:
		for c in p.get_children():
			if c is HealthLite:
				return c
	return null


func _owner_node() -> Node:
	return get_parent() if get_parent() != null else self


# CombatLite is looked up when used instead of named. A script that names an autoload
# won't compile until the plugin that adds it is switched on, so a fresh install
# printed parse errors.
const COMBAT_LITE := preload("res://addons/combat_lite/combat_events_lite.gd")


static func _combat_lite() -> COMBAT_LITE:
	return (Engine.get_main_loop() as SceneTree).root.get_node(^"CombatLite") as COMBAT_LITE
