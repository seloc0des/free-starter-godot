extends CanvasLayer

# HUD: an objective line + Save/Load. The dialogue box lives here too (added in the
# scene) so conversations overlay the world.

@onready var _status: Label = $Bar/Status


func _ready() -> void:
	# don't let the buttons grab keyboard focus, or Space would press them
	# instead of talking to the NPC
	$Bar/Save.focus_mode = Control.FOCUS_NONE
	$Bar/Load.focus_mode = Control.FOCUS_NONE
	$Bar/Save.pressed.connect(func() -> void: SaveLite.save())
	$Bar/Load.pressed.connect(func() -> void: SaveLite.load())
	_status.text = "Find the Healer (green) — walk up and press Space."
	QuestsLite.quest_started.connect(func(_id: String): _status.text = "Gather 3 herbs — they just lit up.")
	QuestsLite.objective_progressed.connect(func(_q: String, _o: String, c: int, r: int): _status.text = "Herbs: %d / %d" % [c, r])
	QuestsLite.quest_completed.connect(func(_id: String): _status.text = "Quest complete! Nice — you made a game loop.")
