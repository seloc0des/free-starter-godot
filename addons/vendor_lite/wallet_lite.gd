class_name WalletLite
extends Node

# Single-currency wallet. The currency id is just a label — there's only one
# in Lite. Use `currency_id = "gold"` or whatever fits your world.

signal balance_changed(new_total: int)

@export var currency_id: String = "gold"
@export var starting_balance: int = 0

var _balance: int = 0


func _ready() -> void:
	_balance = starting_balance


func get_balance() -> int:
	return _balance


func has_amount(amount: int) -> bool:
	return _balance >= amount


func add(amount: int) -> void:
	if amount <= 0:
		return
	_balance += amount
	balance_changed.emit(_balance)


func subtract(amount: int) -> bool:
	if amount <= 0 or _balance < amount:
		return false
	_balance -= amount
	balance_changed.emit(_balance)
	return true


func set_balance(amount: int) -> void:
	_balance = max(0, amount)
	balance_changed.emit(_balance)
