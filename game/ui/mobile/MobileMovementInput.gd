class_name MobileMovementInput
extends RefCounted


var _value := Vector2.ZERO


func set_value(value: Vector2) -> void:
	_value = value.limit_length(1.0)


func clear() -> void:
	_value = Vector2.ZERO


func merged_with(physical: Vector2) -> Vector2:
	return physical if physical.length_squared() >= _value.length_squared() else _value
