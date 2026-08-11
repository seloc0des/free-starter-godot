extends Node

# ControllersLite global bus: THE player reference, interactions, and
# reason-counted movement locks (dialogue + cutscene can overlap safely).

signal player_registered(body: Node)
# Emitted by Interactor rather than from here, so the compiler can't see a use
# and warns. Silenced so a buyer's debugger stays clean on first run.
@warning_ignore("unused_signal")
signal interacted(interactable: Node, by: Node)
signal movement_locked_changed(locked: bool)

var player: Node = null

var _lock_reasons: Dictionary = {}


func register_player(body: Node) -> void:
	player = body
	player_registered.emit(body)


func lock_movement(reason: StringName = &"default") -> void:
	var was := is_locked()
	_lock_reasons[reason] = true
	if not was:
		movement_locked_changed.emit(true)


func unlock_movement(reason: StringName = &"default") -> void:
	if not _lock_reasons.erase(reason):
		return
	if _lock_reasons.is_empty():
		movement_locked_changed.emit(false)


func is_locked() -> bool:
	return not _lock_reasons.is_empty()
