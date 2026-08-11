extends Node

# Headless test for the Start Here plan.
# Run: godot --headless --path . res://tools/starter_kit/verify.tscn
#
# Only covers starter_plan.gd. The dock itself needs a real editor, so that part
# is still a click-through.

var _passes := 0
var _failures := 0

const CFG := "res://addons/%s/plugin.cfg"


func _ready() -> void:
	await get_tree().process_frame
	print("--- starter kit verify ---")

	_catalogue()
	_switches()
	_genre()
	_checklist()
	_shipped_defaults()

	print("--- %d passed, %d failed ---" % [_passes, _failures])
	print("=== PASS ===" if _failures == 0 else "=== FAIL ===")
	get_tree().quit(1 if _failures > 0 else 0)


func _catalogue() -> void:
	_ok(StarterPlan.SYSTEMS.size() == 14, "fourteen systems listed (got %d)" % StarterPlan.SYSTEMS.size())

	var seen := {}
	var dupes := 0
	var missing_folder := 0
	var blank_copy := 0
	for s in StarterPlan.SYSTEMS:
		var id := String(s["id"])
		if seen.has(id):
			dupes += 1
		seen[id] = true
		if not DirAccess.dir_exists_absolute("res://addons/" + id):
			missing_folder += 1
			push_warning("no addon folder for %s" % id)
		if String(s["label"]).is_empty() or String(s["does"]).is_empty():
			blank_copy += 1
	_ok(dupes == 0, "no duplicate ids")
	_ok(missing_folder == 0, "every listed system has an addons/ folder (%d missing)" % missing_folder)
	_ok(blank_copy == 0, "every system has a label and a description")

	# The other direction: a Lite pack in addons/ that the dock forgot to list
	# would be invisible to the buyer.
	var unlisted := 0
	var d := DirAccess.open("res://addons")
	if d != null:
		for folder in d.get_directories():
			if not folder.ends_with("_lite"):
				continue
			if StarterPlan.system(folder).is_empty():
				unlisted += 1
				push_warning("addons/%s is installed but not in StarterPlan.SYSTEMS" % folder)
	_ok(unlisted == 0, "no installed Lite pack is missing from the list (%d unlisted)" % unlisted)


func _switches() -> void:
	var on := PackedStringArray([CFG % "dialogue_lite", CFG % "quests_lite"])
	_ok(StarterPlan.is_on("dialogue_lite", on), "is_on finds an enabled plugin")
	_ok(not StarterPlan.is_on("audio_lite", on), "is_on rejects a disabled plugin")
	_ok(StarterPlan.on_count(on) == 2, "on_count counts only what's enabled (got %d)" % StarterPlan.on_count(on))
	_ok(StarterPlan.on_count(PackedStringArray()) == 0, "on_count of an empty project is zero")
	_ok(StarterPlan.label_for("stats_skills_lite") == "Stats / Skills",
		"label_for returns the buyer-facing name (got %s)" % StarterPlan.label_for("stats_skills_lite"))
	_ok(StarterPlan.label_for("nope_lite") == "nope_lite", "label_for falls back to the id it was given")


# The dock reads which systems the game boots with from content/game.json. This
# runs inside each genre kit, so it checks the real config it shipped with.
func _genre() -> void:
	var cfg := StarterPlan.genre_config()
	_ok(not cfg.is_empty(), "content/game.json parses")
	_ok(String(cfg.get("genre", "")) != "", "game.json names a genre (got '%s')" % cfg.get("genre", ""))

	var active := StarterPlan.active_systems(cfg)
	_ok(active.size() >= 3, "the game boots with at least three systems (got %d)" % active.size())

	var bad := 0
	for id in active:
		if StarterPlan.system(id).is_empty():
			bad += 1
			push_warning("active system %s is not in the catalogue" % id)
	_ok(bad == 0, "every active system is a known lite pack")

	# save/quests are the spine every genre carries
	_ok("save_load_lite" in active and "quests_lite" in active,
		"save and quests are among the active systems")

	var all_on := PackedStringArray()
	for id in active:
		all_on.append(CFG % id)
	_ok(StarterPlan.missing_active_systems(cfg, all_on).is_empty(), "nothing reported missing when the active set is on")
	_ok(StarterPlan.missing_active_systems(cfg, PackedStringArray()).size() == active.size(),
		"all active systems reported missing when none are on")


func _checklist() -> void:
	# no dialogue.json (dungeon / survival): play, goal, systems
	var no_dlg: Array[Dictionary] = StarterPlan.steps({})
	_ok(no_dlg.size() == 3, "three steps without a dialogue file (got %d)" % no_dlg.size())
	_ok(StarterPlan.remaining(no_dlg) == 3, "a fresh project has everything left to do")

	# with dialogue.json (story / rpg): the extra "change what a character says"
	var with_dlg: Array[Dictionary] = StarterPlan.steps({"has_dialogue": true})
	_ok(with_dlg.size() == 4, "four steps when a dialogue file ships (got %d)" % with_dlg.size())

	var done: Array[Dictionary] = StarterPlan.steps({
		"has_dialogue": true, "played": true, "edited_dialogue": true, "edited_quests": true, "extra_on": 1,
	})
	_ok(StarterPlan.remaining(done) == 0, "all steps tick off when the project shows the work")

	var half: Array[Dictionary] = StarterPlan.steps({"played": true, "extra_on": 0})
	_ok(StarterPlan.remaining(half) == 2, "partial progress counts correctly (got %d left)" % StarterPlan.remaining(half))

	var blank_why := 0
	for s in with_dlg:
		if String(s.get("why", "")).is_empty() or String(s.get("title", "")).is_empty():
			blank_why += 1
	_ok(blank_why == 0, "every step says what it is and why")


# The dock decides "have they edited it yet" by diffing against a .orig copy.
# If those go missing the steps silently never tick, so the suite guards them.
# quests.json is universal; dialogue.json only ships in genres that talk.
func _shipped_defaults() -> void:
	_ok(FileAccess.file_exists("res://content/quests.json"), "content/quests.json ships with the project")
	for f in ["res://content/dialogue.json", "res://content/quests.json"]:
		if not FileAccess.file_exists(f):
			continue
		_ok(FileAccess.file_exists(f + ".orig"), "%s.orig ships alongside it" % f)
		if FileAccess.file_exists(f + ".orig"):
			_ok(FileAccess.get_file_as_string(f) == FileAccess.get_file_as_string(f + ".orig"),
				"%s matches its .orig out of the box" % f)


func _ok(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
		print("PASS: %s" % msg)
	else:
		_failures += 1
		print("FAIL: %s" % msg)
