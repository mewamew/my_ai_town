class_name TownWorldAgentGateway
extends Node


signal debug_decision_dispatched(trace: Dictionary)
signal debug_decision_completed(trace: Dictionary)


const RESULT_SHAPES := preload(
	"res://world/contract/TownWorldResultShapes.gd"
)
const AGENT_SYSTEM := preload("res://agent/AgentSystem.gd")
const PHOTO_STORE := preload(
	"res://world/integration/TownConversationPhotoStore.gd"
)
const REQUIRED_WORLD_METHODS: Array[String] = [
	"is_running",
	"get_resident_identity_snapshot",
	"get_agent_initialization_by_id",
	"take_pending_decision_requests_by_ids",
	"redispatch_decision_request_by_id",
	"submit_agent_decision_by_id",
	"mark_social_candidate_terminal",
]
const REQUIRED_PROVIDER_SERVICE_METHODS: Array[String] = [
	"create_provider_for_resident",
	"get_latest_diagnostic",
]
# Fifteen residents sharing two slots can leave most of the town visibly idle
# for several model round trips after a synchronized action boundary. Keep the
# burst bounded, but give a normal town enough lanes to keep living.
const MAX_CONCURRENT_MODEL_REQUESTS := 6
const RESERVED_AVATAR_CONVERSATION_REQUEST_SLOTS := 1
# 本地推理通常由一张显卡或一颗 CPU 串行处理。允许两个普通居民继续推进，
# 再给玩家对话留一个独立位置；其余请求保留在 World 待处理队列中，
# 不会因为排队而触发可见的连续性兜底。
const MAX_CONCURRENT_LOCAL_MODEL_REQUESTS := 3
const MAX_CONCURRENT_LOCAL_ORDINARY_REQUESTS := 2
const LOCAL_MODEL_PROVIDER_IDS: Array[String] = ["ollama", "lm-studio"]
const MAX_DECISION_ATTEMPTS := 2
const MAX_ERROR_HISTORY := 128
const DEFAULT_AVATAR_PERSON_ID := "person_7f3a91c2d8e4"
const DEFAULT_AVATAR_NAME := "旅行者"
# Keep this in step with ResidentMemorySummaryProjector's player-visible
# current-thought contract; the overlay applies its own shorter display limit.
const INNER_OBSERVATION_MAX_CURRENT_FOCUS_CHARS := 1000
const INNER_OBSERVATION_CURRENT_THOUGHT_DISPLAY_CHARS := 220
const INNER_OBSERVATION_NEXT_PLAN_DISPLAY_CHARS := 120
const INNER_OBSERVATION_REASON_DISPLAY_CHARS := 100
const INNER_OBSERVATION_FORBIDDEN_PLAYER_TERMS: Array[String] = [
	"system prompt",
	"systemprompt",
	"提示词",
	"系统指令",
	"模型响应",
	"原始响应",
	"provider",
	"trace",
	"source id",
	"sourceid",
	"memory id",
	"memoryid",
	"chain of thought",
	"思维链",
	"json",
]
const DEATH_STORY_MAX_CHARS := 96
const DEATH_STORY_FORBIDDEN_TERMS: Array[String] = [
	"system prompt",
	"systemprompt",
	"提示词",
	"系统指令",
	"模型回答",
	"原始响应",
	"provider",
	"json",
	"思维链",
	"被杀死",
	"老死",
	"寿终正寝",
	"自然死亡",
	"年老",
]

var _world: RefCounted
# A1 探针:仅 AI_TOWN_UI_FRAME_PROBE=1 时于首次 pump 加载,关闭时零开销。
var _frame_probe: GDScript = null
var _frame_probe_checked := false
var _agent_system: RefCounted = AGENT_SYSTEM.new()
var _photo_store: RefCounted = PHOTO_STORE.new()
var _provider_service: Object
var _request_host: Node
var _session_config: Dictionary = {}
var _save_context: Dictionary = {}
var _resident_identities: Array[Dictionary] = []
var _bindings_by_id: Dictionary = {}
var _resident_name_by_id: Dictionary = {}
var _resident_id_by_name: Dictionary = {}
var _connected_resident_ids: Array[String] = []
var _errors: Array[Dictionary] = []
var _error_sequence := 0
var _last_submissions: Dictionary = {}
var _inflight: Dictionary = {}
var _decision_attempts: Dictionary = {}
var _inner_observation_inflight: Dictionary = {}
var _death_story_inflight: Dictionary = {}
var _pump_cursor := 0
var _generation := 1
var _session_active := false
var _avatar_person_id := DEFAULT_AVATAR_PERSON_ID
var _request_metrics: Dictionary = {
	"providerDispatch": 0,
	"providerComplete": 0,
}


func _reset_request_metrics() -> void:
	_request_metrics = {
		"providerDispatch": 0,
		"providerComplete": 0,
	}


func _count_request_metric(key: String, amount := 1) -> void:
	_request_metrics[key] = int(_request_metrics.get(key, 0)) + amount


func get_request_metrics() -> Dictionary:
	var result := _request_metrics.duplicate(true)
	if _world != null and _world.has_method("get_agent_request_metrics"):
		var world_metrics := _world.get_agent_request_metrics() as Dictionary
		for key: Variant in world_metrics:
			result[key] = int(result.get(key, 0)) + int(
				world_metrics.get(key, 0)
			)
	return result


func configure_session(
	config: Dictionary,
	provider_service: Object = null,
	request_host: Node = null,
) -> Dictionary:
	if is_inside_tree() and _session_active:
		return _failure("AGENT_GATEWAY_CONFIGURATION_LATE", false)
	if provider_service == null:
		return _failure("PROVIDER_SERVICE_REQUIRED", false)
	var missing_provider_methods := _missing_methods(
		provider_service,
		REQUIRED_PROVIDER_SERVICE_METHODS,
	)
	if not missing_provider_methods.is_empty():
		return _failure("PROVIDER_SERVICE_CONTRACT_MISSING", false, [{
			"missingMethods": missing_provider_methods,
		}])
	var session_id := String(config.get("sessionId", "")).strip_edges()
	var slot_id := String(config.get("slotId", "")).strip_edges()
	var save_revision := int(config.get("saveRevision", 0))
	var restore_pending := bool(config.get("restorePending", false))
	if session_id.is_empty():
		return _failure("SESSION_ID_REQUIRED", false)
	if slot_id.is_empty():
		return _failure("SESSION_SLOT_ID_REQUIRED", false)
	if save_revision != 0 and not restore_pending:
		return _failure("SESSION_NEW_GAME_REVISION_INVALID", false)
	if restore_pending and save_revision <= 0:
		return _failure("SESSION_RESTORE_REVISION_REQUIRED", false)
	var identity_result := _normalize_identities(config.get("residentIdentities", []))
	if not bool(identity_result.get("ok", false)):
		return identity_result
	var binding_result := _normalize_bindings(
		config.get("residentBindings", []),
		identity_result.get("residents", []) as Array[Dictionary],
	)
	if not bool(binding_result.get("ok", false)):
		return binding_result
	_generation += 1
	_world = null
	_session_active = false
	_photo_store.clear()
	var photo_storage := _photo_store.configure_session(slot_id,
		session_id,) as Dictionary
	if not bool(photo_storage.get("ok", false)):
		return _failure(
			String(
				photo_storage.get(
					"errorCode",
					"PHOTO_STORAGE_UNAVAILABLE",
				)
			),
			false,
		)
	_inflight.clear()
	_decision_attempts.clear()
	_inner_observation_inflight.clear()
	_death_story_inflight.clear()
	_reset_request_metrics()
	_pump_cursor = 0
	_errors.clear()
	_last_submissions.clear()
	_resident_identities = (
		identity_result.get("residents", []) as Array[Dictionary]
	).duplicate(true)
	_bindings_by_id = (
		binding_result.get("bindingsById", {}) as Dictionary
	).duplicate(true)
	_rebuild_identity_maps()
	_provider_service = provider_service
	_request_host = request_host
	_save_context = {
		"slot_id": slot_id,
		"session_id": session_id,
		"save_revision": save_revision,
	}
	_session_config = config.duplicate(true)
	_session_config["slotId"] = slot_id
	_session_config["sessionId"] = session_id
	_session_config["saveRevision"] = save_revision
	var opening := config.get("openingConfig", {}) as Dictionary
	var player_avatar := opening.get("playerAvatar", {}) as Dictionary
	_avatar_person_id = String(
		player_avatar.get("residentId", DEFAULT_AVATAR_PERSON_ID),
	).strip_edges()
	var avatar_identity := _agent_system.configure_avatar_identity(_avatar_person_id,
		String(player_avatar.get("name", DEFAULT_AVATAR_NAME)),) as Dictionary
	if not bool(avatar_identity.get("ok", false)):
		return _agent_stage_failure(
			"AGENT_AVATAR_IDENTITY_CONFIGURATION_FAILED",
			"configure_avatar_identity",
			"",
			avatar_identity,
		)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"sessionId": session_id,
		"slotId": slot_id,
		"residentCount": _resident_identities.size(),
	}


func bind_world(world: RefCounted) -> Dictionary:
	if _session_config.is_empty():
		return _failure("AGENT_GATEWAY_SESSION_NOT_CONFIGURED", false)
	var missing_world_methods := _missing_methods(world, REQUIRED_WORLD_METHODS)
	if not missing_world_methods.is_empty():
		return _failure("AGENT_GATEWAY_WORLD_CONTRACT_MISSING", false, [{
			"missingMethods": missing_world_methods,
		}])
	if not bool(world.call("is_running")):
		return _failure("WORLD_NOT_RUNNING", false)
	var world_identities := world.call("get_resident_identity_snapshot") as Dictionary
	var normalized_world := _normalize_identities(world_identities.get("residents", []))
	if not bool(normalized_world.get("ok", false)):
		return _failure("WORLD_RESIDENT_IDENTITIES_INVALID", false)
	if (
		(normalized_world.get("residents", []) as Array[Dictionary])
		!= _resident_identities
	):
		return _failure("AGENT_GATEWAY_WORLD_IDENTITY_MISMATCH", false, [{
			"expected": _resident_identities.duplicate(true),
			"actual": (
				normalized_world.get("residents", []) as Array[Dictionary]
			).duplicate(true),
		}])
	if _session_active:
		if _world == world:
			return {
				"ok": true,
				"errorCode": "",
				"retryable": false,
				"residentCount": _connected_resident_ids.size(),
				"alreadyBound": true,
			}
		return _failure("AGENT_GATEWAY_ALREADY_BOUND", false)
	_world = world
	if bool(_session_config.get("restorePending", false)):
		_connected_resident_ids.clear()
		for identity in _resident_identities:
			_connected_resident_ids.append(String(identity.get("residentId", "")))
		_connected_resident_ids.sort()
		# A continue session must not create a revision-0 Agent game or dispatch
		# model work before the save coordinator has restored both participants.
		_session_active = false
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"residentCount": _connected_resident_ids.size(),
			"restorePending": true,
		}
	var start_result := _agent_system.start_new_game(_save_context.duplicate(true),) as Dictionary
	if not bool(start_result.get("ok", false)):
		_world = null
		return _agent_stage_failure(
			"AGENT_NEW_GAME_PREPARE_FAILED",
			"start_new_game",
			"",
			start_result,
		)
	for identity in _resident_identities:
		var resident_id := String(identity.get("residentId", ""))
		var initialization := world.call(
			"get_agent_initialization_by_id",
			resident_id,
		) as Dictionary
		if initialization.is_empty():
			_cancel_new_game()
			_world = null
			return _failure("WORLD_AGENT_INITIALIZATION_MISSING", false, [{
				"residentId": resident_id,
			}])
		var me := initialization.get("me", {}) as Dictionary
		if String(me.get("resident_id", "")) != resident_id:
			_cancel_new_game()
			_world = null
			return _failure("WORLD_AGENT_INITIALIZATION_ID_MISMATCH", false, [{
				"residentId": resident_id,
			}])
		var binding := _bindings_by_id.get(resident_id, {}) as Dictionary
		var provider_result := _provider_service.create_provider_for_resident(binding,) as Dictionary
		if not bool(provider_result.get("ok", false)):
			_cancel_new_game()
			_world = null
			return _normalized_failure(
				provider_result,
				"LLM_MODEL_PROVIDER_CREATION_FAILED",
			)
		var initialize_result := _agent_system.initialize_resident(initialization,
			provider_result.get("provider"),
			_photo_store,) as Dictionary
		if not bool(initialize_result.get("ok", false)):
			_cancel_new_game()
			_world = null
			return _agent_stage_failure(
				"AGENT_RESIDENT_INITIALIZATION_FAILED",
				"initialize_resident",
				resident_id,
				initialize_result,
			)
	var finish_result := _agent_system.finish_new_game() as Dictionary
	if not bool(finish_result.get("ok", false)):
		_cancel_new_game()
		_world = null
		return _agent_stage_failure(
			"AGENT_NEW_GAME_COMMIT_FAILED",
			"finish_new_game",
			"",
			finish_result,
		)
	_connected_resident_ids.clear()
	for identity in _resident_identities:
		_connected_resident_ids.append(String(identity.get("residentId", "")))
	_connected_resident_ids.sort()
	_session_active = true
	_generation += 1
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"residentCount": _connected_resident_ids.size(),
		"saveContext": _agent_system.get_save_context() as Dictionary,
	}


func pump(max_requests := -1) -> int:
	if not _frame_probe_checked:
		_frame_probe_checked = true
		if OS.get_environment("AI_TOWN_UI_FRAME_PROBE") == "1":
			_frame_probe = load("res://world/presentation/ui/TownUiFrameProbe.gd")
	if not _session_active or _world == null:
		return 0
	var probe_lap_usec := Time.get_ticks_usec() if _frame_probe != null else 0
	var requests: Array[Dictionary]
	if _world.has_method("take_pending_decision_envelopes_by_ids"):
		requests = _world.take_pending_decision_envelopes_by_ids(
			_connected_resident_ids,
		) as Array[Dictionary]
	else:
		requests = _world.take_pending_decision_requests_by_ids(
			_connected_resident_ids,
		) as Array[Dictionary]
	if _frame_probe != null:
		var now_usec := Time.get_ticks_usec()
		_frame_probe.record(Engine.get_process_frames(), "agentTakeUsec", now_usec - probe_lap_usec)
		_frame_probe.record(Engine.get_process_frames(), "agentPendingCount", requests.size())
		probe_lap_usec = now_usec
	requests = _round_robin_requests(requests)
	requests = _prioritize_conversation_requests(requests)
	# 玩家或优先事件刚刚产生新的对话请求时，先让同居民旧请求失效，
	# 再做容量投影；旧请求随后仍可返回，但不再占用逻辑槽位。
	_mark_superseded_inflight_for_pending_requests(requests)
	var has_pending_avatar_conversation := false
	for request in requests:
		if _wake_is_avatar_conversation_turn(
			request.get("wakePacket", {}) as Dictionary
		):
			has_pending_avatar_conversation = true
			break
	var selection := _select_dispatchable_requests(
		requests,
		max_requests,
		has_pending_avatar_conversation,
	)
	requests = selection.get("selected", []) as Array[Dictionary]
	var overflow := selection.get("overflow", []) as Array[Dictionary]
	for request: Dictionary in overflow:
		_redispatch(
			String(request.get("residentId", "")),
			String(
				(request.get("wakePacket", {}) as Dictionary).get(
					"decision_id",
					"",
				)
			),
		)
	if _frame_probe != null:
		probe_lap_usec = _probe_record_lap("agentSelectUsec", probe_lap_usec)
	for request in requests:
		_mark_superseded_inflight_for_request(request)
		_request_agent_decision(request)
		if _frame_probe != null:
			probe_lap_usec = _probe_record_lap("agentDispatchUsec", probe_lap_usec)
			_frame_probe.record(Engine.get_process_frames(), "agentDispatchCount", 1)
	if not requests.is_empty() and not _connected_resident_ids.is_empty():
		var last_resident_id := String(requests.back().get("residentId", ""))
		var last_index := _connected_resident_ids.find(last_resident_id)
		if last_index >= 0:
			_pump_cursor = (last_index + 1) % _connected_resident_ids.size()
	return requests.size()


# 排查计时(A1 探针门控):pump 分段耗时按渲染帧编号累计。
func _probe_record_lap(key: String, lap_started_usec: int) -> int:
	var now_usec := Time.get_ticks_usec()
	_frame_probe.record(Engine.get_process_frames(), key, now_usec - lap_started_usec)
	return now_usec


func _select_dispatchable_requests(
	requests: Array[Dictionary],
	max_requests: int,
	has_pending_avatar_conversation: bool,
) -> Dictionary:
	var selected: Array[Dictionary] = []
	var overflow: Array[Dictionary] = []
	# 容量投影只需要在途 decision_id 集合，不需要复制 wake packet 本体。
	var projected := {}
	for inflight_decision_id: Variant in _inflight:
		var inflight := _inflight.get(inflight_decision_id, {}) as Dictionary
		if bool(inflight.get("superseded", false)):
			continue
		projected[inflight_decision_id] = true
	var projected_ordinary_count := _ordinary_inflight_count()
	var projected_local_count := 0
	var projected_local_ordinary_count := 0
	for inflight_decision_id: Variant in projected:
		var inflight := _inflight.get(inflight_decision_id, {}) as Dictionary
		var inflight_resident_id := String(inflight.get("residentId", ""))
		if not _resident_uses_local_model(inflight_resident_id):
			continue
		projected_local_count += 1
		if not _wake_is_avatar_conversation_turn(
			inflight.get("wakePacket", {}) as Dictionary
		):
			projected_local_ordinary_count += 1
	var request_limit := requests.size()
	if max_requests >= 0:
		request_limit = mini(request_limit, max_requests)
	for request: Dictionary in requests:
		var wake_packet := request.get("wakePacket", {}) as Dictionary
		var decision_id := String(
			wake_packet.get(
				"decision_id",
				"",
			)
		)
		if selected.size() >= request_limit or projected.has(decision_id):
			overflow.append(request)
			continue
		var next_total := projected.size() + 1
		var request_is_ordinary := not _wake_is_avatar_conversation_turn(
			wake_packet
		)
		var next_ordinary_count := (
			projected_ordinary_count
			+ (1 if request_is_ordinary else 0)
		)
		var request_uses_local_model := _resident_uses_local_model(
			String(request.get("residentId", ""))
		)
		var next_local_count := (
			projected_local_count + (1 if request_uses_local_model else 0)
		)
		var next_local_ordinary_count := (
			projected_local_ordinary_count
			+ (1 if request_uses_local_model and request_is_ordinary else 0)
		)
		if (
			next_total > MAX_CONCURRENT_MODEL_REQUESTS
			or next_local_count > MAX_CONCURRENT_LOCAL_MODEL_REQUESTS
			or (
				request_uses_local_model
				and next_local_ordinary_count
				> MAX_CONCURRENT_LOCAL_ORDINARY_REQUESTS
			)
			or (
				not has_pending_avatar_conversation
				and next_ordinary_count
				> MAX_CONCURRENT_MODEL_REQUESTS
				- RESERVED_AVATAR_CONVERSATION_REQUEST_SLOTS
			)
		):
			overflow.append(request)
			continue
		projected[decision_id] = true
		projected_ordinary_count = next_ordinary_count
		projected_local_count = next_local_count
		projected_local_ordinary_count = next_local_ordinary_count
		selected.append(request)
	return {
		"selected": selected,
		"overflow": overflow,
	}


func _resident_uses_local_model(resident_id: String) -> bool:
	var binding := _bindings_by_id.get(resident_id, {}) as Dictionary
	var llm_binding := binding.get("llmBinding", {}) as Dictionary
	return String(llm_binding.get("providerId", "")) in LOCAL_MODEL_PROVIDER_IDS


func _mark_superseded_inflight_for_request(
	request: Dictionary,
) -> void:
	var resident_id := String(request.get("residentId", ""))
	var current_decision_id := String(
		(request.get("wakePacket", {}) as Dictionary).get(
			"decision_id",
			"",
		)
	)
	if resident_id.is_empty() or current_decision_id.is_empty():
		return
	for inflight_decision_value: Variant in _inflight.keys():
		var inflight_decision_id := String(inflight_decision_value)
		var inflight := (
			_inflight.get(inflight_decision_id, {}) as Dictionary
		)
		if (
			String(inflight.get("residentId", "")) == resident_id
			and inflight_decision_id != current_decision_id
		):
			inflight["superseded"] = true
			_inflight[inflight_decision_id] = inflight


func _mark_superseded_inflight_for_pending_requests(
	requests: Array[Dictionary],
) -> void:
	for request in requests:
		var wake := request.get("wakePacket", {}) as Dictionary
		if not _wake_is_avatar_conversation_turn(wake):
			continue
		_mark_superseded_inflight_for_request(request)


func get_connected_resident_names() -> Array[String]:
	var names: Array[String] = []
	for resident_id in _connected_resident_ids:
		names.append(String(_resident_name_by_id.get(resident_id, "")))
	names.sort()
	return names


func get_connected_resident_ids() -> Array[String]:
	return _connected_resident_ids.duplicate()


func get_errors() -> Array[Dictionary]:
	return _errors.duplicate(true)


func clear_errors() -> void:
	_errors.clear()


func get_last_submission(resident_id: String) -> Dictionary:
	return (_last_submissions.get(resident_id, {}) as Dictionary).duplicate(true)


func request_resident_inner_observation(
	resident_id: String,
	request_id: String,
	confirmed_world_revision: int,
	on_complete: Callable,
) -> Dictionary:
	var normalized_resident_id := resident_id.strip_edges()
	var normalized_request_id := request_id.strip_edges()
	if not _session_active or _world == null:
		return _inner_observation_request_failure(
			"AGENT_GATEWAY_SESSION_INACTIVE",
			false,
		)
	if (
		normalized_resident_id.is_empty()
		or not _connected_resident_ids.has(normalized_resident_id)
	):
		return _inner_observation_request_failure(
			"RESIDENT_IDENTITY_NOT_FOUND",
			false,
		)
	if normalized_request_id.is_empty():
		return _inner_observation_request_failure(
			"INNER_OBSERVATION_REQUEST_ID_REQUIRED",
			false,
		)
	if not on_complete.is_valid():
		return _inner_observation_request_failure(
			"INNER_OBSERVATION_CALLBACK_REQUIRED",
			false,
		)
	if _inner_observation_inflight.has(normalized_request_id):
		return _inner_observation_request_failure(
			"INNER_OBSERVATION_REQUEST_DUPLICATE",
			false,
		)
	var snapshot := _public_inner_observation_snapshot(
		normalized_resident_id,
		confirmed_world_revision,
	)
	if snapshot.is_empty():
		return _inner_observation_request_failure(
			"INNER_OBSERVATION_PUBLIC_SNAPSHOT_UNAVAILABLE",
			true,
		)
	var captured_generation := _generation
	_inner_observation_inflight[normalized_request_id] = {
		"residentId": normalized_resident_id,
		"generation": captured_generation,
		"callback": on_complete,
		"snapshot": snapshot.duplicate(true),
	}
	# This is a read-only snapshot of the resident memory already captured above;
	# deliver it in the same call so the inner page never renders an empty
	# generating frame before showing the resident's current thought.
	_deliver_resident_inner_observation(
		normalized_request_id,
		normalized_resident_id,
		captured_generation,
	)
	return _inner_observation_request_accepted(normalized_request_id)


func request_resident_death_story(
	resident_id: String,
	request_id: String,
	on_complete: Callable,
) -> Dictionary:
	var normalized_resident_id := resident_id.strip_edges()
	var normalized_request_id := request_id.strip_edges()
	if not _session_active or _world == null:
		return _death_story_request_failure(
			"AGENT_GATEWAY_SESSION_INACTIVE",
			false,
		)
	if (
		normalized_resident_id.is_empty()
		or not _connected_resident_ids.has(normalized_resident_id)
	):
		return _death_story_request_failure(
			"RESIDENT_IDENTITY_NOT_FOUND",
			false,
		)
	if normalized_request_id.is_empty():
		return _death_story_request_failure(
			"DEATH_STORY_REQUEST_ID_REQUIRED",
			false,
		)
	if not on_complete.is_valid():
		return _death_story_request_failure(
			"DEATH_STORY_CALLBACK_REQUIRED",
			false,
		)
	if _death_story_inflight.has(normalized_request_id):
		return _death_story_request_failure(
			"DEATH_STORY_REQUEST_DUPLICATE",
			false,
		)
	if not _world.has_method("get_resident_state"):
		return _death_story_request_failure(
			"DEATH_STORY_WORLD_SNAPSHOT_UNAVAILABLE",
			true,
		)
	var resident_state := _world.get_resident_state(normalized_resident_id) as Dictionary
	if resident_state.is_empty():
		return _death_story_request_failure(
			"RESIDENT_STATE_UNAVAILABLE",
			true,
		)
	var lifecycle := resident_state.get("lifecycle", {}) as Dictionary
	if bool(lifecycle.get("isDead", false)):
		return _death_story_request_failure("RESIDENT_DEAD", false)
	var resident_name := String(
		_resident_name_by_id.get(normalized_resident_id, "居民"),
	).strip_edges()
	var current_place := String(resident_state.get("currentPlace", "小镇中"))
	var doing := String(resident_state.get("doing", "暂时没有明确动作"))
	var time_text := ""
	if _world.has_method("get_time"):
		time_text = JSON.stringify(_world.get_time())
	var weather := ""
	if _world.has_method("get_weather"):
		weather = String(_world.get_weather())
	var model_request := {
		"request_kind": "resident_death_story",
		"max_tokens": 180,
		"messages": [
			{
				"role": "system",
				"content": "你是小镇居民自己的叙事代理。请根据给出的现场事实，编造一段恐怖、离奇但不血腥的死亡故事。只返回严格 JSON：{\"story\":\"故事文本\"}。故事必须是完整句子，使用中文，24到72个汉字，不得出现省略号、模板占位符、提示词、模型术语，也不要只写‘被杀死’。不要解释 JSON 之外的内容。",
			},
			{
				"role": "user",
				"content": "居民：%s\n地点：%s\n当时正在：%s\n天气：%s\n世界时间：%s\n请写出这名居民最后遭遇的恐怖离奇故事。"
					% [resident_name, current_place, doing, weather, time_text],
			},
		],
	}
	var captured_generation := _generation
	_death_story_inflight[normalized_request_id] = {
		"residentId": normalized_resident_id,
		"generation": captured_generation,
		"callback": on_complete,
	}
	var accepted := _agent_system.request_json_for_resident(
		normalized_resident_id,
		model_request,
		Callable(self, "_deliver_resident_death_story").bind(
			normalized_request_id,
			normalized_resident_id,
			captured_generation,
		),
	) as Dictionary
	if not bool(accepted.get("ok", false)):
		_death_story_inflight.erase(normalized_request_id)
		return _death_story_request_failure(
			"DEATH_STORY_AGENT_REQUEST_REJECTED",
			bool(accepted.get("retryable", false)),
		)
	return _death_story_request_accepted(normalized_request_id)


func _deliver_resident_death_story(
	result: Variant,
	request_id: String,
	resident_id: String,
	captured_generation: int,
) -> void:
	var pending := _death_story_inflight.get(request_id, {}) as Dictionary
	if (
		pending.is_empty()
		or captured_generation != _generation
		or int(pending.get("generation", -1)) != captured_generation
		or String(pending.get("residentId", "")) != resident_id
	):
		return
	_death_story_inflight.erase(request_id)
	var callback := pending.get("callback", Callable()) as Callable
	if not callback.is_valid():
		return
	var story := _normalize_death_story_result(result)
	if story.is_empty():
		callback.call({
			"ok": false,
			"errorCode": "DEATH_STORY_INVALID",
			"retryable": false,
			"errors": ["居民 Agent 没有返回完整死亡故事"],
		})
		return
	callback.call({
		"ok": true,
		"story": story,
		"generatedBy": "resident_agent",
		"requestId": request_id,
	})


func _normalize_death_story_result(result: Variant) -> String:
	if typeof(result) != TYPE_DICTIONARY:
		return ""
	var packet := result as Dictionary
	if packet.get("ok") != true:
		return ""
	var json_value: Variant = packet.get("json")
	if typeof(json_value) != TYPE_DICTIONARY:
		return ""
	var story := String((json_value as Dictionary).get("story", "")).strip_edges()
	for separator in ["\r", "\n", "\t"]:
		story = story.replace(separator, " ")
	while story.contains("  "):
		story = story.replace("  ", " ")
	if (
		story.is_empty()
		or story.length() < 8
		or story.length() > DEATH_STORY_MAX_CHARS
		or story.contains("...")
		or story.contains("…")
	):
		return ""
	var lowered := story.to_lower()
	for forbidden_term: String in DEATH_STORY_FORBIDDEN_TERMS:
		if lowered.contains(forbidden_term):
			return ""
	return story


func _death_story_request_accepted(request_id: String) -> Dictionary:
	return {
		"ok": true,
		"accepted": true,
		"status": "loading",
		"requestId": request_id,
		"errorCode": "",
		"retryable": false,
	}


func _death_story_request_failure(error_code: String, retryable: bool) -> Dictionary:
	return {
		"ok": false,
		"accepted": false,
		"status": "error" if retryable else "rejected",
		"requestId": "",
		"errorCode": error_code,
		"retryable": retryable,
	}


func cancel_resident_inner_observation(request_id: String) -> bool:
	var normalized_request_id := request_id.strip_edges()
	if normalized_request_id.is_empty():
		return false
	return _inner_observation_inflight.erase(normalized_request_id)


func _deliver_resident_inner_observation(
	request_id: String,
	resident_id: String,
	captured_generation: int,
) -> void:
	var pending := _inner_observation_inflight.get(
		request_id,
		{},
	) as Dictionary
	if (
		pending.is_empty()
		or captured_generation != _generation
		or int(pending.get("generation", -1)) != captured_generation
		or String(pending.get("residentId", "")) != resident_id
	):
		return
	_inner_observation_inflight.erase(request_id)
	var callback: Callable = pending.get("callback", Callable())
	if not callback.is_valid():
		return
	var snapshot := (
		pending.get("snapshot", {}) as Dictionary
	).duplicate(true)
	callback.call(
		_inner_observation_ready_result(
			snapshot,
			request_id,
		)
	)


func get_resident_memory(resident_id: String) -> Dictionary:
	if not _session_active:
		return _failure(
			"AGENT_GATEWAY_SESSION_INACTIVE",
			true,
			[{
				"sessionConfigured": not _session_config.is_empty(),
				"restorePending": bool(_session_config.get("restorePending", false)),
				"residentId": resident_id,
			}],
		)
	var result := _agent_system.get_resident_memory(resident_id,) as Dictionary
	if result.get("ok") != true:
		return _normalized_failure(result, "RESIDENT_MEMORY_READ_FAILED")
	var memory := (
		result.get("memory", {}) as Dictionary
	).duplicate(true)
	var relationship_progress: Array = []
	if (
		_world != null
		and _world.has_method(
			"get_resident_public_relationship_progress"
		)
	):
		var progress_result := _world.get_resident_public_relationship_progress(resident_id,) as Dictionary
		if progress_result.get("ok") == true:
			relationship_progress = (
				progress_result.get("items", []) as Array
			).duplicate(true)
	memory["relationship_progress"] = relationship_progress
	result["memory"] = memory
	return result


func apply_resident_memory_intervention(
	resident_id: String,
	request: Dictionary,
) -> Dictionary:
	var normalized_resident_id := resident_id.strip_edges()
	if not _session_active or _world == null:
		return _failure("AGENT_GATEWAY_SESSION_INACTIVE", false)
	if (
		normalized_resident_id.is_empty()
		or not _connected_resident_ids.has(normalized_resident_id)
	):
		return _failure("RESIDENT_IDENTITY_NOT_FOUND", false)
	var memory_key := String(request.get("memoryKey", "")).strip_edges()
	var operation := String(request.get("operation", "")).strip_edges()
	var player_text := String(request.get("playerText", ""))
	var expected_revision: Variant = request.get("expectedRevision", -1)
	if (
		(operation != "write" and memory_key.is_empty())
		or operation not in ["edit", "delete", "write"]
		or typeof(expected_revision) != TYPE_INT
		or int(expected_revision) < 0
	):
		return _failure("RESIDENT_MEMORY_INTERVENTION_INVALID", false)
	if operation == "write" and memory_key.is_empty():
		memory_key = "implant-%s-%d" % [
			normalized_resident_id,
			Time.get_ticks_usec(),
		]
	var world_time: Dictionary = {}
	if _world.has_method("get_time"):
		world_time = (_world.get_time() as Dictionary).duplicate(true)
	if world_time.is_empty():
		return _failure("WORLD_TIME_UNAVAILABLE", true)
	var result := _agent_system.apply_resident_memory_intervention(normalized_resident_id,
		{
			"resident_id": normalized_resident_id,
			"memory_id": memory_key,
			"operation": operation,
			"player_text": player_text,
			"world_time": world_time,
			"expected_revision": int(expected_revision),
		},) as Dictionary
	if not bool(result.get("ok", false)):
		return {
			"ok": false,
			"errorCode": "RESIDENT_MEMORY_INTERVENTION_FAILED",
			"retryable": false,
			"errors": (result.get("errors", []) as Array).duplicate(),
		}
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"revision": int(result.get("revision", 0)),
	}


func get_resident_debug_snapshot(resident_id: String) -> Dictionary:
	if not _session_active or not _connected_resident_ids.has(resident_id):
		return {}
	var snapshot := _agent_system.get_resident_debug_snapshot(resident_id,) as Dictionary
	snapshot["resident_id"] = resident_id
	snapshot["resident_name"] = String(
		_resident_name_by_id.get(resident_id, ""),
	)
	snapshot["binding"] = (
		_bindings_by_id.get(resident_id, {}) as Dictionary
	).duplicate(true)
	snapshot["last_submission"] = (
		_last_submissions.get(resident_id, {}) as Dictionary
	).duplicate(true)
	return snapshot


func get_resident_bindings() -> Array[Dictionary]:
	var bindings: Array[Dictionary] = []
	for identity in _resident_identities:
		var resident_id := String(identity.get("residentId", ""))
		var binding := _bindings_by_id.get(resident_id, {}) as Dictionary
		bindings.append({
			"residentId": resident_id,
			"llmBinding": (
				binding.get("llmBinding", {}) as Dictionary
			).duplicate(true),
		})
	return bindings


func update_resident_bindings(bindings_value: Variant) -> Dictionary:
	if not _session_active:
		return _failure("AGENT_GATEWAY_SESSION_INACTIVE", false)
	var normalized := _normalize_bindings(
		bindings_value,
		_resident_identities,
	)
	if not bool(normalized.get("ok", false)):
		return normalized
	if (
		_provider_service == null
		or not _provider_service.has_method("validate_resident_bindings")
	):
		return _failure("PROVIDER_SERVICE_CONTRACT_MISSING", false)
	var validation := _provider_service.validate_resident_bindings(
		bindings_value,
	) as Dictionary
	if not bool(validation.get("ok", false)):
		return validation
	if (
		_agent_system == null
		or not _agent_system.has_method("replace_resident_model_provider")
	):
		return _failure("AGENT_MODEL_PROVIDER_REBIND_UNSUPPORTED", false)
	var previous := get_resident_bindings()
	var changed_resident_ids: Array[String] = []
	var prepared_providers: Dictionary = {}
	var previous_by_id: Dictionary = {}
	for previous_binding_value: Variant in previous:
		if not previous_binding_value is Dictionary:
			continue
		var previous_binding := previous_binding_value as Dictionary
		previous_by_id[String(previous_binding.get("residentId", ""))] = (
			previous_binding.duplicate(true)
		)
	for identity in _resident_identities:
		var resident_id := String(identity.get("residentId", ""))
		var next_binding := (
			normalized.get("bindingsById", {}) as Dictionary
		).get(resident_id, {}) as Dictionary
		var previous_binding := previous_by_id.get(resident_id, {}) as Dictionary
		if next_binding.get("llmBinding", {}) == previous_binding.get("llmBinding", {}):
			continue
		var provider_result := _provider_service.create_provider_for_resident(
			next_binding,
		) as Dictionary
		if not bool(provider_result.get("ok", false)):
			_restore_resident_model_providers(
				changed_resident_ids,
				previous_by_id,
			)
			return _normalized_failure(
				provider_result,
				"LLM_MODEL_PROVIDER_REBIND_FAILED",
			)
		changed_resident_ids.append(resident_id)
		prepared_providers[resident_id] = provider_result.get("provider")
	for resident_id in changed_resident_ids:
		var replacement := _agent_system.replace_resident_model_provider(
			resident_id,
			prepared_providers[resident_id],
		) as Dictionary
		if not bool(replacement.get("ok", false)):
			_restore_resident_model_providers(
				changed_resident_ids,
				previous_by_id,
			)
			return _normalized_failure(
				replacement,
				"AGENT_MODEL_PROVIDER_REBIND_FAILED",
			)
	_bindings_by_id = (
		normalized.get("bindingsById", {}) as Dictionary
	).duplicate(true)
	var current := get_resident_bindings()
	_session_config["residentBindings"] = current.duplicate(true)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"changed": current != previous,
		"previousBindings": previous,
		"residentBindings": current,
	}


func _restore_resident_model_providers(
	resident_ids: Array[String],
	previous_by_id: Dictionary,
) -> void:
	for resident_id in resident_ids:
		var previous_binding := previous_by_id.get(resident_id, {}) as Dictionary
		if previous_binding.is_empty():
			continue
		var provider_result := _provider_service.create_provider_for_resident(
			previous_binding,
		) as Dictionary
		if not bool(provider_result.get("ok", false)):
			continue
		_agent_system.replace_resident_model_provider(
			resident_id,
			provider_result.get("provider"),
		)


func preflight_replacement_resident(
	identity_value: Variant,
	binding_value: Variant,
	initialization_value: Variant,
) -> Dictionary:
	if not _session_active or _world == null:
		return _failure("AGENT_GATEWAY_SESSION_INACTIVE", false)
	if (
		not identity_value is Dictionary
		or not binding_value is Dictionary
		or not initialization_value is Dictionary
	):
		return _failure("RESIDENT_REPLACEMENT_AGENT_INPUT_INVALID", false)
	var identity := identity_value as Dictionary
	var binding := binding_value as Dictionary
	var initialization := initialization_value as Dictionary
	var resident_id := String(identity.get("residentId", "")).strip_edges()
	var resident_name := String(identity.get("residentName", "")).strip_edges()
	var me := initialization.get("me", {}) as Dictionary
	var initialization_attributes := me.get("attributes", {}) as Dictionary
	if (
		resident_id.is_empty()
		or resident_name.is_empty()
		or not _connected_resident_ids.has(resident_id)
		or String(binding.get("residentId", "")) != resident_id
		or not binding.get("llmBinding", {}) is Dictionary
		or String(me.get("resident_id", "")) != resident_id
		or String(initialization_attributes.get("name", "")) != resident_name
	):
		return _failure("RESIDENT_REPLACEMENT_AGENT_INPUT_INVALID", false)
	var provider_result := _provider_service.create_provider_for_resident(
		binding,
	) as Dictionary
	if not bool(provider_result.get("ok", false)):
		return _normalized_failure(
			provider_result,
			"LLM_MODEL_PROVIDER_CREATION_FAILED",
		)
	if not _agent_system.has_method("validate_resident_replacement"):
		return _failure("AGENT_REPLACEMENT_PREFLIGHT_UNAVAILABLE", false)
	var validated := _agent_system.validate_resident_replacement(
		initialization.duplicate(true),
		provider_result.get("provider"),
		_photo_store,
	) as Dictionary
	if not bool(validated.get("ok", false)):
		return _agent_stage_failure(
			"AGENT_RESIDENT_INITIALIZATION_FAILED",
			"preflight_resident",
			resident_id,
			validated,
		)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"residentId": resident_id,
	}


func admit_replacement_resident(
	identity_value: Variant,
	binding_value: Variant,
) -> Dictionary:
	if not _session_active or _world == null:
		return _failure("AGENT_GATEWAY_SESSION_INACTIVE", false)
	if not identity_value is Dictionary or not binding_value is Dictionary:
		return _failure("RESIDENT_REPLACEMENT_AGENT_INPUT_INVALID", false)
	var identity := (identity_value as Dictionary).duplicate(true)
	var resident_id := String(identity.get("residentId", "")).strip_edges()
	var resident_name := String(identity.get("residentName", "")).strip_edges()
	var binding := (binding_value as Dictionary).duplicate(true)
	if (
		resident_id.is_empty()
		or resident_name.is_empty()
		or not _connected_resident_ids.has(resident_id)
		or String(binding.get("residentId", "")) != resident_id
		or not binding.get("llmBinding", {}) is Dictionary
	):
		return _failure("RESIDENT_REPLACEMENT_AGENT_INPUT_INVALID", false)
	var initialization := _world.get_agent_initialization_by_id(resident_id) as Dictionary
	if initialization.is_empty():
		return _failure("WORLD_AGENT_INITIALIZATION_MISSING", false)
	var provider_result := _provider_service.create_provider_for_resident(
		binding,
	) as Dictionary
	if not bool(provider_result.get("ok", false)):
		return _normalized_failure(
			provider_result,
			"LLM_MODEL_PROVIDER_CREATION_FAILED",
		)
	var initialized := _agent_system.replace_resident(
		initialization,
		provider_result.get("provider"),
		_photo_store,
	) as Dictionary
	if not bool(initialized.get("ok", false)):
		return _agent_stage_failure(
			"AGENT_RESIDENT_INITIALIZATION_FAILED",
			"initialize_resident",
			resident_id,
			initialized,
		)
	for identity_index in _resident_identities.size():
		if String(_resident_identities[identity_index].get("residentId", "")) == resident_id:
			_resident_identities[identity_index] = identity
			break
	_resident_identities.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("residentId", "")) < String(b.get("residentId", ""))
	)
	binding["residentName"] = resident_name
	_bindings_by_id[resident_id] = binding
	_rebuild_identity_maps()
	_session_config["residentIdentities"] = _resident_identities.duplicate(true)
	_session_config["residentBindings"] = get_resident_bindings()
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"changed": true,
		"residentId": resident_id,
		"residentCount": _connected_resident_ids.size(),
	}


func get_debug_inflight_count() -> int:
	return _inflight.size()


func get_agent_save_participant() -> RefCounted:
	return _agent_system


func prepare_departure_messages(
	departure_id: String,
	max_candidates: int,
	on_complete: Callable,
) -> Dictionary:
	if not _session_active:
		return _failure("AGENT_GATEWAY_SESSION_INACTIVE", false)
	return _agent_system.prepare_departure_messages(departure_id,
		max_candidates,
		on_complete,) as Dictionary


func can_attach_photo_for_resident(resident_id: String) -> bool:
	var normalized_id := resident_id.strip_edges()
	if normalized_id.is_empty() or not _bindings_by_id.has(normalized_id):
		return false
	return _binding_supports_photo(
		_bindings_by_id[normalized_id] as Dictionary
	)


func stage_conversation_photo(
	resident_id: String,
	path: String,
) -> Dictionary:
	var normalized_id := resident_id.strip_edges()
	if not _session_active:
		return _failure("AGENT_GATEWAY_SESSION_INACTIVE", false)
	if not can_attach_photo_for_resident(normalized_id):
		return _failure("PHOTO_CAPABILITY_UNAVAILABLE", false)
	return _photo_store.stage_file(path,
		normalized_id,) as Dictionary


func has_staged_conversation_photo(
	resident_id: String,
	ref: String,
	mime_type: String,
) -> bool:
	return bool(_photo_store.has_staged_photo(ref,
		mime_type,
		resident_id.strip_edges(),))


func prepare_conversation_photo_commit(
	resident_id: String,
	ref: String,
	mime_type: String,
) -> bool:
	return bool(_photo_store.prepare_photo_commit(ref,
		mime_type,
		resident_id.strip_edges(),))


func commit_conversation_photo(
	resident_id: String,
	ref: String,
	mime_type: String,
) -> bool:
	return bool(_photo_store.commit_photo(ref,
		mime_type,
		resident_id.strip_edges(),))


func discard_staged_conversation_photo(
	resident_id: String,
	ref: String,
) -> bool:
	return bool(_photo_store.discard_staged_photo(ref,
		resident_id.strip_edges(),))


func resolve_conversation_photo_preview(
	ref: String,
	mime_type: String,
) -> Dictionary:
	return _photo_store.resolve_photo_preview(ref,
		mime_type,) as Dictionary


func get_photo_store_audit_snapshot() -> Dictionary:
	return _photo_store.audit_snapshot() as Dictionary


func get_agent_save_context() -> Dictionary:
	return _agent_system.get_save_context() as Dictionary


func hydrate_agent_restore(
	agent_participant: Object,
	session_config: Dictionary,
	resident_ids: Array,
) -> Dictionary:
	if agent_participant != _agent_system or _world == null:
		return _failure("SESSION_CONTINUE_HYDRATOR_CONTEXT_INVALID", false)
	if not bool(_session_config.get("restorePending", false)):
		return _failure("SESSION_CONTINUE_HYDRATOR_CONTEXT_INVALID", false)
	if (
		String(session_config.get("sessionId", ""))
		!= String(_session_config.get("sessionId", ""))
	):
		return _failure("SESSION_CONTINUE_HYDRATOR_CONTEXT_INVALID", false)
	var expected_ids := _connected_resident_ids.duplicate()
	var requested_ids: Array[String] = []
	for value: Variant in resident_ids:
		var resident_id := String(value).strip_edges()
		if resident_id.is_empty() or requested_ids.has(resident_id):
			return _failure("SESSION_CONTINUE_IDENTITY_MISMATCH", false)
		requested_ids.append(resident_id)
	requested_ids.sort()
	if requested_ids != expected_ids:
		return _failure("SESSION_CONTINUE_IDENTITY_MISMATCH", false)
	for resident_id in requested_ids:
		var initialization := _world.get_agent_initialization_by_id(resident_id,) as Dictionary
		if initialization.is_empty():
			return _failure("WORLD_AGENT_INITIALIZATION_MISSING", false, [{
				"residentId": resident_id,
			}])
		var binding := _bindings_by_id.get(resident_id, {}) as Dictionary
		var provider_result := _provider_service.create_provider_for_resident(binding,) as Dictionary
		if not bool(provider_result.get("ok", false)):
			return _normalized_failure(
				provider_result,
				"LLM_MODEL_PROVIDER_CREATION_FAILED",
			)
		var hydrated := _agent_system.hydrate_restored_resident(initialization,
			provider_result.get("provider"),
			_photo_store,) as Dictionary
		if not bool(hydrated.get("ok", false)):
			return _agent_stage_failure(
				"SESSION_CONTINUE_AGENT_HYDRATE_FAILED",
				"hydrate_restored_resident",
				resident_id,
				hydrated,
			)
	_session_active = true
	_session_config["restorePending"] = false
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"residentCount": requested_ids.size(),
	}


func close_session() -> Dictionary:
	_generation += 1
	_inflight.clear()
	_decision_attempts.clear()
	_inner_observation_inflight.clear()
	_death_story_inflight.clear()
	_pump_cursor = 0
	_session_active = false
	_world = null
	_connected_resident_ids.clear()
	_photo_store.clear()
	return _agent_system.close_game() as Dictionary


func discard_unpublished_new_game(
	restore_photo_blocker: bool = false,
) -> Dictionary:
	var context := _save_context.duplicate(true)
	var had_active_session := _session_active
	var photo_discard := _photo_store.discard_unpublished_session(restore_photo_blocker,) as Dictionary
	if not bool(photo_discard.get("ok", false)):
		return _normalized_failure(
			photo_discard,
			"PHOTO_STORAGE_UNAVAILABLE",
		)
	_generation += 1
	_inflight.clear()
	_decision_attempts.clear()
	_inner_observation_inflight.clear()
	_death_story_inflight.clear()
	_pump_cursor = 0
	_session_active = false
	_world = null
	_connected_resident_ids.clear()
	_photo_store.clear()
	_agent_system.close_game()
	if context.is_empty():
		return {"ok": true, "errorCode": "", "retryable": false, "changed": false}
	if not had_active_session:
		_save_context.clear()
		return {"ok": true, "errorCode": "", "retryable": false, "changed": false}
	var deleted := _agent_system.delete_game(context) as Dictionary
	if not bool(deleted.get("ok", false)):
		return _agent_stage_failure(
			"AGENT_NEW_GAME_DISCARD_FAILED",
			"delete_game",
			"",
			deleted,
		)
	_save_context.clear()
	return {"ok": true, "errorCode": "", "retryable": false, "changed": true}


func _public_inner_observation_snapshot(
	resident_id: String,
	confirmed_world_revision: int,
) -> Dictionary:
	if (
		_world == null
		or not _world.has_method("get_world_revision")
		or not _world.has_method("get_resident_state")
	):
		return {}
	var current_revision := int(_world.get_world_revision())
	if confirmed_world_revision < 0:
		return {}
	# Inner observation is a read-only current snapshot. The town may advance
	# between the menu click and this deferred read, so a newer confirmed World
	# revision is valid and must not make the page intermittently unavailable.
	var state := _world.get_resident_state(resident_id) as Dictionary
	if state.is_empty():
		return {}
	var memory_result := get_resident_memory(resident_id)
	if not bool(memory_result.get("ok", false)):
		return {}
	var memory_value: Variant = memory_result.get("memory")
	if not memory_value is Dictionary:
		return {}
	var memory := memory_value as Dictionary
	return {
		"residentId": resident_id,
		"displayName": String(
			_resident_name_by_id.get(resident_id, "")
		).strip_edges(),
		"confirmedWorldRevision": current_revision,
		"currentThought": _inner_observation_player_text(
			memory.get("current_inner_thought"),
			INNER_OBSERVATION_MAX_CURRENT_FOCUS_CHARS,
		),
		"nextPlan": _inner_observation_player_text(
			memory.get("next_plan"),
			INNER_OBSERVATION_MAX_CURRENT_FOCUS_CHARS,
		),
		"reasonBasis": (memory.get("public_basis", []) as Array).duplicate(),
	}


func _inner_observation_ready_result(
	snapshot: Dictionary,
	request_id: String,
) -> Dictionary:
	var current_thought := _inner_observation_player_text(
		snapshot.get("currentThought"),
		INNER_OBSERVATION_MAX_CURRENT_FOCUS_CHARS,
	)
	current_thought = _inner_observation_complete_excerpt(
		current_thought,
		INNER_OBSERVATION_CURRENT_THOUGHT_DISPLAY_CHARS,
	)
	var next_plan := _inner_observation_player_text(
		snapshot.get("nextPlan"),
		INNER_OBSERVATION_MAX_CURRENT_FOCUS_CHARS,
	)
	next_plan = _inner_observation_complete_excerpt(
		next_plan,
		INNER_OBSERVATION_NEXT_PLAN_DISPLAY_CHARS,
	)
	var monologue_parts: Array[String] = []
	var seen := {}
	_append_unique_inner_paragraph(monologue_parts, seen, current_thought)
	_append_unique_inner_paragraph(monologue_parts, seen, next_plan)
	var empty := monologue_parts.is_empty()
	var reason_text := ""
	if not empty:
		reason_text = _first_distinct_inner_reason(
			snapshot.get("reasonBasis", []),
			seen,
			monologue_parts,
		)
	return {
		"residentId": String(snapshot.get("residentId", "")),
		"requestId": request_id,
		"status": "ready",
		"content": {
			"contentKind": "resident_current_focus",
			"monologueText": "\n\n".join(monologue_parts),
			"reasonText": reason_text,
			"playerStatusText": (
				"此刻似乎没有特别在意的事。"
				if empty
				else ""
			),
			"empty": empty,
			"fallbackUsed": false,
		},
		"errorCode": "",
		"retryable": false,
	}


func _append_unique_inner_paragraph(
	target: Array[String],
	seen: Dictionary,
	text: String,
) -> void:
	var normalized := text.strip_edges()
	if normalized.is_empty():
		return
	var key := normalized.to_lower().replace(" ", "").replace("\n", "")
	if seen.has(key):
		return
	seen[key] = true
	target.append(normalized)


func _first_distinct_inner_reason(
	values: Variant,
	seen: Dictionary,
	monologue_parts: Array[String],
) -> String:
	if typeof(values) != TYPE_ARRAY:
		return ""
	# public_basis 已按时间从新到旧排列。原因只取当前最相关的一条，
	# 不再把记忆状态和整份历史列表暴露给玩家。
	for value: Variant in values as Array:
		var text := _inner_observation_player_text(
			value,
			INNER_OBSERVATION_MAX_CURRENT_FOCUS_CHARS,
		)
		text = _inner_observation_complete_excerpt(
			text,
			INNER_OBSERVATION_REASON_DISPLAY_CHARS,
		)
		var key := text.to_lower().replace(" ", "").replace("\n", "")
		if (
			not text.is_empty()
			and not seen.has(key)
			and _inner_reason_matches_monologue(text, monologue_parts)
		):
			return text
	return ""


func _inner_reason_matches_monologue(
	reason_text: String,
	monologue_parts: Array[String],
) -> bool:
	var reason_key := _inner_observation_relation_key(reason_text)
	if reason_key.length() < 2:
		return false
	for paragraph: String in monologue_parts:
		var paragraph_key := _inner_observation_relation_key(paragraph)
		if paragraph_key.is_empty():
			continue
		if reason_key.contains(paragraph_key) or paragraph_key.contains(reason_key):
			return true
		var shared_pairs := {}
		for index: int in range(reason_key.length() - 1):
			var pair := reason_key.substr(index, 2)
			if paragraph_key.contains(pair):
				shared_pairs[pair] = true
				if shared_pairs.size() >= 2:
					return true
	return false


func _inner_observation_relation_key(text: String) -> String:
	var result := text.to_lower().strip_edges()
	for separator: String in [
		" ",
		"\t",
		"\r",
		"\n",
		"，",
		"。",
		"！",
		"？",
		"：",
		"；",
		",",
		".",
		"!",
		"?",
		":",
		";",
		"“",
		"”",
		"\"",
		"'",
	]:
		result = result.replace(separator, "")
	return result


func _inner_observation_complete_excerpt(
	text: String,
	maximum_characters: int,
) -> String:
	var normalized := text.strip_edges()
	if normalized.length() <= maximum_characters:
		return normalized
	# 只在完整句子边界收短内容，不用省略号掩盖被截断的半句话。
	var last_sentence_end := -1
	for index: int in range(mini(normalized.length(), maximum_characters)):
		if "。！？!?；;".contains(normalized.substr(index, 1)):
			last_sentence_end = index + 1
	if last_sentence_end > 0:
		return normalized.left(last_sentence_end).strip_edges()
	# 单句本身很长时也要受显示上限约束，避免固定面板被一整句撑开。
	var bounded_characters := maxi(1, maximum_characters - 1)
	return normalized.left(bounded_characters).strip_edges() + "…"


func _inner_observation_player_text(
	value: Variant,
	maximum_characters: int,
) -> String:
	if typeof(value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return ""
	var text := String(value).strip_edges()
	for separator in ["\r", "\n", "\t"]:
		text = text.replace(separator, " ")
	while text.contains("  "):
		text = text.replace("  ", " ")
	if text.is_empty() or text.length() > maximum_characters:
		return ""
	var lowered := text.to_lower()
	for forbidden_term: String in INNER_OBSERVATION_FORBIDDEN_PLAYER_TERMS:
		if lowered.contains(forbidden_term):
			return ""
	return text


func _inner_observation_request_accepted(request_id: String) -> Dictionary:
	return {
		"ok": true,
		"accepted": true,
		"status": "loading",
		"requestId": request_id,
		"errorCode": "",
		"retryable": false,
	}


func _inner_observation_request_failure(
	error_code: String,
	retryable: bool,
) -> Dictionary:
	return {
		"ok": false,
		"accepted": false,
		"status": "error" if retryable else "rejected",
		"requestId": "",
		"errorCode": error_code,
		"retryable": retryable,
	}


func _request_agent_decision(request: Dictionary) -> void:
	var resident_id := String(request.get("residentId", ""))
	var resident_name := String(request.get("residentName", ""))
	var wake := request.get("wakePacket", {}) as Dictionary
	var decision_id := String(wake.get("decision_id", ""))
	var fallback_applied := false
	if (
		resident_id.is_empty()
		or decision_id.is_empty()
		or not _connected_resident_ids.has(resident_id)
	):
		_record_error(
			resident_id,
			resident_name,
			decision_id,
			"AGENT_DECISION_REQUEST_INVALID",
			false,
		)
		_redispatch(resident_id, decision_id)
		return
	if _world != null and _world.has_method("refresh_pending_decision_request_by_id"):
		var latest_request := _world.refresh_pending_decision_request_by_id(
			resident_id,
			decision_id,
		) as Dictionary
		if not bool(latest_request.get("ok", false)):
			# 优先级事件可能已经替换了这份 pending 请求；旧快照不能交给 Provider。
			_redispatch(resident_id, decision_id)
			return
		wake = (latest_request.get("wakePacket", {}) as Dictionary).duplicate(true)
	var generation := _generation
	var attempt := int(_decision_attempts.get(decision_id, 0)) + 1
	_decision_attempts[decision_id] = attempt
	_count_request_metric("providerDispatch")
	_inflight[decision_id] = {
		"residentId": resident_id,
		"generation": generation,
		"attempt": attempt,
		# take_pending_decision_requests 已交付独占拷贝，这里直接持有。
		"wakePacket": wake,
		"startedAtMsec": Time.get_ticks_msec(),
	}
	if not debug_decision_dispatched.get_connections().is_empty():
		debug_decision_dispatched.emit({
			"residentId": resident_id,
			"residentName": resident_name,
			"decisionId": decision_id,
			"attempt": attempt,
			"wakePacket": wake.duplicate(true),
			"startedAtMsec": Time.get_ticks_msec(),
		})
	var accepted := _agent_system.request_decision(resident_id,
		wake.duplicate(true),
		_on_agent_result.bind(
			resident_id,
			resident_name,
			decision_id,
			generation,
		),) as Dictionary
	if bool(accepted.get("ok", false)):
		return
	_inflight.erase(decision_id)
	var accepted_errors: Array = []
	if accepted.get("errors") is Array:
		accepted_errors = (accepted.get("errors") as Array).duplicate(true)
	var should_retry := (
		bool(accepted.get("retryable", false))
		and attempt < MAX_DECISION_ATTEMPTS
	)
	if should_retry:
		_set_agent_decision_retry_feedback(
			resident_id,
			decision_id,
			accepted_errors,
		)
		_redispatch(resident_id, decision_id)
	else:
		fallback_applied = _submit_continuity_fallback(
			resident_id,
			resident_name,
			decision_id,
			wake,
			"AGENT_DECISION_REQUEST_REJECTED",
		)
	_record_error(
		resident_id,
		resident_name,
		decision_id,
		"AGENT_DECISION_REQUEST_REJECTED",
		bool(accepted.get("retryable", false)),
		{
			"agentErrors": accepted_errors,
			"attempt": attempt,
			"recoveredByFallback": fallback_applied,
			"final": not should_retry and not fallback_applied,
		},
	)
	if not debug_decision_completed.get_connections().is_empty():
		debug_decision_completed.emit({
			"residentId": resident_id,
			"residentName": resident_name,
			"decisionId": decision_id,
			"ok": fallback_applied,
			"ignored": fallback_applied,
			"recovered": fallback_applied,
			"wakePacket": wake.duplicate(true),
			"agentResult": accepted.duplicate(true),
		})


func _on_agent_result(
	result: Dictionary,
	resident_id: String,
	resident_name: String,
	decision_id: String,
	generation: int,
) -> void:
	_count_request_metric("providerComplete")
	if generation != _generation:
		return
	var inflight := _inflight.get(decision_id, {}) as Dictionary
	if (
		inflight.is_empty()
		or int(inflight.get("generation", -1)) != generation
		or String(inflight.get("residentId", "")) != resident_id
	):
		return
	var superseded := bool(inflight.get("superseded", false))
	_inflight.erase(decision_id)
	if superseded or bool(result.get("stale", false)):
		_decision_attempts.erase(decision_id)
		if not debug_decision_completed.get_connections().is_empty():
			debug_decision_completed.emit({
				"residentId": resident_id,
				"residentName": resident_name,
				"decisionId": decision_id,
				"ok": true,
				"ignored": true,
				"stale": true,
				"superseded": superseded,
				"wakePacket": (
					inflight.get("wakePacket", {}) as Dictionary
				).duplicate(true),
				"agentResult": result.duplicate(true),
			})
		return
	if not bool(result.get("ok", false)):
		var diagnostic := _provider_service.get_latest_diagnostic(resident_id,) as Dictionary
		var agent_errors_value: Variant = result.get("errors", [])
		if agent_errors_value is Array:
			diagnostic["agent_errors"] = (
				agent_errors_value as Array
			).duplicate(true)
		if String(diagnostic.get("error_type", "")).is_empty():
			diagnostic["error_type"] = "agent_runtime"
			diagnostic["retryable"] = false
		var error_type := String(diagnostic.get("error_type", ""))
		var error_code := (
			"AGENT_RESPONSE_TIMEOUT"
			if error_type == "timeout"
			else "AGENT_DECISION_REQUEST_FAILED"
		)
		var attempt := int(inflight.get("attempt", 1))
		var inflight_wake := (
			inflight.get("wakePacket", {}) as Dictionary
		)
		var should_retry := _decision_result_should_retry(
			attempt,
			diagnostic,
			inflight_wake,
		)
		var has_contract_feedback := (
			diagnostic.get("agent_errors") is Array
			and not (diagnostic.get("agent_errors") as Array).is_empty()
			and String(diagnostic.get("error_type", "")) not in [
				"billing",
				"authentication",
				"configuration",
				"request_validation",
			]
		)
		diagnostic["attempt"] = attempt
		# 合同错误即使到达重试上限，只要后面的 continuity fallback 能接住，
		# 也属于已恢复的内部事件，不应冒充不可恢复运行错误。Provider 鉴权、
		# 存档或 World 装配等没有 Agent 合同反馈的故障仍保留 final=true。
		diagnostic["recoveredByFallback"] = not should_retry and has_contract_feedback
		diagnostic["final"] = not should_retry and not has_contract_feedback
		_record_error(
			resident_id,
			resident_name,
			decision_id,
			error_code,
			bool(diagnostic.get("retryable", true)),
			diagnostic,
		)
		var fallback_applied := false
		if should_retry:
			_set_agent_decision_retry_feedback(
				resident_id,
				decision_id,
				(
					diagnostic.get("agent_errors", []) as Array
					if diagnostic.get("agent_errors") is Array
					else []
				),
				String(diagnostic.get("error_type", "")),
			)
			_redispatch(resident_id, decision_id)
		else:
			fallback_applied = _submit_continuity_fallback(
				resident_id,
				resident_name,
				decision_id,
				inflight_wake,
				error_code,
			)
		if not debug_decision_completed.get_connections().is_empty():
			debug_decision_completed.emit({
				"residentId": resident_id,
				"residentName": resident_name,
				"decisionId": decision_id,
				"ok": should_retry or fallback_applied,
				"ignored": should_retry or fallback_applied,
				"recovered": fallback_applied,
				"wakePacket": (
					inflight.get("wakePacket", {}) as Dictionary
				).duplicate(true),
				"agentResult": result.duplicate(true),
				"diagnostic": diagnostic.duplicate(true),
			})
		return
	_decision_attempts.erase(decision_id)
	_clear_nonfinal_decision_errors(decision_id)
	var decision := result.get("decision", {}) as Dictionary
	var probe_submission_started_usec := (
		Time.get_ticks_usec()
		if OS.get_environment("AI_TOWN_UI_FRAME_PROBE") == "1"
		else 0
	)
	var submission := _world.submit_agent_decision_by_id(resident_id,
		decision.duplicate(true),) as Dictionary
	if probe_submission_started_usec > 0:
		print("AGENT_PROBE decision=%s action=%s stage=world_submit_decision usec=%d frame=%d" % [
			decision_id,
			String(decision.get("action", {}).get("type", "")),
			Time.get_ticks_usec() - probe_submission_started_usec,
			Engine.get_process_frames(),
		])
	var decision_consumed := _world_consumed_agent_decision(submission)
	var decision_accepted := bool(submission.get("ok", false))
	# A consumed rejection has already queued an authoritative World result for
	# this action. Keep the Agent-side pending intention until that result is
	# ingested, otherwise the evidence layer cannot pair the rejection with the
	# resident's original intent. Only roll back when World did not consume the
	# decision and therefore cannot produce a matching result.
	if not decision_accepted and not decision_consumed:
		_discard_unconfirmed_agent_decision(
			resident_id,
			resident_name,
			decision_id,
			decision,
		)
	var social_response := decision.get(
		"social_response",
		{},
	) as Dictionary
	if decision_consumed:
		_finish_social_candidates_from_wake(
			inflight.get("wakePacket", {}) as Dictionary,
			resident_id,
			String(social_response.get("matter_id", "")),
			"request_cancelled",
		)
	_last_submissions[resident_id] = submission.duplicate(true)
	var recoverable_submission_rejection := (
		_is_recoverable_submission_rejection(submission)
	)
	if not debug_decision_completed.get_connections().is_empty():
		debug_decision_completed.emit({
			"residentId": resident_id,
			"residentName": resident_name,
			"decisionId": decision_id,
			"ok": (
				bool(submission.get("ok", false))
				or bool(submission.get("stale", false))
				or recoverable_submission_rejection
			),
			"ignored": (
				bool(submission.get("stale", false))
				or recoverable_submission_rejection
			),
			"wakePacket": (
				inflight.get("wakePacket", {}) as Dictionary
			).duplicate(true),
			"agentResult": result.duplicate(true),
			"worldSubmission": submission.duplicate(true),
		})
	if (
		not bool(submission.get("ok", false))
		and not bool(submission.get("stale", false))
		and not decision_consumed
	):
		var submission_error_code := String(
			submission.get("errorCode", "")
		).strip_edges()
		if submission_error_code.is_empty():
			submission_error_code = "WORLD_AGENT_DECISION_REJECTED"
		# The snapshot was valid when the model was dispatched, but the live
		# world may have changed while the request was in flight (for example,
		# a nearby conversation target walked away or the resident arrived at
		# the requested place). Preserve the rejection as evidence, then resume
		# the resident's current life instead of leaving it decision-pending.
		if recoverable_submission_rejection:
			_submit_continuity_fallback(
				resident_id,
				resident_name,
				decision_id,
				inflight.get("wakePacket", {}) as Dictionary,
				submission_error_code,
			)
		else:
			_record_error(
				resident_id,
				resident_name,
				decision_id,
				submission_error_code,
				bool(submission.get("retryable", false)),
				{
					"submission": submission.duplicate(true),
					"final": true,
				},
			)
			_submit_continuity_fallback(
				resident_id,
				resident_name,
				decision_id,
				inflight.get("wakePacket", {}) as Dictionary,
				submission_error_code,
			)


func _is_recoverable_submission_rejection(submission: Dictionary) -> bool:
	var error_code := String(submission.get("errorCode", "")).strip_edges()
	if error_code in [
		"WORK_TASK_REQUIRED",
		"ACTION_NOT_CONTINUABLE",
		"CURRENT_ACTION_MISSING",
		"ACTIVITY_RESERVATION_CONFLICT",
		"ACTIVITY_NO_EXECUTABLE_SLOT",
	]:
		return true
	var errors_value: Variant = submission.get("errors", [])
	if not errors_value is Array:
		return false
	for value: Variant in errors_value as Array:
		var message := String(value).strip_edges()
		if (
			message.contains("当前没有需要处理的真实职业任务")
			or message.contains("没有可以继续的当前动作")
		):
			return true
	return false


func _decision_result_should_retry(
	attempt: int,
	diagnostic: Dictionary,
	wake: Dictionary,
) -> bool:
	if attempt >= MAX_DECISION_ATTEMPTS:
		return false
	if bool(diagnostic.get("retryable", false)):
		return true
	# A contract-invalid or malformed model output is not a World decision yet.
	# Give it one fresh request against the same authoritative snapshot instead
	# of immediately making the resident enter a visible continuity wait.
	var error_type := String(diagnostic.get("error_type", ""))
	var agent_errors: Variant = diagnostic.get("agent_errors", [])
	if (
		agent_errors is Array
		and not (agent_errors as Array).is_empty()
		and error_type not in [
			"billing",
			"authentication",
			"configuration",
			"request_validation",
		]
	):
		return true
	if error_type in [
		"invalid_decision_json",
		"output_truncated",
		"empty_content",
		"missing_message",
		"missing_choice",
		"invalid_choice",
	]:
		return true
	# A conversation turn must either receive one fresh model attempt or end
	# with the existing visible, natural fallback.
	return _wake_requires_conversation_turn(wake)


func _set_agent_decision_retry_feedback(
	resident_id: String,
	decision_id: String,
	error_values: Array,
	error_type := "",
) -> void:
	if (
		not _agent_system.has_method(
			"set_decision_retry_feedback",
		)
	):
		return
	var lines: Array[String] = []
	if error_type in [
		"invalid_decision_json",
		"output_truncated",
		"empty_content",
		"missing_message",
		"missing_choice",
		"invalid_choice",
	]:
		lines.append(
			"- 上次回复不是完整、可解析的单个 JSON 对象；请重新生成完整 JSON，不要附加说明文字"
		)
	for value: Variant in error_values:
		var line := String(value).strip_edges()
		if line.is_empty() or lines.has(line):
			continue
		if line.contains("答话作出了对话后的行动承诺"):
			lines.append(
				"- 只有当前 conversation_follow_up_options 中存在合法选项时才能承诺后续行动；否则只完成答话，不要写行动承诺"
			)
		lines.append("- %s" % line.left(240))
		if lines.size() >= 6:
			break
	if lines.is_empty():
		return
	_agent_system.set_decision_retry_feedback(resident_id,
		decision_id,
		"\n".join(lines),)


func _clear_nonfinal_decision_errors(decision_id: String) -> void:
	if decision_id.is_empty() or _errors.is_empty():
		return
	var retained: Array[Dictionary] = []
	for error: Dictionary in _errors:
		if (
			String(error.get("decisionId", "")) == decision_id
			and not bool(error.get("final", false))
		):
			continue
		retained.append(error)
	_errors = retained


func _round_robin_requests(
	requests: Array[Dictionary],
) -> Array[Dictionary]:
	if requests.size() <= 1 or _connected_resident_ids.is_empty():
		return requests
	var result: Array[Dictionary] = []
	var consumed := {}
	for offset in _connected_resident_ids.size():
		var resident_id := _connected_resident_ids[
			(_pump_cursor + offset) % _connected_resident_ids.size()
		]
		for index in requests.size():
			if consumed.has(index):
				continue
			if String(requests[index].get("residentId", "")) == resident_id:
				result.append(requests[index])
				consumed[index] = true
	for index in requests.size():
		if not consumed.has(index):
			result.append(requests[index])
	return result


func _prioritize_conversation_requests(
	requests: Array[Dictionary],
) -> Array[Dictionary]:
	if requests.size() <= 1:
		return requests
	var avatar_conversation_requests: Array[Dictionary] = []
	var conversation_requests: Array[Dictionary] = []
	var ordinary_requests: Array[Dictionary] = []
	for request in requests:
		var wake := request.get("wakePacket", {}) as Dictionary
		if _wake_is_avatar_conversation_turn(wake):
			avatar_conversation_requests.append(request)
		elif _wake_requires_conversation_turn(wake):
			conversation_requests.append(request)
		else:
			ordinary_requests.append(request)
	avatar_conversation_requests.append_array(conversation_requests)
	avatar_conversation_requests.append_array(ordinary_requests)
	return avatar_conversation_requests


func _ordinary_inflight_count() -> int:
	var count := 0
	for inflight_value: Variant in _inflight.values():
		if not inflight_value is Dictionary:
			continue
		if bool((inflight_value as Dictionary).get("superseded", false)):
			continue
		var wake := (
			(inflight_value as Dictionary).get("wakePacket", {}) as Dictionary
		)
		if not _wake_is_avatar_conversation_turn(wake):
			count += 1
	return count


func _wake_is_avatar_conversation_turn(wake: Dictionary) -> bool:
	if not _wake_requires_conversation_turn(wake):
		return false
	var snapshot_value: Variant = wake.get("snapshot")
	if not snapshot_value is Dictionary:
		return false
	var conversation_value: Variant = (
		snapshot_value as Dictionary
	).get("conversation")
	if not conversation_value is Dictionary:
		return false
	var conversation := conversation_value as Dictionary
	return String(
		conversation.get("with_resident_id", ""),
	) == _avatar_person_id


func _wake_requires_conversation_turn(wake: Dictionary) -> bool:
	for event_value: Variant in wake.get("events", []) as Array:
		if not event_value is Dictionary:
			continue
		if String((event_value as Dictionary).get("type", "")) in [
			"搭话",
			"对方答话",
		]:
			return true
	return false


func _submit_continuity_fallback(
	resident_id: String,
	resident_name: String,
	decision_id: String,
	wake: Dictionary,
	source_error_code: String,
) -> bool:
	var snapshot := wake.get("snapshot", {}) as Dictionary
	var conversation: Dictionary = {}
	var conversation_value: Variant = snapshot.get("conversation")
	if conversation_value is Dictionary:
		conversation = (conversation_value as Dictionary).duplicate(true)
	var reply_conversation_id := ""
	for event_index in range(
		(wake.get("events", []) as Array).size() - 1,
		-1,
		-1,
	):
		var event_value: Variant = (wake.get("events", []) as Array)[event_index]
		if not event_value is Dictionary:
			continue
		var event := event_value as Dictionary
		if String(event.get("type", "")) in ["搭话", "对方答话"]:
			reply_conversation_id = String(event.get("conversation_id", ""))
			break
	var decision := {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": {
			"action_id": "%s-continuity" % decision_id,
			"type": "待着",
			"line": "我先停一停，看看周围再作打算。",
		},
	}
	var post_injury_reaction := (
		snapshot.get("post_injury_reaction", {}) as Dictionary
		if snapshot.get("post_injury_reaction") is Dictionary
		else {}
	)
	if bool(post_injury_reaction.get("required", false)):
		var current_place := String(
			(snapshot.get("place", {}) as Dictionary).get("name", "")
		).strip_edges()
		decision["action"] = (
			{
				"action_id": "%s-continuity-injury-rest" % decision_id,
				"type": "待着",
				"line": "我先在诊所缓一缓，看看伤势。",
			}
			if current_place == "诊所"
			else {
				"action_id": "%s-continuity-injury-clinic" % decision_id,
				"type": "去",
				"place": "诊所",
				"line": "我得先去诊所看看伤势。",
			}
		)
	elif not reply_conversation_id.is_empty() and not conversation.is_empty():
		decision["action"] = {
			"action_id": "%s-continuity-reply" % decision_id,
			"type": "答话",
			"conversation_id": reply_conversation_id,
			"say": "抱歉，我刚才没听清。我们改天再聊吧。",
			"narration": "我歉意地点点头，先离开了。",
			"photos": [],
			"end": true,
		}
	else:
		var current_action: Variant = (
			snapshot.get("me", {}) as Dictionary
		).get("current_action")
		var current_action_id := (
			String((current_action as Dictionary).get("action_id", ""))
			if current_action is Dictionary
			else ""
		)
		if (
			current_action is Dictionary
			and not current_action_id.ends_with("-continuity")
		):
			decision = {
				"decision_id": decision_id,
				"handling": "continue_current",
			}
		else:
			var world_action := _continuity_world_action(
				snapshot,
				decision_id,
			)
			if not world_action.is_empty():
				decision["action"] = world_action
			elif current_action is Dictionary:
				decision = {
					"decision_id": decision_id,
					"handling": "continue_current",
				}
	var submission := _world.submit_agent_decision_by_id(resident_id,
		decision,) as Dictionary
	_last_submissions[resident_id] = submission.duplicate(true)
	_decision_attempts.erase(decision_id)
	var world_consumed := _world_consumed_agent_decision(submission)
	if world_consumed:
		_finish_social_candidates_from_wake(
			wake,
			resident_id,
			"",
			(
				"provider_timeout"
				if source_error_code == "AGENT_RESPONSE_TIMEOUT"
				else "provider_failed"
			),
		)
	_record_error(
		resident_id,
		resident_name,
		decision_id,
		(
			"AGENT_CONTINUITY_FALLBACK_APPLIED"
			if world_consumed
			else "AGENT_CONTINUITY_FALLBACK_DEFERRED"
		),
		false,
		{
			"sourceErrorCode": source_error_code,
			"submissionOk": bool(submission.get("ok", false)),
			"stale": bool(submission.get("stale", false)),
		},
	)
	if not world_consumed and not bool(submission.get("stale", false)):
		_redispatch(resident_id, decision_id)
	return world_consumed


func _finish_social_candidates_from_wake(
	wake: Dictionary,
	resident_id: String,
	responded_matter_id: String,
	reason: String,
) -> void:
	if _world == null:
		return
	for matter_value: Variant in (
		(wake.get("snapshot", {}) as Dictionary).get(
			"social_matters",
			[],
		) as Array
	):
		var matter := matter_value as Dictionary
		if (matter.get("options", []) as Array).is_empty():
			continue
		var matter_id := String(matter.get("matter_id", ""))
		if (
			matter_id.is_empty()
			or matter_id == responded_matter_id
		):
			continue
		_world.mark_social_candidate_terminal(matter_id,
			resident_id,
			reason,
			(
				String(matter.get("response_round_id", ""))
				if matter.get("response_round_id") is String
				else ""
			),)


func _world_consumed_agent_decision(submission: Dictionary) -> bool:
	if bool(submission.get("stale", false)):
		return false
	if submission.get("consumed") is bool:
		return bool(submission.get("consumed"))
	return String(submission.get("errorCode", "")) not in [
		"WORLD_NOT_RUNNING",
		"WORLD_PAUSED",
	]


func _discard_unconfirmed_agent_decision(
	resident_id: String,
	resident_name: String,
	decision_id: String,
	decision: Dictionary,
) -> void:
	if not _agent_system.has_method("discard_unconfirmed_decision"):
		return
	var discarded := _agent_system.discard_unconfirmed_decision(resident_id,
		decision.duplicate(true),) as Dictionary
	if discarded.get("ok") == true:
		return
	_record_error(
		resident_id,
		resident_name,
		decision_id,
		"AGENT_UNCONFIRMED_DECISION_DISCARD_FAILED",
		false,
		{
			"agentErrors": (
				(discarded.get("errors", []) as Array).duplicate(true)
				if discarded.get("errors") is Array
				else []
			),
		},
	)


func _continuity_world_action(
	snapshot: Dictionary,
	decision_id: String,
) -> Dictionary:
	var place := snapshot.get("place", {}) as Dictionary
	var activity_candidates: Array[Dictionary] = []
	for activity_value: Variant in place.get("activities", []) as Array:
		if not activity_value is Dictionary:
			continue
		var activity := activity_value as Dictionary
		var activity_id := String(
			activity.get("activity_id", "")
		).strip_edges()
		if activity_id.is_empty():
			continue
		activity_candidates.append({
			"activity_id": activity_id,
			"label": String(activity.get("label", "")).strip_edges(),
		})
	if not activity_candidates.is_empty():
		var activity := activity_candidates[
			posmod(decision_id.hash(), activity_candidates.size())
		] as Dictionary
		var activity_label := String(activity.get("label", "手头的事情"))
		return {
			"action_id": "%s-continuity-activity" % decision_id,
			"type": "做活动",
			"activity_id": String(activity.get("activity_id", "")),
			"line": "我先%s。" % activity_label,
		}
	var candidates: Array[Dictionary] = []
	for prop_value: Variant in place.get("props", []) as Array:
		if not prop_value is Dictionary:
			continue
		var prop := prop_value as Dictionary
		var prop_name := String(prop.get("name", "")).strip_edges()
		if prop_name.is_empty():
			continue
		for verb_value: Variant in prop.get("verbs", []) as Array:
			var verb := String(verb_value).strip_edges()
			if verb.is_empty():
				continue
			candidates.append({
				"prop": prop_name,
				"verb": verb,
			})
	if candidates.is_empty():
		return {}
	# World has already removed occupied or unreachable activity slots from
	# snapshot.place.props. Vary the deterministic pick by decision so repeated
	# continuity does not make every resident use the first prop forever.
	var candidate := candidates[
		posmod(decision_id.hash(), candidates.size())
	] as Dictionary
	var prop_name := String(candidate.get("prop", ""))
	var verb := String(candidate.get("verb", ""))
	return {
		"action_id": "%s-continuity-prop" % decision_id,
		"type": "用道具",
		"prop": prop_name,
		"verb": verb,
		"line": "我先去%s。" % verb,
	}


func _redispatch(resident_id: String, decision_id: String) -> void:
	if _world == null or resident_id.is_empty() or decision_id.is_empty():
		return
	_world.redispatch_decision_request_by_id(resident_id, decision_id)


func _record_error(
	resident_id: String,
	resident_name: String,
	decision_id: String,
	error_code: String,
	retryable: bool,
	diagnostic: Dictionary = {},
) -> void:
	_error_sequence += 1
	_errors.append({
		"errorSequence": _error_sequence,
		"residentId": resident_id,
		"residentName": resident_name,
		"decisionId": decision_id,
		"errorCode": error_code,
		"retryable": retryable,
		"final": bool(diagnostic.get("final", false)),
		"diagnostic": diagnostic.duplicate(true),
		"generation": _generation,
	})
	while _errors.size() > MAX_ERROR_HISTORY:
		_errors.pop_front()


func _normalize_identities(value: Variant) -> Dictionary:
	if not value is Array:
		return _failure("SESSION_RESIDENT_IDENTITIES_INVALID", false)
	var residents: Array[Dictionary] = []
	var ids: Dictionary = {}
	for identity_value: Variant in value as Array:
		if not identity_value is Dictionary:
			return _failure("SESSION_RESIDENT_IDENTITIES_INVALID", false)
		var identity := identity_value as Dictionary
		var resident_id := String(identity.get("residentId", "")).strip_edges()
		var resident_name := String(identity.get("residentName", "")).strip_edges()
		if (
			resident_id.is_empty()
			or resident_name.is_empty()
			or ids.has(resident_id)
		):
			return _failure("SESSION_RESIDENT_IDENTITIES_INVALID", false)
		ids[resident_id] = true
		residents.append({
			"residentId": resident_id,
			"residentName": resident_name,
		})
	residents.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("residentId", "")) < String(b.get("residentId", ""))
	)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"residents": residents,
	}


func _normalize_bindings(value: Variant, identities: Array[Dictionary]) -> Dictionary:
	if not value is Array:
		return _failure("SESSION_LLM_BINDINGS_INVALID", false)
	var expected: Dictionary = {}
	for identity in identities:
		expected[String(identity.get("residentId", ""))] = String(identity.get("residentName", ""))
	var bindings_by_id: Dictionary = {}
	for binding_value: Variant in value as Array:
		if not binding_value is Dictionary:
			return _failure("SESSION_LLM_BINDINGS_INVALID", false)
		var binding := binding_value as Dictionary
		var resident_id := String(binding.get("residentId", ""))
		var resident_name := String(binding.get("residentName", ""))
		var expected_name := String(expected.get(resident_id, ""))
		if (
			not expected.has(resident_id)
			or (
				not resident_name.is_empty()
				and expected_name != resident_name
			)
			or bindings_by_id.has(resident_id)
			or not binding.get("llmBinding", {}) is Dictionary
		):
			return _failure("SESSION_LLM_BINDINGS_INVALID", false)
		# Published session configs intentionally persist only the stable Agent
		# routing identity (residentId + llmBinding). Rehydrate the presentation
		# name from the already validated resident identity contract on Continue.
		var normalized_binding := binding.duplicate(true)
		normalized_binding["residentName"] = expected_name
		bindings_by_id[resident_id] = normalized_binding
	if bindings_by_id.size() != identities.size():
		return _failure("SESSION_LLM_BINDINGS_INVALID", false)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"bindingsById": bindings_by_id,
	}


func _binding_supports_photo(binding: Dictionary) -> bool:
	var llm := binding.get("llmBinding", {}) as Dictionary
	var provider_id := String(llm.get("providerId", "")).strip_edges()
	var model_id := String(llm.get("modelId", "")).strip_edges()
	if (
		provider_id.is_empty()
		or model_id.is_empty()
		or _provider_service == null
		or not _provider_service.has_method("list_available_models")
	):
		return false
	var capability_values: Array = []
	for model_value: Variant in _provider_service.list_available_models() as Array:
		if not model_value is Dictionary:
			continue
		var model := model_value as Dictionary
		if (
			String(model.get("providerId", model.get("provider_id", "")))
			!= provider_id
			or String(model.get("modelId", model.get("id", ""))) != model_id
		):
			continue
		for field_name: String in [
			"inputModalities",
			"input_modalities",
			"capabilities",
		]:
			var value: Variant = model.get(field_name, [])
			if value is Array:
				capability_values.append_array((value as Array).duplicate())
			elif value is Dictionary:
				for key: Variant in (value as Dictionary).keys():
					if bool((value as Dictionary).get(key, false)):
						capability_values.append(key)
		break
	for value: Variant in capability_values:
		if String(value).strip_edges().to_lower() in [
			"image",
			"photo_understanding",
			"image_understanding",
			"vision",
			"multimodal",
		]:
			return true
	return false


func _rebuild_identity_maps() -> void:
	_resident_name_by_id.clear()
	_resident_id_by_name.clear()
	for identity in _resident_identities:
		var resident_id := String(identity.get("residentId", ""))
		var resident_name := String(identity.get("residentName", ""))
		_resident_name_by_id[resident_id] = resident_name


func _cancel_new_game() -> void:
	if _agent_system.has_method("cancel_new_game"):
		_agent_system.cancel_new_game()


func _agent_stage_failure(
	error_code: String,
	stage: String,
	resident_id := "",
	agent_result: Dictionary = {},
) -> Dictionary:
	var detail := {"stage": stage}
	if not resident_id.is_empty():
		detail["residentId"] = resident_id
	var agent_errors: Variant = agent_result.get("errors", [])
	if agent_errors is Array and not (agent_errors as Array).is_empty():
		detail["agentErrors"] = (agent_errors as Array).duplicate(true)
	return _failure(error_code, false, [detail])


func _normalized_failure(result: Dictionary, fallback_code: String) -> Dictionary:
	var normalized := result.duplicate(true)
	normalized["ok"] = false
	if String(normalized.get("errorCode", "")).is_empty():
		normalized["errorCode"] = fallback_code
	normalized["retryable"] = bool(normalized.get("retryable", false))
	return normalized


func _missing_methods(target: Object, methods: Array[String]) -> Array[String]:
	var missing: Array[String] = []
	if target == null:
		return methods.duplicate()
	for method in methods:
		if not target.has_method(method):
			missing.append(method)
	return missing


func _failure(error_code: String, retryable: bool, errors: Array = []) -> Dictionary:
	return RESULT_SHAPES.failure_with(error_code, retryable, errors)
