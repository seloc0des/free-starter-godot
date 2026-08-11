class_name StatDefinitionLite
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var base_value: float = 0.0
@export var min_value: float = -1.0e9
@export var max_value: float = 1.0e9
@export var format_template: String = ""


func format_value(v: float) -> String:
	var fmt := format_template if format_template != "" else "%.2f"
	return fmt % v
