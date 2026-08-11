class_name InteractorLite
extends Area2D

# "Press E" reach. Add under the player body. Focuses the nearest enabled
# InteractableLite in reach and interacts on the action press.

signal focus_changed(interactable: Node)     # null when nothing in reach

@export var action: StringName = &"ui_accept"
@export var enabled: bool = true

var _in_reach: Array[InteractableLite] = []
var _focus: InteractableLite = null


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


func _physics_process(_delta: float) -> void:
	# nearest can change while walking, and the focus can disable itself
	if not _in_reach.is_empty():
		_refresh_focus()


func _unhandled_input(event: InputEvent) -> void:
	if enabled and _focus != null and event.is_action_pressed(action):
		interact()


func interact() -> void:
	if enabled and _focus != null:
		_focus.interact(_owner_body())


func current_focus() -> InteractableLite:
	return _focus


func _on_area_entered(area: Area2D) -> void:
	if area is InteractableLite and not _in_reach.has(area):
		_in_reach.append(area)
		_refresh_focus()


func _on_area_exited(area: Area2D) -> void:
	_in_reach.erase(area)
	_refresh_focus()


func _refresh_focus() -> void:
	var best: InteractableLite = null
	var best_d := INF
	for a in _in_reach:
		if not is_instance_valid(a) or not a.enabled:
			continue
		var d := global_position.distance_squared_to(a.global_position)
		if d < best_d:
			best_d = d
			best = a
	if best == _focus:
		return
	if _focus != null and is_instance_valid(_focus):
		_focus.set_focused(false)
	_focus = best
	if _focus != null:
		_focus.set_focused(true)
	focus_changed.emit(_focus)


func _owner_body() -> Node:
	return get_parent() if get_parent() != null else self
