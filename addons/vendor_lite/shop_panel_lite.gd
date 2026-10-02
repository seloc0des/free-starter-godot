class_name ShopPanelLite
extends Control

# Plain shop window for one VendorLite: its stock with a Buy button each, the
# player's money, and what the shop buys back from the player's bag. The Setup
# tab points area_path at the shop's ShopArea, so it opens when the player walks
# in and closes when they walk out (or press Close). It takes payment from the
# player's WalletLite and fills the player's bag, found by the "player" group.
# Vendor (Pro) has the styled ShopUI: icons, Buy/Sell tabs, several currencies.

## The VendorLite this window sells from. The Setup tab fills it in.
@export_node_path("Node") var vendor_path: NodePath
## Opens when a node in the "player" group walks into this area, closes when it leaves.
@export_node_path("Area2D", "Area3D") var area_path: NodePath
## Short messages like "+1 Potion" at the top of the screen.
@export var show_messages := true

const GROUP := &"shop_panel_lite"
const REASONS := {
	"no_wallet": "The player has no wallet to pay with.",
	"no_inventory": "The player has no bag to carry it.",
	"not_enough_funds": "Not enough %s.",
	"out_of_stock": "Sold out.",
	"item_not_owned": "You don't have that to sell.",
	"item_not_in_stock": "This shop doesn't buy that.",
	"bag_full": "Your bag is full.",
}

var _vendor: Node
var _wallet: Node  # what we listen to, so a swap gets rewired
var _bag: Node
var _title: Label
var _money: Label
var _buy_list: VBoxContainer
var _sell_list: VBoxContainer
var _reason: Label
var _warned := {}
var _dirty := false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if _unplaced():
		_place()
	_build()
	add_to_group(GROUP)
	visibility_changed.connect(_on_visibility_changed)
	var area := get_node_or_null(area_path) if area_path != NodePath("") else null
	if area != null and area.has_signal("body_entered"):
		area.body_entered.connect(_on_body_entered)
		area.body_exited.connect(_on_body_exited)
	if is_visible_in_tree():
		_on_visibility_changed()


func open() -> void:
	show()


func close() -> void:
	hide()


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		open()


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		close()


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		return
	# every shop opens in the same spot: one at a time
	for p in get_tree().get_nodes_in_group(GROUP):
		if p != self and p.visible:
			p.hide()
	_reason.text = ""
	_link()
	_refresh()


# ---- linking -------------------------------------------------------------

func _link() -> void:
	if not is_instance_valid(_vendor):
		_vendor = get_node_or_null(vendor_path) if vendor_path != NodePath("") else null
		if _vendor == null or not _vendor.has_method("link_player"):
			_vendor = null
			_warn_once("vendor", "Shop panel \"%s\" has no shop to show. Select your shopkeeper and Apply \"A shop / vendor\" in the Vendor · Setup tab." % name)
			return
		_vendor.stock_changed.connect(_queue_refresh)
		_vendor.transaction_rejected.connect(_on_rejected)
		_vendor.purchase_completed.connect(_on_bought)
		_vendor.sale_completed.connect(_on_sold)
	var why: String = _vendor.link_player()
	match why:
		"no_player":
			_warn_once(why, "Shop panel: nothing in the scene is marked as the player, so it can't find a wallet or a bag. Select your player and press \"Make the selected node the player\" in the Vendor · Setup tab.")
		"no_wallet":
			_warn_once(why, "Shop panel: the player has no wallet to pay with. Select your player and Apply \"Give the player a wallet\" in the Vendor · Setup tab.")
		"no_inventory":
			_warn_once(why, "Shop panel: the player has no bag to carry what they buy. Add one to your player, for example with the Setup tab of Inventory (Lite).")
	_listen(_vendor.get_wallet(), _vendor.get_inventory())


func _listen(wallet: Node, bag: Node) -> void:
	if wallet != _wallet:
		if is_instance_valid(_wallet) and _wallet.has_signal("balance_changed") and _wallet.is_connected("balance_changed", _on_money):
			_wallet.disconnect("balance_changed", _on_money)
		_wallet = wallet
		if _wallet != null and _wallet.has_signal("balance_changed"):
			_wallet.connect("balance_changed", _on_money)
	if bag != _bag:
		if is_instance_valid(_bag) and _bag.has_signal("contents_changed") and _bag.is_connected("contents_changed", _queue_refresh):
			_bag.disconnect("contents_changed", _queue_refresh)
		_bag = bag
		if _bag != null and _bag.has_signal("contents_changed"):
			_bag.connect("contents_changed", _queue_refresh)


func _warn_once(key: String, text: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(text)


# ---- buy / sell ----------------------------------------------------------

func _on_buy(item: Resource) -> void:
	if _vendor == null:
		return
	_reason.text = ""
	_vendor.buy(item, 1)


func _on_sell(item: Resource) -> void:
	if _vendor == null:
		return
	_reason.text = ""
	_vendor.sell(item, 1)


func _on_rejected(reason: String) -> void:
	var text: String = REASONS.get(reason, "Can't do that (%s)." % reason)
	if reason == "not_enough_funds":
		text = text % _currency()
	_reason.text = text
	_queue_refresh()


func _on_bought(item: Resource, count: int, _paid: int) -> void:
	_toast("+%d %s" % [count, _name_of(item)])


func _on_sold(item: Resource, _count: int, received: int) -> void:
	_toast("Sold %s for %d %s" % [_name_of(item), received, _currency()])


func _on_money(_total: int) -> void:
	_queue_refresh()


# ---- view ----------------------------------------------------------------

func _queue_refresh() -> void:
	# one rebuild per frame: a single buy fires stock, money and bag changes
	if _dirty:
		return
	_dirty = true
	_refresh.call_deferred()


func _refresh() -> void:
	_dirty = false
	if _buy_list == null:
		return
	for list in [_buy_list, _sell_list]:
		for c in list.get_children():
			list.remove_child(c)
			c.queue_free()
	if _vendor == null:
		_title.text = "Shop"
		_money.text = ""
		_note(_buy_list, "(no shop linked)")
		return
	var host: Node = _vendor.get_parent()
	_title.text = String(host.name) if host != null and host != get_tree().current_scene else "Shop"
	var wallet: Node = _vendor.get_wallet()
	var bag: Node = _vendor.get_inventory()
	var money := int(wallet.get_balance()) if wallet != null else 0
	_money.text = "%s: %d" % [_currency().capitalize(), money] if wallet != null else "No wallet on the player."
	if bag == null and _reason.text == "":
		_reason.text = "The player has no bag, so nothing can be bought." if wallet != null \
			else "The player has no wallet or bag, so nothing can be bought."

	var sold_here := {}
	for e in _vendor.stock:
		if not (e is Dictionary) or not (e.get("item") is Resource):
			continue
		var item: Resource = e.get("item")
		var price := int(e.get("price", 0))
		var left := int(e.get("stock", -1))
		var text := "%s  %d" % [_name_of(item), price]
		if left == 0:
			text += "  (sold out)"
		elif left > 0:
			text += "  (%d left)" % left
		var b := _row(_buy_list, text, "Buy")
		b.disabled = wallet == null or bag == null or left == 0 or money < price
		b.pressed.connect(_on_buy.bind(item))
		sold_here[_key(item)] = true
		# what the shop buys back: its own listings, only the ones the player has
		if bag != null and int(bag.count_item(item)) > 0 and not sold_here.has("sell:" + _key(item)):
			sold_here["sell:" + _key(item)] = true
			var s := _row(_sell_list, "%s x%d  %d" % [_name_of(item), int(bag.count_item(item)), int(_vendor.get_sell_price(item))], "Sell")
			s.disabled = wallet == null
			s.pressed.connect(_on_sell.bind(item))
	if bag != null and bool(_vendor.get("accept_any_sale")):
		for item in _bag_items(bag):
			if sold_here.has(_key(item)) or int(bag.count_item(item)) <= 0:
				continue
			var s := _row(_sell_list, "%s x%d  0" % [_name_of(item), int(bag.count_item(item))], "Sell")
			s.disabled = wallet == null
			s.pressed.connect(_on_sell.bind(item))
	if _buy_list.get_child_count() == 0:
		_note(_buy_list, "(nothing for sale)")
	if _sell_list.get_child_count() == 0:
		_note(_sell_list, "(nothing you can sell here)")


# Every item in the bag, whatever bag it is.
func _bag_items(bag: Node) -> Array:
	var rows: Variant = null
	if bag.has_method("slots"):
		rows = bag.slots()  # Inventory (Lite)
	elif bag.has_method("snapshot"):
		rows = bag.snapshot()  # the demo bag
	var out: Array = []
	var seen := {}
	if rows is Array:
		for s in rows:
			if s is Dictionary and s.get("item") is Resource and not seen.has(_key(s.item)):
				seen[_key(s.item)] = true
				out.append(s.item)
	elif bag.has_method("slot_count") and bag.has_method("get_item_at"):
		for i in int(bag.slot_count()):
			var it: Variant = bag.get_item_at(i)
			if it is Resource and not seen.has(_key(it)):
				seen[_key(it)] = true
				out.append(it)
	return out


func _key(item: Resource) -> String:
	var id: Variant = item.get("id")
	return str(id) if id != null and str(id) != "" else item.resource_path


func _name_of(item: Resource) -> String:
	for p in ["name", "display_name", "title", "id"]:
		var v: Variant = item.get(p)
		if v != null and str(v) != "":
			return str(v)
	return item.resource_path.get_file().get_basename()


func _currency() -> String:
	var w: Node = _vendor.get_wallet() if _vendor != null else null
	var c: Variant = w.get("currency_id") if w != null else null
	return str(c) if c != null and str(c) != "" else "gold"


func _row(list: VBoxContainer, text: String, verb: String) -> Button:
	var row := HBoxContainer.new()
	list.add_child(row)
	var l := Label.new()
	l.text = text
	l.tooltip_text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.mouse_filter = Control.MOUSE_FILTER_PASS  # so the tooltip shows
	row.add_child(l)
	var b := Button.new()
	b.text = verb
	row.add_child(b)
	return b


func _note(list: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.modulate = Color(1, 1, 1, 0.6)
	list.add_child(l)


# ---- layout --------------------------------------------------------------

func _unplaced() -> bool:
	return anchor_left == 0.0 and anchor_top == 0.0 and anchor_right == 0.0 and anchor_bottom == 0.0 \
		and offset_left == 0.0 and offset_top == 0.0 and offset_right == 0.0 and offset_bottom == 0.0


# Lower middle, same spot as Pro's shop: the corners belong to the bag, the
# paper doll and the quest log, and crafting sits top centre.
func _place() -> void:
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	anchor_top = 0.5
	offset_left = -240.0
	offset_right = 240.0
	offset_top = 0.0
	offset_bottom = -16.0


func _build() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var pad := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(pad)
	var col := VBoxContainer.new()
	pad.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	_title = Label.new()
	_title.text = "Shop"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var shut := Button.new()
	shut.text = "Close"
	shut.pressed.connect(close)
	head.add_child(shut)

	_money = Label.new()
	col.add_child(_money)

	var lists := HBoxContainer.new()
	lists.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lists.add_theme_constant_override("separation", 12)
	col.add_child(lists)
	_buy_list = _list(lists, "Buy")
	_sell_list = _list(lists, "Sell")

	_reason = Label.new()
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_reason)


func _list(parent: Node, heading: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	var h := Label.new()
	h.text = heading
	box.add_child(h)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	return rows


# ---- toast ---------------------------------------------------------------

# A short line top centre for about two seconds, stacked under any other lite's.
func _toast(text: String) -> void:
	if not show_messages or not is_inside_tree():
		return
	var y := 16.0
	for t in get_tree().get_nodes_in_group("lite_toast"):
		if t is Control and not t.is_queued_for_deletion():
			y = maxf(y, (t as Control).offset_bottom + 4.0)
	var layer := CanvasLayer.new()
	layer.layer = 100
	var l := Label.new()
	l.text = text
	l.add_to_group("lite_toast")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.anchor_left = 0.5
	l.anchor_right = 0.5
	l.offset_left = -240.0
	l.offset_right = 240.0
	l.offset_top = y
	l.offset_bottom = y + 24.0
	layer.add_child(l)
	var scene := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	scene.add_child(layer)
	get_tree().create_timer(2.0).timeout.connect(layer.queue_free)
