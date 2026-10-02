class_name HealthLite
extends Node

# Health component. Drop it on any body; other nodes call take_damage / heal.
# Pure logic + signals — no physics, no dependencies.

signal damaged(amount: float, source: Node)
signal healed(amount: float)
signal died

@export var max_health: float = 100.0
## Removes the character (the node this Health sits on) from the game when it dies.
@export var remove_on_death: bool = false
## Flashes the character (the node this Health sits on) when a hit hurts it but doesn't
## kill it, so you can see hits land before anything else is set up. 2D characters.
## Untick it if yours already has a hit effect of its own.
@export var flash_on_hit: bool = true
## The colour of that flash, multiplied over the character for a moment before it fades.
## Above 1 brightens: the default flashes any sprite white. A tint like red only shows on
## sprites that have that colour in them (a green one just goes dark).
@export var flash_color: Color = Color(2.5, 2.5, 2.5)

var current: float = -1.0   # lazily initialised to max_health on first use
var _flash_tween: Tween
var _rest_modulate := Color.WHITE


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
		# after the emit, so everything listening for the death heard it first
		if remove_on_death:
			_remove_body()
	elif flash_on_hit:
		# not on the killing hit: a death fade or removal owns the character by then
		_flash()


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


# Deferred, so the hit that killed it gets to finish (the hit bus) and deferred
# listeners still find it. Never the root window itself.
func _remove_body() -> void:
	var body: Node = get_parent()
	if body == null or body is Viewport:
		body = self
	body.call_deferred("queue_free")


# Tints the whole character and eases back. It remembers the colour from before the
# first flash, so a second hit landing mid-flash doesn't leave the character stuck lit up.
func _flash() -> void:
	var body := get_parent() as CanvasItem
	if body == null or not is_inside_tree():
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	else:
		_rest_modulate = body.modulate
	body.modulate = _rest_modulate * flash_color
	_flash_tween = create_tween()
	_flash_tween.tween_property(body, "modulate", _rest_modulate, 0.25)
