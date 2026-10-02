@tool
extends Control

# Compact no-code authoring dock for the Lite tier. Reflective: it reads the
# resource's exported scalars and builds a control per field (line edit, spin,
# checkbox, texture picker), so a non-coder authors the Lite resource without the
# Inspector or hand-edited .tres. A table's entries get a row editor (item picker,
# weight, min, max); other arrays / dictionaries / sub-resources are left to the
# Inspector.
#
# Same body as the other Lite tiers' tabs, plus the entry rows at the bottom.

# ===================== CONFIG (per-pack) =====================
const RESOURCE_SCRIPT := preload("res://addons/loot_lite/loot_table.gd")
const DEFAULT_DIR := "res://loot"
const DOCK_NAME := "Loot Tables (Lite)"
const NEW_BASENAME := "new_table"
const UPGRADE_LABEL := "Pro adds nested, conditional and guaranteed entries, magic find, pity counters, and loot you see on the ground."
const UPGRADE_URL := "https://selodev.itch.io/godot-loot-system"
# The table's entries get a row editor here instead of the Inspector.
const ROWS_PROP := "entries"
const ITEM_DIR := "res://items"
# The demo's items, listed after yours as examples. The build nests the demo
# under its pack, so they sit somewhere else in the zip than here.
const DEMO_ITEM_DIRS := [
	"res://demo/loot_lite/items",
	"res://demo/items",  # repo layout
]
# New items use Inventory's item script when it's installed, so they stack in
# its bag inside a bundle. Our own is the fallback.
const ITEM_SCRIPTS := [
	"res://addons/inventory_lite/item_resource.gd",
	"res://addons/inventory/resources/item_resource.gd",
	"res://addons/loot_lite/item_resource.gd",
]
# =============================================================

const OK_COLOR := Color(0.55, 0.9, 0.55)
const ERR_COLOR := Color(0.95, 0.55, 0.55)
const WARN_COLOR := Color(0.95, 0.8, 0.35)
const HINT_COLOR := Color(0.7, 0.7, 0.7)

var _dir := DEFAULT_DIR
var _item_dir := ITEM_DIR
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
	_setup_hint.text = "Editing data here. To add this to your scene, use the ‘Loot · Setup’ tab (no code)."
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
	# In the editor the resource's script only runs as a placeholder, and its
	# properties lose the script-variable flag, so this form came up empty there.
	# Pick them by the script's own list instead.
	var own := {}
	var scr: Script = _current.get_script()
	if scr != null:
		for sp in scr.get_script_property_list():
			own[str(sp["name"])] = true
	for p in _current.get_property_list():
		var usage: int = p["usage"]
		if not own.has(str(p["name"])):
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
		TYPE_ARRAY:
			control = _rows_editor() if prop == ROWS_PROP else _deferred(type_string(t))
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
	# an id to start from, numbered like the files (new_table, new_table_2, ...)
	var stem := path.get_file().get_basename()
	if "id" in res:
		res.set("id", stem)
	if "name" in res:
		res.set("name", stem.capitalize())
	var err := ResourceSaver.save(res, path)
	if err != OK:
		_set_status("Could not create (err %d)" % err, ERR_COLOR)
		return
	# so load(path) hands back this one, not a stale copy of a deleted file
	res.take_over_path(path)
	_after_write(path)
	if Engine.is_editor_hint():
		EditorInterface.edit_resource(load(path))
	_set_status("Made %s. Add its rows below, then Save." % path, OK_COLOR)


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
	var empty := 0
	for e in rows_of(_current):
		if not (e is Dictionary and e.get("item") is Resource):
			empty += 1
	if empty > 0:
		_set_status("Saved. %d row%s no item yet, so it drops nothing when picked." % [empty, " has" if empty == 1 else "s have"], WARN_COLOR)
		return
	_set_status("Saved.", OK_COLOR)


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


func _after_write(path: String) -> void:
	_register_uid(path)
	_rescan_fs()
	_current_path = path
	_refresh_list()
	for i in _paths.size():
		if _paths[i] == path:
			_on_selected(i)
			return


# base.tres, then base_2.tres, base_3.tres, the way the Setup tab numbers its files.
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


# The Inspector edits the file's own copy. Keep the working copy in step, or the
# next Save here would put back whatever the Inspector just changed.
func _on_inspector_edit(prop: String) -> void:
	var obj := EditorInterface.get_inspector().get_edited_object()
	if obj is Resource:
		sync_from(obj, prop)


# No EditorInterface in here, the test calls it headless.
func sync_from(obj: Resource, prop: String) -> void:
	if _current == null:
		return
	if _current_path != "" and obj.resource_path == _current_path:
		_current.set(prop, obj.get(prop))
		_build_fields()
	elif obj.get("id") != null and obj.get(ROWS_PROP) == null:
		_build_fields()  # an item got renamed: the rows show its new name


# ---- entry rows ------------------------------------------------------------
# One row per entry: an item picker, the weight, and the min / max count. The
# working copy shares the file's own entries (same array, same dicts), so an
# edit goes on a copy that's then assigned back. Keys the rows don't show stay.

func _rows_editor() -> Control:
	var box := VBoxContainer.new()
	box.name = "Rows"
	var pool := item_paths()
	var rows := rows_of(_current)
	for i in rows.size():
		var e: Variant = rows[i]
		box.add_child(_row_ui(i, e if e is Dictionary else {}, pool))
	var btns := HBoxContainer.new()
	btns.add_child(_button("Add row", _on_add_row))
	btns.add_child(_button("New item", _on_new_item))
	box.add_child(btns)
	return box


func _row_ui(i: int, entry: Dictionary, pool: PackedStringArray) -> Control:
	var row := VBoxContainer.new()
	row.name = "Row%d" % i
	var top := HBoxContainer.new()
	row.add_child(top)
	var pick := OptionButton.new()
	pick.name = "Item"
	pick.clip_text = true
	# its longest entry used to set the width of the whole tab; the open list still shows every name in full
	pick.fit_to_longest_item = false
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fill_item_pick(pick, entry.get("item"), pool)
	pick.item_selected.connect(func(idx: int) -> void: _on_row_item(i, pick, idx))
	top.add_child(pick)
	var rm := _button("Remove", _on_remove_row.bind(i))
	rm.name = "Remove"
	top.add_child(rm)
	row.add_child(_row_spin("Weight", float(entry.get("weight", 1)), 0.0, i, "weight"))
	var counts := HBoxContainer.new()
	counts.add_child(_row_spin("Min", float(entry.get("min", 1)), 1.0, i, "min"))
	counts.add_child(_row_spin("Max", float(entry.get("max", 1)), 1.0, i, "max"))
	row.add_child(counts)
	row.add_child(HSeparator.new())
	return row


func _row_spin(label: String, value: float, lo: float, i: int, key: String) -> SpinBox:
	var s := SpinBox.new()
	s.name = label
	s.prefix = label
	s.min_value = lo
	s.max_value = 100000
	s.step = 1
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(v: float) -> void: set_row(i, key, int(v)))
	return s


# "(pick an item)" when a row has none. An item that isn't one of the files (a
# starter table carries its own) shows first, marked "(in this table)".
func _fill_item_pick(pick: OptionButton, current: Variant, pool: PackedStringArray) -> void:
	var cur_path := ""
	if current is Resource:
		cur_path = (current as Resource).resource_path
		if not pool.has(cur_path):
			var inside := cur_path == "" or cur_path.contains("::")
			pick.add_item(_item_label(current) + ("  (in this table)" if inside else ""))
			pick.set_item_metadata(0, current)
	else:
		pick.add_item("(pick an item)")
		pick.set_item_metadata(0, null)
	for p in pool:
		var mine := p.get_base_dir() == _item_dir.trim_suffix("/")
		pick.add_item(_item_label(load(p)) + ("" if mine else "  (example)"))
		pick.set_item_metadata(pick.item_count - 1, p)
	for idx in pick.item_count:
		var m: Variant = pick.get_item_metadata(idx)
		if (m is String and m == cur_path) or (m is Resource and m == current):
			pick.select(idx)
			return
	pick.select(0)


func _on_row_item(i: int, pick: OptionButton, idx: int) -> void:
	var m: Variant = pick.get_item_metadata(idx)
	set_row(i, "item", load(m) if m is String else m)


func _on_add_row() -> void:
	if _current == null:
		_set_status("Select or create a table first.", WARN_COLOR)
		return
	add_row()
	_build_fields()
	_set_status("Added a row. Pick its item, then Save.", OK_COLOR)


func _on_remove_row(i: int) -> void:
	remove_row(i)
	_build_fields()
	_set_status("Removed a row. Save to keep the change.", OK_COLOR)


func _on_new_item() -> void:
	if _current == null:
		_set_status("Select or create a table first.", WARN_COLOR)
		return
	var path := make_item(_item_dir)
	if path == "":
		_set_status("Couldn't write a new item into %s." % _item_dir, ERR_COLOR)
		return
	_rescan_fs()
	add_row(load(path))
	_build_fields()
	if Engine.is_editor_hint():
		EditorInterface.edit_resource(load(path))
	_set_status("Made %s and gave it a row. Name it and pick an icon in the Inspector, then Save." % path, OK_COLOR)


# A copy of the table's entries that's safe to edit: new dicts, same items.
func rows_of(table: Resource) -> Array:
	if table == null or not (table.get(ROWS_PROP) is Array):
		return []
	return (table.get(ROWS_PROP) as Array).duplicate(true)


func set_row(i: int, key: String, value: Variant) -> void:
	if _loading or _current == null:
		return
	var rows := rows_of(_current)
	if i < 0 or i >= rows.size():
		return
	var e: Dictionary = rows[i] if rows[i] is Dictionary else {}
	e[key] = value
	rows[i] = e
	_current.set(ROWS_PROP, rows)


func add_row(item: Resource = null) -> void:
	if _current == null:
		return
	var rows := rows_of(_current)
	rows.append({"item": item, "weight": 10, "min": 1, "max": 1})
	_current.set(ROWS_PROP, rows)


func remove_row(i: int) -> void:
	if _current == null:
		return
	var rows := rows_of(_current)
	if i < 0 or i >= rows.size():
		return
	rows.remove_at(i)
	_current.set(ROWS_PROP, rows)


# The pickers' items: yours in res://items first, then the demo's as examples.
func item_paths(own: String = "", demo_dirs: Array = DEMO_ITEM_DIRS) -> PackedStringArray:
	var out := _scan_items(own if own != "" else _item_dir)
	for d in demo_dirs:
		if DirAccess.dir_exists_absolute(str(d)):
			out.append_array(_scan_items(str(d)))
			break
	return out


# Anything with an id and a name that isn't a table, so Inventory's items count.
func _scan_items(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.get_extension() == "tres":
			var res := load(dir_path.path_join(f))
			if res != null and res.get("id") != null and res.get("name") != null and res.get(ROWS_PROP) == null:
				out.append(dir_path.path_join(f))
		f = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


# A new item with a name and an id to start from: new_item.tres, new_item_2.tres,
# ... Returns its path, or "" if it couldn't be written.
func make_item(dir: String = ITEM_DIR) -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("new_item.tres")
	var n := 1
	while FileAccess.file_exists(path):
		n += 1
		path = dir.path_join("new_item_%d.tres" % n)
	var script_path := ""
	for sp in ITEM_SCRIPTS:
		if ResourceLoader.exists(sp):
			script_path = sp
			break
	var it: Resource = load(script_path).new()
	var stem := path.get_file().get_basename()
	it.set("id", stem)
	it.set("name", stem.capitalize())
	if ResourceSaver.save(it, path) != OK:
		return ""
	it.take_over_path(path)  # load(path) gives this one, so Inspector edits land in the file
	_register_uid(path)
	return path


func _item_label(item: Variant) -> String:
	if not (item is Resource):
		return "(item)"
	for key in ["name", "id"]:
		var v: Variant = (item as Resource).get(key)
		if v != null and str(v) != "":
			return str(v)
	return (item as Resource).resource_path.get_file().get_basename()


func _rescan_fs() -> void:
	if Engine.is_editor_hint():
		var fs := EditorInterface.get_resource_filesystem()
		if fs:
			fs.scan()


# A file written into a folder made this session isn't in the editor's file list
# yet, so its UID stayed unknown and the first Play of a scene using it warned
# "invalid UID" (a yellow Debugger badge). Register it the moment it's written.
static func _register_uid(path: String) -> void:
	var uid := ResourceLoader.get_resource_uid(path)
	if uid != ResourceUID.INVALID_ID and not ResourceUID.has_id(uid):
		ResourceUID.add_id(uid, path)
