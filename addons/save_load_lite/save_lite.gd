extends Node

# Save / Load — Lite. Single-slot JSON save/load. Nodes in the
# `save_load_contract_lite` group with `get_save_id() / save_state() / load_state()`
# methods participate.
#
# This is the **working core** of the selodev Save addon. Features cut from
# the paid Pro tier:
#
#   * Multi-slot save/load                 — Pro
#   * Autosave on interval or signal       — Pro
#   * Encrypted binary backend             — Pro
#   * Atomic writes (tmp+rename)           — Pro
#   * Schema migrations                    — Pro
#   * Editor dock (list/inspect/duplicate) — Pro
#   * Screenshots in slot metadata         — Pro
#   * Side-channel slots (e.g. settings)   — Pro
#
# See docs/upgrade.md for the paid tier.

signal save_completed(path: String)
signal load_completed(path: String)
signal save_failed(reason: String)
signal load_failed(reason: String)

const CONTRACT_GROUP := "save_load_contract_lite"
const DEFAULT_PATH := "user://save.json"


## Save every node in the contract group to `path`. Returns true on success.
func save(path: String = DEFAULT_PATH) -> bool:
	var data: Dictionary = {
		"version": 1,
		"nodes": {},
	}
	for node in get_tree().get_nodes_in_group(CONTRACT_GROUP):
		if not node.has_method("save_state") or not node.has_method("get_save_id"):
			continue
		var id := String(node.get_save_id())
		var state = node.save_state()
		if state is Dictionary:
			data.nodes[id] = state
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		save_failed.emit("cannot_open: %s" % path)
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	save_completed.emit(path)
	return true


## Load from `path` and dispatch state to each node in the contract group by
## matching get_save_id(). Returns true on success.
func load(path: String = DEFAULT_PATH) -> bool:
	if not FileAccess.file_exists(path):
		load_failed.emit("not_found: %s" % path)
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		load_failed.emit("cannot_open: %s" % path)
		return false
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		load_failed.emit("malformed_json: %s" % path)
		return false
	var nodes_data: Dictionary = parsed.get("nodes", {})
	for node in get_tree().get_nodes_in_group(CONTRACT_GROUP):
		if not node.has_method("load_state") or not node.has_method("get_save_id"):
			continue
		var id := String(node.get_save_id())
		if nodes_data.has(id):
			node.load_state(nodes_data[id])
	load_completed.emit(path)
	return true


func has_save(path: String = DEFAULT_PATH) -> bool:
	return FileAccess.file_exists(path)


func delete_save(path: String = DEFAULT_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var err := DirAccess.remove_absolute(path)
	return err == OK
