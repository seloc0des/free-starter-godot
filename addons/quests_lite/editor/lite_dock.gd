@tool
extends Control

# Compact no-code authoring dock for the Lite tier. Reflective: it reads the
# resource's exported scalars and builds a control per field (line edit, spin,
# checkbox, texture picker), so a non-coder authors the Lite resource without the
# Inspector or hand-edited .tres. Arrays / dictionaries / sub-resources are left to
# the Inspector (the Pro dock handles those, plus one-click scene wiring).
#
# Shared body across the Lite tiers — only the CONFIG block differs per pack.

# ===================== CONFIG (per-pack) =====================
const RESOURCE_SCRIPT := preload("res://addons/quests_lite/quest_lite.gd")
const DEFAULT_DIR := "res://quests"
const DOCK_NAME := "Quests (Lite)"
const NEW_BASENAME := "new_quest"
const UPGRADE_LABEL := "Pro authors objectives and rewards right here, and adds a QuestGiver talk flow, a styled QuestLogUI with tabs, quest chains, six more objective types and save integration."
const UPGRADE_URL := "https://selodev.itch.io/quests-no-code-quest-system-for-godot-4"
# =============================================================

const OK_COLOR := Color(0.55, 0.9, 0.55)
const ERR_COLOR := Color(0.95, 0.55, 0.55)
const WARN_COLOR := Color(0.95, 0.8, 0.35)
const HINT_COLOR := Color(0.7, 0.7, 0.7)

var _dir := DEFAULT_DIR
var _paths: PackedStringArray = PackedStringArray()
var _current_path := ""
var _current: Resource
var _loading := false

var _list: ItemList
var _dir_label: Label
var _fields: VBoxContainer
var _status: Label
var _file_dialog: EditorFileDialog
var _icon_setter := Callable()


func _ready() -> void:
	name = DOCK_NAME
	custom_minimum_size = Vector2(0, 420)
	_build_ui()
	_refresh_list()
	if Engine.is_editor_hint():
		EditorInterface.get_inspector().property_edited.connect(_on_inspector_edit)


# As wide as what's in it and no wider. The old fixed width pushed a laptop's
# default dock (270 px) wider whenever this tab was open.
func _get_minimum_size() -> Vector2:
	if get_child_count() == 0 or not (get_child(0) is Control):
		return Vector2.ZERO
	return Vector2((get_child(0) as Control).get_combined_minimum_size().x, 0.0)


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.minimum_size_changed.connect(update_minimum_size)
	add_child(root)
	var _setup_hint := Label.new()
	_setup_hint.text = "Editing data here. To add this to your scene, use the ‘Quests · Setup’ tab (no code)."
	_setup_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_setup_hint.modulate = Color(0.66, 0.7, 0.8)
	root.add_child(_setup_hint)

	var header := HBoxContainer.new()
	root.add_child(header)
	_dir_label = Label.new()
	_dir_label.text = _dir
	_dir_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dir_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # a long folder path wraps
	header.add_child(_dir_label)
	header.add_child(_button("Folder…", _on_choose_folder))

	# The list sits above the form. Side by side, the form only got what the list
	# left of a default dock, too narrow for its fields without a sideways scroll.
	var split := VSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 160
	root.add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(120, 0)
	split.add_child(left)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.theme_changed.connect(_hold_five_rows.bind(_list), CONNECT_DEFERRED)  # after the theme cache refreshes
	_list.item_selected.connect(_on_selected)
	left.add_child(_list)
	var lb := HBoxContainer.new()
	left.add_child(lb)
	lb.add_child(_button("New", _on_new))
	lb.add_child(_button("Dup", _on_duplicate))
	lb.add_child(_button("Del", _on_delete))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(scroll)
	_fields = VBoxContainer.new()
	_fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_fields)

	root.add_child(HSeparator.new())
	root.add_child(_button("Save", _on_save))
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # long status lines ran off the dock's edge
	root.add_child(_status)

	# Upgrade footer — the Lite dock's whole reason for being polished.
	root.add_child(HSeparator.new())
	var up := Label.new()
	up.text = "🔒 " + UPGRADE_LABEL
	up.modulate = Color(0.85, 0.8, 0.55)
	up.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(up)
	root.add_child(_button("Upgrade to Pro →", func(): OS.shell_open(UPGRADE_URL)))
	# EditorFileDialog is created lazily in _open_dialog — it's an editor-only
	# class, so constructing it here would break any non-editor instantiation.


# About five rows of the list, from its own font, so it holds at any editor scale.
# It used to get whatever a fixed 160 px top pane left over, which at 125% was a
# few rows at best, and nothing at all where the header rows share that pane.
func _hold_five_rows(list: ItemList) -> void:
	var font := list.get_theme_font("font")
	var row := font.get_height(list.get_theme_font_size("font_size")) + list.get_theme_constant("v_separation")
	list.custom_minimum_size.y = 5 * row


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _set_status(text: String, color: Color) -> void:
	_status.modulate = color
	_status.text = text


# ---- list ----------------------------------------------------------------

func _refresh_list() -> void:
	_dir_label.text = _dir
	_paths = _scan(_dir)
	_list.clear()
	for p in _paths:
		_list.add_item(_list_label(p))
	for i in _paths.size():
		if _paths[i] == _current_path:
			_list.select(i)


# The name typed into the form ("Iron Sword"), not the file it lives in (iron_sword).
# A blank name, or a file that won't load, falls back to the file name.
func _list_label(path: String) -> String:
	var stem := path.get_file().get_basename()
	var res: Resource = load(path)
	if res == null:
		return stem
	for field in ["name", "title"]:
		var v: Variant = res.get(field)
		if v is String and String(v).strip_edges() != "":
			return String(v).strip_edges()
	return stem


func _scan(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.get_extension() == "tres":
			var res := load(dir_path.path_join(f))
			if res != null and res.get_script() == RESOURCE_SCRIPT:
				out.append(dir_path.path_join(f))
		f = dir.get_next()
	dir.list_dir_end()
	return out


func _on_selected(idx: int) -> void:
	if idx < 0 or idx >= _paths.size():
		return
	_current_path = _paths[idx]
	_current = load(_current_path).duplicate(false)  # working copy
	_build_fields()
	_set_status("", OK_COLOR)


# ---- reflective form -----------------------------------------------------

func _build_fields() -> void:
	for c in _fields.get_children():
		_fields.remove_child(c)  # out now, so a rebuild never shows two copies
		c.queue_free()
	if _current == null:
		return
	_loading = true
	# the script's own list: in the editor the resource is a placeholder, and its
	# property list has no script-variable flag, so filtering on that showed nothing
	var scr: Script = RESOURCE_SCRIPT  # typed, or the class constant reads as a static call
	for p in scr.get_script_property_list():
		var usage: int = p["usage"]
		if not (usage & PROPERTY_USAGE_EDITOR):
			continue
		if usage & (PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP):
			continue
		_build_field(p)
	_loading = false


func _build_field(p: Dictionary) -> void:
	var prop: String = p["name"]
	var t: int = p["type"]
	var hint: int = p["hint"]
	var value: Variant = _current.get(prop)
	var control: Control = null

	match t:
		TYPE_BOOL:
			var cb := CheckBox.new()
			cb.button_pressed = value
			cb.toggled.connect(func(v): _set_prop(prop, v))
			control = cb
		TYPE_INT:
			control = _spin(prop, value, true)
		TYPE_FLOAT:
			control = _spin(prop, value, false)
		TYPE_STRING, TYPE_STRING_NAME:
			if hint == PROPERTY_HINT_MULTILINE_TEXT:
				var te := TextEdit.new()
				te.custom_minimum_size = Vector2(0, 48)
				te.text = str(value)
				te.text_changed.connect(func(): _set_prop(prop, te.text))
				control = te
			else:
				var le := LineEdit.new()
				le.text = str(value)
				le.text_changed.connect(func(v): _set_prop(prop, v))
				control = le
		TYPE_OBJECT:
			if hint == PROPERTY_HINT_RESOURCE_TYPE and str(p["hint_string"]).contains("Texture"):
				control = _texture(prop, value)
			else:
				control = _deferred("resource")
		_:
			control = _deferred(type_string(t))
	if control == null:
		return
	_row(_pretty(prop), control)


func _spin(prop: String, value: Variant, is_int: bool) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = -1000000000.0
	s.max_value = 1000000000.0
	s.step = 1.0 if is_int else 0.01
	s.allow_greater = true
	s.allow_lesser = true
	s.value = value
	if is_int:
		s.value_changed.connect(func(v): _set_prop(prop, int(v)))
	else:
		s.value_changed.connect(func(v): _set_prop(prop, v))
	return s


func _texture(prop: String, value: Variant) -> Control:
	var box := HBoxContainer.new()
	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(36, 36)
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture = value
	box.add_child(preview)
	box.add_child(_button("Pick…", func(): _pick_texture(prop, preview)))
	box.add_child(_button("Clear", func():
		preview.texture = null
		_set_prop(prop, null)))
	return box


func _deferred(kind: String) -> Label:
	var l := Label.new()
	l.text = "(%s: edit in Inspector. Pro authors this in-panel)" % kind
	l.modulate = HINT_COLOR
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _row(label_text: String, field: Control) -> void:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := Label.new()
	l.text = label_text
	box.add_child(l)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(field)
	_fields.add_child(box)


func _set_prop(prop: String, value: Variant) -> void:
	if _loading or _current == null:
		return
	_current.set(prop, value)


func _pretty(prop: String) -> String:
	return prop.replace("_", " ").capitalize()


# ---- create / duplicate / delete / save ----------------------------------

func _on_new() -> void:
	if not DirAccess.dir_exists_absolute(_dir):
		DirAccess.make_dir_recursive_absolute(_dir)
	var path := _unique_path(NEW_BASENAME)
	var res: Resource = RESOURCE_SCRIPT.new()
	# an id and a title to start from: new_quest / "New Quest", then new_quest_2 ...
	var stem := path.get_file().get_basename()
	if "id" in res:
		res.set("id", stem)
	for field in ["title", "name"]:
		if field in res:
			res.set(field, stem.capitalize())
	var err := ResourceSaver.save(res, path)
	if err != OK:
		_set_status("Could not create (err %d)" % err, ERR_COLOR)
		return
	_after_write(path)
	if Engine.is_editor_hint():
		EditorInterface.edit_resource(load(path))
	_set_status("Made %s. Title it here or in the Inspector, and add its objectives in the Inspector." % path, OK_COLOR)


func _on_duplicate() -> void:
	if _current == null:
		return
	var path := _unique_path(_current_path.get_file().get_basename() + "_copy")
	var err := ResourceSaver.save(_current.duplicate(false), path)
	if err != OK:
		_set_status("Duplicate failed (err %d)" % err, ERR_COLOR)
		return
	_after_write(path)


func _on_delete() -> void:
	if _current_path == "":
		return
	var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(_current_path))
	if err != OK:
		_set_status("Delete failed (err %d)" % err, ERR_COLOR)
		return
	_current = null
	_current_path = ""
	_build_fields()
	_rescan_fs()
	_refresh_list()


func _on_save() -> void:
	if _current == null or _current_path == "":
		_set_status("Select or create one first.", WARN_COLOR)
		return
	var err := ResourceSaver.save(_current, _current_path)
	if err != OK:
		_set_status("Save failed (err %d)" % err, ERR_COLOR)
		return
	_sync_cached(_current, _current_path)
	_current = _current.duplicate(false)
	_refresh_list()     # the list shows names, and this one may have just changed
	_set_status("Saved.", OK_COLOR)


func _after_write(path: String) -> void:
	_register_uid(path)
	_rescan_fs()
	_current_path = path
	_refresh_list()
	for i in _paths.size():
		if _paths[i] == path:
			_on_selected(i)
			return


# base.tres, then base_2.tres, base_3.tres. New counts new_quest files only, so
# it never lands on the Setup tab's starter_quest.tres.
func _unique_path(base: String) -> String:
	var candidate := _dir.path_join(base + ".tres")
	var n := 1
	while FileAccess.file_exists(candidate):
		n += 1
		candidate = _dir.path_join("%s_%d.tres" % [base, n])
	return candidate


# ---- dialogs -------------------------------------------------------------

func _on_choose_folder() -> void:
	_icon_setter = Callable()
	_open_dialog(EditorFileDialog.FILE_MODE_OPEN_DIR)


func _pick_texture(prop: String, preview: TextureRect) -> void:
	_icon_setter = func(path):
		var tex := load(path)
		if tex is Texture2D:
			preview.texture = tex
			_set_prop(prop, tex)
	_open_dialog(EditorFileDialog.FILE_MODE_OPEN_FILE)


func _open_dialog(mode: int) -> void:
	if _file_dialog == null:
		_file_dialog = EditorFileDialog.new()
		_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
		add_child(_file_dialog)
	for c in _file_dialog.file_selected.get_connections():
		_file_dialog.file_selected.disconnect(c.callable)
	for c in _file_dialog.dir_selected.get_connections():
		_file_dialog.dir_selected.disconnect(c.callable)
	_file_dialog.file_mode = mode
	_file_dialog.clear_filters()
	if mode == EditorFileDialog.FILE_MODE_OPEN_DIR:
		_file_dialog.dir_selected.connect(_on_dir_selected, CONNECT_ONE_SHOT)
	else:
		_file_dialog.add_filter("*.png,*.svg,*.jpg,*.jpeg,*.webp ; Images")
		_file_dialog.file_selected.connect(_on_file_selected, CONNECT_ONE_SHOT)
	_file_dialog.popup_centered_ratio(0.6)


func _on_dir_selected(path: String) -> void:
	_dir = path
	_current = null
	_current_path = ""
	_build_fields()
	_refresh_list()


func _on_file_selected(path: String) -> void:
	if _icon_setter.is_valid():
		_icon_setter.call(path)
		_icon_setter = Callable()


# The Inspector edits the file's own copy (Edit this quest… opens it there too).
# Keep the working copy in step, or the next Save here would put back whatever
# the Inspector just changed, objectives included.
func _on_inspector_edit(prop: String) -> void:
	if _current == null or _current_path == "":
		return
	var obj := EditorInterface.get_inspector().get_edited_object()
	if not (obj is Resource) or (obj as Resource).resource_path != _current_path:
		return
	_current.set(prop, obj.get(prop))
	_build_fields()


func _rescan_fs() -> void:
	if Engine.is_editor_hint():
		var fs := EditorInterface.get_resource_filesystem()
		if fs:
			fs.scan()


# The file is saved; now make the copy everyone else already holds (scene nodes, the
# Inspector) match it. take_over_path handed the path to the working copy instead,
# which left those holders with an orphaned old copy their scene then saved embedded.
func _sync_cached(saved: Resource, path: String) -> void:
	if not ResourceLoader.has_cached(path):
		saved.take_over_path(path)  # nobody holds it yet, so taking over is safe
		return
	var cached: Resource = ResourceLoader.load(path)
	if cached == saved:
		return
	for p in saved.get_property_list():
		var n: String = p.name
		if (int(p.usage) & PROPERTY_USAGE_STORAGE) and n != "script" and n != "resource_path":
			cached.set(n, saved.get(n))
	cached.emit_changed()


# A file written into a folder made this session isn't in the editor's file list
# yet, so its UID stayed unknown and the first Play of a scene using it warned
# "invalid UID" (a yellow Debugger badge). Register it the moment it's written.
static func _register_uid(path: String) -> void:
	var uid := ResourceLoader.get_resource_uid(path)
	if uid != ResourceUID.INVALID_ID and not ResourceUID.has_id(uid):
		ResourceUID.add_id(uid, path)
