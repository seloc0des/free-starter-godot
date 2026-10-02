class_name TopDownMoverLite
extends Node

# 8-way top-down movement for the parent CharacterBody2D. Arrows and WASD work
# out of the box (the move_* actions), acceleration/friction are px/s² (0 =
# instant), and it stands still while a Dialogue conversation runs or the bus
# has a movement lock. Persists position via the lite Save contract when
# `save_id` is set.

signal started_moving
signal stopped_moving

@export var speed: float = 200.0
@export var acceleration: float = 0.0        ## px/s² toward top speed, 0 = instant
@export var friction: float = 0.0            ## px/s² braking, 0 = instant stop
@export var action_left: StringName = &"move_left"
@export var action_right: StringName = &"move_right"
@export var action_up: StringName = &"move_up"
@export var action_down: StringName = &"move_down"
@export var input_enabled: bool = true
@export var is_player: bool = true           ## joins the "player" group + registers on the bus
@export var save_id: String = ""             ## set to persist position via the Save addon
## Stands still while a Dialogue (Lite or Pro) conversation is on screen.
@export var freeze_during_dialogue: bool = true

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
		_controllers_lite().register_player(_body)
	if save_id != "":
		for g in SAVE_GROUPS:
			add_to_group(g)


func _physics_process(delta: float) -> void:
	var dir := Vector2.ZERO
	if input_enabled and not _controllers_lite().is_locked() and not _talking():
		dir = Input.get_vector(action_left, action_right, action_up, action_down)
	var target := dir * speed
	if dir != Vector2.ZERO:
		_body.velocity = _approach(_body.velocity, target, acceleration, delta)
	else:
		_body.velocity = _approach(_body.velocity, Vector2.ZERO, friction, delta)
	_body.move_and_slide()
	_flag_moving(_body.velocity.length_squared() > 1.0)


# Dialogue Lite or Pro, asked through the bus, so neither pack is needed
func _talking() -> bool:
	return freeze_during_dialogue and _controllers_lite().in_dialogue()


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


# ControllersLite is looked up when used instead of named. A script that names an
# autoload won't compile until the plugin that adds it is switched on, so a fresh
# install printed parse errors.
const CONTROLLERS_LITE := preload("res://addons/controller_lite/controllers_bus_lite.gd")


static func _controllers_lite() -> CONTROLLERS_LITE:
	return (Engine.get_main_loop() as SceneTree).root.get_node(^"ControllersLite") as CONTROLLERS_LITE
