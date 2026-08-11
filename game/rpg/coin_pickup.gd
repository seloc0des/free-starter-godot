extends Area2D

# A coin on the cobbles. Lights up when the gear quest starts; walk over it and
# it lands in your wallet AND counts for the quest. Collected state saves.

@export var value: int = 1
@export var pickup_id: String = "coin_1"
@export var quest_id: String = "gear_up"
@export var wallet_path: NodePath

var _collected: bool = false
var _active: bool = false


func _ready() -> void:
	add_to_group("save_load_contract_lite")
	monitoring = false
	modulate.a = 0.35
	body_entered.connect(_on_body_entered)
	QuestsLite.quest_started.connect(_on_quest_started)
	# the chassis autostarts the quest before this scene loads
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
	var wallet := get_node_or_null(wallet_path) as WalletLite
	if wallet != null:
		wallet.add(value)
	GameEvents.item_collected.emit("coin", 1)
	visible = false
	set_deferred("monitoring", false)


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
