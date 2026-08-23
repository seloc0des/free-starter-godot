extends Area2D

# The market stall. Walk up and the shopkeeper talks (Dialogue Lite). Choosing
# to buy fires a `buy_sword` event; this script runs the real Vendor Lite
# transaction, which deposits the sword into the satchel (Inventory Lite) and
# hands it to the player's Equipment. Sold state saves.

@export var vendor_path: NodePath
@export var sword_item: ItemLite
@export var dialogue_id: String = "shopkeeper"

@onready var _prompt: Label = $Prompt

var _sold: bool = false
var _vendor: VendorLite = null


func _ready() -> void:
	add_to_group("save_load_contract_lite")
	_prompt.visible = false
	# Wire the touch and dialogue signals before anything that can fail, so a
	# misconfigured stall still talks instead of standing there completely dead.
	DialoguesLite.event_fired.connect(_on_dialogue_event)
	body_entered.connect(_on_body_entered)
	body_exited.connect(func(_b: Node) -> void: _prompt.visible = false)

	_vendor = get_node_or_null(vendor_path) as VendorLite
	# get_node_or_null and then straight into _vendor.purchase_completed: move
	# the Vendor node in the scene and that aborted the rest of _ready, so the
	# stall never connected anything and the shopkeeper never said a word.
	if _vendor == null:
		push_error("[stall] vendor_path doesn't point at a VendorLite node, so nothing can be bought here")
		return
	_vendor.purchase_completed.connect(_on_purchase)


func _on_body_entered(b: Node) -> void:
	if _sold or not b.is_in_group("player") or DialoguesLite.is_active():
		return
	DialoguesLite.start(dialogue_id)


func _on_dialogue_event(event_id: String) -> void:
	if event_id != "buy_sword" or _sold:
		return
	if _vendor == null or not _vendor.buy(sword_item):
		_prompt.visible = true


func _on_purchase(item: Resource, _count: int, _paid: int) -> void:
	# item is typed Resource on purpose, so a custom item type need not carry an
	# id at all. String(null) throws, and the throw skipped the equip below, which
	# meant the player had paid and got nothing back.
	var raw: Variant = item.get("id") if item != null else null
	if _sold or raw == null or String(raw) != "sword":
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
	# `== true` rather than bool(): bool(null) throws instead of giving false.
	_sold = data.get("sold", false) == true
