extends CharacterBody2D

# Top-down player. Arrows / WASD to move; movement freezes during dialogue. Saves
# its position via the lite Save contract.

@export var speed: float = 150.0


func _ready() -> void:
	add_to_group("player")
	add_to_group("save_load_contract_lite")


func _physics_process(_delta: float) -> void:
	if DialoguesLite.is_active():
		velocity = Vector2.ZERO
		return
	var dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = dir * speed
	move_and_slide()


# --- lite Save contract ---
func get_save_id() -> String:
	return "player"


func save_state() -> Dictionary:
	return {"x": global_position.x, "y": global_position.y}


func load_state(data: Dictionary) -> void:
	global_position = Vector2(float(data.get("x", global_position.x)), float(data.get("y", global_position.y)))
