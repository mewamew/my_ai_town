class_name TownConflictWorldCoordinationRuntime
extends RefCounted


const WORLD_LOG_COMMIT_RUNTIME := preload(
	"res://world/runtime/log/TownWorldLogCommitRuntime.gd"
)


const KNOWLEDGE_PROJECTOR := preload(
	"res://world/runtime/conflict/TownConflictKnowledgeProjector.gd"
)
const RUNTIME_LOG_TEXT := preload(
	"res://world/runtime/log/TownRuntimeLogText.gd"
)
const DOMAIN_LOG_PROJECTION := preload(
	"res://world/runtime/log/TownWorldDomainLogProjection.gd"
)
const CONFLICT_JUDGMENTS := preload(
	"res://world/runtime/conflict/TownConflictJudgments.gd"
)
const AGENT_WORLD_QUERY_RUNTIME := preload(
	"res://world/runtime/agent/TownAgentWorldQueryRuntime.gd"
)
const CLINIC_CONTINUITY_RUNTIME := preload(
	"res://world/runtime/condition/TownClinicContinuityRuntime.gd"
)


static func advance(host) -> void:
	var conflict_controller = host._conflict_controller
	if conflict_controller == null:
		return
	CLINIC_CONTINUITY_RUNTIME.advance_external_aid(
		host,
		conflict_controller,
		host.ACTION_SUPPORT.absolute_minute(host.get_time()),
	)
	var before_revision := runtime_revision(host)
	var result := conflict_controller.advance() as Dictionary
	complete_command(host, result, before_revision)


static func public_projection(host) -> Dictionary:
	if host._conflict_controller == null:
		return empty_projection()
	return (
		host._conflict_controller.get_public_projection() as Dictionary
	).duplicate(true)


static func submit_attack(host, intent: Dictionary) -> Dictionary:
	if not host._running or host._conflict_controller == null:
		return host._command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	for field: String in ["attackerId", "targetId"]:
		var actor_id := String(intent.get(field, "")).strip_edges()
		if not actor_id.is_empty() and not host._resident_is_alive(actor_id):
			return host._command_failure("RESIDENT_DEAD", ["死亡居民不能参与冲突"])
		if not actor_is_available(host, actor_id):
			return host._command_failure(
				"CONFLICT_ACTOR_NOT_AVAILABLE",
				["冲突参与者当前不在场"],
			)
	var before_revision := runtime_revision(host)
	var result := host._conflict_controller.begin_attack(intent) as Dictionary
	return complete_command(host, result, before_revision)


static func submit_tension_action(host, intent: Dictionary) -> Dictionary:
	if not host._running or host._conflict_controller == null:
		return host._command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	for field: String in ["actorId", "targetId"]:
		if not actor_is_available(host, String(intent.get(field, ""))):
			return host._command_failure(
				"CONFLICT_ACTOR_NOT_AVAILABLE",
				["争执参与者当前不在场"],
			)
	var before_revision := runtime_revision(host)
	var result := host._conflict_controller.apply_tension_action(intent) as Dictionary
	return complete_command(host, result, before_revision)


static func submit_avatar_area_attack(host, intent: Dictionary) -> Dictionary:
	if not host._running or host._conflict_controller == null:
		return host._command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	if not actor_is_available(host, String(intent.get("attackerId", ""))):
		return host._command_failure("AVATAR_NOT_PRESENT", ["化身当前不在小镇中"])
	var before_revision := runtime_revision(host)
	var result := host._conflict_controller.begin_avatar_area_attack(intent) as Dictionary
	var relationship_changes: Variant = host._traveler_relationship_state.record_avatar_attack_result(
		result,
		intent,
		host.player_avatar_id(),
		host.get_time(),
	)
	for _change_index in relationship_changes:
		host._bump_world_revision(false)
	return complete_command(host, result, before_revision)


static func submit_response(
	host,
	conflict_id: String,
	actor_id: String,
	response_kind: String,
) -> Dictionary:
	if not host._running or host._conflict_controller == null:
		return host._command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var before_revision := runtime_revision(host)
	var result := host._conflict_controller.respond(
		conflict_id,
		actor_id,
		response_kind,
	) as Dictionary
	return complete_command(host, result, before_revision)


static func leave(
	host,
	conflict_id: String,
	actor_id: String,
	reason: String,
) -> Dictionary:
	if not host._running or host._conflict_controller == null:
		return host._command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var before_revision := runtime_revision(host)
	var result := host._conflict_controller.leave_conflict(
		conflict_id,
		actor_id,
		reason,
	) as Dictionary
	return complete_command(host, result, before_revision)


static func projection_changed(host, projection: Dictionary) -> void:
	host.conflict_projection_changed.emit(projection.duplicate(true))
	var wake_priorities: Dictionary = (
		host._conflict_agent_world_bridge.take_pending_knowledge_wakes()
	)
	for resident_id: String in host.resident_registry.order:
		var resident := host.resident_registry.records.get(resident_id, {}) as Dictionary
		if resident.is_empty() or not host.resident_is_present(resident):
			continue
		var nearby_ids: Array[String] = []
		for nearby_name: Variant in resident.get("nearby", []) as Array:
			var nearby_id: String = host.person_id_for_name(String(nearby_name))
			if not nearby_id.is_empty():
				nearby_ids.append(nearby_id)
		var snapshot: Dictionary = AGENT_WORLD_QUERY_RUNTIME.conflict_snapshot(
			host,
			resident_id,
			resident,
			nearby_ids,
		)
		var direct_participant := false
		for conflict_value: Variant in snapshot.get("conflicts", []) as Array:
			if (
				conflict_value is Dictionary
				and String((conflict_value as Dictionary).get("role", "witness"))
				!= "witness"
			):
				direct_participant = true
				break
		if (
			direct_participant
			or not (snapshot.get("conflict_tension_options", []) as Array).is_empty()
		):
			wake_priorities[resident_id] = true
	var wake_resident_ids: Array[String] = []
	wake_resident_ids.assign(wake_priorities.keys())
	wake_resident_ids.sort()
	for resident_id: String in wake_resident_ids:
		var urgent := bool(wake_priorities.get(resident_id, false))
		host._schedule_decision(resident_id, urgent, false, urgent)


static func event_created(host, event: Dictionary) -> void:
	append_log(host, event)
	queue_knowledge(host, event)
	host.conflict_event_created.emit(event.duplicate(true))


static func follow_up_required(host, follow_up: Dictionary) -> void:
	# Medical routing is a separate owner. This signal is the formal hand-off.
	host.conflict_follow_up_required.emit(follow_up.duplicate(true))


static func queue_knowledge(host, event: Dictionary) -> void:
	var actor_ids := event_actor_ids(event)
	if actor_ids.is_empty():
		return
	var actor_names := {}
	for actor_id: String in actor_ids:
		actor_names[actor_id] = host.person_name_for_id(actor_id)
	for resident_id: String in host.resident_registry.order:
		var resident := host.resident_registry.records.get(resident_id, {}) as Dictionary
		if resident.is_empty() or not host.resident_is_present(resident):
			continue
		var knowledge_kind := ""
		if actor_ids.has(resident_id):
			knowledge_kind = "participant"
		elif resident_witnesses(host, resident, actor_ids):
			knowledge_kind = "witness"
		else:
			continue
		var projected := KNOWLEDGE_PROJECTOR.project(
			event,
			knowledge_kind,
			actor_names,
		) as Dictionary
		if projected.get("ok") != true:
			continue
		var private_event := (
			projected.get("event", {}) as Dictionary
		).duplicate(true)
		private_event["event_id"] = host.world_log_domain.journal.next_world_event_id()
		private_event["time"] = host.get_time()
		host.WORLD_EVENT_DELIVERY_RUNTIME.enqueue(host, resident_id, private_event, false)
		host._conflict_agent_world_bridge.record_pending_knowledge_wake(
			resident_id,
			knowledge_kind == "participant",
		)


static func event_actor_ids(event: Dictionary) -> Array[String]:
	return RUNTIME_LOG_TEXT.conflict_event_actor_ids(event)


static func resident_witnesses(
	host,
	resident: Dictionary,
	actor_ids: Array[String],
) -> bool:
	for nearby_name: Variant in resident.get("nearby", []) as Array:
		if actor_ids.has(host.person_id_for_name(String(nearby_name))):
			return true
	return false


static func append_log(host, event: Dictionary) -> void:
	var source_actor_id := String(event.get("sourceActorId", "")).strip_edges()
	WORLD_LOG_COMMIT_RUNTIME.append_domain(host, DOMAIN_LOG_PROJECTION.conflict_event(
		event,
		host.person_name_for_id(source_actor_id),
	))


static func actor_is_available(host, actor_id: String) -> bool:
	var normalized := actor_id.strip_edges()
	if normalized.is_empty():
		return false
	if normalized == host.player_avatar_id():
		return host.actor_presentation_state.player_avatar_present
	var resident := host.resident_registry.records.get(normalized, {}) as Dictionary
	return not resident.is_empty() and host.resident_is_present(resident)


static func complete_command(
	host,
	result: Dictionary,
	before_revision: int,
) -> Dictionary:
	if result.get("ok") == true and runtime_revision(host) != before_revision:
		host._bump_world_revision(false)
		host._notify_world_revision()
	var decorated: Dictionary = host._decorate_command_result(result)
	decorated["conflict"] = public_projection(host)
	return decorated


static func runtime_revision(host) -> int:
	return int(public_projection(host).get("revision", 0))


static func empty_projection() -> Dictionary:
	return CONFLICT_JUDGMENTS.empty_conflict_projection()
