class_name EnemyBrainLite3D
extends Node

# The 3D twin of EnemyBrainLite: idle -> chase -> attack, with a leash that walks
# it home. Drives the parent CharacterBody3D, with gravity. Hunts the nearest
# Node3D in `target_group`. Units are metres and seconds. A Combat 3D hitbox on
# the body gets switched on for each attack.

signal state_changed(from: StringName, to: StringName)
signal target_acquired(target: Node3D)
signal target_lost
signal attacked(target: Node3D)

const IDLE := &"idle"
const CHASE := &"chase"
const ATTACK := &"attack"
const RETURN := &"return"

const IDLE_BRAKE := 20.0     # m/s^2 an idle enemy slows down at
const ARRIVE := 0.3          # m: close enough to home

@export var move_speed: float = 2.0          ## return-home speed, m/s
@export var chase_speed: float = 4.0         ## m/s
@export var detect_radius: float = 12.0      ## m
@export var attack_radius: float = 1.8       ## m, the stopping distance from the target
@export var give_up_radius: float = 25.0     ## m, leash: this far from home -> walk back
@export var attack_cooldown: float = 1.0     ## s
@export var attack_duration: float = 0.25    ## s, how long a Combat hitbox on the body stays live per attack
@export var turn_speed: float = 540.0        ## degrees per second the body turns to face its way
@export var apply_gravity: bool = true       ## pulls the body down with the project's 3D gravity
@export var target_group: StringName = &"player"
@export var enabled: bool = true

var state: StringName = IDLE
var target: Node3D = null
var home := Vector3.ZERO

var _body: CharacterBody3D = null
var _gravity := 9.8
var _target_id := 0     # instance id of `target`, so a freed one is noticed
var _cooldown := 0.0
var _health: Node = null    # a sibling with is_alive() (HealthLite fits), found in _ready
var _swing: Area3D = null     # the hitbox switched on for the current attack
var _swing_left := 0.0


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	if _body == null:
		push_warning("EnemyBrainLite3D needs a CharacterBody3D parent.")
		set_physics_process(false)
		return
	home = _body.global_position
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	for c in _body.get_children():
		if c != self and c.has_method("is_alive"):
			_health = c
			break


func _physics_process(delta: float) -> void:
	if not enabled:
		# switched off mid-swing (death, cutscene): don't leave the hitbox live
		if _swing_left > 0.0:
			_swing_left = 0.0
			_arm(false)
		return
	if _health_dead():
		# a corpse that stays in the scene (respawn delay, remove_on_death off)
		# stops fighting, and picks up again when it revives
		if _swing_left > 0.0:
			_swing_left = 0.0
			_arm(false)
		if target != null:
			_drop_target()
		_switch(IDLE)
		_stop()
		_fall_and_move(delta)
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	_tick_swing(delta)
	_update_target()

	# leash applies while engaged, mid-attack included
	if (state == CHASE or state == ATTACK) \
			and _flat_distance(home) > give_up_radius:
		_drop_target()
		_switch(RETURN)

	match state:
		IDLE:
			_brake(IDLE_BRAKE * delta)
		CHASE:
			_do_chase()
		ATTACK:
			_do_attack()
		RETURN:
			_do_return()
	_face(delta)
	_fall_and_move(delta)


func _fall_and_move(delta: float) -> void:
	if apply_gravity and not _body.is_on_floor():
		_body.velocity.y -= _gravity * delta
	_body.move_and_slide()


# Dead by is_alive(), which HealthLite and CombatHealth both answer. The brain only
# takes a sibling that has it, so there is no signal fallback here.
func _health_dead() -> bool:
	return _health != null and is_instance_valid(_health) and not bool(_health.call("is_alive"))


func set_state(to: StringName) -> void:
	_switch(to)


# ---- states --------------------------------------------------------------

func _do_chase() -> void:
	if target == null:
		return
	if _body.global_position.distance_to(target.global_position) <= attack_radius:
		_switch(ATTACK)
		return
	_run_toward(target.global_position, chase_speed)


func _do_attack() -> void:
	_stop()
	if target == null:
		return
	if _body.global_position.distance_to(target.global_position) > attack_radius * 1.2:
		_switch(CHASE)
		return
	if _cooldown <= 0.0:
		_cooldown = attack_cooldown
		_swing = _hitbox()
		_swing_left = attack_duration
		_arm(true)
		attacked.emit(target)
		_enemy_ai_lite().attack_started.emit(_body, target)


func _do_return() -> void:
	if _flat_distance(home) < ARRIVE:
		_stop()
		_switch(IDLE)
		return
	_run_toward(home, move_speed)


# ---- internals -----------------------------------------------------------

func _update_target() -> void:
	# a freed target is not null to the type system, so look it up by id. It is
	# only let go here: the search below may find another one in the same tick.
	var lost := false
	if _target_id != 0 and not is_instance_valid(instance_from_id(_target_id)):
		_drop_target()
		lost = true
	if state == RETURN:
		return                                              # deaf until home, no leash ping-pong
	var best: Node3D = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group(target_group):
		if n is Node3D and is_instance_valid(n) and n != _body:
			var d: float = _body.global_position.distance_to(n.global_position)
			if d < best_d:
				best_d = d
				best = n
	if best != null and best_d <= detect_radius:
		_target_id = best.get_instance_id()
		if target == null:
			target = best
			target_acquired.emit(best)
			if state == IDLE:
				_switch(CHASE)
		else:
			target = best
	elif target != null:
		_drop_target()
		if state == CHASE or state == ATTACK:
			_switch(RETURN)
	elif lost and (state == CHASE or state == ATTACK):
		_switch(RETURN)                                     # nobody else in range


func _drop_target() -> void:
	target = null
	_target_id = 0
	target_lost.emit()


# Flat (ground plane) helpers: gravity owns velocity.y. The leash and arriving
# home both judge on the ground, so an enemy that falls below home can't flicker.
func _flat_distance(point: Vector3) -> float:
	var d := point - _body.global_position
	return Vector2(d.x, d.z).length()


func _run_toward(point: Vector3, speed: float) -> void:
	var d := point - _body.global_position
	d.y = 0.0
	var v := d.normalized() * speed
	_body.velocity.x = v.x
	_body.velocity.z = v.z


func _stop() -> void:
	_body.velocity.x = 0.0
	_body.velocity.z = 0.0


func _brake(step: float) -> void:
	var flat := Vector2(_body.velocity.x, _body.velocity.z).move_toward(Vector2.ZERO, step)
	_body.velocity.x = flat.x
	_body.velocity.z = flat.y


# Turns the body (yaw only) toward where it is going, or toward the target while
# attacking, so a hitbox placed in front of the body swings with it.
func _face(delta: float) -> void:
	var look := Vector3(_body.velocity.x, 0.0, _body.velocity.z)
	if state == ATTACK and target != null:
		look = target.global_position - _body.global_position
		look.y = 0.0
	# velocity and the target are global, rotation.y is the parent's: convert first
	var parent := _body.get_parent() as Node3D
	if parent != null:
		look = parent.global_basis.inverse() * look
		look.y = 0.0
	if look.length_squared() < 0.01:
		return
	var want := atan2(-look.x, -look.z)                     # forward is -Z
	var step := deg_to_rad(turn_speed) * delta
	_body.rotation.y += clampf(angle_difference(_body.rotation.y, want), -step, step)


# A Combat hitbox (Pro or Lite) on the body, told apart by its exports so this
# brain never needs the Combat pack. A hitbox only hits when something starts
# touching it, so it goes off after each attack and back on for the next one:
# coming back on is what hits the player again while they stay in reach.
func _hitbox() -> Area3D:
	for c in _body.get_children():
		if c is Area3D and "team" in c and ("damage" in c or "base_damage" in c):
			return c as Area3D
	return null


func _tick_swing(delta: float) -> void:
	if _swing_left <= 0.0:
		return
	_swing_left -= delta
	if _swing_left <= 0.0:
		_arm(false)


func _arm(on: bool) -> void:
	if _swing != null and is_instance_valid(_swing):
		_swing.set_deferred("monitoring", on)


func _switch(to: StringName) -> void:
	if to == state:
		return
	var from := state
	state = to
	state_changed.emit(from, to)
	_enemy_ai_lite().state_changed.emit(_body if _body != null else self, from, to)


# EnemyAILite is looked up when used instead of named. A script that names an autoload
# won't compile until the plugin that adds it is switched on, so a fresh install
# printed parse errors.
const ENEMY_AI_LITE := preload("res://addons/enemy_ai_lite/enemy_ai_bus_lite.gd")


static func _enemy_ai_lite() -> ENEMY_AI_LITE:
	return (Engine.get_main_loop() as SceneTree).root.get_node(^"EnemyAILite") as ENEMY_AI_LITE
