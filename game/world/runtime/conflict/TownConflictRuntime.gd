class_name TownConflictRuntime
extends RefCounted


const STATE_SCHEMA_VERSION := 1
const DEFAULT_LIGHT_RECOVERY_MINUTES := 180
const DEFAULT_HEAVY_TREATMENT_MINUTES := 120
const DEFAULT_MAX_BRAWL_ROUNDS := 4
const DEFAULT_TENSION_EXPIRY_MINUTES := 180
const DEFAULT_PAIR_COOLDOWN_MINUTES := 360
const MAX_EVENT_HISTORY := 256

const PHASE_UNILATERAL_HIT := "unilateral_hit"
const PHASE_BRAWL := "brawl"
const PHASE_ENDED := "ended"

const RESIDENT_ATTACK_KINDS: Array[String] = ["unarmed", "improvised"]
const AVATAR_ATTACK_KINDS: Array[String] = [
	"unarmed",
	"avatar_susanoo_strike",
	"avatar_rasengan",
	"avatar_kamehameha",
]
const ATTACK_KINDS: Array[String] = [
	"unarmed",
	"improvised",
	"avatar_susanoo_strike",
	"avatar_rasengan",
	"avatar_kamehameha",
]
const RESPONSE_KINDS: Array[String] = ["retaliate", "flee", "deescalate"]
const INTERVENTION_KINDS: Array[String] = ["join", "protect", "mediate"]
const INJURY_SEVERITIES: Array[String] = ["light", "heavy"]
const TENSION_STAGES: Array[String] = ["challenged", "threatened", "aftermath"]
const TENSION_ACTION_KINDS: Array[String] = [
	"challenge",
	"threaten",
	"apologize",
	"disengage",
]


var _configured := false
var _light_recovery_minutes := DEFAULT_LIGHT_RECOVERY_MINUTES
var _heavy_treatment_minutes := DEFAULT_HEAVY_TREATMENT_MINUTES
var _max_brawl_rounds := DEFAULT_MAX_BRAWL_ROUNDS
var _tension_expiry_minutes := DEFAULT_TENSION_EXPIRY_MINUTES
var _pair_cooldown_minutes := DEFAULT_PAIR_COOLDOWN_MINUTES
var _conflicts: Dictionary = {}
var _active_conflict_by_actor: Dictionary = {}
var _injuries: Dictionary = {}
var _events: Array[Dictionary] = []
var _request_results: Dictionary = {}
var _tensions: Dictionary = {}
var _tension_by_pair: Dictionary = {}
var _pair_cooldown_until: Dictionary = {}
var _conflict_sequence := 0
var _event_sequence := 0
var _tension_sequence := 0
var _revision := 0


func configure(options: Dictionary = {}) -> Dictionary:
	if _configured:
		return _failure("CONFLICT_RUNTIME_ALREADY_CONFIGURED")
	var allowed := [
		"lightRecoveryMinutes",
		"heavyTreatmentMinutes",
		"maxBrawlRounds",
		"tensionExpiryMinutes",
		"pairCooldownMinutes",
	]
	for key_value: Variant in options:
		if not allowed.has(String(key_value)):
			return _failure("CONFLICT_RUNTIME_OPTIONS_INVALID")
	_light_recovery_minutes = int(
		options.get(
			"lightRecoveryMinutes",
			DEFAULT_LIGHT_RECOVERY_MINUTES,
		)
	)
	_heavy_treatment_minutes = int(
		options.get(
			"heavyTreatmentMinutes",
			DEFAULT_HEAVY_TREATMENT_MINUTES,
		)
	)
	_max_brawl_rounds = int(
		options.get("maxBrawlRounds", DEFAULT_MAX_BRAWL_ROUNDS)
	)
	_tension_expiry_minutes = int(
		options.get("tensionExpiryMinutes", DEFAULT_TENSION_EXPIRY_MINUTES)
	)
	_pair_cooldown_minutes = int(
		options.get("pairCooldownMinutes", DEFAULT_PAIR_COOLDOWN_MINUTES)
	)
	if (
		_light_recovery_minutes <= 0
		or _heavy_treatment_minutes <= 0
		or _max_brawl_rounds < 2
		or _max_brawl_rounds > 12
		or _tension_expiry_minutes <= 0
		or _pair_cooldown_minutes <= 0
	):
		return _failure("CONFLICT_RUNTIME_OPTIONS_INVALID")
	_configured = true
	return {
		"ok": true,
		"errorCode": "",
		"lightRecoveryMinutes": _light_recovery_minutes,
		"heavyTreatmentMinutes": _heavy_treatment_minutes,
		"maxBrawlRounds": _max_brawl_rounds,
		"tensionExpiryMinutes": _tension_expiry_minutes,
		"pairCooldownMinutes": _pair_cooldown_minutes,
	}


func apply_tension_action(command: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("CONFLICT_RUNTIME_NOT_CONFIGURED")
	var request_id := String(command.get("requestId", "")).strip_edges()
	var actor_id := String(command.get("actorId", "")).strip_edges()
	var target_id := String(command.get("targetId", "")).strip_edges()
	var option_id := String(command.get("optionId", "")).strip_edges()
	var action_kind := String(command.get("actionKind", "")).strip_edges()
	var line := String(command.get("line", "")).strip_edges()
	var occurred_at := int(command.get("occurredAtMinute", -1))
	if (
		request_id.is_empty()
		or actor_id.is_empty()
		or target_id.is_empty()
		or actor_id == target_id
		or option_id.is_empty()
		or action_kind not in TENSION_ACTION_KINDS
		or line.is_empty()
		or line.length() > 120
		or occurred_at < 0
	):
		return _failure("CONFLICT_TENSION_ACTION_INVALID")
	if _request_results.has(request_id):
		var duplicate := (
			_request_results[request_id] as Dictionary
		).duplicate(true)
		duplicate["duplicate"] = true
		return duplicate
	var expected := _tension_option(option_id, actor_id, target_id, occurred_at)
	if expected.is_empty() or String(expected.get("kind", "")) != action_kind:
		return _store_request_failure(
			request_id,
			"CONFLICT_TENSION_OPTION_STALE",
		)
	var pair_key := _pair_key(actor_id, target_id)
	var tension_id := String(expected.get("tensionId", ""))
	var tension := _tensions.get(tension_id, {}) as Dictionary
	_revision += 1
	if action_kind == "challenge":
		_tension_sequence += 1
		tension_id = "tension-%06d" % _tension_sequence
		tension = {
			"tensionId": tension_id,
			"participantIds": [actor_id, target_id],
			"initiatorId": actor_id,
			"targetId": target_id,
			"stage": "challenged",
			"reasonSummary": line,
			"causeSummary": String(
				command.get("sourceSummary", ""),
			).strip_edges(),
			"sourceConversationId": String(
				command.get("sourceConversationId", ""),
			),
			"sourceEventIds": (
				command.get("sourceEventIds", []) as Array
			).duplicate(true),
			"startedAtMinute": occurred_at,
			"lastChangedAtMinute": occurred_at,
			"expiresAtMinute": occurred_at + _tension_expiry_minutes,
			"lastActorId": actor_id,
			"runtimeRevision": _revision,
		}
		_tensions[tension_id] = tension
		_tension_by_pair[pair_key] = tension_id
	elif action_kind == "threaten":
		tension["stage"] = "threatened"
		tension["reasonSummary"] = line
		tension["lastChangedAtMinute"] = occurred_at
		tension["expiresAtMinute"] = occurred_at + _tension_expiry_minutes
		tension["lastActorId"] = actor_id
		tension["runtimeRevision"] = _revision
		_tensions[tension_id] = tension
	else:
		_tensions.erase(tension_id)
		_tension_by_pair.erase(pair_key)
	var event_type := String({
		"challenge": "conflict_challenged",
		"threaten": "conflict_threatened",
		"apologize": "conflict_apologized",
		"disengage": "conflict_disengaged",
	}.get(action_kind, ""))
	var source_conversation_id := String(
		command.get("sourceConversationId", ""),
	).strip_edges()
	if source_conversation_id.is_empty():
		source_conversation_id = String(
			tension.get("sourceConversationId", ""),
		).strip_edges()
	var source_event_ids := (
		command.get("sourceEventIds", []) as Array
	).duplicate(true)
	if source_event_ids.is_empty():
		source_event_ids = (
			tension.get("sourceEventIds", []) as Array
		).duplicate(true)
	var event := _append_standalone_event(
		event_type,
		occurred_at,
		{
			"conflictId": tension_id,
			"rootConflictId": tension_id,
			"actorIds": [actor_id, target_id],
			"sourceActorId": actor_id,
			"subjectId": target_id,
			"placeId": String(command.get("placeId", "")),
			"spaceId": String(command.get("spaceId", "")),
			"reason": line,
			"causeSummary": String(
				tension.get("causeSummary", ""),
			).strip_edges(),
			"worldRevision": int(command.get("worldRevision", 0)),
			"causeId": tension_id,
			"sourceConversationId": source_conversation_id,
			"sourceEventIds": source_event_ids,
		},
	)
	var result := _success({
		"duplicate": false,
		"tension": _public_tension(tension),
		"events": [event],
	})
	_request_results[request_id] = result.duplicate(true)
	return result


func tension_options_for_actor(
	actor_id: String,
	nearby_ids: Array,
	now_minute: int,
) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	if not _configured or actor_id.strip_edges().is_empty() or now_minute < 0:
		return options
	_expire_tensions(now_minute)
	var sorted_nearby: Array[String] = _string_array(nearby_ids)
	sorted_nearby.sort()
	var has_unresolved_tension := false
	for tension_value: Variant in _tensions.values():
		if tension_value is not Dictionary:
			continue
		var active_tension := tension_value as Dictionary
		if actor_id in _string_array(active_tension.get("participantIds", [])):
			has_unresolved_tension = true
			break
	for target_id: String in sorted_nearby:
		if target_id == actor_id:
			continue
		var pair_key := _pair_key(actor_id, target_id)
		if now_minute < int(_pair_cooldown_until.get(pair_key, -1)):
			continue
		var tension_id := String(_tension_by_pair.get(pair_key, ""))
		var tension := _tensions.get(tension_id, {}) as Dictionary
		if tension.is_empty():
			# Finish, apologize for, or leave the existing dispute before starting
			# another one. Mixing unrelated challenge options into an active causal
			# thread makes both Agent decisions and the player's story unreadable.
			if has_unresolved_tension:
				continue
			options.append(_tension_option_payload(
				"challenge:%s" % target_id,
				"challenge",
				actor_id,
				target_id,
				"",
				"只有存在具体不满、矛盾或可核对的传闻时，才当面质问对方",
			))
			continue
		var stage := String(tension.get("stage", ""))
		if stage == "challenged":
			options.append(_tension_option_payload(
				"threaten:%s:%s" % [tension_id, target_id],
				"threaten",
				actor_id,
				target_id,
				tension_id,
				"把已经发生的争执升级为明确威胁；只有仍拒绝和解时使用",
			))
		for peaceful_kind: String in ["apologize", "disengage"]:
			options.append(_tension_option_payload(
				"%s:%s:%s" % [peaceful_kind, tension_id, target_id],
				peaceful_kind,
				actor_id,
				target_id,
				tension_id,
				(
					"为这场争执道歉并结束升级"
					if peaceful_kind == "apologize"
					else "主动离开这场争执，避免升级"
				),
			))
		if (
			stage == "threatened"
			and String(tension.get("lastActorId", "")) == actor_id
		):
			options.append(_tension_option_payload(
				"attack:%s:%s" % [tension_id, target_id],
				"attack",
				actor_id,
				target_id,
				tension_id,
				"威胁已经明确，仍决定动手；这会造成真实伤害和长期后果",
			))
	return options


func begin_attack(command: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("CONFLICT_RUNTIME_NOT_CONFIGURED")
	var validation := _validate_attack_command(command)
	if not validation.is_empty():
		return _failure(
			"CONFLICT_ATTACK_INVALID",
			{"errors": validation},
		)
	var request_id := String(command.get("requestId", ""))
	if _request_results.has(request_id):
		var duplicate := (
			_request_results[request_id] as Dictionary
		).duplicate(true)
		duplicate["duplicate"] = true
		return duplicate
	var attacker_id := String(command.get("attackerId", ""))
	var target_id := String(command.get("targetId", ""))
	var cause_id := String(command.get("causeId", "")).strip_edges()
	var cause_summary := String(command.get("causeSummary", "")).strip_edges()
	var cause_tension_id := ""
	var source_kind := String(command.get("sourceKind", ""))
	if source_kind == "resident_decision":
		var cause_option := _tension_option(
			cause_id,
			attacker_id,
			target_id,
			int(command.get("occurredAtMinute", 0)),
		)
		if String(cause_option.get("kind", "")) != "attack":
			return _store_request_failure(
				request_id,
				"CONFLICT_ATTACK_CAUSE_REQUIRED",
			)
		cause_tension_id = String(cause_option.get("tensionId", ""))
		var cause_tension := _tensions.get(cause_tension_id, {}) as Dictionary
		# The causal summary belongs to the confirmed tension, not to the new
		# attack wording supplied by the Agent. This keeps the story root stable
		# across threat, attack, injury, treatment and later recollection.
		cause_summary = String(
			cause_tension.get(
				"causeSummary",
				cause_tension.get("reasonSummary", cause_summary),
			),
		).strip_edges()
		if String(command.get("sourceConversationId", "")).is_empty():
			command["sourceConversationId"] = String(
				cause_tension.get("sourceConversationId", ""),
			)
	elif source_kind == "resident_profile_decision":
		if (
			not cause_id.begins_with("profile-attack:")
			or cause_summary.is_empty()
		):
			return _store_request_failure(
				request_id,
				"CONFLICT_ATTACK_CAUSE_REQUIRED",
			)
	if _active_conflict_by_actor.has(attacker_id):
		return _store_request_failure(
			request_id,
			"CONFLICT_ATTACKER_ALREADY_ACTIVE",
		)
	if _active_conflict_by_actor.has(target_id):
		return _store_request_failure(
			request_id,
			"CONFLICT_TARGET_ALREADY_ACTIVE",
		)
	if get_injury_severity(attacker_id) == "heavy":
		return _store_request_failure(
			request_id,
			"CONFLICT_ATTACKER_HEAVY_INJURY",
		)
	if get_injury_severity(target_id) == "heavy":
		return _store_request_failure(
			request_id,
			"CONFLICT_TARGET_HEAVY_INJURY",
		)
	_conflict_sequence += 1
	_revision += 1
	var conflict_id := "conflict-%06d" % _conflict_sequence
	var occurred_at := int(command.get("occurredAtMinute", 0))
	var world_revision := int(command.get("worldRevision", 0))
	var participant_roles := {}
	participant_roles[attacker_id] = "attacker"
	participant_roles[target_id] = "target"
	var conflict := {
		"conflictId": conflict_id,
		"rootConflictId": (
			cause_tension_id if not cause_tension_id.is_empty() else conflict_id
		),
		"phase": PHASE_UNILATERAL_HIT,
		"attackerId": attacker_id,
		"targetId": target_id,
		"participantIds": [attacker_id, target_id],
		"participantRoles": participant_roles,
		"placeId": String(command.get("placeId", "")),
		"spaceId": String(command.get("spaceId", "")),
		"attackKind": String(command.get("attackKind", "")),
		"sourceKind": String(command.get("sourceKind", "")),
		"sourceRef": String(command.get("sourceRef", "")),
		"causeId": cause_id,
		"causeSummary": cause_summary,
		"sourceConversationId": String(
			command.get("sourceConversationId", ""),
		),
		"sourceEventIds": (
			(_tensions.get(cause_tension_id, {}) as Dictionary).get(
				"sourceEventIds",
				[],
			) as Array
		).duplicate(true),
		"startedAtMinute": occurred_at,
		"lastChangedAtMinute": occurred_at,
		"endedAtMinute": -1,
		"endReason": "",
		"round": 0,
		"maxRounds": _max_brawl_rounds,
		"worldRevision": world_revision,
		"runtimeRevision": _revision,
	}
	_conflicts[conflict_id] = conflict
	if not cause_id.is_empty():
		_consume_attack_cause(
			cause_id,
			attacker_id,
			target_id,
			occurred_at,
			conflict_id,
		)
	_active_conflict_by_actor[attacker_id] = conflict_id
	_active_conflict_by_actor[target_id] = conflict_id
	var events: Array[Dictionary] = []
	events.append(
		_append_event(
			"conflict_formed",
			conflict,
			occurred_at,
			{
				"actorIds": [attacker_id, target_id],
				"sourceActorId": attacker_id,
				"subjectId": target_id,
				"reason": "attack_confirmed",
			},
		)
	)
	events.append(
		_append_event(
			"unilateral_hit_confirmed",
			conflict,
			occurred_at,
			{
				"actorIds": [attacker_id, target_id],
				"sourceActorId": attacker_id,
				"subjectId": target_id,
				"reason": String(command.get("attackKind", "")),
			},
		)
	)
	var injury_result := _apply_injury(
		target_id,
		"light",
		conflict,
		attacker_id,
		occurred_at,
	)
	for event_value: Variant in injury_result.get("events", []) as Array:
		events.append((event_value as Dictionary).duplicate(true))
	conflict = _conflicts[conflict_id] as Dictionary
	var awaiting_response := true
	if String(command.get("sourceKind", "")) == "avatar_intent":
		# Avatar attacks are unilateral player actions. Residents do not retaliate
		# against the avatar, so no Agent response may keep the player locked in
		# an active conflict after the confirmed hit.
		var finished := _finish_conflict(
			conflict,
			"avatar_attack_completed",
			occurred_at,
			world_revision,
		)
		if finished.get("ok") != true:
			return finished
		for event_value: Variant in finished.get("events", []) as Array:
			events.append((event_value as Dictionary).duplicate(true))
		conflict = finished.get("conflict", {}) as Dictionary
		awaiting_response = false
	var result := _success({
		"duplicate": false,
		"conflict": _public_conflict(conflict),
		"injury": injury_result.get("injury", {}),
		"events": events,
		"awaitingResponse": awaiting_response,
	})
	_request_results[request_id] = result.duplicate(true)
	return result


func record_avatar_area_cast(command: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("CONFLICT_RUNTIME_NOT_CONFIGURED")
	var request_id := String(command.get("requestId", "")).strip_edges()
	var attacker_id := String(command.get("attackerId", "")).strip_edges()
	var attack_kind := String(command.get("attackKind", "")).strip_edges()
	var source_kind := String(
		command.get("sourceKind", "avatar_intent")
	).strip_edges()
	var occurred_at := int(command.get("occurredAtMinute", -1))
	var world_revision := int(command.get("worldRevision", -1))
	if (
		request_id.is_empty()
		or attacker_id.is_empty()
		or not AVATAR_ATTACK_KINDS.has(attack_kind)
		or occurred_at < 0
		or world_revision < 0
		or source_kind != "avatar_intent"
		or command.get("hitTargetIds", []) is not Array
	):
		return _failure("CONFLICT_AVATAR_CAST_INVALID")
	if _request_results.has(request_id):
		var duplicate := (
			_request_results[request_id] as Dictionary
		).duplicate(true)
		duplicate["duplicate"] = true
		return duplicate
	var hit_target_ids := _string_array(
		command.get("hitTargetIds", []) as Array
	)
	_revision += 1
	var cast_id := "avatar-cast:%s" % request_id
	var actor_ids: Array[String] = [attacker_id]
	for target_id: String in hit_target_ids:
		if target_id != attacker_id:
			actor_ids.append(target_id)
	var cast_context := {
		"conflictId": cast_id,
		"placeId": String(command.get("placeId", "")),
		"spaceId": String(command.get("spaceId", "")),
		"sourceKind": source_kind,
		"sourceRef": String(command.get("sourceRef", request_id)),
		"worldRevision": world_revision,
	}
	var events: Array[Dictionary] = []
	events.append(_append_standalone_event(
		"avatar_area_attack_cast",
		occurred_at,
		{
			"conflictId": cast_id,
			"actorIds": actor_ids,
			"sourceActorId": attacker_id,
			"attackKind": attack_kind,
			"hitTargetIds": hit_target_ids.duplicate(),
			"sourceKind": source_kind,
			"sourceRef": String(command.get("sourceRef", request_id)),
			"subjectId": (
				hit_target_ids[0]
				if not hit_target_ids.is_empty()
				else attacker_id
			),
			"placeId": String(command.get("placeId", "")),
			"spaceId": String(command.get("spaceId", "")),
			"reason": attack_kind,
			"worldRevision": world_revision,
		},
	))
	var injuries: Array[Dictionary] = []
	for target_id: String in hit_target_ids:
		# The cast still visually hits a resident who is already heavily injured,
		# but authoritative injury cannot escalate beyond heavy or restart the
		# same clinic follow-up on every repeated skill.
		if get_injury_severity(target_id) == "heavy":
			continue
		var injury_result := _apply_injury(
			target_id,
			"light",
			cast_context,
			attacker_id,
			occurred_at,
		)
		injuries.append(
			(injury_result.get("injury", {}) as Dictionary).duplicate(true)
		)
		for event_value: Variant in injury_result.get("events", []) as Array:
			events.append((event_value as Dictionary).duplicate(true))
	var result := _success({
		"duplicate": false,
		"castId": cast_id,
		"attackKind": attack_kind,
		"sourceKind": source_kind,
		"hitTargetIds": hit_target_ids,
		"hitCount": hit_target_ids.size(),
		"injuries": injuries,
		"events": events,
	})
	_request_results[request_id] = result.duplicate(true)
	return result


func respond(
	conflict_id: String,
	actor_id: String,
	response_kind: String,
	occurred_at_minute: int,
	world_revision: int,
) -> Dictionary:
	var conflict := _active_conflict(conflict_id)
	if conflict.is_empty():
		return _failure("CONFLICT_NOT_ACTIVE")
	if String(conflict.get("phase", "")) != PHASE_UNILATERAL_HIT:
		return _failure("CONFLICT_RESPONSE_PHASE_INVALID")
	if actor_id != String(conflict.get("targetId", "")):
		return _failure("CONFLICT_RESPONSE_ACTOR_INVALID")
	if not RESPONSE_KINDS.has(response_kind):
		return _failure("CONFLICT_RESPONSE_KIND_INVALID")
	if occurred_at_minute < int(conflict.get("lastChangedAtMinute", 0)):
		return _failure("CONFLICT_TIME_STALE")
	if response_kind == "retaliate":
		_revision += 1
		conflict["phase"] = PHASE_BRAWL
		conflict["round"] = 1
		conflict["lastChangedAtMinute"] = occurred_at_minute
		conflict["worldRevision"] = world_revision
		conflict["runtimeRevision"] = _revision
		_conflicts[conflict_id] = conflict
		var event := _append_event(
			"brawl_started",
			conflict,
			occurred_at_minute,
			{
				"actorIds": _string_array(
					conflict.get("participantIds", []) as Array
				),
				"sourceActorId": actor_id,
				"subjectId": String(conflict.get("attackerId", "")),
				"reason": "retaliated",
			},
		)
		return _success({
			"conflict": _public_conflict(conflict),
			"events": [event],
		})
	var end_reason := (
		"target_fled" if response_kind == "flee" else "deescalated"
	)
	return _finish_conflict(
		conflict,
		end_reason,
		occurred_at_minute,
		world_revision,
	)


func intervene(
	conflict_id: String,
	actor_id: String,
	intervention_kind: String,
	occurred_at_minute: int,
	world_revision: int,
) -> Dictionary:
	var conflict := _active_conflict(conflict_id)
	if conflict.is_empty():
		return _failure("CONFLICT_NOT_ACTIVE")
	var normalized_id := actor_id.strip_edges()
	if normalized_id.is_empty() or not INTERVENTION_KINDS.has(
		intervention_kind
	):
		return _failure("CONFLICT_INTERVENTION_INVALID")
	if _active_conflict_by_actor.has(normalized_id):
		return _failure("CONFLICT_INTERVENER_ALREADY_ACTIVE")
	if get_injury_severity(normalized_id) == "heavy":
		return _failure("CONFLICT_INTERVENER_HEAVY_INJURY")
	if intervention_kind == "mediate":
		var mediated_event := _append_event(
			"conflict_intervened",
			conflict,
			occurred_at_minute,
			{
				"actorIds": [normalized_id],
				"sourceActorId": normalized_id,
				"subjectId": "",
				"reason": "mediate",
			},
		)
		var finished := _finish_conflict(
			conflict,
			"mediated",
			occurred_at_minute,
			world_revision,
		)
		var combined_events: Array[Dictionary] = [mediated_event]
		for value: Variant in finished.get("events", []) as Array:
			combined_events.append((value as Dictionary).duplicate(true))
		finished["events"] = combined_events
		return finished
	var participants := _string_array(
		conflict.get("participantIds", []) as Array
	)
	participants.append(normalized_id)
	var roles := (
		conflict.get("participantRoles", {}) as Dictionary
	).duplicate(true)
	roles[normalized_id] = intervention_kind
	_revision += 1
	conflict["participantIds"] = participants
	conflict["participantRoles"] = roles
	conflict["lastChangedAtMinute"] = occurred_at_minute
	conflict["worldRevision"] = world_revision
	conflict["runtimeRevision"] = _revision
	_conflicts[conflict_id] = conflict
	_active_conflict_by_actor[normalized_id] = conflict_id
	var event := _append_event(
		"conflict_joined",
		conflict,
		occurred_at_minute,
		{
			"actorIds": [normalized_id],
			"sourceActorId": normalized_id,
			"subjectId": String(conflict.get("targetId", "")),
			"reason": intervention_kind,
		},
	)
	return _success({
		"conflict": _public_conflict(conflict),
		"events": [event],
	})


func advance_brawl(
	conflict_id: String,
	occurred_at_minute: int,
	world_revision: int,
) -> Dictionary:
	var conflict := _active_conflict(conflict_id)
	if conflict.is_empty():
		return _failure("CONFLICT_NOT_ACTIVE")
	if String(conflict.get("phase", "")) != PHASE_BRAWL:
		return _failure("CONFLICT_BRAWL_PHASE_INVALID")
	if occurred_at_minute < int(conflict.get("lastChangedAtMinute", 0)):
		return _failure("CONFLICT_TIME_STALE")
	var participants := _string_array(
		conflict.get("participantIds", []) as Array
	)
	if participants.size() < 2:
		return _finish_conflict(
			conflict,
			"insufficient_participants",
			occurred_at_minute,
			world_revision,
		)
	var next_round := int(conflict.get("round", 0)) + 1
	_revision += 1
	conflict["round"] = next_round
	conflict["lastChangedAtMinute"] = occurred_at_minute
	conflict["worldRevision"] = world_revision
	conflict["runtimeRevision"] = _revision
	_conflicts[conflict_id] = conflict
	var target_index := posmod(next_round - 2, participants.size())
	var source_index := posmod(target_index + 1, participants.size())
	var subject_id := participants[target_index]
	var source_id := participants[source_index]
	var current_severity := get_injury_severity(subject_id)
	var next_severity := "light" if current_severity.is_empty() else "heavy"
	var injury_result := _apply_injury(
		subject_id,
		next_severity,
		conflict,
		source_id,
		occurred_at_minute,
	)
	var events: Array[Dictionary] = []
	for value: Variant in injury_result.get("events", []) as Array:
		events.append((value as Dictionary).duplicate(true))
	var should_finish := (
		next_severity == "heavy"
		or next_round >= int(conflict.get("maxRounds", 0))
	)
	if should_finish:
		var reason := (
			"heavy_injury" if next_severity == "heavy" else "round_limit"
		)
		var finished := _finish_conflict(
			_conflicts[conflict_id] as Dictionary,
			reason,
			occurred_at_minute,
			world_revision,
		)
		for value: Variant in finished.get("events", []) as Array:
			events.append((value as Dictionary).duplicate(true))
		finished["events"] = events
		finished["injury"] = injury_result.get("injury", {})
		return finished
	return _success({
		"conflict": _public_conflict(
			_conflicts[conflict_id] as Dictionary
		),
		"injury": injury_result.get("injury", {}),
		"events": events,
	})


func leave_conflict(
	conflict_id: String,
	actor_id: String,
	reason: String,
	occurred_at_minute: int,
	world_revision: int,
) -> Dictionary:
	var conflict := _active_conflict(conflict_id)
	if conflict.is_empty():
		return _failure("CONFLICT_NOT_ACTIVE")
	var participants := _string_array(
		conflict.get("participantIds", []) as Array
	)
	if not participants.has(actor_id):
		return _failure("CONFLICT_PARTICIPANT_UNKNOWN")
	if reason.strip_edges().is_empty():
		return _failure("CONFLICT_LEAVE_REASON_INVALID")
	participants.erase(actor_id)
	var roles := (
		conflict.get("participantRoles", {}) as Dictionary
	).duplicate(true)
	roles.erase(actor_id)
	_active_conflict_by_actor.erase(actor_id)
	_revision += 1
	conflict["participantIds"] = participants
	conflict["participantRoles"] = roles
	conflict["lastChangedAtMinute"] = occurred_at_minute
	conflict["worldRevision"] = world_revision
	conflict["runtimeRevision"] = _revision
	_conflicts[conflict_id] = conflict
	var event := _append_event(
		"conflict_left",
		conflict,
		occurred_at_minute,
		{
			"actorIds": [actor_id],
			"sourceActorId": actor_id,
			"subjectId": "",
			"reason": reason,
		},
	)
	if participants.size() < 2:
		var finished := _finish_conflict(
			conflict,
			"insufficient_participants",
			occurred_at_minute,
			world_revision,
		)
		var events: Array[Dictionary] = [event]
		for value: Variant in finished.get("events", []) as Array:
			events.append((value as Dictionary).duplicate(true))
		finished["events"] = events
		return finished
	return _success({
		"conflict": _public_conflict(conflict),
		"events": [event],
	})


func begin_treatment(
	actor_id: String,
	place_id: String,
	occurred_at_minute: int,
) -> Dictionary:
	var injury := _injuries.get(actor_id, {}) as Dictionary
	if injury.is_empty():
		return _failure("CONFLICT_INJURY_NOT_ACTIVE")
	if String(injury.get("severity", "")) != "heavy":
		return _failure("CONFLICT_TREATMENT_NOT_REQUIRED")
	if place_id.strip_edges().is_empty():
		return _failure("CONFLICT_TREATMENT_PLACE_INVALID")
	var status := String(injury.get("treatmentStatus", ""))
	if status == "in_progress":
		return _success({
			"duplicate": true,
			"injury": _public_injury(injury),
			"events": [],
		})
	_revision += 1
	injury["treatmentStatus"] = "in_progress"
	injury["treatmentPlaceId"] = place_id
	injury["treatmentStartedAtMinute"] = occurred_at_minute
	injury["treatmentDueAtMinute"] = (
		occurred_at_minute + _heavy_treatment_minutes
	)
	injury["runtimeRevision"] = _revision
	_injuries[actor_id] = injury
	var event := _append_standalone_event(
		"treatment_started",
		occurred_at_minute,
		{
			"conflictId": String(injury.get("sourceConflictId", "")),
			"rootConflictId": String(
				injury.get("rootConflictId", injury.get("sourceConflictId", "")),
			),
			"actorIds": [actor_id],
			"sourceActorId": actor_id,
			"subjectId": actor_id,
			"placeId": place_id,
			"spaceId": "",
			"severity": "heavy",
			"reason": "clinic_treatment",
			"worldRevision": int(injury.get("worldRevision", 0)),
		},
	)
	return _success({
		"duplicate": false,
		"injury": _public_injury(injury),
		"events": [event],
	})


func advance(now_minute: int) -> Dictionary:
	if not _configured or now_minute < 0:
		return _failure("CONFLICT_ADVANCE_INVALID")
	var events: Array[Dictionary] = []
	_expire_tensions(now_minute)
	var actor_ids: Array[String] = []
	for actor_id_value: Variant in _injuries:
		actor_ids.append(String(actor_id_value))
	actor_ids.sort()
	for actor_id: String in actor_ids:
		var injury := _injuries.get(actor_id, {}) as Dictionary
		var severity := String(injury.get("severity", ""))
		if severity == "heavy":
			if (
				String(injury.get("treatmentStatus", "")) == "in_progress"
				and now_minute >= int(
					injury.get("treatmentDueAtMinute", -1)
				)
			):
				_revision += 1
				injury["severity"] = "light"
				injury["treatmentStatus"] = "completed"
				injury["recoveryDueAtMinute"] = (
					now_minute + _light_recovery_minutes
				)
				injury["lastChangedAtMinute"] = now_minute
				injury["runtimeRevision"] = _revision
				_injuries[actor_id] = injury
				events.append(
					_append_injury_event(
						"treatment_completed",
						injury,
						now_minute,
						"heavy_to_light",
					)
				)
			continue
		if (
			severity == "light"
			and now_minute >= int(injury.get("recoveryDueAtMinute", -1))
		):
			_revision += 1
			_injuries.erase(actor_id)
			events.append(
				_append_injury_event(
					"injury_recovered",
					injury,
					now_minute,
					"recovered",
				)
			)
	return _success({
		"events": events,
		"revision": _revision,
	})


func get_actor_conflict_id(actor_id: String) -> String:
	return String(_active_conflict_by_actor.get(actor_id, ""))


func get_injury_severity(actor_id: String) -> String:
	return String(
		(_injuries.get(actor_id, {}) as Dictionary).get("severity", "")
	)


func get_follow_up(actor_id: String) -> Dictionary:
	var injury := _injuries.get(actor_id, {}) as Dictionary
	if injury.is_empty():
		return {
			"actorId": actor_id,
			"required": false,
			"kind": "none",
			"priority": "normal",
			"reason": "",
		}
	var severity := String(injury.get("severity", ""))
	return {
		"actorId": actor_id,
		"required": severity == "heavy",
		"kind": "go_to_clinic" if severity == "heavy" else "rest_or_continue",
		"priority": "urgent" if severity == "heavy" else "normal",
		"reason": "heavy_injury" if severity == "heavy" else "light_injury",
		"conflictId": String(injury.get("sourceConflictId", "")),
		"rootConflictId": String(
			injury.get("rootConflictId", injury.get("sourceConflictId", "")),
		),
		"severity": severity,
		"treatmentStatus": String(injury.get("treatmentStatus", "")),
		"sourceActorId": String(injury.get("sourceActorId", "")),
		"sourceKind": String(injury.get("sourceKind", "")),
		"sourceRef": String(injury.get("sourceRef", "")),
		"causeSummary": String(injury.get("causeSummary", "")),
		"treatmentPlaceId": String(injury.get("treatmentPlaceId", "")),
		"treatmentStartedAtMinute": int(
			injury.get("treatmentStartedAtMinute", -1)
		),
		"treatmentDueAtMinute": int(
			injury.get("treatmentDueAtMinute", -1)
		),
		"recoveryDueAtMinute": int(injury.get("recoveryDueAtMinute", -1)),
	}


func get_public_projection(include_event_history := true) -> Dictionary:
	var active_conflicts: Array[Dictionary] = []
	var conflict_ids: Array[String] = []
	for conflict_id_value: Variant in _conflicts:
		conflict_ids.append(String(conflict_id_value))
	conflict_ids.sort()
	for conflict_id: String in conflict_ids:
		var conflict := _conflicts[conflict_id] as Dictionary
		if String(conflict.get("phase", "")) != PHASE_ENDED:
			active_conflicts.append(_public_conflict(conflict))
	var injuries: Array[Dictionary] = []
	var actor_ids: Array[String] = []
	for actor_id_value: Variant in _injuries:
		actor_ids.append(String(actor_id_value))
	actor_ids.sort()
	for actor_id: String in actor_ids:
		injuries.append(
			_public_injury(_injuries[actor_id] as Dictionary)
		)
	return {
		"revision": _revision,
		"activeConflicts": active_conflicts,
		"injuries": injuries,
		"tensions": _public_tensions(),
		"events": (
			_events.duplicate(true)
			if include_event_history
			else []
		),
	}


func export_state() -> Dictionary:
	return {
		"schemaVersion": STATE_SCHEMA_VERSION,
		"settings": {
			"lightRecoveryMinutes": _light_recovery_minutes,
			"heavyTreatmentMinutes": _heavy_treatment_minutes,
			"maxBrawlRounds": _max_brawl_rounds,
			"tensionExpiryMinutes": _tension_expiry_minutes,
			"pairCooldownMinutes": _pair_cooldown_minutes,
		},
		"conflicts": _conflicts.duplicate(true),
		"activeConflictByActor": _active_conflict_by_actor.duplicate(true),
		"injuries": _injuries.duplicate(true),
		"events": _events.duplicate(true),
		"requestResults": _request_results.duplicate(true),
		"tensions": _tensions.duplicate(true),
		"tensionByPair": _tension_by_pair.duplicate(true),
		"pairCooldownUntil": _pair_cooldown_until.duplicate(true),
		"conflictSequence": _conflict_sequence,
		"eventSequence": _event_sequence,
		"tensionSequence": _tension_sequence,
		"revision": _revision,
	}


func restore_state(state: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("CONFLICT_RUNTIME_NOT_CONFIGURED")
	if (
		not _conflicts.is_empty()
		or not _injuries.is_empty()
		or not _events.is_empty()
		or not _tensions.is_empty()
	):
		return _failure("CONFLICT_RESTORE_REQUIRES_EMPTY_RUNTIME")
	var validation := _validate_state(state)
	if not validation.is_empty():
		return _failure(
			"CONFLICT_RESTORE_INVALID",
			{"errors": validation},
		)
	var settings := state.get("settings", {}) as Dictionary
	if (
		int(settings.get("lightRecoveryMinutes", 0))
		!= _light_recovery_minutes
		or int(settings.get("heavyTreatmentMinutes", 0))
		!= _heavy_treatment_minutes
		or int(settings.get("maxBrawlRounds", 0))
		!= _max_brawl_rounds
		or int(settings.get(
			"tensionExpiryMinutes",
			_tension_expiry_minutes,
		)) != _tension_expiry_minutes
		or int(settings.get(
			"pairCooldownMinutes",
			_pair_cooldown_minutes,
		)) != _pair_cooldown_minutes
	):
		return _failure("CONFLICT_RESTORE_SETTINGS_MISMATCH")
	_conflicts = (state.get("conflicts", {}) as Dictionary).duplicate(true)
	_active_conflict_by_actor = (
		state.get("activeConflictByActor", {}) as Dictionary
	).duplicate(true)
	_injuries = (state.get("injuries", {}) as Dictionary).duplicate(true)
	_events = []
	for value: Variant in state.get("events", []) as Array:
		_events.append((value as Dictionary).duplicate(true))
	_request_results = (
		state.get("requestResults", {}) as Dictionary
	).duplicate(true)
	_tensions = (
		state.get("tensions", {}) as Dictionary
	).duplicate(true)
	_tension_by_pair = (
		state.get("tensionByPair", {}) as Dictionary
	).duplicate(true)
	_pair_cooldown_until = (
		state.get("pairCooldownUntil", {}) as Dictionary
	).duplicate(true)
	_conflict_sequence = int(state.get("conflictSequence", 0))
	_event_sequence = int(state.get("eventSequence", 0))
	_tension_sequence = int(state.get("tensionSequence", 0))
	_revision = int(state.get("revision", 0))
	return _success({
		"restored": true,
		"revision": _revision,
		"activeConflictCount": _active_conflict_by_actor.size(),
		"injuryCount": _injuries.size(),
	})


func _finish_conflict(
	conflict: Dictionary,
	reason: String,
	occurred_at_minute: int,
	world_revision: int,
) -> Dictionary:
	var conflict_id := String(conflict.get("conflictId", ""))
	if conflict_id.is_empty():
		return _failure("CONFLICT_ID_INVALID")
	_revision += 1
	conflict["phase"] = PHASE_ENDED
	conflict["endReason"] = reason
	conflict["endedAtMinute"] = occurred_at_minute
	conflict["lastChangedAtMinute"] = occurred_at_minute
	conflict["worldRevision"] = world_revision
	conflict["runtimeRevision"] = _revision
	_conflicts[conflict_id] = conflict
	for actor_id: String in _string_array(
		conflict.get("participantIds", []) as Array
	):
		if String(_active_conflict_by_actor.get(actor_id, "")) == conflict_id:
			_active_conflict_by_actor.erase(actor_id)
	var event := _append_event(
		"conflict_ended",
		conflict,
		occurred_at_minute,
		{
			"actorIds": _string_array(
				conflict.get("participantIds", []) as Array
			),
			"sourceActorId": "",
			"subjectId": "",
			"reason": reason,
		},
	)
	return _success({
		"conflict": _public_conflict(conflict),
		"events": [event],
	})


func _apply_injury(
	actor_id: String,
	severity: String,
	conflict: Dictionary,
	source_actor_id: String,
	occurred_at_minute: int,
) -> Dictionary:
	var current := _injuries.get(actor_id, {}) as Dictionary
	var current_severity := String(current.get("severity", ""))
	var resolved_severity := severity
	if current_severity == "heavy":
		resolved_severity = "heavy"
	elif current_severity == "light" and severity == "light":
		resolved_severity = "heavy"
	_revision += 1
	var injury := {
		"actorId": actor_id,
		"severity": resolved_severity,
		"sourceConflictId": String(conflict.get("conflictId", "")),
		"rootConflictId": String(
			conflict.get("rootConflictId", conflict.get("conflictId", "")),
		),
		"sourceActorId": source_actor_id,
		"sourceKind": String(conflict.get("sourceKind", "")),
		"sourceRef": String(conflict.get("sourceRef", "")),
		"causeSummary": String(conflict.get("causeSummary", "")),
		"sourceConversationId": String(
			conflict.get("sourceConversationId", ""),
		),
		"sourceEventIds": (
			conflict.get("sourceEventIds", []) as Array
		).duplicate(true),
		"placeId": String(conflict.get("placeId", "")),
		"spaceId": String(conflict.get("spaceId", "")),
		"appliedAtMinute": (
			int(current.get("appliedAtMinute", occurred_at_minute))
			if not current.is_empty()
			else occurred_at_minute
		),
		"lastChangedAtMinute": occurred_at_minute,
		"recoveryDueAtMinute": (
			occurred_at_minute + _light_recovery_minutes
			if resolved_severity == "light"
			else -1
		),
		"treatmentStatus": (
			"required" if resolved_severity == "heavy" else "not_required"
		),
		"treatmentPlaceId": "",
		"treatmentStartedAtMinute": -1,
		"treatmentDueAtMinute": -1,
		"worldRevision": int(conflict.get("worldRevision", 0)),
		"runtimeRevision": _revision,
	}
	_injuries[actor_id] = injury
	var event := _append_injury_event(
		"injury_applied",
		injury,
		occurred_at_minute,
		resolved_severity,
	)
	return {
		"injury": _public_injury(injury),
		"events": [event],
	}


func _append_injury_event(
	event_type: String,
	injury: Dictionary,
	occurred_at_minute: int,
	reason: String,
) -> Dictionary:
	return _append_standalone_event(
		event_type,
		occurred_at_minute,
		{
			"conflictId": String(injury.get("sourceConflictId", "")),
			"rootConflictId": String(
				injury.get("rootConflictId", injury.get("sourceConflictId", "")),
			),
			"actorIds": [String(injury.get("actorId", ""))],
			"sourceActorId": String(injury.get("sourceActorId", "")),
			"sourceKind": String(injury.get("sourceKind", "")),
			"sourceRef": String(injury.get("sourceRef", "")),
			"subjectId": String(injury.get("actorId", "")),
			"placeId": String(injury.get("placeId", "")),
			"spaceId": String(injury.get("spaceId", "")),
			"severity": String(injury.get("severity", "")),
			"reason": reason,
			"causeSummary": String(injury.get("causeSummary", "")),
			"sourceConversationId": String(
				injury.get("sourceConversationId", ""),
			),
			"sourceEventIds": (
				injury.get("sourceEventIds", []) as Array
			).duplicate(true),
			"treatmentStatus": String(injury.get("treatmentStatus", "")),
			"treatmentPlaceId": String(injury.get("treatmentPlaceId", "")),
			"treatmentStartedAtMinute": int(
				injury.get("treatmentStartedAtMinute", -1)
			),
			"treatmentDueAtMinute": int(
				injury.get("treatmentDueAtMinute", -1)
			),
			"recoveryDueAtMinute": int(
				injury.get("recoveryDueAtMinute", -1)
			),
			"worldRevision": int(injury.get("worldRevision", 0)),
		},
	)


func _append_event(
	event_type: String,
	conflict: Dictionary,
	occurred_at_minute: int,
	extra: Dictionary,
) -> Dictionary:
	var event_data := {
		"conflictId": String(conflict.get("conflictId", "")),
		"rootConflictId": String(
			conflict.get("rootConflictId", conflict.get("conflictId", "")),
		),
		"actorIds": extra.get("actorIds", []),
		"sourceActorId": String(extra.get("sourceActorId", "")),
		"sourceKind": String(
			extra.get("sourceKind", conflict.get("sourceKind", ""))
		),
		"sourceRef": String(
			extra.get("sourceRef", conflict.get("sourceRef", ""))
		),
		"subjectId": String(extra.get("subjectId", "")),
		"attackKind": String(extra.get("attackKind", "")),
		"hitTargetIds": _string_array(
			extra.get("hitTargetIds", []) as Array
		),
		"placeId": String(conflict.get("placeId", "")),
		"spaceId": String(conflict.get("spaceId", "")),
		"severity": String(extra.get("severity", "")),
		"reason": String(extra.get("reason", "")),
		"causeId": String(
			extra.get("causeId", conflict.get("causeId", "")),
		),
		"causeSummary": String(
			extra.get(
				"causeSummary",
				conflict.get("causeSummary", ""),
			),
		),
		"sourceConversationId": String(
			extra.get(
				"sourceConversationId",
				conflict.get("sourceConversationId", ""),
			),
		),
		"sourceEventIds": (
			extra.get(
				"sourceEventIds",
				conflict.get("sourceEventIds", []),
			) as Array
		).duplicate(true),
		"worldRevision": int(conflict.get("worldRevision", 0)),
	}
	return _append_standalone_event(
		event_type,
		occurred_at_minute,
		event_data,
	)


func _append_standalone_event(
	event_type: String,
	occurred_at_minute: int,
	data: Dictionary,
) -> Dictionary:
	_event_sequence += 1
	var event := {
		"eventId": "conflict-event-%06d" % _event_sequence,
		"type": event_type,
		"occurredAtMinute": occurred_at_minute,
		"conflictId": String(data.get("conflictId", "")),
		"rootConflictId": String(
			data.get("rootConflictId", data.get("conflictId", "")),
		),
		"actorIds": _string_array(data.get("actorIds", []) as Array),
		"sourceActorId": String(data.get("sourceActorId", "")),
		"sourceKind": String(data.get("sourceKind", "")),
		"sourceRef": String(data.get("sourceRef", "")),
		"subjectId": String(data.get("subjectId", "")),
		"placeId": String(data.get("placeId", "")),
		"spaceId": String(data.get("spaceId", "")),
		"severity": String(data.get("severity", "")),
		"reason": String(data.get("reason", "")),
		"attackKind": String(data.get("attackKind", "")),
		"hitTargetIds": _string_array(
			data.get("hitTargetIds", []) as Array
		),
		"causeId": String(data.get("causeId", "")),
		"causeSummary": String(data.get("causeSummary", "")),
		"sourceConversationId": String(
			data.get("sourceConversationId", ""),
		),
		"sourceEventIds": (
			data.get("sourceEventIds", []) as Array
		).duplicate(true),
		"treatmentStatus": String(data.get("treatmentStatus", "")),
		"treatmentPlaceId": String(data.get("treatmentPlaceId", "")),
		"treatmentStartedAtMinute": int(
			data.get("treatmentStartedAtMinute", -1)
		),
		"treatmentDueAtMinute": int(data.get("treatmentDueAtMinute", -1)),
		"recoveryDueAtMinute": int(data.get("recoveryDueAtMinute", -1)),
		"worldRevision": int(data.get("worldRevision", 0)),
		"runtimeRevision": _revision,
	}
	_events.append(event)
	while _events.size() > MAX_EVENT_HISTORY:
		_events.pop_front()
	return event.duplicate(true)


func _public_conflict(conflict: Dictionary) -> Dictionary:
	return {
		"conflictId": String(conflict.get("conflictId", "")),
		"rootConflictId": String(
			conflict.get("rootConflictId", conflict.get("conflictId", "")),
		),
		"phase": String(conflict.get("phase", "")),
		"attackerId": String(conflict.get("attackerId", "")),
		"targetId": String(conflict.get("targetId", "")),
		"participantIds": _string_array(
			conflict.get("participantIds", []) as Array
		),
		"participantRoles": (
			conflict.get("participantRoles", {}) as Dictionary
		).duplicate(true),
		"placeId": String(conflict.get("placeId", "")),
		"spaceId": String(conflict.get("spaceId", "")),
		"attackKind": String(conflict.get("attackKind", "")),
		"sourceKind": String(conflict.get("sourceKind", "")),
		"causeId": String(conflict.get("causeId", "")),
		"causeSummary": String(conflict.get("causeSummary", "")),
		"sourceConversationId": String(
			conflict.get("sourceConversationId", ""),
		),
		"sourceEventIds": (
			conflict.get("sourceEventIds", []) as Array
		).duplicate(true),
		"startedAtMinute": int(conflict.get("startedAtMinute", 0)),
		"lastChangedAtMinute": int(
			conflict.get("lastChangedAtMinute", 0)
		),
		"endedAtMinute": int(conflict.get("endedAtMinute", -1)),
		"endReason": String(conflict.get("endReason", "")),
		"round": int(conflict.get("round", 0)),
		"maxRounds": int(conflict.get("maxRounds", 0)),
		"worldRevision": int(conflict.get("worldRevision", 0)),
		"runtimeRevision": int(conflict.get("runtimeRevision", 0)),
		"presentation": {
			"mode": (
				"shared_brawl_cloud"
					if String(conflict.get("phase", "")) == PHASE_BRAWL
					else (
						"avatar_rising_uppercut"
						if String(conflict.get("sourceKind", ""))
						== "avatar_intent"
						else "unilateral_hit"
					)
			),
			"hideParticipantSprites": (
				String(conflict.get("phase", "")) == PHASE_BRAWL
			),
		},
	}


func _public_injury(injury: Dictionary) -> Dictionary:
	return {
		"actorId": String(injury.get("actorId", "")),
		"severity": String(injury.get("severity", "")),
		"sourceConflictId": String(
			injury.get("sourceConflictId", "")
		),
		"rootConflictId": String(
			injury.get("rootConflictId", injury.get("sourceConflictId", "")),
		),
		"sourceActorId": String(injury.get("sourceActorId", "")),
		"sourceKind": String(injury.get("sourceKind", "")),
		"sourceRef": String(injury.get("sourceRef", "")),
		"causeSummary": String(injury.get("causeSummary", "")),
		"sourceConversationId": String(
			injury.get("sourceConversationId", ""),
		),
		"sourceEventIds": (
			injury.get("sourceEventIds", []) as Array
		).duplicate(true),
		"placeId": String(injury.get("placeId", "")),
		"spaceId": String(injury.get("spaceId", "")),
		"appliedAtMinute": int(injury.get("appliedAtMinute", 0)),
		"lastChangedAtMinute": int(
			injury.get("lastChangedAtMinute", 0)
		),
		"recoveryDueAtMinute": int(
			injury.get("recoveryDueAtMinute", -1)
		),
		"treatmentStatus": String(
			injury.get("treatmentStatus", "")
		),
		"treatmentPlaceId": String(
			injury.get("treatmentPlaceId", "")
		),
		"treatmentStartedAtMinute": int(
			injury.get("treatmentStartedAtMinute", -1)
		),
		"treatmentDueAtMinute": int(
			injury.get("treatmentDueAtMinute", -1)
		),
		"worldRevision": int(injury.get("worldRevision", 0)),
		"runtimeRevision": int(injury.get("runtimeRevision", 0)),
	}


func _active_conflict(conflict_id: String) -> Dictionary:
	var conflict := _conflicts.get(conflict_id, {}) as Dictionary
	if String(conflict.get("phase", "")) == PHASE_ENDED:
		return {}
	return conflict.duplicate(true)


func _pair_key(left_id: String, right_id: String) -> String:
	var values: Array[String] = [left_id, right_id]
	values.sort()
	return "%s|%s" % [values[0], values[1]]


func _tension_option_payload(
	option_id: String,
	kind: String,
	actor_id: String,
	target_id: String,
	tension_id: String,
	meaning: String,
) -> Dictionary:
	return {
		"optionId": option_id,
		"kind": kind,
		"actorId": actor_id,
		"targetId": target_id,
		"tensionId": tension_id,
		"meaning": meaning,
	}


func _tension_option(
	option_id: String,
	actor_id: String,
	target_id: String,
	now_minute: int,
) -> Dictionary:
	for option: Dictionary in tension_options_for_actor(
		actor_id,
		[target_id],
		now_minute,
	):
		if String(option.get("optionId", "")) == option_id:
			return option
	return {}


func _consume_attack_cause(
	cause_id: String,
	attacker_id: String,
	target_id: String,
	now_minute: int,
	conflict_id: String,
) -> void:
	var option := _tension_option(
		cause_id,
		attacker_id,
		target_id,
		now_minute,
	)
	var tension_id := String(option.get("tensionId", ""))
	if tension_id.is_empty():
		return
	var tension := _tensions.get(tension_id, {}) as Dictionary
	if tension.is_empty():
		return
	var pair_key := _pair_key(attacker_id, target_id)
	tension["stage"] = "aftermath"
	tension["sourceConflictId"] = conflict_id
	tension["lastChangedAtMinute"] = now_minute
	tension["expiresAtMinute"] = (
		now_minute + _pair_cooldown_minutes + _tension_expiry_minutes
	)
	tension["runtimeRevision"] = _revision
	_tensions[tension_id] = tension
	_pair_cooldown_until[pair_key] = now_minute + _pair_cooldown_minutes


func _expire_tensions(now_minute: int) -> void:
	var expired_ids: Array[String] = []
	for tension_id_value: Variant in _tensions:
		var tension_id := String(tension_id_value)
		var tension := _tensions.get(tension_id, {}) as Dictionary
		if now_minute >= int(tension.get("expiresAtMinute", -1)):
			expired_ids.append(tension_id)
	if expired_ids.is_empty():
		return
	for tension_id: String in expired_ids:
		var tension := _tensions.get(tension_id, {}) as Dictionary
		var participants := _string_array(
			tension.get("participantIds", []) as Array,
		)
		if participants.size() == 2:
			_tension_by_pair.erase(_pair_key(participants[0], participants[1]))
		_tensions.erase(tension_id)
		_revision += 1


func _public_tensions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var tension_ids: Array[String] = []
	for tension_id_value: Variant in _tensions:
		tension_ids.append(String(tension_id_value))
	tension_ids.sort()
	for tension_id: String in tension_ids:
		result.append(_public_tension(
			_tensions.get(tension_id, {}) as Dictionary,
		))
	return result


func _public_tension(tension: Dictionary) -> Dictionary:
	if tension.is_empty():
		return {}
	return {
		"tensionId": String(tension.get("tensionId", "")),
		"participantIds": _string_array(
			tension.get("participantIds", []) as Array,
		),
		"initiatorId": String(tension.get("initiatorId", "")),
		"targetId": String(tension.get("targetId", "")),
		"stage": String(tension.get("stage", "")),
		"reasonSummary": String(tension.get("reasonSummary", "")),
		"causeSummary": String(tension.get("causeSummary", "")),
		"sourceConversationId": String(
			tension.get("sourceConversationId", ""),
		),
		"sourceConflictId": String(
			tension.get("sourceConflictId", ""),
		),
		"sourceEventIds": (
			tension.get("sourceEventIds", []) as Array
		).duplicate(true),
		"startedAtMinute": int(tension.get("startedAtMinute", 0)),
		"lastChangedAtMinute": int(
			tension.get("lastChangedAtMinute", 0),
		),
		"expiresAtMinute": int(tension.get("expiresAtMinute", 0)),
		"lastActorId": String(tension.get("lastActorId", "")),
		"runtimeRevision": int(tension.get("runtimeRevision", 0)),
	}


func _validate_attack_command(command: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for field: String in [
		"requestId",
		"attackerId",
		"targetId",
		"placeId",
		"spaceId",
		"sourceKind",
		"sourceRef",
	]:
		if String(command.get(field, "")).strip_edges().is_empty():
			errors.append("%s is required" % field)
	if String(command.get("attackerId", "")) == String(
		command.get("targetId", "")
	):
		errors.append("attackerId and targetId must differ")
	var attack_kind := String(command.get("attackKind", ""))
	var source_kind := String(command.get("sourceKind", ""))
	if not ATTACK_KINDS.has(attack_kind):
		errors.append("attackKind is invalid")
	elif source_kind == "avatar_intent":
		if not AVATAR_ATTACK_KINDS.has(attack_kind):
			errors.append("attackKind is invalid for avatar_intent")
	elif not RESIDENT_ATTACK_KINDS.has(attack_kind):
		errors.append("attackKind is reserved for avatar_intent")
	for field: String in ["occurredAtMinute", "worldRevision"]:
		if typeof(command.get(field)) != TYPE_INT or int(command[field]) < 0:
			errors.append("%s must be a non-negative integer" % field)
	return errors


func _validate_state(state: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if int(state.get("schemaVersion", 0)) != STATE_SCHEMA_VERSION:
		errors.append("schemaVersion is invalid")
	for field: String in [
		"settings",
		"conflicts",
		"activeConflictByActor",
		"injuries",
		"requestResults",
	]:
		if typeof(state.get(field)) != TYPE_DICTIONARY:
			errors.append("%s must be a dictionary" % field)
	if typeof(state.get("events")) != TYPE_ARRAY:
		errors.append("events must be an array")
	for field: String in [
		"tensions",
		"tensionByPair",
		"pairCooldownUntil",
	]:
		if state.has(field) and typeof(state.get(field)) != TYPE_DICTIONARY:
			errors.append("%s must be a dictionary" % field)
	for field: String in [
		"conflictSequence",
		"eventSequence",
		"revision",
	]:
		if typeof(state.get(field)) != TYPE_INT or int(state[field]) < 0:
			errors.append("%s must be a non-negative integer" % field)
	if (
		state.has("tensionSequence")
		and (
			typeof(state.get("tensionSequence")) != TYPE_INT
			or int(state.get("tensionSequence", -1)) < 0
		)
	):
		errors.append("tensionSequence must be a non-negative integer")
	if not errors.is_empty():
		return errors
	var conflicts := state.get("conflicts", {}) as Dictionary
	var active_by_actor := (
		state.get("activeConflictByActor", {}) as Dictionary
	)
	for actor_id_value: Variant in active_by_actor:
		var actor_id := String(actor_id_value).strip_edges()
		var conflict_id := String(active_by_actor[actor_id_value])
		var conflict := conflicts.get(conflict_id, {}) as Dictionary
		if (
			actor_id.is_empty()
			or conflict.is_empty()
			or String(conflict.get("phase", "")) == PHASE_ENDED
			or not (conflict.get("participantIds", []) as Array).has(actor_id)
		):
			errors.append("active conflict actor mapping is invalid")
	var tensions := state.get("tensions", {}) as Dictionary
	var tension_by_pair := state.get("tensionByPair", {}) as Dictionary
	for tension_id_value: Variant in tensions:
		var tension_id := String(tension_id_value).strip_edges()
		var tension := tensions.get(tension_id_value, {}) as Dictionary
		var participants := _string_array(
			tension.get("participantIds", []) as Array,
		)
		if (
			tension_id.is_empty()
			or String(tension.get("tensionId", "")) != tension_id
			or participants.size() != 2
			or participants[0] == participants[1]
			or String(tension.get("stage", "")) not in TENSION_STAGES
			or int(tension.get("expiresAtMinute", -1)) < 0
		):
			errors.append("tension state is invalid")
			continue
		var pair_key := _pair_key(participants[0], participants[1])
		if String(tension_by_pair.get(pair_key, "")) != tension_id:
			errors.append("tension pair mapping is invalid")
	return errors


func _store_request_failure(
	request_id: String,
	error_code: String,
) -> Dictionary:
	var result := _failure(error_code)
	result["duplicate"] = false
	_request_results[request_id] = result.duplicate(true)
	return result


func _string_array(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		var text := String(value).strip_edges()
		if not text.is_empty() and not result.has(text):
			result.append(text)
	return result


func _success(data: Dictionary = {}) -> Dictionary:
	var result := {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"revision": _revision,
	}
	for key_value: Variant in data:
		result[key_value] = data[key_value]
	return result


func _failure(
	error_code: String,
	meta: Dictionary = {},
) -> Dictionary:
	var result := {
		"ok": false,
		"errorCode": error_code,
		"retryable": false,
		"revision": _revision,
	}
	for key_value: Variant in meta:
		result[key_value] = meta[key_value]
	return result
