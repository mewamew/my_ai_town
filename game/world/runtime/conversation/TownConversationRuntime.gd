class_name TownConversationRuntime
extends RefCounted

const AGENT_ACTIVITY_SUBMISSION_RUNTIME := preload(
	"res://world/runtime/activity/TownAgentActivitySubmissionRuntime.gd"
)
const ACTION_RESULT_RUNTIME := preload(
	"res://world/runtime/action/TownActionResultRuntime.gd"
)


const ACTION_PREVIEW_RUNTIME := preload(
	"res://world/runtime/action/TownActionPreviewRuntime.gd"
)
const FOLLOW_UP_ACTION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationFollowUpActionRuntime.gd"
)


const WORLD_LOG_COMMIT_RUNTIME := preload(
	"res://world/runtime/log/TownWorldLogCommitRuntime.gd"
)


const PERCEPTION_RUNTIME := preload(
	"res://world/runtime/perception/TownPerceptionRuntime.gd"
)
const ACTION_PRESENTATION := preload(
	"res://world/runtime/presentation/TownActionPresentationSemantics.gd"
)
const CONVERSATION_CONFLICT_BRIDGE := preload(
	"res://world/runtime/conversation/TownConversationConflictBridge.gd"
)
# 对话状态机与参与者管理(自 TownWorldRuntime 下沉)。world 为世界运行时实例;
# 对话回合、承诺激活、快照投影、超时收束均在此,conversation_changed 由
# world 的信号中继发出。主文件保留 player_*_conversation 门面转发。

static func _start_conversation(
	world,
	traveler_relationship_state: TownTravelerRelationshipState,
	initiator_name: String,
	action: Dictionary,
) -> void:
	var target_name := String(action.get("target_resident_id", ""))
	var conversation_place := String(
		(world.resident_registry.records.get(initiator_name, {}) as Dictionary).get(
			"currentPlace",
			"",
		),
	).strip_edges()
	var conversation_id: String = world.conversation_state.next_id()
	var turn := _conversation_turn(world, initiator_name, action, 1)
	var conversation := {
		"conversationId": conversation_id,
		"participants": [initiator_name, target_name],
		"initiator": initiator_name,
		"turns": [turn],
		"waitingFor": target_name,
		"status": "active",
		"startedAt": world.get_time(),
		"updatedAt": world.get_time(),
		"placeName": conversation_place,
		"endReason": null,
	}
	var clinician_id := initiator_name
	var patient_id := target_name
	var expected_binding : Variant = world.CLINIC_INTERVIEW_RUNTIME.binding_for_pair(world,
		clinician_id,
		patient_id,
	)
	if (
		String(expected_binding.get("requestId", ""))
		!= String(action.get("medicalRequestId", ""))
		or String(expected_binding.get("taskId", ""))
		!= String(action.get("medicalTaskId", ""))
	):
		clinician_id = target_name
		patient_id = initiator_name
	var bound_medical := _begin_clinic_interview_conversation(world,
		clinician_id,
		patient_id,
		conversation_id,
		action,
	)
	if not bound_medical.is_empty():
		conversation["medicalRequestId"] = String(
			bound_medical.get("requestId", ""),
		)
		conversation["medicalTaskId"] = String(
			bound_medical.get("taskId", ""),
		)
	action["conversationId"] = conversation_id
	world.conversation_state.records[conversation_id] = conversation
	world.conversation_state.autonomous_idle_seconds[conversation_id] = 0.0
	_hold_conversation_invitation_target(world, target_name)
	_update_conversation_snapshots(world, traveler_relationship_state, conversation)
	world.conversation_changed.emit(conversation_id, conversation.duplicate(true))
	var action_story: Variant = world.event_journal.action_story_context(
		String(action.get("action_id", ""))
	)
	var root_event_ids := (
		action_story.get("rootEventIds", []) as Array
	).duplicate(true)
	var opening_cause_ids := (
		action_story.get("directCauseEventIds", []) as Array
	).duplicate(true)
	if opening_cause_ids.is_empty():
		opening_cause_ids = root_event_ids.duplicate(true)
	var opening_event : Variant = world.WORLD_EVENT_DELIVERY_RUNTIME.queue_for_person(world, target_name, {
		"type": "搭话",
		"conversation_id": conversation_id,
		"turn": turn.duplicate(true),
		"participant_resident_ids": [
			initiator_name,
			target_name,
		],
		"response_required": true,
		"placeName": conversation_place,
		"causedByEventIds": opening_cause_ids,
		"storyRootEventIds": root_event_ids.duplicate(true),
	})
	world.event_journal.set_conversation_story_context(conversation_id, {
		"rootEventIds": root_event_ids,
		"lastEventId": String(opening_event.get("event_id", "")),
	})
	_queue_overhear_events(world, conversation, turn)
	world._complete_private_message_delivery(
		initiator_name,
		target_name,
		turn,
	)


static func _apply_conversation_reply(
	world,
	traveler_relationship_state: TownTravelerRelationshipState,
	speaker_name: String,
	action: Dictionary,
) -> void:
	var conversation_id := String(action.get("conversation_id", ""))
	if not world.conversation_state.records.has(conversation_id):
		return
	var conversation := world.conversation_state.records[conversation_id] as Dictionary
	if String(conversation.get("status", "")) != "active":
		return
	var turns := conversation.get("turns", []) as Array
	var turn := _conversation_turn(world, speaker_name, action, turns.size() + 1)
	world.CLINIC_INTERVIEW_RUNTIME.record_response(world,
		conversation,
		speaker_name,
		action,
		int(turn.get("turn_id", turns.size() + 1)),
	)
	turns.append(turn)
	_record_traveler_reply(
		world,
		traveler_relationship_state,
		conversation,
		speaker_name,
		action,
		turn,
	)
	var other_name := _other_conversation_participant(world, conversation, speaker_name)
	conversation["waitingFor"] = other_name
	conversation["updatedAt"] = world.get_time()
	world.conversation_state.autonomous_idle_seconds[conversation_id] = 0.0
	_complete_conversation_action(world, other_name, "completed", "对方已经答话")
	_queue_overhear_events(world, conversation, turn)
	if bool(action.get("end", false)):
		# Publish the final turn and ended state atomically. Exposing an active
		# snapshot first briefly tells the UI that it is the other person's turn,
		# which can re-enable the player's composer before the same reply closes
		# the conversation.
		_end_conversation(
			world,
			traveler_relationship_state,
			conversation_id,
			"主动结束",
			"completed",
		)
		return
	if (
		_is_resident_only_conversation(world, conversation)
		and turns.size() >= world.MAX_AUTONOMOUS_CONVERSATION_TURNS
	):
		# Resident-only conversations must not keep two model requests waking
		# each other forever when neither side chooses end=true.
		_end_conversation(
			world,
			traveler_relationship_state,
			conversation_id,
			"无法继续",
			"completed",
		)
		return
	_update_conversation_snapshots(world, traveler_relationship_state, conversation)
	world.conversation_changed.emit(conversation_id, conversation.duplicate(true))
	var conversation_story: Dictionary = (
		world.event_journal.conversation_story_context(conversation_id)
	)
	var previous_story_event_id := String(
		conversation_story.get("lastEventId", "")
	)
	var reply_event : Variant = world.WORLD_EVENT_DELIVERY_RUNTIME.queue_for_person(world, other_name, {
		"type": "对方答话",
		"conversation_id": conversation_id,
		"turn": turn.duplicate(true),
		"placeName": String(conversation.get("placeName", "")),
		"participant_resident_ids": (
			conversation.get("participants", []) as Array
		).duplicate(true),
		"causedByEventIds": (
			[previous_story_event_id]
			if not previous_story_event_id.is_empty()
			else []
		),
		"storyRootEventIds": (
			conversation_story.get("rootEventIds", []) as Array
		).duplicate(true),
	})
	conversation_story["lastEventId"] = String(
		reply_event.get("event_id", "")
	)
	world.event_journal.set_conversation_story_context(
		conversation_id,
		conversation_story,
	)


static func _end_conversation(
	world,
	traveler_relationship_state: TownTravelerRelationshipState,
	conversation_id: String,
	reason: String,
	action_status: String,
) -> void:
	if not world.conversation_state.records.has(conversation_id):
		return
	var conversation := world.conversation_state.records[conversation_id] as Dictionary
	if String(conversation.get("status", "")) != "active":
		return
	conversation["status"] = "ended"
	conversation["waitingFor"] = null
	conversation["updatedAt"] = world.get_time()
	conversation["endReason"] = reason
	conversation["endedAt"] = world.get_time()
	_record_traveler_conversation(
		world,
		traveler_relationship_state,
		conversation,
	)
	_finish_clinic_interview_conversation(world, conversation, reason)
	world.conversation_state.autonomous_idle_seconds.erase(conversation_id)
	var participants := (conversation.get("participants", []) as Array).duplicate()
	for participant_value: Variant in participants:
		var participant_name := String(participant_value)
		_complete_conversation_action(world,
			participant_name,
			action_status,
			_conversation_action_result_reason(world, reason),
		)
	for participant_value: Variant in participants:
		var participant_name := String(participant_value)
		if world.resident_registry.records.has(participant_name):
			var resident := world.resident_registry.records[participant_name] as Dictionary
			resident["conversationId"] = ""
			resident["conversation"] = null
			_resume_action_after_conversation(world,
				participant_name,
				resident,
			)
			world._emit_resident_state_changed(participant_name)
		elif participant_name == world.player_avatar_id():
			world.actor_presentation_state.player_avatar["conversationId"] = ""
			world.actor_presentation_state.player_avatar["conversation"] = null
			world.player_avatar_state_changed.emit(world.get_player_avatar_state())
	world.conversation_changed.emit(conversation_id, conversation.duplicate(true))
	var conversation_story: Dictionary = (
		world.event_journal.conversation_story_context(conversation_id)
	)
	var previous_story_event_id := String(
		conversation_story.get("lastEventId", "")
	)
	var end_causes: Array = (
		[previous_story_event_id]
		if not previous_story_event_id.is_empty()
		else (
			conversation_story.get("rootEventIds", []) as Array
		).duplicate(true)
	)
	for participant_value: Variant in participants:
		var participant_name := String(participant_value)
		var end_event := {
			"type": "对话结束",
			"conversation_id": conversation_id,
			"turns": (conversation.get("turns", []) as Array).duplicate(true),
			"placeName": String(conversation.get("placeName", "")),
			"reason": reason,
			"participant_resident_ids": participants.duplicate(true),
			"causedByEventIds": end_causes.duplicate(true),
			"storyRootEventIds": (
				conversation_story.get("rootEventIds", []) as Array
			).duplicate(true),
		}
		world.WORLD_EVENT_DELIVERY_RUNTIME.queue_for_person(world, participant_name, end_event)
	_activate_conversation_commitments(world, conversation_id)
	_trim_ended_conversation_history(world)


static func _activate_conversation_commitments(world, conversation_id: String) -> void:
	var source_prefix := "conversation-commitment:%s:" % conversation_id
	for matter_value: Variant in world._social_matters.list_matters(false) as Array:
		var matter := matter_value as Dictionary
		var source_ref := matter.get("source_state_ref", {}) as Dictionary
		if (
			String(source_ref.get("source_kind", "")) != "conversation_commitment"
			or not String(source_ref.get("source_id", "")).begins_with(source_prefix)
		):
			continue
		for resident_value: Variant in matter.get("participants", {}) as Dictionary:
			var resident_id := String(resident_value)
			var participant := (matter.get("participants", {}) as Dictionary).get(resident_id, {}) as Dictionary
			if String(participant.get("status", "")) != "assigned":
				continue
			_activate_conversation_commitment_action(world,
				String(matter.get("matter_id", "")),
				resident_id,
				participant.get("action_goal", {}) as Dictionary,
			)


static func _activate_conversation_commitment_action(
	world,
	matter_id: String,
	resident_id: String,
	action_goal: Dictionary,
) -> void:
	var resident := world.resident_registry.records.get(resident_id, {}) as Dictionary
	if resident.is_empty() or not world.resident_is_present(resident):
		_fail_conversation_commitment_action(world, matter_id, resident_id, action_goal, "承诺者当前不在小镇")
		return
	var goal_id := String(action_goal.get("goal_id", ""))
	var capability_id := String(action_goal.get("capability_id", ""))
	var target_refs := action_goal.get("target_refs", {}) as Dictionary
	var action_id := "commitment:%s" % goal_id
	var decision_id := "conversation-follow-up:%s" % goal_id
	var action := {}
	match capability_id:
		"world.go_to_place":
			action = {"action_id": action_id, "type": "去", "place": String(target_refs.get("place_id", "")), "line": "我去履行刚才答应的事"}
		"world.perform_activity":
			action = {"action_id": action_id, "type": "做活动", "activity_id": String(target_refs.get("activity_id", "")), "line": "我开始做刚才答应的事"}
		"world.start_conversation":
			action = {"action_id": action_id, "type": "搭话", "target_resident_id": String(target_refs.get("resident_id", "")), "say": "我来履行刚才答应的事。", "narration": "我走近对方", "photos": []}
		"world.escort_person_to_place":
			action = {"action_id": action_id, "type": "去", "place": String(target_refs.get("place_id", "")), "line": "跟我来，我带你过去"}
		"world.fetch_service_for_person":
			var service_place := String(target_refs.get("service_place_id", ""))
			action = (
				{"action_id": action_id, "type": "待着", "line": "你在这里等我，我去取一下"}
				if service_place == String(resident.get("currentPlace", ""))
				else {"action_id": action_id, "type": "去", "place": service_place, "line": "你在这里等我，我去取一下"}
			)
		_:
			_fail_conversation_commitment_action(world, matter_id, resident_id, action_goal, "当前没有接入这项后续行动")
			return
	if capability_id == "world.perform_activity":
		var activity_result := AGENT_ACTIVITY_SUBMISSION_RUNTIME.submit(
			world, resident_id, resident, decision_id, action, "",
		) as Dictionary
		if activity_result.get("ok") != true:
			_fail_conversation_commitment_action(world, matter_id, resident_id, action_goal, String((activity_result.get("errors", ["答应的活动当前无法开始"]) as Array)[0]))
		return
	var preparation : Variant = world.ACTION_PREPARATION_RUNTIME.prepare(world, resident, action)
	if preparation.get("ok") != true:
		_fail_conversation_commitment_action(world, matter_id, resident_id, action_goal, String((preparation.get("errors", ["答应的行动当前无法开始"]) as Array)[0]))
		return
	var prepared_action := (preparation.get("action", {}) as Dictionary).duplicate(true)
	if capability_id == "world.escort_person_to_place":
		FOLLOW_UP_ACTION_RUNTIME.decorate(
			world, prepared_action, "escort", "leading", target_refs,
		)
	elif capability_id == "world.fetch_service_for_person":
		FOLLOW_UP_ACTION_RUNTIME.decorate(world,
			prepared_action,
			"fetch_service",
			"collecting" if String(prepared_action.get("type", "")) == "待着" else "going_to_source",
			target_refs,
		)
		if String(prepared_action.get("type", "")) == "待着":
			prepared_action["completeAbsoluteMinute"] = int(world._environment.get_absolute_minute()) + world.SERVICE_FETCH_DURATION_MINUTES
	(resident.get("usedActionIds", {}) as Dictionary)[action_id] = true
	var confirmed := ACTION_PREVIEW_RUNTIME.confirm(world,
		resident_id,
		resident,
		decision_id,
		"replace_current",
		prepared_action,
	) as Dictionary
	if (
		confirmed.get("ok") == true
		and capability_id == "world.escort_person_to_place"
	):
		FOLLOW_UP_ACTION_RUNTIME.install_resident_follower(
			world,
			resident_id,
			action_goal,
		)


static func _fail_conversation_commitment_action(
	world,
	matter_id: String,
	resident_id: String,
	action_goal: Dictionary,
	reason: String,
) -> void:
	world.SOCIAL_ASSIGNMENT_RESULT_RUNTIME.record_result(world,
		{"matter_id": matter_id, "action_goal": action_goal.duplicate(true)},
		resident_id,
		{"result_id": "conversation-follow-up-failed:%s" % String(action_goal.get("goal_id", "")), "reason": reason},
		"failed",
	)


static func _complete_conversation_action(world, resident_name: String, status: String, reason: String) -> void:
	if not world.resident_registry.records.has(resident_name):
		return
	var resident := world.resident_registry.records[resident_name] as Dictionary
	var current_action := resident.get("currentAction", {}) as Dictionary
	var reply_action := resident.get("conversationReplyAction", {}) as Dictionary
	var action := reply_action if not reply_action.is_empty() else current_action
	var conversation_id := String(resident.get("conversationId", ""))
	if action.is_empty() or not _action_belongs_to_conversation(world, action, conversation_id):
		return
	var action_id := String(action.get("action_id", ""))
	world.SOCIAL_ASSIGNMENT_RESULT_RUNTIME.record_matching_action_result(world,
		resident_name,
		action,
		world.SOCIAL_GOAL_MATCHING_RUNTIME.execution_status(status),
		reason,
	)
	var reply_is_shadowed := (
		not reply_action.is_empty()
		and String(current_action.get("action_id", ""))
		!= String(reply_action.get("action_id", ""))
	)
	resident["conversationReplyAction"] = {}
	if not reply_is_shadowed:
		resident["currentAction"] = {}
		resident["actionSuspendedAbsoluteMinute"] = -1
	resident["doing"] = reason
	ACTION_RESULT_RUNTIME.queue(
		world, resident_name, action_id, status, reason, true, false,
	)
	world._emit_resident_state_changed(resident_name)


static func _action_belongs_to_conversation(world, action: Dictionary, conversation_id: String) -> bool:
	if conversation_id.is_empty():
		return false
	if String(action.get("type", "")) == "搭话":
		return String(action.get("conversationId", "")) == conversation_id
	if String(action.get("type", "")) == "答话":
		return String(action.get("conversation_id", "")) == conversation_id
	return false


static func _active_conversation_for_person(world, person_name: String) -> Dictionary:
	var person : Variant = world._person_state(person_name)
	if person.is_empty():
		return {}
	var conversation_id := String(person.get("conversationId", ""))
	if conversation_id.is_empty() or not world.conversation_state.records.has(conversation_id):
		return {}
	var conversation := world.conversation_state.records[conversation_id] as Dictionary
	return conversation if String(conversation.get("status", "")) == "active" else {}


static func _is_initial_invitation_for(world, resident_name: String, conversation: Dictionary) -> bool:
	return not conversation.is_empty() and String(conversation.get("waitingFor", "")) == resident_name and String(conversation.get("initiator", "")) != resident_name and (conversation.get("turns", []) as Array).size() == 1


static func _is_resident_only_conversation(world, conversation: Dictionary) -> bool:
	var participants := conversation.get("participants", []) as Array
	if participants.size() != 2:
		return false
	for participant_value: Variant in participants:
		if not world.resident_registry.records.has(String(participant_value)):
			return false
	return true


static func _is_player_initiated_conversation(world, conversation: Dictionary) -> bool:
	return (
		not conversation.is_empty()
		and String(conversation.get("initiator", "")) == world.player_avatar_id()
	)


static func _hold_conversation_invitation_target(world, resident_id: String) -> void:
	if not world.resident_registry.records.has(resident_id):
		return
	var resident := world.resident_registry.records[resident_id] as Dictionary
	if (resident.get("currentAction", {}) as Dictionary).is_empty():
		return
	if int(resident.get("actionSuspendedAbsoluteMinute", -1)) >= 0:
		return
	resident["actionSuspendedAbsoluteMinute"] = int(
		world._environment.get_absolute_minute(),
	)
	resident["movementRevision"] = int(resident.get("movementRevision", 1)) + 1
	resident["doing"] = "停下来等待回应"
	world._bump_world_revision()
	world._emit_resident_state_changed(resident_id)
	world.resident_action_phase_changed.emit(
		resident_id,
		ACTION_PRESENTATION._resident_action_phase_projection(world, resident),
	)


static func _resident_has_suspended_conversation(
	world,
	resident: Dictionary,
) -> bool:
	var resident_id := String(resident.get("residentId", ""))
	var conversation := _active_conversation_for_person(world, resident_id)
	return not conversation.is_empty()


static func _resume_action_after_conversation(
	world,
	resident_id: String,
	resident: Dictionary,
) -> void:
	if int(resident.get("actionSuspendedAbsoluteMinute", -1)) < 0:
		return
	world.ACTION_TIMING.resume_suspended_action(world, resident)
	var action := resident.get("currentAction", {}) as Dictionary
	if action.is_empty():
		return
	if not world.ACTION_VALIDITY_POLICY.is_valid(world, resident, action):
		world.ACTION_SETTLEMENT_RUNTIME.interrupt(world,
			resident_id,
			"交谈后，原来的事务已经无法继续",
		)
		return
	resident["doing"] = world.ACTION_PROJECTION_MODULE.default_doing(world, action)
	world.resident_action_phase_changed.emit(
		resident_id,
		ACTION_PRESENTATION._resident_action_phase_projection(world, resident),
	)


static func _resident_pair_conversation_on_cooldown(
	world,
	left_resident_id: String,
	right_resident_id: String,
) -> bool:
	if not world.resident_registry.records.has(left_resident_id) or not world.resident_registry.records.has(
		right_resident_id
	):
		return false
	var now_absolute := int(world._environment.get_absolute_minute())
	for conversation_value: Variant in world.conversation_state.records.values():
		var conversation := conversation_value as Dictionary
		if String(conversation.get("status", "")) != "ended":
			continue
		var participants := conversation.get("participants", []) as Array
		if (
			participants.size() != 2
			or not participants.has(left_resident_id)
			or not participants.has(right_resident_id)
		):
			continue
		var ended_at := conversation.get("endedAt", {}) as Dictionary
		if (
			now_absolute - world.ACTION_SUPPORT.absolute_minute(ended_at)
			< world.RESIDENT_CONVERSATION_PAIR_COOLDOWN_MINUTES
		):
			return true
	return false


static func _trim_ended_conversation_history(world) -> void:
	var ended_ids: Array[String] = []
	for conversation_id_value: Variant in world.conversation_state.records:
		var conversation_id := String(conversation_id_value)
		var conversation := world.conversation_state.records[conversation_id] as Dictionary
		if String(conversation.get("status", "")) == "ended":
			ended_ids.append(conversation_id)
	ended_ids.sort_custom(
		func(left: String, right: String) -> bool:
			return int(left.get_slice("-", 1)) < int(right.get_slice("-", 1))
	)
	while ended_ids.size() > world.MAX_ENDED_CONVERSATION_HISTORY:
		var oldest_id := String(ended_ids.pop_front())
		world.conversation_state.records.erase(oldest_id)
		world.event_journal.erase_conversation_story_context(oldest_id)


static func _other_conversation_participant(world, conversation: Dictionary, resident_name: String) -> String:
	for participant_value: Variant in conversation.get("participants", []) as Array:
		var participant_name := String(participant_value)
		if participant_name != resident_name:
			return participant_name
	return ""


static func _conversation_turn(world, speaker_name: String, action: Dictionary, turn_id: int) -> Dictionary:
	return {
		"turn_id": turn_id,
		"speaker_resident_id": world.person_id_for_name(speaker_name),
		"speaker": world.person_name_for_id(world.person_id_for_name(speaker_name)),
		"say": String(action.get("say", "")),
		"narration": String(action.get("narration", "")),
		"photos": (action.get("photos", []) as Array).duplicate(true),
	}


static func _record_traveler_reply(
	world,
	traveler_relationship_state: TownTravelerRelationshipState,
	conversation: Dictionary,
	resident_ref: String,
	action: Dictionary,
	turn: Dictionary,
) -> void:
	var resident_id: String = world._resident_key(resident_ref)
	if resident_id.is_empty() or not action.has("traveler_affinity_delta"):
		return
	var delta_value: Variant = action.get("traveler_affinity_delta")
	if typeof(delta_value) != TYPE_INT:
		return
	if traveler_relationship_state.record_resident_reply(
		world.player_avatar_id(),
		resident_id,
		conversation,
		turn,
		int(delta_value),
	):
		world._bump_world_revision(false)


static func _record_traveler_conversation(
	world,
	traveler_relationship_state: TownTravelerRelationshipState,
	conversation: Dictionary,
) -> void:
	var avatar_id: String = world.player_avatar_id()
	for participant_value: Variant in conversation.get("participants", []) as Array:
		var participant_id := String(participant_value)
		if participant_id == avatar_id or not world.resident_registry.records.has(participant_id):
			continue
		if traveler_relationship_state.record_ended_conversation(
			avatar_id,
			participant_id,
			conversation,
		):
			world._bump_world_revision(false)


static func _agent_traveler_projection_for_conversation(
	world,
	traveler_relationship_state: TownTravelerRelationshipState,
	participant_name: String,
	other_name: String,
) -> Dictionary:
	var avatar_id: String = world.player_avatar_id()
	if (
		not world.resident_registry.records.has(participant_name)
		or world.person_id_for_name(other_name) != avatar_id
	):
		return {}
	return traveler_relationship_state.agent_projection_for_resident(
		avatar_id,
		participant_name,
	)


static func _update_conversation_snapshots(
	world,
	traveler_relationship_state: TownTravelerRelationshipState,
	conversation: Dictionary,
) -> void:
	# 快照只保留最近若干轮：完整 turns 的唯一权威在 conversation_state，
	# 而快照会被塞进居民状态/化身状态/wake packet 并被高频深拷贝，
	# 不裁剪会让化身长对话把位置同步和唤醒链路拖成 O(轮数)。
	var full_turns := conversation.get("turns", []) as Array
	var snapshot_turns := (
		full_turns.slice(full_turns.size() - world.CONVERSATION_SNAPSHOT_TURN_LIMIT)
		if full_turns.size() > world.CONVERSATION_SNAPSHOT_TURN_LIMIT
		else full_turns
	)
	for participant_value: Variant in conversation.get("participants", []) as Array:
		var participant_name := String(participant_value)
		var other_name := _other_conversation_participant(world, conversation, participant_name)
		var snapshot := {
			"conversation_id": String(conversation.get("conversationId", "")),
			"with_resident_id": world.person_id_for_name(other_name),
			"with": world.person_name_for_id(world.person_id_for_name(other_name)),
			"turns": snapshot_turns.duplicate(true),
			"medical_context": world.CLINIC_INTERVIEW_RUNTIME.projection_for_participant(world,
				conversation,
				participant_name,
			),
		}
		var traveler_relationship := _agent_traveler_projection_for_conversation(
			world,
			traveler_relationship_state,
			participant_name,
			other_name,
		)
		if not traveler_relationship.is_empty():
			snapshot["traveler_relationship"] = traveler_relationship
		if world.resident_registry.records.has(participant_name):
			var resident := world.resident_registry.records[participant_name] as Dictionary
			resident["conversationId"] = String(conversation.get("conversationId", ""))
			resident["conversation"] = snapshot
			world._emit_resident_state_changed(participant_name)
		elif participant_name == world.player_avatar_id():
			world.actor_presentation_state.player_avatar["conversationId"] = String(conversation.get("conversationId", ""))
			world.actor_presentation_state.player_avatar["conversation"] = snapshot
			world.player_avatar_state_changed.emit(world.get_player_avatar_state())


static func _queue_overhear_events(world, conversation: Dictionary, turn: Dictionary) -> void:
	var participant_names := conversation.get("participants", []) as Array
	var speaker_resident_ids: Array[String] = []
	var speakers: Array[String] = []
	for participant_value: Variant in participant_names:
		var participant_ref := String(participant_value)
		var participant_id : Variant = world.person_id_for_name(participant_ref)
		if not participant_id.is_empty():
			speaker_resident_ids.append(participant_id)
			speakers.append(world.person_name_for_id(participant_id))
	var recipients := {}
	for participant_value: Variant in participant_names:
		var participant : Variant = world._person_state(String(participant_value))
		for nearby_value: Variant in participant.get("nearby", []) as Array:
			var nearby_name := String(nearby_value)
			if world.resident_registry.records.has(nearby_name) and not participant_names.has(nearby_name):
				recipients[nearby_name] = true
	for recipient_name_value: Variant in recipients:
		world.WORLD_EVENT_DELIVERY_RUNTIME.queue(world, String(recipient_name_value), {
			"type": "旁听",
			"conversation_id": String(conversation.get("conversationId", "")),
			"speaker_resident_ids": speaker_resident_ids.duplicate(),
			"speakers": speakers.duplicate(),
			"turn": turn.duplicate(true),
		})


static func _conversation_action_result_reason(world, end_reason: String) -> String:
	match end_reason:
		"拒绝接话": return "对方没有接话"
		"一方离开": return "对话因一方离开而结束"
		"主动结束": return "对话已经主动结束"
		_: return "对话已经结束"


static func _end_conversations_out_of_range(
	world,
	traveler_relationship_state: TownTravelerRelationshipState,
) -> void:
	for conversation_id_value: Variant in world.conversation_state.records.keys():
		var conversation_id := String(conversation_id_value)
		var conversation := world.conversation_state.records[conversation_id] as Dictionary
		if String(conversation.get("status", "")) != "active":
			continue
		var participants := conversation.get("participants", []) as Array
		if participants.size() != 2:
			_end_conversation(
				world,
				traveler_relationship_state,
				conversation_id,
				"无法继续",
				"interrupted",
			)
			continue
		var left : Variant = world._person_state(String(participants[0]))
		var right : Variant = world._person_state(String(participants[1]))
		if (
			left.is_empty()
			or right.is_empty()
			or not PERCEPTION_RUNTIME._are_currently_perceived(
				world,
				String(participants[0]),
				left,
				String(participants[1]),
				right,
			)
		):
			_end_conversation(
				world,
				traveler_relationship_state,
				conversation_id,
				"一方离开",
				"interrupted",
			)


static func _advance_autonomous_conversation_timeouts(
	world,
	traveler_relationship_state: TownTravelerRelationshipState,
	real_seconds: float,
) -> void:
	if not is_finite(real_seconds) or real_seconds <= 0.0:
		return
	# 超时以 45 秒计，0.5 秒粒度足够；把逐帧全量遍历降为每半秒一次。
	world.conversation_state.autonomous_timeout_tick_seconds += real_seconds
	if world.conversation_state.autonomous_timeout_tick_seconds < 0.5:
		return
	real_seconds = world.conversation_state.autonomous_timeout_tick_seconds
	world.conversation_state.autonomous_timeout_tick_seconds = 0.0
	for conversation_id_value: Variant in world.conversation_state.records.keys():
		var conversation_id := String(conversation_id_value)
		var conversation := world.conversation_state.records[conversation_id] as Dictionary
		var waiting_for := str(conversation.get("waitingFor", ""))
		# 纯居民对话始终适用闲置兜底；含化身的对话只有在等待居民答话时
		# 适用——等待化身（玩家输入）不设超时，但 Provider 静默失败不能
		# 把对话永久卡在居民回合。
		var timeout_applies: bool = (
			_is_resident_only_conversation(world, conversation)
			or world.resident_registry.records.has(waiting_for)
		)
		if (
			String(conversation.get("status", "")) != "active"
			or not timeout_applies
		):
			world.conversation_state.autonomous_idle_seconds.erase(conversation_id)
			continue
		var idle_seconds := (
			float(
				world.conversation_state.autonomous_idle_seconds.get(
					conversation_id,
					0.0,
				)
			)
			+ real_seconds
		)
		world.conversation_state.autonomous_idle_seconds[conversation_id] = idle_seconds
		if idle_seconds < world.AUTONOMOUS_CONVERSATION_IDLE_TIMEOUT_SECONDS:
			continue
		# A resident conversation must release both residents even when a
		# Provider request never returns. Watching it is presentation-only and
		# cannot extend this World-owned deadline.
		_end_conversation(
			world,
			traveler_relationship_state,
			conversation_id,
			"无法继续",
			"interrupted",
		)


static func _activate_conversation_reply(
	world,
	traveler_relationship_state: TownTravelerRelationshipState,
	resident_id: String,
	resident: Dictionary,
	action: Dictionary,
	preview: Dictionary,
) -> void:
	var current_action := resident.get("currentAction", {}) as Dictionary
	if (
		not current_action.is_empty()
		and int(resident.get("actionSuspendedAbsoluteMinute", -1)) < 0
	):
		resident["actionSuspendedAbsoluteMinute"] = int(
			world._environment.get_absolute_minute(),
		)
	resident["conversationReplyAction"] = action.duplicate(true)
	if current_action.is_empty():
		resident["currentAction"] = action.duplicate(true)
	resident["doing"] = world.ACTION_PROJECTION_MODULE.default_doing(world, action)
	WORLD_LOG_COMMIT_RUNTIME.record_story_action_started(world,
		resident_id,
		action,
		preview.get("storyProvenance", {}) as Dictionary,
	)
	world._bump_world_revision()
	var resident_display_name : Variant = world.resident_display_name(resident_id)
	world._emit_resident_state_changed(resident_id)
	var presented_action: Dictionary = ACTION_PRESENTATION.public_action(world, action)
	presented_action["residentId"] = resident_id
	world.resident_action_started.emit(resident_display_name, presented_action)
	world.resident_action_phase_changed.emit(
		resident_id,
		ACTION_PRESENTATION._resident_action_phase_projection(world, resident),
	)
	world.CONVERSATION_COMMITMENT_SUBMISSION_RUNTIME.submit(world,
		resident_id,
		action,
		preview.get("conversationFollowUp", {}) as Dictionary,
		_active_conversation_for_person(world, resident_id),
	)
	_apply_conversation_reply(
		world,
		traveler_relationship_state,
		resident_id,
		action,
	)
	# 答话捷径(等待方直接激活)同样可能携带对话收尾后的结构化冲突意图,
	# 与 TownWorldRuntime 主路径的答话分支保持同一处理。
	var conflict_intent := preview.get("conflictIntent", {}) as Dictionary
	if not conflict_intent.is_empty():
		var conflict_result := CONVERSATION_CONFLICT_BRIDGE.activate_after_reply(
			world,
			resident_id,
			resident,
			conflict_intent,
			preview.get("decisionWakeSnapshot", {}) as Dictionary,
			preview.get("storyProvenance", {}) as Dictionary,
		) as Dictionary
		if conflict_result.get("ok") != true:
			resident["doing"] = "这场火气已经散了，先缓一缓"
			ACTION_RESULT_RUNTIME.queue(
				world,
				resident_id,
				String(conflict_intent.get("action_id", "")),
				"rejected",
				"对方已经走远，冲突没有继续",
				true,
				true,
			)


static func _validate_conversation_turn_action(world, resident_name: String, action: Dictionary, is_reply: bool) -> String:
	if typeof(action.get("say")) != TYPE_STRING or typeof(action.get("narration")) != TYPE_STRING:
		return "对话动作的 say 和 narration 必须是文本"
	if String(action.get("say", "")).strip_edges().is_empty() and String(action.get("narration", "")).strip_edges().is_empty():
		return "对话动作的 say 和 narration 至少一项不能为空"
	if typeof(action.get("photos")) != TYPE_ARRAY:
		return "对话动作的 photos 必须是数组"
	var available_photo_refs := _available_conversation_photo_refs(world, resident_name)
	for photo_value: Variant in action.get("photos", []) as Array:
		if typeof(photo_value) != TYPE_DICTIONARY:
			return "照片引用必须是对象"
		var photo := photo_value as Dictionary
		for key_value: Variant in photo:
			if not key_value is String or not ["ref", "mime_type"].has(key_value):
				return "照片引用包含未知字段：%s" % str(key_value)
		var photo_ref := String(photo.get("ref", "")).strip_edges() if photo.get("ref") is String else ""
		var mime_type := String(photo.get("mime_type", "")).strip_edges() if photo.get("mime_type") is String else ""
		if photo_ref.is_empty() or mime_type.is_empty():
			return "照片引用缺少 ref 或 mime_type"
		if not available_photo_refs.has(photo_ref):
			return "照片引用不在当前对话可用范围内：%s" % photo_ref
	if is_reply and typeof(action.get("end")) != TYPE_BOOL:
		return "答话动作的 end 必须是布尔值"
	if is_reply and bool(action.get("end", false)) and String(action.get("narration", "")).strip_edges().is_empty():
		return "主动结束对话时 narration 必须说明结束行为"
	if is_reply:
		var medical_error : Variant = world.CLINIC_INTERVIEW_RUNTIME.validate_response(world,
			resident_name,
			action,
		)
		if not medical_error.is_empty():
			return medical_error
	return ""


static func _available_conversation_photo_refs(world, resident_name: String) -> Dictionary:
	var refs := {}
	var conversation := _active_conversation_for_person(world, resident_name)
	for turn_value: Variant in conversation.get("turns", []) as Array:
		for photo_value: Variant in (turn_value as Dictionary).get("photos", []) as Array:
			if typeof(photo_value) == TYPE_DICTIONARY:
				refs[String((photo_value as Dictionary).get("ref", ""))] = true
	return refs


static func _begin_clinic_interview_conversation(
	world,
	clinician_resident_id: String,
	patient_resident_id: String,
	conversation_id: String,
	action: Dictionary,
) -> Dictionary:
	var request_id := String(
		action.get("medicalRequestId", ""),
	).strip_edges()
	var task_id := String(action.get("medicalTaskId", "")).strip_edges()
	if request_id.is_empty() or task_id.is_empty():
		return {}
	var expected : Variant = world.CLINIC_INTERVIEW_RUNTIME.binding_for_pair(world,
		clinician_resident_id,
		patient_resident_id,
	)
	if (
		String(expected.get("requestId", "")) != request_id
		or String(expected.get("taskId", "")) != task_id
	):
		return {}
	var task := world.work_domain.tasks.task(task_id) as Dictionary
	var occupation_id : Variant = world.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.id_for_activity(world,
		clinician_resident_id,
		"activity_clinic_receive_patient",
	)
	var claimed := world.work_domain.claim_specific_work_task(
		task,
		occupation_id,
		clinician_resident_id,
		world.residents(),
	) as Dictionary
	if claimed.get("ok") != true:
		return {}
	task = claimed.get("task", {}) as Dictionary
	var request := world.work_domain.services.request(request_id,) as Dictionary
	var request_context := request.get("context", {}) as Dictionary
	var interview := request_context.get(
		"medicalInterview",
		{},
	) as Dictionary
	var bound := world._clinic_interviews.bind_conversation(interview,
		conversation_id,
		clinician_resident_id,
		int(world._environment.call("get_absolute_minute")),) as Dictionary
	if bound.get("ok") != true:
		return {}
	var updated_interview := bound.get("context", {}) as Dictionary
	var merged := world.work_domain.services.merge_request_context(request_id,
		{"medicalInterview": updated_interview},) as Dictionary
	if merged.get("ok") != true:
		return {}
	var staged := world.work_domain.tasks.set_process_stage_from_world(task_id,
		int(task.get("revision", 0)),
		"interview_active",
		{
			"nextActivityId": "medical_interview",
			"serviceRequestId": request_id,
			"conversationId": conversation_id,
			"clinicianResidentId": clinician_resident_id,
			"patientResidentId": patient_resident_id,
		},) as Dictionary
	if staged.get("ok") != true:
		return {}
	world._bump_world_revision(false)
	return {
		"requestId": request_id,
		"taskId": task_id,
		"context": updated_interview.duplicate(true),
	}


static func _clinic_interview_for_conversation(
	world,
	conversation: Dictionary,
) -> Dictionary:
	var request_id := String(
		conversation.get("medicalRequestId", ""),
	).strip_edges()
	if request_id.is_empty():
		return {}
	var request := world.work_domain.services.request(request_id,) as Dictionary
	if String(request.get("kind", "")) != "clinic":
		return {}
	var interview := (
		(request.get("context", {}) as Dictionary).get(
			"medicalInterview",
			{},
		) as Dictionary
	)
	if (
		interview.is_empty()
		or String(interview.get("conversationId", ""))
		!= String(conversation.get("conversationId", ""))
	):
		return {}
	return {
		"request": request,
		"context": interview,
	}


static func _finish_clinic_interview_conversation(
	world,
	conversation: Dictionary,
	reason: String,
) -> void:
	var linked := _clinic_interview_for_conversation(world, conversation)
	if linked.is_empty():
		return
	var request := linked.get("request", {}) as Dictionary
	var interview := linked.get("context", {}) as Dictionary
	var finished := world._clinic_interviews.finish_conversation(interview,
		String(conversation.get("conversationId", "")),
		reason,
		int(world._environment.call("get_absolute_minute")),) as Dictionary
	if finished.get("ok") != true:
		return
	var updated := finished.get("context", {}) as Dictionary
	var request_id := String(request.get("requestId", ""))
	var merged := world.work_domain.services.merge_request_context(request_id,
		{"medicalInterview": updated},) as Dictionary
	if merged.get("ok") != true:
		return
	var task_id := String(conversation.get("medicalTaskId", ""))
	var task := world.work_domain.tasks.task(task_id) as Dictionary
	if task.is_empty():
		return
	var ready := world._clinic_interviews.activity_is_allowed(updated,) as bool
	var next_stage := (
		"ready_examination" if ready else "awaiting_interview"
	)
	var next_activity := (
		"activity_clinic_receive_patient"
		if ready
		else "medical_interview"
	)
	world.work_domain.tasks.set_process_stage_from_world(task_id,
		int(task.get("revision", 0)),
		next_stage,
		{
			"nextActivityId": next_activity,
			"serviceRequestId": request_id,
			"conversationId": String(
				conversation.get("conversationId", ""),
			),
			"interviewStatus": String(updated.get("status", "")),
			"patientResponseKind": String(
				updated.get("patientResponseKind", ""),
			),
		},)
	world._bump_world_revision(false)
