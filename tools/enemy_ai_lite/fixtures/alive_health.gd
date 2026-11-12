extends Node

# Test stand-in for a health node that answers is_alive() (CombatHealth and
# HealthLite both do): flip `alive` to kill or revive it.

signal died

var alive := true


func is_alive() -> bool:
	return alive


func fraction() -> float:
	return 1.0 if alive else 0.0
