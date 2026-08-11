@tool
class_name StarterPlan
extends RefCounted

# The data behind the Start Here dock. Kept free of EditorInterface on purpose so
# the headless suite can drive it: everything takes the project state as an
# argument instead of reaching for it.
#
# Why the docks aren't all switched on out of the box: every Lite pack puts its
# dock in the same slot as the Inspector. Fourteen of them is twenty tabs, and
# Godot answers that by hiding the lot behind two overflow arrows. So we ship
# with the three the story game runs on, and this list turns the rest on one at
# a time, when the buyer asks for it.

const SYSTEMS: Array[Dictionary] = [
	{"id": "dialogue_lite", "label": "Dialogue", "in_story": true,
	 "does": "Conversations with choices. The Healer already uses it."},
	{"id": "quests_lite", "label": "Quests", "in_story": true,
	 "does": "Objectives that track and complete. The herb hunt is one."},
	{"id": "save_load_lite", "label": "Save / Load", "in_story": true,
	 "does": "Save slots. Quit and come back where you left off."},
	{"id": "controller_lite", "label": "Controller", "in_story": false,
	 "does": "Walking, jumping, press-E on things."},
	{"id": "inventory_lite", "label": "Inventory", "in_story": false,
	 "does": "Carrying items, stacking, weight."},
	{"id": "equipment_lite", "label": "Equipment", "in_story": false,
	 "does": "Wearing gear that changes your stats."},
	{"id": "loot_lite", "label": "Loot", "in_story": false,
	 "does": "What a chest or an enemy drops, and how often."},
	{"id": "crafting_lite", "label": "Crafting", "in_story": false,
	 "does": "Turning items into other items from a recipe."},
	{"id": "vendor_lite", "label": "Vendor", "in_story": false,
	 "does": "A shop that buys and sells."},
	{"id": "stats_skills_lite", "label": "Stats / Skills", "in_story": false,
	 "does": "Health, damage, levels, skill points."},
	{"id": "combat_lite", "label": "Combat", "in_story": false,
	 "does": "Hitboxes, damage, dying."},
	{"id": "enemy_ai_lite", "label": "Enemy AI", "in_story": false,
	 "does": "Enemies that notice you, chase, and give up."},
	{"id": "scene_flow_lite", "label": "Scene Flow", "in_story": false,
	 "does": "Doors between rooms, spawn points, checkpoints."},
	{"id": "audio_lite", "label": "Audio", "in_story": false,
	 "does": "Music that crossfades, sound effects, audio zones."},
]

const PLUGIN_CFG := "res://addons/%s/plugin.cfg"


static func system(id: String) -> Dictionary:
	for s in SYSTEMS:
		if String(s["id"]) == id:
			return s
	return {}


static func label_for(id: String) -> String:
	var s: Dictionary = system(id)
	return String(s["label"]) if not s.is_empty() else id


# `enabled` is whatever ProjectSettings has in editor_plugins/enabled. Passed in
# rather than read here so the suite can hand us a pretend project.
static func is_on(id: String, enabled: PackedStringArray) -> bool:
	return (PLUGIN_CFG % id) in enabled


static func on_count(enabled: PackedStringArray) -> int:
	var n := 0
	for s in SYSTEMS:
		if is_on(String(s["id"]), enabled):
			n += 1
	return n


# The story systems are the ones the bundled game actually boots with. If one of
# those got switched off the game still runs, but a chunk of it goes quiet, so
# the dock says so.
static func story_systems() -> Array[String]:
	var out: Array[String] = []
	for s in SYSTEMS:
		if bool(s["in_story"]):
			out.append(String(s["id"]))
	return out


static func missing_story_systems(enabled: PackedStringArray) -> Array[String]:
	var out: Array[String] = []
	for id in story_systems():
		if not is_on(id, enabled):
			out.append(id)
	return out


# The checklist. Order matters: it's the path from "I just unzipped this" to
# "I changed something and saw it change".
#
# `state` is a plain dictionary the dock fills in from the project:
#   played           bool   they've pressed play at least once
#   edited_dialogue  bool   content/dialogue.json differs from what shipped
#   edited_quests    bool   content/quests.json differs
#   extra_on         int    non-story systems switched on
static func steps(state: Dictionary) -> Array[Dictionary]:
	var played := bool(state.get("played", false))
	var dlg := bool(state.get("edited_dialogue", false))
	var qst := bool(state.get("edited_quests", false))
	var extra := int(state.get("extra_on", 0))

	return [
		{
			"id": "play",
			"title": "Press Play and finish the little game",
			"why": "Talk to the Healer, take the quest, pick the three herbs, then save. Two minutes. You need to have seen it working before you change it.",
			"done": played,
		},
		{
			"id": "dialogue",
			"title": "Change what the Healer says",
			"why": "Open content/dialogue.json and rewrite a line. Press Play again and she says your words. This is the whole trick: the game reads text files, and you can edit text files.",
			"done": dlg,
		},
		{
			"id": "quests",
			"title": "Change the quest",
			"why": "content/quests.json decides what you're collecting and how many. Make it five feathers instead of three herbs. Nothing else needs to change.",
			"done": qst,
		},
		{
			"id": "systems",
			"title": "Switch on a system you want to use",
			"why": "Eleven more are sitting in the project, switched off so they don't crowd the editor. Turn one on below and its dock appears on the right.",
			"done": extra > 0,
		},
	]


static func remaining(step_list: Array[Dictionary]) -> int:
	var n := 0
	for s in step_list:
		if not bool(s.get("done", false)):
			n += 1
	return n
