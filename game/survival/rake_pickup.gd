extends Area2D

# The forager's rake, lying in the clearing. Walk over it and it equips into the
# player's Equipment weapon_main slot, which raises Foraging from 1 to 2 through
# a Stats modifier. After that, every gather brings back double. Picked-up state
# saves.

@export var item: ItemLite

var _taken: bool = false


func _ready() -> void:
	add_to_group("save_load_contract_lite")
	var sprite := Sprite2D.new()
	sprite.texture = item.icon if item != null else null
	add_child(sprite)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(14, 14)
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)
	body_entered.connect(_on_body_entered)


func _on_body_entered(b: Node) -> void:
	if _taken or not b.is_in_group("player") or not b.has_node("Equipment"):
		return
	b.get_node("Equipment").try_equip(item)
	_taken = true
	visible = false
	set_deferred("monitoring", false)


# --- lite Save contract ---
func get_save_id() -> String:
	return "rake"


func save_state() -> Dictionary:
	return {"taken": _taken}


func load_state(data: Dictionary) -> void:
	_taken = bool(data.get("taken", false))
	if _taken:
		visible = false
		set_deferred("monitoring", false)
