extends Node

# Stand-in for the player's bag in the tests: the same add_item / remove_item /
# count_item a real inventory has. `room` caps how much it holds.

var room := 999
var _counts := {}


func add_item(item: Resource, amount: int = 1) -> int:
	var id := str(item.get("id"))
	var take := clampi(amount, 0, maxi(0, room - total()))
	_counts[id] = int(_counts.get(id, 0)) + take
	return amount - take


func remove_item(item: Resource, amount: int = 1) -> int:
	var id := str(item.get("id"))
	var take := mini(amount, int(_counts.get(id, 0)))
	_counts[id] = int(_counts.get(id, 0)) - take
	return take


func count_item(item: Resource) -> int:
	return int(_counts.get(str(item.get("id")), 0))


func total() -> int:
	var n := 0
	for v in _counts.values():
		n += int(v)
	return n
