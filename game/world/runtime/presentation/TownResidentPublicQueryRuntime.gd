class_name TownResidentPublicQueryRuntime
extends RefCounted


const CONVERSATION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationRuntime.gd"
)
const RESIDENT_MOVEMENT_PROJECTION := preload(
	"res://world/runtime/presentation/TownResidentMovementProjection.gd"
)
const RESIDENT_STATE_PROJECTION := preload(
	"res://world/runtime/presentation/TownResidentStateProjection.gd"
)
const ACTION_PRESENTATION := preload(
	"res://world/runtime/presentation/TownActionPresentationSemantics.gd"
)
const RELATIONSHIP_EVIDENCE_PROGRESS := preload(
	"res://world/runtime/relationship/TownRelationshipEvidenceProgress.gd"
)


static func names(host) -> Array[String]:
	var result: Array[String] = []
	for resident_id in host.resident_registry.order:
		result.append(String(host.resident_registry.name_by_id.get(resident_id, "")))
	return result


static func ids(host) -> Array[String]:
	return host.resident_registry.order.duplicate()


static func identity_snapshot(host) -> Dictionary:
	var residents: Array[Dictionary] = []
	var resident_ids: Array[String] = []
	for resident_id_value: Variant in host.resident_registry.name_by_id:
		resident_ids.append(String(resident_id_value))
	resident_ids.sort()
	for resident_id in resident_ids:
		residents.append({
			"residentId": resident_id,
			"residentName": String(
				host.resident_registry.name_by_id.get(resident_id, ""),
			),
		})
	return {
		"status": host.resident_registry.identity_status,
		"residents": residents,
	}


static func state(host, resident_ref: String) -> Dictionary:
	var resident_id: String = host._resident_key(resident_ref)
	if resident_id.is_empty():
		return {}
	return host.RESIDENT_STATE_PROJECTION.project(host,
		host.resident_registry.records[resident_id] as Dictionary,
	)


static func lifecycle_state(host, resident_ref: String) -> Dictionary:
	var resident_id: String = host._resident_key(resident_ref)
	if resident_id.is_empty():
		return {}
	return (
		host._resident_lifecycle.get_resident_state(resident_id) as Dictionary
	).duplicate(true)


static func public_death_events(host) -> Array[Dictionary]:
	return (
		host._resident_lifecycle.get_public_death_events() as Array
	).duplicate(true)


static func action_phase(host, resident_ref: String) -> Dictionary:
	var resident_id: String = host._resident_key(resident_ref)
	if resident_id.is_empty():
		return {}
	return ACTION_PRESENTATION._resident_action_phase_projection(
		host,
		host.resident_registry.records[resident_id] as Dictionary,
	)


static func relationship_progress(host, resident_ref: String) -> Dictionary:
	if not host._running:
		return host._command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var resident_id: String = host._resident_key(resident_ref)
	if resident_id.is_empty():
		return host._command_failure("RESIDENT_NOT_FOUND", ["找不到要查看的居民"])
	var resident_names := {}
	for other_id_value: Variant in host.resident_registry.name_by_id:
		var other_id := String(other_id_value)
		resident_names[other_id] = String(
			host.resident_registry.name_by_id.get(other_id, ""),
		)
	var items: Array = RELATIONSHIP_EVIDENCE_PROGRESS.build(
		resident_id,
		resident_names,
		host.conversation_state.records.values(),
		host._social_matters.list_matters(true) as Array,
		host.get_public_conflict_projection().get("events", []) as Array,
	)
	host._traveler_relationship_state.append_public_projection(
		items,
		host.player_avatar_id(),
		String(host.actor_presentation_state.player_avatar.get("name", "旅行者")),
		resident_id,
	)
	return {
		"ok": true,
		"residentId": resident_id,
		"items": items,
		"worldRevision": host._world_revision,
	}


static func movement_snapshot(host, resident_ref: String) -> Dictionary:
	var resident_id: String = host._resident_key(resident_ref)
	if resident_id.is_empty():
		return {}
	var resident := host.resident_registry.records[resident_id] as Dictionary
	var movement_rules := (
		host.world_definition.world_data.get("movementRules", {}) as Dictionary
	)
	return RESIDENT_MOVEMENT_PROJECTION.project(
		resident_id,
		resident,
		int(host._environment.get_absolute_minute()),
		host._world_revision,
		CONVERSATION_RUNTIME._resident_has_suspended_conversation(host, resident),
		float(movement_rules.get("outdoorDistancePerGameMinute", 0.0)),
	)


static func all_states(host) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for resident_id in host.resident_registry.order:
		result.append(host.get_resident_state(resident_id))
	return result


# town_hud 专用轻量投影：只计算 HUD 实际消费的键。
static func hud_states(host) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for resident_id in host.resident_registry.order:
		result.append(RESIDENT_STATE_PROJECTION.project_hud(
			host,
			host.resident_registry.records[resident_id] as Dictionary,
		))
	return result


static func detail(host, resident_ref: String) -> Dictionary:
	var resident_id: String = host._resident_key(resident_ref)
	if resident_id.is_empty():
		return {}
	var resident := host.resident_registry.records[resident_id] as Dictionary
	return {
		"residentId": resident_id,
		"name": String(
			(resident.get("attributes", {}) as Dictionary).get("name", ""),
		),
		"attributes": (
			resident.get("attributes", {}) as Dictionary
		).duplicate(true),
		"socialState": (
			resident.get("socialState", {}) as Dictionary
		).duplicate(true),
		"runtimeState": host.RESIDENT_STATE_PROJECTION.project(host, resident),
	}
