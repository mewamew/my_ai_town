class_name AgentSystem
extends RefCounted


const AgentContractScript := preload("res://agent/AgentContract.gd")
const AgentFileSystemScript := preload("res://agent/AgentFileSystem.gd")
const ResidentRuntimeScript := preload("res://agent/ResidentRuntime.gd")
const AgentSaveStoreScript := preload("res://agent/lifecycle/AgentSaveStore.gd")
const AgentSessionEpochScript := preload("res://agent/lifecycle/AgentSessionEpoch.gd")
const ResidentStateCodecScript := preload("res://agent/lifecycle/ResidentStateCodec.gd")
const RUNTIME_MEMORY_ROOT := "user://agent_runtime_memory"
const DEFAULT_AVATAR_PERSON_ID := "person_7f3a91c2d8e4"
const DEFAULT_AVATAR_NAME := "旅行者"
const DEBUG_RUNTIME_ROOTS: Array[String] = [
	"user://agent_debug/runtime/",
	"user://agent_debug/tests/",
]
const BATCH_RUNTIME_ROOTS: Array[String] = [
	"user://agent-batch-memory/",
	"user://agent-batch-runner-tests/",
]
const TEST_RUNTIME_ROOTS: Array[String] = [
	"user://tests/",
	"user://agent_save_tests/",
]

var _residents: Dictionary = {}
var _memory_root := ""
var _memory_root_owned := false
var _runtime_memory_root_base := RUNTIME_MEMORY_ROOT
static var _runtime_memory_generation := 0
var _retired_residents: Array[RefCounted] = []
var _save_context: Dictionary = {}
var _session_epoch: RefCounted = AgentSessionEpochScript.new()
var _session_open := true
var _save_store: RefCounted
var _resident_state_codec: RefCounted = ResidentStateCodecScript.new()
var _pending_new_game: Dictionary = {}
var _pending_restore: Dictionary = {}
var _runtime_storage_configured_for_tool := false
var _tool_storage_purpose := ""
var _avatar_person_id := DEFAULT_AVATAR_PERSON_ID
var _avatar_name := DEFAULT_AVATAR_NAME
var _departure_operations: Dictionary = {}
var _decision_retry_feedback: Dictionary = {}
var _event_memory_claim_roots: Dictionary = {}


func _init(save_store: RefCounted = null) -> void:
	_save_store = save_store if save_store != null else AgentSaveStoreScript.new()
	_memory_root = _allocate_runtime_memory_root("initial")
	_memory_root_owned = true


func configure_avatar_identity(
	avatar_person_id: String,
	avatar_name: String,
) -> Dictionary:
	var normalized_id := avatar_person_id.strip_edges()
	var normalized_name := avatar_name.strip_edges()
	if (
		normalized_id.is_empty()
		or normalized_id.length() > 128
		or normalized_name.is_empty()
	):
		return {"ok": false, "errors": ["化身稳定身份无效"]}
	if (
		not _residents.is_empty()
		or not _pending_new_game.is_empty()
		or not _pending_restore.is_empty()
	):
		return {"ok": false, "errors": ["化身身份必须在居民运行时建立前配置"]}
	_avatar_person_id = normalized_id
	_avatar_name = normalized_name
	return {"ok": true}


func start_new_game(context: Variant) -> Dictionary:
	var result: Dictionary = _save_store.call("validate_new_game", context)
	if not bool(result.get("ok", false)):
		return result
	_discard_pending_restore()
	_discard_pending_new_game()
	_pending_new_game = {
		"context": (result["context"] as Dictionary).duplicate(true),
		"residents": {},
		"memory_root": _allocate_runtime_memory_root("new_game"),
		"memory_root_owned": true,
	}
	return {
		"ok": true,
		"status": "pending_initialization",
		"context": (result["context"] as Dictionary).duplicate(true),
	}


func finish_new_game() -> Dictionary:
	if _pending_new_game.is_empty():
		return {"ok": false, "errors": ["没有等待提交的新游戏事务"]}
	var staged_residents := _pending_new_game["residents"] as Dictionary
	var capture_result := _capture_resident_payloads(staged_residents)
	if not bool(capture_result.get("ok", false)):
		return capture_result
	var context := _pending_new_game["context"] as Dictionary
	var result: Dictionary = _save_store.call(
		"create_new_game",
		context,
		capture_result["resident_payloads"],
	)
	if not bool(result.get("ok", false)):
		return result
	var transaction := _pending_new_game
	_pending_new_game = {}
	_invalidate_session()
	_activate_session(
		result["context"] as Dictionary,
		String(transaction["memory_root"]),
		bool(transaction.get("memory_root_owned", false)),
	)
	for resident_id: Variant in staged_residents:
		var resident := staged_residents[resident_id] as RefCounted
		resident.call("mark_new_game_state_ready")
		resident.call("attach_session_epoch", _session_epoch)
		_residents[resident_id] = resident
	return {
		"ok": true,
		"status": "started",
		"context": _save_context.duplicate(true),
	}


func cancel_new_game() -> Dictionary:
	_discard_pending_new_game()
	return {"ok": true}


func restore_game(context: Variant) -> Dictionary:
	var result: Dictionary = _save_store.call("load_snapshot", context)
	if not bool(result.get("ok", false)):
		return result
	var payloads := result.get("resident_payloads", {}) as Dictionary
	var decode_result := _decode_resident_payloads(payloads)
	if not bool(decode_result.get("ok", false)):
		return decode_result
	var transaction := {
		"context": (result["context"] as Dictionary).duplicate(true),
		"resident_states": decode_result["resident_states"],
		"hydrated_runtimes": {},
		"memory_root": _allocate_runtime_memory_root("restore"),
		"memory_root_owned": true,
	}
	if payloads.is_empty():
		_discard_pending_new_game()
		_discard_pending_restore()
		return _commit_restore_transaction(transaction)
	_discard_pending_new_game()
	_discard_pending_restore()
	_pending_restore = transaction
	var resident_ids: Array = payloads.keys()
	resident_ids.sort()
	return {
		"ok": true,
		"status": "pending_hydration",
		"context": (result["context"] as Dictionary).duplicate(true),
		"resident_ids": resident_ids,
	}


func save_game(next_context: Variant) -> Dictionary:
	if not _session_open or _save_context.is_empty():
		return {"ok": false, "errors": ["没有可保存的活动存档会话"]}
	if typeof(next_context) != TYPE_DICTIONARY:
		return {"ok": false, "errors": ["存档上下文必须是对象"]}
	var next := next_context as Dictionary
	var transition_errors: Array[String] = []
	for field_name in ["slot_id", "session_id"]:
		if next.get(field_name) != _save_context.get(field_name):
			transition_errors.append("保存时 %s 必须与活动存档上下文一致" % field_name)
	if not transition_errors.is_empty():
		return {"ok": false, "errors": transition_errors}
	var capture_result := _capture_resident_payloads(_residents)
	if not bool(capture_result.get("ok", false)):
		return capture_result
	var result: Dictionary = _save_store.call(
		"save_snapshot",
		next,
		capture_result["resident_payloads"],
	)
	if bool(result.get("ok", false)):
		_save_context = (result["context"] as Dictionary).duplicate(true)
	return result


func close_game() -> Dictionary:
	_discard_pending_new_game()
	_discard_pending_restore()
	_invalidate_session()
	return {"ok": true}


func delete_game(context: Variant) -> Dictionary:
	var result: Dictionary = _save_store.call("delete_slot", context)
	if not bool(result.get("ok", false)):
		return result
	if typeof(context) == TYPE_DICTIONARY:
		var deleted_context := context as Dictionary
		if _pending_new_game_targets_slot(deleted_context):
			_discard_pending_new_game()
		if _pending_restore_targets_slot(deleted_context):
			_discard_pending_restore()
		if _is_active_slot(deleted_context):
			_invalidate_session()
	return result


func get_save_context() -> Dictionary:
	return _save_context.duplicate(true)


func get_active_resident_ids() -> Dictionary:
	if not _session_open or _save_context.is_empty():
		return {"ok": false, "errors": ["没有活动的 Agent 存档会话"]}
	var resident_ids: Array[String] = []
	for resident_id_value: Variant in _residents:
		if not resident_id_value is String:
			return {"ok": false, "errors": ["活动居民 ID 集合无效"]}
		resident_ids.append(resident_id_value as String)
	resident_ids.sort()
	return {
		"ok": true,
		"resident_ids": resident_ids,
	}


func prepare_departure_messages(
	departure_id: String,
	max_candidates: int,
	on_complete: Callable,
) -> Dictionary:
	var normalized_id := departure_id.strip_edges()
	if (
		normalized_id.is_empty()
		or max_candidates < 1
		or max_candidates > 2
		or not on_complete.is_valid()
	):
		return {"ok": false, "errors": ["退出留言请求参数无效"]}
	if not _session_open or _save_context.is_empty():
		return {"ok": false, "errors": ["没有活动的 Agent 会话可生成留言"]}
	if _departure_operations.has(normalized_id):
		var existing := (
			_departure_operations[normalized_id] as Dictionary
		)
		if String(existing.get("status", "")) == "completed":
			on_complete.call(
				(existing.get("result", {}) as Dictionary).duplicate(true),
			)
			return {
				"ok": true,
				"started": false,
				"completed": true,
				"departure_id": normalized_id,
			}
		var callbacks := (existing.get("callbacks", []) as Array)
		callbacks.append(on_complete)
		existing["callbacks"] = callbacks
		_departure_operations[normalized_id] = existing
		return {
			"ok": true,
			"started": false,
			"completed": false,
			"departure_id": normalized_id,
		}
	var candidates: Array[String] = []
	var candidate_errors: Array[String] = []
	for resident_id_value: Variant in _residents:
		var resident_id := String(resident_id_value)
		var resident := _residents[resident_id] as RefCounted
		var eligible := resident.call(
			"has_avatar_departure_context",
		) as Dictionary
		if not bool(eligible.get("ok", false)):
			for error_value: Variant in eligible.get("errors", []) as Array:
				candidate_errors.append(String(error_value))
			continue
		if bool(eligible.get("eligible", false)):
			candidates.append(resident_id)
	candidates.sort()
	_departure_operations[normalized_id] = {
		"status": "pending",
		"departure_id": normalized_id,
		"candidates": candidates.duplicate(),
		"message_limit": max_candidates,
		"pending_count": candidates.size(),
		"results": {},
		"callbacks": [on_complete],
		"errors": candidate_errors,
	}
	if candidates.is_empty():
		_finish_departure_operation(normalized_id)
		return {
			"ok": true,
			"started": false,
			"completed": true,
			"departure_id": normalized_id,
		}
	for resident_id in candidates:
		var resident := _residents[resident_id] as RefCounted
		var started := resident.call(
			"request_departure_message",
			normalized_id,
			_on_departure_resident_result.bind(
				normalized_id,
				resident_id,
			),
		) as Dictionary
		if not bool(started.get("ok", false)):
			_on_departure_resident_result(
				started,
				normalized_id,
				resident_id,
			)
	return {
		"ok": true,
		"started": true,
		"completed": false,
		"departure_id": normalized_id,
		"candidate_ids": candidates.duplicate(),
	}


func get_departure_debug_snapshot(departure_id: String) -> Dictionary:
	if not _departure_operations.has(departure_id):
		return {}
	var operation := (
		_departure_operations[departure_id] as Dictionary
	).duplicate(true)
	operation.erase("callbacks")
	return operation


func hydrate_restored_resident(
	initialization: Variant,
	model_provider: Object,
	photo_content_resolver: Object = null,
) -> Dictionary:
	if _pending_restore.is_empty():
		return {"ok": false, "errors": ["没有等待 hydration 的读档事务"]}
	var errors: Array[String] = AgentContractScript.validate_initialization(initialization)
	if model_provider == null or not model_provider.has_method("request_decision"):
		errors.append("model_provider 必须实现 request_decision")
	if (
		photo_content_resolver != null
		and not photo_content_resolver.has_method("resolve_photo")
	):
		errors.append("photo_content_resolver 必须实现 resolve_photo")
	if not errors.is_empty():
		return _abort_pending_restore(errors)
	var initialization_data := initialization as Dictionary
	var resident_id := String(initialization_data["me"]["resident_id"])
	var resident_name := String(initialization_data["me"]["attributes"]["name"])
	var resident_states := _pending_restore["resident_states"] as Dictionary
	var hydrated_runtimes := _pending_restore["hydrated_runtimes"] as Dictionary
	if not resident_states.has(resident_id):
		return _abort_pending_restore(["居民 %s 不属于待读档居民集合" % resident_id])
	if hydrated_runtimes.has(resident_id):
		return _abort_pending_restore(["居民 %s 的恢复状态已经应用" % resident_id])
	var resident_state := resident_states[resident_id] as Dictionary
	if not bool(_resident_state_codec.call(
		"equivalent_initialization",
		resident_state.get("initialization"),
		initialization_data,
	)):
		var difference_paths := _resident_state_codec.call(
			"initialization_difference_paths",
			resident_state.get("initialization"),
			initialization_data,
		) as Array
		return _abort_pending_restore([
			"居民 %s 的初始化资料与保存点不一致：%s"
			% [resident_id, ", ".join(difference_paths)],
		])
	var resident: RefCounted = ResidentRuntimeScript.new(
		initialization_data,
		model_provider,
		String(_pending_restore["memory_root"]),
		photo_content_resolver,
		_avatar_person_id,
		_avatar_name,
	)
	var runtime_errors: Array = resident.call("get_initialization_errors")
	if not runtime_errors.is_empty():
		return _abort_pending_restore(runtime_errors)
	var apply_result: Dictionary = resident.call("apply_persistent_state", resident_state)
	if not bool(apply_result.get("ok", false)):
		return _abort_pending_restore(apply_result.get("errors", []) as Array)
	hydrated_runtimes[resident_id] = resident
	return {
		"ok": true,
		"resident_id": resident_id,
		"resident_name": resident_name,
	}


func finish_restore() -> Dictionary:
	if _pending_restore.is_empty():
		return {"ok": false, "errors": ["没有等待提交的读档事务"]}
	var resident_states := _pending_restore["resident_states"] as Dictionary
	var hydrated_runtimes := _pending_restore["hydrated_runtimes"] as Dictionary
	var missing_residents: Array[String] = []
	for resident_id: Variant in resident_states:
		if not hydrated_runtimes.has(resident_id):
			missing_residents.append(String(resident_id))
	missing_residents.sort()
	if not missing_residents.is_empty():
		return _abort_pending_restore(
			["读档仍缺少居民 hydration：%s" % ", ".join(missing_residents)],
		)
	var transaction := _pending_restore
	_pending_restore = {}
	return _commit_restore_transaction(transaction)


func cancel_restore() -> Dictionary:
	_discard_pending_restore()
	return {"ok": true}


func initialize_resident(
	initialization: Variant,
	model_provider: Object,
	photo_content_resolver: Object = null,
) -> Dictionary:
	var errors: Array[String] = AgentContractScript.validate_initialization(initialization)
	if _pending_new_game.is_empty() and not _session_open:
		errors.append("Agent 会话已关闭")
	if model_provider == null or not model_provider.has_method("request_decision"):
		errors.append("model_provider 必须实现 request_decision")
	if (
		photo_content_resolver != null
		and not photo_content_resolver.has_method("resolve_photo")
	):
		errors.append("photo_content_resolver 必须实现 resolve_photo")
	if not errors.is_empty():
		return {"ok": false, "errors": errors}

	var initialization_data := initialization as Dictionary
	var resident_id := String(initialization_data["me"]["resident_id"])
	var resident_name := String(initialization_data["me"]["attributes"]["name"])
	var target_residents := _residents
	var target_memory_root := _memory_root
	if not _pending_new_game.is_empty():
		target_residents = _pending_new_game["residents"] as Dictionary
		target_memory_root = String(_pending_new_game["memory_root"])
	if target_residents.has(resident_id):
		return {"ok": false, "errors": ["居民 %s 已初始化" % resident_id]}

	var resident_runtime: RefCounted = ResidentRuntimeScript.new(
		initialization_data,
		model_provider,
		target_memory_root,
		photo_content_resolver,
		_avatar_person_id,
		_avatar_name,
	)
	var runtime_errors: Array = resident_runtime.call("get_initialization_errors")
	if not runtime_errors.is_empty():
		return {"ok": false, "errors": runtime_errors}
	if _pending_new_game.is_empty():
		resident_runtime.call("attach_session_epoch", _session_epoch)
	target_residents[resident_id] = resident_runtime
	return {
		"ok": true,
		"resident_id": resident_id,
		"resident_name": resident_name,
	}


func replace_resident_model_provider(
	resident_id: String,
	model_provider: Object,
) -> Dictionary:
	var normalized_id := resident_id.strip_edges()
	if not _session_open:
		return {"ok": false, "errors": ["Agent 会话已关闭"]}
	if normalized_id.is_empty() or not _residents.has(normalized_id):
		return {"ok": false, "errors": ["找不到要替换模型的居民 Agent"]}
	if model_provider == null or not model_provider.has_method("request_decision"):
		return {"ok": false, "errors": ["model_provider 必须实现 request_decision"]}
	var resident := _residents[normalized_id] as AgentResidentRuntime
	return resident.replace_model_provider(model_provider)


func validate_resident_replacement(
	initialization: Variant,
	model_provider: Object,
	photo_content_resolver: Object = null,
) -> Dictionary:
	var errors: Array[String] = AgentContractScript.validate_initialization(
		initialization,
	)
	if not _session_open:
		errors.append("Agent 会话已关闭")
	if model_provider == null or not model_provider.has_method("request_decision"):
		errors.append("model_provider 必须实现 request_decision")
	if (
		photo_content_resolver != null
		and not photo_content_resolver.has_method("resolve_photo")
	):
		errors.append("photo_content_resolver 必须实现 resolve_photo")
	if not errors.is_empty() or not initialization is Dictionary:
		return {"ok": false, "errors": errors}
	var initialization_data := initialization as Dictionary
	var resident_id := String(
		(initialization_data.get("me", {}) as Dictionary).get(
			"resident_id",
			"",
		)
	).strip_edges()
	if resident_id.is_empty() or not _residents.has(resident_id):
		return {"ok": false, "errors": ["找不到要接替的居民 Agent 席位"]}
	# 在 World 改变生命状态之前构造一次完整运行时，确认严格
	# Agent 合同、记忆上下文与模型适配都能接受新居民。
	# 该运行时不接入会话，随局部引用释放，不会替换现有居民。
	var resident_runtime := ResidentRuntimeScript.new(
		initialization_data,
		model_provider,
		_memory_root,
		photo_content_resolver,
		_avatar_person_id,
		_avatar_name,
	)
	var runtime_errors: Array = resident_runtime.get_initialization_errors()
	if not runtime_errors.is_empty():
		return {"ok": false, "errors": runtime_errors}
	return {
		"ok": true,
		"resident_id": resident_id,
		"resident_name": String(
			(initialization_data.get("me", {}) as Dictionary)
			.get("attributes", {})
			.get("name", "")
		),
	}


func replace_resident(
	initialization: Variant,
	model_provider: Object,
	photo_content_resolver: Object = null,
) -> Dictionary:
	if not initialization is Dictionary:
		return {"ok": false, "errors": ["新居民初始化资料无效"]}
	var me := (initialization as Dictionary).get("me", {}) as Dictionary
	var resident_id := String(me.get("resident_id", "")).strip_edges()
	if not _session_open or resident_id.is_empty() or not _residents.has(resident_id):
		return {"ok": false, "errors": ["找不到要接替的居民 Agent 席位"]}
	var previous := _residents[resident_id] as AgentResidentRuntime
	_residents.erase(resident_id)
	var initialized := initialize_resident(
		initialization,
		model_provider,
		photo_content_resolver,
	) as Dictionary
	if not bool(initialized.get("ok", false)):
		_residents[resident_id] = previous
		return initialized
	_retired_residents.append(previous)
	previous.retire(_release_retired_resident.bind(previous))
	return initialized


func configure_debug_runtime_storage(root: String) -> Dictionary:
	return _configure_tool_runtime_storage(root, DEBUG_RUNTIME_ROOTS, "debug")


static func validate_debug_runtime_storage(root: String) -> Dictionary:
	return _validate_tool_runtime_storage_root(
		root,
		DEBUG_RUNTIME_ROOTS,
		"debug",
	)


func configure_batch_runtime_storage(root: String) -> Dictionary:
	return _configure_tool_runtime_storage(
		root,
		BATCH_RUNTIME_ROOTS,
		"batch",
	)


static func validate_batch_runtime_storage(root: String) -> Dictionary:
	return _validate_tool_runtime_storage_root(
		root,
		BATCH_RUNTIME_ROOTS,
		"batch",
	)


func configure_test_runtime_storage(root: String) -> Dictionary:
	return _configure_tool_runtime_storage(
		root,
		TEST_RUNTIME_ROOTS,
		"test",
	)


func request_decision(
	resident_id: String,
	wake_packet: Variant,
	on_complete: Callable,
) -> Dictionary:
	if not _session_open:
		return {"ok": false, "errors": ["Agent 会话已关闭"]}
	if not _residents.has(resident_id):
		return {"ok": false, "errors": ["居民 %s 尚未初始化" % resident_id]}
	var decision_id := (
		String((wake_packet as Dictionary).get("decision_id", ""))
		if wake_packet is Dictionary
		else ""
	)
	var feedback_key := _decision_retry_feedback_key(
		resident_id,
		decision_id,
	)
	var retry_feedback := String(
		_decision_retry_feedback.get(feedback_key, ""),
	)
	_decision_retry_feedback.erase(feedback_key)
	var prepared_wake: Variant = _wake_with_memory_claim_roots(wake_packet)
	if retry_feedback.is_empty():
		return _residents[resident_id].call(
			"request_decision",
			prepared_wake,
			on_complete,
		)
	return _residents[resident_id].call(
		"request_decision",
		prepared_wake,
		on_complete,
		retry_feedback,
	)


func request_json_for_resident(
	resident_id: String,
	model_request: Dictionary,
	on_complete: Callable,
) -> Dictionary:
	if not _session_open:
		return {"ok": false, "errors": ["Agent 会话已关闭"]}
	if not _residents.has(resident_id):
		return {"ok": false, "errors": ["居民 %s 尚未初始化" % resident_id]}
	if not on_complete.is_valid():
		return {"ok": false, "errors": ["模型结构化请求回调无效"]}
	return _residents[resident_id].call(
		"request_json",
		model_request,
		on_complete,
	) as Dictionary


func _wake_with_memory_claim_roots(wake_packet: Variant) -> Variant:
	if typeof(wake_packet) != TYPE_DICTIONARY:
		return wake_packet
	var prepared := (wake_packet as Dictionary).duplicate(true)
	var events := prepared.get("events", []) as Array
	for event_index in range(events.size()):
		if typeof(events[event_index]) != TYPE_DICTIONARY:
			continue
		var event := (events[event_index] as Dictionary).duplicate(true)
		var event_id := String(event.get("event_id", "")).strip_edges()
		if typeof(event.get("turn")) == TYPE_DICTIONARY:
			event["turn"] = _turn_with_memory_claim_root(
				event["turn"] as Dictionary,
			_event_turn_claim_key(event_id, "turn"),
		)
		if typeof(event.get("turns")) == TYPE_ARRAY:
			var turns: Array = []
			for turn_index in (event["turns"] as Array).size():
				var turn_value: Variant = (event["turns"] as Array)[turn_index]
				if typeof(turn_value) == TYPE_DICTIONARY:
					turns.append(_turn_with_memory_claim_root(
						turn_value as Dictionary,
						_event_turn_claim_key(
							event_id,
							"turns:%d" % turn_index,
						),
					))
				else:
					turns.append(turn_value)
			event["turns"] = turns
		events[event_index] = event
	prepared["events"] = events
	return prepared


func _event_turn_claim_key(event_id: String, turn_path: String) -> String:
	if event_id.is_empty():
		return ""
	return "%s\n%s" % [event_id, turn_path]


func _turn_with_memory_claim_root(
	turn: Dictionary,
	claim_key := "",
) -> Dictionary:
	var prepared := turn.duplicate(true)
	if not claim_key.is_empty() and _event_memory_claim_roots.has(claim_key):
		var stable_claim_root := String(
			_event_memory_claim_roots.get(claim_key, ""),
		)
		if not stable_claim_root.is_empty():
			prepared["memory_claim_root_id"] = stable_claim_root
		else:
			prepared.erase("memory_claim_root_id")
		return prepared
	var speaker_id := String(prepared.get("speaker_resident_id", "")).strip_edges()
	var spoken_text := String(prepared.get("say", "")).strip_edges()
	if speaker_id.is_empty() or spoken_text.is_empty() or not _residents.has(speaker_id):
		if not claim_key.is_empty():
			_event_memory_claim_roots[claim_key] = ""
		return prepared
	var match_result := _residents[speaker_id].call(
		"find_expressed_memory_claim",
		spoken_text,
	) as Dictionary
	if bool(match_result.get("ok", false)) and bool(match_result.get("matched", false)):
		prepared["memory_claim_root_id"] = String(match_result.get("claim_root_id", ""))
	if not claim_key.is_empty():
		_event_memory_claim_roots[claim_key] = String(
			prepared.get("memory_claim_root_id", ""),
		)
	return prepared


func set_decision_retry_feedback(
	resident_id: String,
	decision_id: String,
	feedback: String,
) -> Dictionary:
	var normalized_resident := resident_id.strip_edges()
	var normalized_decision := decision_id.strip_edges()
	var normalized_feedback := feedback.strip_edges()
	if (
		normalized_resident.is_empty()
		or normalized_decision.is_empty()
		or normalized_feedback.is_empty()
		or normalized_feedback.length() > 1200
	):
		return {"ok": false, "errors": ["决定重试反馈无效"]}
	_decision_retry_feedback[
		_decision_retry_feedback_key(
			normalized_resident,
			normalized_decision,
		)
	] = normalized_feedback
	return {"ok": true}


func _decision_retry_feedback_key(
	resident_id: String,
	decision_id: String,
) -> String:
	return "%s\n%s" % [resident_id, decision_id]


func discard_unconfirmed_decision(
	resident_id: String,
	decision: Dictionary,
) -> Dictionary:
	if not _session_open:
		return {"ok": false, "errors": ["Agent 会话已关闭"]}
	if not _residents.has(resident_id):
		return {"ok": false, "errors": ["居民 %s 尚未初始化" % resident_id]}
	return _residents[resident_id].call(
		"discard_unconfirmed_decision",
		decision,
	) as Dictionary


func get_memory_debug_snapshot(resident_id: String) -> Dictionary:
	if not _residents.has(resident_id):
		return {}
	return _residents[resident_id].call("get_memory_debug_snapshot")


func get_resident_debug_snapshot(resident_id: String) -> Dictionary:
	if not _residents.has(resident_id):
		return {}
	return _residents[resident_id].call("get_debug_snapshot")


func get_resident_memory(resident_id: String) -> Dictionary:
	if not _session_open:
		return {"ok": false, "errors": ["Agent 会话已关闭"]}
	if not _residents.has(resident_id):
		return {"ok": false, "errors": ["居民 %s 尚未初始化" % resident_id]}
	return _residents[resident_id].call("get_read_only_memory")


func apply_resident_memory_intervention(
	resident_id: String,
	request: Variant,
) -> Dictionary:
	if not _session_open:
		return {"ok": false, "errors": ["Agent 会话已关闭"]}
	if not _residents.has(resident_id):
		return {"ok": false, "errors": ["居民 %s 尚未初始化" % resident_id]}
	return _residents[resident_id].call(
		"apply_memory_intervention",
		request,
	) as Dictionary


func seed_debug_memory(resident_id: String, memory: Variant) -> Dictionary:
	if not _runtime_storage_configured_for_tool or _tool_storage_purpose != "debug":
		return {"ok": false, "errors": ["居民记忆样例只能写入 DEBUG 专属运行时"]}
	if _pending_new_game.is_empty():
		return {"ok": false, "errors": ["记忆样例只能在调试存档初始化事务中写入"]}
	var staged_residents := _pending_new_game["residents"] as Dictionary
	if not staged_residents.has(resident_id):
		return {"ok": false, "errors": ["居民 %s 尚未初始化" % resident_id]}
	return staged_residents[resident_id].call("seed_debug_memory", memory)


func _on_departure_resident_result(
	result: Dictionary,
	departure_id: String,
	resident_id: String,
) -> void:
	if not _departure_operations.has(departure_id):
		return
	var operation := (
		_departure_operations[departure_id] as Dictionary
	)
	if String(operation.get("status", "")) != "pending":
		return
	var results := operation.get("results", {}) as Dictionary
	if results.has(resident_id):
		return
	results[resident_id] = result.duplicate(true)
	operation["results"] = results
	operation["pending_count"] = maxi(
		0,
		int(operation.get("pending_count", 0)) - 1,
	)
	if not bool(result.get("ok", false)):
		var errors := operation.get("errors", []) as Array
		for error_value: Variant in result.get("errors", []) as Array:
			errors.append("%s：%s" % [resident_id, error_value])
		operation["errors"] = errors
	_departure_operations[departure_id] = operation
	if int(operation.get("pending_count", 0)) == 0:
		_finish_departure_operation(departure_id)


func _finish_departure_operation(departure_id: String) -> void:
	if not _departure_operations.has(departure_id):
		return
	var operation := (
		_departure_operations[departure_id] as Dictionary
	)
	if String(operation.get("status", "")) != "pending":
		return
	var results := operation.get("results", {}) as Dictionary
	var proposal_ids: Array[String] = []
	for resident_id_value: Variant in operation.get("candidates", []) as Array:
		var resident_id := String(resident_id_value)
		if not results.has(resident_id):
			continue
		var resident_result := results[resident_id] as Dictionary
		if (
			bool(resident_result.get("ok", false))
			and bool(resident_result.get("wrote", false))
		):
			proposal_ids.append(resident_id)
	var selected_ids := proposal_ids.duplicate()
	var message_limit := int(operation.get("message_limit", 2))
	if selected_ids.size() > message_limit:
		selected_ids.shuffle()
		selected_ids.resize(message_limit)
	var messages: Array[Dictionary] = []
	var errors := operation.get("errors", []) as Array
	for resident_id: String in proposal_ids:
		var resident := _residents.get(resident_id) as RefCounted
		if resident == null:
			errors.append("%s：居民运行时不存在" % resident_id)
			continue
		if not selected_ids.has(resident_id):
			var discarded := resident.call(
				"discard_departure_message_proposal",
				departure_id,
			) as Dictionary
			if not bool(discarded.get("ok", false)):
				for error_value: Variant in (
					discarded.get("errors", []) as Array
				):
					errors.append("%s：%s" % [resident_id, error_value])
			continue
		var committed := resident.call(
			"commit_departure_message",
			departure_id,
		) as Dictionary
		if (
			bool(committed.get("ok", false))
			and bool(committed.get("wrote", false))
			and committed.get("message") is Dictionary
		):
			messages.append(
				(committed.get("message", {}) as Dictionary).duplicate(true),
			)
			continue
		for error_value: Variant in committed.get("errors", []) as Array:
			errors.append("%s：%s" % [resident_id, error_value])
	var result := {
		# Resident messages are an optional departure extra. Memory/model faults
		# must never prevent the authoritative town save and process exit.
		"ok": true,
		"departure_id": departure_id,
		"candidate_ids": (
			operation.get("candidates", []) as Array
		).duplicate(),
		"message_candidate_ids": proposal_ids.duplicate(),
		"selected_message_ids": selected_ids.duplicate(),
		"messages": messages,
	}
	if not errors.is_empty():
		result["warnings"] = errors.duplicate()
	operation["status"] = "completed"
	operation["result"] = result.duplicate(true)
	var callbacks := (operation.get("callbacks", []) as Array).duplicate()
	operation["callbacks"] = []
	_departure_operations[departure_id] = operation
	for callback_value: Variant in callbacks:
		if callback_value is Callable and (callback_value as Callable).is_valid():
			(callback_value as Callable).call(result.duplicate(true))


func _invalidate_session() -> void:
	if _session_epoch != null:
		_session_epoch.call("invalidate")
	for resident: RefCounted in _residents.values():
		_retired_residents.append(resident)
		resident.call("retire", _release_retired_resident.bind(resident))
	_residents.clear()
	_departure_operations.clear()
	_decision_retry_feedback.clear()
	_event_memory_claim_roots.clear()
	_save_context.clear()
	_session_open = false
	if _memory_root_owned:
		_remove_runtime_memory_root(_memory_root)
	_memory_root = ""
	_memory_root_owned = false


func _activate_session(
	context: Dictionary,
	memory_root: String,
	memory_root_owned: bool,
) -> void:
	_session_epoch = AgentSessionEpochScript.new()
	_save_context = context.duplicate(true)
	_memory_root = memory_root
	_memory_root_owned = memory_root_owned
	_session_open = true


func _release_retired_resident(resident: RefCounted) -> void:
	_retired_residents.erase(resident)


func _capture_resident_payloads(residents: Dictionary) -> Dictionary:
	var payloads := {}
	var resident_ids: Array = residents.keys()
	resident_ids.sort()
	for resident_id: Variant in resident_ids:
		var resident := residents[resident_id] as RefCounted
		var capture_result: Dictionary = resident.call("capture_persistent_state")
		if not bool(capture_result.get("ok", false)):
			return capture_result
		if String(capture_result.get("resident_id", "")) != String(resident_id):
			return {"ok": false, "errors": ["活动居民字典与运行时身份不一致"]}
		var resident_name := String(capture_result.get("resident_name", ""))
		var encode_result: Dictionary = _resident_state_codec.call(
			"encode",
			String(resident_id),
			resident_name,
			capture_result.get("resident_state"),
		)
		if not bool(encode_result.get("ok", false)):
			return encode_result
		payloads[resident_id] = {
			"resident_name": resident_name,
			"payload": encode_result["payload"],
		}
	return {"ok": true, "resident_payloads": payloads}


func _decode_resident_payloads(payloads: Dictionary) -> Dictionary:
	var resident_states := {}
	for resident_id: Variant in payloads:
		var payload_record := payloads[resident_id] as Dictionary
		var decode_result: Dictionary = _resident_state_codec.call(
			"decode",
			String(resident_id),
			String(payload_record["resident_name"]),
			payload_record["payload"],
		)
		if not bool(decode_result.get("ok", false)):
			return decode_result
		resident_states[resident_id] = decode_result["resident_state"]
	return {"ok": true, "resident_states": resident_states}


func _commit_restore_transaction(transaction: Dictionary) -> Dictionary:
	var restored_context := (transaction["context"] as Dictionary).duplicate(true)
	var hydrated_runtimes := transaction["hydrated_runtimes"] as Dictionary
	var restored_memory_root := String(transaction["memory_root"])
	var restored_memory_root_owned := bool(transaction.get("memory_root_owned", false))
	_invalidate_session()
	_activate_session(
		restored_context,
		restored_memory_root,
		restored_memory_root_owned,
	)
	for resident_id: Variant in hydrated_runtimes:
		var resident := hydrated_runtimes[resident_id] as RefCounted
		resident.call("attach_session_epoch", _session_epoch)
		_residents[resident_id] = resident
	return {
		"ok": true,
		"status": "restored",
		"context": _save_context.duplicate(true),
	}


func _abort_pending_restore(errors: Array) -> Dictionary:
	_discard_pending_restore()
	return {"ok": false, "errors": errors.duplicate(true)}


func _is_active_slot(context: Dictionary) -> bool:
	if _save_context.is_empty():
		return false
	return context.get("slot_id") == _save_context.get("slot_id")


func _pending_restore_targets_slot(context: Dictionary) -> bool:
	if _pending_restore.is_empty():
		return false
	var pending_context := _pending_restore.get("context", {}) as Dictionary
	return context.get("slot_id") == pending_context.get("slot_id")


func _pending_new_game_targets_slot(context: Dictionary) -> bool:
	if _pending_new_game.is_empty():
		return false
	var pending_context := _pending_new_game.get("context", {}) as Dictionary
	return context.get("slot_id") == pending_context.get("slot_id")


func _discard_pending_new_game() -> void:
	if _pending_new_game.is_empty():
		return
	if bool(_pending_new_game.get("memory_root_owned", false)):
		_remove_runtime_memory_root(String(_pending_new_game.get("memory_root", "")))
	_pending_new_game.clear()


func _discard_pending_restore() -> void:
	if _pending_restore.is_empty():
		return
	if bool(_pending_restore.get("memory_root_owned", false)):
		_remove_runtime_memory_root(String(_pending_restore.get("memory_root", "")))
	_pending_restore.clear()


func _configure_tool_runtime_storage(
	root: String,
	allowed_prefixes: Array[String],
	purpose: String,
) -> Dictionary:
	if _runtime_storage_configured_for_tool:
		return {"ok": false, "errors": ["Agent 工具运行时存储只能配置一次"]}
	if (
		not _residents.is_empty()
		or not _save_context.is_empty()
		or not _pending_new_game.is_empty()
		or not _pending_restore.is_empty()
	):
		return {"ok": false, "errors": ["Agent 工具运行时存储必须在建立会话状态前配置"]}
	var validation := _validate_tool_runtime_storage_root(root, allowed_prefixes, purpose)
	if validation.get("ok") != true:
		return validation
	if _memory_root_owned:
		_remove_runtime_memory_root(_memory_root)
	_runtime_memory_root_base = String(validation["root"])
	_memory_root = String(validation["root"])
	_memory_root_owned = false
	_runtime_storage_configured_for_tool = true
	_tool_storage_purpose = purpose
	return {"ok": true}


static func _validate_tool_runtime_storage_root(
	root: String,
	allowed_prefixes: Array[String],
	purpose: String,
) -> Dictionary:
	var normalized := root.trim_suffix("/")
	var allowed := false
	for prefix: String in allowed_prefixes:
		if normalized.begins_with(prefix):
			allowed = true
			break
	if not allowed or normalized.contains(".."):
		return {"ok": false, "errors": ["Agent %s 运行时存储不在允许的 user:// 命名空间" % purpose]}
	return {"ok": true, "root": normalized}


func _allocate_runtime_memory_root(purpose: String) -> String:
	while true:
		_runtime_memory_generation += 1
		var nonce := Crypto.new().generate_random_bytes(16).hex_encode()
		var candidate := "%s/%d_%d_%s_%s" % [
			_runtime_memory_root_base,
			OS.get_process_id(),
			_runtime_memory_generation,
			purpose,
			nonce,
		]
		if (
			not FileAccess.file_exists(candidate)
			and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(candidate))
		):
			return candidate
	return ""


func _remove_runtime_memory_root(path: String) -> void:
	if (
		_runtime_memory_root_base.is_empty()
		or not path.begins_with("%s/" % _runtime_memory_root_base)
		or path.contains("..")
	):
		return
	var remove_error := AgentFileSystemScript.remove_tree(path)
	if remove_error != OK:
		push_error("清理 Agent 运行时记忆目录失败：%s" % error_string(remove_error))
		return
	AgentFileSystemScript.remove_empty_directory(_runtime_memory_root_base)
