class_name CraftingLite
extends Node

# Shapeless instant-craft. Bind any duck-typed inventory with
# `has_item(item, n)`, `remove_item(item, n)`, `add_item(item, n)`. Pair with
# Inventory — Lite for the smoothest experience.
#
# Cut from Pro:
#   * Shaped (grid) recipes
#   * Timed crafting (per-recipe duration)
#   * Multi-slot craft queue
#   * Recipe unlock progression + level requirement
#   * Station id gating (recipes only craftable at the forge / cookpot / etc.)
#   * Drop-in browser UI
#   * Shared Events bus
#   * Save-contract auto-join

signal recipes_changed
# Named `craft_completed` to match the Pro CraftingComponent signal so Lite→Pro
# upgrades don't have to rewrite every listener. The legacy `crafted` alias is
# kept emitting in parallel so existing Lite consumers keep working.
signal craft_completed(recipe: Resource, outputs: Array)
signal crafted(recipe: Resource, outputs: Array)
signal craft_failed(recipe: Resource, reason: String)

@export var recipes: Array = []  # Array of RecipeLite Resources
@export_node_path("Node") var inventory_path: NodePath

const REASON_MISSING_INPUTS := "missing_inputs"
const REASON_NO_INVENTORY := "no_inventory_bound"
const REASON_NOT_A_RECIPE := "not_a_recipe"

var _inventory: Node


func _ready() -> void:
	if inventory_path != NodePath(""):
		_inventory = get_node_or_null(inventory_path)


func bind_inventory(node: Node) -> void:
	_inventory = node


func add_recipe(recipe: RecipeLite) -> void:
	if recipe == null or recipes.has(recipe):
		return
	recipes.append(recipe)
	recipes_changed.emit()


## Returns "" if the player can craft the recipe, otherwise a reason code.
func block_reason(recipe: RecipeLite) -> String:
	if recipe == null:
		return REASON_NOT_A_RECIPE
	if _inventory == null:
		return REASON_NO_INVENTORY
	for inp in recipe.inputs:
		if not (inp is Dictionary):
			continue
		var item: Resource = inp.get("item")
		var count: int = int(inp.get("count", 1))
		if item == null:
			continue
		if not _inventory.has_method("has_item") or not _inventory.has_item(item, count):
			return REASON_MISSING_INPUTS
	return ""


func can_craft(recipe: RecipeLite) -> bool:
	return block_reason(recipe) == ""


func craft(recipe: RecipeLite) -> bool:
	var reason := block_reason(recipe)
	if reason != "":
		craft_failed.emit(recipe, reason)
		return false
	# Consume inputs.
	for inp in recipe.inputs:
		var in_item: Resource = inp.get("item")
		var in_count: int = int(inp.get("count", 1))
		if in_item != null and _inventory.has_method("remove_item"):
			_inventory.remove_item(in_item, in_count)
	# Produce outputs.
	for outp in recipe.outputs:
		var out_item: Resource = outp.get("item")
		var out_count: int = int(outp.get("count", 1))
		if out_item != null and _inventory.has_method("add_item"):
			_inventory.add_item(out_item, out_count)
	# Emit both signal names so listeners hooked to either still fire.
	craft_completed.emit(recipe, recipe.outputs)
	crafted.emit(recipe, recipe.outputs)
	return true
