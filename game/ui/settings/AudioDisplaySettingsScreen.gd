class_name AudioDisplaySettingsScreen
extends Control


signal intent_requested(intent: StringName, payload: Dictionary)
signal action_blocked(intent: StringName, reason: String)

const UI_SIGNALS := preload(
	"res://ui/common/AiTownUiSignals.gd"
)
const UiViewModel = preload("res://ui/common/AiTownUiViewModel.gd")
const ImageLayout = preload(
	"res://ui/settings/AudioDisplaySettingsImageLayout.gd"
)

const SCOPE := &"audio_display_settings"
const APPROVED_LAYOUT_SIZE := Vector2(1920, 1080)
const RUNTIME_SHELL_PATH := (
	"res://assets/ui/settings/final/shell/"
	+ "audio_display_settings_runtime_shell_approved_v1.png"
)
const REQUIRED_ACTIONS := [
	"setAudioValue",
	"toggleMute",
	"selectResolution",
	"selectWindowMode",
	"selectUiScale",
	"toggleReducedFlashing",
	"apply",
	"restoreDefaults",
	"discardChanges",
	"confirmDisplay",
	"revertDisplay",
	"retry",
	"back",
]

var _adapter: Node
var _view_model: Dictionary = {}
var _render_data: Dictionary = {}
var _last_confirmed_data: Dictionary = {}
var _current_revision := -1
var _layout_profile := "wide"
var _layout_queued := false
var _image_layout: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_runtime_asset_wrapper()
	if is_instance_valid(_adapter):
		_refresh_from_adapter()
		if _view_model.is_empty():
			_apply_runtime_unavailable_view_model()
	else:
		_apply_runtime_unavailable_view_model()
	resized.connect(_queue_layout)
	get_viewport().size_changed.connect(_queue_layout)
	_queue_layout()
	_render()
	var back := runtime_gate_control("back")
	if back != null:
		back.call_deferred("grab_focus")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if request_back():
			get_viewport().set_input_as_handled()


func request_back() -> bool:
	if not is_instance_valid(_image_layout):
		return false
	_image_layout.call("_on_back_pressed")
	return true


func bind_town_ui_adapter(adapter: Node) -> void:
	if _adapter == adapter:
		return
	_disconnect_adapter()
	_adapter = adapter if is_instance_valid(adapter) else null
	_current_revision = -1
	_view_model.clear()
	_render_data.clear()
	_last_confirmed_data.clear()
	if _adapter != null and _adapter.has_signal("view_model_changed"):
		var callback := Callable(self, "_on_view_model_changed")
		if not _adapter.is_connected("view_model_changed", callback):
			_adapter.connect("view_model_changed", callback)
	if _adapter == null:
		_apply_runtime_unavailable_view_model()
	else:
		_refresh_from_adapter()
		if _view_model.is_empty():
			_apply_runtime_unavailable_view_model()
	_render()


func unbind_town_ui_adapter() -> void:
	bind_town_ui_adapter(null)


func apply_view_model(view_model: Dictionary) -> bool:
	var normalized := _normalize_compatibility_view_model(view_model)
	var issues := _validate_complete_view_model(normalized)
	if not issues.is_empty():
		for issue: String in issues:
			push_error(issue)
		return false
	var incoming_revision := UiViewModel.revision(normalized)
	if _current_revision >= 0 and incoming_revision < _current_revision:
		return false

	var operation_status := UiViewModel.operation_status(normalized)
	var incoming_data := UiViewModel.data(normalized)
	if not incoming_data.is_empty():
		_last_confirmed_data = incoming_data.duplicate(true)
	_render_data = incoming_data.duplicate(true)
	if _render_data.is_empty():
		_render_data = _last_confirmed_data.duplicate(true)

	_view_model = normalized.duplicate(true)
	_current_revision = incoming_revision
	if is_node_ready():
		_render()
		_queue_layout()
	return true


func current_view_model() -> Dictionary:
	return _view_model.duplicate(true)


func current_revision() -> int:
	return _current_revision


func current_layout_profile() -> String:
	return _layout_profile


func runtime_gate_snapshot() -> Dictionary:
	var viewport_size := get_viewport_rect().size
	var safe_insets := _safe_insets()
	var text_slots: Array = []
	var touch_targets: Array = []
	var regions: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group(
		"audio_display_settings_text_slot"
	):
		if node is Control and is_ancestor_of(node) and (node as Control).is_visible_in_tree():
			var control := node as Control
			text_slots.append({
				"id": str(control.get_meta("gate_text_id", "")),
				"rect": _rect_to_array(_visual_rect(control)),
				"fontSize": control.get_theme_font_size("font_size"),
				"text": _control_text(control),
			})
	for node: Node in get_tree().get_nodes_in_group(
		"audio_display_settings_touch_target"
	):
		if node is Control and is_ancestor_of(node) and (node as Control).is_visible_in_tree():
			var control := node as Control
			var disabled := false
			if control is BaseButton:
				disabled = (control as BaseButton).disabled
			elif control is HSlider:
				disabled = not (control as HSlider).editable
			touch_targets.append({
				"id": str(control.get_meta("gate_touch_id", "")),
				"rect": _rect_to_array(_visual_rect(control)),
				"focusMode": control.focus_mode,
				"disabled": disabled,
			})
	for node: Node in get_tree().get_nodes_in_group(
		"audio_display_settings_region"
	):
		if node is Control and is_ancestor_of(node) and (node as Control).is_visible_in_tree():
			var control := node as Control
			regions[str(control.get_meta("gate_region_id", ""))] = (
				_rect_to_array(_visual_rect(control))
			)
	var board_rect := _visual_rect(_image_layout)
	return {
		"layoutProfile": _layout_profile,
		"mainColumns": 2,
		"sourceMode": "town_ui_adapter",
		"source": str(_render_data.get("source", "")),
		"capabilityMode": str(_render_data.get("capabilityMode", "")),
		"formalReady": bool(_render_data.get("formalReady", false)),
		"operationStatus": str(UiViewModel.operation_status(_view_model)),
		"wholePageScale": [_image_layout.scale.x, _image_layout.scale.y],
		"boardRect": _rect_to_array(board_rect),
		"minimumSizes": {
			"approvedLayout": [APPROVED_LAYOUT_SIZE.x, APPROVED_LAYOUT_SIZE.y],
			"renderedLayout": [board_rect.size.x, board_rect.size.y],
		},
		"textSlots": text_slots,
		"touchTargets": touch_targets,
		"regions": regions,
		"scrollRange": 0.0,
		"viewport": [viewport_size.x, viewport_size.y],
		"safeInsets": [safe_insets.x, safe_insets.y, safe_insets.z, safe_insets.w],
		"runtimeShell": RUNTIME_SHELL_PATH,
		"approvedAssetWrapper": true,
		"programmaticFrameCount": 0,
		"controlAssetMode": "approved_shell_registered_states",
		"controlAssetStateCount": 6,
		"dropdownExpanded": bool(_image_layout.call("dropdown_expanded")),
		"unsavedDialogVisible": bool(_image_layout.call("unsaved_dialog_visible")),
		"confirmationDialogVisible": bool(_image_layout.call("confirmation_dialog_visible")),
		"confirmationRemainingSeconds": int(
			(_render_data.get("confirmation", {}) as Dictionary).get("remainingSeconds", 0)
		),
		"pixelRenderingControlVisible": true,
		"uiScaleDisabledReason": str(
			UiViewModel.disabled_reason(UiViewModel.action(_view_model, "selectUiScale"))
		),
		"buttonAnimationFrame": int(_image_layout.call("animation_frame")),
		"revision": _current_revision,
		"audio": (_render_data.get("audio", {}) as Dictionary).duplicate(true),
		"display": (_render_data.get("display", {}) as Dictionary).duplicate(true),
	}


func runtime_gate_control(control_id: String) -> Control:
	for node: Node in get_tree().get_nodes_in_group(
		"audio_display_settings_touch_target"
	):
		if (
			node is Control
			and is_ancestor_of(node)
			and str(node.get_meta("gate_touch_id", "")) == control_id
			and (node as Control).is_visible_in_tree()
		):
			return node as Control
	return null


func _build_runtime_asset_wrapper() -> void:
	_image_layout = ImageLayout.new()
	_image_layout.name = "ApprovedImageAssetLayout"
	_image_layout.position = Vector2.ZERO
	_image_layout.size = APPROVED_LAYOUT_SIZE
	_image_layout.custom_minimum_size = APPROVED_LAYOUT_SIZE
	_image_layout.action_requested.connect(_on_image_action_requested)
	add_child(_image_layout)


func _on_image_action_requested(
	action_key: String,
	payload: Dictionary
) -> void:
	_request_action(action_key, payload)


func _render() -> void:
	if _image_layout == null or not is_instance_valid(_image_layout):
		return
	_image_layout.call(
		"apply_snapshot",
		_view_model,
		_render_data
	)


func _request_action(action_key: String, payload: Dictionary) -> void:
	var action := UiViewModel.action(_view_model, action_key)
	var intent := StringName(action.get("intent", ""))
	var enabled := UiViewModel.action_enabled(action)
	var reason := UiViewModel.disabled_reason(action)
	if intent.is_empty() or not enabled:
		action_blocked.emit(
			intent,
			reason if not reason.is_empty() else "ACTION_DISABLED"
		)
		return
	var envelope := {}
	var static_payload: Variant = action.get("payload", {})
	if static_payload is Dictionary:
		envelope = (static_payload as Dictionary).duplicate(true)
	envelope.merge(payload, true)
	envelope["revision"] = _current_revision
	intent_requested.emit(intent, envelope.duplicate(true))
	if _adapter != null and _adapter.has_method("dispatch"):
		_adapter.call("dispatch", intent, envelope)


func _refresh_from_adapter() -> void:
	if _adapter == null or not _adapter.has_method("get_view_model"):
		return
	var incoming: Variant = _adapter.call("get_view_model", SCOPE)
	if incoming is Dictionary:
		apply_view_model(incoming as Dictionary)


func _disconnect_adapter() -> void:
	UI_SIGNALS.disconnect_view_model(
		_adapter,
		Callable(self, "_on_view_model_changed"),
	)


func _on_view_model_changed(
	scope_value: Variant,
	view_model: Dictionary
) -> void:
	if StringName(scope_value) != SCOPE:
		return
	apply_view_model(view_model)


func _apply_runtime_unavailable_view_model() -> void:
	var actions := {}
	for action_key: String in REQUIRED_ACTIONS:
		var intent_suffix := ""
		match action_key:
			"setAudioValue": intent_suffix = "set_audio_value"
			"toggleMute": intent_suffix = "toggle_mute"
			"selectResolution": intent_suffix = "select_resolution"
			"selectWindowMode": intent_suffix = "select_window_mode"
			"selectUiScale": intent_suffix = "select_ui_scale"
			"toggleReducedFlashing": intent_suffix = "toggle_reduced_flashing"
			"apply": intent_suffix = "apply"
			"restoreDefaults": intent_suffix = "restore_defaults"
			"discardChanges": intent_suffix = "discard_changes"
			"confirmDisplay": intent_suffix = "confirm_display"
			"revertDisplay": intent_suffix = "revert_display"
			"retry": intent_suffix = "retry"
			"back": intent_suffix = "back"
		actions[action_key] = {
			"intent": "audio_display_settings.%s" % intent_suffix,
			"enabled": action_key == "back",
			"disabledReason": (
				""
				if action_key == "back"
				else "AUDIO_DISPLAY_SETTINGS_SERVICE_NOT_BOUND"
			),
		}
	apply_view_model({
		"scope": "audio_display_settings",
		"status": "disabled",
		"revision": maxi(_current_revision + 1, 1),
		"data": {
			"source": "runtime",
			"capabilityMode": "formal",
			"formalReady": false,
			"audio": {
				"masterPercent": 0,
				"musicPercent": 0,
				"ambiencePercent": 0,
				"sfxPercent": 0,
				"uiPercent": 0,
				"muted": false,
			},
			"display": {
				"resolutionId": "",
				"windowModeId": "",
				"uiScalePercent": 100,
				"reducedFlashingEnabled": false,
			},
			"confirmed": {
				"audio": {
					"masterPercent": 0,
					"musicPercent": 0,
					"ambiencePercent": 0,
					"sfxPercent": 0,
					"uiPercent": 0,
					"muted": false,
				},
				"display": {
					"resolutionId": "",
					"windowModeId": "",
					"uiScalePercent": 100,
					"reducedFlashingEnabled": false,
				},
			},
			"defaults": {
				"audio": {
					"masterPercent": 80,
					"musicPercent": 55,
					"ambiencePercent": 45,
					"sfxPercent": 70,
					"uiPercent": 60,
					"muted": false,
				},
				"display": {
					"resolutionId": "1920x1080",
					"windowModeId": "windowed",
					"uiScalePercent": 100,
					"reducedFlashingEnabled": false,
				},
			},
			"dirty": false,
			"dirtySections": [],
			"confirmation": {
				"active": false,
				"deadlineMsec": 0,
				"remainingSeconds": 0,
				"previousDisplay": {},
				"targetDisplay": {},
			},
				"uiScaleCapability": {
					"formalReady": true,
					"effectivePercent": 100,
					"supportedPercents": [100],
					"requiredConsumers": ["responsive_layout"],
					"readyConsumers": ["responsive_layout"],
					"disabledReason": "UI_SCALE_AUTOMATIC_BY_LAYOUT_POLICY",
			},
			"storage": {
				"status": "unavailable",
				"errorCode": "AUDIO_DISPLAY_SETTINGS_SERVICE_NOT_BOUND",
				"message": "声音与画面设置服务尚未绑定。",
			},
			"feedback": {
				"kind": "error",
				"code": "AUDIO_DISPLAY_SETTINGS_SERVICE_NOT_BOUND",
				"message": "声音与画面设置服务尚未绑定。",
			},
			"options": {
				"resolutions": [],
				"windowModes": [],
				"uiScalePercents": [100],
			},
		},
		"actions": actions,
		"operation": {
			"requestId": "",
			"intent": "",
			"status": "disabled",
			"submittedAtMsec": 0,
			"completedAtMsec": 0,
		},
		"error": {
			"code": "AUDIO_DISPLAY_SETTINGS_SERVICE_NOT_BOUND",
			"retryable": false,
			"message": "声音与画面设置服务尚未绑定。",
		},
	})


func _normalize_compatibility_view_model(view_model: Dictionary) -> Dictionary:
	var result := view_model.duplicate(true)
	var data_value: Variant = result.get("data", {})
	if data_value is Dictionary:
		var data := data_value as Dictionary
		var audio := data.get("audio", {}) as Dictionary
		var display := data.get("display", {}) as Dictionary
		if not data.has("confirmed"):
			data["confirmed"] = {
				"audio": audio.duplicate(true),
				"display": display.duplicate(true),
			}
		if not data.has("defaults"):
			data["defaults"] = {
				"audio": audio.duplicate(true),
				"display": display.duplicate(true),
			}
		if not data.has("dirty"):
			data["dirty"] = false
		if not data.has("dirtySections"):
			data["dirtySections"] = []
		if not data.has("confirmation"):
			data["confirmation"] = {
				"active": false,
				"deadlineMsec": 0,
				"remainingSeconds": 0,
				"previousDisplay": {},
				"targetDisplay": {},
			}
		if not data.has("uiScaleCapability"):
			data["uiScaleCapability"] = {
				"formalReady": true,
				"effectivePercent": 100,
				"supportedPercents": [100],
				"requiredConsumers": ["responsive_layout"],
				"readyConsumers": ["responsive_layout"],
				"disabledReason": "UI_SCALE_AUTOMATIC_BY_LAYOUT_POLICY",
			}
		if not data.has("storage"):
			data["storage"] = {
				"status": "ready",
				"errorCode": "",
				"message": "",
			}
		if not data.has("feedback"):
			data["feedback"] = {"kind": "", "code": "", "message": ""}
		display["uiScalePercent"] = 100
		var options := data.get("options", {}) as Dictionary
		options["uiScalePercents"] = [100]

	var actions := result.get("actions", {}) as Dictionary
	var legacy_intents := {
		"apply": "audio_display_settings.apply",
		"restoreDefaults": "audio_display_settings.restore_defaults",
		"discardChanges": "audio_display_settings.discard_changes",
		"confirmDisplay": "audio_display_settings.confirm_display",
		"revertDisplay": "audio_display_settings.revert_display",
	}
	for key: String in legacy_intents:
		if actions.get(key, null) is Dictionary:
			continue
		actions[key] = {
			"intent": str(legacy_intents[key]),
			"enabled": false,
			"disabledReason": "ACTION_NOT_AVAILABLE_IN_CAPTURED_VIEW_MODEL",
		}
	var ui_scale := actions.get("selectUiScale", {}) as Dictionary
	if not ui_scale.is_empty():
		ui_scale["enabled"] = false
		ui_scale["disabledReason"] = "UI_SCALE_AUTOMATIC_BY_LAYOUT_POLICY"
	return result


func _validate_complete_view_model(
	view_model: Dictionary
) -> PackedStringArray:
	var issues := UiViewModel.validate(view_model, "声音与画面设置")
	if UiViewModel.scope(view_model) != SCOPE:
		issues.append(
			"声音与画面设置 scope 不匹配：%s"
			% str(UiViewModel.scope(view_model))
		)
	var data_value: Variant = view_model.get("data", null)
	if not data_value is Dictionary:
		return issues
	var data := data_value as Dictionary
	for key: String in [
		"source",
		"capabilityMode",
		"formalReady",
		"audio",
		"display",
		"confirmed",
		"defaults",
		"dirty",
		"dirtySections",
		"uiScaleCapability",
		"confirmation",
		"storage",
		"feedback",
		"options",
	]:
		if not data.has(key):
			issues.append("声音与画面设置 data 缺少 %s" % key)
	if (
		str(data.get("source", "")) == "placeholder"
		and bool(data.get("formalReady", true))
	):
		issues.append("placeholder 快照不得 formalReady=true")
	var audio_value: Variant = data.get("audio", null)
	if audio_value is Dictionary:
		var audio := audio_value as Dictionary
		for key: String in [
			"masterPercent",
			"musicPercent",
			"ambiencePercent",
			"sfxPercent",
			"uiPercent",
			"muted",
		]:
			if not audio.has(key):
				issues.append("声音数据缺少 %s" % key)
	else:
		issues.append("声音与画面设置 audio 必须是 Dictionary")
	var display_value: Variant = data.get("display", null)
	if display_value is Dictionary:
		var display := display_value as Dictionary
		for key: String in [
			"resolutionId",
			"windowModeId",
			"uiScalePercent",
			"reducedFlashingEnabled",
		]:
			if not display.has(key):
				issues.append("画面数据缺少 %s" % key)
	else:
		issues.append("声音与画面设置 display 必须是 Dictionary")
	var options_value: Variant = data.get("options", null)
	if options_value is Dictionary:
		var options := options_value as Dictionary
		for key: String in [
			"resolutions",
			"windowModes",
			"uiScalePercents",
		]:
			if not options.has(key):
				issues.append("画面选项缺少 %s" % key)
	else:
		issues.append("声音与画面设置 options 必须是 Dictionary")
	for snapshot_key: String in ["confirmed", "defaults"]:
		var snapshot_value: Variant = data.get(snapshot_key, null)
		if not snapshot_value is Dictionary:
			issues.append("声音与画面设置 %s 必须是 Dictionary" % snapshot_key)
			continue
		var snapshot := snapshot_value as Dictionary
		if not snapshot.get("audio", null) is Dictionary:
			issues.append("声音与画面设置 %s.audio 必须是 Dictionary" % snapshot_key)
		if not snapshot.get("display", null) is Dictionary:
			issues.append("声音与画面设置 %s.display 必须是 Dictionary" % snapshot_key)
	var dirty_sections_value: Variant = data.get("dirtySections", null)
	if not dirty_sections_value is Array:
		issues.append("声音与画面设置 dirtySections 必须是 Array")
	var ui_scale_capability := data.get("uiScaleCapability", {}) as Dictionary
	if (
		not bool(ui_scale_capability.get("formalReady", false))
		or str(ui_scale_capability.get("disabledReason", ""))
		!= "UI_SCALE_AUTOMATIC_BY_LAYOUT_POLICY"
	):
		issues.append("界面缩放必须明确标记为正式自动响应式布局策略")
	var confirmation := data.get("confirmation", {}) as Dictionary
	for key: String in ["active", "remainingSeconds"]:
		if not confirmation.has(key):
			issues.append("显示设置确认数据缺少 %s" % key)
	var actions_value: Variant = view_model.get("actions", null)
	if actions_value is Dictionary:
		var actions := actions_value as Dictionary
		for action_key: String in REQUIRED_ACTIONS:
			if not actions.get(action_key, null) is Dictionary:
				issues.append("声音与画面设置 actions 缺少 %s" % action_key)
	return issues


func _queue_layout() -> void:
	if _layout_queued:
		return
	_layout_queued = true
	call_deferred("_apply_layout")


func _apply_layout() -> void:
	_layout_queued = false
	if _image_layout == null or not is_instance_valid(_image_layout):
		return
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var insets := _safe_insets()
	var available := Rect2(
		Vector2(insets.x, insets.y),
		Vector2(
			maxf(1.0, viewport_size.x - insets.x - insets.z),
			maxf(1.0, viewport_size.y - insets.y - insets.w)
		)
	)
	_layout_profile = (
		"wide"
		if available.size.x >= 1600.0
		else "desktop" if available.size.x >= 1100.0
		else "asset_scaled"
	)
	var scale_factor := minf(
		viewport_size.x / APPROVED_LAYOUT_SIZE.x,
		viewport_size.y / APPROVED_LAYOUT_SIZE.y
	)
	_image_layout.scale = Vector2.ONE * scale_factor
	var rendered_size := APPROVED_LAYOUT_SIZE * scale_factor
	_image_layout.position = (
		(viewport_size - rendered_size) * 0.5
	).round()


func _safe_insets() -> Vector4:
	if not OS.is_debug_build():
		return Vector4.ZERO
	var encoded := OS.get_environment("AI_TOWN_SETTINGS_SAFE_INSETS")
	if encoded.is_empty():
		return Vector4.ZERO
	var parts := encoded.split(",")
	if parts.size() != 4:
		return Vector4.ZERO
	return Vector4(
		float(parts[0]),
		float(parts[1]),
		float(parts[2]),
		float(parts[3])
	)


func _visual_rect(control: Control) -> Rect2:
	var transform := control.get_global_transform_with_canvas()
	var corners := [
		transform * Vector2.ZERO,
		transform * Vector2(control.size.x, 0.0),
		transform * control.size,
		transform * Vector2(0.0, control.size.y),
	]
	var minimum := corners[0] as Vector2
	var maximum := corners[0] as Vector2
	for corner_value: Variant in corners:
		var corner := corner_value as Vector2
		minimum.x = minf(minimum.x, corner.x)
		minimum.y = minf(minimum.y, corner.y)
		maximum.x = maxf(maximum.x, corner.x)
		maximum.y = maxf(maximum.y, corner.y)
	return Rect2(minimum.round(), (maximum - minimum).round())


func _rect_to_array(rect: Rect2) -> Array:
	return [
		roundi(rect.position.x),
		roundi(rect.position.y),
		roundi(rect.size.x),
		roundi(rect.size.y),
	]


func _control_text(control: Control) -> String:
	if control is Label:
		return (control as Label).text
	if control is Button:
		return (control as Button).text
	return ""
