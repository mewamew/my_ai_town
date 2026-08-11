class_name AgentDecisionExecution
extends RefCounted


const AgentContractScript := preload("res://agent/AgentContract.gd")

var _model_provider: Object
var _prompt_compiler: RefCounted


func _init(model_provider: Object, prompt_compiler: RefCounted) -> void:
	_model_provider = model_provider
	_prompt_compiler = prompt_compiler


func replace_model_provider(model_provider: Object) -> Dictionary:
	if model_provider == null or not model_provider.has_method("request_decision"):
		return {"ok": false, "errors": ["model_provider 必须实现 request_decision"]}
	_model_provider = model_provider
	return {"ok": true}


# C4 排查计时(AI_TOWN_UI_FRAME_PROBE=1 门控):与 AgentResidentRuntime 的
# AGENT_PROBE 行同格式,按 decision_id 汇总提示编译与请求发起两段。
static var _probe_checked := false
static var _probe_enabled := false


static func _probe_active() -> bool:
	if not _probe_checked:
		_probe_checked = true
		_probe_enabled = OS.get_environment("AI_TOWN_UI_FRAME_PROBE") == "1"
	return _probe_enabled


func request_decision(
	initialization: Dictionary,
	wake_packet: Dictionary,
	memory_prompt: String,
	used_action_ids: Dictionary,
	on_complete: Callable,
	retry_feedback: String = "",
) -> void:
	var probe_lap_usec := Time.get_ticks_usec() if _probe_active() else 0
	var model_request: Dictionary = _prompt_compiler.call(
		"compile",
		wake_packet,
		memory_prompt,
		retry_feedback,
	)
	if _probe_active():
		var now_usec := Time.get_ticks_usec()
		print("AGENT_PROBE decision=%s stage=prompt_compile usec=%d frame=%d" % [
			String(wake_packet.get("decision_id", "")),
			now_usec - probe_lap_usec,
			Engine.get_process_frames(),
		])
		probe_lap_usec = now_usec
	if model_request.get("ok") == false:
		on_complete.call({
			"ok": false,
			"errors": model_request.get("errors", ["模型输入组装失败"]),
		})
		return
	_model_provider.call(
		"request_decision",
		model_request,
		_validate_model_decision.bind(
			initialization.duplicate(true),
			wake_packet.duplicate(true),
			used_action_ids.duplicate(true),
			on_complete,
		),
	)
	if _probe_active():
		print("AGENT_PROBE decision=%s stage=provider_dispatch usec=%d frame=%d" % [
			String(wake_packet.get("decision_id", "")),
			Time.get_ticks_usec() - probe_lap_usec,
			Engine.get_process_frames(),
		])


func _validate_model_decision(
	provider_result: Variant,
	initialization: Dictionary,
	wake_packet: Dictionary,
	used_action_ids: Dictionary,
	on_complete: Callable,
) -> void:
	var probe_started_usec := Time.get_ticks_usec() if _probe_active() else 0
	var model_decision: Variant = provider_result
	if typeof(provider_result) == TYPE_DICTIONARY and (provider_result as Dictionary).has("ok"):
		var result := provider_result as Dictionary
		if result.get("ok") != true:
			on_complete.call({
				"ok": false,
				"errors": ["模型调用失败"],
			})
			return
		model_decision = result.get("decision")
	if typeof(model_decision) != TYPE_DICTIONARY:
		on_complete.call({"ok": false, "errors": ["决定必须是对象"]})
		return
	var raw_decision := model_decision as Dictionary
	var action_decision := AgentContractScript.normalize_model_decision_references(
		raw_decision,
		wake_packet,
	)
	action_decision.erase("social_response")
	action_decision.erase("social_attention")
	action_decision.erase("social_request")
	action_decision.erase("conversation_follow_up")
	var stale_reply_discarded := _repair_stale_reply_to_continue_current(
		action_decision,
		wake_packet,
	)
	var action_id_repaired := _repair_opaque_action_id_collision(
		action_decision,
		wake_packet,
		used_action_ids,
	)
	var errors: Array[String] = AgentContractScript.validate_decision(
		action_decision,
		initialization,
		wake_packet,
		used_action_ids,
	)
	if not errors.is_empty():
		on_complete.call({"ok": false, "errors": errors})
		return
	var canonical_decision := AgentContractScript.canonicalize_decision(
		action_decision,
	)
	var social_response_errors: Array[String] = []
	if (
		raw_decision.has("social_response")
		and not AgentContractScript.wake_requires_reply(wake_packet)
	):
		social_response_errors = (
			AgentContractScript.validate_social_response(
				raw_decision.get("social_response"),
				wake_packet,
			)
		)
		if social_response_errors.is_empty():
			canonical_decision["social_response"] = (
				AgentContractScript.canonicalize_social_response(
					raw_decision.get("social_response") as Dictionary,
				)
			)
	var social_attention_errors: Array[String] = []
	if (
		raw_decision.has("social_attention")
		and not AgentContractScript.wake_requires_reply(wake_packet)
	):
		social_attention_errors = (
			AgentContractScript.validate_social_attention(
				raw_decision.get("social_attention"),
				wake_packet,
			)
		)
		if social_attention_errors.is_empty():
			canonical_decision["social_attention"] = (
				AgentContractScript.canonicalize_social_attention(
					raw_decision.get("social_attention") as Dictionary,
				)
			)
	var social_request_errors: Array[String] = []
	if (
		raw_decision.has("social_request")
		and not AgentContractScript.wake_requires_reply(wake_packet)
	):
		social_request_errors = (
			AgentContractScript.validate_social_request(
				raw_decision.get("social_request"),
				initialization,
				wake_packet,
				canonical_decision.get("action", {}) as Dictionary,
			)
		)
		if social_request_errors.is_empty():
				canonical_decision["social_request"] = (
					AgentContractScript.canonicalize_social_request(
						raw_decision.get("social_request") as Dictionary,
					)
				)
	var conversation_follow_up_errors: Array[String] = []
	if raw_decision.has("conversation_follow_up"):
		conversation_follow_up_errors = (
			AgentContractScript.validate_conversation_follow_up(
				raw_decision.get("conversation_follow_up"),
				wake_packet,
				canonical_decision.get("action", {}) as Dictionary,
			)
		)
		if conversation_follow_up_errors.is_empty():
			canonical_decision["conversation_follow_up"] = (
				AgentContractScript.canonicalize_conversation_follow_up(
					raw_decision.get("conversation_follow_up") as Dictionary,
				)
			)
	var conversation_follow_up_speech_errors := (
		AgentContractScript.validate_conversation_follow_up_speech(
			canonical_decision.get("action", {}) as Dictionary,
			canonical_decision.has("conversation_follow_up"),
		)
	)
	# A conversation follow-up is optional. If its World option is missing or
	# invalid, keep the legal reply and drop only the unconfirmed attachment;
	# otherwise a malformed social promise would block ordinary life.
	if (
		canonical_decision.has("conversation_follow_up")
		and not conversation_follow_up_speech_errors.is_empty()
	):
		conversation_follow_up_errors.append_array(
			conversation_follow_up_speech_errors,
		)
		canonical_decision.erase("conversation_follow_up")
		conversation_follow_up_speech_errors = (
			AgentContractScript.validate_conversation_follow_up_speech(
				canonical_decision.get("action", {}) as Dictionary,
				false,
			)
		)
	if not conversation_follow_up_speech_errors.is_empty():
		if (
			String(
				(canonical_decision.get("action", {}) as Dictionary).get(
					"type",
					"",
				)
			) == "答话"
			and not canonical_decision.has("conversation_follow_up")
		):
			conversation_follow_up_speech_errors.clear()
		else:
			on_complete.call({
				"ok": false,
				"errors": conversation_follow_up_speech_errors,
			})
			return
	if _probe_active():
		print("AGENT_PROBE decision=%s stage=decision_validate usec=%d frame=%d" % [
			String(wake_packet.get("decision_id", "")),
			Time.get_ticks_usec() - probe_started_usec,
			Engine.get_process_frames(),
		])
		probe_started_usec = Time.get_ticks_usec()
	on_complete.call({
		"ok": true,
		"decision": canonical_decision,
		"actionIdRepaired": action_id_repaired,
		"staleConversationReplyDiscarded": stale_reply_discarded,
		"socialResponseErrors": social_response_errors,
		"socialAttentionErrors": social_attention_errors,
		"socialRequestErrors": social_request_errors,
		"conversationFollowUpErrors": conversation_follow_up_errors,
	})
	if _probe_active():
		print("AGENT_PROBE decision=%s stage=decision_complete_callback usec=%d frame=%d" % [
			String(wake_packet.get("decision_id", "")),
			Time.get_ticks_usec() - probe_started_usec,
			Engine.get_process_frames(),
		])


func _repair_stale_reply_to_continue_current(
	decision: Dictionary,
	wake_packet: Dictionary,
) -> bool:
	if (
		String(decision.get("handling", "")) != "replace_current"
		or not decision.get("action") is Dictionary
		or String(
			(decision.get("action") as Dictionary).get("type", "")
		) != "答话"
		or AgentContractScript.wake_allows_reply(wake_packet)
		or AgentContractScript.current_action_id(wake_packet).is_empty()
	):
		return false
	# A delayed model reply must never reopen or extend a conversation whose
	# matching turn is absent from this wake. When a confirmed World action is
	# still running, safely preserve it instead of rejecting the whole request
	# and replacing the resident with an invented continuity wait.
	decision["handling"] = "continue_current"
	decision.erase("action")
	return true


func _repair_opaque_action_id_collision(
	decision: Dictionary,
	wake_packet: Dictionary,
	used_action_ids: Dictionary,
) -> bool:
	if (
		String(decision.get("handling", "")) != "replace_current"
		or not decision.get("action") is Dictionary
	):
		return false
	var action := decision.get("action") as Dictionary
	var action_id := String(action.get("action_id", "")).strip_edges()
	if action_id.is_empty():
		return false
	var current_action_id := AgentContractScript.current_action_id(
		wake_packet,
	)
	if (
		not used_action_ids.has(action_id)
		and action_id != current_action_id
	):
		return false
	var decision_id := String(
		wake_packet.get("decision_id", ""),
	).strip_edges()
	if decision_id.is_empty():
		return false
	var action_type := String(action.get("type", "动作")).strip_edges()
	if action_type.is_empty():
		action_type = "动作"
	var candidate := "%s-%s" % [decision_id, action_type]
	var suffix := 2
	while (
		used_action_ids.has(candidate)
		or candidate == current_action_id
	):
		candidate = "%s-%s-%d" % [
			decision_id,
			action_type,
			suffix,
		]
		suffix += 1
	action["action_id"] = candidate
	decision["action"] = action
	return true
