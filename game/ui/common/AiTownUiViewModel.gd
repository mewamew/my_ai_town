class_name AiTownUiViewModel
extends RefCounted


const VALID_OPERATION_STATUSES: Array[String] = [
	"idle",
	"loading",
	"success",
	"rejected",
	"error",
	"disabled",
]


static func validate(view_model: Dictionary, component_name: String = "UI component") -> PackedStringArray:
	var issues := PackedStringArray()
	var scope_value: Variant = view_model.get("scope")
	if (
		typeof(scope_value) not in [TYPE_STRING, TYPE_STRING_NAME]
		or (scope_value as String).is_empty()
		or scope_value != (scope_value as String).strip_edges()
	):
		issues.append("%s.scope 必须是非空字符串" % component_name)
	var status_value: Variant = view_model.get("status")
	if (
		typeof(status_value) not in [TYPE_STRING, TYPE_STRING_NAME]
		or (status_value as String).is_empty()
		or status_value != (status_value as String).strip_edges()
	):
		issues.append("%s.status 必须是非空字符串" % component_name)
	if typeof(view_model.get("data", {})) != TYPE_DICTIONARY:
		issues.append("%s.data 必须是 Dictionary" % component_name)
	if typeof(view_model.get("actions", {})) != TYPE_DICTIONARY:
		issues.append("%s.actions 必须是 Dictionary" % component_name)
	var revision_value: Variant = view_model.get("revision", 0)
	if typeof(revision_value) != TYPE_INT or int(revision_value) < 0:
		issues.append("%s.revision 必须是非负整数" % component_name)
	var operation_value: Variant = view_model.get("operation", null)
	if typeof(operation_value) != TYPE_DICTIONARY:
		issues.append("%s.operation 必须是 Dictionary" % component_name)
	else:
		var operation := operation_value as Dictionary
		var operation_status_value: Variant = operation.get("status")
		if (
			typeof(operation_status_value) not in [
				TYPE_STRING,
				TYPE_STRING_NAME,
			]
			or not VALID_OPERATION_STATUSES.has(
				operation_status_value as String
			)
		):
			issues.append(
				"%s.operation.status 无效" % component_name
			)
		var request_id_value: Variant = operation.get("requestId", "")
		if typeof(request_id_value) != TYPE_STRING and typeof(request_id_value) != TYPE_STRING_NAME:
			issues.append("%s.operation.requestId 必须是字符串" % component_name)
	var error_value: Variant = view_model.get("error", null)
	if error_value != null and typeof(error_value) != TYPE_DICTIONARY:
		issues.append("%s.error 必须是 null 或 Dictionary" % component_name)
	elif typeof(error_value) == TYPE_DICTIONARY:
		var error_data := error_value as Dictionary
		if typeof(error_data.get("code")) not in [TYPE_STRING, TYPE_STRING_NAME]:
			issues.append("%s.error.code 必须是字符串" % component_name)
		if typeof(error_data.get("message")) not in [TYPE_STRING, TYPE_STRING_NAME]:
			issues.append("%s.error.message 必须是字符串" % component_name)
		if typeof(error_data.get("retryable")) != TYPE_BOOL:
			issues.append("%s.error.retryable 必须是布尔值" % component_name)
	return issues


static func scope(view_model: Dictionary) -> StringName:
	var value: Variant = view_model.get("scope")
	if typeof(value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return &""
	return StringName(value)


static func revision(view_model: Dictionary) -> int:
	var value: Variant = view_model.get("revision")
	if typeof(value) != TYPE_INT or int(value) < 0:
		return -1
	return value as int


static func accepts_revision(
	current_revision: Variant,
	view_model: Dictionary,
) -> bool:
	if typeof(current_revision) != TYPE_INT or int(current_revision) < -1:
		return false
	var incoming_revision := revision(view_model)
	return incoming_revision >= 0 and incoming_revision >= int(current_revision)


static func data(view_model: Dictionary) -> Dictionary:
	var value: Variant = view_model.get("data")
	if not value is Dictionary:
		return {}
	return (value as Dictionary).duplicate(true)


static func data_for_render(
	view_model: Dictionary,
	last_confirmed_data: Dictionary
) -> Dictionary:
	var incoming_data := data(view_model)
	if operation_status(view_model) == &"rejected" and incoming_data.is_empty():
		return last_confirmed_data.duplicate(true)
	return incoming_data


static func operation(view_model: Dictionary) -> Dictionary:
	var value: Variant = view_model.get("operation", {})
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return (value as Dictionary).duplicate(true)


# 只读取单个字段时不做整个 operation 字典的深拷贝。
static func _operation_field(view_model: Dictionary, field: String) -> Variant:
	var value: Variant = view_model.get("operation", {})
	if typeof(value) != TYPE_DICTIONARY:
		return null
	return (value as Dictionary).get(field)


static func operation_status(view_model: Dictionary) -> StringName:
	var value: Variant = _operation_field(view_model, "status")
	if typeof(value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return &""
	return StringName(value)


static func operation_request_id(view_model: Dictionary) -> String:
	var value: Variant = _operation_field(view_model, "requestId")
	if typeof(value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return ""
	return value as String


static func action(view_model: Dictionary, action_key: String) -> Dictionary:
	var actions_value: Variant = view_model.get("actions")
	if not actions_value is Dictionary:
		return {}
	var actions := actions_value as Dictionary
	var value: Variant = actions.get(action_key, {})
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return (value as Dictionary).duplicate(true)


static func action_enabled(action_data: Dictionary) -> bool:
	return (
		not action_data.is_empty()
		and typeof(action_data.get("enabled")) == TYPE_BOOL
		and action_data.get("enabled") == true
	)


static func disabled_reason(action_data: Dictionary) -> String:
	var value: Variant = action_data.get(
		"disabledReason",
		action_data.get("disabled_reason"),
	)
	if typeof(value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return ""
	return value as String


static func player_reason(reason: Variant) -> String:
	if typeof(reason) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return ""
	var normalized := (reason as String).strip_edges()
	if normalized.is_empty():
		return ""
	match normalized:
		"ACTION_DISABLED", "ACTION_NOT_AVAILABLE", \
		"ACTION_NOT_AVAILABLE_IN_MODE", \
		"ACTION_NOT_AVAILABLE_IN_CAPTURED_VIEW_MODEL":
			return "当前操作暂不可用"
		"REQUEST_ALREADY_SUBMITTED", "DUPLICATE_REQUEST_PENDING", \
		"OPERATION_IN_FLIGHT", "SAVE_CREATE_ALREADY_PENDING":
			return "操作正在进行，请稍候"
		"OCCUPATION_SERVICE_UNSTAFFED":
			return "对应岗位当前无人可执行，这项服务已经暂停"
		"SESSION_SAVE_NO_PUBLISHED_REVISION":
			return "当前没有可用的完整存档"
		"SESSION_SAVE_CORRUPT":
			return "这个存档已损坏，无法直接进入"
		"SESSION_SAVE_INCOMPLETE":
			return "上次保存未完成，将使用最近的完整存档"
		"SESSION_SAVE_STORE_READ_FAILED":
			return "存档目录暂时无法读取，请稍后重试"
		"SESSION_SAVE_STORE_WRITE_FAILED":
			return "存档暂时无法写入，请稍后重试"
		"SESSION_SAVE_STORE_JSON_INVALID":
			return "存档索引损坏，请检查后重试"
		"SESSION_SAVE_SLOT_BUSY":
			return "存档正在使用，请稍候"
		"SESSION_SAVE_CONTEXT_INVALID":
			return "存档信息不完整，请重新选择"
		"SESSION_CONTINUE_FAILED":
			return "无法继续游戏，请稍后重试"
		"SESSION_BOOTSTRAP_FAILED", "SESSION_TOWN_RUNTIME_MISSING":
			return "小镇暂时无法启动，当前选择已保留"
		"SESSION_OPENING_CONFIG_INVALID":
			return "新游戏配置不完整，请检查后重试"
		"SESSION_SAVE_NOT_AVAILABLE", \
		"SESSION_SAVE_REQUIRES_ACTIVE_SESSION":
			return "当前小镇暂时无法保存"
		"FORMAL_SESSION_CATALOG_MISSING":
			return "居民资料尚未准备好"
		"STARTUP_NEW_GAME_NOT_READY":
			return "新游戏入口尚未准备好"
		"STARTUP_SAVE_CATALOG_UNAVAILABLE", \
		"STARTUP_SAVE_CATALOG_CONTRACT_INVALID":
			return "存档列表暂不可用"
		"STARTUP_SAVE_SLOT_ID_INVALID":
			return "所选存档槽位不可用"
		"SESSION_SAVE_INTERFACE_MISSING", \
		"SESSION_SAVE_SERVICE_NOT_BOUND", \
		"SESSION_SAVE_SERVICE_NOT_CONFIGURED", \
		"AGENT_SAVE_INTERFACE_MISSING":
			return "存档服务尚未准备好"
		"STARTUP_OVERWRITE_SLOT_EMPTY":
			return "空槽位不需要覆盖"
		"STARTUP_OVERWRITE_SLOT_CONFIRMATION_UNAVAILABLE":
			return "当前槽位暂不能覆盖"
		"FORMAL_SLOT_ARCHIVE_STORE_FAILED":
			return "存档暂时无法处理，请稍后重试"
		"FORMAL_SLOT_ARCHIVE_BUSY":
			return "存档正在使用，请稍候"
		"FORMAL_SLOT_ARCHIVE_CONTEXT_INVALID":
			return "存档信息不完整，无法继续"
		"FORMAL_SLOT_ARCHIVE_SAVE_CHANGED":
			return "存档已发生变化，请重新选择"
		"FORMAL_SLOT_ARCHIVE_PENDING_MARK_FAILED", \
		"FORMAL_SLOT_ARCHIVE_LEASE_RELEASE_FAILED":
			return "存档处理未完成，请稍后重试"
		"FORMAL_SLOT_ARCHIVE_RECOVERY_PENDING":
			return "存档恢复仍在进行，请稍候"
		"FORMAL_SLOT_OVERWRITE_COMPENSATION_REQUIRED":
			return "上一次存档替换未完成，请先恢复后重试"
		"WORLD_DATA_INCOMPLETE":
			return "小镇数据尚未准备好，请稍后重试"
		"TOWN_RUNTIME_SCENE_UNAVAILABLE":
			return "小镇场景暂不可用，请稍后重试"
		"TOWN_RUNTIME_STARTUP_RESULT_MISSING":
			return "小镇启动结果缺失，请稍后重试"
		"RESIDENT_DIRECT_SELECTION_REQUIRED":
			return "请直接在地图中选择居民"
		"RESIDENT_IDENTITY_UNAVAILABLE", "RESIDENT_IDENTITY_NOT_FOUND":
			return "居民资料暂不可用"
		"RESIDENT_DETAIL_INTERFACE_MISSING":
			return "居民状态暂不可查看"
		"RESIDENT_RELATIONSHIP_PUBLIC_INTERFACE_MISSING":
			return "居民关系暂不可查看"
		"RESIDENT_MEMORY_PUBLIC_INTERFACE_MISSING":
			return "居民记忆暂不可查看"
		"INNER_OBSERVATION_INTERFACE_MISSING", \
		"AGENT_INNER_OBSERVATION_INTERFACE_MISSING", \
		"INNER_OBSERVATION_TEMPORARILY_UNAVAILABLE":
			return "内心观察暂不可用"
		"RESIDENT_VIEW_NOT_PAUSED":
			return "正在准备居民查看"
		"NO_ACTIVE_EVENT":
			return "当前没有可查看的事件"
		"NO_RETRYABLE_ERROR":
			return "当前没有可重试的操作"
		"PLACE_FOCUS_CONTENT_NOT_FORMAL_READY", \
		"PLACE_FOCUS_PLACE_NOT_FOUND":
			return "地点资料暂不可用"
		"PLACE_LOG_NOT_AVAILABLE":
			return "这里暂时没有公开日志"
		"PLACE_HAS_NO_INTERIOR":
			return "这里没有可进入的室内"
		"PLACE_OBSERVATION_INTERFACE_MISSING":
			return "室内观察暂不可用"
		"OBSERVER_MODE_REQUIRED":
			return "请先返回观察模式"
		"ROUTE_NOT_CONNECTED":
			return "这个入口暂不可用"
		"RESIDENT_EDITOR_MOUNTING_NOT_AUTHORIZED":
			return "居民总览暂不可用"
		"PLACE_INTERACTABLE_REQUIRES_INDOOR_ENTRY":
			return "进入室内后才能查看"
		"TOWN_LOG_INTERFACE_MISSING":
			return "小镇日志暂不可用"
		"CAUSAL_CHAIN_NOT_AVAILABLE":
			return "这条记录没有可查看的前因后果"
		"INDOOR_UI_INTERFACE_MISSING":
			return "室内资料暂不可用"
		"PROVIDER_SETTINGS_SERVICE_NOT_BOUND":
			return "模型设置暂不可用"
		"PROVIDER_API_KEY_REQUIRED":
			return "请先保存 API Key"
		"PROVIDER_MODEL_SELECTION_REQUIRED":
			return "请先选择居民模型"
		"PROVIDER_HEALTH_CHECK_REQUIRED":
			return "配置已更新，请重新检查连接"
		"PROVIDER_HEALTH_INTERFACE_MISSING", \
		"PROVIDER_HEALTH_UNAVAILABLE", \
		"PROVIDER_HEALTH_QUERY_FAILED", \
		"PROVIDER_CATALOG_UNAVAILABLE":
			return "模型服务状态暂不可用"
		"PROVIDER_AUTH_FAILED":
			return "API Key 认证失败，请检查后重试"
		"PROVIDER_TIMEOUT", "PROVIDER_NETWORK_UNAVAILABLE", \
		"PROVIDER_CONNECTION_FAILED":
			return "无法连接模型服务，请检查网络后重试"
		"LLM_PROVIDER_UNAVAILABLE":
			return "所选模型服务当前不可用"
		"LLM_MODEL_UNAVAILABLE", "LLM_MODEL_UNKNOWN", \
		"NO_AVAILABLE_MODEL":
			return "所选模型当前不可用，请重新选择"
		"PROVIDER_FORMAL_RUNTIME_REQUIRED":
			return "模型服务尚未完成正式配置"
		"RESIDENT_MODEL_ASSIGNMENT_START_FAILED", \
		"SESSION_LLM_BINDINGS_INVALID":
			return "居民模型分配尚未完成，请检查后重试"
		"WEATHER_CONTROL_INTERFACE_MISSING":
			return "天气控制暂不可用"
		"SIMULATION_SPEED_INTERFACE_MISSING":
			return "时间速度控制暂不可用"
		"TOWN_UI_ROUTE_HOST_NOT_CONNECTED":
			return "页面入口暂不可用"
		"WORLD_NOT_RUNNING":
			return "小镇尚未开始运行"
		_:
			return (
				"当前操作暂不可用"
				if _looks_like_internal_reason(normalized)
				else normalized
			)


static func _looks_like_internal_reason(value: String) -> bool:
	if value.is_empty():
		return false
	for index in range(value.length()):
		var codepoint := value.unicode_at(index)
		if (
			(codepoint >= 65 and codepoint <= 90)
			or (codepoint >= 48 and codepoint <= 57)
			or codepoint == 95
		):
			continue
		return false
	return true


static func error_message(view_model: Dictionary) -> String:
	var error_value: Variant = view_model.get("error", null)
	if typeof(error_value) != TYPE_DICTIONARY:
		return ""
	var error := error_value as Dictionary
	var message_value: Variant = error.get(
		"playerMessage",
		error.get("message"),
	)
	var code_value: Variant = error.get("code", error.get("errorCode"))
	var message := (
		(message_value as String).strip_edges()
		if typeof(message_value) in [TYPE_STRING, TYPE_STRING_NAME]
		else ""
	)
	var code := (
		code_value as String
		if typeof(code_value) in [TYPE_STRING, TYPE_STRING_NAME]
		else ""
	)
	if message.is_empty() or message == code:
		return player_reason(code)
	return message


static func public_error_message(view_model: Dictionary) -> String:
	var error_value: Variant = view_model.get("error", null)
	if typeof(error_value) != TYPE_DICTIONARY:
		return ""
	var error := error_value as Dictionary
	var message_value: Variant = error.get(
		"playerMessage",
		error.get("message"),
	)
	if typeof(message_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return ""
	var message := (message_value as String).strip_edges()
	var code_value: Variant = error.get("code", error.get("errorCode"))
	var code := (
		(code_value as String).strip_edges()
		if typeof(code_value) in [TYPE_STRING, TYPE_STRING_NAME]
		else ""
	)
	if (
		message.is_empty()
		or message == code
		or _looks_like_internal_reason(message)
	):
		return ""
	return message


static func public_operation_error_message(
	error: Dictionary,
	fallback: String = "当前操作暂不可用"
) -> String:
	var code_value: Variant = error.get("code", error.get("errorCode"))
	var code := (
		(code_value as String).strip_edges()
		if typeof(code_value) in [TYPE_STRING, TYPE_STRING_NAME]
		else ""
	)
	if error.has("playerMessage"):
		var public_message := public_error_message({
			"error": {
				"code": code,
				"playerMessage": error.get("playerMessage"),
			},
		})
		if not public_message.is_empty():
			return public_message
	var mapped_message := player_reason(code)
	if not mapped_message.is_empty() and mapped_message != code:
		return mapped_message
	return fallback


static func idle_operation() -> Dictionary:
	return {
		"requestId": "",
		"intent": "",
		"status": "idle",
		"submittedAtMsec": 0,
		"completedAtMsec": 0,
	}


static func make_action(intent: String, enabled: bool, disabled_reason := "") -> Dictionary:
	return {
		"intent": intent,
		"enabled": enabled,
		"disabledReason": "" if enabled else disabled_reason,
	}


static func request_id(prefix: String, sequence: int) -> String:
	return "%s-%06d" % [prefix, sequence]


static func envelope(
	scope: String,
	status: String,
	revision: int,
	data: Dictionary,
	actions: Dictionary,
	operation: Dictionary,
	error: Dictionary,
) -> Dictionary:
	return {
		"scope": scope,
		"status": status,
		"revision": revision,
		"data": data.duplicate(true),
		"actions": actions.duplicate(true),
		"operation": operation.duplicate(true),
		"error": null if error.is_empty() else error.duplicate(true),
	}


static func rect_to_array(rect: Rect2) -> Array:
	return [
		rect.position.x,
		rect.position.y,
		rect.size.x,
		rect.size.y,
	]


static func dispatch_result(
	ok: bool,
	accepted: bool,
	request_id: String,
	error_code: String,
	retryable: bool,
	changed := false,
) -> Dictionary:
	return {
		"ok": ok,
		"accepted": accepted,
		"requestId": request_id,
		"errorCode": error_code,
		"retryable": retryable,
		"changed": changed,
	}


static func world_revision(world: Object) -> int:
	if world != null and world.has_method("get_world_revision"):
		return int(world.get_world_revision())
	return 0
