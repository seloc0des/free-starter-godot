class_name VendorLite
extends Node

# Single-currency vendor. Bind a duck-typed inventory and a WalletLite. Stock
# is a flat Array of Dictionaries: `{item, price, stock}` (stock = -1 means
# unlimited). Buy and sell are symmetric — sell price defaults to `price`
# unless `sell_price` is set explicitly per entry.
#
# Cut from Pro:
#   * Multi-currency wallets
#   * Buyback ratio (separate buy and sell prices automatically)
#   * Restock timers (`restock_seconds`)
#   * Conditional offers (flag / level / quest gates)
#   * Timed offers (`available_until`)
#   * Category-only sell-back filtering (e.g. junk-only NPC trade-in)
#   * Styled `ShopUI` (icons, Buy/Sell tabs). Lite has the plain ShopPanelLite.
#   * Shared `Events` autoload + save-contract auto-join

signal purchase_completed(item: Resource, count: int, paid: int)
signal sale_completed(item: Resource, count: int, received: int)
signal transaction_rejected(reason: String)
signal stock_changed

@export_node_path("Node") var wallet_path: NodePath
@export_node_path("Node") var inventory_path: NodePath
## Stock entries: {item: Resource, price: int, stock: int, sell_price?: int}
@export var stock: Array = []
## If true, players can sell ANY item they own back. If false, only items
## currently listed in `stock` can be sold (and only at their `sell_price`).
@export var accept_any_sale: bool = false

const REASON_NO_WALLET := "no_wallet"
const REASON_NO_INVENTORY := "no_inventory"
const REASON_NO_FUNDS := "not_enough_funds"
const REASON_OUT_OF_STOCK := "out_of_stock"
const REASON_NOT_OWNED := "item_not_owned"
const REASON_NOT_LISTED := "item_not_in_stock"
const REASON_BAG_FULL := "bag_full"
const REASON_NO_PLAYER := "no_player"

var _wallet: Node
var _inventory: Node


func _ready() -> void:
	if wallet_path != NodePath(""):
		_wallet = get_node_or_null(wallet_path)
	if inventory_path != NodePath(""):
		_inventory = get_node_or_null(inventory_path)


func bind_wallet(node: Node) -> void:
	_wallet = node


func bind_inventory(node: Node) -> void:
	_inventory = node


func get_wallet() -> Node:
	return _wallet if is_instance_valid(_wallet) else null


func get_inventory() -> Node:
	return _inventory if is_instance_valid(_inventory) else null


## Binds the player's wallet and bag when nothing else has: the first node in the
## "player" group, then the first node on or under it with the right methods.
## Wallet Path / Inventory Path (or bind_*) still win. Returns "" when both are
## bound, else what's missing: no_player, no_wallet or no_inventory.
func link_player() -> String:
	if get_wallet() == null or get_inventory() == null:
		var player: Node = get_tree().get_first_node_in_group("player") if is_inside_tree() else null
		if player == null:
			return REASON_NO_PLAYER
		if get_wallet() == null:
			_wallet = _find_with(player, ["get_balance", "has_amount", "subtract", "add"])
		if get_inventory() == null:
			_inventory = _find_with(player, ["add_item", "remove_item", "count_item"])
	if get_wallet() == null:
		return REASON_NO_WALLET
	if get_inventory() == null:
		return REASON_NO_INVENTORY
	return ""


func buy(item: Resource, count: int = 1) -> bool:
	if _wallet == null:
		_reject(REASON_NO_WALLET); return false
	if _inventory == null:
		_reject(REASON_NO_INVENTORY); return false
	var entry := _find_entry(item)
	if entry.is_empty():
		_reject(REASON_OUT_OF_STOCK); return false
	if int(entry.get("stock", -1)) >= 0 and int(entry.stock) < count:
		_reject(REASON_OUT_OF_STOCK); return false
	var unit_price := int(entry.get("price", 0))
	var total := unit_price * count
	if not _wallet.has_amount(total):
		_reject(REASON_NO_FUNDS); return false
	# Only call subtract if there's actually something to deduct — WalletLite
	# rejects amount <= 0, which would misfire as REASON_NO_FUNDS for free items.
	if total > 0 and not _wallet.subtract(total):
		_reject(REASON_NO_FUNDS); return false
	if int(entry.get("stock", -1)) >= 0:
		entry.stock = int(entry.stock) - count
	if _inventory.has_method("add_item"):
		var left: Variant = _inventory.add_item(item, count)
		# A full bag hands back what didn't fit. Undo the sale rather than keep the gold.
		if typeof(left) == TYPE_INT and int(left) > 0:
			if int(left) < count and _inventory.has_method("remove_item"):
				_inventory.remove_item(item, count - int(left))
			if total > 0:
				_wallet.add(total)
			if int(entry.get("stock", -1)) >= 0:
				entry.stock = int(entry.stock) + count
			_reject(REASON_BAG_FULL); return false
	purchase_completed.emit(item, count, total)
	stock_changed.emit()
	return true


func sell(item: Resource, count: int = 1) -> bool:
	if _wallet == null:
		_reject(REASON_NO_WALLET); return false
	if _inventory == null:
		_reject(REASON_NO_INVENTORY); return false
	if not (_inventory.has_method("has_item") and _inventory.has_item(item, count)):
		_reject(REASON_NOT_OWNED); return false
	var entry := _find_entry(item)
	var unit_price := 0
	if not entry.is_empty():
		unit_price = int(entry.get("sell_price", entry.get("price", 0)))
	elif not accept_any_sale:
		_reject(REASON_NOT_LISTED); return false
	# (else: accept_any_sale on an unlisted item — unit_price stays 0)
	var total := unit_price * count
	if _inventory.has_method("remove_item"):
		_inventory.remove_item(item, count)
	if total > 0:
		_wallet.add(total)
	if not entry.is_empty() and int(entry.get("stock", -1)) >= 0:
		entry.stock = int(entry.stock) + count
	sale_completed.emit(item, count, total)
	stock_changed.emit()
	return true


# ---- inspection ----------------------------------------------------------

func get_price(item: Resource) -> int:
	var entry := _find_entry(item)
	return int(entry.get("price", 0))


func get_sell_price(item: Resource) -> int:
	var entry := _find_entry(item)
	if entry.is_empty():
		return 0
	return int(entry.get("sell_price", entry.get("price", 0)))


func get_stock(item: Resource) -> int:
	var entry := _find_entry(item)
	if entry.is_empty():
		return -1
	return int(entry.get("stock", -1))


# ---- internals -----------------------------------------------------------

# Returns the matching stock entry Dictionary, or an empty Dictionary on miss.
# Callers check `.is_empty()` — GDScript-typed returns can't be null without
# the caller widening to Variant, and the empty-Dict sentinel is enough.
func _find_entry(item: Resource) -> Dictionary:
	if item == null:
		return {}
	for e in stock:
		if not (e is Dictionary):
			continue
		var entry_item: Resource = e.get("item")
		if entry_item == null:
			continue
		if String(entry_item.id) == String(item.id):
			return e
	return {}


func _reject(reason: String) -> void:
	transaction_rejected.emit(reason)


# The node itself, then its children, depth first.
func _find_with(node: Node, methods: Array) -> Node:
	var ok := true
	for m in methods:
		if not node.has_method(m):
			ok = false
			break
	if ok:
		return node
	for c in node.get_children():
		var f := _find_with(c, methods)
		if f != null:
			return f
	return null
