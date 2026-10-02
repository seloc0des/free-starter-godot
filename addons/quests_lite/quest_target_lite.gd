class_name QuestTargetLite
extends Node

# Counts toward a quest objective with no code. The Quests · Setup tab drops me
# under the thing that counts.
#   Collect: the player touches my parent (an Area2D/Area3D, or the PickupArea
#   the tab puts next to me), it counts, and my parent goes away.
#   Kill: my parent, or anything under it, sends a died signal (a Health node,
#   like the Combat pack's).

const TOAST := preload("res://addons/quests_lite/quest_toast_lite.gd")
const AREA_NAME := "PickupArea"

# same values as QuestObjectiveLite.Type
enum Type { COLLECT, KILL }

@export var type: Type = Type.COLLECT
## Matches the objective's Target Id ("herb", "slime").
@export var target_id: String = ""
## How much one pickup or one kill counts for.
@export_range(1, 999) var amount: int = 1
## Collect only: hide and free my parent once it counts.
@export var remove_when_collected := true
## Collect only: shows "+1 herb" at the top of the screen.
@export var show_messages := true

var _area: Node = null
var _collected := false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if type == Type.KILL:
		_hook_died.call_deferred()  # after the parent's own setup, in case it adds its Health late
	else:
		_hook_touch()


## Count one pickup or kill now, whatever set it off.
func report() -> void:
	var qm: Node = _manager()
	if qm == null:
		return
	if type == Type.KILL:
		qm.report_kill(target_id, amount)
	else:
		qm.report_collect(target_id, amount)


# ---- collect -------------------------------------------------------------

func _hook_touch() -> void:
	_area = _touch_area()
	if _area == null:
		push_warning("QuestTargetLite '%s': nothing to touch. Put it under an Area2D/Area3D, or Apply it again in the Quests · Setup tab to get a PickupArea." % name)
		return
	_area.connect("body_entered", _on_touched)
	_area.connect("area_entered", _on_touched)
	# the player may already be standing on it when the quest starts
	var qm: Node = _manager()
	if qm != null:
		qm.quest_started.connect(_on_quest_started)


func _on_touched(other: Node) -> void:
	if _collected or not other.is_in_group("player"):
		return
	var qm: Node = _manager()
	# nothing needs it yet, so leave it lying there for when a quest does
	if qm == null or not _wanted(qm):
		return
	report()
	if show_messages:
		TOAST.show_toast(self, "+%d %s" % [amount, _pretty(target_id)])
	if remove_when_collected:
		_collected = true
		_remove_parent()


func _on_quest_started(_quest_id: String) -> void:
	if _area == null or _collected or not _area.is_inside_tree():
		return
	for b in _area.get_overlapping_bodies():
		_on_touched(b)
	for a in _area.get_overlapping_areas():
		_on_touched(a)


func _wanted(qm: Node) -> bool:
	for q in qm.list_quests():
		var qid := String(q.id)
		if not qm.is_active(qid):
			continue
		for o in q.objectives:
			if o == null or int(o.type) != int(type) or String(o.target_id) != target_id:
				continue
			if int(qm.get_progress(qid, String(o.id))) < int(o.required):
				return true
	return false


func _remove_parent() -> void:
	var p := get_parent()
	if p == null:
		return
	# never take the whole level with it
	if p == get_tree().current_scene or p == get_tree().root:
		push_warning("QuestTargetLite '%s': it sits on the scene root, so there's nothing to remove. Put it under the pickup itself." % name)
		return
	if p is CanvasItem:
		(p as CanvasItem).hide()
	elif p is Node3D:
		(p as Node3D).hide()
	p.queue_free()


func _touch_area() -> Node:
	var p := get_parent()
	if p is Area2D or p is Area3D:
		return p
	if p != null:
		var a := p.get_node_or_null(AREA_NAME)
		if a is Area2D or a is Area3D:
			return a
	return null


# ---- kill ----------------------------------------------------------------

func _hook_died() -> void:
	var src := _died_source()
	if src == null:
		var who: String = String(get_parent().name) if get_parent() != null else String(name)
		push_warning("QuestTargetLite '%s': nothing on '%s' sends a died signal, so this never counts. Add a Health node to it (the Combat pack's Health works)." % [name, who])
		return
	# died() on the Combat packs has no arguments, but take whatever it sends
	var argc := 0
	for s in src.get_signal_list():
		if s.name == "died":
			argc = (s.args as Array).size()
			break
	src.connect("died", report.unbind(argc) if argc > 0 else report)


func _died_source() -> Node:
	var p := get_parent()
	if p == null:
		return null
	if p.has_signal("died"):
		return p
	for n in p.find_children("*", "", true, false):
		if n != self and n.has_signal("died"):
			return n
	return null


func _pretty(id: String) -> String:
	var s := id.replace("_", " ").strip_edges()
	return s if s != "" else "item"


func _manager() -> Node:
	var qm := get_node_or_null("/root/QuestsLite")
	if qm == null:
		push_warning("QuestTargetLite '%s': the QuestsLite autoload isn't running. Turn on Quests (Lite) in Project Settings > Plugins." % name)
	return qm
