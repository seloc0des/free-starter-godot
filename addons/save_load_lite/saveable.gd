class_name SaveableLite
extends Node

# Drop this Node on any parent and list the properties you want persisted in
# `save_properties`. On save, the named properties are read from the parent.
# On load, they're written back.
#
# Joins the SaveLite contract group automatically. Use `save_id` to make the
# id stable across scene reloads — defaults to the parent's NodePath if blank.
#
# For full control (custom serialization, dependencies on other state), skip
# this node and implement `get_save_id / save_state / load_state` directly on
# your own node, then add it to the `save_load_contract_lite` group.

@export var save_id: String = ""
@export var save_properties: PackedStringArray = PackedStringArray()


func _ready() -> void:
	add_to_group(SaveLite.CONTRACT_GROUP)


func get_save_id() -> String:
	if save_id != "":
		return save_id
	var parent := get_parent()
	if parent == null:
		return "anonymous_%d" % get_instance_id()
	return str(parent.get_path())


func save_state() -> Dictionary:
	var parent := get_parent()
	if parent == null:
		return {}
	var data: Dictionary = {}
	for prop_name in save_properties:
		var key := String(prop_name)
		if key in parent:
			data[key] = parent.get(key)
	return data


func load_state(data: Dictionary) -> void:
	var parent := get_parent()
	if parent == null:
		return
	for key in data.keys():
		if String(key) in parent:
			parent.set(String(key), data[key])
