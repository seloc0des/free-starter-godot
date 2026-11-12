class_name FollowCameraLite3D
extends Camera3D

# A fixed-angle camera that smoothly follows the player, for top-down and
# isometric 3D games. A 3D game with no camera shows nothing, so this is the one
# you need. Leave `target_path` empty and it follows whatever registered as the
# player on the ControllersLite bus. Drop it anywhere in the scene, but not
# under the player body: the body turns, the camera must not.

## Empty = follow the player.
@export var target_path: NodePath
## Where the camera looks, as an offset from the target's feet in metres. Chest height by default.
@export var target_offset: Vector3 = Vector3(0.0, 1.2, 0.0)
## Distance from the target in metres.
@export var distance: float = 9.0
## Compass direction of the camera in degrees. 0 looks toward -Z, 90 toward -X.
@export_range(-360.0, 360.0, 0.1) var yaw: float = 0.0
## Tilt in degrees. 0 is level, negative looks down.
@export_range(-89.0, 89.0, 0.1) var pitch: float = -55.0
## How quickly it catches up, as an exponential rate. 0 = snap to the target every frame.
@export var follow_speed: float = 6.0
## A teleport (a door or a respawn) moves the camera there at once instead of swooping. Any move in one frame that is longer than the target's own speed explains, plus this many metres, counts as one.
@export var snap_distance: float = 1.5

var _target: Node3D = null
var _focus: Vector3 = Vector3.ZERO
var _last_target: Vector3 = Vector3.ZERO
var _placed: bool = false


func _ready() -> void:
	_resolve_target()
	_controllers_lite().player_registered.connect(func(_b: Node) -> void:
		if target_path == NodePath():
			_resolve_target())


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_target):
		_resolve_target()
	if not is_instance_valid(_target):
		return
	var feet: Vector3 = _target.global_position
	var own_travel: float = 0.0
	if _target is CharacterBody3D:
		own_travel = (_target as CharacterBody3D).velocity.length() * delta
	if not _placed or feet.distance_to(_last_target) > own_travel + snap_distance:
		_focus = feet + target_offset
		_placed = true
	_last_target = feet
	var wanted: Vector3 = feet + target_offset
	if follow_speed <= 0.0:
		_focus = wanted
	else:
		_focus = _focus.lerp(wanted, 1.0 - exp(-follow_speed * delta))
	var facing: Basis = Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0))
	# The body turns, so a camera under it must not turn with it. Placed in world
	# space from here on; this also makes its place in the tree order irrelevant.
	if not top_level:
		var keep: Transform3D = global_transform
		top_level = true
		global_transform = keep
	global_transform = Transform3D(facing, _focus + facing.z * distance)


func _resolve_target() -> void:
	_target = null
	if target_path != NodePath():
		_target = get_node_or_null(target_path) as Node3D
	elif is_instance_valid(_controllers_lite().player) and _controllers_lite().player is Node3D:
		_target = _controllers_lite().player
	_placed = false


# ControllersLite is looked up when used instead of named. A script that names an
# autoload won't compile until the plugin that adds it is switched on, so a fresh
# install printed parse errors.
const CONTROLLERS_LITE := preload("res://addons/controller_lite/controllers_bus_lite.gd")


static func _controllers_lite() -> CONTROLLERS_LITE:
	return (Engine.get_main_loop() as SceneTree).root.get_node(^"ControllersLite") as CONTROLLERS_LITE
