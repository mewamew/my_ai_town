class_name TownConversationCommitmentSubmissionRuntime
extends RefCounted


const CONVERSATION_RUNTIME := preload(
	"res://world/runtime/conversation/TownConversationRuntime.gd"
)


static func submit(
	host,
	resident_id: String,
	action: Dictionary,
	option: Dictionary,
	conversation: Dictionary,
) -> void:
	if option.is_empty() or conversation.is_empty() or String(action.get("type", "")) != "答话":
		return
	var conversation_id := String(conversation.get("conversationId", "")).strip_edges()
	if conversation_id != String(action.get("conversation_id", "")).strip_edges():
		return
	var beneficiary_ref := CONVERSATION_RUNTIME._other_conversation_participant(
		host,
		conversation,
		resident_id,
	)
	var beneficiary_id: String = host.person_id_for_name(beneficiary_ref)
	var capability_id := String(option.get("capability_id", "")).strip_edges()
	var target_refs := (option.get("target_refs", {}) as Dictionary).duplicate(true)
	var meaning := String(option.get("meaning", "")).strip_edges()
	var option_id := String(option.get("option_id", "")).strip_edges()
	if beneficiary_id.is_empty() or capability_id.is_empty() or target_refs.is_empty() or meaning.is_empty() or option_id.is_empty():
		return
	var commitment_id := "conversation-commitment:%s:%s" % [
		conversation_id,
		String(action.get("action_id", "")),
	]
	var now := int(host._environment.get_absolute_minute())
	var source_result: Dictionary = host.sync_conversation_commitment({
		"commitment_id": commitment_id,
		"source_revision": 1,
		"conversation_id": conversation_id,
		"promisor_id": resident_id,
		"beneficiary_id": beneficiary_id,
		"active": true,
		"reason_summary": meaning,
		"place_id": String(option.get("place_id", "")),
		"capability_id": capability_id,
		"target_refs": target_refs,
		"success_result_id": String(option.get("success_result_id", "")),
		"expires_at": now + 360,
		"source_event_ids": ["conversation-follow-up:%s:%s" % [
			conversation_id,
			String(action.get("action_id", "")),
		]],
	})
	if source_result.get("ok") != true:
		return
	var matter := host._social_matters.find_active_matter(
		"conversation_commitment",
		commitment_id,
		[resident_id, beneficiary_id],
	) as Dictionary
	if matter.is_empty():
		return
	var matter_id := String(matter.get("matter_id", ""))
	var candidate := host._social_sources.response_candidate(
		resident_id,
		0,
		host.SOCIAL_GOAL_MATCHING_RUNTIME.active_commitment_count(host, resident_id),
		now,
		matter_id,
	) as Dictionary
	if candidate.is_empty():
		return
	var round_result := host._social_matters.begin_response_round(
		matter_id,
		[candidate],
		now,
		now + 1,
	) as Dictionary
	if round_result.get("ok") != true:
		return
	matter = host._social_matters.get_matter(matter_id) as Dictionary
	var submitted := host._social_matters.submit_response(
		resident_id,
		{
			"response_id": "conversation-response:%s" % String(action.get("action_id", "")),
			"matter_id": matter_id,
			"matter_revision": int(matter.get("revision", 0)),
			"response_round_id": String(matter.get("response_round_id", "")),
			"option_id": "accept",
		},
		now,
	) as Dictionary
	if submitted.get("ok") != true:
		return
	var settled := host._social_matters.settle_response_round(
		matter_id,
		now,
		"close",
	) as Dictionary
	if settled.get("ok") != true:
		return
	host.SOCIAL_ASSIGNMENT_RECONCILIATION_RUNTIME.reconcile(host, matter_id)
	action["conversation_commitment_matter_id"] = matter_id
	action["conversation_commitment_option_id"] = option_id
	# 选择正式后续行动就是“结束交谈后马上去做”的明确决定。只有成功创建并
	# 指派事项后才自动结束，失败时仍保留原对话，让居民继续说明或重新决定。
	action["end"] = true
	host.SOCIAL_MATTER_COMMAND_RUNTIME.emit_summary(host, matter_id)
