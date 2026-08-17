class_name TownAudioDisplaySettingsService
extends Node


signal view_model_changed(scope: String, view_model: Dictionary)
signal ui_scale_changed(percent: int)


const STORE := preload("res://world/presentation/ui/TownAudioDisplaySettingsStore.gd")
const RESPONSIVE_VIEWPORT := preload("res://ui/common/ResponsiveViewportPolicy.gd")
const SCOPE := "audio_display_settings"
const SOURCE := "runtime"
const CAPABILITY_MODE := "formal"
const REDUCED_FLASHING_SETTING := "application/accessibility/reduced_flashing"
const DISPLAY_CONFIRMATION_MSEC := 15_000
const WINDOWED_GEOMETRY_RETRY_MSEC := 2_000
const DISPLAY_SIZE_TOLERANCE_PX := 4
const SCREEN_COVERAGE_TOLERANCE_PX := 16
const EXTERNAL_FULLSCREEN_EXIT_GRACE_MSEC := 500
const DEFAULT_WINDOWED_SIZE := RESPONSIVE_VIEWPORT.DESIGN_SIZE
const WEB_CANVAS_SIZE := Vector2i(1280, 720)
const MINIMUM_WINDOW_SIZE := RESPONSIVE_VIEWPORT.MINIMUM_WINDOW_SIZE
const FULLSCREEN_WINDOW_MODES := [
	DisplayServer.WINDOW_MODE_FULLSCREEN,
	DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
]
const RESOLUTION_SIZES: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]
const UI_SCALE_PERCENTS: Array[int] = [100]
const UI_SCALE_POLICY_REASON := "UI_SCALE_AUTOMATIC_BY_LAYOUT_POLICY"
const REQUIRED_UI_SCALE_CONSUMERS := ["responsive_layout"]
const AUDIO_DEFAULTS := {
	"masterPercent": 80,
	"musicPercent": 55,
	"ambiencePercent": 45,
	"sfxPercent": 70,
	"uiPercent": 60,
	"muted": false,
}
const AUDIO_CHANNELS := {
	"master": {"dataKey": "masterPercent", "aliases": ["Master"]},
	"music": {"dataKey": "musicPercent", "aliases": ["Music", "BGM"]},
	"ambience": {"dataKey": "ambiencePercent", "aliases": ["Ambience", "Ambient"]},
	"sfx": {"dataKey": "sfxPercent", "aliases": ["SFX", "Effects"]},
	"ui": {"dataKey": "uiPercent", "aliases": ["UI", "Interface"]},
}
const INTENT_TO_ACTION := {
	"audio_display_settings.set_audio_value": "setAudioValue",
	"audio_display_settings.toggle_mute": "toggleMute",
	"audio_display_settings.select_resolution": "selectResolution",
	"audio_display_settings.select_window_mode": "selectWindowMode",
	"audio_display_settings.select_ui_scale": "selectUiScale",
	"audio_display_settings.toggle_reduced_flashing": "toggleReducedFlashing",
	"audio_display_settings.apply": "apply",
	"audio_display_settings.restore_defaults": "restoreDefaults",
	"audio_display_settings.discard_changes": "discardChanges",
	"audio_display_settings.confirm_display": "confirmDisplay",
	"audio_display_settings.revert_display": "revertDisplay",
	"audio_display_settings.retry": "retry",
	"audio_display_settings.back": "back",
}


@export var settings_path := STORE.DEFAULT_SETTINGS_PATH
@export var display_confirmation_timeout_msec := DISPLAY_CONFIRMATION_MSEC

var _revision := 1
var _request_sequence := 0
var _operation := _idle_operation()
var _error: Variant = null
var _store: STORE
var _initialized := false
var _confirmed: Dictionary = {}
var _draft: Dictionary = {}
var _defaults: Dictionary = {}
var _storage := {"status": "ready", "errorCode": "", "message": ""}
var _feedback := {"kind": "", "code": "", "message": ""}
var _last_retryable: Dictionary = {}
var _confirmation: Dictionary = {}
var _display_before_confirmation: Dictionary = {}
var _confirmation_last_second := -1
var _windowed_size := DEFAULT_WINDOWED_SIZE
var _effective_ui_scale_percent := 100
var _ui_scale_consumer: Object
var _display_backend: Object
var _pending_windowed_geometry: Dictionary = {}
var _last_observed_window_mode := -1
var _external_fullscreen_exit_grace_until_msec := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_initialize_runtime_state()
	_enforce_window_constraints()


func _process(_delta: float) -> void:
	_process_pending_windowed_geometry()
	_synchronize_external_fullscreen_state()
	if not bool(_confirmation.get("active", false)):
		return
	var remaining_msec := int(_confirmation.get("deadlineMsec", 0)) - Time.get_ticks_msec()
	if remaining_msec <= 0:
		_revert_confirmation(true)
		return
	var remaining_second := ceili(float(remaining_msec) / 1000.0)
	if remaining_second != _confirmation_last_second:
		_confirmation_last_second = remaining_second
		_revision += 1
		_emit_view_model()


func _exit_tree() -> void:
	if bool(_confirmation.get("active", false)):
		_restore_display_state(_display_before_confirmation)


func bind_ui_scale_consumer(consumer: Object) -> Dictionary:
	return {
		"ok": false,
		"bound": false,
		"errorCode": UI_SCALE_POLICY_REASON,
	}


func toggle_fullscreen_from_global_shortcut() -> bool:
	_initialize_runtime_state()
	if (
		_display_server_name().to_lower() != "windows"
		or not _display_changes_available()
		or bool(_confirmation.get("active", false))
	):
		return false
	var current_mode := _display_window_get_mode()
	var target_display := (
		_confirmed.get("display", {}) as Dictionary
	).duplicate(true)
	target_display["windowModeId"] = (
		"windowed"
		if current_mode in FULLSCREEN_WINDOW_MODES
		else "borderless_fullscreen"
	)
	var applied := _apply_display_draft(target_display)
	if not bool(applied.get("ok", false)):
		return false
	_last_observed_window_mode = _display_window_get_mode()
	if current_mode in FULLSCREEN_WINDOW_MODES:
		_external_fullscreen_exit_grace_until_msec = (
			Time.get_ticks_msec() + EXTERNAL_FULLSCREEN_EXIT_GRACE_MSEC
		)
	else:
		_external_fullscreen_exit_grace_until_msec = 0
	_adopt_runtime_display(target_display, "FULLSCREEN_SHORTCUT_APPLIED")
	return true


func configure_display_backend_for_tests(backend: Object) -> Dictionary:
	if _initialized:
		return {
			"ok": false,
			"errorCode": "DISPLAY_TEST_BACKEND_TOO_LATE",
		}
	if backend == null:
		_display_backend = null
		return {"ok": true}
	for method_name: String in [
		"get_name",
		"window_get_mode",
		"window_set_mode",
		"window_get_size",
		"window_set_size",
		"window_get_position",
		"window_set_position",
		"window_get_current_screen",
		"screen_get_usable_rect",
	]:
		if not backend.has_method(method_name):
			return {
				"ok": false,
				"errorCode": "DISPLAY_TEST_BACKEND_INVALID",
				"missingMethod": method_name,
			}
	_display_backend = backend
	return {"ok": true}


func get_view_model() -> Dictionary:
	_initialize_runtime_state()
	var capabilities := _capability_snapshot()
	var data := _data_snapshot(capabilities)
	var actions := _actions_snapshot(capabilities, data)
	var operation_status := String(_operation.get("status", "idle"))
	var status := "ready"
	if operation_status == "loading":
		status = "loading"
	elif operation_status == "error":
		status = "error"
	return {
		"scope": SCOPE,
		"status": status,
		"revision": _revision,
		"data": data,
		"actions": actions,
		"operation": _operation.duplicate(true),
		"error": null if _error == null else (_error as Dictionary).duplicate(true),
	}


func dispatch(intent_value: Variant, payload_value: Variant = {}) -> Dictionary:
	if typeof(intent_value) != TYPE_STRING:
		return _dispatch_unknown()
	if typeof(payload_value) != TYPE_DICTIONARY:
		return _dispatch_invalid_payload()
	var intent := String(intent_value)
	var payload := (payload_value as Dictionary).duplicate(true)
	var action_key := String(INTENT_TO_ACTION.get(intent, ""))
	if action_key.is_empty():
		return _dispatch_unknown()
	_initialize_runtime_state()
	var request_revision: Variant = payload.get("revision")
	if typeof(request_revision) != TYPE_INT or int(request_revision) != _revision:
		return _dispatch_revision_stale()
	_process_pending_windowed_geometry()
	var action := ((get_view_model().get("actions", {}) as Dictionary).get(action_key, {}) as Dictionary)
	var request_id := _next_request_id()
	_revision += 1
	_operation = {
		"requestId": request_id,
		"intent": intent,
		"status": "loading",
		"submittedAtMsec": Time.get_ticks_msec(),
		"completedAtMsec": 0,
	}
	_error = null
	_emit_view_model()
	var result: Dictionary
	if not bool(action.get("enabled", false)):
		var disabled_reason := String(
			action.get("disabledReason", "AUDIO_DISPLAY_ACTION_DISABLED"),
		)
		if (
			intent == "audio_display_settings.confirm_display"
			and disabled_reason == "DISPLAY_APPLY_FAILED"
		):
			result = _failure(
				"DISPLAY_APPLY_FAILED",
				true,
				"窗口没有切换到请求的显示状态，已恢复原画面。",
				"error",
			)
		else:
			result = _failure(
				disabled_reason,
				false,
				"当前不能执行这项设置操作。",
			)
	else:
		result = _execute_intent(intent, payload)
	var ok := bool(result.get("ok", false))
	_operation["status"] = "success" if ok else String(result.get("operationStatus", "rejected"))
	_operation["completedAtMsec"] = Time.get_ticks_msec()
	_error = null if ok else _error_payload(result)
	if not ok and bool(result.get("retryable", false)):
		_last_retryable = {
			"intent": String(result.get("retryIntent", intent)),
			"payload": (result.get("retryPayload", payload) as Dictionary).duplicate(true),
		}
	elif ok and intent in [
		"audio_display_settings.apply",
		"audio_display_settings.confirm_display",
		"audio_display_settings.retry",
	]:
		_last_retryable = {}
	_emit_view_model()
	return {
		"ok": ok,
		"accepted": true,
		"requestId": request_id,
		"errorCode": String(result.get("errorCode", "")),
		"retryable": bool(result.get("retryable", false)),
		"changed": bool(result.get("changed", false)),
		"revision": _revision,
	}


func _execute_intent(intent: String, payload: Dictionary) -> Dictionary:
	match intent:
		"audio_display_settings.set_audio_value":
			return _stage_audio_value(payload)
		"audio_display_settings.toggle_mute":
			return _stage_mute(payload)
		"audio_display_settings.select_resolution":
			return _stage_resolution(payload)
		"audio_display_settings.select_window_mode":
			return _stage_window_mode(payload)
		"audio_display_settings.select_ui_scale":
			return _stage_ui_scale(payload)
		"audio_display_settings.toggle_reduced_flashing":
			return _stage_reduced_flashing(payload)
		"audio_display_settings.apply":
			return _apply_changes()
		"audio_display_settings.restore_defaults":
			return _restore_defaults()
		"audio_display_settings.discard_changes":
			return _discard_changes()
		"audio_display_settings.confirm_display":
			return _confirm_display()
		"audio_display_settings.revert_display":
			return _revert_confirmation(false)
		"audio_display_settings.retry":
			return _retry_last_failure()
		"audio_display_settings.back":
			if bool(_confirmation.get("active", false)):
				return _failure("DISPLAY_CONFIRMATION_REQUIRED", false, "请先保留或恢复显示设置。")
			if _is_dirty():
				return _failure("SETTINGS_DIRTY_CONFIRM_REQUIRED", false, "仍有尚未应用的设置。")
			return _success(false)
	return _failure("UNKNOWN_AUDIO_DISPLAY_INTENT", false, "未知设置操作。")


func _stage_audio_value(payload: Dictionary) -> Dictionary:
	var setting_id_value: Variant = payload.get("settingId")
	if typeof(setting_id_value) != TYPE_STRING:
		return _failure("AUDIO_SETTING_INVALID", false, "音频通道无效。")
	var setting_id := String(setting_id_value)
	if not AUDIO_CHANNELS.has(setting_id):
		return _failure("AUDIO_SETTING_UNKNOWN", false, "未知音频通道。")
	var value: Variant = payload.get("percent")
	if typeof(value) != TYPE_INT:
		return _failure("AUDIO_PERCENT_INVALID", false, "音量必须是 0 到 100 的整数。")
	var percent := int(value)
	if percent < 0 or percent > 100:
		return _failure("AUDIO_PERCENT_INVALID", false, "音量必须在 0 到 100 之间。")
	var bus_index := _audio_bus_index(setting_id)
	if bus_index < 0:
		return _failure("AUDIO_BUS_UNAVAILABLE", true, "音频通道尚未就绪。", "error")
	var data_key := String((AUDIO_CHANNELS[setting_id] as Dictionary).get("dataKey", ""))
	var draft_audio := _draft.get("audio", {}) as Dictionary
	if int(draft_audio.get(data_key, 0)) == percent:
		return _success(false)
	var before_db := AudioServer.get_bus_volume_db(bus_index)
	AudioServer.set_bus_volume_db(bus_index, _percent_to_db(percent))
	if absi(_db_to_percent(AudioServer.get_bus_volume_db(bus_index)) - percent) > 1:
		AudioServer.set_bus_volume_db(bus_index, before_db)
		return _failure("AUDIO_PREVIEW_FAILED", true, "音量试听失败，原值已恢复。", "error")
	draft_audio[data_key] = percent
	return _success(true)


func _stage_mute(payload: Dictionary) -> Dictionary:
	if typeof(payload.get("muted")) != TYPE_BOOL:
		return _failure("AUDIO_MUTE_INVALID", false, "静音状态无效。")
	var bus_index := _audio_bus_index("master")
	if bus_index < 0:
		return _failure("AUDIO_BUS_UNAVAILABLE", true, "主音频通道不可用。", "error")
	var muted := bool(payload.get("muted"))
	var draft_audio := _draft.get("audio", {}) as Dictionary
	if bool(draft_audio.get("muted", false)) == muted:
		return _success(false)
	var before_mute := AudioServer.is_bus_mute(bus_index)
	AudioServer.set_bus_mute(bus_index, muted)
	if AudioServer.is_bus_mute(bus_index) != muted:
		AudioServer.set_bus_mute(bus_index, before_mute)
		return _failure("AUDIO_PREVIEW_FAILED", true, "静音试听失败。", "error")
	draft_audio["muted"] = muted
	return _success(true)


func _stage_resolution(payload: Dictionary) -> Dictionary:
	var display := _draft.get("display", {}) as Dictionary
	if String(display.get("windowModeId", "windowed")) != "windowed":
		return _failure("RESOLUTION_FOLLOWS_DESKTOP", false, "全屏模式的分辨率跟随桌面。")
	var resolution_value: Variant = payload.get("resolutionId")
	if typeof(resolution_value) != TYPE_STRING:
		return _failure("DISPLAY_RESOLUTION_INVALID", false, "分辨率选项无效。")
	var resolution_id := String(resolution_value)
	if not _resolution_is_offered(resolution_id):
		return _failure("DISPLAY_RESOLUTION_INVALID", false, "分辨率选项无效。")
	if String(display.get("windowedResolutionId", "")) == resolution_id:
		return _success(false)
	display["windowedResolutionId"] = resolution_id
	return _success(true)


func _stage_window_mode(payload: Dictionary) -> Dictionary:
	var mode_value: Variant = payload.get("windowModeId")
	if typeof(mode_value) != TYPE_STRING:
		return _failure("DISPLAY_WINDOW_MODE_UNAVAILABLE", false, "当前平台不支持这个窗口模式。")
	var mode_id := String(mode_value)
	if not _window_mode_is_offered(mode_id):
		return _failure("DISPLAY_WINDOW_MODE_UNAVAILABLE", false, "当前平台不支持这个窗口模式。")
	var display := _draft.get("display", {}) as Dictionary
	if String(display.get("windowModeId", "")) == mode_id:
		return _success(false)
	display["windowModeId"] = mode_id
	return _success(true)


func _stage_ui_scale(payload: Dictionary) -> Dictionary:
	return _failure(
		UI_SCALE_POLICY_REASON,
		false,
		"界面会随窗口和分辨率自动重排。",
	)


func _stage_reduced_flashing(payload: Dictionary) -> Dictionary:
	if typeof(payload.get("enabled")) != TYPE_BOOL:
		return _failure("REDUCED_FLASHING_INVALID", false, "减少闪烁状态无效。")
	var display := _draft.get("display", {}) as Dictionary
	var enabled := bool(payload.get("enabled"))
	if bool(display.get("reducedFlashingEnabled", false)) == enabled:
		return _success(false)
	display["reducedFlashingEnabled"] = enabled
	return _success(true)


func _apply_changes() -> Dictionary:
	if not _is_dirty():
		return _success(false)
	var draft_display := _draft.get("display", {}) as Dictionary
	var confirmed_display := _confirmed.get("display", {}) as Dictionary
	var ui_scale_changed_now := (
		int(draft_display.get("uiScalePercent", 100))
		!= int(confirmed_display.get("uiScalePercent", 100))
	)
	if ui_scale_changed_now and _ui_scale_consumer == null:
		return _failure(
			UI_SCALE_POLICY_REASON,
			false,
			"界面缩放由响应式布局自动管理，未应用手动缩放值。",
		)
	var dangerous_display_change := ui_scale_changed_now
	dangerous_display_change = dangerous_display_change or (
		String(draft_display.get("windowModeId", "windowed"))
		!= String(confirmed_display.get("windowModeId", "windowed"))
	)
	dangerous_display_change = dangerous_display_change or (
		String(draft_display.get("windowModeId", "windowed")) == "windowed"
		and String(draft_display.get("windowedResolutionId", ""))
		!= String(confirmed_display.get("windowedResolutionId", ""))
	)
	if dangerous_display_change:
		_display_before_confirmation = _capture_display_state()
		var applied := _apply_display_draft(draft_display)
		if not bool(applied.get("ok", false)):
			_pending_windowed_geometry.clear()
			_restore_display_state(_display_before_confirmation)
			_display_before_confirmation = {}
			return applied
		_confirmation = {
			"active": true,
			"deadlineMsec": Time.get_ticks_msec() + display_confirmation_timeout_msec,
			"previousDisplay": _display_for_view(confirmed_display),
			"targetDisplay": _display_for_view(draft_display),
		}
		_confirmation_last_second = -1
		_feedback = {
			"kind": "confirmation",
			"code": "DISPLAY_CONFIRMATION_REQUIRED",
			"message": "请确认是否保留新的显示设置。",
		}
		return _success(true)
	return _persist_confirmed_draft()


func _confirm_display() -> Dictionary:
	if not bool(_confirmation.get("active", false)):
		return _failure("DISPLAY_CONFIRMATION_NOT_ACTIVE", false, "当前没有待确认的显示设置。")
	if Time.get_ticks_msec() >= int(_confirmation.get("deadlineMsec", 0)):
		_revert_confirmation(true)
		return _failure(
			"DISPLAY_CONFIRMATION_EXPIRED",
			false,
			"显示设置确认已超时，原画面已经恢复。",
		)
	_process_pending_windowed_geometry()
	if not bool(_confirmation.get("active", false)):
		return _failure(
			"DISPLAY_APPLY_FAILED",
			true,
			"窗口没有切换到请求的显示状态，已恢复原画面。",
			"error",
		)
	if not _pending_windowed_geometry.is_empty():
		return _failure(
			"DISPLAY_APPLY_PENDING",
			true,
			"窗口仍在应用新的显示设置，请稍后再确认。",
			"error",
		)
	var target := _confirmation.get("targetDisplay", {}) as Dictionary
	if not _display_target_matches(target):
		_fail_active_display_application()
		return _failure(
			"DISPLAY_APPLY_FAILED",
			true,
			"窗口没有切换到请求的显示状态，已恢复原画面。",
			"error",
		)
	var result := _persist_confirmed_draft()
	if not bool(result.get("ok", false)):
		_restore_display_state(_display_before_confirmation)
		_confirmation = {}
		_display_before_confirmation = {}
		_feedback = {
			"kind": "error",
			"code": "SETTINGS_SAVE_FAILED",
			"message": String(result.get("message", "设置保存失败，显示已恢复。")),
		}
		result["retryIntent"] = "audio_display_settings.apply"
		result["retryPayload"] = {}
		return result
	_confirmation = {}
	_display_before_confirmation = {}
	_feedback = {"kind": "success", "code": "DISPLAY_CONFIRMED", "message": "显示设置已保留。"}
	return _success(true)


func _revert_confirmation(timed_out: bool) -> Dictionary:
	if not bool(_confirmation.get("active", false)):
		return _failure("DISPLAY_CONFIRMATION_NOT_ACTIVE", false, "当前没有待恢复的显示设置。")
	_restore_display_state(_display_before_confirmation)
	var draft_audio := (_draft.get("audio", {}) as Dictionary).duplicate(true)
	var draft_reduced := bool(
		(_draft.get("display", {}) as Dictionary).get("reducedFlashingEnabled", false)
	)
	_draft = _confirmed.duplicate(true)
	_draft["audio"] = draft_audio
	(_draft.get("display", {}) as Dictionary)["reducedFlashingEnabled"] = draft_reduced
	_confirmation = {}
	_display_before_confirmation = {}
	_feedback = {
		"kind": "notice",
		"code": "DISPLAY_CONFIRMATION_TIMED_OUT" if timed_out else "DISPLAY_REVERTED",
		"message": "未确认新的显示设置，已恢复原画面。" if timed_out else "显示设置已恢复。",
	}
	_revision += 1
	if timed_out:
		_operation = {
			"requestId": _next_request_id(),
			"intent": "audio_display_settings.revert_display",
			"status": "success",
			"submittedAtMsec": Time.get_ticks_msec(),
			"completedAtMsec": Time.get_ticks_msec(),
		}
		_error = null
		_emit_view_model()
	return _success(true)


func _restore_defaults() -> Dictionary:
	if _draft == _defaults:
		return _success(false)
	var before_audio := (_draft.get("audio", {}) as Dictionary).duplicate(true)
	var default_audio := _defaults.get("audio", {}) as Dictionary
	var applied := _apply_audio_snapshot(default_audio)
	if not bool(applied.get("ok", false)):
		_apply_audio_snapshot(before_audio)
		return applied
	_draft = _defaults.duplicate(true)
	_feedback = {"kind": "notice", "code": "DEFAULTS_STAGED", "message": "默认设置已填入，应用后保存。"}
	return _success(true)


func _discard_changes() -> Dictionary:
	var result := _apply_audio_snapshot(_confirmed.get("audio", {}) as Dictionary)
	if not bool(result.get("ok", false)):
		return result
	_draft = _confirmed.duplicate(true)
	_feedback = {"kind": "notice", "code": "CHANGES_DISCARDED", "message": "未应用的更改已放弃。"}
	return _success(true)


func _retry_last_failure() -> Dictionary:
	if _last_retryable.is_empty():
		return _failure("NOTHING_TO_RETRY", false, "没有可以重试的设置操作。")
	return _execute_intent(
		String(_last_retryable.get("intent", "")),
		(_last_retryable.get("payload", {}) as Dictionary).duplicate(true),
	)


func _persist_confirmed_draft() -> Dictionary:
	var target_reduced := bool(
		(_draft.get("display", {}) as Dictionary).get("reducedFlashingEnabled", false)
	)
	var before_reduced := bool(ProjectSettings.get_setting(REDUCED_FLASHING_SETTING, false))
	ProjectSettings.set_setting(REDUCED_FLASHING_SETTING, target_reduced)
	var saved := _store.call("save_settings", _draft) as Dictionary
	if not bool(saved.get("ok", false)):
		ProjectSettings.set_setting(REDUCED_FLASHING_SETTING, before_reduced)
		_storage = {
			"status": "error",
			"errorCode": String(saved.get("errorCode", "SETTINGS_SAVE_FAILED")),
			"message": String(saved.get("message", "设置保存失败。")),
		}
		return _failure(
			String(_storage.get("errorCode", "SETTINGS_SAVE_FAILED")),
			true,
			String(_storage.get("message", "设置保存失败。")),
			"error",
		)
	_confirmed = _draft.duplicate(true)
	_storage = {"status": "ready", "errorCode": "", "message": ""}
	_feedback = {"kind": "success", "code": "SETTINGS_APPLIED", "message": "设置已应用并保存。"}
	return _success(true)


func _initialize_runtime_state() -> void:
	if _initialized:
		return
	_initialized = true
	_ensure_audio_buses()
	if _display_available() and _window_mode_id() == "windowed":
		_windowed_size = _physical_window_size()
	var runtime := {
		"audio": _runtime_audio_snapshot(),
		"display": _runtime_display_snapshot(),
	}
	_defaults = {
		"audio": AUDIO_DEFAULTS.duplicate(true),
		"display": {
			"windowModeId": "windowed",
			"windowedResolutionId": _safe_default_resolution_id(),
			"uiScalePercent": 100,
			"reducedFlashingEnabled": false,
		},
	}
	_store = STORE.new(settings_path)
	var loaded := _store.call("load_settings", runtime) as Dictionary
	_confirmed = (loaded.get("settings", runtime) as Dictionary).duplicate(true)
	_normalize_confirmed_for_capabilities()
	_draft = _confirmed.duplicate(true)
	_apply_audio_snapshot(_confirmed.get("audio", {}) as Dictionary)
	var display := _confirmed.get("display", {}) as Dictionary
	ProjectSettings.set_setting(
		REDUCED_FLASHING_SETTING,
		bool(display.get("reducedFlashingEnabled", false)),
	)
	_effective_ui_scale_percent = int(display.get("uiScalePercent", 100))
	if not bool(loaded.get("ok", false)):
		_storage = {
			"status": "error",
			"errorCode": String(loaded.get("errorCode", "SETTINGS_LOAD_FAILED")),
			"message": String(loaded.get("message", "本机设置无法读取。")),
		}
	elif not bool(loaded.get("found", false)):
		var migrated := _store.call("save_settings", _confirmed) as Dictionary
		if not bool(migrated.get("ok", false)):
			_storage = {
				"status": "error",
				"errorCode": String(migrated.get("errorCode", "SETTINGS_SAVE_FAILED")),
				"message": String(migrated.get("message", "本机设置无法保存。")),
			}
	_apply_confirmed_display.call_deferred()


func _apply_confirmed_display() -> void:
	if not is_inside_tree():
		return
	var display := _confirmed.get("display", {}) as Dictionary
	_apply_display_draft(display)


func _synchronize_external_fullscreen_state() -> void:
	if (
		_display_server_name().to_lower() != "windows"
		or not _display_changes_available()
		or bool(_confirmation.get("active", false))
	):
		return
	var mode := _display_window_get_mode()
	var previous_mode := _last_observed_window_mode
	_last_observed_window_mode = mode
	if previous_mode < 0:
		previous_mode = mode
	if mode in FULLSCREEN_WINDOW_MODES:
		_external_fullscreen_exit_grace_until_msec = 0
		_normalize_active_windows_fullscreen(mode)
		return
	if previous_mode in FULLSCREEN_WINDOW_MODES:
		_external_fullscreen_exit_grace_until_msec = (
			Time.get_ticks_msec() + EXTERNAL_FULLSCREEN_EXIT_GRACE_MSEC
		)
		var windowed_display := (
			_confirmed.get("display", {}) as Dictionary
		).duplicate(true)
		windowed_display["windowModeId"] = "windowed"
		var restored_size := _size_from_resolution_id(
			String(windowed_display.get("windowedResolutionId", ""))
		)
		if restored_size.x > 0 and restored_size.y > 0:
			_windowed_size = restored_size
			_set_logical_canvas_size(DEFAULT_WINDOWED_SIZE)
		if String(
			(_confirmed.get("display", {}) as Dictionary).get(
				"windowModeId", "windowed"
			)
		) != "windowed":
			_adopt_runtime_display(
				windowed_display,
				"EXTERNAL_FULLSCREEN_EXITED",
			)
		return
	if Time.get_ticks_msec() < _external_fullscreen_exit_grace_until_msec:
		return
	if (
		mode == DisplayServer.WINDOW_MODE_MAXIMIZED
		or (
			mode == DisplayServer.WINDOW_MODE_WINDOWED
			and _window_covers_current_screen()
			and not _window_matches_managed_windowed_geometry()
		)
	):
		_promote_windows_window_to_fullscreen()


func _normalize_active_windows_fullscreen(mode: int) -> void:
	# Windows or an external fullscreen helper may change the native window mode
	# without passing through the settings page. Keep the shipped desktop canvas
	# and settings state in sync so every scene selects its 1920x1080 layout.
	_set_logical_canvas_size(DEFAULT_WINDOWED_SIZE)
	var mode_id := (
		"exclusive_fullscreen"
		if mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		else "borderless_fullscreen"
	)
	var confirmed_display := _confirmed.get("display", {}) as Dictionary
	if String(confirmed_display.get("windowModeId", "windowed")) == mode_id:
		return
	var adopted_display := confirmed_display.duplicate(true)
	adopted_display["windowModeId"] = mode_id
	_adopt_runtime_display(adopted_display, "EXTERNAL_FULLSCREEN_ADOPTED")


func _promote_windows_window_to_fullscreen() -> void:
	var target_display := (
		_confirmed.get("display", {}) as Dictionary
	).duplicate(true)
	target_display["windowModeId"] = "borderless_fullscreen"
	var applied := _apply_display_draft(target_display)
	if not bool(applied.get("ok", false)):
		return
	_last_observed_window_mode = _display_window_get_mode()
	_external_fullscreen_exit_grace_until_msec = 0
	_adopt_runtime_display(target_display, "WINDOWS_SCREEN_COVERAGE_PROMOTED")


func _window_covers_current_screen() -> bool:
	var screen := _display_window_get_current_screen()
	var usable := _display_screen_get_usable_rect(screen)
	if usable.size.x <= 0 or usable.size.y <= 0:
		return false
	var window_position := _display_window_get_position()
	var window_size := _display_window_get_size()
	var window_end := window_position + window_size
	var usable_end := usable.position + usable.size
	return (
		window_position.x <= usable.position.x + SCREEN_COVERAGE_TOLERANCE_PX
		and window_position.y <= usable.position.y + SCREEN_COVERAGE_TOLERANCE_PX
		and window_end.x >= usable_end.x - SCREEN_COVERAGE_TOLERANCE_PX
		and window_end.y >= usable_end.y - SCREEN_COVERAGE_TOLERANCE_PX
	)


func _window_matches_managed_windowed_geometry() -> bool:
	return (
		_windowed_size.x > 0
		and _windowed_size.y > 0
		and _window_size_matches(_display_window_get_size(), _windowed_size)
	)


func _adopt_runtime_display(display: Dictionary, feedback_code: String) -> void:
	_confirmed["display"] = display.duplicate(true)
	_draft["display"] = display.duplicate(true)
	var saved := _store.save_settings(_confirmed)
	if bool(saved.get("ok", false)):
		_storage = {"status": "ready", "errorCode": "", "message": ""}
	else:
		_storage = {
			"status": "error",
			"errorCode": String(saved.get("errorCode", "SETTINGS_SAVE_FAILED")),
			"message": String(saved.get("message", "设置保存失败。")),
		}
	_feedback = {
		"kind": "notice",
		"code": feedback_code,
		"message": "已同步 Windows 全屏显示状态。",
	}
	_revision += 1
	_emit_view_model()


func _apply_display_draft(display: Dictionary) -> Dictionary:
	var mode_id := String(display.get("windowModeId", "windowed"))
	if _display_available() and not _is_web_runtime():
		if _display_changes_blocked_by_embedding():
			return _failure(
				"DISPLAY_CHANGES_UNSUPPORTED_WHILE_EMBEDDED",
				false,
				"Godot 编辑器的内嵌运行不支持窗口或全屏切换；请改用独立游戏窗口。",
			)
		if not _window_mode_is_offered(mode_id):
			return _failure("DISPLAY_WINDOW_MODE_UNAVAILABLE", false, "当前平台不支持这个窗口模式。")
		match mode_id:
			"windowed":
				_display_window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				var target_size := _size_from_resolution_id(
					String(display.get("windowedResolutionId", "1920x1080"))
				)
				if target_size.x > 0 and target_size.y > 0:
					_windowed_size = target_size
					_request_windowed_geometry(target_size)
			"borderless_fullscreen":
				_pending_windowed_geometry.clear()
				_set_logical_canvas_size(DEFAULT_WINDOWED_SIZE)
				_display_window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			"exclusive_fullscreen":
				_pending_windowed_geometry.clear()
				_set_logical_canvas_size(DEFAULT_WINDOWED_SIZE)
				_display_window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		if _display_backend != null and not _display_target_matches(display):
			_pending_windowed_geometry.clear()
			return _failure(
				"DISPLAY_APPLY_FAILED",
				true,
				"显示后端没有接受请求的窗口模式或分辨率。",
				"error",
			)
	var scale := int(display.get("uiScalePercent", 100))
	if scale != _effective_ui_scale_percent:
		if _ui_scale_consumer == null:
			return _failure(
				UI_SCALE_POLICY_REASON,
				false,
				"界面缩放由响应式布局自动管理。",
			)
		var consumer_result: Variant = _ui_scale_consumer.call("apply_ui_scale", scale)
		if consumer_result is Dictionary and not bool((consumer_result as Dictionary).get("ok", true)):
			return _failure("UI_SCALE_APPLY_FAILED", true, "正式界面没有确认新的缩放。", "error")
		_effective_ui_scale_percent = scale
		ui_scale_changed.emit(scale)
	return _success(true)


func _capture_display_state() -> Dictionary:
	return {
		"mode": _display_window_get_mode() if _display_available() else DisplayServer.WINDOW_MODE_WINDOWED,
		"size": _physical_window_size(),
		"position": _display_window_get_position() if _display_available() else Vector2i.ZERO,
		"uiScalePercent": _effective_ui_scale_percent,
	}


func _restore_display_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	if _display_available() and not _is_web_runtime():
		var mode := int(state.get("mode", DisplayServer.WINDOW_MODE_WINDOWED))
		_display_window_set_mode(mode)
		var size := state.get("size", DEFAULT_WINDOWED_SIZE) as Vector2i
		if mode == DisplayServer.WINDOW_MODE_WINDOWED and size.x > 0 and size.y > 0:
			_request_windowed_geometry(
				size,
				state.get("position", Vector2i.ZERO) as Vector2i,
				true,
			)
		else:
			_pending_windowed_geometry.clear()
	var scale := int(state.get("uiScalePercent", 100))
	if _ui_scale_consumer != null:
		_ui_scale_consumer.call("apply_ui_scale", scale)
	_effective_ui_scale_percent = scale
	ui_scale_changed.emit(scale)


func _data_snapshot(capabilities: Dictionary) -> Dictionary:
	return {
		"source": SOURCE,
		"capabilityMode": CAPABILITY_MODE,
		"formalReady": true,
		"audio": (_draft.get("audio", {}) as Dictionary).duplicate(true),
		"display": _display_for_view(_draft.get("display", {}) as Dictionary),
		"confirmed": {
			"audio": (_confirmed.get("audio", {}) as Dictionary).duplicate(true),
			"display": _display_for_view(_confirmed.get("display", {}) as Dictionary),
		},
		"defaults": {
			"audio": (_defaults.get("audio", {}) as Dictionary).duplicate(true),
			"display": _display_for_view(_defaults.get("display", {}) as Dictionary),
		},
		"dirty": _is_dirty(),
		"dirtySections": _dirty_sections(),
		"uiScaleCapability": {
			"formalReady": true,
			"effectivePercent": 100,
			"supportedPercents": [100],
			"requiredConsumers": REQUIRED_UI_SCALE_CONSUMERS.duplicate(),
			"readyConsumers": REQUIRED_UI_SCALE_CONSUMERS.duplicate(),
			"disabledReason": UI_SCALE_POLICY_REASON,
		},
		"confirmation": _confirmation_snapshot(),
		"storage": _storage.duplicate(true),
		"feedback": _feedback.duplicate(true),
		"options": {
			"resolutions": _resolution_options(capabilities),
			"windowModes": _window_mode_options(capabilities),
			"uiScalePercents": UI_SCALE_PERCENTS.duplicate(),
		},
	}


func _display_for_view(display: Dictionary) -> Dictionary:
	var mode_id := String(display.get("windowModeId", "windowed"))
	var windowed_resolution := String(display.get("windowedResolutionId", "1920x1080"))
	return {
		"resolutionId": windowed_resolution if mode_id == "windowed" else "desktop",
		"windowedResolutionId": windowed_resolution,
		"resolutionControlEnabled": mode_id == "windowed" and _display_changes_available(),
		"windowModeId": mode_id,
		"uiScalePercent": int(display.get("uiScalePercent", 100)),
		"uiScaleFormalReady": true,
		# Transitional read-only compatibility for the visually approved page.
		# Pixel rendering is fixed by project policy and has no executable intent.
		"pixelRenderingEnabled": true,
		"reducedFlashingEnabled": bool(display.get("reducedFlashingEnabled", false)),
	}


func _confirmation_snapshot() -> Dictionary:
	if not bool(_confirmation.get("active", false)):
		return {
			"active": false,
			"deadlineMsec": 0,
			"remainingSeconds": 0,
			"previousDisplay": {},
			"targetDisplay": {},
		}
	var deadline := int(_confirmation.get("deadlineMsec", 0))
	return {
		"active": true,
		"deadlineMsec": deadline,
		"remainingSeconds": maxi(0, ceili(float(deadline - Time.get_ticks_msec()) / 1000.0)),
		"previousDisplay": (_confirmation.get("previousDisplay", {}) as Dictionary).duplicate(true),
		"targetDisplay": (_confirmation.get("targetDisplay", {}) as Dictionary).duplicate(true),
	}


func _actions_snapshot(capabilities: Dictionary, data: Dictionary) -> Dictionary:
	var confirmation_active := bool((data.get("confirmation", {}) as Dictionary).get("active", false))
	var confirmation_pending := (
		confirmation_active
		and not _pending_windowed_geometry.is_empty()
	)
	var editing := not confirmation_active
	var draft_display := _draft.get("display", {}) as Dictionary
	var display_changes := bool(capabilities.get("displayChanges", false))
	var display_reason := _display_change_unavailable_reason()
	return {
		"setAudioValue": _action("audio_display_settings.set_audio_value", editing and bool(capabilities.get("audio", false)), "AUDIO_BUS_UNAVAILABLE"),
		"toggleMute": _action("audio_display_settings.toggle_mute", editing and bool(capabilities.get("mute", false)), "AUDIO_BUS_UNAVAILABLE"),
		"selectResolution": _action("audio_display_settings.select_resolution", editing and display_changes and String(draft_display.get("windowModeId", "")) == "windowed", "RESOLUTION_FOLLOWS_DESKTOP" if display_changes else display_reason),
		"selectWindowMode": _action("audio_display_settings.select_window_mode", editing and display_changes, display_reason),
		"selectUiScale": _action("audio_display_settings.select_ui_scale", false, UI_SCALE_POLICY_REASON),
		"togglePixelRendering": _action("audio_display_settings.toggle_pixel_rendering", false, "PIXEL_RENDERING_PROJECT_POLICY"),
		"toggleReducedFlashing": _action("audio_display_settings.toggle_reduced_flashing", editing, "DISPLAY_CONFIRMATION_REQUIRED"),
		"apply": _action("audio_display_settings.apply", editing and _is_dirty(), "NO_UNAPPLIED_CHANGES"),
		"restoreDefaults": _action("audio_display_settings.restore_defaults", editing and _draft != _defaults, "DEFAULTS_ALREADY_STAGED"),
		"discardChanges": _action("audio_display_settings.discard_changes", editing and _is_dirty(), "NO_UNAPPLIED_CHANGES"),
		"confirmDisplay": _action(
			"audio_display_settings.confirm_display",
			confirmation_active and not confirmation_pending,
			(
				"DISPLAY_APPLY_PENDING"
				if confirmation_pending
				else (
					"DISPLAY_APPLY_FAILED"
					if String(_feedback.get("code", "")) == "DISPLAY_APPLY_FAILED"
					else "DISPLAY_CONFIRMATION_NOT_ACTIVE"
				)
			),
		),
		"revertDisplay": _action("audio_display_settings.revert_display", confirmation_active, "DISPLAY_CONFIRMATION_NOT_ACTIVE"),
		"retry": _action("audio_display_settings.retry", not _last_retryable.is_empty(), "NOTHING_TO_RETRY"),
		"back": _action("audio_display_settings.back", true),
	}


func _capability_snapshot() -> Dictionary:
	var audio_available := true
	for setting_id: String in AUDIO_CHANNELS:
		if _audio_bus_index(setting_id) < 0:
			audio_available = false
			break
	return {
		"audio": audio_available,
		"mute": _audio_bus_index("master") >= 0,
		"display": _display_available(),
		"displayChanges": _display_changes_available(),
		"uiScale": false,
		"reducedFlashing": true,
	}


func _runtime_audio_snapshot() -> Dictionary:
	var audio := AUDIO_DEFAULTS.duplicate(true)
	for setting_id: String in AUDIO_CHANNELS:
		var index := _audio_bus_index(setting_id)
		if index >= 0:
			var key := String((AUDIO_CHANNELS[setting_id] as Dictionary).get("dataKey", ""))
			audio[key] = _db_to_percent(AudioServer.get_bus_volume_db(index))
	var master_index := _audio_bus_index("master")
	if master_index >= 0:
		audio["muted"] = AudioServer.is_bus_mute(master_index)
	return audio


func _runtime_display_snapshot() -> Dictionary:
	return {
		"windowModeId": _window_mode_id() if _display_available() else "windowed",
		"windowedResolutionId": (
			_resolution_id(WEB_CANVAS_SIZE)
			if _is_web_runtime()
			else _resolution_id(_windowed_size)
		),
		"uiScalePercent": 100,
		"reducedFlashingEnabled": bool(ProjectSettings.get_setting(REDUCED_FLASHING_SETTING, false)),
	}


func _apply_audio_snapshot(audio: Dictionary) -> Dictionary:
	var indices := {}
	var before_db := {}
	for setting_id: String in AUDIO_CHANNELS:
		var index := _audio_bus_index(setting_id)
		if index < 0:
			return _failure("AUDIO_BUS_UNAVAILABLE", true, "音频通道尚未就绪。", "error")
		indices[setting_id] = index
		before_db[setting_id] = AudioServer.get_bus_volume_db(index)
	var master_index := int(indices.get("master", -1))
	var before_mute := AudioServer.is_bus_mute(master_index)
	for setting_id: String in AUDIO_CHANNELS:
		var index := int(indices.get(setting_id, -1))
		var key := String((AUDIO_CHANNELS[setting_id] as Dictionary).get("dataKey", ""))
		AudioServer.set_bus_volume_db(index, _percent_to_db(int(audio.get(key, 0))))
	AudioServer.set_bus_mute(master_index, bool(audio.get("muted", false)))
	for setting_id: String in AUDIO_CHANNELS:
		var index := int(indices.get(setting_id, -1))
		var key := String((AUDIO_CHANNELS[setting_id] as Dictionary).get("dataKey", ""))
		if absi(_db_to_percent(AudioServer.get_bus_volume_db(index)) - int(audio.get(key, 0))) <= 1:
			continue
		for restore_id: String in indices:
			AudioServer.set_bus_volume_db(
				int(indices.get(restore_id, -1)),
				float(before_db.get(restore_id, -80.0)),
			)
		AudioServer.set_bus_mute(master_index, before_mute)
		return _failure("AUDIO_APPLY_FAILED", true, "音频设置未完整生效，原值已恢复。", "error")
	if AudioServer.is_bus_mute(master_index) != bool(audio.get("muted", false)):
		for restore_id: String in indices:
			AudioServer.set_bus_volume_db(
				int(indices.get(restore_id, -1)),
				float(before_db.get(restore_id, -80.0)),
			)
		AudioServer.set_bus_mute(master_index, before_mute)
		return _failure("AUDIO_APPLY_FAILED", true, "音频设置未完整生效，原值已恢复。", "error")
	return _success(true)


func _ensure_audio_buses() -> void:
	if AudioServer.get_bus_index("Master") < 0:
		return
	for setting_id: String in AUDIO_CHANNELS:
		if setting_id == "master" or _audio_bus_index(setting_id) >= 0:
			continue
		var aliases := (AUDIO_CHANNELS[setting_id] as Dictionary).get("aliases", []) as Array
		AudioServer.add_bus()
		var index := AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(index, String(aliases[0]))
		AudioServer.set_bus_send(index, "Master")


func _normalize_confirmed_for_capabilities() -> void:
	if _display_changes_blocked_by_embedding():
		return
	var display := _confirmed.get("display", {}) as Dictionary
	if _is_web_runtime():
		display["windowModeId"] = "windowed"
		display["windowedResolutionId"] = _resolution_id(WEB_CANVAS_SIZE)
		return
	if not _window_mode_is_offered(String(display.get("windowModeId", "windowed"))):
		display["windowModeId"] = "windowed"
	if not _resolution_is_offered(String(display.get("windowedResolutionId", ""))):
		display["windowedResolutionId"] = _safe_default_resolution_id()


func _resolution_options(capabilities: Dictionary) -> Array[Dictionary]:
	var available := bool(capabilities.get("displayChanges", false))
	var usable := _usable_screen_size()
	var unavailable_reason := _display_change_unavailable_reason()
	var options: Array[Dictionary] = []
	for size: Vector2i in RESOLUTION_SIZES:
		var fits := available and (usable == Vector2i.ZERO or (size.x <= usable.x and size.y <= usable.y))
		options.append({
			"id": _resolution_id(size),
			"label": "%d × %d" % [size.x, size.y],
			"enabled": fits,
			"disabledReason": "" if fits else "RESOLUTION_EXCEEDS_DISPLAY" if available else unavailable_reason,
		})
	return options


func _window_mode_options(capabilities: Dictionary) -> Array[Dictionary]:
	var display := bool(capabilities.get("displayChanges", false))
	var unavailable_reason := _display_change_unavailable_reason()
	var exclusive := display and _exclusive_fullscreen_available()
	return [
		{"id": "windowed", "label": "窗口", "enabled": display, "disabledReason": "" if display else unavailable_reason},
		{"id": "borderless_fullscreen", "label": "无边框全屏", "enabled": display, "disabledReason": "" if display else unavailable_reason},
		{"id": "exclusive_fullscreen", "label": "全屏", "enabled": exclusive, "disabledReason": "" if exclusive else "EXCLUSIVE_FULLSCREEN_UNAVAILABLE" if display else unavailable_reason},
	]


func _resolution_is_offered(resolution_id: String) -> bool:
	for option: Dictionary in _resolution_options(_capability_snapshot()):
		if String(option.get("id", "")) == resolution_id and bool(option.get("enabled", false)):
			return true
	return false


func _window_mode_is_offered(mode_id: String) -> bool:
	for option: Dictionary in _window_mode_options(_capability_snapshot()):
		if String(option.get("id", "")) == mode_id and bool(option.get("enabled", false)):
			return true
	return false


func _safe_default_resolution_id() -> String:
	if _is_web_runtime():
		return _resolution_id(WEB_CANVAS_SIZE)
	var options := _resolution_options(_capability_snapshot())
	var best := _resolution_id(_windowed_size)
	for option: Dictionary in options:
		if bool(option.get("enabled", false)):
			best = String(option.get("id", best))
			if best == "1920x1080":
				return best
	return best


func _usable_screen_size() -> Vector2i:
	if not _display_available():
		return Vector2i.ZERO
	var screen := _display_window_get_current_screen()
	return _display_screen_get_usable_rect(screen).size


func _exclusive_fullscreen_available() -> bool:
	return _display_server_name().to_lower() in [
		"windows",
		"macos",
		"x11",
		"wayland",
	]


func _display_available() -> bool:
	if _display_server_name().to_lower() in ["headless", "dummy"]:
		return false
	var size := _display_window_get_size()
	return size.x > 0 and size.y > 0


func _display_changes_available() -> bool:
	return (
		_display_available()
		and not _is_web_runtime()
		and not _display_changes_blocked_by_embedding()
	)


func _display_changes_blocked_by_embedding() -> bool:
	return _display_backend == null and Engine.is_embedded_in_editor()


func _display_change_unavailable_reason() -> String:
	if _is_web_runtime():
		return "DISPLAY_CHANGES_MANAGED_BY_BROWSER"
	return (
		"DISPLAY_CHANGES_UNSUPPORTED_WHILE_EMBEDDED"
		if _display_changes_blocked_by_embedding()
		else "DISPLAY_SERVER_UNAVAILABLE"
	)


func _window_mode_id() -> String:
	match _display_window_get_mode():
		DisplayServer.WINDOW_MODE_FULLSCREEN:
			return "borderless_fullscreen"
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			return "exclusive_fullscreen"
	return "windowed"


func _physical_window_size() -> Vector2i:
	if _display_backend != null:
		return _display_window_get_size()
	var window := _root_window()
	if window != null and window.size.x > 0 and window.size.y > 0:
		return window.size
	return _display_window_get_size()


func _request_windowed_geometry(
	size: Vector2i,
	position := Vector2i.ZERO,
	restore_position := false,
) -> void:
	_pending_windowed_geometry = {
		"size": size,
		"position": position,
		"restorePosition": restore_position,
		"deadlineMsec": Time.get_ticks_msec() + WINDOWED_GEOMETRY_RETRY_MSEC,
	}
	_process_pending_windowed_geometry()


func _process_pending_windowed_geometry() -> void:
	if _pending_windowed_geometry.is_empty() or not _display_available():
		return
	if Time.get_ticks_msec() > int(_pending_windowed_geometry.get("deadlineMsec", 0)):
		_pending_windowed_geometry.clear()
		if bool(_confirmation.get("active", false)):
			_fail_active_display_application()
		return
	if _display_window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		return
	var target_size := _pending_windowed_geometry.get("size", Vector2i.ZERO) as Vector2i
	if target_size.x <= 0 or target_size.y <= 0:
		_pending_windowed_geometry.clear()
		return
	_set_physical_window_size(target_size)
	if bool(_pending_windowed_geometry.get("restorePosition", false)):
		_display_window_set_position(
			_pending_windowed_geometry.get("position", Vector2i.ZERO) as Vector2i
		)
	if _window_size_matches(_display_window_get_size(), target_size):
		_pending_windowed_geometry.clear()


func _display_target_matches(display: Dictionary) -> bool:
	if not _display_available():
		return false
	var mode_id := String(display.get("windowModeId", "windowed"))
	var expected_mode := DisplayServer.WINDOW_MODE_WINDOWED
	match mode_id:
		"borderless_fullscreen":
			expected_mode = DisplayServer.WINDOW_MODE_FULLSCREEN
		"exclusive_fullscreen":
			expected_mode = DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		"windowed":
			expected_mode = DisplayServer.WINDOW_MODE_WINDOWED
		_:
			return false
	if _display_window_get_mode() != expected_mode:
		return false
	if mode_id != "windowed":
		return true
	var expected_size := _size_from_resolution_id(
		String(display.get("windowedResolutionId", "")),
	)
	return (
		expected_size.x > 0
		and expected_size.y > 0
		and _window_size_matches(_display_window_get_size(), expected_size)
	)


func _window_size_matches(actual: Vector2i, expected: Vector2i) -> bool:
	return (
		absi(actual.x - expected.x) <= DISPLAY_SIZE_TOLERANCE_PX
		and absi(actual.y - expected.y) <= DISPLAY_SIZE_TOLERANCE_PX
	)


func _fail_active_display_application() -> void:
	if not bool(_confirmation.get("active", false)):
		return
	_pending_windowed_geometry.clear()
	_restore_display_state(_display_before_confirmation)
	_confirmation = {}
	_display_before_confirmation = {}
	_feedback = {
		"kind": "error",
		"code": "DISPLAY_APPLY_FAILED",
		"message": "窗口没有切换到请求的显示状态，已恢复原画面。",
	}
	var failure := _failure(
		"DISPLAY_APPLY_FAILED",
		true,
		String(_feedback.get("message", "")),
		"error",
	)
	_operation = {
		"requestId": _next_request_id(),
		"intent": "audio_display_settings.apply",
		"status": "error",
		"submittedAtMsec": Time.get_ticks_msec(),
		"completedAtMsec": Time.get_ticks_msec(),
	}
	_error = _error_payload(failure)
	_last_retryable = {
		"intent": "audio_display_settings.apply",
		"payload": {},
	}
	_revision += 1
	_emit_view_model()


func _set_physical_window_size(size: Vector2i) -> void:
	if _is_web_runtime():
		return
	if _display_backend == null:
		var window := _root_window()
		if window != null:
			window.content_scale_size = DEFAULT_WINDOWED_SIZE
			window.size = size
	_display_window_set_size(size)


func _set_logical_canvas_size(size: Vector2i) -> void:
	if _is_web_runtime() or _display_backend != null or size.x <= 0 or size.y <= 0:
		return
	var window := _root_window()
	if window != null:
		window.content_scale_size = size


func _enforce_window_constraints() -> void:
	var window := _root_window()
	if window == null:
		return
	if _is_web_runtime():
		window.unresizable = false
		return
	window.unresizable = true
	if (
		_display_backend == null
		and _display_server_name().to_lower() == "windows"
	):
		window.min_size = MINIMUM_WINDOW_SIZE


func _display_server_name() -> String:
	return (
		String(_display_backend.call("get_name"))
		if _display_backend != null
		else DisplayServer.get_name()
	)


func _is_web_runtime() -> bool:
	var name := _display_server_name().to_lower()
	return OS.has_feature("web") or name == "web"


func _display_window_get_mode() -> int:
	return (
		int(_display_backend.call("window_get_mode"))
		if _display_backend != null
		else DisplayServer.window_get_mode()
	)


func _display_window_set_mode(mode: int) -> void:
	if _display_backend != null:
		_display_backend.call("window_set_mode", mode)
	else:
		DisplayServer.window_set_mode(mode)


func _display_window_get_size() -> Vector2i:
	return (
		_display_backend.call("window_get_size") as Vector2i
		if _display_backend != null
		else DisplayServer.window_get_size()
	)


func _display_window_set_size(size: Vector2i) -> void:
	if _display_backend != null:
		_display_backend.call("window_set_size", size)
	else:
		DisplayServer.window_set_size(size)


func _display_window_get_position() -> Vector2i:
	return (
		_display_backend.call("window_get_position") as Vector2i
		if _display_backend != null
		else DisplayServer.window_get_position()
	)


func _display_window_set_position(position: Vector2i) -> void:
	if _display_backend != null:
		_display_backend.call("window_set_position", position)
	else:
		DisplayServer.window_set_position(position)


func _display_window_get_current_screen() -> int:
	return (
		int(_display_backend.call("window_get_current_screen"))
		if _display_backend != null
		else DisplayServer.window_get_current_screen()
	)


func _display_screen_get_usable_rect(screen: int) -> Rect2i:
	return (
		_display_backend.call("screen_get_usable_rect", screen) as Rect2i
		if _display_backend != null
		else DisplayServer.screen_get_usable_rect(screen)
	)


func _root_window() -> Window:
	var main_loop := Engine.get_main_loop()
	if main_loop is SceneTree:
		return (main_loop as SceneTree).root
	return null


func _audio_bus_index(setting_id: String) -> int:
	if not AUDIO_CHANNELS.has(setting_id):
		return -1
	for alias: Variant in (AUDIO_CHANNELS[setting_id] as Dictionary).get("aliases", []):
		var index := AudioServer.get_bus_index(String(alias))
		if index >= 0:
			return index
	return -1


func _is_dirty() -> bool:
	return _draft != _confirmed


func _dirty_sections() -> Array[String]:
	var sections: Array[String] = []
	if _draft.get("audio", {}) != _confirmed.get("audio", {}):
		sections.append("audio")
	if _draft.get("display", {}) != _confirmed.get("display", {}):
		sections.append("display")
	return sections


func _resolution_id(size: Vector2i) -> String:
	for supported: Vector2i in RESOLUTION_SIZES:
		if (
			absi(supported.x - size.x) <= DISPLAY_SIZE_TOLERANCE_PX
			and absi(supported.y - size.y) <= DISPLAY_SIZE_TOLERANCE_PX
		):
			return "%dx%d" % [supported.x, supported.y]
	return "%dx%d" % [size.x, size.y]


func _size_from_resolution_id(resolution_id: String) -> Vector2i:
	var parts := resolution_id.to_lower().split("x")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))


func _percent_to_db(percent: int) -> float:
	return -80.0 if percent <= 0 else linear_to_db(float(percent) / 100.0)


func _db_to_percent(db: float) -> int:
	return 0 if db <= -79.9 else clampi(int(round(db_to_linear(db) * 100.0)), 0, 100)


func _emit_view_model() -> void:
	view_model_changed.emit(SCOPE, get_view_model())


func _next_request_id() -> String:
	_request_sequence += 1
	return AiTownUiViewModel.request_id("audio-display", _request_sequence)


func _action(intent: String, enabled: bool, disabled_reason := "") -> Dictionary:
	return AiTownUiViewModel.make_action(intent, enabled, disabled_reason)


func _idle_operation() -> Dictionary:
	return AiTownUiViewModel.idle_operation()


func _success(changed: bool) -> Dictionary:
	return {"ok": true, "errorCode": "", "retryable": false, "changed": changed, "operationStatus": "success"}


func _failure(code: String, retryable: bool, message: String, status := "rejected") -> Dictionary:
	return {"ok": false, "errorCode": code, "retryable": retryable, "changed": false, "message": message, "operationStatus": status}


func _error_payload(result: Dictionary) -> Dictionary:
	var code := String(result.get("errorCode", "AUDIO_DISPLAY_OPERATION_FAILED"))
	return {
		"kind": "storage" if code.begins_with("SETTINGS_") else "transport" if bool(result.get("retryable", false)) else "rejected",
		"code": code,
		"message": String(result.get("message", "声音或画面设置未生效。")),
		"retryable": bool(result.get("retryable", false)),
		"details": [],
	}


func _dispatch_unknown() -> Dictionary:
	return {"ok": false, "accepted": false, "requestId": "", "errorCode": "UNKNOWN_AUDIO_DISPLAY_INTENT", "retryable": false, "changed": false, "revision": _revision}


func _dispatch_invalid_payload() -> Dictionary:
	return {"ok": false, "accepted": false, "requestId": "", "errorCode": "AUDIO_DISPLAY_PAYLOAD_INVALID", "retryable": false, "changed": false, "revision": _revision}


func _dispatch_revision_stale() -> Dictionary:
	return {"ok": false, "accepted": false, "requestId": "", "errorCode": "AUDIO_DISPLAY_SETTINGS_REVISION_STALE", "retryable": false, "changed": false, "revision": _revision}
