class_name QuestBoardLite
extends Node

# Gives the player a quest with no code: as soon as the scene starts, or the
# first time the player touches my parent (an Area2D/Area3D, or the QuestArea the
# Quests · Setup tab puts next to me). It registers the quest itself, so any
# QuestLite .tres works.

const TOAST := preload("res://addons/quests_lite/quest_toast_lite.gd")
const AREA_NAME := "QuestArea"

enum StartMode {
	ON_SCENE_START,  ## as soon as the scene starts
	ON_PLAYER_TOUCH,  ## the first time the player touches my Area2D/Area3D parent or the QuestArea next to me
}

## The quest to give (a QuestLite .tres).
@export var quest: QuestLite
@export var start_mode: StartMode = StartMode.ON_SCENE_START
## Shows "Quest started: <title>" at the top of the screen.
@export var show_messages := true

var _given := false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var qm: Node = _manager()
	if qm == null:
		return
	if quest == null:
		push_warning("QuestBoardLite '%s': no quest picked. Pick one in the Quests · Setup tab, or drag a quest onto its Quest field." % name)
		return
	if String(quest.id) == "":
		push_warning("QuestBoardLite '%s': its quest has no id, so it can't start. Give it one in the Quests (Lite) tab." % name)
		return
	# something else may have registered it (and started it) already, and
	# register() would wipe that progress
	if not qm.is_registered(String(quest.id)):
		qm.register(quest)
	if start_mode == StartMode.ON_SCENE_START:
		give.call_deferred()  # deferred so the tracker is listening first
		return
	var area := _touch_area()
	if area == null:
		push_warning("QuestBoardLite '%s': it starts on touch, but there's nothing to touch. Put it under an Area2D/Area3D, or Apply it again in the Quests · Setup tab to get a QuestArea." % name)
		return
	area.connect("body_entered", _on_touched)
	area.connect("area_entered", _on_touched)


## Give the quest now, whatever the start mode. Does nothing if it's already
## active or done.
func give() -> void:
	var qm: Node = _manager()
	if qm == null or quest == null or String(quest.id) == "":
		return
	if not qm.is_registered(String(quest.id)):
		qm.register(quest)
	if qm.start_quest(String(quest.id)):
		_given = true
		if show_messages:
			TOAST.show_toast(self, "Quest started: %s" % _title())


func _on_touched(other: Node) -> void:
	if _given or not other.is_in_group("player"):
		return
	give()


func _touch_area() -> Node:
	var p := get_parent()
	if p is Area2D or p is Area3D:
		return p
	if p != null:
		var a := p.get_node_or_null(AREA_NAME)
		if a is Area2D or a is Area3D:
			return a
	return null


func _title() -> String:
	return String(quest.title) if String(quest.title) != "" else String(quest.id)


func _manager() -> Node:
	var qm := get_node_or_null("/root/QuestsLite")
	if qm == null:
		push_warning("QuestBoardLite '%s': the QuestsLite autoload isn't running. Turn on Quests (Lite) in Project Settings > Plugins." % name)
	return qm
