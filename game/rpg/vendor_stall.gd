extends Area2D

# The market stall. Vendor Lite holds the stock and the wallet binding; this
# script is the walk-up: enough gold buys the sword and hands it straight to
# the player's Equipment. Sold state saves.

@export var vendor_path: NodePath
@export var sword_item: ItemLite

@onready var _prompt: Label = $Prompt

var _sold: bool = false
var _vendor: VendorLite = null


func _ready() -> void:
	add_to_group("save_load_contract_lite")
	_prompt.visible = false
	_vendor = get_node_or_null(vendor_path) as VendorLite
	_vendor.purchase_completed.connect(_on_purchase)
	body_entered.connect(_on_body_entered)
	body_exited.connect(func(_b: Node) -> void: _prompt.visible = false)


func _on_body_entered(b: Node) -> void:
	if _sold or not b.is_in_group("player"):
		return
	if not _vendor.buy(sword_item):
		_prompt.visible = true


func _on_purchase(item: Resource, _count: int, _paid: int) -> void:
	if _sold or String(item.get("id")) != "sword":
		return
	_sold = true
	_prompt.visible = false
	GameEvents.item_collected.emit("sword", 1)
	for p in get_tree().get_nodes_in_group("player"):
		if p.has_node("Equipment"):
			p.get_node("Equipment").try_equip(sword_item)
			break


# --- lite Save contract ---
func get_save_id() -> String:
	return "vendor_stall"


func save_state() -> Dictionary:
	return {"sold": _sold}


func load_state(data: Dictionary) -> void:
	_sold = bool(data.get("sold", false))
