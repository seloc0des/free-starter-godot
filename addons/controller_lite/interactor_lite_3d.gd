class_name InteractorLite3D
extends Area3D

# "Press E" reach for 3D. Add under the player body, with a CollisionShape3D in
# front of it: the body turns to face where it walks, so a reach placed ahead
# swings with it. Focuses the nearest enabled InteractableLite3D in reach and
# interacts on the action press.

signal focus_changed(interactable: Node)     # null when nothing in reach

@export var action: StringName = &"interact"
@export var enabled: bool = true

var _in_reach: Array[InteractableLite3D] = []
var _focus: InteractableLite3D = null


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


func _physics_process(_delta: float) -> void:
	# nearest can change while walking, and the focus can disable itself or be freed
	if not _in_reach.is_empty():
		_refresh_focus()


func _unhandled_input(event: InputEvent) -> void:
	if enabled and is_instance_valid(_focus) and event.is_action_pressed(action):
		interact()


func interact() -> void:
	# mid-conversation, E mustn't start something else behind the dialogue box
	if enabled and is_instance_valid(_focus) and not _controllers_lite().in_dialogue():
		_focus.interact(_owner_body())


func current_focus() -> InteractableLite3D:
	return _focus if is_instance_valid(_focus) else null


func _on_area_entered(area: Area3D) -> void:
	if area is InteractableLite3D and not _in_reach.has(area):
		_in_reach.append(area)
		_refresh_focus()


func _on_area_exited(area: Area3D) -> void:
	# a typed array refuses anything else, with an error each time, so only the right kind
	if area is InteractableLite3D:
		_in_reach.erase(area)
	_refresh_focus()


func _refresh_focus() -> void:
	for i in range(_in_reach.size() - 1, -1, -1):
		if not is_instance_valid(_in_reach[i]):
			_in_reach.remove_at(i)
	var best: InteractableLite3D = null
	var best_d: float = INF
	for a in _in_reach:
		if not a.enabled:
			continue
		var d: float = global_position.distance_squared_to(a.global_position)
		if d < best_d:
			best_d = d
			best = a
	var current: InteractableLite3D = _focus if is_instance_valid(_focus) else null
	if best == current:
		return
	if current != null:
		current.set_focused(false, self)
	_focus = best
	if _focus != null:
		_focus.set_focused(true, self)
	focus_changed.emit(_focus)


func _owner_body() -> Node:
	return get_parent() if get_parent() != null else self


# ControllersLite is looked up when used instead of named. A script that names an
# autoload won't compile until the plugin that adds it is switched on, so a fresh
# install printed parse errors.
const CONTROLLERS_LITE := preload("res://addons/controller_lite/controllers_bus_lite.gd")


static func _controllers_lite() -> CONTROLLERS_LITE:
	return (Engine.get_main_loop() as SceneTree).root.get_node(^"ControllersLite") as CONTROLLERS_LITE
