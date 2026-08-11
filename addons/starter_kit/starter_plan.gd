@tool
class_name StarterPlan
extends RefCounted

# The data behind the Start Here dock. Kept free of EditorInterface on purpose so
# the headless suite can drive it: everything takes the project state as an
# argument instead of reaching for it.
#
# Genre-aware: which systems the game boots with, and what the checklist says,
# come from content/game.json (the `systems` list). The same dock ships in every
# genre kit and reads its own genre out of that file.
#
# Why the docks aren't all switched on out of the box: every Lite pack puts its
# dock in the same slot as the Inspector. Fourteen of them is twenty tabs, and
# Godot answers that by hiding the lot behind two overflow arrows. So we ship
# with the handful the game runs on, and this list turns the rest on one at a
# time, when the buyer asks for it.

const SYSTEMS: Array[Dictionary] = [
	{"id": "dialogue_lite", "label": "Dialogue",
	 "does": "Conversations with choices."},
	{"id": "quests_lite", "label": "Quests",
	 "does": "Objectives that track and complete."},
	{"id": "save_load_lite", "label": "Save / Load",
	 "does": "Save slots. Quit and come back where you left off."},
	{"id": "controller_lite", "label": "Controller",
	 "does": "Walking, jumping, press-E on things."},
	{"id": "inventory_lite", "label": "Inventory",
	 "does": "Carrying items, stacking, weight."},
	{"id": "equipment_lite", "label": "Equipment",
	 "does": "Wearing gear that changes your stats."},
	{"id": "loot_lite", "label": "Loot",
	 "does": "What a chest or an enemy drops, and how often."},
	{"id": "crafting_lite", "label": "Crafting",
	 "does": "Turning items into other items from a recipe."},
	{"id": "vendor_lite", "label": "Vendor",
	 "does": "A shop that buys and sells."},
	{"id": "stats_skills_lite", "label": "Stats / Skills",
	 "does": "Health, damage, levels, skill points."},
	{"id": "combat_lite", "label": "Combat",
	 "does": "Hitboxes, damage, dying."},
	{"id": "enemy_ai_lite", "label": "Enemy AI",
	 "does": "Enemies that notice you, chase, and give up."},
	{"id": "scene_flow_lite", "label": "Scene Flow",
	 "does": "Doors between rooms, spawn points, checkpoints."},
	{"id": "audio_lite", "label": "Audio",
	 "does": "Music that crossfades, sound effects, audio zones."},
]

const PLUGIN_CFG := "res://addons/%s/plugin.cfg"
const GAME_JSON := "res://content/game.json"

# content/game.json names each system in short form; the docks live under the
# `_lite` suffix. This bridges the two.
const SHORT_TO_LITE := {
	"save": "save_load_lite", "quests": "quests_lite", "dialogue": "dialogue_lite",
	"controller": "controller_lite", "inventory": "inventory_lite",
	"equipment": "equipment_lite", "loot": "loot_lite", "crafting": "crafting_lite",
	"vendor": "vendor_lite", "stats": "stats_skills_lite", "combat": "combat_lite",
	"enemy_ai": "enemy_ai_lite", "scene_flow": "scene_flow_lite", "audio": "audio_lite",
}


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


# ---- genre config ---------------------------------------------------------

# The parsed content/game.json (title, genre, systems). Empty if it's missing.
static func genre_config(path := GAME_JSON) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


# The lite plugin ids this genre's game actually boots with, mapped from the
# short names in game.json. Unknown names are skipped.
static func active_systems(cfg: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for short in cfg.get("systems", []):
		var lite := String(SHORT_TO_LITE.get(String(short), ""))
		if lite != "" and not out.has(lite):
			out.append(lite)
	return out


static func is_active(id: String, cfg: Dictionary) -> bool:
	return active_systems(cfg).has(id)


static func missing_active_systems(cfg: Dictionary, enabled: PackedStringArray) -> Array[String]:
	var out: Array[String] = []
	for id in active_systems(cfg):
		if not is_on(id, enabled):
			out.append(id)
	return out


# ---- the checklist --------------------------------------------------------

# Order matters: it's the path from "I just unzipped this" to "I changed
# something and saw it change".
#
# `state` is a plain dictionary the dock fills in from the project:
#   played          bool   they've pressed play at least once
#   edited_dialogue bool   content/dialogue.json differs from what shipped
#   edited_quests   bool   content/quests.json differs
#   extra_on        int    systems switched on beyond the ones the game boots with
#   has_dialogue    bool   this genre ships a content/dialogue.json to edit
static func steps(state: Dictionary) -> Array[Dictionary]:
	var played := bool(state.get("played", false))
	var dlg := bool(state.get("edited_dialogue", false))
	var qst := bool(state.get("edited_quests", false))
	var extra := int(state.get("extra_on", 0))
	var has_dialogue := bool(state.get("has_dialogue", false))

	var out: Array[Dictionary] = [
		{
			"id": "play",
			"title": "Press Play and finish the little game",
			"why": "Play it through once. Two minutes. You need to have seen it working before you change it.",
			"done": played,
		},
	]
	if has_dialogue:
		out.append({
			"id": "dialogue",
			"title": "Change what a character says",
			"why": "Open content/dialogue.json and rewrite a line. Press Play again and they say your words. This is the whole trick: the game reads text files, and you can edit text files.",
			"done": dlg,
		})
	out.append({
		"id": "quests",
		"title": "Change the goal",
		"why": "content/quests.json decides what you're collecting or clearing and how many. Change a number, press Play, watch the counter follow. Nothing else needs to change.",
		"done": qst,
	})
	out.append({
		"id": "systems",
		"title": "Switch on a system you want to use",
		"why": "The rest are sitting in the project, switched off so they don't crowd the editor. Turn one on below and its dock appears on the right.",
		"done": extra > 0,
	})
	return out


static func remaining(step_list: Array[Dictionary]) -> int:
	var n := 0
	for s in step_list:
		if not bool(s.get("done", false)):
			n += 1
	return n
