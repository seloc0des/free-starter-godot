class_name LootTableLite
extends Resource

# Weighted loot table. Each entry has an item, weight, min/max count. Rolling
# the table picks `rolls` entries (with replacement) using the weights, and
# returns an Array of {item, count} dictionaries.
#
# Cut from Pro:
#   * Nested LootTable entries (a roll points at another table)
#   * Conditional entries (drop only if flag X, biome Y, kill count Z)
#   * Guaranteed entries (no weight roll)
#   * Magic-find boost on rare-tagged entries
#   * Pity counters
#   * Deterministic RNG seed override
#   * `LootDropSource` Node + `WorldDrop` scene
#   * Inventory addon bridge

@export var id: String = ""
## Each entry is a Dictionary: {item: Resource, weight: int, min: int, max: int}.
## Inspector exposes this as an Array of Dictionaries.
@export var entries: Array = []
## How many rolls per call to `roll()`. Default 1.
@export var rolls: int = 1


func roll(rng: RandomNumberGenerator = null) -> Array:
	if entries.is_empty() or rolls <= 0:
		return []
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var total_weight := 0.0
	for e in entries:
		total_weight += max(0.0, float(e.get("weight", 1)))
	if total_weight <= 0.0:
		return []
	var out: Array = []
	for _i in range(rolls):
		var pick := rng.randf() * total_weight
		var acc := 0.0
		for e in entries:
			acc += max(0.0, float(e.get("weight", 1)))
			if pick <= acc:
				var min_c := int(e.get("min", 1))
				var max_c := int(e.get("max", 1))
				var count := rng.randi_range(min_c, maxi(min_c, max_c))
				out.append({"item": e.get("item"), "count": count})
				break
	return out


# Helper for factory scripts — builds an entry dict.
static func entry(item: Resource, weight: int, min_count: int = 1, max_count: int = 1) -> Dictionary:
	return {"item": item, "weight": weight, "min": min_count, "max": max_count}
