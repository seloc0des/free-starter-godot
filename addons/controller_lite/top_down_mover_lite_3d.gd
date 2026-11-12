class_name TopDownMoverLite3D
extends Node

# Ground movement for the parent CharacterBody3D, the 3D twin of TopDownMoverLite.
# Arrows and WASD work out of the box (the move_* actions). It moves relative to
# what the active camera is looking at, turns the body to face where it goes,
# and keeps gravity on so slopes, steps and ledges behave. Stands still while a
# Dialogue conversation runs or the bus has a movement lock. Persists position
# and facing via the lite Save contract when `save_id` is set.
# Everything is metres and seconds.

signal started_moving
signal stopped_moving

## Top speed in m/s. 5 is a brisk run for a 1.8 m character.
@export var speed: float = 5.0
## m/s² toward top speed. 0 = instant. The default reaches 5 m/s in about a sixth of a second.
@export var acceleration: float = 30.0
## m/s² braking. 0 = instant stop.
@export var friction: float = 40.0
## How fast the body turns to face where it moves, in degrees per second. 0 = turn instantly.
@export var turn_speed: float = 720.0
## Off = movement follows the camera: W goes away from it. On = W is always -Z, whatever the camera does.
@export var world_relative: bool = false
## Fall acceleration in m/s². The engine's own 9.8 feels floaty in a game, so this is higher.
@export var gravity: float = 20.0
## Terminal fall speed in m/s.
@export var max_fall_speed: float = 40.0
## The tallest step it walks straight up, in metres. 0 = no stepping (ramps still work).
@export var step_height: float = 0.3
@export var action_left: StringName = &"move_left"
@export var action_right: StringName = &"move_right"
@export var action_up: StringName = &"move_up"
@export var action_down: StringName = &"move_down"
@export var input_enabled: bool = true
@export var is_player: bool = true           ## joins the "player" group + registers on the bus
@export var save_id: String = ""             ## set to persist position via the Save addon
## Stands still while a Dialogue (Lite or Pro) conversation is on screen.
@export var freeze_during_dialogue: bool = true

var _body: CharacterBody3D = null
var _moving: bool = false
var _reach_radius: float = 0.35
var _step_hit: KinematicCollision3D = KinematicCollision3D.new()      # reused every frame by the step test
var _step_landing: KinematicCollision3D = KinematicCollision3D.new()

const SAVE_GROUPS: Array[String] = ["save_load_contract", "save_load_contract_lite"]


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	if _body == null:
		push_warning("TopDownMoverLite3D needs a CharacterBody3D parent.")
		set_physics_process(false)
		return
	# The body has to snap back down onto the step it just climbed, or it
	# hops on every stair.
	_body.floor_snap_length = maxf(_body.floor_snap_length, step_height)
	_reach_radius = _measure_reach()
	if is_player:
		_body.add_to_group("player")
		_controllers_lite().register_player(_body)
	if save_id != "":
		for g in SAVE_GROUPS:
			add_to_group(g)


func _physics_process(delta: float) -> void:
	var locked: bool = not input_enabled or _controllers_lite().is_locked() or _talking()
	if _body.is_on_floor():
		_body.velocity.y = maxf(_body.velocity.y, 0.0)
	else:
		_body.velocity.y = maxf(_body.velocity.y - gravity * delta, -max_fall_speed)
	var wish: Vector3 = Vector3.ZERO
	if not locked:
		wish = _wish_direction()
	var flat: Vector2 = Vector2(_body.velocity.x, _body.velocity.z)
	var target: Vector2 = Vector2(wish.x, wish.z) * speed
	var rate: float = acceleration if wish != Vector3.ZERO else friction
	flat = target if rate <= 0.0 else flat.move_toward(target, rate * delta)
	_body.velocity.x = flat.x
	_body.velocity.z = flat.y
	if wish != Vector3.ZERO:
		_turn_toward(wish, delta)
	_step_up(delta)
	_body.move_and_slide()
	_flag_moving(Vector2(_body.velocity.x, _body.velocity.z).length_squared() > 0.01)


# Where the player is pushing, as a flat world direction of length 0..1.
func _wish_direction() -> Vector3:
	var pushed: Vector2 = Input.get_vector(action_left, action_right, action_up, action_down)
	if pushed == Vector2.ZERO:
		return Vector3.ZERO
	var forward: Vector3 = Vector3(0.0, 0.0, -1.0)
	var cam: Camera3D = get_viewport().get_camera_3d() if not world_relative else null
	if cam != null:
		forward = _flat(-cam.global_basis.z)
		if forward == Vector3.ZERO:
			# a camera looking straight down: its up edge is "forward" on screen
			forward = _flat(cam.global_basis.y)
		if forward == Vector3.ZERO:
			forward = Vector3(0.0, 0.0, -1.0)
	var right: Vector3 = forward.cross(Vector3.UP)
	return right * pushed.x + forward * -pushed.y


static func _flat(v: Vector3) -> Vector3:
	v.y = 0.0
	return v.normalized() if v.length_squared() > 0.0001 else Vector3.ZERO


func _turn_toward(wish: Vector3, delta: float) -> void:
	# `wish` is a world direction, so turn in world space: a body under a rotated
	# parent would otherwise face sideways
	var goal: float = atan2(-wish.x, -wish.z)
	var now: float = _body.global_rotation.y
	if turn_speed <= 0.0:
		_body.global_rotation.y = goal
		return
	var nearest: float = now + wrapf(goal - now, -PI, PI)
	_body.global_rotation.y = rotate_toward(now, nearest, deg_to_rad(turn_speed) * delta)



# Walks up a step instead of stopping against it. A real up, forward, down test:
# the way must be blocked at foot level by something steeper than a ramp, clear
# when raised by step_height and moved forward by a body radius, and there must be
# floor within step_height below that. The body rises only by the measured height
# of that floor, so a ledge taller than step_height is a wall.
func _step_up(delta: float) -> void:
	if step_height <= 0.0 or not _body.is_on_floor() or _body.velocity.y > 0.0:
		return
	var heading: Vector3 = Vector3(_body.velocity.x, 0.0, _body.velocity.z)
	if heading.length_squared() < 0.000001:
		return
	var motion: Vector3 = heading * delta
	var here: Transform3D = _body.global_transform
	var hit: KinematicCollision3D = _step_hit
	if not _body.test_move(here, motion, hit):
		return
	# a ramp the body can already walk is not a step
	if hit.get_normal().angle_to(Vector3.UP) <= _body.floor_max_angle:
		return
	var up: Vector3 = Vector3.UP * step_height
	if _body.test_move(here, up):
		return
	var raised: Transform3D = here.translated(up)
	var reach: Vector3 = heading.normalized() * maxf(motion.length(), _reach_radius)
	if _body.test_move(raised, reach):
		return
	var landing: KinematicCollision3D = _step_landing
	if not _body.test_move(raised.translated(reach), -up, landing):
		return
	if landing.get_normal().angle_to(Vector3.UP) > _body.floor_max_angle:
		return
	var rise: float = step_height - landing.get_travel().length()
	if rise > 0.005:
		_body.global_position.y += rise


# How far out the body's collision shape reaches sideways, for the step test.
func _measure_reach() -> float:
	for c in _body.get_children():
		var cs: CollisionShape3D = c as CollisionShape3D
		if cs == null or cs.shape == null:
			continue
		if cs.shape is CapsuleShape3D:
			return (cs.shape as CapsuleShape3D).radius
		if cs.shape is SphereShape3D:
			return (cs.shape as SphereShape3D).radius
		if cs.shape is CylinderShape3D:
			return (cs.shape as CylinderShape3D).radius
		if cs.shape is BoxShape3D:
			var size: Vector3 = (cs.shape as BoxShape3D).size
			return maxf(size.x, size.z) * 0.5
	return 0.35


func _flag_moving(now: bool) -> void:
	if now == _moving:
		return
	_moving = now
	if _moving:
		started_moving.emit()
	else:
		stopped_moving.emit()


# Dialogue Lite or Pro, asked through the bus, so neither pack is needed
func _talking() -> bool:
	return freeze_during_dialogue and _controllers_lite().in_dialogue()


# ---- save contract -------------------------------------------------------

func get_save_id() -> String:
	return "controller_%s" % save_id


func save_state() -> Dictionary:
	if _body == null:
		return {}
	var p: Vector3 = _body.global_position
	return {"x": p.x, "y": p.y, "z": p.z, "yaw": _body.global_rotation.y}


func load_state(data: Dictionary) -> void:
	if _body == null or data.is_empty():
		return
	var x: float = _num(data.get("x", 0.0))
	var y: float = _num(data.get("y", 0.0))
	var z: float = _num(data.get("z", 0.0))
	var yaw: float = _num(data.get("yaw", _body.global_rotation.y))
	# A non-finite position is unrecoverable: the body leaves the visible world and
	# every later move_and_slide keeps it there. Refuse rather than strand the player.
	if not (is_finite(x) and is_finite(y) and is_finite(z) and is_finite(yaw)):
		push_error("%s: saved position is not a finite number; leaving the body where it is." % name)
		return
	_body.global_position = Vector3(x, y, z)
	_body.global_rotation.y = yaw
	_body.velocity = Vector3.ZERO


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
