extends Node

# Headless test for the Vendor Lite chooser's wiring logic (the part behind the
# Apply button). Editor-only calls (get_edited_scene_root/selection) are split out;
# this drives the pure wire_* helpers against a real scene tree and asserts the
# result is baked-in and re-entrant.
# Run: godot --headless --path . res://tools/vendor_lite/verify_chooser.tscn

const CHOOSER := preload("res://addons/vendor_lite/editor/vendor_chooser_dock.gd")

var _passes := 0
var _failures := 0


func _ready() -> void:
	await get_tree().process_frame
	print("--- vendor lite chooser verify ---")
	var dock = CHOOSER.new()  # not added to tree; we only call pure helpers
	var root := Node.new()
	root.name = "GameRoot"
	get_tree().root.add_child(root)

	# SHOP — drops a VendorLite on the target, owned by the scene root
	var target := Node.new()
	target.name = "ShopNPC"
	root.add_child(target); target.owner = root
	var shop = dock.wire_shop(root, target)
	_assert(shop != null and _is_vendor(shop), "wire_shop created a VendorLite")
	_assert(shop.get_parent() == target, "shop dropped under the selected node")
	_assert(shop.owner == root, "shop owned by scene root: bakes into the .tscn")

	# RE-ENTRANT — applying again reuses the same VendorLite, never a second one
	var shop2 = dock.wire_shop(root, target)
	_assert(shop2 == shop, "second Apply reused the same VendorLite (no duplicate)")
	_assert(_count_cls(target, "VendorLite") == 1, "exactly one VendorLite after two Applies (got %d)" % _count_cls(target, "VendorLite"))

	# WALLET — drops a WalletLite carrying the chosen starting balance
	var wallet = dock.wire_wallet(root, target, 250)
	_assert(wallet != null and _is_wallet(wallet), "wire_wallet created a WalletLite")
	_assert(int(wallet.get("starting_balance")) == 250, "wallet carries the chosen starting balance (got %d)" % int(wallet.get("starting_balance")))
	_assert(wallet.owner == root, "wallet owned by scene root")
	# re-entrant + option preserved: re-apply with a new balance updates in place
	var wallet2 = dock.wire_wallet(root, target, 500)
	_assert(wallet2 == wallet, "second wallet Apply reused the same node")
	_assert(int(wallet2.get("starting_balance")) == 500, "re-apply updated the starting balance in place (got %d)" % int(wallet2.get("starting_balance")))
	_assert(_count_cls(target, "WalletLite") == 1, "exactly one WalletLite after two Applies (got %d)" % _count_cls(target, "WalletLite"))

	# SCENE-ROOT scope — dropping onto the root itself works (target == root)
	var root_only := Node.new()
	get_tree().root.add_child(root_only)
	var shop_on_root = dock.wire_shop(root_only, root_only)
	_assert(shop_on_root.get_parent() == root_only and shop_on_root.owner == root_only, "scene-root scope drops the component on the root, owned by it")
	root_only.queue_free()

	# SHOP + WALLET — both dropped, and the vendor's wallet_path points at the sibling
	var pair_root := Node.new()
	get_tree().root.add_child(pair_root)
	var pair_target := Node.new()
	pair_root.add_child(pair_target); pair_target.owner = pair_root
	var vendor = dock.wire_shop_and_wallet(pair_root, pair_target, 300)
	_assert(_is_vendor(vendor), "shop+wallet returned the VendorLite")
	var wpath: NodePath = vendor.get("wallet_path")
	var linked_wallet: Node = vendor.get_node_or_null(wpath)
	_assert(linked_wallet != null and _is_wallet(linked_wallet), "vendor's wallet_path resolves to a WalletLite sibling")
	_assert(int(linked_wallet.get("starting_balance")) == 300, "paired wallet carries the chosen balance (got %d)" % int(linked_wallet.get("starting_balance")))
	# re-entrant: applying the pair again reuses both nodes
	var vendor2 = dock.wire_shop_and_wallet(pair_root, pair_target, 300)
	_assert(vendor2 == vendor, "second shop+wallet Apply reused the vendor")
	_assert(_count_cls(pair_target, "VendorLite") == 1 and _count_cls(pair_target, "WalletLite") == 1, "shop+wallet stays a single pair after two Applies")
	pair_root.queue_free()

	# OWNERSHIP — a VendorLite inside an instanced sub-scene (owner != root) must NOT
	# be hijacked; Apply should make a fresh one the scene actually owns. Fresh root so
	# the ONLY VendorLite present is the non-owned, buried one.
	var root2 := Node.new()
	get_tree().root.add_child(root2)
	var sub := Node.new()
	root2.add_child(sub); sub.owner = root2
	var buried = load("res://addons/vendor_lite/vendor_lite.gd").new()
	sub.add_child(buried); buried.owner = sub  # owned by the sub-scene, not root2
	var fresh = dock.wire_shop(root2, root2)
	_assert(fresh != buried, "did not hijack a VendorLite owned by a sub-scene")
	_assert(fresh.owner == root2, "made a fresh VendorLite the scene root owns")
	root2.queue_free()

	root.queue_free()
	print("--- %d passed, %d failed ---" % [_passes, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


# ---- helpers -------------------------------------------------------------

func _is_vendor(n: Node) -> bool:
	var scr: Script = n.get_script()
	return scr != null and scr.get_global_name() == "VendorLite"


func _is_wallet(n: Node) -> bool:
	var scr: Script = n.get_script()
	return scr != null and scr.get_global_name() == "WalletLite"


func _count_cls(parent: Node, cls: String) -> int:
	var n := 0
	for c in parent.get_children():
		var scr: Script = c.get_script()
		if scr != null and scr.get_global_name() == cls:
			n += 1
	return n


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
		print("PASS: " + msg)
	else:
		_failures += 1
		printerr("FAIL: " + msg)
