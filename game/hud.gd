extends CanvasLayer

# HUD: an objective line, a live herb-bag count, and Save/Load. The dialogue box
# lives here too (added in the scene) so conversations overlay the world.

@onready var _status: Label = $Bar/Status
@onready var _herbs: Label = $Bar/Herbs

@export var bag_path: NodePath


func _ready() -> void:
	# don't let the buttons grab keyboard focus, or Space would press them
	# instead of talking to the NPC
	$Bar/Save.focus_mode = Control.FOCUS_NONE
	$Bar/Load.focus_mode = Control.FOCUS_NONE
	$Bar/Save.pressed.connect(func() -> void: SaveLite.save())
	$Bar/Load.pressed.connect(func() -> void: SaveLite.load())
	_status.text = "Find the Healer. Walk up and press Space."
	QuestsLite.quest_started.connect(func(_id: String): _status.text = "Gather 3 green flasks. They just lit up.")
	QuestsLite.objective_progressed.connect(func(_q: String, _o: String, c: int, r: int): _status.text = "Gathered %d of %d." % [c, r])
	QuestsLite.quest_completed.connect(func(_id: String): _status.text = "Quest complete. You made a game loop.")

	var bag := get_node_or_null(bag_path) as InventoryLite
	if bag != null:
		bag.contents_changed.connect(func() -> void: _herbs.text = "Herbs: %d" % bag.count_item(preload("res://game/items/herb.tres")))
