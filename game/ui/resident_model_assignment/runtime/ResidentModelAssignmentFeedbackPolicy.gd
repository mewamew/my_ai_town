class_name ResidentModelAssignmentFeedbackPolicy
extends RefCounted


const UI_VIEW_MODEL := preload("res://ui/common/AiTownUiViewModel.gd")


const PROVIDER_CONFIGURATION_ERRORS: Array[String] = [
	"SESSION_LLM_BINDINGS_INVALID",
	"LLM_PROVIDER_UNAVAILABLE",
	"LLM_MODEL_UNAVAILABLE",
	"LLM_MODEL_UNKNOWN",
	"PROVIDER_HEALTH_UNAVAILABLE",
	"PROVIDER_HEALTH_QUERY_FAILED",
	"PROVIDER_CATALOG_UNAVAILABLE",
	"PROVIDER_AUTO_REFRESH_EXHAUSTED",
]


static func error_message(error_code: String) -> String:
	match error_code:
		"RESIDENT_MODEL_ASSIGNMENT_REVISION_STALE":
			return "页面数据已更新，请按最新状态继续操作。"
		"RESIDENT_MODEL_ASSIGNMENT_DRAFT_INCOMPLETE", "SESSION_DRAFT_INVALID":
			return "仍有居民未完成有效模型绑定，草稿已保留。"
		"SESSION_LLM_BINDINGS_INVALID", "SESSION_LLM_PROVIDER_REQUIRED", "SESSION_LLM_MODEL_REQUIRED":
			return "当前模型连接不可用，系统已尝试自动迁移但没有找到可用模型，草稿已保留。"
		"PROVIDER_HEALTH_UNAVAILABLE", "PROVIDER_HEALTH_QUERY_FAILED", "PROVIDER_HEALTH_SNAPSHOT_INVALID", "PROVIDER_CATALOG_UNAVAILABLE", "PROVIDER_MODEL_CATALOG_INVALID", "PROVIDER_MODEL_CATALOG_DUPLICATED", "PROVIDER_HEALTH_CATALOG_INVALID", "PROVIDER_HEALTH_CATALOG_DUPLICATED", "PROVIDER_FORMAL_RUNTIME_REQUIRED", "LLM_PROVIDER_UNAVAILABLE", "LLM_MODEL_UNAVAILABLE", "LLM_MODEL_UNKNOWN":
			return "目标 Provider 或模型当前不可用，原绑定与草稿已保留。"
		"SESSION_SAVE_MANIFEST_PUBLISH_FAILED", "SESSION_SAVE_STORE_WRITE_FAILED":
			return "新存档修订尚未发布，原存档和草稿未变，请检查磁盘后重试。"
		"OFFLINE_RESIDENT_MODEL_REBIND_TARGET_STALE":
			return "存档已被其他流程更新，原存档和草稿未变；请返回加载页重新选择。"
		"SESSION_DRAFT_SCHEMA_UNSUPPORTED", "SESSION_DRAFT_SOURCE_INVALID", "SESSION_DRAFT_REVISION_INVALID", "SESSION_DRAFT_SLOTS_INVALID", "SESSION_DRAFT_SLOT_INVALID", "SESSION_RESIDENT_COUNT_OUT_OF_RANGE", "SESSION_HOME_SPACE_COUNT_MISMATCH", "SESSION_HOME_SPACE_REQUIRED", "SESSION_HOME_SPACE_UNKNOWN", "SESSION_HOME_SPACE_DUPLICATED", "SESSION_HOME_SPACE_MISSING", "SESSION_RESIDENT_ID_REQUIRED", "SESSION_RESIDENT_ID_UNKNOWN", "SESSION_RESIDENT_ID_DUPLICATED", "SESSION_LLM_BINDING_INVALID":
			return "居民选择草稿无效，未进入模型分配；原草稿未被修改。"
		"RESIDENT_MODEL_ASSIGNMENT_BATCH_EMPTY":
			return "请先在批量模式选择至少一位居民。"
	return "操作未完成，已保留最近一次确认数据。"


static func save_slot_error(
	message: String,
	error_code: String,
	route_mode: String,
) -> String:
	if (
		not ResidentModelAssignmentRouteMode.is_save_slot(route_mode)
		or not PROVIDER_CONFIGURATION_ERRORS.has(error_code)
	):
		return message
	return "%s 草稿已保留；可点击“返回模型配置”修复连接。" % message


static func operation_failure_copy(
	view_model: Dictionary,
	route_mode: String,
	fallback: String,
) -> String:
	var error_value: Variant = view_model.get("error")
	var error_code := (
		String((error_value as Dictionary).get("code", ""))
		if error_value is Dictionary
		else ""
	)
	var message := UI_VIEW_MODEL.error_message(view_model)
	if message.is_empty():
		message = fallback
	return save_slot_error(message, error_code, route_mode)


static func provider_settings_available(
	view_model: Dictionary,
	route_mode: String,
) -> bool:
	if not ResidentModelAssignmentRouteMode.is_save_slot(route_mode):
		return false
	var error_value: Variant = view_model.get("error")
	if not error_value is Dictionary:
		return false
	return PROVIDER_CONFIGURATION_ERRORS.has(
		String((error_value as Dictionary).get("code", "")),
	)


static func completion_copy(
	route_mode: String,
	return_to_provider_settings: bool,
	resident_count: int,
) -> Dictionary:
	var count := maxi(resident_count, 1)
	var primary := "全部居民的模型均已配置完成"
	var secondary := "现在可以开始游戏。"
	var confirm := "开始游戏"
	if ResidentModelAssignmentRouteMode.is_single_resident(route_mode):
		primary = "这位新居民的模型已经配置完成"
		secondary = "确认后会立即进入小镇。"
		confirm = "确认入镇"
	elif return_to_provider_settings:
		primary = "居民模型分配已更新"
		secondary = "确认后返回模型设置。"
		confirm = "确认并返回"
	elif ResidentModelAssignmentRouteMode.is_in_session(route_mode):
		primary = "%d 位居民的模型均已配置完成" % count
		secondary = "保存后会立即用于当前小镇。"
		confirm = "保存修改"
	elif ResidentModelAssignmentRouteMode.is_save_slot(route_mode):
		primary = "%d 位居民的模型均已配置完成" % count
		secondary = "保存后会写入此存档的新修订。"
		confirm = "保存到此存档"
	else:
		primary = "%d 位居民的模型均已配置完成" % count
	return {
		"primary": primary,
		"secondary": secondary,
		"message": "%s\n%s" % [primary, secondary],
		"confirm": confirm,
	}
