class_name AgentResidentRuntime
extends RefCounted


const AgentContractScript := preload("res://agent/AgentContract.gd")
const DecisionExecutionScript := preload("res://agent/DecisionExecution.gd")
const PromptCompilerScript := preload("res://agent/prompt/AgentPromptCompiler.gd")
const ResidentMemorySystemScript := preload("res://agent/memory/ResidentMemorySystem.gd")
const ResidentAvatarMemoryModuleScript := preload(
	"res://agent/avatar_memory/ResidentAvatarMemoryModule.gd"
)
const PERSISTENT_STATE_VERSION := 6
const LEGACY_PERSISTENT_STATE_VERSION := 5
const DEFAULT_AVATAR_PERSON_ID := "person_7f3a91c2d8e4"
const DEFAULT_AVATAR_NAME := "旅行者"

var _initialization: Dictionary
var _decision_execution: DecisionExecutionScript
var _session_epoch: AgentSessionEpoch
var _current_decision_id := ""
var _current_request_has_result := false
var _used_action_ids: Dictionary = {}
var _memory_system: ResidentMemorySystemScript
var _avatar_memory_module: ResidentAvatarMemoryModuleScript
var _initialization_errors: Array[String] = []
var _pending_request_count := 0
var _on_retired_drained := Callable()
var _persistent_state_applied := false
var _model_provider: Object
var _departure_message_proposals: Dictionary = {}


func _init(
	initialization: Dictionary,
	model_provider: Object,
	memory_root: String,
	photo_content_resolver: Object = null,
	avatar_person_id: String = DEFAULT_AVATAR_PERSON_ID,
	avatar_name: String = DEFAULT_AVATAR_NAME,
) -> void:
	# 入口做一次拷贝形成运行时私有快照（外部调用方之后的改动不得影响居民，
	# 见 agent_world_wake_test 的所有权契约）；内部各组件共享这份私有快照，
	# 不再各自深拷贝。
	_initialization = initialization.duplicate(true)
	_model_provider = model_provider
	_memory_system = ResidentMemorySystemScript.new(
		_initialization,
		memory_root,
		photo_content_resolver,
	)
	_avatar_memory_module = ResidentAvatarMemoryModuleScript.new(
		_initialization,
		memory_root,
		avatar_person_id,
		avatar_name,
	)
	var prompt_compiler := PromptCompilerScript.new(
		_initialization,
		"res://prompts",
		photo_content_resolver,
	)
	_initialization_errors = prompt_compiler.get_load_errors()
	_decision_execution = DecisionExecutionScript.new(model_provider, prompt_compiler)


func get_initialization_errors() -> Array[String]:
	return _initialization_errors.duplicate()


func attach_session_epoch(session_epoch: AgentSessionEpoch) -> void:
	_session_epoch = session_epoch


func replace_model_provider(model_provider: Object) -> Dictionary:
	if model_provider == null or not model_provider.has_method("request_decision"):
		return {"ok": false, "errors": ["model_provider 必须实现 request_decision"]}
	var replaced := _decision_execution.replace_model_provider(model_provider)
	if not bool(replaced.get("ok", false)):
		return replaced
	_model_provider = model_provider
	return {"ok": true}


func capture_persistent_state() -> Dictionary:
	var resident_id := String(_initialization["me"]["resident_id"])
	var resident_name := String(_initialization["me"]["attributes"]["name"])
	var memory_capture: Dictionary = _memory_system.capture_persistent_state()
	if not bool(memory_capture.get("ok", false)):
		return memory_capture
	var avatar_capture: Dictionary = _avatar_memory_module.capture_persistent_state(
	)
	if not bool(avatar_capture.get("ok", false)):
		return avatar_capture
	var memory_state := memory_capture["memory_state"] as Dictionary
	var used_action_ids := (memory_state["known_action_ids"] as Array).duplicate()
	return {
		"ok": true,
		"resident_id": resident_id,
		"resident_name": resident_name,
		"resident_state": {
			"runtime_state_version": PERSISTENT_STATE_VERSION,
			"initialization": _initialization.duplicate(true),
			"used_action_ids": used_action_ids,
			"memory_system": memory_state,
			"avatar_memory_module": (
				avatar_capture["avatar_memory_state"] as Dictionary
			).duplicate(true),
		},
	}


func apply_persistent_state(resident_state: Variant) -> Dictionary:
	if _persistent_state_applied:
		return {"ok": false, "errors": ["居民持久状态只能应用一次"]}
	if typeof(resident_state) != TYPE_DICTIONARY:
		return {"ok": false, "errors": ["居民持久状态必须是对象"]}
	var state := resident_state as Dictionary
	var state_version := int(state.get("runtime_state_version", -1))
	var legacy_state := state_version == LEGACY_PERSISTENT_STATE_VERSION
	var legacy_fields := [
		"runtime_state_version",
		"initialization",
		"used_action_ids",
		"memory_system",
	]
	var current_fields := legacy_fields.duplicate()
	current_fields.append("avatar_memory_module")
	if (
		legacy_state
		and not _has_exact_state_fields(state, legacy_fields)
	):
		return {"ok": false, "errors": ["居民持久状态字段不完整"]}
	if (
		not legacy_state
		and (
			state_version != PERSISTENT_STATE_VERSION
			or not _has_exact_state_fields(state, current_fields)
		)
	):
		return {"ok": false, "errors": ["居民运行时状态版本不受支持"]}
	var saved_initialization: Variant = state.get("initialization")
	var initialization_errors := AgentContractScript.validate_initialization(saved_initialization)
	if not initialization_errors.is_empty():
		return {"ok": false, "errors": initialization_errors}
	var saved_id := String((saved_initialization as Dictionary)["me"]["resident_id"])
	var current_id := String(_initialization["me"]["resident_id"])
	if saved_id != current_id:
		return {"ok": false, "errors": ["居民初始化资料身份与保存点不一致"]}
	if typeof(state.get("used_action_ids")) != TYPE_ARRAY:
		return {"ok": false, "errors": ["居民 used_action_ids 损坏"]}
	var restored_action_ids := {}
	for value: Variant in state["used_action_ids"]:
		if typeof(value) != TYPE_STRING or String(value).is_empty():
			return {"ok": false, "errors": ["居民 used_action_ids 包含无效动作编号"]}
		if restored_action_ids.has(value):
			return {"ok": false, "errors": ["居民 used_action_ids 包含重复动作编号"]}
		restored_action_ids[value] = true
	if not state.has("memory_system"):
		return {"ok": false, "errors": ["居民记忆持久状态缺失"]}
	var memory_state: Variant = state["memory_system"]
	if typeof(memory_state) != TYPE_DICTIONARY:
		return {"ok": false, "errors": ["居民记忆持久状态必须是对象"]}
	var memory_action_id_value: Variant = (memory_state as Dictionary).get("known_action_ids")
	if typeof(memory_action_id_value) != TYPE_ARRAY:
		return {"ok": false, "errors": ["居民记忆动作编号索引损坏"]}
	var runtime_action_id_list: Array = restored_action_ids.keys()
	var memory_action_id_list: Array[String] = []
	var memory_action_id_set := {}
	for value: Variant in memory_action_id_value as Array:
		if typeof(value) != TYPE_STRING or String(value).is_empty():
			return {"ok": false, "errors": ["居民记忆动作编号索引损坏"]}
		var action_id := String(value)
		if memory_action_id_set.has(action_id):
			return {"ok": false, "errors": ["居民记忆动作编号索引包含重复项"]}
		memory_action_id_set[action_id] = true
		memory_action_id_list.append(action_id)
	runtime_action_id_list.sort()
	memory_action_id_list.sort()
	if runtime_action_id_list != memory_action_id_list:
		return {"ok": false, "errors": ["居民运行时动作编号与记忆索引不一致"]}
	var memory_apply: Dictionary = _memory_system.apply_persistent_state(
		memory_state,
	)
	if not bool(memory_apply.get("ok", false)):
		return memory_apply
	var memory_action_ids := memory_apply.get("used_action_ids", {}) as Dictionary
	var applied_action_id_list: Array = memory_action_ids.keys()
	applied_action_id_list.sort()
	if runtime_action_id_list != applied_action_id_list:
		return {"ok": false, "errors": ["居民运行时动作编号与记忆索引不一致"]}
	var avatar_state: Variant = (
		_avatar_memory_module.empty_persistent_state()
		if legacy_state
		else state.get("avatar_memory_module")
	)
	if typeof(avatar_state) != TYPE_DICTIONARY:
		return {"ok": false, "errors": ["居民化身记忆持久状态缺失"]}
	var avatar_apply: Dictionary = _avatar_memory_module.apply_persistent_state(
		avatar_state,
	)
	if not bool(avatar_apply.get("ok", false)):
		return avatar_apply
	_used_action_ids = restored_action_ids
	_persistent_state_applied = true
	return {"ok": true}


func mark_new_game_state_ready() -> void:
	# 新游戏居民的空状态已经在提交存档前完整捕获，不会再走读档应用流程。
	# 明确标记后，记忆页面才能在第一次读档前安全地编辑、删除或写入记忆。
	_persistent_state_applied = true


# C4 排查计时(docs/居民状态通知链减负方案.md,AI_TOWN_UI_FRAME_PROBE=1 门控):
# 决策链分段耗时按 decision_id 串联跨帧输出;异步整理段单独报告,不计入
# 同步子项;同步子项之和与 gateway 外层 agentDispatchUsec 按帧对齐。
static var _decision_probe_checked := false
static var _decision_probe_enabled := false


static func _decision_probe_active() -> bool:
	if not _decision_probe_checked:
		_decision_probe_checked = true
		_decision_probe_enabled = (
			OS.get_environment("AI_TOWN_UI_FRAME_PROBE") == "1"
		)
	return _decision_probe_enabled


static func _decision_probe(decision_id: String, stage: String, usec: int) -> void:
	print("AGENT_PROBE decision=%s stage=%s usec=%d frame=%d" % [
		decision_id,
		stage,
		usec,
		Engine.get_process_frames(),
	])


func request_decision(
	wake_packet: Variant,
	on_complete: Callable,
	retry_feedback: String = "",
) -> Dictionary:
	var errors: Array[String] = AgentContractScript.validate_wake_packet(wake_packet)
	if not on_complete.is_valid():
		errors.append("on_complete 必须是有效回调")
	if not errors.is_empty():
		return {"ok": false, "errors": errors}

	var wake_data := wake_packet as Dictionary
	var probe_prep_started_usec := (
		Time.get_ticks_usec() if _decision_probe_active() else 0
	)
	var memory_preparation: Dictionary = _memory_system.prepare_context(wake_data)
	if memory_preparation.get("ok") != true:
		return {"ok": false, "errors": memory_preparation.get("errors", ["记忆更新失败"])}
	var avatar_preparation: Dictionary = _avatar_memory_module.prepare_context(
		wake_data,
	)
	if avatar_preparation.get("ok") != true:
		return {
			"ok": false,
			"errors": avatar_preparation.get(
				"errors",
				["化身记忆更新失败"],
			),
		}
	_used_action_ids = (memory_preparation.get("used_action_ids", {}) as Dictionary).duplicate()
	var request_decision_id := String(wake_data["decision_id"])
	if _decision_probe_active():
		_decision_probe(
			request_decision_id,
			"memory_prep",
			Time.get_ticks_usec() - probe_prep_started_usec,
		)
	var captured_epoch := 0
	if _session_epoch != null:
		captured_epoch = int(_session_epoch.capture())
	_current_decision_id = request_decision_id
	_current_request_has_result = false
	_pending_request_count += 1
	var completion_state := {
		"completed": false,
		"avatar_preparation": avatar_preparation.duplicate(true),
		"decision_retry_feedback": retry_feedback.strip_edges(),
	}
	if memory_preparation.has("organization_request"):
		if _decision_probe_active():
			completion_state["probeOrganizationStartedUsec"] = Time.get_ticks_usec()
		_request_json(
			memory_preparation["organization_request"],
			_on_organization_result.bind(
				memory_preparation["organization_token"],
				request_decision_id,
				wake_data.duplicate(true),
				captured_epoch,
				completion_state,
				on_complete,
				0,
			),
		)
	else:
		_continue_with_avatar_organization(
			wake_data,
			request_decision_id,
			captured_epoch,
			completion_state,
			on_complete,
		)
	return {"ok": true, "decision_id": request_decision_id}


func get_memory_debug_snapshot() -> Dictionary:
	return _memory_system.get_debug_snapshot()


func get_debug_snapshot() -> Dictionary:
	var provider: Dictionary = {}
	if _model_provider != null and _model_provider.has_method("get_debug_snapshot"):
		provider = _model_provider.call("get_debug_snapshot") as Dictionary
	return {
		"initialization": _initialization.duplicate(true),
		"memory": get_memory_debug_snapshot(),
		"avatar_memory": get_avatar_memory_debug_snapshot(),
		"provider": provider.duplicate(true),
		"pending_request_count": _pending_request_count,
		"current_decision_id": _current_decision_id,
	}


func get_avatar_memory_debug_snapshot() -> Dictionary:
	return _avatar_memory_module.get_debug_snapshot()


func has_avatar_departure_context() -> Dictionary:
	return _avatar_memory_module.has_departure_context()


func request_departure_message(
	departure_id: String,
	on_complete: Callable,
) -> Dictionary:
	if not on_complete.is_valid():
		return {"ok": false, "errors": ["退出留言回调无效"]}
	var organization := _avatar_memory_module.prepare_departure_organization(
	) as Dictionary
	if not bool(organization.get("ok", false)):
		return organization
	if not bool(organization.get("triggered", false)):
		return _begin_departure_message_request(
			departure_id,
			on_complete,
			false,
			0,
			{},
		)
	var captured_epoch := 0
	if _session_epoch != null:
		captured_epoch = int(_session_epoch.capture())
	_pending_request_count += 1
	var completion_state := {"completed": false}
	_request_json(
		organization["request"],
		_on_departure_organization_result.bind(
			organization["token"],
			departure_id,
			captured_epoch,
			completion_state,
			on_complete,
			0,
		),
	)
	return {"ok": true, "started": true, "completed": false}


func _begin_departure_message_request(
	departure_id: String,
	on_complete: Callable,
	request_already_pending: bool,
	captured_epoch: int,
	completion_state: Dictionary,
) -> Dictionary:
	var prepared := _avatar_memory_module.build_departure_message_request(
		departure_id,
	) as Dictionary
	if not bool(prepared.get("ok", false)):
		if request_already_pending:
			_finish_request(completion_state)
			on_complete.call({
				"ok": true,
				"wrote": false,
				"model_failure": true,
				"errors": prepared.get("errors", []),
			})
			return {"ok": true, "started": false, "completed": true}
		return prepared
	if bool(prepared.get("already_completed", false)):
		if request_already_pending:
			_finish_request(completion_state)
		on_complete.call({
			"ok": true,
			"wrote": true,
			"message": prepared.get("message", {}).duplicate(true),
		})
		return {"ok": true, "started": false, "completed": true}
	if not bool(prepared.get("eligible", false)):
		if request_already_pending:
			_finish_request(completion_state)
		on_complete.call({"ok": true, "wrote": false})
		return {"ok": true, "started": false, "completed": true}
	if not request_already_pending:
		if _session_epoch != null:
			captured_epoch = int(_session_epoch.capture())
		_pending_request_count += 1
		completion_state = {"completed": false}
	_request_json(
		prepared["request"],
		_on_departure_message_result.bind(
			prepared["token"],
			captured_epoch,
			completion_state,
			on_complete,
		),
	)
	return {"ok": true, "started": true, "completed": false}


func commit_departure_message(departure_id: String) -> Dictionary:
	var normalized_id := departure_id.strip_edges()
	if normalized_id.is_empty():
		return {"ok": false, "errors": ["退出留言提交标识无效"]}
	if not _departure_message_proposals.has(normalized_id):
		var prepared := _avatar_memory_module.build_departure_message_request(
			normalized_id,
		) as Dictionary
		if (
			bool(prepared.get("ok", false))
			and bool(prepared.get("already_completed", false))
		):
			return {
				"ok": true,
				"wrote": true,
				"message": prepared.get("message", {}).duplicate(true),
			}
		return {"ok": false, "errors": ["退出留言提案不存在"]}
	var proposal := (
		_departure_message_proposals[normalized_id] as Dictionary
	).duplicate(true)
	var committed := _avatar_memory_module.commit_departure_message(
		proposal,
	) as Dictionary
	if bool(committed.get("ok", false)):
		_departure_message_proposals.erase(normalized_id)
	return committed


func discard_departure_message_proposal(departure_id: String) -> Dictionary:
	var normalized_id := departure_id.strip_edges()
	if normalized_id.is_empty():
		return {"ok": false, "errors": ["退出留言丢弃标识无效"]}
	if not _departure_message_proposals.has(normalized_id):
		return {"ok": true, "changed": false}
	var proposal := (
		_departure_message_proposals[normalized_id] as Dictionary
	).duplicate(true)
	var screened := _avatar_memory_module.mark_departure_context_screened(
		proposal.get("token"),
	) as Dictionary
	if not bool(screened.get("ok", false)):
		return screened
	_departure_message_proposals.erase(normalized_id)
	return {"ok": true, "changed": true, "screened": true}


func get_read_only_memory() -> Dictionary:
	return _memory_system.get_read_only_memory()


func find_expressed_memory_claim(spoken_text: String) -> Dictionary:
	return _memory_system.call("find_expressed_memory_claim", spoken_text)


func apply_memory_intervention(request: Variant) -> Dictionary:
	if not _persistent_state_applied:
		return {"ok": false, "errors": ["居民记忆状态尚未恢复完成"]}
	return _memory_system.call("apply_memory_intervention", request) as Dictionary


func seed_debug_memory(memory: Variant) -> Dictionary:
	if _persistent_state_applied or _pending_request_count > 0 or not _used_action_ids.is_empty():
		return {"ok": false, "errors": ["居民运行开始后不能再写入记忆样例"]}
	return _memory_system.seed_debug_memory(memory)


func request_json(model_request: Dictionary, on_complete: Callable) -> Dictionary:
	if not on_complete.is_valid():
		return {"ok": false, "errors": ["模型结构化请求回调无效"]}
	var messages: Variant = model_request.get("messages")
	if typeof(messages) != TYPE_ARRAY or (messages as Array).is_empty():
		return {"ok": false, "errors": ["模型结构化请求必须包含非空 messages"]}
	if _model_provider == null:
		return {"ok": false, "errors": ["居民模型提供方不可用"]}
	_request_json(model_request.duplicate(true), on_complete)
	return {"ok": true, "started": true}


func _request_json(model_request: Dictionary, on_complete: Callable) -> void:
	if _model_provider.has_method("request_json"):
		_model_provider.call("request_json", model_request, on_complete)
		return
	_model_provider.call(
		"request_decision",
		model_request,
		_forward_legacy_json_result.bind(on_complete),
	)


func _forward_legacy_json_result(result: Variant, on_complete: Callable) -> void:
	if typeof(result) != TYPE_DICTIONARY:
		on_complete.call({"ok": false, "errors": ["模型结构化结果不是对象"]})
		return
	var packet := result as Dictionary
	if packet.has("ok"):
		if packet.get("ok") != true:
			on_complete.call(packet.duplicate(true))
			return
		if typeof(packet.get("decision")) == TYPE_DICTIONARY:
			on_complete.call({
				"ok": true,
				"json": (packet["decision"] as Dictionary).duplicate(true),
			})
			return
	on_complete.call({"ok": true, "json": packet.duplicate(true)})


func _on_organization_result(
	result: Dictionary,
	organization_token: Dictionary,
	request_decision_id: String,
	wake_packet: Dictionary,
	captured_epoch: int,
	completion_state: Dictionary,
	on_complete: Callable,
	retry_attempt: int,
) -> void:
	if bool(completion_state.get("completed", false)):
		return
	var attempt_key := "organization_attempt_%d_completed" % retry_attempt
	if bool(completion_state.get(attempt_key, false)):
		return
	completion_state[attempt_key] = true
	if completion_state.has("probeOrganizationStartedUsec"):
		_decision_probe(
			request_decision_id,
			"memory_organization_span",
			Time.get_ticks_usec()
			- int(completion_state["probeOrganizationStartedUsec"]),
		)
		completion_state.erase("probeOrganizationStartedUsec")
	if not _request_is_current(request_decision_id, captured_epoch):
		_finish_without_callback(completion_state)
		on_complete.call({
			"ok": false,
			"stale": true,
			"decision_id": request_decision_id,
		})
		return
	var organization_acceptance := {"ok": true}
	if bool(result.get("ok", false)) and typeof(result.get("json")) == TYPE_DICTIONARY:
		organization_acceptance = _memory_system.accept_organization(
			organization_token,
			(result["json"] as Dictionary).duplicate(true),
		)
		if (
			organization_acceptance.has("retry_request")
			and retry_attempt == 0
		):
			_request_json(
				organization_acceptance["retry_request"],
				_on_organization_result.bind(
					organization_token,
					request_decision_id,
					wake_packet,
					captured_epoch,
					completion_state,
					on_complete,
					1,
				),
			)
			return
	else:
		organization_acceptance = _memory_system.record_organization_failure(
			result.get("errors", ["居民记忆整理模型调用失败"]),
		)
	_continue_after_organization(
		organization_acceptance,
		request_decision_id,
		wake_packet,
		captured_epoch,
		completion_state,
		on_complete,
	)


func _continue_after_organization(
	organization_acceptance: Dictionary,
	request_decision_id: String,
	wake_packet: Dictionary,
	captured_epoch: int,
	completion_state: Dictionary,
	on_complete: Callable,
) -> void:
	if (
		not bool(organization_acceptance.get("ok", false))
		and not bool(organization_acceptance.get("safe_to_continue", false))
	):
		_finish_request(completion_state)
		_current_request_has_result = true
		on_complete.call({
			"ok": false,
			"errors": organization_acceptance.get("errors", ["居民记忆整理提交失败"]),
		})
		return
	_continue_with_avatar_organization(
		wake_packet,
		request_decision_id,
		captured_epoch,
		completion_state,
		on_complete,
	)


func _continue_with_avatar_organization(
	wake_packet: Dictionary,
	request_decision_id: String,
	captured_epoch: int,
	completion_state: Dictionary,
	on_complete: Callable,
) -> void:
	var preparation := (
		completion_state.get("avatar_preparation", {}) as Dictionary
	)
	if preparation.has("organization_request"):
		if _decision_probe_active():
			completion_state["probeAvatarOrganizationStartedUsec"] = (
				Time.get_ticks_usec()
			)
		_request_json(
			preparation["organization_request"],
			_on_avatar_organization_result.bind(
				preparation["organization_token"],
				request_decision_id,
				wake_packet.duplicate(true),
				captured_epoch,
				completion_state,
				on_complete,
				0,
			),
		)
		return
	_continue_after_avatar_organization(
		{"ok": true},
		request_decision_id,
		wake_packet,
		captured_epoch,
		completion_state,
		on_complete,
	)


func _on_avatar_organization_result(
	result: Dictionary,
	organization_token: Dictionary,
	request_decision_id: String,
	wake_packet: Dictionary,
	captured_epoch: int,
	completion_state: Dictionary,
	on_complete: Callable,
	retry_attempt: int,
) -> void:
	if bool(completion_state.get("completed", false)):
		return
	var attempt_key := "avatar_organization_attempt_%d_completed" % retry_attempt
	if bool(completion_state.get(attempt_key, false)):
		return
	completion_state[attempt_key] = true
	if completion_state.has("probeAvatarOrganizationStartedUsec"):
		_decision_probe(
			request_decision_id,
			"avatar_organization_span",
			Time.get_ticks_usec()
			- int(completion_state["probeAvatarOrganizationStartedUsec"]),
		)
		completion_state.erase("probeAvatarOrganizationStartedUsec")
	if not _request_is_current(request_decision_id, captured_epoch):
		_finish_without_callback(completion_state)
		on_complete.call({
			"ok": false,
			"stale": true,
			"decision_id": request_decision_id,
		})
		return
	var acceptance := {"ok": true}
	if bool(result.get("ok", false)) and typeof(result.get("json")) == TYPE_DICTIONARY:
		acceptance = _avatar_memory_module.accept_organization(
			organization_token,
			(result["json"] as Dictionary).duplicate(true),
		)
		if acceptance.has("retry_request") and retry_attempt == 0:
			_request_json(
				acceptance["retry_request"],
				_on_avatar_organization_result.bind(
					organization_token,
					request_decision_id,
					wake_packet,
					captured_epoch,
					completion_state,
					on_complete,
					1,
				),
			)
			return
	else:
		acceptance = _avatar_memory_module.record_organization_failure(
			result.get("errors", ["居民化身记忆整理模型调用失败"]),
		)
	_continue_after_avatar_organization(
		acceptance,
		request_decision_id,
		wake_packet,
		captured_epoch,
		completion_state,
		on_complete,
	)


func _continue_after_avatar_organization(
	organization_acceptance: Dictionary,
	request_decision_id: String,
	wake_packet: Dictionary,
	captured_epoch: int,
	completion_state: Dictionary,
	on_complete: Callable,
) -> void:
	var probe_context_started_usec := (
		Time.get_ticks_usec() if _decision_probe_active() else 0
	)
	if (
		not bool(organization_acceptance.get("ok", false))
		and not bool(organization_acceptance.get("safe_to_continue", false))
	):
		_finish_request(completion_state)
		_current_request_has_result = true
		on_complete.call({
			"ok": false,
			"errors": organization_acceptance.get(
				"errors",
				["居民化身记忆整理提交失败"],
			),
		})
		return
	var context_result: Dictionary = _memory_system.retrieve_context(
		wake_packet,
	)
	if not bool(context_result.get("ok", false)):
		_finish_request(completion_state)
		_current_request_has_result = true
		on_complete.call({
			"ok": false,
			"errors": context_result.get("errors", ["居民相关记忆读取失败"]),
		})
		return
	var avatar_context: Dictionary = _avatar_memory_module.retrieve_context(
		wake_packet,
	)
	if not bool(avatar_context.get("ok", false)):
		_finish_request(completion_state)
		_current_request_has_result = true
		on_complete.call({
			"ok": false,
			"errors": avatar_context.get(
				"errors",
				["居民化身记忆读取失败"],
			),
		})
		return
	if _decision_probe_active():
		_decision_probe(
			request_decision_id,
			"context_retrieve",
			Time.get_ticks_usec() - probe_context_started_usec,
		)
	_request_world_decision(
		wake_packet,
		_combined_memory_prompt(
			String(context_result.get("memory_prompt", "")),
			String(avatar_context.get("avatar_prompt", "")),
		),
		request_decision_id,
		captured_epoch,
		completion_state,
		on_complete,
	)


func _on_departure_organization_result(
	result: Dictionary,
	organization_token: Dictionary,
	departure_id: String,
	captured_epoch: int,
	completion_state: Dictionary,
	on_complete: Callable,
	retry_attempt: int,
) -> void:
	if bool(completion_state.get("completed", false)):
		return
	var attempt_key := "departure_organization_attempt_%d_completed" % (
		retry_attempt
	)
	if bool(completion_state.get(attempt_key, false)):
		return
	completion_state[attempt_key] = true
	if _session_epoch != null and not bool(
		_session_epoch.is_current(captured_epoch),
	):
		_finish_request(completion_state)
		on_complete.call({
			"ok": true,
			"wrote": false,
			"model_failure": true,
			"errors": ["退出前化身记忆整理结果已经过期"],
		})
		return
	var acceptance := {"ok": true}
	if bool(result.get("ok", false)) and typeof(result.get("json")) == TYPE_DICTIONARY:
		acceptance = _avatar_memory_module.accept_organization(
			organization_token,
			(result["json"] as Dictionary).duplicate(true),
		) as Dictionary
		if acceptance.has("retry_request") and retry_attempt == 0:
			_request_json(
				acceptance["retry_request"],
				_on_departure_organization_result.bind(
					organization_token,
					departure_id,
					captured_epoch,
					completion_state,
					on_complete,
					1,
				),
			)
			return
	else:
		acceptance = _avatar_memory_module.record_organization_failure(
			result.get("errors", ["退出前化身记忆整理模型调用失败"]),
		) as Dictionary
	if not bool(acceptance.get("ok", false)):
		completion_state["organization_errors"] = (
			acceptance.get("errors", []) as Array
		).duplicate()
	_begin_departure_message_request(
		departure_id,
		on_complete,
		true,
		captured_epoch,
		completion_state,
	)


func _on_departure_message_result(
	result: Dictionary,
	token: Dictionary,
	captured_epoch: int,
	completion_state: Dictionary,
	on_complete: Callable,
) -> void:
	if bool(completion_state.get("completed", false)):
		return
	if _session_epoch != null and not bool(
		_session_epoch.is_current(captured_epoch),
	):
		_finish_request(completion_state)
		return
	_finish_request(completion_state)
	if not bool(result.get("ok", false)) or typeof(result.get("json")) != TYPE_DICTIONARY:
		on_complete.call({
			"ok": true,
			"wrote": false,
			"model_failure": true,
			"errors": result.get("errors", ["居民留言模型调用失败"]),
		})
		return
	var accepted := _avatar_memory_module.review_departure_message(
		token,
		(result["json"] as Dictionary).duplicate(true),
	) as Dictionary
	if (
		not bool(accepted.get("ok", false))
		and String(accepted.get("failure_kind", "")) == "model_output"
	):
		on_complete.call({
			"ok": true,
			"wrote": false,
			"model_failure": true,
			"errors": accepted.get("errors", []),
		})
		return
	if (
		bool(accepted.get("ok", false))
		and bool(accepted.get("wrote", false))
		and accepted.get("proposal") is Dictionary
	):
		var departure_id := String(token.get("departure_id", ""))
		_departure_message_proposals[departure_id] = (
			accepted.get("proposal", {}) as Dictionary
		).duplicate(true)
		accepted.erase("proposal")
	on_complete.call(accepted.duplicate(true))


func _combined_memory_prompt(
	memory_prompt: String,
	avatar_prompt: String,
) -> String:
	var sections: Array[String] = []
	if not memory_prompt.strip_edges().is_empty():
		sections.append(memory_prompt.strip_edges())
	if not avatar_prompt.strip_edges().is_empty():
		sections.append(
			"[关于化身的个人记忆]\n%s" % avatar_prompt.strip_edges(),
		)
	return "\n\n".join(sections)


func _has_exact_state_fields(state: Dictionary, fields: Array) -> bool:
	if state.size() != fields.size():
		return false
	for field_name: Variant in fields:
		if not state.has(field_name):
			return false
	return true


func _request_world_decision(
	wake_packet: Dictionary,
	memory_prompt: String,
	request_decision_id: String,
	captured_epoch: int,
	completion_state: Dictionary,
	on_complete: Callable,
) -> void:
	_decision_execution.request_decision(
		_initialization,
		wake_packet,
		memory_prompt,
		_used_action_ids,
		_on_decision_result.bind(
			request_decision_id,
			wake_packet.duplicate(true),
			captured_epoch,
			completion_state,
			on_complete,
		),
		String(
			completion_state.get("decision_retry_feedback", ""),
		),
	)


func _on_decision_result(
	result: Dictionary,
	request_decision_id: String,
	wake_packet: Dictionary,
	captured_epoch: int,
	completion_state: Dictionary,
	on_complete: Callable,
) -> void:
	var probe_started_usec := (
		Time.get_ticks_usec() if _decision_probe_active() else 0
	)
	if bool(completion_state.get("completed", false)):
		return
	if not _request_is_current(request_decision_id, captured_epoch):
		_finish_without_callback(completion_state)
		on_complete.call({
			"ok": false,
			"stale": true,
			"decision_id": request_decision_id,
		})
		return
	_finish_request(completion_state)
	_current_request_has_result = true
	if not bool(result.get("ok", false)):
		on_complete.call(result.duplicate(true))
		return
	var decision: Dictionary = result["decision"]
	var memory_acceptance: Dictionary = _memory_system.accept_decision(decision, wake_packet)
	if _decision_probe_active():
		_decision_probe(
			request_decision_id,
			"memory_accept_decision",
			Time.get_ticks_usec() - probe_started_usec,
		)
		probe_started_usec = Time.get_ticks_usec()
	if memory_acceptance.get("ok") != true:
		on_complete.call({"ok": false, "errors": memory_acceptance.get("errors", ["记忆写入失败"])})
		return
	if decision.get("handling") == "replace_current":
		_used_action_ids[String(decision["action"]["action_id"])] = true
	var completed_result := result.duplicate(true)
	completed_result["decision"] = decision.duplicate(true)
	on_complete.call(completed_result)
	if _decision_probe_active():
		_decision_probe(
			request_decision_id,
			"gateway_complete_callback",
			Time.get_ticks_usec() - probe_started_usec,
		)


func _request_is_current(request_decision_id: String, captured_epoch: int) -> bool:
	if _session_epoch != null and not bool(_session_epoch.is_current(captured_epoch)):
		return false
	return request_decision_id == _current_decision_id and not _current_request_has_result


func discard_unconfirmed_decision(decision: Dictionary) -> Dictionary:
	var discarded := _memory_system.discard_unconfirmed_decision(
		decision,
	) as Dictionary
	if discarded.get("ok") == true and discarded.get("changed") == true:
		_used_action_ids.erase(String(discarded.get("action_id", "")))
	return discarded


func _finish_without_callback(completion_state: Dictionary) -> void:
	_finish_request(completion_state)


func _finish_request(completion_state: Dictionary) -> void:
	if bool(completion_state.get("completed", false)):
		return
	completion_state["completed"] = true
	_pending_request_count -= 1
	_notify_retired_if_drained()


func retire(on_drained: Callable) -> void:
	_on_retired_drained = on_drained
	_notify_retired_if_drained()


func _notify_retired_if_drained() -> void:
	if _pending_request_count != 0 or not _on_retired_drained.is_valid():
		return
	var callback := _on_retired_drained
	_on_retired_drained = Callable()
	callback.call()
