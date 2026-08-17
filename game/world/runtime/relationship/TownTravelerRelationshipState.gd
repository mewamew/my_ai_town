class_name TownTravelerRelationshipState
extends RefCounted


const RUNTIME := preload(
	"res://world/runtime/relationship/TownTravelerRelationshipRuntime.gd"
)

var _snapshot: Dictionary = RUNTIME.empty_snapshot()


func reset() -> void:
	_snapshot = RUNTIME.empty_snapshot()


func snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func restore(
	value: Variant,
	avatar_id: String,
	resident_ids: Array,
) -> void:
	_snapshot = RUNTIME.normalize_snapshot(value, avatar_id, resident_ids)


func record_ended_conversation(
	avatar_id: String,
	resident_id: String,
	conversation: Dictionary,
) -> bool:
	return RUNTIME.record_ended_conversation(
		_snapshot,
		avatar_id,
		resident_id,
		conversation,
	)


func record_resident_reply(
	avatar_id: String,
	resident_id: String,
	conversation: Dictionary,
	turn: Dictionary,
	delta: int,
) -> bool:
	return RUNTIME.record_resident_reply(
		_snapshot,
		avatar_id,
		resident_id,
		conversation,
		turn,
		delta,
	)


func record_avatar_attack(
	avatar_id: String,
	resident_id: String,
	attack_id: String,
	interaction_at: Dictionary,
) -> bool:
	return RUNTIME.record_avatar_attack(
		_snapshot,
		avatar_id,
		resident_id,
		attack_id,
		interaction_at,
	)


func projection_for_resident(
	avatar_id: String,
	avatar_name: String,
	resident_id: String,
	include_default := false,
) -> Dictionary:
	return RUNTIME.projection_for_resident(
		_snapshot,
		avatar_id,
		avatar_name,
		resident_id,
		include_default,
	)


func agent_projection_for_resident(
	avatar_id: String,
	resident_id: String,
) -> Dictionary:
	return RUNTIME.agent_projection_for_resident(
		_snapshot,
		avatar_id,
		resident_id,
	)


func append_public_projection(
	items: Array[Dictionary],
	avatar_id: String,
	avatar_name: String,
	resident_id: String,
) -> void:
	var relation := projection_for_resident(
		avatar_id,
		avatar_name,
		resident_id,
	)
	if not relation.is_empty():
		items.append(relation)


func record_avatar_attack_result(
	result: Dictionary,
	intent: Dictionary,
	avatar_id: String,
	interaction_at: Dictionary,
) -> int:
	if result.get("ok") != true:
		return 0
	var attack_id := String(result.get("castId", intent.get("requestId", "")))
	var changed_count := 0
	for target_value: Variant in result.get("hitTargetIds", []) as Array:
		if record_avatar_attack(
			avatar_id,
			String(target_value),
			attack_id,
			interaction_at,
		):
			changed_count += 1
	return changed_count
