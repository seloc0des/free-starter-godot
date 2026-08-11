class_name StatsComponentLite
extends Node

# Stat aggregator. Same modifier shape and math as the Pro tier — three ops
# (flat / percent_add / percent_mult), same formula. Drop in a StatSet (array
# of StatDefinitionLite) and call add_modifier / get_stat.
#
# Cut from Pro:
#   * Skill tree runtime + UI (the headline feature)
#   * Equipment auto-bridge (`equipment_paths` + bus subscription)
#   * Timed buffs with auto-expiry
#   * Save-contract auto-join
#   * Atomic `replace_modifiers(source_id, mods)` swap
#   * StatsPanelUI Control with breakdown tooltips
#   * Shared Events autoload

signal stat_changed(stat_id: String, new_value: float)
signal modifier_added(stat_id: String, source_id: String)
signal modifier_removed(stat_id: String, source_id: String)

## Array of StatDefinitionLite Resources defining each stat's base + clamp.
@export var definitions: Array[StatDefinitionLite] = []

var _base_overrides: Dictionary = {}  # stat_id -> float
var _modifiers: Array = []  # Array of {stat, op, amount, source_id?}


func find(stat_id: String) -> StatDefinitionLite:
	for d in definitions:
		if d != null and String(d.id) == stat_id:
			return d
	return null


func get_base(stat_id: String) -> float:
	if _base_overrides.has(stat_id):
		return float(_base_overrides[stat_id])
	var d := find(stat_id)
	return float(d.base_value) if d != null else 0.0


func set_base(stat_id: String, value: float) -> void:
	_base_overrides[stat_id] = value
	stat_changed.emit(stat_id, get_stat(stat_id))


func get_stat(stat_id: String) -> float:
	return float(get_breakdown(stat_id).final)


func get_breakdown(stat_id: String) -> Dictionary:
	var base := get_base(stat_id)
	var flat := 0.0
	var pct_add := 0.0
	var pct_mult := 1.0
	for m in _modifiers:
		if String(m.get("stat", "")) != stat_id:
			continue
		var amt := float(m.get("amount", 0.0))
		match String(m.get("op", "flat")):
			"flat":
				flat += amt
			"percent_add", "percent":
				pct_add += amt
			"percent_mult":
				pct_mult *= 1.0 + (amt / 100.0)
	var raw := (base + flat) * (1.0 + pct_add / 100.0) * pct_mult
	var d := find(stat_id)
	var final := raw
	if d != null:
		final = clampf(raw, d.min_value, d.max_value)
	return {"base": base, "flat": flat, "percent_add": pct_add,
		"percent_mult": pct_mult, "raw": raw, "final": final}


## Accepts a Dictionary `{stat, op, amount, source_id}`. `op` defaults to
## "flat". `source_id` defaults to "" — set it if you want to remove the
## modifier later.
func add_modifier(mod: Dictionary) -> void:
	var entry := mod.duplicate()
	if not entry.has("op"):
		entry["op"] = "flat"
	if not entry.has("amount"):
		entry["amount"] = 0.0
	if not entry.has("source_id"):
		entry["source_id"] = ""
	_modifiers.append(entry)
	var sid := String(entry.stat)
	stat_changed.emit(sid, get_stat(sid))
	modifier_added.emit(sid, String(entry.source_id))


## Remove every modifier matching `source_id`. Returns the number removed.
func remove_modifier(source_id: String) -> int:
	if source_id == "":
		return 0
	var affected := {}
	var removed := 0
	var i := _modifiers.size() - 1
	while i >= 0:
		var m: Dictionary = _modifiers[i]
		if String(m.get("source_id", "")) == source_id:
			affected[String(m.get("stat", ""))] = true
			_modifiers.remove_at(i)
			removed += 1
		i -= 1
	for sid in affected.keys():
		stat_changed.emit(String(sid), get_stat(String(sid)))
		modifier_removed.emit(String(sid), source_id)
	return removed


func clear_modifiers() -> void:
	var affected := {}
	for m in _modifiers:
		affected[String(m.get("stat", ""))] = true
	_modifiers.clear()
	for sid in affected.keys():
		stat_changed.emit(String(sid), get_stat(String(sid)))


# ---- snapshot for manual save layers --------------------------------------

func snapshot() -> Dictionary:
	return {
		"base_overrides": _base_overrides.duplicate(true),
		"modifiers": _modifiers.duplicate(true),
	}


func restore(data: Dictionary) -> void:
	_base_overrides = data.get("base_overrides", {}).duplicate(true)
	_modifiers = data.get("modifiers", []).duplicate(true)
	for d in definitions:
		if d == null:
			continue
		stat_changed.emit(String(d.id), get_stat(String(d.id)))
