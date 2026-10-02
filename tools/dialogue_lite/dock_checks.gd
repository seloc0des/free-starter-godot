extends RefCounted

# The Dialogue (Lite) authoring dock's node ids. They have to stay unique after a
# delete: two nodes sharing an id means the dock edits one and the game plays the
# other. Nothing here touches res://dialogues/, it all stays in memory.

const DOCK := preload("res://addons/dialogue_lite/editor/dialogue_lite_dock.gd")


static func run(host: Node) -> Dictionary:
	var lines: Array[String] = []
	var ok := true
	var dock: Control = DOCK.new()
	host.add_child(dock)  # _ready builds the form fields the helpers write into

	dock._on_new()
	dock._on_add_node()
	dock._on_add_node()
	ok = _chk(lines, _ids(dock) == ["node_1", "node_2"], "dock: fresh nodes get node_1, node_2 (got %s)" % str(_ids(dock))) and ok
	dock._node = dock._dialogue.nodes[0]
	dock._on_remove_node()
	dock._on_add_node()
	ok = _chk(lines, _ids(dock) == ["node_2", "node_1"], "dock: after deleting node_1, Add reuses node_1 instead of a second node_2 (got %s)" % str(_ids(dock))) and ok
	dock._on_add_node()
	ok = _chk(lines, _ids(dock) == ["node_2", "node_1", "node_3"], "dock: the next one is node_3 (got %s)" % str(_ids(dock))) and ok
	var seen := {}
	var unique := true
	for id in _ids(dock):
		unique = unique and not seen.has(id)
		seen[id] = true
	ok = _chk(lines, unique, "dock: no id is handed out twice") and ok

	dock.free()
	return {"ok": ok, "lines": lines}


static func _ids(dock: Control) -> Array:
	var out: Array = []
	for n in dock._dialogue.nodes:
		if n != null:
			out.append(String(n.id))
	return out


static func _chk(lines: Array[String], cond: bool, label: String) -> bool:
	lines.append(("[ok] " if cond else "[XX] ") + label)
	return cond
