class_name TownActivityRoutineState
extends RefCounted


var records: Dictionary = {}


func reset() -> void:
	records.clear()


func restore(prepared: Dictionary) -> void:
	records = prepared.duplicate(true)


func snapshot() -> Dictionary:
	return records.duplicate(true)
