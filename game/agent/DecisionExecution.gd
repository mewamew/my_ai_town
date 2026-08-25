class_name AgentDecisionExecution
extends RefCounted


const AgentContractScript := preload("res://agent/AgentContract.gd")

var _model_provider: Object
var _prompt_compiler: RefCounted

# 角色请求留档(狼人杀警察/卧底调试): configure_role_archive 装配后,
# 目标居民的每次模型请求会把编译出的提示词(messages)与最终决策 JSON
# 成对写入 <root>/<时间戳>_<居民id>_<决策id前段>.json。
var _role_archive_enabled := false
var _role_archive_ids: Array[String] = []
var _role_archive_root := ""
var _role_archive_prompts := {}


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


func configure_role_archive(
	enabled: bool,
	resident_ids: Array,
	root: String,
) -> void:
	_role_archive_enabled = enabled
	_role_archive_ids.clear()
	for resident_value: Variant in resident_ids:
		var candidate := String(resident_value).strip_edges()
		if not candidate.is_empty():
			_role_archive_ids.append(candidate)
	_role_archive_root = root.strip_edges()
	if not enabled:
		_role_archive_prompts.clear()


func request_decision(
	initialization: Dictionary,
	wake_packet: Dictionary,
	memory_prompt: String,
	used_action_ids: Dictionary,
	on_complete: Callable,
	retry_feedback: String = "",
) -> void:
	var probe_lap_usec := Time.get_ticks_usec() if _probe_active() else 0
	var request_id := String(wake_packet.get("decision_id", "")).strip_edges()
	var resident_id := String(
		(initialization.get("me", {}) as Dictionary).get("resident_id", ""),
	)
	var archive_target := (
		_role_archive_enabled
		and not resident_id.is_empty()
		and _role_archive_ids.has(resident_id)
	)
	var final_on_complete := on_complete
	if archive_target:
		var resident_name := String(
			(initialization.get("me", {}) as Dictionary).get("name", resident_id),
		)
		final_on_complete = _role_archive_wrapped_complete.bind(
			resident_id,
			resident_name,
			request_id,
			wake_packet.duplicate(true),
			on_complete,
		)
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
		final_on_complete.call({
			"ok": false,
			"errors": model_request.get("errors", ["模型输入组装失败"]),
		})
		return
	if archive_target and not request_id.is_empty():
		_role_archive_prompts[request_id] = (
			(model_request.get("messages", []) as Array).duplicate(true)
		)
	if not request_id.is_empty():
		# 这是 Provider 内部的请求关联号，不会进入供应商请求 body；
		# Gateway 取消旧决策时用它终止真实传输。
		model_request["_agent_request_id"] = request_id
	_model_provider.call(
		"request_decision",
		model_request,
		_validate_model_decision.bind(
			initialization.duplicate(true),
			wake_packet.duplicate(true),
			used_action_ids.duplicate(true),
			final_on_complete,
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


## 目标居民的回调包装: 拿到结果后先落盘(提示词 + 输出 JSON), 再透传原回调。
func _role_archive_wrapped_complete(
	payload: Dictionary,
	resident_id: String,
	resident_name: String,
	request_id: String,
	wake_packet: Dictionary,
	on_complete: Callable,
) -> void:
	# 无提示词缓存(如编译失败路径)时只透传, 不写半条记录。
	if _role_archive_prompts.has(request_id):
		_persist_role_archive(
			resident_id,
			resident_name,
			request_id,
			wake_packet,
			payload,
		)
		_role_archive_prompts.erase(request_id)
	on_complete.call(payload)


## 写角色请求留档: user://logs/requests/role 之外的固定目录(由装配方注入),
## 每条 = 提示词全量(messages) + 居民最终决策 JSON(或错误)。
func _persist_role_archive(
	resident_id: String,
	resident_name: String,
	request_id: String,
	wake_packet: Dictionary,
	payload: Dictionary,
) -> void:
	if _role_archive_root.is_empty():
		return
	var root := ProjectSettings.globalize_path(_role_archive_root)
	DirAccess.make_dir_recursive_absolute(root)
	var game_time := ""
	var snapshot := wake_packet.get("snapshot", {}) as Dictionary
	if snapshot.has("clock"):
		game_time = JSON.stringify(snapshot.get("clock"))
	var now := Time.get_unix_time_from_system()
	var dt := Time.get_datetime_dict_from_unix_time(now)
	var stamp := "%04d%02d%02d-%02d%02d%02d" % [
		dt.year,
		dt.month,
		dt.day,
		dt.hour,
		dt.minute,
		dt.second,
	]
	var archive := {
		"schema": "agent-decision-role-archive",
		"resident_id": resident_id,
		"resident_name": resident_name,
		"request_id": request_id,
		"recorded_at": stamp,
		"game_time": game_time,
		"ok": bool(payload.get("ok", false)),
		"messages": _role_archive_prompts.get(request_id, []),
	}
	if payload.has("decision"):
		archive["decision"] = payload.get("decision")
	if payload.has("errors"):
		archive["errors"] = payload.get("errors")
	var file_path := "%s/%s_%s_%s.json" % [
		root,
		stamp,
		resident_id,
		String(request_id).left(8),
	]
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(archive, "  "))
	file.close()
