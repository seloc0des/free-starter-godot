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
	QuestsLite.quest_started.connect(func(id: String): _status.text = "Gather %s green flasks. They just lit up." % _goal(id))
	QuestsLite.objective_progressed.connect(func(_q: String, _o: String, c: int, r: int): _status.text = "Gathered %d of %d." % [c, r])
	QuestsLite.quest_completed.connect(func(_id: String): _status.text = "Quest complete. You made a game loop.")

	var bag := get_node_or_null(bag_path) as InventoryLite
	if bag != null:
		bag.contents_changed.connect(func() -> void: _herbs.text = "Herbs: %d" % bag.count_item(preload("res://game/items/herb.tres")))


# How many the quest asks for, read from content/quests.json through the quest
# manager, so an edited goal shows here too. It used to say 3 whatever the file said.
func _goal(quest_id: String) -> String:
	var qm := get_node_or_null("/root/QuestsLite")
	if qm != null:
		for q in qm.list_quests():
			if String(q.id) == quest_id and not q.objectives.is_empty():
				return str(int(q.objectives[0].required))
	return "the"
