class_name TownConflictWorldController
extends RefCounted


signal conflict_projection_changed(projection: Dictionary)
signal conflict_event_created(event: Dictionary)
signal conflict_follow_up_required(follow_up: Dictionary)

const RESULT_SHAPES := preload(
	"res://world/contract/TownWorldResultShapes.gd"
)
const CONFLICT_RUNTIME := preload(
	"res://world/runtime/conflict/TownConflictRuntime.gd"
)
const DEFAULT_MAX_ATTACK_DISTANCE_PX := 144.0
const AVATAR_AREA_RANGE_BY_KIND := {
	"unarmed": 160.0,
	"avatar_susanoo_strike": 260.0,
	"avatar_rasengan": 210.0,
	"avatar_kamehameha": 360.0,
}
const REQUIRED_WORLD_METHODS := [
	"get_world_revision",
	"get_time",
	"get_resident_state",
	"get_all_resident_states",
	"get_player_avatar_state",
]
const SOURCE_KINDS := [
	"resident_decision",
	"resident_profile_decision",
	"avatar_intent",
]

var _world_ref: WeakRef
var _runtime: RefCounted
var _max_attack_distance_px := DEFAULT_MAX_ATTACK_DISTANCE_PX
var _configured := false
var _emitted_event_ids: Dictionary = {}
var _last_emitted_projection_revision := -1


func configure(world: Object, options: Dictionary = {}) -> Dictionary:
	if _configured:
		return _failure("CONFLICT_CONTROLLER_ALREADY_CONFIGURED")
	if world == null:
		return _failure("CONFLICT_CONTROLLER_WORLD_REQUIRED")
	for method_name_value: Variant in REQUIRED_WORLD_METHODS:
		var method_name := StringName(String(method_name_value))
		if not world.has_method(method_name):
			return _failure(
				"CONFLICT_CONTROLLER_WORLD_INTERFACE_MISSING",
				{"method": String(method_name)},
			)
	var allowed_options := [
		"maxAttackDistancePx",
		"lightRecoveryMinutes",
		"heavyTreatmentMinutes",
		"maxBrawlRounds",
	]
	for key_value: Variant in options:
		if not allowed_options.has(String(key_value)):
			return _failure("CONFLICT_CONTROLLER_OPTIONS_INVALID")
	_max_attack_distance_px = float(
		options.get(
			"maxAttackDistancePx",
			DEFAULT_MAX_ATTACK_DISTANCE_PX,
		)
	)
	if (
		not is_finite(_max_attack_distance_px)
		or _max_attack_distance_px <= 0.0
	):
		return _failure("CONFLICT_CONTROLLER_OPTIONS_INVALID")
	_runtime = CONFLICT_RUNTIME.new()
	var runtime_options := options.duplicate(true)
	runtime_options.erase("maxAttackDistancePx")
	var runtime_result := _runtime.configure(runtime_options,) as Dictionary
	if runtime_result.get("ok") != true:
		_runtime = null
		return runtime_result
	_world_ref = weakref(world)
	_configured = true
	_last_emitted_projection_revision = int(
		get_public_projection().get("revision", 0),
	)
	return {
		"ok": true,
		"errorCode": "",
		"maxAttackDistancePx": _max_attack_distance_px,
	}


func begin_attack(intent: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("CONFLICT_CONTROLLER_NOT_CONFIGURED")
	var allowed_fields := [
		"requestId",
		"attackerId",
		"targetId",
		"attackKind",
		"sourceKind",
		"sourceRef",
		"causeId",
		"causeSummary",
		"sourceConversationId",
	]
	if not _has_only_fields(intent, allowed_fields):
		return _failure("CONFLICT_ATTACK_INTENT_INVALID")
	var request_id := _string_field(intent, "requestId")
	var attacker_id := _string_field(intent, "attackerId")
	var target_id := _string_field(intent, "targetId")
	var attack_kind := _string_field(intent, "attackKind")
	var source_kind := _string_field(intent, "sourceKind")
	if (
		request_id.is_empty()
		or attacker_id.is_empty()
		or target_id.is_empty()
		or attacker_id == target_id
		or not SOURCE_KINDS.has(source_kind)
	):
		return _failure("CONFLICT_ATTACK_INTENT_INVALID")
	var attacker := _actor_snapshot(attacker_id)
	var target := _actor_snapshot(target_id)
	if attacker.is_empty():
		return _failure("CONFLICT_ATTACKER_NOT_FOUND")
	if target.is_empty():
		return _failure("CONFLICT_TARGET_NOT_FOUND")
	if (
		String(attacker.get("kind", "")) == "avatar"
		and source_kind != "avatar_intent"
	) or (
		String(attacker.get("kind", "")) == "resident"
		and source_kind not in [
			"resident_decision",
			"resident_profile_decision",
		]
	):
		return _failure("CONFLICT_ATTACK_SOURCE_MISMATCH")
	if not bool(attacker.get("present", false)):
		return _failure("CONFLICT_ATTACKER_NOT_PRESENT")
	if not bool(target.get("present", false)):
		return _failure("CONFLICT_TARGET_NOT_PRESENT")
	var attacker_space := String(attacker.get("spaceId", ""))
	var target_space := String(target.get("spaceId", ""))
	if attacker_space.is_empty() or attacker_space != target_space:
		return _failure("CONFLICT_ACTORS_NOT_IN_SAME_SPACE")
	var attacker_position := attacker.get("position", Vector2.INF) as Vector2
	var target_position := target.get("position", Vector2.INF) as Vector2
	if (
		not attacker_position.is_finite()
		or not target_position.is_finite()
	):
		return _failure("CONFLICT_ACTOR_POSITION_INVALID")
	var distance := attacker_position.distance_to(target_position)
	if distance > _max_attack_distance_px:
		return _failure(
			"CONFLICT_TARGET_OUT_OF_RANGE",
			{
				"distancePx": distance,
				"maxDistancePx": _max_attack_distance_px,
			},
		)
	var result := _runtime.begin_attack({
			"requestId": request_id,
			"attackerId": attacker_id,
			"targetId": target_id,
			"placeId": String(attacker.get("placeId", "")),
			"spaceId": attacker_space,
			"attackKind": attack_kind,
			"sourceKind": source_kind,
			"sourceRef": String(intent.get("sourceRef", "")),
			"causeId": String(intent.get("causeId", "")),
			"causeSummary": String(intent.get("causeSummary", "")),
			"sourceConversationId": String(
				intent.get("sourceConversationId", ""),
			),
			"occurredAtMinute": _absolute_minute(),
			"worldRevision": int(_world_call("get_world_revision")),
		},) as Dictionary
	return _publish_result(result)


func apply_tension_action(intent: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("CONFLICT_CONTROLLER_NOT_CONFIGURED")
	var allowed_fields := [
		"requestId",
		"actorId",
		"targetId",
		"optionId",
		"actionKind",
		"line",
		"sourceConversationId",
		"sourceEventIds",
		"sourceSummary",
	]
	if not _has_only_fields(intent, allowed_fields):
		return _failure("CONFLICT_TENSION_INTENT_INVALID")
	var actor_id := _string_field(intent, "actorId")
	var target_id := _string_field(intent, "targetId")
	var actor := _actor_snapshot(actor_id)
	var target := _actor_snapshot(target_id)
	if actor.is_empty() or target.is_empty():
		return _failure("CONFLICT_TENSION_ACTOR_NOT_FOUND")
	if (
		not bool(actor.get("present", false))
		or not bool(target.get("present", false))
		or String(actor.get("spaceId", ""))
		!= String(target.get("spaceId", ""))
	):
		return _failure("CONFLICT_TENSION_ACTORS_NOT_PRESENT")
	var actor_position := actor.get("position", Vector2.INF) as Vector2
	var target_position := target.get("position", Vector2.INF) as Vector2
	if (
		not actor_position.is_finite()
		or not target_position.is_finite()
		or actor_position.distance_to(target_position)
		> _max_attack_distance_px
	):
		return _failure("CONFLICT_TENSION_TARGET_OUT_OF_RANGE")
	var result := _runtime.apply_tension_action({
		"requestId": _string_field(intent, "requestId"),
		"actorId": actor_id,
		"targetId": target_id,
		"optionId": _string_field(intent, "optionId"),
		"actionKind": _string_field(intent, "actionKind"),
		"line": _string_field(intent, "line"),
		"sourceConversationId": String(
			intent.get("sourceConversationId", ""),
		),
		"sourceEventIds": (
			intent.get("sourceEventIds", []) as Array
		).duplicate(true),
		"sourceSummary": String(intent.get("sourceSummary", "")),
		"placeId": String(actor.get("placeId", "")),
		"spaceId": String(actor.get("spaceId", "")),
		"occurredAtMinute": _absolute_minute(),
		"worldRevision": int(_world_call("get_world_revision")),
	}) as Dictionary
	return _publish_result(result)


func tension_options_for_actor(
	actor_id: String,
	nearby_ids: Array,
) -> Array[Dictionary]:
	if not _configured:
		return []
	return (
		_runtime.tension_options_for_actor(actor_id,
			nearby_ids,
			_absolute_minute(),) as Array[Dictionary]
	).duplicate(true)


func begin_avatar_area_attack(intent: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("CONFLICT_CONTROLLER_NOT_CONFIGURED")
	var allowed_fields := [
		"requestId",
		"attackerId",
		"attackKind",
		"sourceKind",
		"sourceRef",
	]
	if not _has_only_fields(intent, allowed_fields):
		return _failure("CONFLICT_AVATAR_CAST_INTENT_INVALID")
	var request_id := _string_field(intent, "requestId")
	var attacker_id := _string_field(intent, "attackerId")
	var attack_kind := _string_field(intent, "attackKind")
	var source_kind := _string_field(intent, "sourceKind")
	if (
		request_id.is_empty()
		or attacker_id.is_empty()
		or source_kind != "avatar_intent"
		or not AVATAR_AREA_RANGE_BY_KIND.has(attack_kind)
	):
		return _failure("CONFLICT_AVATAR_CAST_INTENT_INVALID")
	var attacker := _actor_snapshot(attacker_id)
	if attacker.is_empty() or String(attacker.get("kind", "")) != "avatar":
		return _failure("CONFLICT_ATTACK_SOURCE_MISMATCH")
	if not bool(attacker.get("present", false)):
		return _failure("CONFLICT_ATTACKER_NOT_PRESENT")
	var attacker_position := attacker.get("position", Vector2.INF) as Vector2
	var attacker_space := String(attacker.get("spaceId", ""))
	if attacker_space.is_empty() or not attacker_position.is_finite():
		return _failure("CONFLICT_ACTOR_POSITION_INVALID")
	var range_px := float(AVATAR_AREA_RANGE_BY_KIND[attack_kind])
	var candidates: Array[Dictionary] = []
	for resident_value: Variant in _world_call("get_all_resident_states") as Array:
		if resident_value is not Dictionary:
			continue
		var resident := resident_value as Dictionary
		var resident_id := String(resident.get("residentId", "")).strip_edges()
		var lifecycle := resident.get("lifecycle", {}) as Dictionary
		var resident_position := resident.get("position", Vector2.INF) as Vector2
		if (
			resident_id.is_empty()
			or resident_id == attacker_id
			or not bool(resident.get("isPresent", false))
			or String(resident.get("spaceId", "")) != attacker_space
			or not resident_position.is_finite()
			or (
				bool(lifecycle.get("available", false))
				and not bool(lifecycle.get("isAlive", true))
			)
		):
			continue
		var distance := attacker_position.distance_to(resident_position)
		if distance <= range_px:
			candidates.append({
				"residentId": resident_id,
				"distancePx": distance,
			})
	candidates.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			var left_distance := float(left.get("distancePx", INF))
			var right_distance := float(right.get("distancePx", INF))
			if not is_equal_approx(left_distance, right_distance):
				return left_distance < right_distance
			return String(left.get("residentId", "")) < String(
				right.get("residentId", "")
			)
	)
	var hit_target_ids: Array[String] = []
	for candidate: Dictionary in candidates:
		hit_target_ids.append(String(candidate.get("residentId", "")))
	var result := _runtime.record_avatar_area_cast({
			"requestId": request_id,
			"attackerId": attacker_id,
			"attackKind": attack_kind,
			"sourceRef": String(intent.get("sourceRef", request_id)),
			"hitTargetIds": hit_target_ids,
			"placeId": String(attacker.get("placeId", "")),
			"spaceId": attacker_space,
			"occurredAtMinute": _absolute_minute(),
			"worldRevision": int(_world_call("get_world_revision")),
		},) as Dictionary
	result["rangePx"] = range_px
	result["hitCount"] = hit_target_ids.size()
	return _publish_result(result)


func respond(
	conflict_id: String,
	actor_id: String,
	response_kind: String,
) -> Dictionary:
	if not _configured:
		return _failure("CONFLICT_CONTROLLER_NOT_CONFIGURED")
	var actor := _actor_snapshot(actor_id)
	if actor.is_empty() or not bool(actor.get("present", false)):
		return _failure("CONFLICT_RESPONSE_ACTOR_NOT_PRESENT")
	var result := _runtime.respond(conflict_id,
		actor_id,
		response_kind,
		_absolute_minute(),
		int(_world_call("get_world_revision")),) as Dictionary
	return _publish_result(result)


func intervene(
	conflict_id: String,
	actor_id: String,
	intervention_kind: String,
) -> Dictionary:
	if not _configured:
		return _failure("CONFLICT_CONTROLLER_NOT_CONFIGURED")
	var conflict := _active_conflict(conflict_id)
	if conflict.is_empty():
		return _failure("CONFLICT_NOT_ACTIVE")
	var actor := _actor_snapshot(actor_id)
	if actor.is_empty() or not bool(actor.get("present", false)):
		return _failure("CONFLICT_INTERVENER_NOT_PRESENT")
	if String(actor.get("spaceId", "")) != String(
		conflict.get("spaceId", "")
	):
		return _failure("CONFLICT_INTERVENER_NOT_IN_SAME_SPACE")
	if not _actor_near_conflict(actor, conflict):
		return _failure("CONFLICT_INTERVENER_OUT_OF_RANGE")
	var result := _runtime.intervene(conflict_id,
		actor_id,
		intervention_kind,
		_absolute_minute(),
		int(_world_call("get_world_revision")),) as Dictionary
	return _publish_result(result)


func advance_brawl(conflict_id: String) -> Dictionary:
	if not _configured:
		return _failure("CONFLICT_CONTROLLER_NOT_CONFIGURED")
	var result := _runtime.advance_brawl(conflict_id,
		_absolute_minute(),
		int(_world_call("get_world_revision")),) as Dictionary
	return _publish_result(result)


func leave_conflict(
	conflict_id: String,
	actor_id: String,
	reason: String,
) -> Dictionary:
	if not _configured:
		return _failure("CONFLICT_CONTROLLER_NOT_CONFIGURED")
	var result := _runtime.leave_conflict(conflict_id,
		actor_id,
		reason,
		_absolute_minute(),
		int(_world_call("get_world_revision")),) as Dictionary
	return _publish_result(result)


func begin_treatment(actor_id: String, place_id: String) -> Dictionary:
	if not _configured:
		return _failure("CONFLICT_CONTROLLER_NOT_CONFIGURED")
	var actor := _actor_snapshot(actor_id)
	if actor.is_empty() or not bool(actor.get("present", false)):
		return _failure("CONFLICT_TREATMENT_ACTOR_NOT_PRESENT")
	var actor_place := String(actor.get("placeId", ""))
	if place_id.strip_edges().is_empty() or actor_place != place_id:
		return _failure("CONFLICT_TREATMENT_PLACE_MISMATCH")
	var result := _runtime.begin_treatment(actor_id,
		place_id,
		_absolute_minute(),) as Dictionary
	return _publish_result(result)


func advance() -> Dictionary:
	if not _configured:
		return _failure("CONFLICT_CONTROLLER_NOT_CONFIGURED")
	var result := _runtime.advance(_absolute_minute()) as Dictionary
	return _publish_result(result)


func get_public_projection() -> Dictionary:
	if not _configured:
		return {
			"revision": 0,
			"activeConflicts": [],
			"injuries": [],
			"tensions": [],
			"events": [],
		}
	return (
		_runtime.get_public_projection() as Dictionary
	).duplicate(true)


func get_agent_projection() -> Dictionary:
	if not _configured:
		return {
			"revision": 0,
			"activeConflicts": [],
			"injuries": [],
			"tensions": [],
			"events": [],
		}
	# Agent 决策只读取当前冲突、伤势和紧张关系。历史事件已经通过
	# World 的事件队列单独交付，不能在每次唤醒时再完整深拷贝。
	return (
		_runtime.get_public_projection(false) as Dictionary
	).duplicate(true)


func export_state() -> Dictionary:
	if not _configured:
		return {}
	return (_runtime.export_state() as Dictionary).duplicate(true)


func restore_state(state: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("CONFLICT_CONTROLLER_NOT_CONFIGURED")
	var result := _runtime.restore_state(state) as Dictionary
	if result.get("ok") == true:
		_emitted_event_ids.clear()
		for event_value: Variant in (
			get_public_projection().get("events", []) as Array
		):
			if event_value is Dictionary:
				var event_id := String(
					(event_value as Dictionary).get("eventId", "")
				)
				if not event_id.is_empty():
					_emitted_event_ids[event_id] = true
		_last_emitted_projection_revision = -1
		_emit_projection()
	return result


func get_follow_up(actor_id: String) -> Dictionary:
	if not _configured:
		return {}
	return (
		_runtime.get_follow_up(actor_id) as Dictionary
	).duplicate(true)


func _publish_result(result: Dictionary) -> Dictionary:
	if result.get("ok") != true:
		return result
	for event_value: Variant in result.get("events", []) as Array:
		if event_value is not Dictionary:
			continue
		var event := (event_value as Dictionary).duplicate(true)
		var event_id := String(event.get("eventId", ""))
		if event_id.is_empty() or _emitted_event_ids.has(event_id):
			continue
		_emitted_event_ids[event_id] = true
		conflict_event_created.emit(event)
		if String(event.get("type", "")) == "injury_applied":
			var follow_up := get_follow_up(
				String(event.get("subjectId", ""))
			)
			if bool(follow_up.get("required", false)):
				conflict_follow_up_required.emit(follow_up)
	_emit_projection()
	return result


func _emit_projection() -> void:
	var projection := get_public_projection()
	var revision := int(projection.get("revision", 0))
	if revision == _last_emitted_projection_revision:
		return
	_last_emitted_projection_revision = revision
	conflict_projection_changed.emit(projection)


func _active_conflict(conflict_id: String) -> Dictionary:
	for conflict_value: Variant in (
		get_agent_projection().get("activeConflicts", []) as Array
	):
		if conflict_value is not Dictionary:
			continue
		var conflict := conflict_value as Dictionary
		if String(conflict.get("conflictId", "")) == conflict_id:
			return conflict
	return {}


func _actor_snapshot(actor_id: String) -> Dictionary:
	var resident_value: Variant = _world_call("get_resident_state", actor_id)
	if resident_value is Dictionary and not (resident_value as Dictionary).is_empty():
		var resident := resident_value as Dictionary
		return {
			"actorId": String(resident.get("residentId", actor_id)),
			"present": bool(resident.get("isPresent", true)),
			"position": resident.get("position", Vector2.INF),
			"spaceId": String(resident.get("spaceId", "")),
			"placeId": String(resident.get("currentPlace", "")),
			"kind": "resident",
		}
	var avatar_value: Variant = _world_call("get_player_avatar_state")
	if avatar_value is Dictionary:
		var avatar := avatar_value as Dictionary
		if String(avatar.get("residentId", "")) == actor_id:
			return {
				"actorId": actor_id,
				"present": bool(avatar.get("present", true)),
				"position": avatar.get("position", Vector2.INF),
				"spaceId": String(avatar.get("spaceId", "")),
				"placeId": String(avatar.get("currentPlace", "")),
				"kind": "avatar",
			}
	return {}


func _actor_near_conflict(
	actor: Dictionary,
	conflict: Dictionary,
) -> bool:
	var actor_position := actor.get("position", Vector2.INF) as Vector2
	if not actor_position.is_finite():
		return false
	for participant_id_value: Variant in (
		conflict.get("participantIds", []) as Array
	):
		var participant := _actor_snapshot(String(participant_id_value))
		if participant.is_empty():
			continue
		var position := participant.get("position", Vector2.INF) as Vector2
		if (
			position.is_finite()
			and actor_position.distance_to(position)
			<= _max_attack_distance_px
		):
			return true
	return false


func _absolute_minute() -> int:
	var time_value: Variant = _world_call("get_time")
	if time_value is not Dictionary:
		return 0
	var time := time_value as Dictionary
	if time.has("absoluteMinute"):
		return maxi(0, int(time.get("absoluteMinute", 0)))
	var hour := int(time.get("hour", 0))
	var minute := int(time.get("minute", 0))
	var clock := String(time.get("clock", "")).strip_edges()
	if not clock.is_empty():
		var clock_parts := clock.split(":")
		if clock_parts.size() == 2:
			hour = int(clock_parts[0])
			minute = int(clock_parts[1])
	return maxi(
		0,
		(maxi(1, int(time.get("day", 1))) - 1) * 1440
		+ hour * 60
		+ minute,
	)


func _has_only_fields(value: Dictionary, allowed: Array) -> bool:
	for key_value: Variant in value:
		if not allowed.has(String(key_value)):
			return false
	return true


func _string_field(value: Dictionary, key: String) -> String:
	var field_value: Variant = value.get(key)
	return (
		String(field_value).strip_edges()
		if field_value is String
		else ""
	)


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	var result := RESULT_SHAPES.failure(error_code)
	for key_value: Variant in details:
		result[key_value] = details[key_value]
	return result


func _world_call(method: StringName, arg: Variant = null) -> Variant:
	var world: Object = _world_ref.get_ref() if _world_ref != null else null
	if world == null:
		return null
	if arg == null:
		return world.call(method)
	return world.call(method, arg)
