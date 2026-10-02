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
	add_to_group(SAVE_LITE.CONTRACT_GROUP)


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
			data[key] = _to_json(parent.get(key))
	return data


func load_state(data: Dictionary) -> void:
	var parent := get_parent()
	if parent == null:
		return
	for key in data.keys():
		if String(key) in parent:
			parent.set(String(key), _from_json(data[key], parent.get(String(key))))


# JSON turns a Vector2 into "(1.0, 2.0)", which nothing can read back, so position,
# colours and friends are stored as Godot's own text form instead.
const _TEXT_TYPES := [TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_RECT2, TYPE_RECT2I, TYPE_VECTOR3,
	TYPE_VECTOR3I, TYPE_TRANSFORM2D, TYPE_VECTOR4, TYPE_VECTOR4I, TYPE_PLANE, TYPE_QUATERNION,
	TYPE_AABB, TYPE_BASIS, TYPE_TRANSFORM3D, TYPE_COLOR]


func _to_json(v: Variant) -> Variant:
	if typeof(v) in _TEXT_TYPES:
		return var_to_str(v)
	return v


func _from_json(v: Variant, current: Variant) -> Variant:
	# only rebuild the type the property already has, never anything else
	if v is String and typeof(current) in _TEXT_TYPES and String(v).begins_with(type_string(typeof(current))):
		var back: Variant = str_to_var(v)
		if typeof(back) == typeof(current):
			return back
	# JSON hands every number back as a float
	if v is float and typeof(current) == TYPE_INT:
		return int(v)
	# and every array untyped, which an Array[String] export refuses
	if v is Array and current is Array and current.is_typed() and current.get_typed_builtin() != TYPE_OBJECT:
		var typed: Array = current.duplicate()
		typed.assign(v)
		return typed
	return v


# SaveLite is reached through its script instead of named. A script that names an
# autoload won't compile until the plugin that adds it is switched on, so a fresh
# install printed parse errors.
const SAVE_LITE := preload("res://addons/save_load_lite/save_lite.gd")
