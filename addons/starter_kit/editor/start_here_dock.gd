@tool
extends Control

# Start Here.
#
# The buyer arrives with an idea and no code. This is the first thing they should
# see: a short list that ticks itself off, and a switch for each of the fourteen
# systems in the project.
#
# It reads the project rather than remembering what got clicked, so closing Godot
# and coming back a week later doesn't reset anything.
#
# The list logic is in starter_plan.gd so the headless suite can test it. This
# file is the view and the buttons.

const OK_COLOR := Color(0.55, 0.9, 0.55)
const WARN_COLOR := Color(0.95, 0.8, 0.35)
const DIM_COLOR := Color(0.72, 0.75, 0.82)

var _list: VBoxContainer
var _systems_box: VBoxContainer
var _progress: Label
var _status: Label
var _played := false


func _ready() -> void:
	name = "Start Here"
	# Bottom panel, so height is the scarce axis, not width.
	custom_minimum_size = Vector2(0, 260)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 6)
	scroll.add_child(root)

	var intro := _wrap("You don't have to write any code. Work down this list, then switch on whatever your game needs.")
	intro.modulate = DIM_COLOR
	root.add_child(intro)

	root.add_child(HSeparator.new())
	root.add_child(_h("1.  Your first hour"))
	_progress = _wrap("")
	_progress.modulate = DIM_COLOR
	root.add_child(_progress)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	root.add_child(_list)

	root.add_child(HSeparator.new())
	root.add_child(_h("2.  The fourteen systems"))
	var note := _wrap("Three are on already, because the story game uses them. The rest are off so the editor stays readable. Switch one on and its dock appears with the Inspector on the right.")
	note.modulate = DIM_COLOR
	root.add_child(note)

	_systems_box = VBoxContainer.new()
	_systems_box.add_theme_constant_override("separation", 3)
	root.add_child(_systems_box)

	root.add_child(HSeparator.new())
	_status = _wrap("")
	root.add_child(_status)

	var foot := HBoxContainer.new()
	foot.add_child(_btn("Play the game", _on_play, true))
	foot.add_child(_btn("Refresh", _refresh))
	root.add_child(foot)

	var tail := _wrap("Nothing here is permanent. Every system is a normal folder in addons/, every bit of content is a text file you can open. Switching a system off doesn't delete anything.")
	tail.modulate = DIM_COLOR
	root.add_child(tail)

	# Tick the list off when they save a file, not when they remember to come back
	# and press Refresh. Not disconnected on the way out on purpose: freeing an
	# object drops its connections anyway, and doing it in _exit_tree would kill
	# the signal the first time the dock gets dragged to another slot.
	var fs := EditorInterface.get_resource_filesystem()
	if fs != null and not fs.filesystem_changed.is_connected(_refresh):
		fs.filesystem_changed.connect(_refresh)
	visibility_changed.connect(_refresh)

	_refresh()


# ---- reading the project --------------------------------------------------

func _enabled_plugins() -> PackedStringArray:
	var raw: Variant = ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
	if raw is PackedStringArray:
		return raw
	return PackedStringArray()


# "Have they edited it yet" without storing state: compare against the copy that
# shipped, which lives beside the live one as a .orig. If the .orig is missing we
# say no rather than guess, so the step just stays unticked.
func _edited(path: String) -> bool:
	var orig := path + ".orig"
	if not FileAccess.file_exists(orig) or not FileAccess.file_exists(path):
		return false
	return FileAccess.get_file_as_string(path) != FileAccess.get_file_as_string(orig)


func _state() -> Dictionary:
	var enabled := _enabled_plugins()
	var extra := 0
	for s in StarterPlan.SYSTEMS:
		var id := String(s["id"])
		if not bool(s["in_story"]) and StarterPlan.is_on(id, enabled):
			extra += 1
	return {
		"played": _played,
		"edited_dialogue": _edited("res://content/dialogue.json"),
		"edited_quests": _edited("res://content/quests.json"),
		"extra_on": extra,
	}


# ---- drawing --------------------------------------------------------------

func _refresh() -> void:
	if not is_instance_valid(_list):
		return
	# filesystem_changed fires on every import and every save. No point rebuilding
	# a panel nobody is looking at.
	if is_inside_tree() and not is_visible_in_tree():
		return

	for c in _list.get_children():
		c.queue_free()
	for c in _systems_box.get_children():
		c.queue_free()

	var steps: Array[Dictionary] = StarterPlan.steps(_state())
	var left: int = StarterPlan.remaining(steps)
	if left == 0:
		_progress.text = "All four done. You know how this project works now."
	else:
		_progress.text = "%d of %d done." % [steps.size() - left, steps.size()]
	for s in steps:
		_list.add_child(_step_row(s))

	var enabled := _enabled_plugins()
	for s in StarterPlan.SYSTEMS:
		_systems_box.add_child(_system_row(s, enabled))


func _step_row(step: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var head := HBoxContainer.new()
	var done := bool(step.get("done", false))
	var tick := Label.new()
	tick.text = "[x]" if done else "[ ]"
	tick.modulate = OK_COLOR if done else WARN_COLOR
	head.add_child(tick)

	var title := Label.new()
	title.text = String(step["title"])
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if done:
		title.modulate = DIM_COLOR
	head.add_child(title)
	box.add_child(head)

	var why := _wrap(String(step.get("why", "")))
	why.modulate = DIM_COLOR
	box.add_child(why)

	var row := HBoxContainer.new()
	match String(step["id"]):
		"play":
			row.add_child(_btn("Play it", _on_play))
		"dialogue":
			row.add_child(_btn("Open dialogue.json", _on_open.bind("res://content/dialogue.json")))
		"quests":
			row.add_child(_btn("Open quests.json", _on_open.bind("res://content/quests.json")))
	if row.get_child_count() > 0:
		box.add_child(row)

	box.add_child(HSeparator.new())
	return box


func _system_row(spec: Dictionary, enabled: PackedStringArray) -> Control:
	var id := String(spec["id"])
	var on := StarterPlan.is_on(id, enabled)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)

	var head := HBoxContainer.new()
	var check := CheckBox.new()
	check.text = String(spec["label"])
	check.button_pressed = on
	check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	check.toggled.connect(_on_toggle.bind(id))
	head.add_child(check)

	if bool(spec["in_story"]):
		var tag := Label.new()
		tag.text = "used by the game"
		tag.modulate = DIM_COLOR
		head.add_child(tag)
	box.add_child(head)

	var does := _wrap(String(spec["does"]))
	does.modulate = DIM_COLOR
	box.add_child(does)
	return box


# ---- buttons --------------------------------------------------------------

# Switching a plugin on is the buyer pressing a switch, so it's their edit to
# make. We never do it for them on load.
func _on_toggle(pressed: bool, id: String) -> void:
	EditorInterface.set_plugin_enabled(id, pressed)
	var label := StarterPlan.label_for(id)
	if pressed:
		_say("%s is on. Its dock is with the Inspector on the right. If you can't see the tab, the arrows at the end of the tab row scroll through them." % label, OK_COLOR)
	else:
		_say("%s is off. Nothing was deleted, the folder is still in addons/." % label, DIM_COLOR)
	_refresh()


func _on_open(path: String) -> void:
	if not FileAccess.file_exists(path):
		_say("Couldn't find %s. It should be in the content folder." % path, WARN_COLOR)
		return
	EditorInterface.select_file(path)
	_say("Opened it in the file list. Double-click it there to edit, or open it in any text editor.", OK_COLOR)


func _on_play() -> void:
	_played = true
	_say("Running the game. Arrow keys to walk, Enter to talk.", OK_COLOR)
	EditorInterface.play_main_scene()
	_refresh()


# ---- helpers --------------------------------------------------------------

func _h(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = Color(0.8, 0.85, 0.95)
	return l


func _wrap(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _btn(text: String, cb: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	if primary:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	return b


func _say(text: String, color: Color) -> void:
	_status.modulate = color
	_status.text = text
