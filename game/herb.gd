extends Area2D

# A herb pickup. Dim and inert until the gather quest starts (so the loop reads
# talk -> collect), then walk over it to collect. Collected state saves.

@export var herb_id: String = "herb_1"
@export var item: ItemLite
@export var bag_path: NodePath

var _collected: bool = false
var _active: bool = false


func _ready() -> void:
	add_to_group("save_load_contract_lite")
	monitoring = false
	modulate.a = 0.35
	body_entered.connect(_on_body_entered)
	QuestsLite.quest_started.connect(_on_quest_started)


func _on_quest_started(id: String) -> void:
	if id == "gather_herbs":
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
	var bag := get_node_or_null(bag_path)
	if bag != null and item != null:
		bag.add_item(item, 1)
	GameEvents.item_collected.emit("herb", 1)
	visible = false
	set_deferred("monitoring", false)


# --- lite Save contract ---
func get_save_id() -> String:
	return herb_id


func save_state() -> Dictionary:
	return {"collected": _collected}


func load_state(data: Dictionary) -> void:
	# `== true` rather than bool(): bool(null) is a hard error, and a save with a
	# null in it would abort here and leave the herb in whatever state it spawned.
	_collected = data.get("collected", false) == true
	if _collected:
		_active = false
		visible = false
		set_deferred("monitoring", false)
	else:
		# restore an uncollected herb; active only if the gather quest is running
		var quest_on := QuestsLite.is_active("gather_herbs")
		visible = true
		_active = quest_on
		modulate.a = 1.0 if quest_on else 0.35
		set_deferred("monitoring", quest_on)
