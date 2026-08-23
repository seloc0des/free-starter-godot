class_name TopDownMoverLite
extends Node

# 8-way top-down movement for the parent CharacterBody2D. Arrows work out of
# the box (ui_* actions), acceleration/friction are px/s² (0 = instant), and
# movement locks from the bus freeze it during dialogue. Persists position via
# the lite Save contract when `save_id` is set.

signal started_moving
signal stopped_moving

@export var speed: float = 200.0
@export var acceleration: float = 0.0        ## px/s² toward top speed, 0 = instant
@export var friction: float = 0.0            ## px/s² braking, 0 = instant stop
@export var action_left: StringName = &"ui_left"
@export var action_right: StringName = &"ui_right"
@export var action_up: StringName = &"ui_up"
@export var action_down: StringName = &"ui_down"
@export var input_enabled: bool = true
@export var is_player: bool = true           ## joins the "player" group + registers on the bus
@export var save_id: String = ""             ## set to persist position via the Save addon

var _body: CharacterBody2D = null
var _moving := false

const SAVE_GROUPS := ["save_load_contract", "save_load_contract_lite"]


func _ready() -> void:
	_body = get_parent() as CharacterBody2D
	if _body == null:
		push_warning("TopDownMoverLite needs a CharacterBody2D parent.")
		set_physics_process(false)
		return
	if is_player:
		_body.add_to_group("player")
		ControllersLite.register_player(_body)
	if save_id != "":
		for g in SAVE_GROUPS:
			add_to_group(g)


func _physics_process(delta: float) -> void:
	var dir := Vector2.ZERO
	if input_enabled and not ControllersLite.is_locked():
		dir = Input.get_vector(action_left, action_right, action_up, action_down)
	var target := dir * speed
	if dir != Vector2.ZERO:
		_body.velocity = _approach(_body.velocity, target, acceleration, delta)
	else:
		_body.velocity = _approach(_body.velocity, Vector2.ZERO, friction, delta)
	_body.move_and_slide()
	_flag_moving(_body.velocity.length_squared() > 1.0)


func _approach(v: Vector2, target: Vector2, rate: float, delta: float) -> Vector2:
	return target if rate <= 0.0 else v.move_toward(target, rate * delta)


func _flag_moving(now: bool) -> void:
	if now == _moving:
		return
	_moving = now
	if _moving:
		started_moving.emit()
	else:
		stopped_moving.emit()


# ---- save contract -------------------------------------------------------

func get_save_id() -> String:
	return "controller_%s" % save_id


func save_state() -> Dictionary:
	if _body == null:
		return {}
	return {"x": _body.global_position.x, "y": _body.global_position.y}


func load_state(data: Dictionary) -> void:
	if _body == null or data.is_empty():
		return
	_body.global_position = Vector2(_num(data.get("x", 0.0)), _num(data.get("y", 0.0)))


# float(null) throws rather than giving 0.0, so a hand-edited or truncated save
# would abort load_state and quietly leave the body where it spawned.
static func _num(v: Variant) -> float:
	return float(v) if (v is float or v is int) else 0.0
