extends Area2D

# The camp spot, marked by a sign. Registers the chest recipe with Crafting
# Lite, and when the player walks up carrying enough wood, crafts it: wood
# leaves the bag, the chest appears by the sign, and the quest hears about it.

@export var crafting_path: NodePath
@export var wood_item: ItemLite
@export var chest_item: ItemLite
@export var wood_needed: int = 3

@onready var _chest_sprite: Sprite2D = $Chest
@onready var _prompt: Label = $Prompt

var _crafted: bool = false
var _crafting: CraftingLite = null
var _recipe: RecipeLite = null


func _ready() -> void:
	add_to_group("save_load_contract_lite")
	_chest_sprite.visible = false
	_prompt.visible = false
	# Wire the touch signals before anything that can fail, so a misconfigured
	# camp spot still reacts to the player instead of sitting there inert.
	body_entered.connect(_on_body_entered)
	body_exited.connect(func(_b: Node) -> void: _prompt.visible = false)

	_crafting = get_node_or_null(crafting_path) as CraftingLite
	# get_node_or_null and then straight into _crafting.add_recipe: move the
	# Crafting node in the scene and that aborted the rest of _ready, so the camp
	# spot silently did nothing for the whole game.
	if _crafting == null:
		push_error("[camp] crafting_path doesn't point at a CraftingLite node, so the camp spot can't craft")
		return

	_recipe = RecipeLite.new()
	_recipe.id = "camp_chest"
	_recipe.title = "Camp Chest"
	_recipe.inputs = [{"item": wood_item, "count": wood_needed}]
	_recipe.outputs = [{"item": chest_item, "count": 1}]
	_crafting.add_recipe(_recipe)
	_crafting.crafted.connect(_on_crafted)


func _on_body_entered(b: Node) -> void:
	if _crafted or not b.is_in_group("player"):
		return
	if _crafting == null or _recipe == null:
		_prompt.visible = true      # nothing to craft with, but say something
		return
	if _crafting.can_craft(_recipe):
		_crafting.craft(_recipe)
	else:
		_prompt.visible = true


func _on_crafted(recipe: Resource, _outputs: Array) -> void:
	if recipe.id != "camp_chest" or _crafted:
		return
	_crafted = true
	_prompt.visible = false
	_chest_sprite.visible = true
	GameEvents.item_collected.emit("camp_chest", 1)


# --- lite Save contract ---
func get_save_id() -> String:
	return "camp_station"


func save_state() -> Dictionary:
	return {"crafted": _crafted}


func load_state(data: Dictionary) -> void:
	# `== true` rather than bool(): bool(null) throws instead of giving false, and
	# the throw aborts load_state, leaving this one node stuck as it spawned.
	_crafted = data.get("crafted", false) == true
	_chest_sprite.visible = _crafted
