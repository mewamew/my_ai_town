class_name TownUiPageProjectionService
extends RefCounted

const WORLD_LOG_STORE = preload("res://world/runtime/log/TownWorldLogStore.gd")
const GATHERING_HOT_PARTICIPANT_COUNT := WORLD_LOG_STORE.GATHERING_HOT_PARTICIPANT_COUNT


signal view_model_changed(scope: String, view_model: Dictionary)
signal operation_completed(scope: String, operation: Dictionary)


const RESULT_SHAPES := preload(
	"res://world/contract/TownWorldResultShapes.gd"
)
const SCOPES: Array[String] = [
	"weather_control",
	"announcements",
	"resident_action_menu",
	"resident_overview",
	"resident_detail",
	"inner_observation",
	"place_focus",
	"indoor",
	"town_log",
	"wardrobe",
]
const WORLD_REFRESH_SCOPES: Array[String] = [
	"weather_control",
	"announcements",
	"resident_action_menu",
	"resident_overview",
	"resident_detail",
	"inner_observation",
	"place_focus",
	"indoor",
]
const ANNOUNCEMENT_LIMIT := 120
const RESIDENT_CATALOG_PATH := "res://world/data/town/resident_catalog.json"
const DEATH_STORY_FALLBACK := "一道不属于人间的命令落下，他在原地无声死去。"
const WARDROBE_CATALOG_PATH := (
	"res://assets/characters/resident_2d_rig_v1/wardrobe_v1/"
	+ "wardrobe_catalog.json"
)
const WEATHER_IDS: Array[String] = [
	"晴天",
	"阴天",
	"小雨",
	"大雨",
	"雷暴",
	"下雪",
]
const WEATHER_COPY := {
	"晴天": {
		"iconId": "weather_sunny",
		"description": "雨雪层关闭，光照恢复，户外活动更自然。",
		"affectedPlaceLabels": ["广场", "水边"],
		"residentSummary": "户外居民可能恢复原目标或继续活动。",
	},
	"阴天": {
		"iconId": "weather_cloudy",
		"description": "云层变厚、光线转柔，小镇保持可见但气氛更安静。",
		"affectedPlaceLabels": ["广场", "桥边"],
		"residentSummary": "户外居民可能放慢脚步或留意天气。",
	},
	"小雨": {
		"iconId": "weather_light_rain",
		"description": "轻雨覆盖地图，户外居民可能寻找屋檐或继续赶路。",
		"affectedPlaceLabels": ["咖啡馆门口", "图书馆入口"],
		"residentSummary": "户外居民可能避雨、看雨或调整短计划。",
	},
	"中雨": {
		"iconId": "weather_heavy_rain",
		"description": "稳定雨势覆盖小镇，路面湿润并出现持续雨滴反馈。",
		"affectedPlaceLabels": ["广场", "桥边"],
		"residentSummary": "户外居民可能加快脚步、避雨或调整短计划。",
	},
	"大雨": {
		"iconId": "weather_heavy_rain",
		"description": "雨势明显增强，更多户外居民会优先寻找室内地点。",
		"affectedPlaceLabels": ["广场", "住宅门口"],
		"residentSummary": "户外居民可能暂停行动、回家或前往公共室内地点。",
	},
	"雷暴": {
		"iconId": "weather_thunderstorm",
		"description": "雷声与闪电成为主要反馈，户外居民会出现受惊或避雨反应。",
		"affectedPlaceLabels": ["广场", "桥边", "公告栏"],
		"residentSummary": "户外居民可能受惊、抱怨、暂停或立即寻找避雨点。",
	},
	"下雪": {
		"iconId": "weather_snow",
		"description": "雪粒与冷色环境出现，居民可能观察雪景或放慢行动。",
		"affectedPlaceLabels": ["广场", "水边"],
		"residentSummary": "居民可能开心、觉得冷、观察雪景或前往室内。",
	},
}

var _runtime: Object
var _world: Object
var _gateway: Object
var _session_config: Dictionary = {}
var _view_models: Dictionary = {}
var _dirty_world_scopes: Dictionary = {}
var _last_confirmed_data: Dictionary = {}
var _last_confirmed_revision: Dictionary = {}
var _page_contexts: Dictionary = {}
var _revision_sequence := 0
var _request_sequence := 0
var _last_world_revision := -1

var _announcement_panel_open := true
var _announcement_composer_open := false
var _announcement_draft := ""
var _announcement_dialog_open := false
var _announcement_feedback: Dictionary = {}
var _announcement_retryable := false
var _announcement_retry_payload: Dictionary = {}
var _town_log_selected_filter := "all"
var _town_log_open := false
var _town_log_selected_entry_id := ""
var _town_log_expanded_entry_id := ""
var _town_log_compact_entry_id := ""
var _town_log_filters := {
	"residentId": "",
	"kindTag": "",
	"day": 0,
	"unreadOnly": false,
}
var _town_log_filter_catalog: Dictionary = {}
var _town_log_rows: Array[Dictionary] = []
var _town_log_paging := {
	"cursor": {},
	"hasMore": false,
	"isLoading": false,
}
var _town_log_detail: Variant = null
var _town_log_detail_paging := {
	"cursor": 0,
	"hasMore": false,
	"isLoading": false,
}
var _town_log_has_newer_threads := false
var _town_log_query_timeline_id := ""
var _town_log_query_upper_bound := 0
var _town_log_query_error: Variant = null
var _indoor_focused_event_id := ""
var _pending_place_focus_operation: Dictionary = {}
var _pending_indoor_return_operation: Dictionary = {}
var _resident_catalog_by_id: Dictionary = {}
var _identity_name_by_id: Dictionary = {}
var _identity_record_by_name: Dictionary = {}
var _identity_index_revision := -1
var _wardrobe_portrait_by_appearance_id: Dictionary = {}
var _inner_observation_state: Dictionary = {}
var _inner_observation_generation := 0
var _death_story_inflight: Dictionary = {}


func bind(
	runtime: Object,
	world: Object,
	session_config: Dictionary = {},
	gateway: Object = null,
) -> Dictionary:
	unbind()
	_runtime = runtime
	_world = world
	_gateway = gateway
	_session_config = session_config.duplicate(true)
	_dirty_world_scopes.clear()
	_identity_name_by_id.clear()
	_identity_record_by_name.clear()
	_identity_index_revision = -1
	_load_resident_catalog_index()
	_load_wardrobe_portrait_index()
	_last_world_revision = _read_world_revision()
	_revision_sequence = maxi(_last_world_revision, 0)
	_seed_town_log()
	_connect_world_signals()
	_connect_runtime_signals()
	_refresh_all()
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"scopes": SCOPES.duplicate(),
	}


func unbind() -> void:
	_cancel_inner_observation_request()
	_death_story_inflight.clear()
	_disconnect_runtime_signals()
	_disconnect_world_signals()
	_runtime = null
	_world = null
	_gateway = null
	_session_config.clear()
	_view_models.clear()
	_dirty_world_scopes.clear()
	_last_confirmed_data.clear()
	_last_confirmed_revision.clear()
	_page_contexts.clear()
	_revision_sequence = 0
	_request_sequence = 0
	_last_world_revision = -1
	_announcement_panel_open = true
	_announcement_composer_open = false
	_announcement_draft = ""
	_announcement_dialog_open = false
	_announcement_feedback.clear()
	_announcement_retryable = false
	_announcement_retry_payload.clear()
	_town_log_selected_filter = "all"
	_town_log_open = false
	_town_log_selected_entry_id = ""
	_town_log_expanded_entry_id = ""
	_town_log_compact_entry_id = ""
	_town_log_filters = {
		"residentId": "",
		"kindTag": "",
		"day": 0,
		"unreadOnly": false,
	}
	_town_log_filter_catalog.clear()
	_town_log_rows.clear()
	_town_log_paging = {
		"cursor": {},
		"hasMore": false,
		"isLoading": false,
	}
	_town_log_detail = null
	_town_log_detail_paging = {
		"cursor": 0,
		"hasMore": false,
		"isLoading": false,
	}
	_town_log_has_newer_threads = false
	_town_log_query_timeline_id = ""
	_town_log_query_upper_bound = 0
	_town_log_query_error = null
	_indoor_focused_event_id = ""
	_pending_place_focus_operation.clear()
	_pending_indoor_return_operation.clear()
	_resident_catalog_by_id.clear()
	_wardrobe_portrait_by_appearance_id.clear()
	_identity_name_by_id.clear()
	_identity_record_by_name.clear()
	_identity_index_revision = -1
	_inner_observation_state.clear()
	_inner_observation_generation = 0


func get_view_model(scope: String) -> Dictionary:
	if not SCOPES.has(scope):
		return _unknown_scope_view_model(scope)
	if not _view_models.has(scope) or _dirty_world_scopes.has(scope):
		refresh(scope)
	return (_view_models.get(scope, {}) as Dictionary).duplicate(true)


func view_model(scope: String) -> Dictionary:
	return get_view_model(scope)


func get_all_view_models() -> Dictionary:
	var result: Dictionary = {}
	for scope in SCOPES:
		result[scope] = get_view_model(scope)
	return result


func set_page_context(scope: String, context: Dictionary) -> Dictionary:
	if not SCOPES.has(scope):
		return _dispatch_failure("UNKNOWN_UI_SCOPE", false, "")
	_page_contexts[scope] = context.duplicate(true)
	if scope == "announcements" and bool(context.get("open", false)):
		_announcement_panel_open = true
	if scope == "town_log":
		var next_open := bool(context.get("open", false))
		var requested_thread_id := String(
			context.get("threadId", ""),
		).strip_edges()
		if (
			next_open
			and (
				not _town_log_open
				or not requested_thread_id.is_empty()
			)
		):
			_town_log_open = true
			_reload_town_log_threads()
		else:
			_town_log_open = next_open
		if next_open and not requested_thread_id.is_empty():
			_load_town_log_detail(requested_thread_id, false)
	if scope == "inner_observation" and not bool(context.get("open", false)):
		_close_inner_observation_state()
	refresh(scope)
	return {
		"ok": true,
		"accepted": true,
		"requestId": "",
		"errorCode": "",
		"retryable": false,
	}


func refresh(scope: String) -> Dictionary:
	match scope:
		"weather_control":
			_publish_weather(_idle_operation(), null)
		"announcements":
			_publish_announcements(_idle_operation(), null)
		"resident_action_menu":
			_publish_resident_action_menu(_idle_operation(), null)
		"resident_overview":
			_publish_resident_overview(_idle_operation(), null)
		"resident_detail":
			_publish_resident_detail(_idle_operation(), null)
		"inner_observation":
			if bool(_inner_observation_state.get("open", false)):
				var resident_id := String(
					_inner_observation_state.get("residentId", "")
				)
				var refresh_result := _begin_inner_observation_generation(
					resident_id,
					"inner_observation.refresh",
					"inner_observation.refresh",
				)
				if not bool(refresh_result.get("ok", false)):
					_present_inner_observation_failure(
						resident_id,
						"inner_observation.refresh",
						"inner_observation.refresh",
						refresh_result,
					)
			else:
				_publish_inner_observation(_idle_operation(), null)
		"place_focus":
			_publish_place_focus(_idle_operation(), null)
		"indoor":
			_publish_indoor(_idle_operation(), null)
		"town_log":
			_publish_town_log(_idle_operation(), null)
		"wardrobe":
			_publish_disabled_wardrobe()
		_:
			return _unknown_scope_view_model(scope)
	return get_view_model(scope)


func dispatch(intent: Variant, payload: Dictionary = {}) -> Dictionary:
	var intent_string := String(intent)
	var scope := _scope_for_intent(intent_string)
	var request_id := _next_request_id()
	if scope.is_empty():
		return _dispatch_failure("UNKNOWN_UI_INTENT", false, request_id)
	var current := get_view_model(scope)
	var action := _action_for_intent(current, intent_string, payload)
	if action.is_empty() or not bool(action.get("enabled", false)):
		return _dispatch_failure(
			String(action.get("disabledReason", "ACTION_DISABLED")),
			false,
			request_id,
		)
	match scope:
		"weather_control":
			return _dispatch_weather(intent_string, payload, request_id)
		"announcements":
			return _dispatch_announcement(intent_string, payload, request_id)
		"resident_action_menu":
			return _dispatch_resident_action(intent_string, payload, request_id)
		"resident_overview":
			return _dispatch_resident_overview(intent_string, payload, request_id)
		"resident_detail":
			return _dispatch_resident_detail(intent_string, payload, request_id)
		"inner_observation":
			return _dispatch_inner_observation(intent_string, payload, request_id)
		"place_focus":
			return _dispatch_place_focus(intent_string, payload, request_id)
		"indoor":
			return _dispatch_indoor(intent_string, payload, request_id)
		"town_log":
			return _dispatch_town_log(intent_string, payload, request_id)
		"wardrobe":
			return _dispatch_wardrobe(intent_string, request_id)
	return _dispatch_failure("PAGE_DOMAIN_INTERFACE_MISSING", false, request_id)


func _refresh_all() -> void:
	for scope in SCOPES:
		refresh(scope)


func _dispatch_weather(
	intent: String,
	payload: Dictionary,
	request_id: String,
) -> Dictionary:
	if intent == "avatar.switch_to_overview":
		if _runtime == null or not _runtime.has_method("exit_avatar_mode"):
			return _dispatch_failure("AVATAR_MODE_INTERFACE_MISSING", false, request_id)
		var submitted_at := Time.get_ticks_msec()
		_publish_weather(
			_operation(request_id, intent, "loading", submitted_at, 0),
			null,
		)
		var exit_result := _runtime.call("exit_avatar_mode") as Dictionary
		if bool(exit_result.get("ok", false)):
			_publish_weather(
				_operation(request_id, intent, "success", submitted_at, Time.get_ticks_msec()),
				null,
			)
			return _dispatch_success(request_id)
		_publish_failure("weather_control", intent, request_id, submitted_at, exit_result)
		return _command_dispatch_result(request_id, exit_result)
	var submitted_at := Time.get_ticks_msec()
	_publish_weather(
		_operation(request_id, intent, "loading", submitted_at, 0),
		null,
	)
	var weather_id := String(payload.get("weatherId", ""))
	var result := _world.set_weather(weather_id) as Dictionary
	if bool(result.get("ok", false)):
		var confirmed_weather := _read_weather()
		var confirmed_copy := WEATHER_COPY.get(confirmed_weather, {}) as Dictionary
		_publish_weather(
			_operation(
				request_id,
				intent,
				"success",
				submitted_at,
				Time.get_ticks_msec(),
			),
			null,
			{
				"weatherId": confirmed_weather,
				"summary": "世界已确认天气：%s" % confirmed_weather,
				"affectedPlaceLabels": (confirmed_copy.get("affectedPlaceLabels", []) as Array).duplicate(true),
				"residentSummary": String(confirmed_copy.get("residentSummary", "")),
				"logReceipt": {
					"written": true,
					"label": "已记入小镇日志",
				},
			},
		)
		return _dispatch_success(request_id)
	_publish_failure("weather_control", intent, request_id, submitted_at, result)
	return _command_dispatch_result(request_id, result)


func _dispatch_announcement(
	intent: String,
	payload: Dictionary,
	request_id: String,
) -> Dictionary:
	match intent:
		"announcements.composer.open":
			_announcement_composer_open = true
			_announcement_dialog_open = false
			_announcement_feedback.clear()
			_publish_announcements(_idle_operation(), null)
			return _dispatch_success(request_id)
		"announcements.draft.update":
			_announcement_draft = String(payload.get("text", ""))
			_announcement_feedback.clear()
			_publish_announcements(_idle_operation(), null)
			return _dispatch_success(request_id)
		"announcements.panel.close":
			if not _announcement_draft.is_empty():
				_announcement_dialog_open = true
			else:
				_announcement_panel_open = false
			_publish_announcements(_idle_operation(), null)
			return _dispatch_success(request_id)
		"announcements.draft.continue":
			_announcement_dialog_open = false
			_announcement_composer_open = true
			_publish_announcements(_idle_operation(), null)
			return _dispatch_success(request_id)
		"announcements.draft.discard":
			_announcement_draft = ""
			_announcement_dialog_open = false
			_announcement_composer_open = false
			_announcement_panel_open = false
			_publish_announcements(_idle_operation(), null)
			return _dispatch_success(request_id)
		"announcements.feedback.dismiss":
			_announcement_feedback.clear()
			_publish_announcements(_idle_operation(), null)
			return _dispatch_success(request_id)
		"announcements.publish", "announcements.retry":
			return _publish_announcement_command(intent, payload, request_id)
	return _dispatch_failure("UNKNOWN_UI_INTENT", false, request_id)


func _publish_announcement_command(
	intent: String,
	payload: Dictionary,
	request_id: String,
) -> Dictionary:
	var text := String(
		_announcement_retry_payload.get("text", "")
		if intent == "announcements.retry"
		else payload.get("text", _announcement_draft)
	)
	var submitted_at := Time.get_ticks_msec()
	_publish_announcements(
		_operation(request_id, intent, "loading", submitted_at, 0),
		null,
	)
	var result := _runtime.call("publish_player_announcement", text) as Dictionary
	if bool(result.get("ok", false)):
		var announcement := result.get("announcement", {}) as Dictionary
		var scheduled_label := String(
			announcement.get("scheduled_time_label", ""),
		).strip_edges()
		var schedule_warning := bool(result.get("scheduleWarning", false))
		_announcement_draft = ""
		_announcement_composer_open = false
		_announcement_dialog_open = false
		_announcement_retryable = false
		_announcement_retry_payload.clear()
		_announcement_feedback = {
			"visible": true,
			"kind": "warning" if schedule_warning else "success",
			"title": "公告已经发布",
			"message": (
				"公告已记入右侧事件链，但没有识别出可执行的时间；居民会即时回应，不会到点再提醒。请写成“明天下午三点”或“两小时后”。"
				if schedule_warning
				else (
					"公告已记入右侧事件链；已识别约定时间 %s，居民会先回应，到点后再次提醒。" % scheduled_label
					if not scheduled_label.is_empty()
					else "公告已记入右侧事件链；居民会逐个回应。"
				)
			),
			"durationMs": 2600,
			"blocksInput": false,
		}
		_publish_announcements(
			_operation(
				request_id,
				intent,
				"success",
				submitted_at,
				Time.get_ticks_msec(),
			),
			null,
		)
		return _dispatch_success(request_id)
	_announcement_retryable = bool(result.get("retryable", false))
	_announcement_retry_payload = {"text": text}
	_publish_failure("announcements", intent, request_id, submitted_at, result)
	return _command_dispatch_result(request_id, result)


func _dispatch_resident_action(
	intent: String,
	payload: Dictionary,
	request_id: String,
) -> Dictionary:
	var submitted_at := Time.get_ticks_msec()
	if intent == "resident.action_menu.close":
		var context := (_page_contexts.get("resident_action_menu", {}) as Dictionary).duplicate(true)
		context["open"] = false
		_page_contexts["resident_action_menu"] = context
		_publish_resident_action_menu(
			_operation(request_id, intent, "success", submitted_at, Time.get_ticks_msec()),
			null,
		)
		return _dispatch_success(request_id)
	if intent == "resident.detail.open":
		var resident_id := String(payload.get("residentId", "")).strip_edges()
		if _resident_name_for_id(resident_id).is_empty():
			return _dispatch_failure("RESIDENT_IDENTITY_NOT_FOUND", false, request_id)
		var requested_tab := String(payload.get("tab", "status"))
		var selected_tab: String = String({
			"relationship": "relationships",
			"memory": "memories",
		}.get(requested_tab, requested_tab))
		if selected_tab not in ["status", "relationships", "memories"]:
			return _dispatch_failure("RESIDENT_DETAIL_TAB_INVALID", false, request_id)
		_page_contexts["resident_detail"] = {
			"open": true,
			"residentId": resident_id,
			"selectedTab": selected_tab,
		}
		_publish_resident_detail(
			_operation(request_id, intent, "success", submitted_at, Time.get_ticks_msec()),
			null,
		)
		return _dispatch_success(request_id)
	if intent == "resident.inner_observation.open":
		var resident_id := String(
			payload.get("residentId", "")
		).strip_edges()
		var generation_result := _begin_inner_observation_generation(
			resident_id,
			request_id,
			intent,
		)
		if not bool(generation_result.get("ok", false)):
			_present_inner_observation_failure(
				resident_id,
				request_id,
				intent,
				generation_result,
			)
			# Opening the player-facing page succeeded even though reading its
			# data did not. Keep the page reachable so it can show the honest
			# failure and offer retry/exit instead of making the button appear
			# to do nothing.
			_publish_resident_action_menu(
				_operation(
					request_id,
					intent,
					"success",
					submitted_at,
					Time.get_ticks_msec(),
				),
				null,
			)
			return _dispatch_success(request_id)
		_publish_resident_action_menu(
			_operation(
				request_id,
				intent,
				"success",
				submitted_at,
				Time.get_ticks_msec(),
			),
			null,
		)
		return _dispatch_success(request_id)
	if intent == "resident.death.confirm":
		var resident_id := String(payload.get("residentId", "")).strip_edges()
		var resident_name := _resident_name_for_id(resident_id)
		if resident_name.is_empty():
			return _dispatch_failure(
				"RESIDENT_IDENTITY_NOT_FOUND",
				false,
				request_id,
			)
		if _world == null or not _world.has_method("confirm_resident_death"):
			return _dispatch_failure(
				"RESIDENT_DEATH_INTERFACE_MISSING",
				false,
				request_id,
			)
		if _death_story_inflight.has(resident_id):
			return _dispatch_failure(
				"DEATH_STORY_IN_PROGRESS",
				false,
				request_id,
			)
		var lifecycle_revision := int(payload.get("lifecycleRevision", -1))
		var world_instance_token := String(payload.get("worldInstanceToken", ""))
		_death_story_inflight[resident_id] = {
			"requestId": request_id,
			"residentName": resident_name,
			"submittedAtMsec": submitted_at,
			"lifecycleRevision": lifecycle_revision,
			"worldInstanceToken": world_instance_token,
		}
		_publish_resident_action_menu(
			_operation(
				request_id,
				intent,
				"loading",
				submitted_at,
				0,
			),
			null,
		)
		var accepted := {
			"ok": false,
			"errorCode": "DEATH_STORY_AGENT_INTERFACE_MISSING",
			"retryable": false,
		}
		if (
			_gateway != null
			and _gateway.has_method("request_resident_death_story")
		):
			accepted = _gateway.call(
				"request_resident_death_story",
				resident_id,
				request_id,
				Callable(self, "_on_resident_death_story_result").bind(
					resident_id,
					request_id,
				),
			) as Dictionary
		if not bool(accepted.get("ok", false)):
			_on_resident_death_story_result(
				accepted,
				resident_id,
				request_id,
			)
		return _dispatch_success(request_id)
	if intent != "resident.follow":
		return _dispatch_failure("UNKNOWN_UI_INTENT", false, request_id)
	var resident_id := String(payload.get("residentId", ""))
	var resident_name := _resident_name_for_id(resident_id)
	var result := false
	if not resident_name.is_empty():
		result = bool(_runtime.call("follow_resident", resident_name))
	if result:
		_publish_resident_action_menu(
			_operation(request_id, intent, "success", submitted_at, Time.get_ticks_msec()),
			null,
		)
		return _dispatch_success(request_id)
	var failure := {
		"ok": false,
		"errorCode": "RESIDENT_FOLLOW_REJECTED",
		"retryable": false,
		"errors": [],
	}
	_publish_failure("resident_action_menu", intent, request_id, submitted_at, failure)
	return _command_dispatch_result(request_id, failure)


func _dispatch_resident_overview(
	intent: String,
	payload: Dictionary,
	request_id: String,
) -> Dictionary:
	var submitted_at := Time.get_ticks_msec()
	var resident_id := String(payload.get("residentId", "")).strip_edges()
	var resident_name := _resident_name_for_id(resident_id)
	if resident_name.is_empty():
		return _dispatch_failure("RESIDENT_IDENTITY_NOT_FOUND", false, request_id)
	match intent:
		"resident_overview.follow":
			var resident_lifecycle := (
				_resident_state(resident_name).get("lifecycle", {}) as Dictionary
			)
			if bool(resident_lifecycle.get("isDead", false)):
				return _dispatch_failure("RESIDENT_DEAD", false, request_id)
			var followed := (
				_runtime != null
				and _runtime.has_method("follow_resident")
				and bool(_runtime.call("follow_resident", resident_name))
			)
			if followed:
				_publish_resident_overview(
					_operation(
						request_id,
						intent,
						"success",
						submitted_at,
						Time.get_ticks_msec(),
					),
					null,
				)
				return _dispatch_success(request_id)
			var follow_failure := {
				"ok": false,
				"errorCode": "RESIDENT_FOLLOW_REJECTED",
				"retryable": false,
				"errors": [],
			}
			_publish_failure(
				"resident_overview",
				intent,
				request_id,
				submitted_at,
				follow_failure,
			)
			return _command_dispatch_result(request_id, follow_failure)
		"resident_overview.update_profile":
			var resident_lifecycle := (
				_resident_state(resident_name).get("lifecycle", {}) as Dictionary
			)
			if bool(resident_lifecycle.get("isDead", false)):
				return _dispatch_failure("RESIDENT_DEAD", false, request_id)
			if (
				_world == null
				or not _world.has_method("update_resident_profile")
			):
				return _dispatch_failure(
					"RESIDENT_PROFILE_UPDATE_INTERFACE_MISSING",
					false,
					request_id,
				)
			var profile_value: Variant = payload.get("profile")
			if not profile_value is Dictionary:
				return _dispatch_failure(
					"RESIDENT_PROFILE_DRAFT_INVALID",
					false,
					request_id,
				)
			var update_result := _world.update_resident_profile(resident_id,
				(profile_value as Dictionary).duplicate(true),) as Dictionary
			if bool(update_result.get("ok", false)):
				_publish_resident_overview(
					_operation(
						request_id,
						intent,
						"success",
						submitted_at,
						Time.get_ticks_msec(),
					),
					null,
				)
				return _command_dispatch_result(request_id, update_result)
			_publish_failure(
				"resident_overview",
				intent,
				request_id,
				submitted_at,
				update_result,
			)
			return _command_dispatch_result(request_id, update_result)
		_:
			return _dispatch_failure(
				"RESIDENT_OVERVIEW_ACTION_NOT_AVAILABLE",
				false,
				request_id,
			)


func _dispatch_resident_detail(
	intent: String,
	payload: Dictionary,
	request_id: String,
) -> Dictionary:
	var submitted_at := Time.get_ticks_msec()
	var context := (_page_contexts.get("resident_detail", {}) as Dictionary).duplicate(true)
	var resident_id := String(payload.get("residentId", context.get("residentId", ""))).strip_edges()
	if _resident_name_for_id(resident_id).is_empty():
		return _dispatch_failure("RESIDENT_IDENTITY_NOT_FOUND", false, request_id)
	context["residentId"] = resident_id
	match intent:
		"resident_detail.close":
			context["open"] = false
		"resident_detail.select_tab":
			var tab_id := String(payload.get("tabId", ""))
			if tab_id not in ["status", "relationships", "memories"]:
				return _dispatch_failure("RESIDENT_DETAIL_TAB_INVALID", false, request_id)
			context["selectedTab"] = tab_id
		"resident_detail.refresh", "resident_detail.retry":
			pass
		"resident_detail.filter_memories":
			var filter_id := String(payload.get("filterId", ""))
			if filter_id not in ["influencing", "past", "doubtful", "anomalous", "interventions", "all"]:
				return _dispatch_failure("RESIDENT_MEMORY_FILTER_INVALID", false, request_id)
			context["selectedTab"] = "memories"
			context["memoryFilter"] = filter_id
			context["memoryPage"] = 0
		"resident_detail.filter_relationships":
			var relationship_filter_id := String(payload.get("filterId", ""))
			if relationship_filter_id not in ["all", "close", "trust", "conflict", "distant", "player"]:
				return _dispatch_failure("RESIDENT_RELATIONSHIP_FILTER_INVALID", false, request_id)
			context["selectedTab"] = "relationships"
			context["relationshipFilter"] = relationship_filter_id
		"resident_detail.page_memories":
			var direction := String(payload.get("direction", ""))
			if direction not in ["previous", "next"]:
				return _dispatch_failure("RESIDENT_MEMORY_PAGE_INVALID", false, request_id)
			context["selectedTab"] = "memories"
			var current_page := maxi(0, int(context.get("memoryPage", 0)))
			context["memoryPage"] = maxi(
				0,
				current_page + (-1 if direction == "previous" else 1),
			)
		"resident_detail.change_memory":
			if _gateway == null or not _gateway.has_method("apply_resident_memory_intervention"):
				return _dispatch_failure("RESIDENT_MEMORY_INTERVENTION_INTERFACE_MISSING", false, request_id)
			var intervention_result := _gateway.call(
				"apply_resident_memory_intervention",
				resident_id,
				{
					"memoryKey": String(payload.get("memoryKey", "")),
					"operation": String(payload.get("operation", "")),
					"playerText": String(payload.get("playerText", "")),
					"expectedRevision": int(payload.get("expectedRevision", -1)),
				},
			) as Dictionary
			if not bool(intervention_result.get("ok", false)):
				_publish_failure(
					"resident_detail",
					intent,
					request_id,
					submitted_at,
					intervention_result,
				)
				return _command_dispatch_result(request_id, intervention_result)
			context["selectedTab"] = "memories"
		_:
			return _dispatch_failure("RESIDENT_DETAIL_ACTION_NOT_AVAILABLE", false, request_id)
	_page_contexts["resident_detail"] = context
	_publish_resident_detail(
		_operation(request_id, intent, "success", submitted_at, Time.get_ticks_msec()),
		null,
	)
	return _dispatch_success(request_id)


func _dispatch_inner_observation(
	intent: String,
	_payload: Dictionary,
	request_id: String,
) -> Dictionary:
	var submitted_at := Time.get_ticks_msec()
	match intent:
		"inner_observation.exit":
			if not bool(_inner_observation_state.get("open", false)):
				return _dispatch_failure(
					"INNER_OBSERVATION_NOT_OPEN",
					false,
					request_id,
				)
			_inner_observation_state["phase"] = "closing"
			_publish_inner_observation(
				_operation(
					request_id,
					intent,
					"loading",
					submitted_at,
					0,
				),
				null,
			)
			_close_inner_observation_state()
			_publish_inner_observation(
				_operation(
					request_id,
					intent,
					"success",
					submitted_at,
					Time.get_ticks_msec(),
				),
				null,
			)
			return _dispatch_success(request_id)
		"inner_observation.retry":
			if not bool(_inner_observation_state.get("open", false)):
				return _dispatch_failure(
					"INNER_OBSERVATION_NOT_OPEN",
					false,
					request_id,
				)
			if not bool(_inner_observation_state.get("retryable", false)):
				return _dispatch_failure(
					"NO_RETRYABLE_ERROR",
					false,
					request_id,
				)
			var resident_id := String(
				_inner_observation_state.get("residentId", "")
			)
			var retry_result := _begin_inner_observation_generation(
				resident_id,
				request_id,
				intent,
			)
			if not bool(retry_result.get("ok", false)):
				_present_inner_observation_failure(
					resident_id,
					request_id,
					intent,
					retry_result,
				)
			return retry_result
	return _dispatch_failure(
		"INNER_OBSERVATION_ACTION_NOT_AVAILABLE",
		false,
		request_id,
	)


func _begin_inner_observation_generation(
	resident_id: String,
	request_id: String,
	intent: String,
) -> Dictionary:
	var resident_name := _resident_name_for_id(resident_id)
	if resident_name.is_empty():
		return RESULT_SHAPES.failure("RESIDENT_IDENTITY_NOT_FOUND")
	if (
		_gateway == null
		or not _gateway.has_method(
			"request_resident_inner_observation"
		)
		or not _gateway.has_method(
			"cancel_resident_inner_observation"
		)
	):
		return RESULT_SHAPES.failure("INNER_OBSERVATION_INTERFACE_MISSING")
	if not _session_formal_ready():
		return RESULT_SHAPES.failure("INNER_OBSERVATION_SESSION_NOT_FORMAL")
	_cancel_inner_observation_request()
	_inner_observation_generation += 1
	var generation_request_id := "%s:inner:%d" % [
		request_id,
		_inner_observation_generation,
	]
	var confirmed_revision := _read_world_revision()
	var submitted_at := Time.get_ticks_msec()
	_inner_observation_state = {
		"open": true,
		"residentId": resident_id,
		"requestId": generation_request_id,
		"confirmedWorldRevision": confirmed_revision,
		"phase": "generating",
			"generationStatus": "generating",
			"content": {
				"contentKind": "resident_current_focus",
				"monologueText": "",
				"reasonText": "",
				"playerStatusText": "正在读取想法…",
				"empty": false,
			},
		"fallbackUsed": false,
		"retryable": false,
		"errorCode": "",
		"startedAtMsec": submitted_at,
	}
	_page_contexts["inner_observation"] = {
		"open": true,
		"residentId": resident_id,
		"requestId": generation_request_id,
	}
	_publish_inner_observation(
		_operation(
			request_id,
			intent,
			"loading",
			submitted_at,
			0,
		),
		null,
	)
	var accepted := _gateway.call(
		"request_resident_inner_observation",
		resident_id,
		generation_request_id,
		confirmed_revision,
		Callable(self, "_on_inner_observation_result").bind(
			generation_request_id,
			resident_id,
			_inner_observation_generation,
		),
	) as Dictionary
	if not bool(accepted.get("ok", false)):
		return accepted
	return _dispatch_success(request_id)


func _present_inner_observation_failure(
	resident_id: String,
	request_id: String,
	intent: String,
	result: Dictionary,
) -> void:
	_cancel_inner_observation_request()
	_inner_observation_generation += 1
	var generation_request_id := "%s:inner-failed:%d" % [
		request_id,
		_inner_observation_generation,
	]
	var error_code := String(
		result.get(
			"errorCode",
			"INNER_OBSERVATION_FAILED",
		)
	)
	var retryable := bool(result.get("retryable", false))
	var submitted_at := Time.get_ticks_msec()
	_inner_observation_state = {
		"open": true,
		"residentId": resident_id,
		"requestId": generation_request_id,
		"confirmedWorldRevision": _read_world_revision(),
		"phase": "failed",
		"generationStatus": "error",
		"content": {},
		"fallbackUsed": false,
		"retryable": retryable,
		"errorCode": error_code,
		"startedAtMsec": submitted_at,
	}
	_page_contexts["inner_observation"] = {
		"open": true,
		"residentId": resident_id,
		"requestId": generation_request_id,
	}
	_publish_inner_observation(
		_operation(
			request_id,
			intent,
			"error",
			submitted_at,
			Time.get_ticks_msec(),
		),
		_error_payload(error_code, retryable, ""),
	)


func _on_inner_observation_result(
	result: Dictionary,
	request_id: String,
	resident_id: String,
	generation: int,
) -> void:
	if (
		generation != _inner_observation_generation
		or not bool(_inner_observation_state.get("open", false))
		or String(_inner_observation_state.get("requestId", ""))
		!= request_id
		or String(_inner_observation_state.get("residentId", ""))
		!= resident_id
		or String(result.get("requestId", "")) != request_id
		or String(result.get("residentId", "")) != resident_id
	):
		return
	var result_status := String(result.get("status", "error"))
	var content_value: Variant = result.get("content")
	if (
		result_status != "ready"
		or not content_value is Dictionary
	):
		result_status = "error"
		content_value = {}
		if String(result.get("errorCode", "")).is_empty():
			result["errorCode"] = "INNER_OBSERVATION_RESULT_CONTRACT_INVALID"
			result["retryable"] = true
	var content := (
		(content_value as Dictionary).duplicate(true)
		if content_value is Dictionary
		else {}
	)
	_inner_observation_state["content"] = content
	_inner_observation_state["phase"] = (
		"ready" if result_status == "ready" else "failed"
	)
	_inner_observation_state["generationStatus"] = (
		"ready" if result_status == "ready" else "error"
	)
	_inner_observation_state["retryable"] = bool(
		result.get("retryable", false)
	)
	_inner_observation_state["errorCode"] = String(
		result.get("errorCode", "")
	)
	var operation_status := (
		"success" if result_status == "ready" else "error"
	)
	var error_value: Variant = null
	if result_status != "ready":
		error_value = _error_payload(
			String(
				result.get(
					"errorCode",
					"INNER_OBSERVATION_FAILED",
				)
			),
			bool(result.get("retryable", false)),
			"",
		)
	_publish_inner_observation(
		_operation(
			request_id,
			"inner_observation.generate",
			operation_status,
			int(_inner_observation_state.get("startedAtMsec", 0)),
			Time.get_ticks_msec(),
		),
		error_value,
	)


func _publish_inner_observation(
	operation: Dictionary,
	error_value: Variant,
) -> void:
	var open := bool(_inner_observation_state.get("open", false))
	var resident_id := String(
		_inner_observation_state.get("residentId", "")
	)
	var resident_name := _resident_name_for_id(resident_id)
	var phase := String(
		_inner_observation_state.get(
			"phase",
			"hidden",
		)
	) if open else "hidden"
	var content := (
		(
			_inner_observation_state.get(
				"content",
				{},
			) as Dictionary
		).duplicate(true)
			if open
			else {
				"contentKind": "resident_current_focus",
				"monologueText": "",
				"reasonText": "",
				"playerStatusText": "",
				"empty": false,
				"fallbackUsed": false,
			}
	)
	var generation_status := String(
		_inner_observation_state.get(
			"generationStatus",
			"idle",
		)
	) if open else "idle"
	var request_id := String(
		_inner_observation_state.get("requestId", "")
	)
	# The page shell is a formal resident view even when its read-only data
	# source is temporarily unavailable. Keep it reachable so the player sees
	# an honest empty/error state instead of a button that appears to do
	# nothing.
	var available := _session_formal_ready()
	var data := {
		"capabilityMode": "formal" if available else "unavailable",
		"source": "town_ui_adapter",
		"formalReady": available,
		"visibility": "visible" if open else "hidden",
		"phase": phase,
		"pauseState": "running",
		"background": {
			"mode": "live_town_frame",
			"available": true,
			"dimmed": open,
			"focusVisible": open,
		},
		"resident": _inner_observation_resident(
			resident_id,
			resident_name,
		),
		"content": content,
		"generation": {
			"status": generation_status,
			"requestId": request_id,
			"retryable": bool(
				_inner_observation_state.get("retryable", false)
			),
		},
		"motion": {
			"reduceMotion": false,
		},
	}
	var exit_enabled := open and phase != "closing"
	var retry_enabled := (
		open
		and phase == "failed"
		and bool(_inner_observation_state.get("retryable", false))
	)
	var view_status: String = String({
		"hidden": "hidden",
		"opening": "opening",
		"generating": "loading",
		"ready": "ready",
		"failed": "error",
		"closing": "loading",
	}.get(phase, "hidden"))
	_store_view_model(
		"inner_observation",
		view_status if available else "disabled",
		data,
		{
			"exit": _action(
				"inner_observation.exit",
				exit_enabled,
				"INNER_OBSERVATION_NOT_OPEN"
				if not open
				else "EXIT_IN_PROGRESS",
				{"residentId": resident_id},
			),
			"retry": _action(
				"inner_observation.retry",
				retry_enabled,
				"NO_RETRYABLE_ERROR",
				{"residentId": resident_id},
			),
		},
		operation,
		error_value,
		true,
		false,
	)


func _inner_observation_resident(
	resident_id: String,
	resident_name: String,
) -> Dictionary:
	# 居民 ID 才是稳定身份；姓名只是旧世界/测试替身仍支持的兼容入口。
	# 同名居民合法存在时，不能先按姓名查询，否则可能把另一人的实时外观
	# 投影到当前居民的内观察页面。
	var detail := _resident_detail(resident_id)
	if detail.is_empty():
		detail = _resident_detail(resident_name)
	var live_attributes := detail.get("attributes", {}) as Dictionary
	var portrait := _resident_portrait_projection(
		resident_id,
		live_attributes,
	)
	var portrait_path := String(portrait.get("portraitRef", "")).strip_edges()
	var portrait_ready := (
		not portrait_path.is_empty()
		and ResourceLoader.exists(portrait_path, "Texture2D")
	)
	var source_kind := "placeholder"
	if portrait_ready:
		source_kind = (
			"true_bust_portrait"
			if portrait_path.contains("/portraits/")
			else "front_walk_frame"
		)
	return {
		"residentId": resident_id,
		"displayName": resident_name,
		"expressionId": "calm",
		"portrait": {
			# 使用当前小镇居民的正式外观；自定义居民不依赖内置目录。
			"assetPath": portrait_path if portrait_ready else "",
			"sourceKind": source_kind,
			"status": "ready" if portrait_ready else "missing",
			"atlasRegion": {
				"x": 0,
				"y": 0,
				"width": 0,
				"height": 0,
			},
		},
	}


func _cancel_inner_observation_request() -> void:
	var request_id := String(
		_inner_observation_state.get("requestId", "")
	)
	if (
		not request_id.is_empty()
		and _gateway != null
		and _gateway.has_method(
			"cancel_resident_inner_observation"
		)
	):
		_gateway.call(
			"cancel_resident_inner_observation",
			request_id,
		)


func _close_inner_observation_state() -> void:
	_cancel_inner_observation_request()
	_inner_observation_generation += 1
	_inner_observation_state.clear()
	_page_contexts["inner_observation"] = {
		"open": false,
	}


func _on_resident_death_story_result(
	result: Dictionary,
	resident_id: String,
	request_id: String,
) -> void:
	var pending := _death_story_inflight.get(resident_id, {}) as Dictionary
	if (
		pending.is_empty()
		or String(pending.get("requestId", "")) != request_id
	):
		return
	_death_story_inflight.erase(resident_id)
	var submitted_at := int(pending.get("submittedAtMsec", Time.get_ticks_msec()))
	var story := String(result.get("story", "")).strip_edges()
	if not bool(result.get("ok", false)) or story.is_empty():
		story = DEATH_STORY_FALLBACK
	if _world == null or not _world.has_method("confirm_resident_death"):
		_publish_failure(
			"resident_action_menu",
			"resident.death.confirm",
			request_id,
			submitted_at,
			{
				"ok": false,
				"errorCode": "RESIDENT_DEATH_INTERFACE_MISSING",
				"retryable": false,
				"errors": ["死亡确认接口不可用"],
			},
		)
		return
	var confirmed := _world.confirm_resident_death(
		resident_id,
		story,
		int(pending.get("lifecycleRevision", -1)),
		String(pending.get("worldInstanceToken", "")),
	) as Dictionary
	if bool(confirmed.get("ok", false)):
		_publish_resident_action_menu(
			_operation(
				request_id,
				"resident.death.confirm",
				"success",
				submitted_at,
				Time.get_ticks_msec(),
			),
			null,
		)
		return
	_publish_failure(
		"resident_action_menu",
		"resident.death.confirm",
		request_id,
		submitted_at,
		confirmed,
	)


func _dispatch_place_focus(
	intent: String,
	payload: Dictionary,
	request_id: String,
) -> Dictionary:
	var submitted_at := Time.get_ticks_msec()
	var context := (_page_contexts.get("place_focus", {}) as Dictionary).duplicate(true)
	var place_name := String(payload.get("placeName", context.get("placeName", ""))).strip_edges()
	if place_name.is_empty():
		var space_id := String(payload.get("spaceId", ""))
		place_name = _place_name_for_space_id(space_id)
	if _place_detail(place_name).is_empty():
		return _dispatch_failure("PLACE_FOCUS_PLACE_NOT_FOUND", false, request_id)
	context["placeName"] = place_name
	context["open"] = true
	_page_contexts["place_focus"] = context
	match intent:
		"place_focus.open_resident":
			return _dispatch_failure(
				"RESIDENT_DIRECT_SELECTION_REQUIRED",
				false,
				request_id,
			)
		"place_focus.open_event", "place_focus.open_log":
			var entry_id := String(payload.get(
				"eventId" if intent.ends_with("open_event") else "logEntryId",
				"",
			)).strip_edges()
			var resolved_thread_id := _resolve_world_log_thread_id(entry_id)
			if resolved_thread_id.is_empty():
				return _dispatch_failure("PLACE_FOCUS_LOG_NOT_FOUND", false, request_id)
			_town_log_open = true
			_town_log_selected_entry_id = resolved_thread_id
			_publish_town_log(_idle_operation(), null)
		"place_focus.enter_interior", "place_focus.retry":
			if _runtime == null or not _runtime.has_method("request_observe_place"):
				return _dispatch_failure("PLACE_OBSERVATION_INTERFACE_MISSING", false, request_id)
			var result := _runtime.call("request_observe_place", place_name) as Dictionary
			if not bool(result.get("ok", false)):
				_publish_place_focus(
					_operation(request_id, intent, "rejected", submitted_at, Time.get_ticks_msec()),
					result,
				)
				return _command_dispatch_result(request_id, result)
			_pending_place_focus_operation = {
				"requestId": request_id,
				"intent": intent,
				"submittedAtMsec": submitted_at,
				"placeName": place_name,
			}
			_publish_place_focus(
				_operation(request_id, intent, "loading", submitted_at, 0),
				null,
			)
			return _dispatch_success(request_id)
		"place_focus.open_interactable":
			return _dispatch_failure("PLACE_INTERACTABLE_REQUIRES_INDOOR_ENTRY", false, request_id)
		_:
			return _dispatch_failure("PLACE_FOCUS_ACTION_NOT_AVAILABLE", false, request_id)
	_publish_place_focus(
		_operation(request_id, intent, "success", submitted_at, Time.get_ticks_msec()),
		null,
	)
	return _dispatch_success(request_id)


func _dispatch_town_log(
	intent: String,
	payload: Dictionary,
	request_id: String,
) -> Dictionary:
	var submitted_at := Time.get_ticks_msec()
	match intent:
		"town_log.open":
			_town_log_open = true
			_reload_town_log_threads()
			var requested_thread_id := String(
				payload.get("threadId", ""),
			).strip_edges()
			if not requested_thread_id.is_empty():
				_load_town_log_detail(requested_thread_id, false)
		"town_log.close":
			_town_log_open = false
		"town_log.set_filter":
			var filter_result := _set_town_log_filter(payload)
			if filter_result.get("ok") != true:
				return _dispatch_failure(
					String(filter_result.get("errorCode", "TOWN_LOG_FILTER_INVALID")),
					false,
					request_id,
				)
			_reload_town_log_threads()
		"town_log.toggle_unread":
			_town_log_filters["unreadOnly"] = bool(
				payload.get(
					"unreadOnly",
					not bool(_town_log_filters.get("unreadOnly", false)),
				),
			)
			_reload_town_log_threads()
		"town_log.select_thread":
			var thread_id := String(payload.get("threadId", "")).strip_edges()
			if not _town_log_rows.any(
				func(row: Dictionary) -> bool:
					return String(row.get("threadId", "")) == thread_id
			):
				return _dispatch_failure("WORLD_LOG_THREAD_NOT_FOUND", false, request_id)
			var detail_result := _load_town_log_detail(thread_id, false)
			if detail_result.get("ok") != true:
				return _dispatch_failure(
					String(detail_result.get("errorCode", "WORLD_LOG_DETAIL_FAILED")),
					bool(detail_result.get("retryable", false)),
					request_id,
				)
		"town_log.back_to_list":
			_town_log_selected_entry_id = ""
			_town_log_detail = null
			_town_log_detail_paging = {
				"cursor": 0,
				"hasMore": false,
				"isLoading": false,
			}
		"town_log.load_more":
			var more_result := _load_more_town_log_threads()
			if more_result.get("ok") != true:
				return _dispatch_failure(
					String(more_result.get("errorCode", "WORLD_LOG_QUERY_FAILED")),
					bool(more_result.get("retryable", false)),
					request_id,
				)
		"town_log.load_more_detail":
			var detail_more_result := _load_town_log_detail(
				_town_log_selected_entry_id,
				true,
			)
			if detail_more_result.get("ok") != true:
				return _dispatch_failure(
					String(detail_more_result.get("errorCode", "WORLD_LOG_DETAIL_FAILED")),
					bool(detail_more_result.get("retryable", false)),
					request_id,
				)
		"town_log.refresh_newer", "town_log.retry":
			_reload_town_log_threads()
		_:
			return _dispatch_failure("TOWN_LOG_ACTION_NOT_AVAILABLE", false, request_id)
	_publish_town_log(
		_operation(request_id, intent, "success", submitted_at, Time.get_ticks_msec()),
		null,
	)
	return _dispatch_success(request_id)


func _dispatch_wardrobe(intent: String, request_id: String) -> Dictionary:
	if intent == "wardrobe.cancel":
		return _dispatch_success(request_id)
	return _dispatch_failure("WARDROBE_INTERFACE_MISSING", false, request_id)


func _dispatch_indoor(
	intent: String,
	payload: Dictionary,
	request_id: String,
) -> Dictionary:
	var submitted_at := Time.get_ticks_msec()
	if intent == "indoor.dismiss_feedback":
		_publish_indoor(
			_operation(request_id, intent, "success", submitted_at, Time.get_ticks_msec()),
			null,
		)
		return _dispatch_success(request_id)
	if (
		intent == "indoor.return_outdoor"
		and String(_read_runtime_state().get("viewMode", "town")) != "interior"
	):
		_publish_indoor(
			_operation(request_id, intent, "success", submitted_at, Time.get_ticks_msec()),
			null,
		)
		return _dispatch_success(request_id)
	var result := false
	var command_failure: Dictionary = {}
	if intent == "indoor.return_outdoor":
		if _runtime != null and _runtime.has_method("request_return_to_town_overview"):
			var return_result := _runtime.call("request_return_to_town_overview") as Dictionary
			if (
				bool(return_result.get("ok", false))
				and bool(return_result.get("pending", false))
			):
				_pending_indoor_return_operation = {
					"requestId": request_id,
					"intent": intent,
					"submittedAtMsec": submitted_at,
					"placeName": String(
						_read_runtime_state().get("observedPlace", "")
					),
				}
				_publish_indoor(
					_operation(request_id, intent, "loading", submitted_at, 0),
					null,
				)
				return _dispatch_success(request_id)
			result = bool(return_result.get("ok", false))
			if not result:
				command_failure = return_result.duplicate(true)
		else:
			command_failure = {
				"ok": false,
				"errorCode": "INDOOR_RETURN_INTERFACE_MISSING",
				"retryable": false,
				"errors": [],
			}
	elif intent == "indoor.focus_target":
		var resident_id := String(payload.get("residentId", ""))
		if resident_id.is_empty():
			var target := _indoor_target_by_id(String(payload.get("targetId", "")))
			resident_id = String(target.get("residentId", ""))
		var resident_name := _resident_name_for_id(resident_id)
		if not resident_name.is_empty():
			result = bool(_runtime.call("select_resident", resident_name))
	elif intent == "indoor.focus_event":
		var event_id := String(payload.get("eventId", ""))
		var event_entry := _world_log_thread_item(
			_resolve_world_log_thread_id(event_id),
		)
		if not event_entry.is_empty():
			var current_indoor := _view_models.get("indoor", {}) as Dictionary
			var current_place := String(
				((current_indoor.get("data", {}) as Dictionary).get(
					"location",
					{},
				) as Dictionary).get("placeName", "")
			)
			if String(event_entry.get("placeLabel", "")) == current_place:
				result = true
				_indoor_focused_event_id = String(event_entry.get("id", ""))
				var resident_id := String(event_entry.get("focusResidentId", ""))
				var resident_name := _resident_name_for_id(resident_id)
				if (
					not resident_name.is_empty()
					and _runtime != null
					and _runtime.has_method("select_resident")
				):
					_runtime.call("select_resident", resident_name)
	if result:
		_publish_indoor(
			_operation(request_id, intent, "success", submitted_at, Time.get_ticks_msec()),
			null,
		)
		return _dispatch_success(request_id)
	var failure: Dictionary = command_failure if not command_failure.is_empty() else {
		"ok": false,
		"errorCode": "INDOOR_ACTION_REJECTED",
		"retryable": false,
		"errors": [],
	}
	_publish_indoor(
		_operation(request_id, intent, "rejected", submitted_at, Time.get_ticks_msec()),
		failure,
	)
	return _command_dispatch_result(request_id, failure)


func _publish_weather(
	operation: Dictionary,
	error_value: Variant,
	feedback: Variant = null,
) -> void:
	var available := (
		_world != null
		and _world.has_method("get_weather")
		and _world.has_method("set_weather")
	)
	var formal_ready := available and _session_formal_ready()
	var options: Array[Dictionary] = []
	for weather_id in WEATHER_IDS:
		var copy := (WEATHER_COPY.get(weather_id, {}) as Dictionary).duplicate(true)
		copy["id"] = weather_id
		copy["label"] = weather_id
		copy["enabled"] = available
		copy["disabledReason"] = "" if available else "WEATHER_CONTROL_INTERFACE_MISSING"
		options.append(copy)
	var current := _read_weather()
	var current_copy := WEATHER_COPY.get(current, {}) as Dictionary
	var runtime_state := _read_runtime_state()
	var avatar_mode := String(runtime_state.get("avatarMode", "observer"))
	var in_overview := avatar_mode == "observer"
	var data := {
		"source": "runtime",
		"capabilityMode": _session_capability_mode() if available else "unavailable",
		"formalReady": formal_ready,
		"internalPlaytest": _session_internal_playtest(),
		"mode": {
			"id": "overview" if in_overview else "avatar",
			"label": "俯瞰模式" if in_overview else "化身模式",
			"avatarMode": avatar_mode,
		},
		"currentWeather": {
			"id": current,
			"label": current,
			"iconId": String(current_copy.get("iconId", "weather_sunny")),
		},
		"weatherOptions": options,
		"lastConfirmedFeedback": feedback,
	}
	var busy := String(operation.get("status", "")) == "loading"
	var effective_error: Variant = error_value
	if not available and effective_error == null:
		effective_error = _error_payload(
			"WEATHER_CONTROL_INTERFACE_MISSING",
			false,
			"世界天气公共接口尚未绑定。",
		)
	var actions := {
		"weatherChange": _action(
			"environment.weather_change",
			available and in_overview and not busy,
			(
				"OPERATION_IN_PROGRESS"
				if busy
				else "SWITCH_TO_OVERVIEW_REQUIRED"
				if not in_overview
				else "WEATHER_CONTROL_INTERFACE_MISSING"
			),
		),
		"switchToOverview": _action(
			"avatar.switch_to_overview",
			not in_overview and not busy and _runtime != null and _runtime.has_method("exit_avatar_mode"),
			"OPERATION_IN_PROGRESS" if busy else "ALREADY_IN_OVERVIEW" if in_overview else "AVATAR_MODE_INTERFACE_MISSING",
		),
	}
	_store_view_model(
		"weather_control",
		"ready" if available else "disabled",
		data,
		actions,
		operation,
		effective_error,
	)


func _publish_announcements(operation: Dictionary, error_value: Variant) -> void:
	var available := (
		_runtime != null
		and _runtime.has_method("publish_player_announcement")
		and _world != null
		and _world.has_method("get_announcements")
	)
	var formal_ready := available and _session_formal_ready()
	var draft_count := _announcement_draft.length()
	var validation_code := ""
	if _announcement_composer_open and _announcement_draft.strip_edges().is_empty():
		validation_code = "EMPTY_ANNOUNCEMENT"
	elif draft_count > ANNOUNCEMENT_LIMIT:
		validation_code = "ANNOUNCEMENT_TOO_LONG"
	var dialog := {
		"open": _announcement_dialog_open,
		"kind": "unsaved_draft" if _announcement_dialog_open else "none",
		"title": "尚未发布" if _announcement_dialog_open else "",
		"message": "要继续编辑，还是放弃这段公告？" if _announcement_dialog_open else "",
	}
	var feedback := _announcement_feedback.duplicate(true)
	if feedback.is_empty():
		feedback = {
			"visible": false,
			"kind": "none",
			"title": "",
			"message": "",
			"durationMs": 0,
			"blocksInput": false,
		}
	var data := {
		"capabilityMode": _session_capability_mode() if available else "unavailable",
		"source": "runtime",
		"formalReady": formal_ready,
		"panel": {
			"open": _announcement_panel_open,
			"mode": "compose" if _announcement_composer_open else "browse",
			"title": "公告栏",
			"worldContinues": true,
			"focusTarget": "composerInput" if _announcement_composer_open else "openComposer",
		},
		"items": _announcement_items(),
		"emptyState": {
			"title": "公告栏还是空的",
			"message": "发布一条公告，让全镇都知道。",
		},
		"composer": {
			"open": _announcement_composer_open,
			"publisherLabel": "发布者：旅行者",
			"draftText": _announcement_draft,
			"characterCount": draft_count,
			"characterLimit": ANNOUNCEMENT_LIMIT,
			"remainingCount": ANNOUNCEMENT_LIMIT - draft_count,
			"validationCode": validation_code,
			"inputFocused": _announcement_composer_open and not _announcement_dialog_open,
			"softKeyboardVisible": false,
			"keyboardSubmitBehavior": "dismiss_only",
		},
		"dialog": dialog,
		"feedback": feedback,
	}
	var busy := String(operation.get("status", "")) == "loading"
	var composer_available := available and _announcement_composer_open and not busy
	var publish_available := composer_available and validation_code.is_empty()
	var actions := {
		"openComposer": _action(
			"announcements.composer.open",
			available and not _announcement_composer_open and not busy,
			"COMPOSER_ALREADY_OPEN" if _announcement_composer_open else "ANNOUNCEMENTS_INTERFACE_MISSING",
		),
		"updateDraft": _action(
			"announcements.draft.update",
			composer_available,
			"COMPOSER_CLOSED" if not _announcement_composer_open else "OPERATION_IN_PROGRESS",
		),
		"publish": _action(
			"announcements.publish",
			publish_available,
			validation_code if not validation_code.is_empty() else "OPERATION_IN_PROGRESS" if busy else "COMPOSER_CLOSED",
		),
		"requestClose": _action(
			"announcements.panel.close", available and not busy, "OPERATION_IN_PROGRESS"
		),
		"continueEditing": _action(
			"announcements.draft.continue", _announcement_dialog_open, "DIALOG_CLOSED"
		),
		"discardDraft": _action(
			"announcements.draft.discard", _announcement_dialog_open, "DIALOG_CLOSED"
		),
		"retry": _action(
			"announcements.retry", _announcement_retryable and not busy, "NO_RETRYABLE_ERROR"
		),
		"dismissFeedback": _action(
			"announcements.feedback.dismiss", bool(feedback.get("visible", false)), "FEEDBACK_HIDDEN"
		),
	}
	_store_view_model(
		"announcements",
		"ready" if available else "disabled",
		data,
		actions,
		operation,
		error_value,
	)


func _publish_resident_action_menu(operation: Dictionary, error_value: Variant) -> void:
	var target := _resident_target()
	var resident_id := String(target.get("residentId", ""))
	var resident_name := String(target.get("residentName", ""))
	var resident_lifecycle := (
		_resident_state(resident_name).get("lifecycle", {}) as Dictionary
	)
	var resident_alive := not bool(resident_lifecycle.get("isDead", false))
	var observer_mode := (
		String(_read_runtime_state().get("avatarMode", "observer"))
		== "observer"
	)
	var follow_available := (
		not resident_id.is_empty()
		and not resident_name.is_empty()
		and resident_alive
		and _runtime != null
		and _runtime.has_method("follow_resident")
	)
	var detail_page_available := (
		not resident_id.is_empty()
		and not resident_name.is_empty()
	)
	var inner_available := (
		not resident_id.is_empty()
		and resident_alive
		and _session_formal_ready()
	)
	var death_available := (
		not resident_id.is_empty()
		and resident_alive
		and observer_mode
		and _session_formal_ready()
		and _world != null
		and _world.has_method("confirm_resident_death")
	)
	var death_story_pending := _death_story_inflight.has(resident_id)
	var formal_ready := (
		not resident_id.is_empty()
		and _session_formal_ready()
	)
	var menu_available := (
		follow_available
		or detail_page_available
		or inner_available
	)
	var placement := _resident_placement(resident_name)
	var menu_ready := menu_available
	var menu_items: Array[Dictionary] = [
		{"id": "follow", "actionKey": "follow", "label": "跟随", "iconKey": "follow_camera", "semanticOrder": 0},
		{"id": "status", "actionKey": "openStatus", "label": "状态", "iconKey": "resident_status", "semanticOrder": 1},
		{"id": "relationship", "actionKey": "openRelationship", "label": "关系", "iconKey": "resident_relationship", "semanticOrder": 2},
		{"id": "memory", "actionKey": "openMemory", "label": "记忆", "iconKey": "resident_memory", "semanticOrder": 3},
		{"id": "inner", "actionKey": "openInner", "label": "内心", "iconKey": "inner_observation", "semanticOrder": 4},
	]
	if death_available or death_story_pending:
		menu_items.append({
			"id": "kill",
			"actionKey": "killResident",
			"label": "正在生成死因" if death_story_pending else "杀死",
			"iconKey": "resident_death",
			"semanticOrder": 5,
		})
	var data := {
		"source": "town_ui_adapter" if menu_ready else "placeholder",
		"capabilityMode": _session_capability_mode() if menu_ready else "placeholder",
		"formalReady": formal_ready,
		"phase": (
			"closed"
			if not bool((_page_contexts.get("resident_action_menu", {}) as Dictionary).get("open", true))
			else "menu"
		),
		"resident": {
			"residentId": resident_id,
			"residentName": resident_name if not resident_name.is_empty() else "居民",
			"identityStatus": String(target.get("identityStatus", "unavailable")),
			"portraitKey": resident_id,
			"lifecycleStatus": String(resident_lifecycle.get("lifecycleStatus", "alive")),
			"statusLabel": String(resident_lifecycle.get("statusLabel", "生活中")),
		},
		"world": {
			"paused": false,
			"pauseReasonId": "",
			"pauseLabel": "查看期间，小镇仍在运行",
		},
		"placement": placement,
		"menuItems": menu_items,
		"feedback": {
			"kind": "none" if menu_ready else "disabled",
			"message": "" if menu_ready else (
				"正在准备居民查看。"
				if menu_available
				else "居民身份暂不可用"
			),
		},
		"motion": {
			"reduceMotion": false,
			"openingDurationMs": 280,
			"itemStaggerMs": 28,
			"breathPeriodMs": 2100,
		},
	}
	var actions := {
		"follow": _action(
			"resident.follow", follow_available, "" if follow_available else ("RESIDENT_DEAD" if not resident_alive else "RESIDENT_IDENTITY_UNAVAILABLE"), {"residentId": resident_id}
		),
		"openStatus": _action(
			"resident.detail.open", detail_page_available, "" if detail_page_available else "RESIDENT_IDENTITY_UNAVAILABLE", {"residentId": resident_id, "tab": "status"}
		),
		"openRelationship": _action(
			"resident.detail.open", detail_page_available, "" if detail_page_available else "RESIDENT_IDENTITY_UNAVAILABLE", {"residentId": resident_id, "tab": "relationship"}
		),
		"openMemory": _action(
			"resident.detail.open", detail_page_available, "" if detail_page_available else "RESIDENT_IDENTITY_UNAVAILABLE", {"residentId": resident_id, "tab": "memory"}
		),
		"openInner": _action(
			"resident.inner_observation.open", inner_available, "" if inner_available else ("RESIDENT_DEAD" if not resident_alive else "INNER_OBSERVATION_INTERFACE_MISSING"), {"residentId": resident_id}
		),
		"killResident": _action(
			"resident.death.confirm",
			death_available and not death_story_pending,
			"DEATH_STORY_IN_PROGRESS" if death_story_pending else ("" if death_available else (
				"RESIDENT_DEAD"
				if not resident_alive
				else ("OBSERVER_MODE_REQUIRED" if not observer_mode else "RESIDENT_DEATH_INTERFACE_MISSING")
			)),
			{
				"residentId": resident_id,
				"residentName": resident_name,
				"worldInstanceToken": str(_world.get_instance_id()) if _world != null else "",
				"lifecycleRevision": int(resident_lifecycle.get("revision", -1)),
			},
		),
		"close": _action(
			"resident.action_menu.close", true, "", {"residentId": resident_id}
		),
	}
	_store_view_model(
		"resident_action_menu",
		"ready" if menu_ready else "disabled",
		data,
		actions,
		operation,
		error_value,
	)


func _publish_resident_overview(
	operation: Dictionary,
	error_value: Variant,
) -> void:
	var identities := _resident_identities()
	identities.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			var left_record := _resident_catalog_record(
				String(left.get("residentId", "")),
			)
			var right_record := _resident_catalog_record(
				String(right.get("residentId", "")),
			)
			return int(left_record.get("_ordinal", 9999)) < int(
				right_record.get("_ordinal", 9999),
			)
	)
	var residents: Array[Dictionary] = []
	for identity in identities:
		var resident_id := String(identity.get("residentId", ""))
		var resident_name := String(identity.get("residentName", ""))
		var detail := _resident_detail(resident_name)
		if detail.is_empty():
			continue
		var attributes := detail.get("attributes", {}) as Dictionary
		var social := detail.get("socialState", {}) as Dictionary
		var runtime_state := detail.get("runtimeState", {}) as Dictionary
		var action_phase := runtime_state.get("actionPhase", {}) as Dictionary
		var catalog_record := _resident_catalog_record(resident_id)
		var catalog_attributes := catalog_record.get("attributes", {}) as Dictionary
		var presentation := catalog_record.get("presentation", {}) as Dictionary
		var appearance_id := String(attributes.get("appearance", "")).strip_edges()
		if appearance_id.is_empty():
			appearance_id = String(
				catalog_attributes.get("appearance", ""),
			).strip_edges()
		var portrait_ref := _resident_overview_portrait_ref(
			appearance_id,
			presentation,
		)
		var job := String(social.get("job", "")).strip_edges()
		var workplace := String(social.get("workplace", "")).strip_edges()
		var action_label := String(action_phase.get("summary", "")).strip_edges()
		if action_label.is_empty():
			action_label = String(runtime_state.get("doing", "")).strip_edges()
		if action_label.is_empty():
			var current_action_value: Variant = runtime_state.get("currentAction")
			if current_action_value is Dictionary:
				action_label = String(
					(current_action_value as Dictionary).get("type", ""),
				).strip_edges()
		if action_label.is_empty():
			action_label = "暂无公开行动"
		residents.append({
			"residentId": resident_id,
			"displayName": resident_name,
			"identityStatus": String(identity.get("identityStatus", "unavailable")),
			"genderLabel": String(attributes.get("gender", "未知")),
			"age": int(attributes.get("age", 0)),
			"appearanceId": appearance_id,
			"desire": String(attributes.get("desire", "")),
			"personality": String(attributes.get("personality", "")),
			"speech": String(attributes.get("speech", "")),
			"interests": (
				attributes.get("interests", []) as Array
			).duplicate(),
			"customInterests": (
				attributes.get("customInterests", []) as Array
			).duplicate(),
				"portraitRef": portrait_ref,
				"portraitFrameMode": (
					"full_texture"
					if portrait_ref.contains("/wardrobe_v1/")
					else "legacy_atlas_64x64"
				),
			"homeLabel": String(social.get("home", "")),
			"occupationLabel": job,
			"workplaceLabel": workplace,
			"currentPlaceLabel": String(runtime_state.get("currentPlace", "")),
			"currentActionLabel": action_label,
			"actionPhaseLabel": _resident_overview_phase_label(
				String(action_phase.get("phase", "idle")),
			),
			"availabilityLabel": (
				"可跟随"
				if _runtime != null and _runtime.has_method("follow_resident")
				else "只读"
			),
		})
	var context := _page_contexts.get("resident_overview", {}) as Dictionary
	var selected_resident_id := String(
		context.get(
			"selectedResidentId",
			context.get("residentId", ""),
		),
	).strip_edges()
	if (
		selected_resident_id.is_empty()
		or not _resident_overview_has_resident(residents, selected_resident_id)
	):
		selected_resident_id = (
			String(residents[0].get("residentId", ""))
			if not residents.is_empty()
			else ""
		)
	var available := not residents.is_empty()
	var follow_available := (
		available
		and _runtime != null
		and _runtime.has_method("follow_resident")
	)
	var data := {
		"capabilityMode": _session_capability_mode() if available else "unavailable",
		"source": "runtime",
		"formalReady": available and _session_formal_ready(),
		"contractVersion": "resident-overview-runtime-v1",
		"residentCount": residents.size(),
		"selectedResidentId": selected_resident_id,
		"residents": residents,
		"managementMode": "runtime_profile_management",
		"options": _resident_overview_options(residents),
	}
	var effective_error: Variant = error_value
	if not available and effective_error == null:
		effective_error = _error_payload(
			"RESIDENT_OVERVIEW_DATA_UNAVAILABLE",
			false,
			"居民运行资料暂不可用。",
		)
	_store_view_model(
		"resident_overview",
		"ready" if available else "disabled",
		data,
		{
			"follow": _action(
				"resident_overview.follow",
				follow_available,
				"RESIDENT_FOLLOW_INTERFACE_MISSING",
			),
			"updateProfile": _action(
				"resident_overview.update_profile",
				(
					available
					and _world != null
					and _world.has_method("update_resident_profile")
				),
				"RESIDENT_PROFILE_UPDATE_INTERFACE_MISSING",
			),
		},
		operation,
		effective_error,
	)


func _resident_overview_options(
	residents: Array[Dictionary],
) -> Dictionary:
	var home_labels: Array[String] = []
	var occupation_labels: Array[String] = []
	var workplace_labels: Array[String] = []
	for resident in residents:
		var home_label := String(resident.get("homeLabel", "")).strip_edges()
		if not home_label.is_empty() and home_label not in home_labels:
			home_labels.append(home_label)
		var occupation_label := String(
			resident.get("occupationLabel", ""),
		).strip_edges()
		if (
			not occupation_label.is_empty()
			and occupation_label not in occupation_labels
		):
			occupation_labels.append(occupation_label)
		var workplace_label := String(
			resident.get("workplaceLabel", ""),
		).strip_edges()
		if (
			not workplace_label.is_empty()
			and workplace_label not in workplace_labels
		):
			workplace_labels.append(workplace_label)
	if _world != null and _world.has_method("get_all_place_details"):
		for place_value: Variant in _world.get_all_place_details() as Array:
			if not place_value is Dictionary:
				continue
			var place := place_value as Dictionary
			var place_name := String(place.get("name", "")).strip_edges()
			var place_type := String(place.get("type", "")).strip_edges()
			if place_name.is_empty():
				continue
			if place_type == "住家" and place_name not in home_labels:
				home_labels.append(place_name)
			elif (
				place_type in ["铺面", "公共地点"]
				and place_name not in workplace_labels
			):
				workplace_labels.append(place_name)
	home_labels.sort()
	occupation_labels.sort()
	workplace_labels.sort()
	return {
		"homes": _resident_overview_option_records(home_labels),
		"occupations": _resident_overview_option_records(occupation_labels),
		"workplaces": _resident_overview_option_records(workplace_labels),
	}


func _resident_overview_option_records(
	labels: Array[String],
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for label in labels:
		result.append({"id": label, "label": label})
	return result


func _publish_resident_detail(operation: Dictionary, error_value: Variant) -> void:
	var context := _page_contexts.get("resident_detail", {}) as Dictionary
	var resident_id := String(context.get("residentId", "")).strip_edges()
	var resident_name := _resident_name_for_id(resident_id)
	var detail := _resident_detail(resident_name)
	var available := not detail.is_empty()
	var page_available := (
		not resident_id.is_empty()
		and not resident_name.is_empty()
	)
	var runtime_state := detail.get("runtimeState", {}) as Dictionary
	var resident_lifecycle := runtime_state.get("lifecycle", {}) as Dictionary
	var attributes := detail.get("attributes", {}) as Dictionary
	var social_state := detail.get("socialState", {}) as Dictionary
	var portrait_projection := _resident_portrait_projection(
		resident_id,
		attributes,
	)
	var memory_result: Dictionary = {}
	if (
		page_available
		and _gateway != null
		and _gateway.has_method("get_resident_memory")
	):
		memory_result = _gateway.call("get_resident_memory", resident_id) as Dictionary
	var memory_available := bool(memory_result.get("ok", false))
	var memory := memory_result.get("memory", {}) as Dictionary
	var relationship_available := (
		memory_available
		and memory.has("relationships")
	)
	var important_memory_available := (
		memory_available
		and memory.has("formal_memories")
	)
	var memory_action_disabled_reason := (
		""
		if important_memory_available
		else (
			"RESIDENT_MEMORY_NOT_READY"
			if page_available
			else "RESIDENT_IDENTITY_UNAVAILABLE"
		)
	)
	var selected_tab := String(context.get("selectedTab", "status"))
	if selected_tab not in ["status", "relationships", "memories"]:
		selected_tab = "status"
	var content := _resident_detail_content(
		selected_tab,
		attributes,
		runtime_state,
		memory,
		relationship_available,
		important_memory_available,
		resident_id,
		available,
		String(context.get("relationshipFilter", "all")),
		String(context.get("memoryFilter", "influencing")),
		maxi(0, int(context.get("memoryPage", 0))),
	)
	var lifecycle := _read_lifecycle()
	var formal_ready := page_available and _session_formal_ready()
	var unavailable_sections: Array[String] = []
	if not relationship_available:
		unavailable_sections.append("relationships")
	if not important_memory_available:
		unavailable_sections.append("memories")
	var data := {
		"capabilityMode": _session_capability_mode() if page_available else "unavailable",
		"source": "town_ui_adapter",
		"formalReady": formal_ready,
		"contractVersion": "resident-detail-public-v1",
		"resident": {
			"residentId": resident_id,
			"displayName": resident_name,
			"occupationLabel": String(social_state.get("job", "")),
			"currentPlaceLabel": String(runtime_state.get("currentPlace", "")),
			"identityStatus": "confirmed" if page_available else "unavailable",
			"portrait": String(portrait_projection.get("portraitRef", "")),
			"portraitFrameMode": String(
				portrait_projection.get("portraitFrameMode", "auto"),
			),
			"appearanceId": String(
				portrait_projection.get("appearanceId", ""),
			),
			"lifecycleStatus": String(resident_lifecycle.get("lifecycleStatus", "alive")),
			"lifecycleStatusLabel": String(resident_lifecycle.get("statusLabel", "生活中")),
			"appearancePolicy": String(resident_lifecycle.get("appearancePolicy", "normal")),
			"deathSummary": (resident_lifecycle.get("deathSummary", {}) as Dictionary).duplicate(true),
			},
			"context": {
				"worldRunState": String(lifecycle.get("state", "running")),
				"contextLabel": "查看期间，小镇仍在运行",
				"pauseReasonId": "",
				"presentationMode": "full_overlay",
		},
		"selectedTab": selected_tab,
		"tabs": [
			{"id": "status", "label": "状态", "availability": "ready" if page_available else "disabled", "disabledReason": "" if page_available else "RESIDENT_IDENTITY_UNAVAILABLE"},
			{"id": "relationships", "label": "关系", "availability": "ready" if page_available else "disabled", "disabledReason": "" if page_available else "RESIDENT_IDENTITY_UNAVAILABLE"},
			{"id": "memories", "label": "记忆", "availability": "ready" if page_available else "disabled", "disabledReason": "" if page_available else "RESIDENT_IDENTITY_UNAVAILABLE"},
		],
		"content": content,
		"freshness": {
			"state": "fresh" if relationship_available and important_memory_available else ("partial" if page_available else "unavailable"),
			"lastConfirmedRevision": _read_world_revision(),
			"updatedLabel": _time_label(_world.get_time() as Dictionary if _world != null and _world.has_method("get_time") else {}),
			"retainedFromRevision": int(_last_confirmed_revision.get("resident_detail", -1)),
			"retainedSections": [],
			"unavailableSections": unavailable_sections,
		},
		"privacy": {
			"policyId": "resident-detail-public-summary-v1",
			"publicSummaryOnly": true,
			"sanitizedUpstream": true,
			"containsAgentPrivateText": false,
		},
	}
	var effective_error: Variant = error_value
	var memory_error_code := String(
		memory_result.get("errorCode", "RESIDENT_PUBLIC_SUMMARY_UNAVAILABLE")
	)
	if not page_available and effective_error == null:
		effective_error = _error_payload("RESIDENT_IDENTITY_UNAVAILABLE", false, "居民身份暂不可用。")
	elif (
		effective_error == null
		and selected_tab in ["relationships", "memories"]
		and not memory_available
	):
		effective_error = _error_payload(
			memory_error_code,
			bool(memory_result.get("retryable", false)),
			_resident_memory_error_message(memory_error_code),
		)
	elif not available and selected_tab == "status" and effective_error == null:
		effective_error = _error_payload("RESIDENT_DETAIL_INTERFACE_MISSING", false, "居民公开详情暂不可用。")
	_store_view_model(
		"resident_detail",
		(
			("ready" if relationship_available and important_memory_available else "partial")
			if page_available
			else "disabled"
		),
		data,
		{
			"close": _action("resident_detail.close", true, "", {"residentId": resident_id}),
			"selectStatus": _action("resident_detail.select_tab", page_available, "" if page_available else "RESIDENT_IDENTITY_UNAVAILABLE", {"residentId": resident_id, "tabId": "status"}),
			"selectRelationships": _action("resident_detail.select_tab", page_available, "" if page_available else "RESIDENT_IDENTITY_UNAVAILABLE", {"residentId": resident_id, "tabId": "relationships"}),
			"selectMemories": _action("resident_detail.select_tab", page_available, "" if page_available else "RESIDENT_IDENTITY_UNAVAILABLE", {"residentId": resident_id, "tabId": "memories"}),
			"refresh": _action("resident_detail.refresh", page_available, "" if page_available else "RESIDENT_IDENTITY_UNAVAILABLE", {"residentId": resident_id}),
			"retry": _action("resident_detail.retry", effective_error is Dictionary and bool((effective_error as Dictionary).get("retryable", false)), "NO_RETRYABLE_ERROR", {"residentId": resident_id}),
			"filterInfluencing": _action("resident_detail.filter_memories", important_memory_available, memory_action_disabled_reason, {"residentId": resident_id, "filterId": "influencing"}),
			"filterAll": _action("resident_detail.filter_memories", important_memory_available, memory_action_disabled_reason, {"residentId": resident_id, "filterId": "all"}),
			"filterPast": _action("resident_detail.filter_memories", important_memory_available, memory_action_disabled_reason, {"residentId": resident_id, "filterId": "past"}),
			"filterDoubtful": _action("resident_detail.filter_memories", important_memory_available, memory_action_disabled_reason, {"residentId": resident_id, "filterId": "doubtful"}),
			"filterAnomalous": _action("resident_detail.filter_memories", important_memory_available, memory_action_disabled_reason, {"residentId": resident_id, "filterId": "anomalous"}),
			"filterInterventions": _action("resident_detail.filter_memories", important_memory_available, memory_action_disabled_reason, {"residentId": resident_id, "filterId": "interventions"}),
			"filterRelationshipAll": _action("resident_detail.filter_relationships", relationship_available, "" if relationship_available else "RESIDENT_RELATIONSHIP_NOT_READY", {"residentId": resident_id, "filterId": "all"}),
			"filterRelationshipClose": _action("resident_detail.filter_relationships", relationship_available, "" if relationship_available else "RESIDENT_RELATIONSHIP_NOT_READY", {"residentId": resident_id, "filterId": "close"}),
			"filterRelationshipTrust": _action("resident_detail.filter_relationships", relationship_available, "" if relationship_available else "RESIDENT_RELATIONSHIP_NOT_READY", {"residentId": resident_id, "filterId": "trust"}),
			"filterRelationshipConflict": _action("resident_detail.filter_relationships", relationship_available, "" if relationship_available else "RESIDENT_RELATIONSHIP_NOT_READY", {"residentId": resident_id, "filterId": "conflict"}),
			"filterRelationshipDistant": _action("resident_detail.filter_relationships", relationship_available, "" if relationship_available else "RESIDENT_RELATIONSHIP_NOT_READY", {"residentId": resident_id, "filterId": "distant"}),
			"filterRelationshipPlayer": _action("resident_detail.filter_relationships", relationship_available, "" if relationship_available else "RESIDENT_RELATIONSHIP_NOT_READY", {"residentId": resident_id, "filterId": "player"}),
			"editMemory": _action("resident_detail.change_memory", important_memory_available, memory_action_disabled_reason, {"residentId": resident_id, "operation": "edit", "expectedRevision": int(memory.get("formal_memory_revision", 0))}),
			"deleteMemory": _action("resident_detail.change_memory", important_memory_available, memory_action_disabled_reason, {"residentId": resident_id, "operation": "delete", "expectedRevision": int(memory.get("formal_memory_revision", 0))}),
			"writeMemory": _action("resident_detail.change_memory", important_memory_available, memory_action_disabled_reason, {"residentId": resident_id, "operation": "write", "expectedRevision": int(memory.get("formal_memory_revision", 0))}),
			"previousMemoryPage": _action("resident_detail.page_memories", page_available and int(content.get("page", 0)) > 0, "FIRST_MEMORY_PAGE", {"residentId": resident_id, "direction": "previous"}),
			"nextMemoryPage": _action("resident_detail.page_memories", page_available and int(content.get("page", 0)) + 1 < int(content.get("pageCount", 1)), "LAST_MEMORY_PAGE", {"residentId": resident_id, "direction": "next"}),
		},
		operation,
		effective_error,
	)


func _resident_detail_content(
	selected_tab: String,
	attributes: Dictionary,
	runtime_state: Dictionary,
	memory: Dictionary,
	relationship_available: bool,
	important_memory_available: bool,
	resident_id: String,
	detail_available: bool,
	relationship_filter: String,
	memory_filter: String,
	memory_page: int,
) -> Dictionary:
	if selected_tab == "relationships":
		var relationship_text := String(memory.get("relationships", "")).strip_edges()
		var relationship_progress := memory.get(
			"relationship_progress",
			[],
		) as Array
		if not relationship_progress.is_empty():
			var relationship_items: Array[Dictionary] = []
			for progress_value: Variant in relationship_progress:
				var progress := progress_value as Dictionary
				if not _relationship_matches_filter(progress, relationship_filter):
					continue
				var related_resident_id := String(
					progress.get("residentId", "")
				)
				var related_portrait := _resident_portrait_projection(
					related_resident_id,
				)
				var display_name := String(
					progress.get("displayName", "")
				).strip_edges()
				var depth := (
					progress.get("depth", {}) as Dictionary
				).duplicate(true)
				relationship_items.append({
					"residentId": related_resident_id,
					"displayName": display_name,
					"portraitRef": String(
						related_portrait.get("portraitRef", ""),
					),
					"relationshipLabel": "交往深度",
					"summaryOnly": false,
					"depth": depth,
					"familiarity": depth.duplicate(true),
					"tension": {"available": false},
					"summary": _relationship_summary_for_person(
						relationship_text,
						display_name,
					),
					"recentInteractionSummary": (
						"已完成 %d 次对话，共 %d 个确认轮次"
						% [
							int(progress.get(
								"conversationCount",
								0,
							)),
							int(progress.get(
								"confirmedTurnCount",
								0,
							)),
						]
					),
					"updatedLabel": _time_label(
						progress.get(
							"lastInteractionAt",
							{},
						) as Dictionary
					),
				})
			return {
				"tabId": selected_tab,
				"availability": "ready",
				"retained": false,
				"filterId": relationship_filter,
				"filters": _relationship_filter_options(),
				"items": relationship_items,
				"emptyState": {
					"title": _relationship_empty_state_title(relationship_filter),
				},
			}
		var relationship_items: Array[Dictionary] = []
		if relationship_filter == "all" and not relationship_text.is_empty():
			relationship_items.append({
				"residentId": "",
				"displayName": "关系概览",
				"relationshipLabel": "公开摘要",
				"summaryOnly": true,
				"familiarity": {"available": false},
				"tension": {"available": false},
				"summary": relationship_text,
				"recentInteractionSummary": relationship_text,
				"updatedLabel": "最近整理",
			})
		return {
			"tabId": selected_tab,
			"availability": "ready" if relationship_available else "unavailable",
			"retained": false,
			"filterId": relationship_filter,
			"filters": _relationship_filter_options(),
			"items": relationship_items,
			"emptyState": {
				"title": _relationship_empty_state_title(relationship_filter)
					if relationship_available
					else "关系资料暂时没有准备好。"
			},
		}
	if selected_tab == "memories":
		return _resident_memory_content(
			memory,
			important_memory_available,
			memory_filter,
			memory_page,
		)
	if not detail_available:
		return {
			"tabId": "status",
			"availability": "unavailable",
			"retained": false,
			"statusRows": [],
			"emptyState": {"title": "状态资料暂时没有准备好。"},
		}
	var body := runtime_state.get("body", {}) as Dictionary
	var activity_needs_value: Variant = runtime_state.get(
		"activityNeeds",
		{},
	)
	var activity_needs: Dictionary = (
		activity_needs_value
		if activity_needs_value is Dictionary
		else {}
	)
	var conditions := runtime_state.get("conditions", []) as Array
	var active_needs := runtime_state.get("activeNeeds", []) as Array
	var doing := String(runtime_state.get("doing", "")).strip_edges()
	var desire := String(attributes.get("desire", "")).strip_edges()
	var resident_lifecycle := runtime_state.get("lifecycle", {}) as Dictionary
	if bool(resident_lifecycle.get("isDead", false)):
		var death_summary := resident_lifecycle.get("deathSummary", {}) as Dictionary
		var death_time := death_summary.get("time", {}) as Dictionary
		var death_location := death_summary.get("location", {}) as Dictionary
		var death_reason := String(death_summary.get("reason", "")).strip_edges()
		return {
			"tabId": "status",
			"availability": "ready",
			"retained": false,
			"preferredStatusRowId": "state",
			"statusRows": [
				{"id": "doing", "label": "正在", "shortText": "已经死亡", "text": "该居民已经死亡，不再参与普通生活。", "visible": true},
				{"id": "state", "label": "状态", "shortText": "已死亡", "text": "该居民的死亡记录已经归档。", "visible": true},
				{"id": "place", "label": "地点", "shortText": String(death_location.get("placeName", runtime_state.get("currentPlace", ""))), "text": "记录中的死亡发生地点。", "visible": true},
				{"id": "time", "label": "时间", "shortText": _time_label(death_time), "text": _time_label(death_time), "visible": true},
				{"id": "reason", "label": "原因", "shortText": death_reason, "text": death_reason, "visible": true},
			],
			"moodLabel": "死亡记录已归档",
			"expressionId": "unavailable",
			"expressionLabel": "",
			"urgentNeed": {"visible": false, "label": "", "reason": ""},
			"lifeMeters": _resident_life_meters(activity_needs),
		}
	var body_summary := _body_summary(body)
	var condition_summary := _condition_summary(conditions)
	var need_summary := _condition_need_summary(active_needs)
	var current_plan := String(memory.get("next_plan", "")).strip_edges()
	var recent_outcome := _recent_outcome_summary(
		runtime_state.get("recentOutcome", null),
	)
	var preferred_status_row_id := "doing"
	if not conditions.is_empty():
		preferred_status_row_id = "conditions"
	elif not current_plan.is_empty():
		preferred_status_row_id = "plan"
	return {
		"tabId": "status",
		"availability": "ready",
		"retained": false,
		"preferredStatusRowId": preferred_status_row_id,
		"statusRows": [
			{"id": "doing", "label": "正在", "shortText": doing if not doing.is_empty() else "暂时没有动作", "text": doing if not doing.is_empty() else "当前没有正在执行的动作。", "visible": true},
			{"id": "body", "label": "身体", "shortText": body_summary, "text": body_summary, "visible": true},
			{"id": "conditions", "label": "状况", "shortText": condition_summary.get("shortText", "没有临时状况"), "text": condition_summary.get("text", "当前没有生病、受伤或其他临时状况。"), "visible": true},
			{"id": "needs", "label": "需要", "shortText": need_summary.get("shortText", _body_need(body)), "text": need_summary.get("text", _body_need(body)), "visible": true},
			{"id": "plan", "label": "打算", "shortText": current_plan if not current_plan.is_empty() else "还没有近期打算", "text": current_plan if not current_plan.is_empty() else "当前还没有形成能够公开的近期计划或承诺。", "visible": true},
			{"id": "desire", "label": "愿望", "shortText": desire if not desire.is_empty() else "还没有长期愿望", "text": desire if not desire.is_empty() else "居民资料中还没有长期愿望。", "visible": true},
			{"id": "recent", "label": "刚刚", "shortText": recent_outcome if not recent_outcome.is_empty() else "还没有最近结果", "text": recent_outcome if not recent_outcome.is_empty() else "当前还没有可以确认的最近行动结果。", "visible": true},
		],
		"moodLabel": "只显示世界已确认的公开状态",
		"expressionId": "unavailable",
		"expressionLabel": "表情资源待接入",
		"urgentNeed": {"visible": false, "label": "", "reason": ""},
		# These five values come directly from the World resident projection and
		# are persisted with the resident. The meter only buckets the confirmed
		# 0..100 value into the approved five-cell presentation; it never
		# invents a value from the descriptive status rows.
		"lifeMeters": _resident_life_meters(activity_needs),
	}


func _relationship_filter_options() -> Array[Dictionary]:
	return [
		{"id": "all", "label": "全部"},
		{"id": "close", "label": "亲近"},
		{"id": "trust", "label": "信任"},
		{"id": "conflict", "label": "矛盾"},
		{"id": "distant", "label": "疏远"},
		{"id": "player", "label": "与你有关"},
	]


func _relationship_empty_state_title(filter_id: String) -> String:
	match filter_id:
		"close":
			return "还没有亲近的关系。"
		"trust":
			return "还没有明确的信任关系。"
		"conflict":
			return "还没有确认的矛盾关系。"
		"distant":
			return "还没有疏远的关系。"
		"player":
			return "还没有与你有关的关系。"
		_:
			return "还没有认识的人。"


func _relationship_matches_filter(progress: Dictionary, filter_id: String) -> bool:
	if filter_id == "all":
		return true
	var explicit_tags := progress.get("filterTags", []) as Array
	if explicit_tags.has(filter_id):
		return true
	var depth := progress.get("depth", {}) as Dictionary
	var depth_level := int(depth.get("level", -1))
	match filter_id:
		"close":
			return depth_level >= 3
		"distant":
			return depth_level >= 0 and depth_level <= 1
		"conflict":
			return (
				int(progress.get("conflictEvidenceCount", 0)) > 0
				or bool(progress.get("hasConflict", false))
			)
		"trust":
			return (
				bool(progress.get("trusted", false))
				or int(progress.get("trustLevel", 0)) > 0
			)
		"player":
			return (
				bool(progress.get("playerInvolved", false))
				or bool(progress.get("relatedToPlayer", false))
			)
	return false


func _resident_memory_content(
	memory: Dictionary,
	important_memory_available: bool,
	memory_filter: String,
	memory_page: int,
) -> Dictionary:
	var formal_memories := memory.get("formal_memories", []) as Array
	var visible_formal_memories := (
		formal_memories
		if memory_filter != "interventions"
		else []
	) as Array
	var all_memory_items: Array[Dictionary] = []
	for entry_value: Variant in visible_formal_memories:
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var entry := entry_value as Dictionary
		var state := String(entry.get("state", "past"))
		if (
			memory_filter != "all"
			and not (memory_filter == "past" and state in ["past", "corrected"])
			and state != memory_filter
		):
			continue
		var subject := String(entry.get("subject", "")).strip_edges()
		var interpretation := String(entry.get("interpretation", "")).strip_edges()
		var related_residents := (entry.get("people", []) as Array).duplicate()
		all_memory_items.append({
			"memoryId": String(entry.get("memoryKey", "")),
			"title": subject,
			"summary": interpretation if not interpretation.is_empty() else subject,
			"kindId": state,
			"kindLabel": _memory_state_label(state),
			"timeLabel": _time_label(entry.get("worldTime", {}) as Dictionary),
			"playerInvolved": related_residents.has("玩家") or related_residents.has("player"),
			"relatedPlaces": (entry.get("places", []) as Array).duplicate(),
			"relatedResidents": related_residents,
			"sourceKind": String(entry.get("sourceKind", "")),
			"sourceLabel": _memory_source_label(String(entry.get("sourceKind", ""))),
			"confidence": int(entry.get("confidence", 0)),
			"influence": {
				"available": true,
				"level": clampi(int(round(float(entry.get("confidence", 0)) / 20.0)), 0, 5),
				"segmentCount": 5,
				"label": "%d%% 确信" % int(entry.get("confidence", 0)),
			},
		})
	if memory_filter == "interventions":
		for intervention_value: Variant in memory.get("interventions", []) as Array:
			if typeof(intervention_value) != TYPE_DICTIONARY:
				continue
			var intervention := intervention_value as Dictionary
			var original_subject := String(intervention.get("originalSubject", "")).strip_edges()
			var active_subject := String(intervention.get("activeSubject", "")).strip_edges()
			var player_text := String(intervention.get("playerText", "")).strip_edges()
			all_memory_items.append({
				"memoryId": String(intervention.get("memoryKey", "")),
				"title": original_subject if not original_subject.is_empty() else active_subject,
				"summary": _memory_intervention_summary(intervention),
				"kindId": "intervention",
				"kindLabel": _memory_operation_label(String(intervention.get("operation", ""))),
				"timeLabel": _time_label(intervention.get("createdWorldTime", {}) as Dictionary),
				"playerInvolved": true,
				"relatedPlaces": [],
				"relatedResidents": [],
				"sourceKind": "player_intervention",
				"sourceLabel": "你的介入",
				"confidence": 0,
				"interventionStatus": String(intervention.get("status", "active")),
				"playerText": player_text,
				"influence": {"available": false},
			})
	const MEMORY_ITEMS_PER_PAGE := 4
	var page_count := maxi(
		1,
		int(ceil(float(all_memory_items.size()) / float(MEMORY_ITEMS_PER_PAGE))),
	)
	var effective_page := clampi(memory_page, 0, page_count - 1)
	var start_index := effective_page * MEMORY_ITEMS_PER_PAGE
	var memory_items: Array[Dictionary] = []
	for index in range(
		start_index,
		mini(start_index + MEMORY_ITEMS_PER_PAGE, all_memory_items.size()),
	):
		memory_items.append((all_memory_items[index] as Dictionary).duplicate(true))
	return {
		"tabId": "memories",
		"availability": "ready" if important_memory_available else "unavailable",
		"retained": false,
		"filterId": memory_filter,
		"page": effective_page,
		"pageCount": page_count,
		"totalCount": all_memory_items.size(),
		"filters": [
			{"id": "all", "label": "全部"},
			{"id": "influencing", "label": "正在影响"},
			{"id": "past", "label": "往事"},
			{"id": "doubtful", "label": "存疑"},
			{"id": "anomalous", "label": "异常"},
			{"id": "interventions", "label": "我的介入"},
		],
		"formalMemoryRevision": int(memory.get("formal_memory_revision", 0)),
		"items": memory_items,
		"interventions": (memory.get("interventions", []) as Array).duplicate(true),
		"emptyState": {
			"title": (
				"这个分类里还没有记忆。"
				if important_memory_available
				else "记忆资料暂时没有准备好。"
			),
		},
	}


func _memory_state_label(state: String) -> String:
	match state:
		"influencing":
			return "正在影响"
		"past":
			return "往事"
		"doubtful":
			return "存疑"
		"anomalous":
			return "异常"
		"corrected":
			return "已修正"
	return "记忆"


func _memory_source_label(source_kind: String) -> String:
	match source_kind:
		"firsthand":
			return "亲历"
		"hearsay":
			return "听说"
		"implanted":
			return "无来源印象"
	return ""


func _memory_operation_label(operation: String) -> String:
	match operation:
		"edit":
			return "修改"
		"delete":
			return "删除"
		"write":
			return "写入"
	return "介入记录"


func _memory_intervention_summary(intervention: Dictionary) -> String:
	var operation := String(intervention.get("operation", ""))
	var original_subject := String(intervention.get("originalSubject", "")).strip_edges()
	var active_subject := String(intervention.get("activeSubject", "")).strip_edges()
	var original := String(intervention.get("originalInterpretation", "")).strip_edges()
	var active := String(intervention.get("activeInterpretation", "")).strip_edges()
	var player_text := String(intervention.get("playerText", "")).strip_edges()
	if operation == "delete":
		return "你删除了普通回想中的这段记忆：%s" % (
			original_subject if not original_subject.is_empty() else "这段记忆"
		)
	if operation == "write":
		return player_text if not player_text.is_empty() else active
	if operation == "edit" and not original_subject.is_empty() and not active_subject.is_empty():
		return "原来：%s\n现在：%s" % [original_subject, active_subject]
	if not original.is_empty() and not active.is_empty():
		return "原来：%s\n现在：%s" % [original, active]
	return player_text if not player_text.is_empty() else active


func _recent_outcome_summary(value: Variant) -> String:
	if value is String:
		return (value as String).strip_edges()
	if not value is Dictionary:
		return ""
	var outcome := value as Dictionary
	for field in ["summary", "text"]:
		var public_text := String(outcome.get(field, "")).strip_edges()
		if not public_text.is_empty():
			return public_text
	var public_label := String(outcome.get("label", "")).strip_edges()
	var status := String(outcome.get("status", ""))
	if not public_label.is_empty():
		return {
			"completed": "完成了%s" % public_label,
			"interrupted": "%s被中断" % public_label,
			"replaced": "%s被新的行动替代" % public_label,
			"rejected": "%s没有获准" % public_label,
		}.get(status, public_label)
	return String({
		"completed": "完成了上一件事",
		"failed": "上一件事没有完成",
		"rejected": "上一件事没有获准",
		"replaced": "上一件事被新的行动替代",
		"interrupted": "被中断",
	}.get(status, "")).strip_edges()


func _relationship_summary_for_person(
	relationship_text: String,
	display_name: String,
) -> String:
	var normalized := relationship_text.strip_edges()
	if normalized.is_empty():
		return "暂时没有形成可以单独概括的公开态度。"
	if display_name.is_empty():
		return normalized
	for separator: String in ["\n", "；", ";"]:
		normalized = normalized.replace(separator, "\n")
	for line: String in normalized.split("\n", false):
		var candidate := line.strip_edges()
		if candidate.contains(display_name):
			return candidate
	return "已经有共同经历，但暂未形成单独的公开态度摘要。"


func _publish_place_focus(operation: Dictionary, error_value: Variant) -> void:
	var context := _page_contexts.get("place_focus", {}) as Dictionary
	var place_name := String(context.get("placeName", "")).strip_edges()
	var detail := _place_detail(place_name)
	var available := not detail.is_empty()
	var residents: Array[Dictionary] = []
	for resident_name_value: Variant in detail.get("residentNames", []) as Array:
		var resident_name := String(resident_name_value)
		var identity := _resident_identity_for_name(resident_name)
		var state := _resident_state(resident_name)
		residents.append({
			"residentId": String(identity.get("residentId", "")),
			"residentName": resident_name,
			"portraitRef": "",
			"statusLabel": String(state.get("doing", "")),
			# Resident details are opened by directly selecting the resident in
			# the world. The place page is informational and must not advertise
			# a second, rejected navigation path.
			"canOpen": false,
			"disabledReason": "RESIDENT_DIRECT_SELECTION_REQUIRED",
		})
	var recent_logs := _place_log_items(place_name, 3)
	var current_events: Array[Dictionary] = []
	for item in recent_logs:
		if not (item.get("sourceEventIds", []) as Array).is_empty():
			current_events.append(_place_event_projection(item))
			break
	var space_id := String(detail.get("spaceId", ""))
	var connection_id := ""
	if _world != null and _world.has_method("get_place_connection_id"):
		connection_id = String(
			_world.get_place_connection_id(place_name)
		)
	var has_interior := not connection_id.is_empty()
	var observer_mode := String(_read_runtime_state().get("avatarMode", "observer")) == "observer"
	var formal_ready := available and _session_formal_ready()
	var data := {
		"source": "town_ui_adapter",
		"capabilityMode": _session_capability_mode() if available else "unavailable",
		"formalReady": formal_ready,
		"place": {
			"placeName": String(detail.get("name", place_name)),
			"placeType": String(detail.get("type", "")),
			"spaceId": space_id,
			"summary": String(detail.get("summary", "")),
			"hasInterior": has_interior,
			"residentCount": residents.size(),
		},
		"residents": residents,
		"currentEvents": current_events,
		# Player-owned prop interaction is not part of the formal product
		# contract. Keep the legacy structural field empty for the approved
		# page wrapper, but never project World props as disabled player
		# actions.
		"interactables": [],
		"recentLogs": _place_log_projections(recent_logs),
	}
	var effective_error: Variant = error_value
	if not available and effective_error == null:
		effective_error = _error_payload("PLACE_FOCUS_PLACE_NOT_FOUND", false, "地点资料暂不可用。")
	_store_view_model(
		"place_focus",
		"ready" if available else "disabled",
		data,
		{
			"openResident": _action(
				"place_focus.open_resident",
				false,
				"RESIDENT_DIRECT_SELECTION_REQUIRED",
			),
			"openEvent": _action("place_focus.open_event", not current_events.is_empty(), "NO_ACTIVE_EVENT"),
			"openInteractable": _action("place_focus.open_interactable", false, "PLACE_INTERACTABLE_REQUIRES_INDOOR_ENTRY"),
			"openLog": _action("place_focus.open_log", not recent_logs.is_empty(), "PLACE_LOG_NOT_AVAILABLE"),
			"enterInterior": _action("place_focus.enter_interior", formal_ready and has_interior and observer_mode and _runtime != null and _runtime.has_method("request_observe_place"), "OBSERVER_MODE_REQUIRED" if not observer_mode else ("PLACE_HAS_NO_INTERIOR" if not has_interior else "PLACE_OBSERVATION_INTERFACE_MISSING"), {"placeName": place_name}),
			"retry": _action("place_focus.retry", error_value is Dictionary and bool((error_value as Dictionary).get("retryable", false)), "NO_RETRYABLE_ERROR", {"placeName": place_name}),
		},
		operation,
		effective_error,
	)


func _publish_indoor(
	operation: Dictionary,
	error_value: Variant,
) -> void:
	var runtime_state := _read_runtime_state()
	var avatar := runtime_state.get("playerAvatar", {}) as Dictionary
	var view_mode := String(runtime_state.get("viewMode", "town"))
	var place_name := String(runtime_state.get("observedPlace", ""))
	if place_name.is_empty() and view_mode == "interior":
		place_name = String(avatar.get("currentPlace", ""))
	var place: Dictionary = {}
	if not place_name.is_empty() and _world != null and _world.has_method("get_place_detail"):
		place = _world.get_place_detail(place_name) as Dictionary
	var active := view_mode == "interior" and not place.is_empty()
	var resident_targets: Array[Dictionary] = []
	for identity in _resident_identities() if active and _world != null and _world.has_method("get_resident_state") else []:
		var resident_name := String(identity.get("residentName", ""))
		var state := _world.get_resident_state(resident_name) as Dictionary
		if String(state.get("currentPlace", "")) != place_name:
			continue
		var resident_id := String(identity.get("residentId", ""))
		var portrait_projection := _resident_portrait_projection(resident_id)
		var placement := _resident_placement(resident_name)
		resident_targets.append({
			"targetId": "resident-%s" % resident_id,
			"residentId": resident_id,
			"name": resident_name,
			"portraitPath": String(
				portrait_projection.get("portraitRef", ""),
			),
			"doingLabel": String(state.get("doing", "")),
			"statusIconId": "resident",
			"screenAnchor": (placement.get("screenAnchor", {}) as Dictionary).duplicate(true),
			"isOnScreen": true,
			"edgeDirection": "",
			"canOpen": true,
			"disabledReason": "",
			"isEventRelated": false,
			"focusOrder": 20 + resident_targets.size(),
		})
	var player_avatar_enabled := bool(runtime_state.get("playerAvatarEnabled", false))
	var can_return := active and not player_avatar_enabled
	var code := "" if active else "INDOOR_SCENE_NOT_ACTIVE"
	var event_focus := _indoor_event_focus(place_name)
	var observation_feed := _indoor_observation_feed(place_name)
	var data := {
		"capabilityMode": _session_capability_mode(),
		"source": "runtime",
		"formalReady": active and _session_formal_ready(),
		"internalPlaytest": _session_internal_playtest(),
		"view": {"presentationMode": "interior_overlay", "entryReason": String((_page_contexts.get("indoor", {}) as Dictionary).get("entryReason", "runtime")), "selectedTargetId": String((_page_contexts.get("indoor", {}) as Dictionary).get("targetId", "")), "reduceMotion": false},
		"location": {"spaceId": String(place.get("spaceId", "")), "placeName": place_name, "placeTypeLabel": String(place.get("type", "")), "title": place_name if not place_name.is_empty() else "室内", "subtitle": String(place.get("summary", ""))},
		"sceneLoad": {"status": "ready" if active else "idle", "progressLabel": "", "canRetry": false, "failureCode": code},
		"residentTargets": resident_targets,
		"observationFeed": observation_feed,
		"eventFocus": event_focus,
		"feedback": {"code": code, "message": "" if active else "当前没有载入室内地点", "tone": "idle" if active else "disabled"},
		"outdoorFallback": {"visible": false, "renderOwner": "place_focus", "placeName": "", "residentSummaries": [], "recentEventSummaries": []},
	}
	var effective_error: Variant = error_value
	_store_view_model(
		"indoor",
		"ready" if active else "disabled",
		data,
		{
			"returnOutdoor": _action("indoor.return_outdoor", can_return, "PHYSICAL_EXIT_REQUIRED" if player_avatar_enabled else "INDOOR_SCENE_NOT_ACTIVE"),
			"focusTarget": _action("indoor.focus_target", active and not resident_targets.is_empty(), "NO_RESIDENT_TARGET"),
			"focusEvent": _action(
				"indoor.focus_event",
				bool(event_focus.get("canFocus", false)),
				String(event_focus.get("focusDisabledReason", "NO_ACTIVE_EVENT")),
			),
			"retryLoad": _action("indoor.retry_load", false, "NO_RETRYABLE_ERROR"),
			"dismissFeedback": _action("indoor.dismiss_feedback", active and not code.is_empty(), "NO_FEEDBACK"),
		},
		operation,
		effective_error,
	)


func _world_log_query_available() -> bool:
	return (
		_world != null
		and _world.has_method("query_world_log_threads")
		and _world.has_method("get_world_log_thread_detail")
		and _world.has_method("mark_world_log_thread_read")
		and _world.has_method("get_world_log_filter_catalog")
	)


func _town_log_query_options(cursor: Dictionary = {}) -> Dictionary:
	var options := {
		"residentId": String(_town_log_filters.get("residentId", "")),
		"kindTag": String(_town_log_filters.get("kindTag", "")),
		"day": int(_town_log_filters.get("day", 0)),
		"unreadOnly": bool(_town_log_filters.get("unreadOnly", false)),
		"limit": 50,
	}
	if not cursor.is_empty():
		options["cursor"] = cursor.duplicate(true)
	return options


func _reload_town_log_threads() -> Dictionary:
	_town_log_query_error = null
	_town_log_has_newer_threads = false
	if not _world_log_query_available():
		_town_log_rows.clear()
		_town_log_filter_catalog.clear()
		_town_log_paging = {
			"cursor": {},
			"hasMore": false,
			"isLoading": false,
		}
		return RESULT_SHAPES.failure("TOWN_LOG_INTERFACE_MISSING")
	var catalog := _world.get_world_log_filter_catalog() as Dictionary
	if catalog.get("ok") != true:
		_town_log_query_error = _error_payload(
			String(catalog.get("errorCode", "WORLD_LOG_CATALOG_FAILED")),
			bool(catalog.get("retryable", false)),
			"世界日志筛选目录暂时不可用。",
		)
		return catalog
	_town_log_filter_catalog = catalog.duplicate(true)
	var result := _world.query_world_log_threads(_town_log_query_options(),) as Dictionary
	if result.get("ok") != true:
		_town_log_query_error = _error_payload(
			String(result.get("errorCode", "WORLD_LOG_QUERY_FAILED")),
			bool(result.get("retryable", false)),
			"世界日志暂时无法读取。",
		)
		return result
	_town_log_rows.clear()
	for value: Variant in result.get("rows", []) as Array:
		if value is Dictionary:
			_town_log_rows.append((value as Dictionary).duplicate(true))
	_town_log_query_timeline_id = String(result.get("timelineId", ""))
	_town_log_query_upper_bound = int(result.get("upperBoundSequence", 0))
	_town_log_paging = {
		"cursor": (result.get("nextCursor", {}) as Dictionary).duplicate(true),
		"hasMore": bool(result.get("hasMore", false)),
		"isLoading": false,
	}
	if not _town_log_selected_entry_id.is_empty():
		var selected_still_visible := _town_log_rows.any(
			func(row: Dictionary) -> bool:
				return String(row.get("threadId", "")) == _town_log_selected_entry_id
		)
		if selected_still_visible:
			_load_town_log_detail(_town_log_selected_entry_id, false)
		else:
			_town_log_selected_entry_id = ""
			_town_log_detail = null
			_town_log_detail_paging = {
				"cursor": 0,
				"hasMore": false,
				"isLoading": false,
			}
	return result


func _load_more_town_log_threads() -> Dictionary:
	if not bool(_town_log_paging.get("hasMore", false)):
		return RESULT_SHAPES.failure("NO_MORE_ITEMS")
	var cursor_value: Variant = _town_log_paging.get("cursor", {})
	if not cursor_value is Dictionary:
		return RESULT_SHAPES.failure("WORLD_LOG_CURSOR_INVALID")
	var result := _world.query_world_log_threads(_town_log_query_options(cursor_value as Dictionary),) as Dictionary
	if result.get("ok") != true:
		return result
	var known: Dictionary = {}
	for row: Dictionary in _town_log_rows:
		known[String(row.get("threadId", ""))] = true
	for value: Variant in result.get("rows", []) as Array:
		if not value is Dictionary:
			continue
		var row := value as Dictionary
		var thread_id := String(row.get("threadId", ""))
		if not known.has(thread_id):
			_town_log_rows.append(row.duplicate(true))
			known[thread_id] = true
	_town_log_paging = {
		"cursor": (result.get("nextCursor", {}) as Dictionary).duplicate(true),
		"hasMore": bool(result.get("hasMore", false)),
		"isLoading": false,
	}
	return result


func _load_town_log_detail(thread_id: String, append_page: bool) -> Dictionary:
	if thread_id.is_empty() or not _world_log_query_available():
		return RESULT_SHAPES.failure("WORLD_LOG_THREAD_NOT_FOUND")
	var after_sequence := (
		int(_town_log_detail_paging.get("cursor", 0)) if append_page else 0
	)
	var result := _world.get_world_log_thread_detail(thread_id,
		{
			"timelineId": _town_log_query_timeline_id,
			"upperBoundSequence": _town_log_query_upper_bound,
			"afterSequence": after_sequence,
			"limit": 100,
		},) as Dictionary
	if result.get("ok") != true:
		return result
	var records: Array[Dictionary] = []
	if append_page and _town_log_detail is Dictionary:
		for value: Variant in (_town_log_detail as Dictionary).get("records", []) as Array:
			if value is Dictionary:
				records.append((value as Dictionary).duplicate(true))
	for value: Variant in result.get("records", []) as Array:
		if value is Dictionary:
			records.append((value as Dictionary).duplicate(true))
	_town_log_selected_entry_id = thread_id
	_town_log_detail = {
		"thread": (result.get("thread", {}) as Dictionary).duplicate(true),
		"records": records,
	}
	var next_sequence := int(result.get("nextSequence", after_sequence))
	_town_log_detail_paging = {
		"cursor": next_sequence,
		"hasMore": bool(result.get("hasMore", false)),
		"isLoading": false,
	}
	if next_sequence > 0:
		_world.mark_world_log_thread_read(thread_id, next_sequence)
		_refresh_town_log_read_projection(thread_id, next_sequence)
	return result


func _refresh_town_log_read_projection(thread_id: String, through_sequence: int) -> void:
	for index in _town_log_rows.size():
		var row := _town_log_rows[index]
		if String(row.get("threadId", "")) != thread_id:
			continue
		var latest := int(row.get("latestSequence", 0))
		row["unread"] = through_sequence < latest
		if through_sequence >= latest:
			row["unreadRecordCount"] = 0
		_town_log_rows[index] = row
		break
	var catalog := _world.get_world_log_filter_catalog() as Dictionary
	if catalog.get("ok") == true:
		_town_log_filter_catalog = catalog.duplicate(true)


func _set_town_log_filter(payload: Dictionary) -> Dictionary:
	var key := String(payload.get("key", ""))
	var value: Variant = payload.get("value")
	match key:
		"residentId":
			_town_log_filters[key] = String(value).strip_edges()
		"kindTag":
			_town_log_filters[key] = String(value).strip_edges()
		"day":
			var day := int(value)
			if day < 0:
				return {"ok": false, "errorCode": "TOWN_LOG_FILTER_INVALID"}
			_town_log_filters[key] = day
		_:
			return {"ok": false, "errorCode": "TOWN_LOG_FILTER_INVALID"}
	return {"ok": true, "errorCode": ""}


func _flag_town_log_newer() -> void:
	if _town_log_open:
		_town_log_has_newer_threads = true


func _publish_town_log(operation: Dictionary, error_value: Variant) -> void:
	var available := _world_log_query_available()
	var catalog := _town_log_filter_catalog
	var effective_error: Variant = (
		error_value if error_value != null else _town_log_query_error
	)
	var data := {
		"capabilityMode": _session_capability_mode() if available else "unavailable",
		"source": "runtime",
		"formalReady": available and _session_formal_ready(),
		"internalPlaytest": _session_internal_playtest(),
		"panel": {
			"open": _town_log_open,
			"presentation": "world_log_table",
			"title": "世界日志",
		},
		"state": "ready" if available else "disabled",
		"errorCode": (
			String((effective_error as Dictionary).get("code", ""))
			if effective_error is Dictionary
			else ""
		),
		"summary": {
			"attentionUnreadThreadCount": int(
				catalog.get("attentionUnreadThreadCount", 0),
			),
			"totalUnreadThreadCount": int(
				catalog.get("totalUnreadThreadCount", 0),
			),
			"hasNewerThreads": _town_log_has_newer_threads,
		},
		"entryPoint": {
			"unreadCount": int(catalog.get("attentionUnreadThreadCount", 0)),
			"unreadCountLabel": str(catalog.get("attentionUnreadThreadCount", 0)),
			"hasUnread": int(catalog.get("attentionUnreadThreadCount", 0)) > 0,
			"hasHot": false,
			"attentionToken": "%s:%d" % [
				String(catalog.get("timelineId", "")),
				int(catalog.get("attentionUnreadThreadCount", 0)),
			],
			"recentImportantEntry": (
				_town_log_rows[0].duplicate(true)
				if not _town_log_rows.is_empty()
				else null
			),
		},
		"filters": _town_log_filters.duplicate(true),
		"filterOptions": {
			"residents": (catalog.get("residents", []) as Array).duplicate(true),
			"kinds": (catalog.get("kindTags", []) as Array).duplicate(true),
			"days": (catalog.get("days", []) as Array).duplicate(true),
		},
		"rows": _town_log_rows.duplicate(true),
		"selectedThreadId": _town_log_selected_entry_id,
		"detail": (
			(_town_log_detail as Dictionary).duplicate(true)
			if _town_log_detail is Dictionary
			else null
		),
		"detailPaging": _town_log_detail_paging.duplicate(true),
		"paging": _town_log_paging.duplicate(true),
	}
	if not available and effective_error == null:
		effective_error = _error_payload(
			"TOWN_LOG_INTERFACE_MISSING",
			false,
			"世界日志资料库尚未绑定。",
		)
	_store_view_model(
		"town_log",
		"ready" if available else "disabled",
		data,
		{
			"open": _action("town_log.open", not _town_log_open, "PANEL_ALREADY_OPEN"),
			"close": _action("town_log.close", _town_log_open, "PANEL_NOT_OPEN"),
			"setFilter": _action("town_log.set_filter", _town_log_open and available, "PANEL_NOT_OPEN"),
			"toggleUnread": _action("town_log.toggle_unread", _town_log_open and available, "PANEL_NOT_OPEN"),
			"selectThread": _action("town_log.select_thread", _town_log_open and not _town_log_rows.is_empty(), "NO_WORLD_LOG_THREADS"),
			"backToList": _action("town_log.back_to_list", _town_log_open and not _town_log_selected_entry_id.is_empty(), "NO_SELECTED_THREAD"),
			"loadMore": _action("town_log.load_more", _town_log_open and bool(_town_log_paging.get("hasMore", false)), "NO_MORE_ITEMS"),
			"loadMoreDetail": _action("town_log.load_more_detail", _town_log_open and bool(_town_log_detail_paging.get("hasMore", false)), "NO_MORE_DETAIL"),
			"refreshNewer": _action("town_log.refresh_newer", _town_log_open and _town_log_has_newer_threads, "NO_NEW_WORLD_LOG_THREADS"),
			"retry": _action("town_log.retry", available and effective_error != null, "NO_RETRYABLE_ERROR"),
		},
		operation,
		effective_error,
	)


func _seed_town_log() -> void:
	_town_log_rows.clear()
	_town_log_selected_entry_id = ""
	_town_log_detail = null
	_town_log_has_newer_threads = false
	_town_log_query_error = null
	_reload_town_log_threads()


func _resident_identity_for_name(resident_name: String) -> Dictionary:
	_refresh_identity_index()
	var identity := _identity_record_by_name.get(resident_name, {}) as Dictionary
	return identity.duplicate(true) if not identity.is_empty() else {}


func _normalize_string_list(value: Variant) -> Array[String]:
	var result: Array[String] = []
	var values: Array = value as Array if value is Array else [value]
	for item_value: Variant in values:
		var item := String(item_value).strip_edges()
		if not item.is_empty() and not result.has(item):
			result.append(item)
	return result


func _indoor_target_by_id(target_id: String) -> Dictionary:
	var current := _view_models.get("indoor", {}) as Dictionary
	var data := current.get("data", {}) as Dictionary
	for target_value: Variant in data.get("residentTargets", []) as Array:
		var target := target_value as Dictionary
		if String(target.get("targetId", "")) == target_id:
			return target.duplicate(true)
	return {}


func _indoor_event_focus(place_name: String) -> Dictionary:
	# G 之 1 收尾:聚焦事件取自世界侧线程——选中项须仍属当前地点,
	# 否则退回该地点最新一条(与影子层"倒序找同地点首条"等价)。
	var place_items := _place_log_items(place_name, 1)
	var selected: Dictionary = {}
	var focused := _world_log_thread_item(_indoor_focused_event_id)
	if (
		not focused.is_empty()
		and String(focused.get("placeLabel", "")) == place_name
	):
		selected = focused
	elif not place_items.is_empty():
		selected = place_items[0]
	if selected.is_empty():
		return {
			"active": false,
			"eventId": "",
			"title": "",
			"summary": "",
			"screenAnchor": {"x": 0.0, "y": 0.0, "valid": false},
			"isOnScreen": false,
			"edgeDirection": "",
			"relatedTargetIds": [],
			"attentionToken": "",
			"focusState": "unavailable",
			"canFocus": false,
			"focusDisabledReason": "NO_ACTIVE_EVENT",
		}
	var resident_id := String(selected.get("focusResidentId", ""))
	var resident_name := _resident_name_for_id(resident_id)
	var anchor := (
		(_resident_placement(resident_name).get("screenAnchor", {}) as Dictionary).duplicate(true)
		if not resident_name.is_empty()
		else {"x": 0.0, "y": 0.0, "valid": false}
	)
	var can_focus := true
	return {
		"active": true,
		"eventId": String(selected.get("id", "")),
		"title": String(selected.get("title", "")),
		"summary": String(selected.get("subtitle", "")),
		"screenAnchor": anchor,
		"isOnScreen": bool(anchor.get("valid", false)),
		"edgeDirection": "",
		"relatedTargetIds": (["resident-%s" % resident_id] if not resident_id.is_empty() else []),
		"attentionToken": "event:%s" % String(selected.get("id", "")),
		"focusState": "ready",
		"canFocus": can_focus,
		"focusDisabledReason": "",
	}


func _indoor_observation_feed(place_name: String) -> Array[Dictionary]:
	# G 之 1 第五步:观察流数据源切到世界侧 query_place_observations——
	# 该接口已内建"每类取最新一条 + 固定 action/dialogue/important 顺序"
	# (与影子层的 newest_by_kind + 固定序输出逐条等价),表现层只做形态映射。
	var result: Array[Dictionary] = []
	if place_name.is_empty() or not _world_log_query_available():
		return result
	var query := _world.query_world_log_place_observations(
		place_name,
		{"perKindLimit": 1},
	) as Dictionary
	if query.get("ok") != true:
		return result
	for entry_value: Variant in query.get("observations", []) as Array:
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		var resident_ids: Array[String] = []
		for resident_value: Variant in entry.get("participantIds", []) as Array:
			var resident_id := String(resident_value).strip_edges()
			if not resident_id.is_empty() and not resident_ids.has(resident_id):
				resident_ids.append(resident_id)
		var primary_resident := String(entry.get("residentId", "")).strip_edges()
		if not primary_resident.is_empty() and not resident_ids.has(primary_resident):
			resident_ids.insert(0, primary_resident)
		result.append({
			"eventId": String(entry.get("threadId", "")),
			"kind": String(entry.get("observationKind", "")),
			"timeLabel": _time_label(entry.get("time", {}) as Dictionary),
			"summary": _indoor_observation_summary({
				"title": entry.get("title", ""),
				"subtitle": entry.get("text", ""),
			}),
			"residentIds": resident_ids,
			"sourceEventIds": [String(entry.get("recordId", ""))],
		})
	return result


func _indoor_observation_summary(item: Dictionary) -> String:
	var title := String(item.get("title", "")).strip_edges()
	var subtitle := String(item.get("subtitle", "")).strip_edges()
	if title.is_empty():
		return subtitle
	if subtitle.is_empty() or subtitle == title:
		return title
	return "%s\n%s" % [title, subtitle]


func _publish_disabled_wardrobe() -> void:
	var code := "WARDROBE_INTERFACE_MISSING"
	var empty_selection := {"head": "", "expression": "", "top": "", "bottom": "", "shoes": ""}
	var target := _resident_target()
	var data := {
		"capabilityMode": "placeholder",
		"source": "placeholder",
		"formalReady": false,
		"target": {"residentId": String(target.get("residentId", "")), "displayName": String(target.get("residentName", "")), "appearanceRevision": 0},
		"assetContract": {"contractId": "paper-doll-144x192-five-slot", "frameWidth": 144, "frameHeight": 192, "directions": ["down", "right", "up", "left"], "editableSlots": ["head", "top", "bottom", "shoes"], "passThroughSlots": ["expression"], "catalogStatus": "placeholder"},
		"activeCategoryId": "preset",
		"preview": {"status": "disabled", "directionId": "down", "poseId": "neutral", "frameReady": false, "placeholderAssetId": ""},
		"confirmedSelection": empty_selection.duplicate(true),
		"draftSelection": empty_selection.duplicate(true),
		"selectionDirty": false,
		"appliedToFormalProfile": false,
		"presets": [],
		"categories": [],
		"items": [],
	}
	_store_disabled_scope(
		"wardrobe",
		data,
		{
			"selectCategory": "wardrobe.select_category",
			"selectItem": "wardrobe.select_item",
			"selectPreset": "wardrobe.select_preset",
			"setPreviewDirection": "wardrobe.set_preview_direction",
			"randomize": "wardrobe.randomize",
			"restore": "wardrobe.restore",
			"apply": "wardrobe.apply",
			"cancel": "wardrobe.cancel",
			"retry": "wardrobe.retry",
		},
		code,
		"正式换装接口尚未接入。",
	)


func _store_disabled_scope(
	scope: String,
	data: Dictionary,
	intents: Dictionary,
	error_code: String,
	message: String,
) -> void:
	var actions: Dictionary = {}
	for action_key: Variant in intents:
		actions[action_key] = _action(String(intents[action_key]), false, error_code)
	var navigation_action: String = String({
		"indoor": "returnOutdoor",
		"town_log": "close",
		"wardrobe": "cancel",
	}.get(scope, ""))
	if not navigation_action.is_empty() and actions.has(navigation_action):
		actions[navigation_action] = _action(
			String(intents[navigation_action]),
			true,
			"",
		)
	_store_view_model(
		scope,
		"disabled",
		data,
		actions,
		_operation("", "", "disabled", 0, 0),
		_error_payload(error_code, false, message),
	)


func _publish_failure(
	scope: String,
	intent: String,
	request_id: String,
	submitted_at: int,
	result: Dictionary,
) -> void:
	var retryable := bool(result.get("retryable", false))
	var operation := _operation(
		request_id,
		intent,
		"error" if retryable else "rejected",
		submitted_at,
		Time.get_ticks_msec(),
	)
	var error_code := String(result.get("errorCode", "COMMAND_REJECTED"))
	if error_code.is_empty():
		error_code = "COMMAND_REJECTED"
	var error_value := _error_payload(error_code, retryable, "")
	error_value["details"] = (result.get("errors", []) as Array).duplicate(true)
	match scope:
		"weather_control":
			_publish_weather(operation, error_value)
		"announcements":
			_publish_announcements(operation, error_value)
		"resident_action_menu":
			_publish_resident_action_menu(operation, error_value)
		"resident_overview":
			_publish_resident_overview(operation, error_value)
		"resident_detail":
			_publish_resident_detail(operation, error_value)
		"inner_observation":
			_publish_inner_observation(operation, error_value)
		"place_focus":
			_publish_place_focus(operation, error_value)
		"indoor":
			_publish_indoor(operation, error_value)
		"town_log":
			_publish_town_log(operation, error_value)


func _store_view_model(
	scope: String,
	status: String,
	data: Dictionary,
	actions: Dictionary,
	operation: Dictionary,
	error_value: Variant,
	update_confirmed := true,
	preserve_last_confirmed_on_error := true,
) -> void:
	var operation_status := String(operation.get("status", ""))
	var rendered_data := data.duplicate(true)
	var use_last_confirmed := (
		preserve_last_confirmed_on_error
		and operation_status in ["loading", "rejected", "error"]
		and _last_confirmed_data.has(scope)
	)
	if use_last_confirmed:
		rendered_data = (
			_last_confirmed_data.get(scope, {}) as Dictionary
		).duplicate(true)
	var previous := _view_models.get(scope, {}) as Dictionary
	var view_model := {
		"scope": scope,
		"status": status,
		"revision": int(previous.get("revision", 0)),
		"source": String(rendered_data.get("source", "runtime")),
		"capabilityMode": String(rendered_data.get("capabilityMode", "unavailable")),
		"formalReady": bool(rendered_data.get("formalReady", false)),
		"data": rendered_data,
		"actions": actions.duplicate(true),
		"operation": operation.duplicate(true),
		"error": error_value,
	}
	_dirty_world_scopes.erase(scope)
	if not previous.is_empty() and previous == view_model:
		if operation_status in ["success", "rejected", "error"]:
			operation_completed.emit(scope, operation.duplicate(true))
		return
	var revision := 0
	if use_last_confirmed:
		revision = int(_last_confirmed_revision.get(scope, 0))
	else:
		_revision_sequence += 1
		revision = _revision_sequence
	view_model["revision"] = revision
	_view_models[scope] = view_model
	if (
		update_confirmed
		and operation_status in ["idle", "success"]
		and not data.is_empty()
	):
		_last_confirmed_data[scope] = data.duplicate(true)
		_last_confirmed_revision[scope] = revision
	view_model_changed.emit(scope, view_model.duplicate(true))
	if operation_status in ["success", "rejected", "error"]:
		operation_completed.emit(scope, operation.duplicate(true))


func _resident_target() -> Dictionary:
	var identities := _resident_identities()
	var context := _page_contexts.get("resident_action_menu", {}) as Dictionary
	var requested_id := String(context.get("residentId", ""))
	var requested_name := String(context.get("residentName", ""))
	var has_explicit_request := (
		not requested_id.is_empty()
		or not requested_name.is_empty()
	)
	var state := _read_runtime_state()
	if not has_explicit_request and requested_name.is_empty():
		requested_name = String(state.get("selectedResident", ""))
	if not has_explicit_request and requested_name.is_empty():
		requested_name = String(state.get("followedResident", ""))
	for identity_value: Variant in identities:
		var identity := identity_value as Dictionary
		if (
			(not requested_id.is_empty() and String(identity.get("residentId", "")) == requested_id)
			or (not requested_name.is_empty() and String(identity.get("residentName", "")) == requested_name)
			):
				return identity.duplicate(true)
	return {"residentId": "", "residentName": "", "identityStatus": "unavailable"}


func _resident_identities() -> Array[Dictionary]:
	var snapshot: Dictionary = {}
	if _runtime != null and _runtime.has_method("get_resident_identity_snapshot"):
		snapshot = _runtime.call("get_resident_identity_snapshot") as Dictionary
	elif _world != null and _world.has_method("get_resident_identity_snapshot"):
		snapshot = _world.get_resident_identity_snapshot() as Dictionary
	var result: Array[Dictionary] = []
	for identity_value: Variant in snapshot.get("residents", []) as Array:
		if not identity_value is Dictionary:
			continue
		var identity := (identity_value as Dictionary).duplicate(true)
		identity["identityStatus"] = String(snapshot.get("status", "unavailable"))
		result.append(identity)
	return result


# 身份查找是高频路径（约 20 处调用），按世界 revision 缓存双向索引，
# 避免每次全量重建身份数组再线性扫描。
func _refresh_identity_index() -> void:
	var revision := _read_world_revision()
	if (
		revision == _identity_index_revision
		and not _identity_name_by_id.is_empty()
	):
		return
	_identity_name_by_id.clear()
	_identity_record_by_name.clear()
	for identity in _resident_identities():
		var resident_id := String(identity.get("residentId", ""))
		var resident_name := String(identity.get("residentName", ""))
		if not resident_id.is_empty() and not _identity_name_by_id.has(resident_id):
			_identity_name_by_id[resident_id] = resident_name
		if (
			not resident_name.is_empty()
			and not _identity_record_by_name.has(resident_name)
		):
			_identity_record_by_name[resident_name] = identity
	_identity_index_revision = revision


func _resident_name_for_id(resident_id: String) -> String:
	_refresh_identity_index()
	return String(_identity_name_by_id.get(resident_id, ""))


func _resident_public_summary_capabilities(resident_id: String) -> Dictionary:
	var unavailable := {
		"relationships": false,
		"memories": false,
	}
	if (
		resident_id.is_empty()
		or _gateway == null
		or not _gateway.has_method("get_resident_memory")
	):
		return unavailable
	var result := _gateway.call("get_resident_memory", resident_id) as Dictionary
	if not bool(result.get("ok", false)):
		return unavailable
	var memory_value: Variant = result.get("memory")
	if not memory_value is Dictionary:
		return unavailable
	var memory := memory_value as Dictionary
	return {
		"relationships": memory.has("relationships"),
		"memories": memory.has("formal_memories"),
	}


func _resident_placement(resident_name: String) -> Dictionary:
	var viewport := (_session_config.get("logicalViewport", {}) as Dictionary).duplicate(true)
	if viewport.is_empty():
		viewport = {"x": 0, "y": 0, "width": 1920, "height": 1080}
	var width := float(viewport.get("width", 1920))
	var height := float(viewport.get("height", 1080))
	var anchor := {"x": width * 0.5, "y": height * 0.65}
	if _runtime != null and _runtime.has_method("get_resident_screen_anchor"):
		var runtime_anchor := _runtime.call("get_resident_screen_anchor", resident_name) as Dictionary
		if not runtime_anchor.is_empty():
			anchor = runtime_anchor.duplicate(true)
	var anchor_x := float(anchor.get("x", width * 0.5))
	var anchor_y := float(anchor.get("y", height * 0.65))
	return {
		"viewport": viewport,
		"screenAnchor": {"x": anchor_x, "y": anchor_y, "valid": not resident_name.is_empty(), "coordinateSpace": "viewport_logical"},
		"focusRect": {"x": anchor_x - 32, "y": anchor_y, "width": 64, "height": 96},
		"safeRect": {"x": 32, "y": 96, "width": maxf(0, width - 64), "height": maxf(0, height - 128)},
		"closeRect": {"x": maxf(0, width - 96), "y": 32, "width": 64, "height": 64},
		"avoidRects": [{"id": "top_status_bar", "x": 0, "y": 0, "width": width, "height": 64}],
		"preferredArc": "up",
		"pixelGrid": 4,
	}


func _announcement_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _world == null or not _world.has_method("get_announcements"):
		return result
	for value: Variant in _world.get_announcements() as Array:
		if not value is Dictionary:
			continue
		var item := (value as Dictionary).duplicate(true)
		var time := item.get("time", {}) as Dictionary
		item["time"] = time.duplicate(true)
		item["timeLabel"] = _time_label(time)
		var publisher_name := String(item.get("publisher_name", "")).strip_edges()
		var publisher_role := String(item.get("publisher_role", "")).strip_edges()
		item["publisherLabel"] = (
			"发布者：%s（%s）" % [publisher_name, publisher_role]
			if not publisher_name.is_empty() and not publisher_role.is_empty()
			else "发布者：%s" % publisher_name
			if not publisher_name.is_empty()
			else ""
		)
		var scheduled_label := String(
			item.get("scheduled_time_label", ""),
		).strip_edges()
		item["scheduleLabel"] = scheduled_label
		item["scheduleStatus"] = (
			"已到点"
			if item.has("schedule_triggered_at")
			else "等待到点"
			if not scheduled_label.is_empty()
			else ""
		)
		result.append(item)
	return result


func _time_label(time: Dictionary) -> String:
	var clock := String(time.get("clock", ""))
	var period := String(time.get("period", ""))
	if period.is_empty() and clock.length() >= 2:
		period = "上午" if int(clock.left(2)) < 12 else "下午"
	return "第 %d 天 · %s %s" % [int(time.get("day", 0)), period, clock]


func _read_weather() -> String:
	if _world != null and _world.has_method("get_weather"):
		return String(_world.get_weather())
	return ""


func _read_world_revision() -> int:
	return AiTownUiViewModel.world_revision(_world)


func _read_runtime_state() -> Dictionary:
	if _runtime != null and _runtime.has_method("get_runtime_state"):
		return (_runtime.call("get_runtime_state") as Dictionary).duplicate(true)
	return {}


func _resident_detail(resident_name: String) -> Dictionary:
	if (
		resident_name.is_empty()
		or _world == null
		or not _world.has_method("get_resident_detail")
	):
		return {}
	return _world.get_resident_detail(resident_name) as Dictionary


func _resident_state(resident_name: String) -> Dictionary:
	if (
		resident_name.is_empty()
		or _world == null
		or not _world.has_method("get_resident_state")
	):
		return {}
	return _world.get_resident_state(resident_name) as Dictionary


func _place_detail(place_name: String) -> Dictionary:
	if (
		place_name.is_empty()
		or _world == null
		or not _world.has_method("get_place_detail")
	):
		return {}
	return _world.get_place_detail(place_name) as Dictionary


func _place_name_for_space_id(space_id: String) -> String:
	if space_id.is_empty() or _world == null or not _world.has_method("get_place_names"):
		return ""
	for place_name_value: Variant in _world.get_place_names() as Array:
		var place_name := String(place_name_value)
		if String(_place_detail(place_name).get("spaceId", "")) == space_id:
			return place_name
	return ""


func _world_log_thread_item(thread_id: String) -> Dictionary:
	var normalized := thread_id.strip_edges()
	if normalized.is_empty() or not _world_log_query_available():
		return {}
	var query := _world.query_world_log_threads({}) as Dictionary
	if query.get("ok") != true:
		return {}
	for row_value: Variant in query.get("rows", []) as Array:
		if not row_value is Dictionary:
			continue
		var row := row_value as Dictionary
		if String(row.get("threadId", "")) == normalized:
			return _thread_to_place_log_item(row)
	return {}


func _resolve_world_log_thread_id(entry_id: String) -> String:
	# 条目 id 既可能是线程 id(来自 recentLogs),也可能是来源事件 id
	# (来自 currentEvents 的 eventId);两路依次尝试,与影子层
	# _town_log_item_by_id → _town_log_item_for_source_event 的次序等价。
	var normalized := entry_id.strip_edges()
	if normalized.is_empty() or not _world_log_query_available():
		return ""
	var detail := _world.get_world_log_thread_detail(normalized, {}) as Dictionary
	if detail.get("ok") == true:
		return normalized
	var found := _world.find_world_log_thread_by_source_event(
		normalized,
	) as Dictionary
	if found.get("ok") != true:
		return ""
	return String(found.get("threadId", ""))


func _place_log_items(place_name: String, limit: int) -> Array[Dictionary]:
	# G 之 1:数据源为世界侧 LogStore(影子层已拆除)。
	# query_threads 已按 latestSequence 倒序返回,与影子层"从新到旧"取前 N
	# 的顺序一致;条目形态由 _thread_to_place_log_item 映射(逐字段等价测试
	# 在 town_world_log_causal_query_test)。
	var result: Array[Dictionary] = []
	if place_name.is_empty() or limit <= 0:
		return result
	if not _world_log_query_available():
		return result
	var query := _world.query_world_log_threads({
		"placeId": place_name,
		"limit": limit,
	}) as Dictionary
	if query.get("ok") != true:
		return result
	for row_value: Variant in query.get("rows", []) as Array:
		if not row_value is Dictionary:
			continue
		result.append(_thread_to_place_log_item(row_value as Dictionary))
		if result.size() >= limit:
			break
	return result


func _thread_to_place_log_item(thread: Dictionary) -> Dictionary:
	# G 之 1 第二步适配器:把 LogStore 线程行映射为 place_focus 消费端期望的
	# 条目形态。类目映射按影子层的二值语义(对话类→social,其余→resident);
	# 参与者标签取线程参与者快照的显示名,与影子层 participantLabels 同义。
	# 本函数当前只供等价性比对,消费端切换在下一刀。
	var kind_tags := thread.get("kindTags", []) as Array
	var category := (
		"social"
		if kind_tags.has("conversation") or String(thread.get("kind", "")) == "conversation"
		else "resident"
	)
	var participant_labels: Array[String] = []
	for snapshot_value: Variant in thread.get("participantSnapshots", []) as Array:
		if not snapshot_value is Dictionary:
			continue
		var display_name := String(
			(snapshot_value as Dictionary).get("displayName", ""),
		).strip_edges()
		if not display_name.is_empty() and not participant_labels.has(display_name):
			participant_labels.append(display_name)
	return {
		"id": String(thread.get("threadId", "")),
		"timeLabel": _time_label(thread.get("updatedAt", {}) as Dictionary),
		"title": String(thread.get("title", "")),
		"subtitle": String(thread.get("preview", "")),
		"primaryCategory": category,
		"placeLabel": String(thread.get("placeLabel", "")),
		"participantLabels": participant_labels,
		"isHot": (
			(thread.get("participantIds", []) as Array).size()
			>= GATHERING_HOT_PARTICIPANT_COUNT
		),
		"observationKind": String(thread.get("observationKind", "")),
		"sourceEventIds": (thread.get("sourceEventIds", []) as Array).duplicate(),
	}


func _place_log_projections(items: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in items:
		result.append({
			"logEntryId": String(item.get("id", "")),
			"timeLabel": String(item.get("timeLabel", "")),
			"categoryId": String(item.get("primaryCategory", "")),
			"title": String(item.get("title", "")),
			"subtitle": String(item.get("subtitle", "")),
			"residentIds": _resident_ids_for_labels(item.get("participantLabels", []) as Array),
			"canOpen": true,
			"disabledReason": "",
		})
	return result


func _place_event_projection(item: Dictionary) -> Dictionary:
	var source_ids := item.get("sourceEventIds", []) as Array
	return {
		"eventId": String(source_ids[0]) if not source_ids.is_empty() else String(item.get("id", "")),
		"categoryId": String(item.get("primaryCategory", "")),
		"categoryLabel": String(item.get("primaryCategory", "")),
		"title": String(item.get("title", "")),
		"summary": String(item.get("subtitle", "")),
		"timeLabel": String(item.get("timeLabel", "")),
		"importance": "normal",
		"residentIds": _resident_ids_for_labels(item.get("participantLabels", []) as Array),
		"canOpen": true,
		"disabledReason": "",
	}


func _resident_ids_for_labels(labels: Array) -> Array[String]:
	var result: Array[String] = []
	for label_value: Variant in labels:
		var identity := _resident_identity_for_name(String(label_value))
		var resident_id := String(identity.get("residentId", ""))
		if not resident_id.is_empty() and not result.has(resident_id):
			result.append(resident_id)
	return result


func _load_resident_catalog_index() -> void:
	_resident_catalog_by_id.clear()
	if not FileAccess.file_exists(RESIDENT_CATALOG_PATH):
		return
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(RESIDENT_CATALOG_PATH),
	)
	if not parsed is Dictionary:
		return
	var catalog := parsed as Dictionary
	var ordinal := 0
	for value: Variant in catalog.get("residents", []) as Array:
		if not value is Dictionary:
			continue
		var record := (value as Dictionary).duplicate(true)
		var resident_id := String(record.get("residentId", "")).strip_edges()
		if resident_id.is_empty():
			continue
		record["_ordinal"] = ordinal
		ordinal += 1
		_resident_catalog_by_id[resident_id] = record


func _resident_catalog_record(resident_id: String) -> Dictionary:
	return (
		(_resident_catalog_by_id.get(resident_id, {}) as Dictionary).duplicate(true)
	)


func _load_wardrobe_portrait_index() -> void:
	_wardrobe_portrait_by_appearance_id.clear()
	if not FileAccess.file_exists(WARDROBE_CATALOG_PATH):
		return
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(WARDROBE_CATALOG_PATH),
	)
	if not parsed is Dictionary:
		return
	for value: Variant in (parsed as Dictionary).get("loadouts", []) as Array:
		if not value is Dictionary:
			continue
		var loadout := value as Dictionary
		var appearance_id := String(
			loadout.get("appearanceId", ""),
		).strip_edges()
		var portrait_path := String(
			loadout.get("portraitPath", ""),
		).strip_edges()
		if (
			appearance_id.begins_with("resident_wardrobe_v1:")
			and ResourceLoader.exists(portrait_path, "Texture2D")
		):
			_wardrobe_portrait_by_appearance_id[appearance_id] = portrait_path


func _resident_overview_has_resident(
	residents: Array[Dictionary],
	resident_id: String,
) -> bool:
	for resident in residents:
		if String(resident.get("residentId", "")) == resident_id:
			return true
	return false


func _resident_overview_portrait_ref(
	appearance_id: String,
	presentation: Dictionary,
) -> String:
	var current_portrait := String(
		_wardrobe_portrait_by_appearance_id.get(appearance_id, ""),
	)
	if not current_portrait.is_empty():
		return current_portrait
	var saved_portrait := String(
		presentation.get(
			"portraitPath",
			presentation.get("spritePath", ""),
		)
	)
	if (
		not saved_portrait.contains("/portraits/")
		and ResourceLoader.exists(saved_portrait, "Texture2D")
	):
		return saved_portrait
	return saved_portrait


func _resident_portrait_projection(
	resident_id: String,
	live_attributes: Dictionary = {},
) -> Dictionary:
	var catalog_record := _resident_catalog_record(resident_id)
	var catalog_attributes := catalog_record.get("attributes", {}) as Dictionary
	var presentation := catalog_record.get("presentation", {}) as Dictionary
	var attributes := live_attributes
	if attributes.is_empty():
		var resident_name := _resident_name_for_id(resident_id)
		var detail := _resident_detail(resident_name)
		attributes = detail.get("attributes", {}) as Dictionary
	var appearance_id := String(attributes.get("appearance", "")).strip_edges()
	if appearance_id.is_empty():
		appearance_id = String(
			catalog_attributes.get("appearance", ""),
		).strip_edges()
	var portrait_ref := _resident_overview_portrait_ref(
		appearance_id,
		presentation,
	).strip_edges()
	return {
		"appearanceId": appearance_id,
		"portraitRef": portrait_ref,
		"portraitFrameMode": (
			"full_texture"
			if portrait_ref.contains("/wardrobe_v1/")
			else "legacy_atlas_64x80"
		),
	}


func _resident_overview_phase_label(phase: String) -> String:
	return {
		"idle": "空闲",
		"thinking": "正在思考",
		"executing_preview": "准备行动",
		"executing": "行动中",
	}.get(phase, "状态已同步")


func _body_summary(body: Dictionary) -> String:
	if body.is_empty():
		return "生活状态暂未公开"
	var parts: Array[String] = []
	for key in ["累", "饿", "困"]:
		if body.has(key):
			parts.append(String(body.get(key, "")))
	return "、".join(parts) if not parts.is_empty() else "生活状态暂未公开"


func _body_need(body: Dictionary) -> String:
	for key in ["累", "饿", "困"]:
		var value := String(body.get(key, ""))
		if value.is_empty() or value.begins_with("不"):
			continue
		return value
	return "暂无紧迫需要"


func _condition_summary(conditions: Array) -> Dictionary:
	var labels: Array[String] = []
	var short_labels: Array[String] = []
	for condition_value: Variant in conditions:
		if typeof(condition_value) != TYPE_DICTIONARY:
			continue
		var condition := condition_value as Dictionary
		var state := String(condition.get("state", "active"))
		if state not in ["active", "recovering"]:
			continue
		var raw_label := String(condition.get("label", "")).strip_edges()
		if raw_label.is_empty():
			continue
		var label := raw_label
		if state == "recovering":
			label += "（恢复中）"
		if labels.has(label):
			continue
		labels.append(label)
		var short_label := _condition_short_label(
			String(condition.get("kind", "")),
			raw_label,
		)
		if state == "recovering":
			short_label += "（恢复中）"
		short_labels.append(short_label)
	if labels.is_empty():
		return {}
	return {
		"shortText": _compact_public_labels(short_labels),
		"text": "\n".join(labels),
	}


func _condition_need_summary(active_needs: Array) -> Dictionary:
	var labels: Array[String] = []
	var short_labels: Array[String] = []
	for need_value: Variant in active_needs:
		if typeof(need_value) != TYPE_DICTIONARY:
			continue
		var need := need_value as Dictionary
		var label := String(need.get("label", "")).strip_edges()
		if label.is_empty() or labels.has(label):
			continue
		labels.append(label)
		short_labels.append(_condition_need_short_label(
			String(need.get("kind", "")),
			label,
		))
	if labels.is_empty():
		return {}
	return {
		"shortText": _compact_public_labels(short_labels),
		"text": "\n".join(labels),
	}


func _compact_public_labels(labels: Array[String]) -> String:
	if labels.is_empty():
		return ""
	if labels.size() <= 2:
		return "、".join(labels)
	return "%s、%s（共%d项）" % [labels[0], labels[1], labels.size()]


func _condition_short_label(kind: String, fallback: String) -> String:
	return String({
		"wet": "淋湿",
		"chilled": "发冷",
		"malaise": "身体不适",
		"overfatigue": "过度疲劳",
		"strain": "酸痛",
		"minor_injury": "擦伤或扭伤",
		"minor_burn": "烫伤",
		"irritation": "刺激不适",
		"headache": "头痛",
	}.get(kind, fallback))


func _condition_need_short_label(kind: String, fallback: String) -> String:
	return String({
		"get_dry": "擦干休息",
		"warm_up": "保暖",
		"rest": "休息",
		"sleep": "睡眠",
		"eat": "进食",
		"leave_source": "离开不适来源",
		"self_care": "基础处理",
		"consider_clinic": "考虑看诊",
	}.get(kind, fallback))


func _resident_life_meters(activity_needs: Dictionary) -> Array[Dictionary]:
	var definitions: Array[Dictionary] = [
		{
			"id": "energy",
			"sourceKey": "energy",
			"label": "精力",
			"higherIsBetter": true,
		},
		{
			"id": "satiety",
			"sourceKey": "satiety",
			"label": "饱腹",
			"higherIsBetter": true,
		},
		{
			"id": "stress",
			"sourceKey": "stress",
			"label": "压力",
			"higherIsBetter": false,
		},
		{
			"id": "social_need",
			"sourceKey": "socialNeed",
			"label": "社交",
			"higherIsBetter": false,
		},
		{
			"id": "solitude_need",
			"sourceKey": "solitudeNeed",
			"label": "独处",
			"higherIsBetter": false,
		},
	]
	if activity_needs.size() != definitions.size():
		return []
	var meters: Array[Dictionary] = []
	for definition in definitions:
		var source_key := String(definition.get("sourceKey", ""))
		if not activity_needs.has(source_key):
			return []
		var raw_value: Variant = activity_needs.get(source_key)
		if typeof(raw_value) != TYPE_INT:
			return []
		var confirmed_value := int(raw_value)
		if confirmed_value < 0 or confirmed_value > 100:
			return []
		var higher_is_better := bool(
			definition.get("higherIsBetter", false)
		)
		var severity_value := (
			100 - confirmed_value
			if higher_is_better
			else confirmed_value
		)
		var severity_level := _resident_meter_level(severity_value)
		var segments_filled := clampi(
			int(round(float(confirmed_value) / 20.0)),
			0,
			5,
		)
		var tone := String(
			{
				"low": "normal",
				"medium": "attention",
				"high": "warning",
			}.get(severity_level, "attention")
		)
		if higher_is_better:
			tone = String(
				{
					"low": "normal",
					"medium": "attention",
					"high": "warning",
				}.get(severity_level, "attention")
			)
		meters.append({
			"id": String(definition.get("id", source_key)),
			"label": String(definition.get("label", "")),
			"levelId": severity_level,
			"levelLabel": "%d / 100" % confirmed_value,
			"shortLevelLabel": "%d" % confirmed_value,
			"value": confirmed_value,
			"minimum": 0,
			"maximum": 100,
			"segmentsFilled": segments_filled,
			"segmentCount": 5,
			"tone": tone,
			"urgent": severity_level == "high",
		})
	return meters


func _resident_meter_level(severity_value: int) -> String:
	if severity_value >= 70:
		return "high"
	if severity_value >= 30:
		return "medium"
	return "low"


func _read_lifecycle() -> Dictionary:
	if _runtime != null and _runtime.has_method("get_lifecycle_state"):
		return (_runtime.call("get_lifecycle_state") as Dictionary).duplicate(true)
	return {}


func _session_formal_ready() -> bool:
	if _session_config.has("formalReady"):
		return bool(_session_config.get("formalReady", false))
	return String(_session_config.get("worldStartMode", "development")) == "formal"


func _session_capability_mode() -> String:
	if _session_config.has("capabilityMode"):
		return String(_session_config.get("capabilityMode", "unavailable"))
	return "formal" if _session_formal_ready() else "development"


func _session_internal_playtest() -> bool:
	return (
		bool(_session_config.get("internalPlaytest", false))
		and _session_capability_mode() == "development"
		and not _session_formal_ready()
	)


func _scope_for_intent(intent: String) -> String:
	return TownUiIntentScopeTable.scope_for_intent(intent)

func _action_for_intent(
	view_model: Dictionary,
	intent: String,
	payload: Dictionary = {},
) -> Dictionary:
	var matches: Array[Dictionary] = []
	for action_value: Variant in (view_model.get("actions", {}) as Dictionary).values():
		if (
			action_value is Dictionary
			and String((action_value as Dictionary).get("intent", "")) == intent
		):
			matches.append((action_value as Dictionary).duplicate(true))
	if matches.size() == 1:
		return matches[0]
	for action: Dictionary in matches:
		var action_payload := action.get("payload", {}) as Dictionary
		var selectors_match := true
		for selector: String in ["tab", "tabId", "filterId", "kind", "direction"]:
			if not action_payload.has(selector):
				continue
			if String(action_payload.get(selector, "")) != String(
				payload.get(selector, "")
			):
				selectors_match = false
				break
		if selectors_match:
			return action
	return {}


func _action(
	intent: String,
	enabled: bool,
	disabled_reason: String,
	payload: Dictionary = {},
) -> Dictionary:
	return {
		"intent": intent,
		"enabled": enabled,
		"disabledReason": "" if enabled else disabled_reason,
		"payload": payload.duplicate(true),
	}


func _operation(
	request_id: String,
	intent: String,
	status: String,
	submitted_at: int,
	completed_at: int,
) -> Dictionary:
	return {
		"requestId": request_id,
		"intent": intent,
		"status": status,
		"submittedAtMsec": submitted_at,
		"completedAtMsec": completed_at,
	}


func _idle_operation() -> Dictionary:
	return AiTownUiViewModel.idle_operation()


func _error_payload(
	code: String,
	retryable: bool,
	message: String,
	details: Variant = [],
) -> Dictionary:
	return {
		"kind": "transport" if retryable else "rejected",
		"code": code,
		"retryable": retryable,
		"message": message,
		"details": details.duplicate(true) if details is Array else [],
	}


func _resident_memory_error_message(error_code: String) -> String:
	if error_code == "AGENT_GATEWAY_SESSION_INACTIVE":
		return "居民资料正在连接 Agent 会话，请稍后刷新。"
	if error_code == "RESIDENT_MEMORY_READ_FAILED":
		return "居民记忆读取失败，请稍后重试。"
	return "居民公开资料暂时没有准备好。"


func _next_request_id() -> String:
	_request_sequence += 1
	return "page-projection-%d-%d" % [_request_sequence, Time.get_ticks_msec()]


func _dispatch_success(request_id: String) -> Dictionary:
	return {"ok": true, "accepted": true, "requestId": request_id, "errorCode": "", "retryable": false}


func _dispatch_failure(
	error_code: String,
	retryable: bool,
	request_id: String,
) -> Dictionary:
	return {"ok": false, "accepted": false, "requestId": request_id, "errorCode": error_code, "retryable": retryable}


func _command_dispatch_result(request_id: String, result: Dictionary) -> Dictionary:
	return {
		"ok": bool(result.get("ok", false)),
		"accepted": true,
		"requestId": request_id,
		"errorCode": String(result.get("errorCode", "")),
		"retryable": bool(result.get("retryable", false)),
	}


func _unknown_scope_view_model(scope: String) -> Dictionary:
	return {
		"scope": scope,
		"status": "error",
		"revision": 0,
		"source": "runtime",
		"capabilityMode": "unavailable",
		"formalReady": false,
		"data": {},
		"actions": {},
		"operation": _idle_operation(),
		"error": _error_payload("UNKNOWN_UI_SCOPE", false, "未知页面 scope。"),
	}


func _connect_world_signals() -> void:
	_connect_signal(_world, &"world_revision_changed", Callable(self, "_on_world_revision_changed"))
	_connect_signal(_world, &"world_log_changed", Callable(self, "_on_world_log_changed"))
	_connect_signal(_world, &"environment_changed", Callable(self, "_on_environment_changed"))
	_connect_signal(_world, &"announcement_published", Callable(self, "_on_announcement_published"))
	_connect_signal(_world, &"world_event_created", Callable(self, "_on_world_event_created"))
	_connect_signal(_world, &"story_event_created", Callable(self, "_on_story_event_created"))
	_connect_signal(_world, &"action_result_created", Callable(self, "_on_action_result_created"))
	_connect_signal(_world, &"resident_place_changed", Callable(self, "_on_resident_place_changed"))
	_connect_signal(_world, &"player_avatar_place_changed", Callable(self, "_on_player_avatar_place_changed"))
	_connect_signal(_world, &"world_restored", Callable(self, "_on_world_restored"))


func _disconnect_world_signals() -> void:
	_disconnect_signal(_world, &"world_revision_changed", Callable(self, "_on_world_revision_changed"))
	_disconnect_signal(_world, &"world_log_changed", Callable(self, "_on_world_log_changed"))
	_disconnect_signal(_world, &"environment_changed", Callable(self, "_on_environment_changed"))
	_disconnect_signal(_world, &"announcement_published", Callable(self, "_on_announcement_published"))
	_disconnect_signal(_world, &"world_event_created", Callable(self, "_on_world_event_created"))
	_disconnect_signal(_world, &"story_event_created", Callable(self, "_on_story_event_created"))
	_disconnect_signal(_world, &"action_result_created", Callable(self, "_on_action_result_created"))
	_disconnect_signal(_world, &"resident_place_changed", Callable(self, "_on_resident_place_changed"))
	_disconnect_signal(_world, &"player_avatar_place_changed", Callable(self, "_on_player_avatar_place_changed"))
	_disconnect_signal(_world, &"world_restored", Callable(self, "_on_world_restored"))


func _connect_runtime_signals() -> void:
	_connect_signal(
		_runtime,
		&"observed_place_changed",
		Callable(self, "_on_observed_place_changed"),
	)


func _disconnect_runtime_signals() -> void:
	_disconnect_signal(
		_runtime,
		&"observed_place_changed",
		Callable(self, "_on_observed_place_changed"),
	)


func _connect_signal(source: Object, signal_name: StringName, callback: Callable) -> void:
	if source != null and source.has_signal(signal_name) and not source.is_connected(signal_name, callback):
		source.connect(signal_name, callback)


func _disconnect_signal(source: Object, signal_name: StringName, callback: Callable) -> void:
	if source != null and source.has_signal(signal_name) and source.is_connected(signal_name, callback):
		source.disconnect(signal_name, callback)


func _on_world_revision_changed(revision: int) -> void:
	if revision <= _last_world_revision:
		return
	_last_world_revision = revision
	_flag_town_log_newer()
	for scope in WORLD_REFRESH_SCOPES:
		_dirty_world_scopes[scope] = true
		if _world_scope_is_visible(scope):
			refresh(scope)


func _on_environment_changed(time: Dictionary, weather: String) -> void:
	_dirty_world_scopes["weather_control"] = true
	if _world_scope_is_visible("weather_control"):
		refresh("weather_control")


func _on_world_log_changed(_change: Dictionary) -> void:
	_flag_town_log_newer()
	_dirty_world_scopes["town_log"] = true
	if _town_log_open:
		_reload_town_log_threads()
		_publish_town_log(_idle_operation(), null)


func _world_scope_is_visible(scope: String) -> bool:
	if scope == "town_log":
		return _town_log_open
	var context := _page_contexts.get(scope, {}) as Dictionary
	return context.get("open", false) == true


func _on_announcement_published(announcement: Dictionary) -> void:
	_flag_town_log_newer()
	_publish_announcements(_idle_operation(), null)
	_publish_town_log(_idle_operation(), null)


func _refresh_log_scopes_if_visible() -> void:
	_flag_town_log_newer()
	_dirty_world_scopes["town_log"] = true
	_dirty_world_scopes["indoor"] = true
	if _world_scope_is_visible("town_log"):
		_publish_town_log(_idle_operation(), null)
	if _world_scope_is_visible("indoor"):
		_publish_indoor(_idle_operation(), null)


func _on_world_event_created(resident_name: String, event: Dictionary) -> void:
	_refresh_log_scopes_if_visible()


func _on_story_event_created(event: Dictionary) -> void:
	_refresh_log_scopes_if_visible()


func _on_action_result_created(resident_name: String, result: Dictionary) -> void:
	_refresh_log_scopes_if_visible()


func _on_resident_place_changed(resident_name: String, change: Dictionary) -> void:
	_refresh_log_scopes_if_visible()


func _on_player_avatar_place_changed(change: Dictionary) -> void:
	_refresh_log_scopes_if_visible()


func _on_world_restored(_summary: Dictionary) -> void:
	_seed_town_log()
	_refresh_log_scopes_if_visible()


func _on_observed_place_changed(result: Dictionary) -> void:
	var transition_kind := String(result.get("transitionKind", ""))
	if transition_kind == "return_outdoor":
		if _pending_indoor_return_operation.is_empty():
			_publish_indoor(_idle_operation(), null)
			return
		var request_id := String(
			_pending_indoor_return_operation.get("requestId", "")
		)
		var intent := String(
			_pending_indoor_return_operation.get(
				"intent",
				"indoor.return_outdoor",
			)
		)
		var submitted_at := int(
			_pending_indoor_return_operation.get("submittedAtMsec", 0)
		)
		var expected_place := String(
			_pending_indoor_return_operation.get("placeName", "")
		)
		if (
			not expected_place.is_empty()
			and String(result.get("placeName", "")) != expected_place
		):
			return
		_pending_indoor_return_operation.clear()
		if bool(result.get("ok", false)):
			_publish_indoor(
				_operation(
					request_id,
					intent,
					"success",
					submitted_at,
					Time.get_ticks_msec(),
				),
				null,
			)
			return
		_publish_indoor(
			_operation(
				request_id,
				intent,
				(
					"error"
					if bool(result.get("retryable", false))
					else "rejected"
				),
				submitted_at,
				Time.get_ticks_msec(),
			),
			result,
		)
		return
	if not _pending_indoor_return_operation.is_empty():
		return
	# The indoor page must consume the runtime state produced by this
	# transition, not the idle snapshot cached before entering the building.
	# This also covers physical/direct observer entries that have no pending
	# place-focus operation, without replacing an unrelated pending return.
	_publish_indoor(_idle_operation(), null)
	if _pending_place_focus_operation.is_empty():
		return
	var request_id := String(_pending_place_focus_operation.get("requestId", ""))
	var intent := String(_pending_place_focus_operation.get("intent", "place_focus.enter_interior"))
	var submitted_at := int(_pending_place_focus_operation.get("submittedAtMsec", 0))
	var expected_place := String(_pending_place_focus_operation.get("placeName", ""))
	if String(result.get("placeName", "")) != expected_place:
		return
	_pending_place_focus_operation.clear()
	if bool(result.get("ok", false)):
		_publish_place_focus(
			_operation(request_id, intent, "success", submitted_at, Time.get_ticks_msec()),
			null,
		)
		return
	_publish_place_focus(
		_operation(request_id, intent, "error" if bool(result.get("retryable", false)) else "rejected", submitted_at, Time.get_ticks_msec()),
		result,
	)
