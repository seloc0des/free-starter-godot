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
const RESOURCE_SCRIPT := preload("res://addons/stats_skills_lite/stat_definition_lite.gd")
const DEFAULT_DIR := "res://stats"
const DOCK_NAME := "Stats (Lite)"
const NEW_BASENAME := "new_stat"
const UPGRADE_LABEL := "Pro adds skill trees, modifier stacking, XP/levels, three docks + one-click wiring + the EventTrigger node."
const UPGRADE_URL := "https://selodev.itch.io/stats-skill-trees-no-code-character-progression-for-godot-4"
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
	custom_minimum_size = Vector2(320, 420)
	_build_ui()
	_refresh_list()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var _setup_hint := Label.new()
	_setup_hint.text = "Editing data here. To add this to your scene, use the ‘Stats · Setup’ tab (no code)."
	_setup_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_setup_hint.modulate = Color(0.66, 0.7, 0.8)
	root.add_child(_setup_hint)

	var header := HBoxContainer.new()
	root.add_child(header)
	_dir_label = Label.new()
	_dir_label.text = _dir
	_dir_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_dir_label)
	header.add_child(_button("Folder…", _on_choose_folder))

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 120
	root.add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(120, 0)
	split.add_child(left)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_selected)
	left.add_child(_list)
	var lb := HBoxContainer.new()
	left.add_child(lb)
	lb.add_child(_button("New", _on_new))
	lb.add_child(_button("Dup", _on_duplicate))
	lb.add_child(_button("Del", _on_delete))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(scroll)
	_fields = VBoxContainer.new()
	_fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_fields)

	root.add_child(HSeparator.new())
	root.add_child(_button("Save", _on_save))
	_status = Label.new()
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
		_list.add_item(p.get_file().get_basename())
	for i in _paths.size():
		if _paths[i] == _current_path:
			_list.select(i)


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
		c.queue_free()
	if _current == null:
		return
	_loading = true
	for p in _current.get_property_list():
		var usage: int = p["usage"]
		if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		if not (usage & PROPERTY_USAGE_EDITOR):
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
	var err := ResourceSaver.save(res, path)
	if err != OK:
		_set_status("Could not create (err %d)" % err, ERR_COLOR)
		return
	_after_write(path)


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
	_current.take_over_path(_current_path)
	_current = _current.duplicate(false)
	_set_status("Saved.", OK_COLOR)


func _after_write(path: String) -> void:
	_rescan_fs()
	_current_path = path
	_refresh_list()
	for i in _paths.size():
		if _paths[i] == path:
			_on_selected(i)
			return


func _unique_path(base: String) -> String:
	var candidate := _dir.path_join(base + ".tres")
	var n := 1
	while FileAccess.file_exists(candidate):
		candidate = _dir.path_join("%s_%d.tres" % [base, n])
		n += 1
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


func _rescan_fs() -> void:
	if Engine.is_editor_hint():
		var fs := EditorInterface.get_resource_filesystem()
		if fs:
			fs.scan()
