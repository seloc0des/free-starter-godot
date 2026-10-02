@tool
extends Control

# No-code authoring dock. Build branching conversations in a panel: create a
# Dialogue, add nodes (speaker + line + optional event + next), and give nodes
# choices that jump to other nodes. Saves to .tres in the target folder.

const FOLDER := "res://dialogues/"

var _dialogue: DialogueLite = null
var _node: DialogueNodeLite = null
# What the node form last showed: the node's values then, and the form's own reading of
# them. Apply writes only the fields that differ from that.
var _node_seen := {}
var _form_shown := {}

var _folder_edit: LineEdit
var _file_list: ItemList
var _id_edit: LineEdit
var _title_edit: LineEdit
var _entry_edit: LineEdit
var _node_list: ItemList
var _node_id: LineEdit
var _node_speaker: LineEdit
var _node_text: TextEdit
var _node_event: LineEdit
var _node_next: LineEdit
var _choice_list: ItemList
var _choice_text: LineEdit
var _choice_next: LineEdit
var _status: Label
var _scroll: ScrollContainer


func _ready() -> void:
	name = "Dialogue"
	_build_ui()
	_reload_folder()
	if Engine.is_editor_hint():
		EditorInterface.get_inspector().property_edited.connect(_on_inspector_edit)
		# an edit inside a node never reaches property_edited, but it does go through undo/redo
		var ur := EditorInterface.get_editor_undo_redo()
		ur.history_changed.connect(_on_editor_history)
		ur.version_changed.connect(_on_editor_history)


# A plain Control doesn't tell the dock slot how narrow its page can go, so say it
# here. Height is the scroll's job.
func _get_minimum_size() -> Vector2:
	return Vector2(_scroll.get_combined_minimum_size().x, 0.0) if _scroll != null else Vector2.ZERO


func _build_ui() -> void:
	# taller than any dock slot, so it scrolls; never sideways, so long text wraps
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.minimum_size_changed.connect(update_minimum_size)
	add_child(_scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(root)

	_folder_edit = LineEdit.new()
	_folder_edit.text = FOLDER
	root.add_child(_labeled("Folder", _folder_edit))
	var reload := Button.new()
	reload.text = "Reload"
	reload.pressed.connect(_reload_folder)
	root.add_child(reload)
	_file_list = ItemList.new()
	_file_list.custom_minimum_size = Vector2(0, 80)
	_file_list.item_selected.connect(_on_file_selected)
	root.add_child(_file_list)
	var new_btn := Button.new()
	new_btn.text = "New Dialogue"
	new_btn.pressed.connect(_on_new)
	root.add_child(new_btn)

	root.add_child(HSeparator.new())
	_id_edit = LineEdit.new()
	root.add_child(_labeled("Dialogue id", _id_edit))
	_title_edit = LineEdit.new()
	root.add_child(_labeled("Title", _title_edit))
	_entry_edit = LineEdit.new()
	root.add_child(_labeled("Entry node id", _entry_edit))

	root.add_child(HSeparator.new())
	root.add_child(_header("Nodes"))
	_node_list = ItemList.new()
	_node_list.custom_minimum_size = Vector2(0, 80)
	_node_list.item_selected.connect(_on_node_selected)
	root.add_child(_node_list)
	var node_btns := HBoxContainer.new()
	var add_node := Button.new()
	add_node.text = "Add node"
	add_node.pressed.connect(_on_add_node)
	var del_node := Button.new()
	del_node.text = "Remove node"
	del_node.pressed.connect(_on_remove_node)
	node_btns.add_child(add_node)
	node_btns.add_child(del_node)
	root.add_child(node_btns)

	_node_id = LineEdit.new()
	root.add_child(_labeled("Node id", _node_id))
	_node_speaker = LineEdit.new()
	root.add_child(_labeled("Speaker", _node_speaker))
	_node_text = TextEdit.new()
	_node_text.custom_minimum_size = Vector2(0, 56)
	root.add_child(_labeled("Text", _node_text))
	_node_event = LineEdit.new()
	_node_event.placeholder_text = "optional, e.g. give_quest:gather_herbs"
	root.add_child(_labeled("Event", _node_event))
	_node_next = LineEdit.new()
	root.add_child(_labeled("Next node id", _node_next))
	var apply_node := Button.new()
	apply_node.text = "Apply node fields"
	apply_node.pressed.connect(_on_apply_node)
	root.add_child(apply_node)

	root.add_child(HSeparator.new())
	root.add_child(_header("Choices (for selected node)"))
	_choice_list = ItemList.new()
	_choice_list.custom_minimum_size = Vector2(0, 64)
	root.add_child(_choice_list)
	_choice_text = LineEdit.new()
	_choice_text.placeholder_text = "choice text"
	_choice_next = LineEdit.new()
	_choice_next.placeholder_text = "-> node id"
	var choice_row := HBoxContainer.new()
	choice_row.add_child(_choice_text)
	choice_row.add_child(_choice_next)
	root.add_child(choice_row)
	var choice_btns := HBoxContainer.new()
	var add_choice := Button.new()
	add_choice.text = "Add choice"
	add_choice.pressed.connect(_on_add_choice)
	var del_choice := Button.new()
	del_choice.text = "Remove choice"
	del_choice.pressed.connect(_on_remove_choice)
	choice_btns.add_child(add_choice)
	choice_btns.add_child(del_choice)
	root.add_child(choice_btns)

	root.add_child(HSeparator.new())
	var save := Button.new()
	save.text = "Save dialogue (.tres)"
	save.pressed.connect(_on_save)
	root.add_child(save)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)


func _labeled(text: String, field: Control) -> Control:
	var box := VBoxContainer.new()
	var l := Label.new()
	l.text = text
	box.add_child(l)
	box.add_child(field)
	return box


func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	return l


func _say(msg: String) -> void:
	if _status != null:
		_status.text = msg


func _reload_folder() -> void:
	_file_list.clear()
	var dir := DirAccess.open(_folder_edit.text)
	if dir == null:
		_say("Folder not found (created on save): " + _folder_edit.text)
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.ends_with(".tres"):
			_file_list.add_item(f)
		f = dir.get_next()
	dir.list_dir_end()
	_say("%d dialogue file(s)." % _file_list.item_count)


func _on_file_selected(index: int) -> void:
	var fname := _file_list.get_item_text(index)
	var res: Resource = ResourceLoader.load(_folder_edit.text.path_join(fname))
	if res is DialogueLite:
		_dialogue = res
		_node = null
		_load_dialogue_into_form()
		_say("Loaded " + fname)
	else:
		_say("Not a DialogueLite resource: " + fname)


func _on_new() -> void:
	_dialogue = DialogueLite.new()
	_dialogue.id = "new_dialogue"
	_node = null
	_load_dialogue_into_form()
	_say("New dialogue. Set an id and add nodes.")


func _load_dialogue_into_form() -> void:
	if _dialogue == null:
		return
	_id_edit.text = _dialogue.id
	_title_edit.text = _dialogue.title
	_entry_edit.text = _dialogue.entry
	_refresh_node_list()
	_node_id.text = ""
	_node_speaker.text = ""
	_node_text.text = ""
	_node_event.text = ""
	_node_next.text = ""
	_choice_list.clear()
	_node_seen.clear()
	_form_shown.clear()


func _refresh_node_list() -> void:
	_node_list.clear()
	if _dialogue == null:
		return
	for n in _dialogue.nodes:
		if n != null:
			_node_list.add_item(String(n.id))


func _on_add_node() -> void:
	if _dialogue == null:
		_on_new()
	var n := DialogueNodeLite.new()
	n.id = _free_node_id()
	# copy, change, assign back: on a .tres the editor loaded, an empty array is
	# the script's read-only default, and appending to it in place fails
	var arr: Array[DialogueNodeLite] = _dialogue.nodes.duplicate()
	arr.append(n)
	_dialogue.nodes = arr
	if _dialogue.entry == "":
		_dialogue.entry = n.id
		_entry_edit.text = n.id
	_refresh_node_list()
	_node = n
	_load_node_into_form()


# First unused "node_N". Numbering off the node count hands out a duplicate as
# soon as anything was deleted ([node_1, node_2] minus node_1 gives a second
# node_2), and then only the last of the two ever plays.
func _free_node_id() -> String:
	var used := {}
	for n in _dialogue.nodes:
		if n != null:
			used[String(n.id)] = true
	var i := 1
	while used.has("node_%d" % i):
		i += 1
	return "node_%d" % i


func _on_remove_node() -> void:
	if _node == null or _dialogue == null:
		return
	var arr: Array[DialogueNodeLite] = _dialogue.nodes.duplicate()
	arr.erase(_node)
	_dialogue.nodes = arr
	_node = null
	_refresh_node_list()
	_choice_list.clear()


func _on_node_selected(index: int) -> void:
	var nid := _node_list.get_item_text(index)
	for n in _dialogue.nodes:
		if n != null and String(n.id) == nid:
			_node = n
			break
	_load_node_into_form()


func _load_node_into_form() -> void:
	if _node == null:
		return
	_node_id.text = _node.id
	_node_speaker.text = _node.speaker
	_node_text.text = _node.text
	_node_event.text = _node.event
	_node_next.text = _node.next
	_refresh_choice_list()
	_node_seen = _node_fields()
	_form_shown = _form_fields()


# The node's fields keyed like the form (the keys are the node's property names).
func _node_fields() -> Dictionary:
	return {"id": _node.id, "speaker": _node.speaker, "text": _node.text, "event": _node.event, "next": _node.next}


func _form_fields() -> Dictionary:
	return {"id": _node_id.text, "speaker": _node_speaker.text, "text": _node_text.text, "event": _node_event.text, "next": _node_next.text}


func _show_field(f: String, v: Variant) -> void:
	match f:
		"id": _node_id.text = v
		"speaker": _node_speaker.text = v
		"text": _node_text.text = v
		"event": _node_event.text = v
		"next": _node_next.text = v


# Show whatever changed on the node since the form last showed it, one field at a time,
# so anything typed here and not applied yet stays. A field changed on both sides takes
# the node's value: that edit is the newer one.
func _pull_node_form() -> void:
	var now := _node_fields()
	for f in now:
		if _node_seen.has(f) and _same(now[f], _node_seen[f]):
			continue
		_show_field(f, now[f])
		_node_seen[f] = now[f]
		_form_shown[f] = _form_fields()[f]


func _same(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and a == b


func _on_apply_node() -> void:
	if _node == null:
		_say("Add or select a node first.")
		return
	# Only what was changed here since the form showed it. The Inspector edits this same
	# node, so writing every field back would undo its edits.
	var form := _form_fields()
	for f in form:
		if _form_shown.has(f) and _same(form[f], _form_shown[f]):
			continue
		_node.set(f, form[f])
	_refresh_node_list()
	_pull_node_form()
	_say("Applied node '%s'." % _node.id)


func _refresh_choice_list() -> void:
	_choice_list.clear()
	if _node == null:
		return
	for c in _node.choices:
		if c != null:
			_choice_list.add_item("%s  ->  %s" % [c.text, c.next])


func _on_add_choice() -> void:
	if _node == null:
		_say("Select a node first.")
		return
	var c := DialogueChoiceLite.new()
	c.text = _choice_text.text
	c.next = _choice_next.text
	var arr: Array[DialogueChoiceLite] = _node.choices.duplicate()
	arr.append(c)
	_node.choices = arr
	_choice_text.text = ""
	_choice_next.text = ""
	_refresh_choice_list()


func _on_remove_choice() -> void:
	if _node == null:
		return
	var sel := _choice_list.get_selected_items()
	if sel.is_empty():
		return
	var arr: Array[DialogueChoiceLite] = _node.choices.duplicate()
	var idx := sel[0]
	if idx >= 0 and idx < arr.size():
		arr.remove_at(idx)
		_node.choices = arr
		_refresh_choice_list()


func _on_save() -> void:
	if _dialogue == null:
		_say("Nothing to save.")
		return
	_dialogue.id = _id_edit.text
	_dialogue.title = _title_edit.text
	_dialogue.entry = _entry_edit.text
	if String(_dialogue.id) == "":
		_say("Give the dialogue an id first.")
		return
	if not DirAccess.dir_exists_absolute(_folder_edit.text):
		DirAccess.make_dir_recursive_absolute(_folder_edit.text)
	var path := _folder_edit.text.path_join(_dialogue.id + ".tres")
	var err := ResourceSaver.save(_dialogue, path)
	if err == OK:
		_register_uid(path)
		_adopt_file_copy(path)
		_reload_folder()
		_say("Saved " + path)
	else:
		_say("Save failed (err %d)." % err)


# The Inspector and scenes load the file's own copy. Make that the one this dock
# edits, or the editor's next save writes their old copy back over this Save.
func _adopt_file_copy(path: String) -> void:
	if not ResourceLoader.has_cached(path):
		_dialogue.take_over_path(path)  # nobody holds it yet
		return
	var cached: Resource = ResourceLoader.load(path)
	if cached == _dialogue or not (cached is DialogueLite):
		return
	for p in _dialogue.get_property_list():
		var n: String = p.name
		if (int(p.usage) & PROPERTY_USAGE_STORAGE) and n != "script" and n != "resource_path":
			cached.set(n, _dialogue.get(n))
	cached.emit_changed()
	_dialogue = cached


# The Inspector edits this same dialogue, and Save writes the id, title and entry
# fields back over it, so show its change here. The rest stays as typed.
func _on_inspector_edit(prop: String) -> void:
	if _dialogue == null or EditorInterface.get_inspector().get_edited_object() != _dialogue:
		return
	match prop:
		"id": _id_edit.text = _dialogue.id
		"title": _title_edit.text = _dialogue.title
		"entry": _entry_edit.text = _dialogue.entry
		"nodes":
			_refresh_node_list()
			if not _dialogue.nodes.has(_node):
				_node = null
				_choice_list.clear()


# An edit inside a node (its fields or its choices) comes through here, undo included.
# Show it without touching what's typed and not applied yet.
func _on_editor_history() -> void:
	if _dialogue == null:
		return
	if _node != null and not _dialogue.nodes.has(_node):
		# deleted in the Inspector: empty the form too, so it doesn't keep showing it
		_node = null
		_choice_list.clear()
		for le in [_node_id, _node_speaker, _node_event, _node_next]:
			(le as LineEdit).text = ""
		_node_text.text = ""
		_node_seen.clear()
		_form_shown.clear()
	if _node_list_stale():
		_refresh_node_list()
	if _node == null:
		return
	var row := _node_row()
	if row >= 0:
		_node_list.select(row)
	_pull_node_form()
	_relist(_choice_list, _refresh_choice_list)


# Rebuild the node list only when its ids changed: rebuilding on every editor action
# (moving a sprite counts) jumped a long list back to the top.
func _node_list_stale() -> bool:
	var ids := []
	for n in _dialogue.nodes:
		if n != null:
			ids.append(String(n.id))
	if ids.size() != _node_list.item_count:
		return true
	for i in ids.size():
		if _node_list.get_item_text(i) != ids[i]:
			return true
	return false


func _node_row() -> int:
	var row := 0
	for n in _dialogue.nodes:
		if n == null:
			continue
		if n == _node:
			return row
		row += 1
	return -1


# Rebuild a list, keeping the picked row picked (Remove works off it).
func _relist(list: ItemList, refresh: Callable) -> void:
	var sel := list.get_selected_items()
	refresh.call()
	if not sel.is_empty() and sel[0] < list.item_count:
		list.select(sel[0])


# A file written into a folder made this session isn't in the editor's file list
# yet, so its UID stayed unknown and the first Play of a scene using it warned
# "invalid UID" (a yellow Debugger badge). Register it the moment it's written.
static func _register_uid(path: String) -> void:
	var uid := ResourceLoader.get_resource_uid(path)
	if uid != ResourceUID.INVALID_ID and not ResourceUID.has_id(uid):
		ResourceUID.add_id(uid, path)
