class_name HealthLite
extends Node

# Health component. Drop it on any body; other nodes call take_damage / heal.
# Pure logic + signals — no physics, no dependencies.

signal damaged(amount: float, source: Node)
signal healed(amount: float)
signal died

@export var max_health: float = 100.0

var current: float = -1.0   # lazily initialised to max_health on first use


func _ready() -> void:
	_ensure_init()


func _ensure_init() -> void:
	if current < 0.0:
		current = max_health


func take_damage(amount: float, source: Node = null) -> void:
	_ensure_init()
	if amount <= 0.0 or not is_alive():
		return
	current = max(0.0, current - amount)
	damaged.emit(amount, source)
	if current <= 0.0:
		died.emit()


func heal(amount: float) -> void:
	_ensure_init()
	if amount <= 0.0 or not is_alive():
		return
	current = min(max_health, current + amount)
	healed.emit(amount)


func revive(to: float = -1.0) -> void:
	current = max_health if to < 0.0 else min(max_health, to)


func is_alive() -> bool:
	_ensure_init()
	return current > 0.0


func fraction() -> float:
	_ensure_init()
	return current / max_health if max_health > 0.0 else 0.0
