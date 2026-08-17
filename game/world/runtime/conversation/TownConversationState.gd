class_name TownConversationState
extends RefCounted


var records: Dictionary = {}
var autonomous_idle_seconds: Dictionary = {}
var autonomous_timeout_tick_seconds := 0.0
var sequence := 0


func reset() -> void:
	records.clear()
	autonomous_idle_seconds.clear()
	autonomous_timeout_tick_seconds = 0.0
	sequence = 0


func restore(
	prepared_records: Dictionary,
	prepared_idle_seconds: Dictionary,
	prepared_sequence: int,
) -> void:
	records = prepared_records.duplicate(true)
	autonomous_idle_seconds = prepared_idle_seconds.duplicate(true)
	autonomous_timeout_tick_seconds = 0.0
	sequence = prepared_sequence


func next_id() -> String:
	sequence += 1
	return "conversation-%d" % sequence
