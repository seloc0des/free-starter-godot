extends Area2D

# A forageable: firewood on the ground, mushrooms at a tree's foot. Dim and
# inert until the camp quest starts, then walk over it to gather. Goes into
# the camp bag (Inventory Lite) AND counts for the quest. Gathered state saves.

@export var item: ItemLite
@export var pickup_id: String = "pickup_1"
@export var quest_id: String = "make_camp"
@export var bag_path: NodePath

var _collected: bool = false
var _active: bool = false


func _ready() -> void:
	add_to_group("save_load_contract_lite")
	monitoring = false
	modulate.a = 0.35
	body_entered.connect(_on_body_entered)
	QuestsLite.quest_started.connect(_on_quest_started)
	# the chassis autostarts the camp quest before this scene loads
	if QuestsLite.is_active(quest_id):
		_enable()


func _on_quest_started(id: String) -> void:
	if id == quest_id:
		_enable()


func _enable() -> void:
	if _collected:
		return
	_active = true
	modulate.a = 1.0
	set_deferred("monitoring", true)


func _on_body_entered(b: Node) -> void:
	if _active and not _collected and b.is_in_group("player"):
		_collect()


func _collect() -> void:
	_collected = true
	_active = false
	var amount := _forage_amount()
	var bag := get_node_or_null(bag_path)
	if bag != null and item != null:
		bag.add_item(item, amount)
	GameEvents.item_collected.emit(item.id if item != null else pickup_id, amount)
	visible = false
	set_deferred("monitoring", false)


# How much a single gather brings back — the player's Foraging stat if they have
# one (the rake raises it), otherwise 1.
func _forage_amount() -> int:
	for p in get_tree().get_nodes_in_group("player"):
		if p.has_node("Stats"):
			return maxi(1, int(p.get_node("Stats").get_stat("foraging")))
	return 1


# --- lite Save contract ---
func get_save_id() -> String:
	return pickup_id


func save_state() -> Dictionary:
	return {"collected": _collected}


func load_state(data: Dictionary) -> void:
	_collected = bool(data.get("collected", false))
	if _collected:
		_active = false
		visible = false
		set_deferred("monitoring", false)
	else:
		var quest_on := QuestsLite.is_active(quest_id)
		visible = true
		_active = quest_on
		modulate.a = 1.0 if quest_on else 0.35
		set_deferred("monitoring", quest_on)
