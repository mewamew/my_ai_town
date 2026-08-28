class_name NewGameOverwriteScreen
extends Control


signal intent_requested(intent: StringName, payload: Dictionary)
signal action_blocked(intent: StringName, reason: String)


enum LayoutMode {
	WIDE,
	STANDARD,
	COMPACT_LANDSCAPE,
	COMPACT_PORTRAIT,
}


const UI_SIGNALS := preload(
	"res://ui/common/AiTownUiSignals.gd"
)
const UiViewModel := preload("res://ui/common/AiTownUiViewModel.gd")
const PageTheme := preload(
	"res://ui/new_game_overwrite/NewGameOverwriteTheme.gd"
)
const SCOPE := &"session"
const VALID_MODES: Array[String] = [
	"new_game_overwrite",
	"continue_recovery",
	"delete_save",
]
const FRAME_PATH := (
	"res://assets/ui/new_game_overwrite/final/composite/"
	+ "dialog_frame_9patch.png"
)
const EMBLEM_PATHS := {
	"healthy": (
		"res://assets/ui/new_game_overwrite/final/emblems/"
		+ "emblem_healthy_96.png"
	),
	"corrupt": (
		"res://assets/ui/new_game_overwrite/final/emblems/"
		+ "emblem_corrupt_96.png"
	),
	"incompatible": (
		"res://assets/ui/new_game_overwrite/final/emblems/"
		+ "emblem_incompatible_96.png"
	),
	"unavailable": (
		"res://assets/ui/new_game_overwrite/final/emblems/"
		+ "emblem_corrupt_96.png"
	),
}
const REQUIRED_ENVELOPE_KEYS: Array[String] = [
	"scope",
	"status",
	"revision",
	"data",
	"actions",
	"operation",
	"error",
]
const REQUIRED_ACTION_KEYS: Array[String] = [
	"confirmOverwrite",
	"cancel",
	"retryRestore",
	"rediagnose",
]
const REQUIRED_SUMMARY_KEYS: Array[String] = [
	"promptId",
	"saveId",
	"saveRevision",
	"condition",
	"savedAtLabel",
	"townSummary",
	"saveVersion",
	"mapVersion",
	"requiredSaveVersion",
	"requiredMapVersion",
	"recoveryStatus",
	"copy",
]
const REQUIRED_COPY_KEYS: Array[String] = [
	"kicker",
	"title",
	"body",
	"consequence",
	"cancel",
	"retryRestore",
	"confirmOverwrite",
	"rediagnose",
]
const VALID_CONDITIONS: Array[String] = [
	"healthy",
	"corrupt",
	"incompatible",
	"unavailable",
]
const TOUCH_TARGET_HEIGHT := 75.0


var _view_model: Dictionary = {}
var _render_data: Dictionary = {}
var _last_confirmed_data: Dictionary = {}
var _current_revision := -1
var _layout_mode := LayoutMode.WIDE
var _safe_rect := Rect2()
var _layout_queued := false
var _layout_profile_size_override := Vector2.ZERO
var _safe_insets_override := Vector4(-1, -1, -1, -1)
var _adapter: Node
var _contract_failure := false
var _contract_failure_message := ""
var _pending_action_intent := ""
var _dialog: NinePatchRect
var _scroll: ScrollContainer
var _content: VBoxContainer
var _header: GridContainer
var _emblem: TextureRect
var _kicker: Label
var _title: Label
var _body_panel: PanelContainer
var _body: Label
var _consequence: Label
var _summary_panel: PanelContainer
var _summary: Label
var _feedback_panel: PanelContainer
var _feedback: Label
var _actions: GridContainer
var _cancel_button: Button
var _retry_button: Button
var _overwrite_button: Button
var _rediagnose_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	theme = PageTheme.create()
	_build_interface()
	if not _view_model.is_empty():
		_render()
	elif _adapter != null:
		_refresh_from_adapter()
	else:
		_enter_empty_contract_failure("新游戏覆盖确认缺少运行时 ViewModel。")
	resized.connect(_queue_layout)
	get_viewport().size_changed.connect(_queue_layout)
	_queue_layout()


func deactivate_modal_ownership() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_unhandled_input(false)
	hide()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	var cancel_requested := event.is_action_pressed(&"ui_cancel")
	if event is InputEventKey:
		cancel_requested = (
			cancel_requested
			or (event as InputEventKey).keycode == KEY_ESCAPE
		)
	if not cancel_requested:
		return
	_request_action("cancel")
	get_viewport().set_input_as_handled()


func apply_view_model(
	view_model: Dictionary,
	log_validation_errors := true
) -> bool:
	var issues := _validate_page_view_model(view_model)
	if not issues.is_empty():
		if log_validation_errors:
			for issue: String in issues:
				push_error(issue)
		return false
	var incoming_revision := UiViewModel.revision(view_model)
	if _current_revision >= 0 and incoming_revision < _current_revision:
		return false

	var operation_status := UiViewModel.operation_status(view_model)
	var incoming_data := UiViewModel.data(view_model)
	if (
		operation_status in [&"idle", &"success", &"disabled"]
		and not incoming_data.is_empty()
	):
		_last_confirmed_data = incoming_data.duplicate(true)
	if (
		operation_status in [&"loading", &"rejected", &"error"]
		and _can_preserve_confirmed_data(incoming_data)
	):
		_render_data = _last_confirmed_data.duplicate(true)
	else:
		_render_data = incoming_data.duplicate(true)
	if _render_data.is_empty():
		_render_data = incoming_data.duplicate(true)
	_view_model = view_model.duplicate(true)
	_current_revision = incoming_revision
	_contract_failure = false
	_contract_failure_message = ""
	_pending_action_intent = ""
	if is_node_ready():
		_render()
	return true


func _can_preserve_confirmed_data(
	incoming_data: Dictionary
) -> bool:
	if _last_confirmed_data.is_empty() or incoming_data.is_empty():
		return false
	var incoming_summary := (
		incoming_data.get("loadSummary", {}) as Dictionary
	)
	var confirmed_summary := (
		_last_confirmed_data.get("loadSummary", {}) as Dictionary
	)
	var incoming_save_id := str(incoming_summary.get("saveId", ""))
	var confirmed_save_id := str(confirmed_summary.get("saveId", ""))
	return (
		not incoming_save_id.is_empty()
		and incoming_save_id == confirmed_save_id
	)


func bind_town_ui_adapter(adapter: Node) -> void:
	if _adapter == adapter:
		return
	_disconnect_adapter()
	_adapter = adapter
	_reset_view_model_state()
	if _adapter != null and _adapter.has_signal("view_model_changed"):
		var callback := Callable(self, "_on_view_model_changed")
		if not _adapter.is_connected("view_model_changed", callback):
			_adapter.connect("view_model_changed", callback)
	if _adapter == null:
		_enter_empty_contract_failure(
			"正式 TownUiAdapter 未绑定，覆盖确认不可用。"
		)
	else:
		_refresh_from_adapter()


func unbind_town_ui_adapter() -> void:
	bind_town_ui_adapter(null)


func debug_request_action(action_key: String) -> bool:
	return _request_action(action_key)


func _reset_view_model_state() -> void:
	_view_model.clear()
	_render_data.clear()
	_last_confirmed_data.clear()
	_current_revision = -1
	_contract_failure = false
	_contract_failure_message = ""
	_pending_action_intent = ""


func _refresh_from_adapter() -> void:
	if _adapter == null:
		return
	if not _adapter.has_method("get_view_model"):
		_enter_contract_failure(
			"TownUiAdapter 缺少 get_view_model(session)。"
		)
		return
	var incoming: Variant = _adapter.call(
		"get_view_model",
		str(SCOPE)
	)
	if not incoming is Dictionary:
		_enter_contract_failure(
			"TownUiAdapter session 未返回完整 ViewModel。"
		)
		return
	if not apply_view_model(incoming as Dictionary, false):
		_enter_contract_failure(
			"TownUiAdapter session 尚未提供覆盖确认完整页面字段。"
		)


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
	if not apply_view_model(view_model, false):
		_enter_contract_failure(
			"TownUiAdapter session 更新未通过覆盖确认完整页面合同。"
		)


func _enter_contract_failure(message: String) -> void:
	_reset_view_model_state()
	_enter_empty_contract_failure(message)


func _enter_empty_contract_failure(message: String) -> void:
	_reset_view_model_state()
	_contract_failure = true
	_contract_failure_message = message
	if is_node_ready():
		_feedback.text = message
		_feedback.theme_type_variation = &"OverwriteError"
		_cancel_button.disabled = true
		_retry_button.disabled = true
		_overwrite_button.disabled = true
		_rediagnose_button.disabled = true


func current_revision() -> int:
	return _current_revision


func current_view_model() -> Dictionary:
	return _view_model.duplicate(true)


func set_layout_profile_size_override(profile_size: Vector2) -> void:
	_layout_profile_size_override = profile_size.round()
	if is_node_ready():
		_queue_layout()


func set_safe_insets_override(insets: Vector4) -> void:
	_safe_insets_override = insets.round()
	if is_node_ready():
		_queue_layout()


func runtime_gate_snapshot() -> Dictionary:
	var buttons := {}
	for action_key: String in [
		"cancel",
		"retryRestore",
		"confirmOverwrite",
		"rediagnose",
	]:
		var button := _button_for_action(action_key)
		var button_bottom := (
			button.global_position.y + button.size.y
		)
		var content_bottom := (
			_content.global_position.y
			+ maxf(
				_content.size.y,
				_content.get_combined_minimum_size().y
			)
		)
		buttons[action_key] = {
			"visible": button.visible,
			"disabled": button.disabled,
			"rect": _rect_array(
				Rect2(button.global_position, button.size)
			),
			"fontSize": button.get_theme_font_size(&"font_size"),
			"text": button.text,
			"focusMode": button.focus_mode,
			"styleAssets": _button_style_asset_paths(button),
			"styleStateMetrics": _button_style_state_metrics(button),
			"scrollReachable": (
				_scroll.is_ancestor_of(button)
				and button_bottom <= content_bottom + 1.0
			),
		}
	var data := _render_data
	return {
		"layoutMode": LayoutMode.keys()[_layout_mode],
		"safeRect": _rect_array(_safe_rect),
		"dialogRect": _rect_array(
			Rect2(_dialog.global_position, _dialog.size)
		),
		"scrollRect": _rect_array(
			Rect2(_scroll.global_position, _scroll.size)
		),
		"contentMinimumSize": [
			_content.get_combined_minimum_size().x,
			_content.get_combined_minimum_size().y,
		],
		"minimumWidths": {
			"header": _header.get_combined_minimum_size().x,
			"kicker": _kicker.get_combined_minimum_size().x,
			"title": _title.get_combined_minimum_size().x,
			"bodyPanel": _body_panel.get_combined_minimum_size().x,
			"body": _body.get_combined_minimum_size().x,
			"summaryPanel": _summary_panel.get_combined_minimum_size().x,
			"summary": _summary.get_combined_minimum_size().x,
			"feedbackPanel": _feedback_panel.get_combined_minimum_size().x,
			"actions": _actions.get_combined_minimum_size().x,
			"cancel": _cancel_button.get_combined_minimum_size().x,
			"retry": _retry_button.get_combined_minimum_size().x,
			"overwrite": _overwrite_button.get_combined_minimum_size().x,
			"rediagnose": _rediagnose_button.get_combined_minimum_size().x,
		},
		"textRects": {
			"kicker": _rect_array(
				Rect2(_kicker.global_position, _kicker.size)
			),
			"title": _rect_array(
				Rect2(_title.global_position, _title.size)
			),
			"body": _rect_array(
				Rect2(_body.global_position, _body.size)
			),
			"consequence": _rect_array(
				Rect2(_consequence.global_position, _consequence.size)
			),
			"summary": _rect_array(
				Rect2(_summary.global_position, _summary.size)
			),
			"feedback": _rect_array(
				Rect2(_feedback.global_position, _feedback.size)
			),
		},
		"scrollVerticalVisible": (
			_scroll.get_v_scroll_bar().visible
		),
		"actionGridColumns": _actions.columns,
		"focusOwner": (
			str(get_path_to(get_viewport().gui_get_focus_owner()))
			if (
				get_viewport().gui_get_focus_owner() != null
				and is_ancestor_of(
					get_viewport().gui_get_focus_owner()
				)
			)
			else ""
		),
		"feedbackText": _feedback.text,
		"feedbackVariation": str(
			_feedback.theme_type_variation
		),
		"titleFontSize": _title.get_theme_font_size(&"font_size"),
		"bodyFontSize": _body.get_theme_font_size(&"font_size"),
		"actionFontSize": (
			_cancel_button.get_theme_font_size(&"font_size")
		),
		"formalReady": bool(data.get("formalReady", false)),
		"source": str(data.get("source", "")),
		"capabilityMode": str(data.get("capabilityMode", "")),
		"contractFailure": _contract_failure,
		"contractFailureMessage": _contract_failure_message,
		"pendingActionIntent": _pending_action_intent,
		"saveId": str(
			(data.get("loadSummary", {}) as Dictionary).get(
				"saveId",
				""
			)
		),
		"saveRevision": int(
			(data.get("loadSummary", {}) as Dictionary).get(
				"saveRevision",
				0
			)
		),
		"townSummary": str(
			(data.get("loadSummary", {}) as Dictionary).get(
				"townSummary",
				""
			)
		),
		"operationStatus": str(
			(_view_model.get("operation", {}) as Dictionary).get(
				"status",
				""
			)
		),
		"condition": str(
			(data.get("loadSummary", {}) as Dictionary).get(
				"condition",
				""
			)
		),
		"mode": _mode(),
		"emblemPath": str(_emblem.get_meta("asset_path", "")),
		"buttons": buttons,
		"fontShrinkToFit": false,
		"wholePageScale": false,
		"modalInputActive": (
			visible
			and is_inside_tree()
			and mouse_filter == Control.MOUSE_FILTER_STOP
		),
		"modalInputOwner": str(get_path()),
		"darkScrimPresent": get_node_or_null("OverwriteScrim") != null,
	}


func _button_style_asset_paths(button: Button) -> Dictionary:
	var result := {}
	for state: StringName in [&"normal", &"hover", &"focus", &"pressed", &"disabled"]:
		var style := button.get_theme_stylebox(state)
		var texture_style := style as StyleBoxTexture
		result[String(state)] = (
			texture_style.texture.resource_path
			if texture_style != null and texture_style.texture != null
			else ""
		)
	return result


func _button_style_state_metrics(button: Button) -> Dictionary:
	var result := {}
	for state: StringName in [
		&"normal",
		&"hover",
		&"focus",
		&"pressed",
		&"disabled",
	]:
		var style := button.get_theme_stylebox(state) as StyleBoxTexture
		if style == null:
			result[String(state)] = {}
			continue
		result[String(state)] = {
			"contentMargins": [
				style.content_margin_left,
				style.content_margin_top,
				style.content_margin_right,
				style.content_margin_bottom,
			],
			"modulate": style.modulate_color.to_html(true),
		}
	return result


func runtime_ownership_snapshot() -> Array[Dictionary]:
	var condition := str(
		(
			_render_data.get("loadSummary", {}) as Dictionary
		).get("condition", "unavailable")
	)
	var emblem_asset_suffix := (
		condition
		if condition in ["healthy", "corrupt", "incompatible"]
		else "corrupt"
	)
	var entries: Array[Dictionary] = [
		{
			"edgeId": "dialog_outer_border",
			"layer": "page_shell",
			"owner": str(get_path_to(_dialog)),
			"controlType": "NinePatchRect",
			"assetId": "ui.new-game-overwrite.dialog-shell.rev0",
			"assetPath": FRAME_PATH,
			"componentType": "composite_shell",
			"registeredAsStyleBoxTexture": false,
			"duplicatesParentBoundary": false,
		},
		_section_ownership(
			"warning_section_border",
			_body_panel
		),
		_section_ownership(
			"summary_section_border",
			_summary_panel
		),
		_section_ownership(
			"feedback_section_border",
			_feedback_panel
		),
		{
			"edgeId": "condition_emblem_frame",
			"layer": "content_slot",
			"owner": str(get_path_to(_emblem)),
			"controlType": "TextureRect",
			"assetId": (
				"ui.new-game-overwrite.emblem.%s.rev0"
				% emblem_asset_suffix
			),
			"assetPath": str(
				_emblem.get_meta("asset_path", "")
			),
			"componentType": "content_emblem",
			"registeredAsStyleBoxTexture": false,
			"duplicatesParentBoundary": false,
		},
		_action_ownership(
			"cancel_action_border",
			"cancel",
			_cancel_button
		),
		_action_ownership(
			"recovery_action_border",
			"recovery",
			_retry_button
		),
		_action_ownership(
			"overwrite_action_border",
			"overwrite",
			_overwrite_button
		),
		_action_ownership(
			"rediagnose_action_border",
			"rediagnose",
			_rediagnose_button
		),
	]
	return entries


func _section_ownership(
	edge_id: String,
	owner: PanelContainer
) -> Dictionary:
	return {
		"edgeId": edge_id,
		"layer": "section_frame",
		"owner": str(get_path_to(owner)),
		"controlType": "PanelContainer",
		"assetId": "ui.new-game-overwrite.paper-slot.base.rev0",
		"assetPath": (
			"res://assets/ui/new_game_overwrite/final/base/"
			+ "paper_slot_9patch.png"
		),
		"componentType": "basic_nine_patch_stylebox",
		"registeredAsStyleBoxTexture": true,
		"duplicatesParentBoundary": false,
	}


func _action_ownership(
	edge_id: String,
	asset_suffix: String,
	owner: Button
) -> Dictionary:
	return {
		"edgeId": edge_id,
		"layer": "operation_control",
		"owner": str(get_path_to(owner)),
		"controlType": "Button",
		"assetId": (
			"ui.new-game-overwrite.action.%s.rev0"
			% asset_suffix
		),
		"assetPath": (
			"res://assets/ui/new_game_overwrite/final/actions/"
			+ "button_%s.png" % asset_suffix
		),
		"componentType": "button_stylebox",
		"registeredAsStyleBoxTexture": true,
		"focusIndicatorOwner": str(get_path_to(owner)),
		"duplicatesParentBoundary": false,
	}


func _validate_page_view_model(
	view_model: Dictionary
) -> PackedStringArray:
	var issues := UiViewModel.validate(
		view_model,
		"NewGameOverwriteScreen"
	)
	for key: String in REQUIRED_ENVELOPE_KEYS:
		if not view_model.has(key):
			issues.append(
				"NewGameOverwriteScreen 缺少完整 envelope.%s" % key
			)
	if UiViewModel.scope(view_model) != SCOPE:
		issues.append(
			"NewGameOverwriteScreen scope 必须为 session"
		)
	var data_value: Variant = view_model.get("data", {})
	if data_value is Dictionary:
		var data := data_value as Dictionary
		if not VALID_MODES.has(str(data.get("mode", ""))):
			issues.append(
				"NewGameOverwriteScreen data.mode 必须为 %s"
				% ", ".join(VALID_MODES)
			)
		for key: String in [
			"loadSummary",
			"source",
			"capabilityMode",
			"formalReady",
		]:
			if not data.has(key):
				issues.append(
					"NewGameOverwriteScreen data 缺少 %s" % key
				)
		if typeof(data.get("loadSummary", {})) != TYPE_DICTIONARY:
			issues.append(
				"NewGameOverwriteScreen data.loadSummary 必须为 Dictionary"
			)
		if typeof(data.get("formalReady", false)) != TYPE_BOOL:
			issues.append(
				"NewGameOverwriteScreen data.formalReady 必须为 bool"
			)
		for string_key: String in ["source", "capabilityMode"]:
			if typeof(data.get(string_key, "")) != TYPE_STRING:
				issues.append(
					"NewGameOverwriteScreen data.%s 必须为 String"
					% string_key
				)
		var summary_value: Variant = data.get("loadSummary", {})
		if summary_value is Dictionary:
			_validate_load_summary(
				summary_value as Dictionary,
				issues
			)
		if (
			(
				str(data.get("source", "")) == "placeholder"
				or str(data.get("capabilityMode", "")) == "placeholder"
			)
			and bool(data.get("formalReady", true))
		):
			issues.append(
				"NewGameOverwriteScreen placeholder 必须 formalReady=false"
			)
	var actions_value: Variant = view_model.get("actions", {})
	if actions_value is Dictionary:
		var actions := actions_value as Dictionary
		for action_key: String in REQUIRED_ACTION_KEYS:
			var action_value: Variant = actions.get(action_key)
			if not action_value is Dictionary:
				issues.append(
					"NewGameOverwriteScreen actions.%s 缺失"
					% action_key
				)
				continue
			var action := action_value as Dictionary
			for action_field: String in [
				"intent",
				"enabled",
				"disabledReason",
			]:
				if not action.has(action_field):
					issues.append(
						"NewGameOverwriteScreen actions.%s 缺少 %s"
						% [action_key, action_field]
					)
			var intent_value: Variant = action.get("intent", "")
			if (
				typeof(intent_value) not in [
					TYPE_STRING,
					TYPE_STRING_NAME,
				]
				or str(intent_value).is_empty()
			):
				issues.append(
					"NewGameOverwriteScreen actions.%s.intent 必须为非空字符串"
					% action_key
				)
			if typeof(action.get("enabled", false)) != TYPE_BOOL:
				issues.append(
					"NewGameOverwriteScreen actions.%s.enabled 必须为 bool"
					% action_key
				)
			if (
				typeof(action.get("disabledReason", ""))
				!= TYPE_STRING
			):
				issues.append(
					"NewGameOverwriteScreen actions.%s.disabledReason 必须为 String"
					% action_key
				)
		if data_value is Dictionary:
			_validate_mode_contract(
				data_value as Dictionary,
				actions,
				issues
			)
	return issues


func _validate_mode_contract(
	data: Dictionary,
	actions: Dictionary,
	issues: PackedStringArray
) -> void:
	if str(data.get("mode", "")) != "continue_recovery":
		return
	var summary := data.get("loadSummary", {}) as Dictionary
	if str(summary.get("condition", "")) != "corrupt":
		issues.append(
			"NewGameOverwriteScreen continue_recovery 只接受 corrupt 存档条件"
		)
	if (
		str(summary.get("recoveryStatus", ""))
		!= "progress_rollback_confirmation"
	):
		issues.append(
			"NewGameOverwriteScreen continue_recovery 必须确认真实进度回退"
		)
	var damage_value: Variant = summary.get("damageDetails", {})
	if not damage_value is Dictionary:
		issues.append(
			"NewGameOverwriteScreen continue_recovery 缺少 damageDetails"
		)
	else:
		var damage := damage_value as Dictionary
		if typeof(damage.get("progressRollback")) != TYPE_BOOL:
			issues.append(
				"NewGameOverwriteScreen continue_recovery progressRollback 必须为 bool"
			)
		if (
			typeof(damage.get("damagedSaveRevision"))
			not in [TYPE_INT, TYPE_FLOAT]
			or typeof(damage.get("fallbackSaveRevision"))
			not in [TYPE_INT, TYPE_FLOAT]
		):
			issues.append(
				"NewGameOverwriteScreen continue_recovery revision 合同无效"
			)
		elif (
			int(damage.get("fallbackSaveRevision", -1))
			!= int(summary.get("saveRevision", -2))
		):
			issues.append(
				"NewGameOverwriteScreen continue_recovery 回退 revision 与摘要不一致"
			)
	var rediagnose := actions.get("rediagnose", {}) as Dictionary
	if (
		not bool(rediagnose.get("enabled", false))
		or String(rediagnose.get("intent", ""))
		!= "session.rediagnose_recovery"
	):
		issues.append(
			"NewGameOverwriteScreen continue_recovery 必须提供重新诊断操作"
		)


func _validate_load_summary(
	summary: Dictionary,
	issues: PackedStringArray
) -> void:
	for key: String in REQUIRED_SUMMARY_KEYS:
		if not summary.has(key):
			issues.append(
				"NewGameOverwriteScreen data.loadSummary 缺少 %s"
				% key
			)
	var condition := str(summary.get("condition", ""))
	if not VALID_CONDITIONS.has(condition):
		issues.append(
			"NewGameOverwriteScreen data.loadSummary.condition 无效：%s"
			% condition
		)
	if (
		typeof(summary.get("saveRevision", 0)) != TYPE_INT
		and typeof(summary.get("saveRevision", 0)) != TYPE_FLOAT
	):
		issues.append(
			"NewGameOverwriteScreen data.loadSummary.saveRevision 必须为数字"
		)
	for string_key: String in [
		"promptId",
		"saveId",
		"savedAtLabel",
		"townSummary",
		"saveVersion",
		"mapVersion",
		"requiredSaveVersion",
		"requiredMapVersion",
		"recoveryStatus",
	]:
		if typeof(summary.get(string_key, "")) != TYPE_STRING:
			issues.append(
				"NewGameOverwriteScreen data.loadSummary.%s 必须为 String"
				% string_key
			)
	var copy_value: Variant = summary.get("copy", {})
	if not copy_value is Dictionary:
		issues.append(
			"NewGameOverwriteScreen data.loadSummary.copy 必须为 Dictionary"
		)
		return
	var copy := copy_value as Dictionary
	for copy_key: String in REQUIRED_COPY_KEYS:
		if not copy.has(copy_key):
			issues.append(
				"NewGameOverwriteScreen data.loadSummary.copy 缺少 %s"
				% copy_key
			)
		elif typeof(copy.get(copy_key, "")) != TYPE_STRING:
			issues.append(
				"NewGameOverwriteScreen data.loadSummary.copy.%s 必须为 String"
				% copy_key
			)


func _build_interface() -> void:
	_dialog = NinePatchRect.new()
	_dialog.name = "OverwriteDialog"
	_dialog.texture = ResourceLoader.load(
		FRAME_PATH,
		"Texture2D"
	) as Texture2D
	_dialog.patch_margin_left = 66
	_dialog.patch_margin_top = 92
	_dialog.patch_margin_right = 66
	_dialog.patch_margin_bottom = 47
	_dialog.axis_stretch_horizontal = (
		NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	)
	_dialog.axis_stretch_vertical = (
		NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	)
	_dialog.draw_center = true
	_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	_dialog.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_dialog)

	_scroll = ScrollContainer.new()
	_scroll.name = "OverwriteContentScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_dialog.add_child(_scroll)

	_content = VBoxContainer.new()
	_content.name = "OverwriteContent"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override(&"separation", 18)
	_scroll.add_child(_content)

	_header = GridContainer.new()
	_header.name = "OverwriteHeader"
	_header.columns = 2
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_theme_constant_override(&"h_separation", 22)
	_header.add_theme_constant_override(&"v_separation", 8)
	_content.add_child(_header)

	_emblem = TextureRect.new()
	_emblem.name = "ConditionEmblem"
	_emblem.custom_minimum_size = Vector2(96, 96)
	_emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_emblem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_emblem.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(_emblem)

	var heading := VBoxContainer.new()
	heading.name = "HeadingCopy"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override(&"separation", 2)
	_header.add_child(heading)

	_kicker = _make_label(
		"Kicker",
		&"OverwriteKicker",
		1
	)
	heading.add_child(_kicker)
	_title = _make_label(
		"Title",
		&"OverwriteTitle",
		2
	)
	heading.add_child(_title)

	_body_panel = _make_paper_panel("WarningPanel")
	_content.add_child(_body_panel)
	var body_stack := VBoxContainer.new()
	body_stack.add_theme_constant_override(&"separation", 6)
	_body_panel.add_child(body_stack)
	_body = _make_label("WarningBody", &"OverwriteBody", 4)
	body_stack.add_child(_body)
	_consequence = _make_label(
		"Consequence",
		&"OverwriteMuted",
		4
	)
	body_stack.add_child(_consequence)

	_summary_panel = _make_paper_panel("SaveSummaryPanel")
	_content.add_child(_summary_panel)
	_summary = _make_label(
		"SaveSummary",
		&"OverwriteBody",
		8
	)
	_summary_panel.add_child(_summary)

	_feedback_panel = _make_paper_panel("OperationFeedbackPanel")
	_content.add_child(_feedback_panel)
	_feedback = _make_label(
		"OperationFeedback",
		&"OverwriteFeedback",
		3
	)
	_feedback_panel.add_child(_feedback)

	_actions = GridContainer.new()
	_actions.name = "OverwriteActions"
	_actions.columns = 3
	_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_actions.add_theme_constant_override(&"h_separation", 24)
	_actions.add_theme_constant_override(&"v_separation", 14)
	_content.add_child(_actions)

	_cancel_button = _make_action_button(
		"CancelButton",
		&"OverwriteCancel",
		"cancel"
	)
	_retry_button = _make_action_button(
		"RetryRestoreButton",
		&"OverwriteRecovery",
		"retryRestore"
	)
	_overwrite_button = _make_action_button(
		"ConfirmOverwriteButton",
		&"OverwriteDestructive",
		"confirmOverwrite"
	)
	_rediagnose_button = _make_action_button(
		"RediagnoseButton",
		&"OverwriteRecovery",
		"rediagnose"
	)
	_actions.add_child(_cancel_button)
	_actions.add_child(_retry_button)
	_actions.add_child(_overwrite_button)
	_actions.add_child(_rediagnose_button)


func _make_label(
	node_name: String,
	variation: StringName,
	max_lines: int
) -> Label:
	var label := Label.new()
	label.name = node_name
	label.theme_type_variation = variation
	# 中文长句不能依赖西文单词边界；允许按字形换行，保持固定字号。
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	label.max_lines_visible = max_lines
	label.clip_text = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return label


func _make_paper_panel(node_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.theme_type_variation = &"OverwritePaperSlot"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


func _make_action_button(
	node_name: String,
	variation: StringName,
	action_key: String
) -> Button:
	var button := Button.new()
	button.name = node_name
	button.theme_type_variation = variation
	button.custom_minimum_size = Vector2(180, TOUCH_TARGET_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.pressed.connect(_request_action.bind(action_key))
	return button


func _render() -> void:
	if _view_model.is_empty() or _render_data.is_empty():
		return
	var summary := (
		_render_data.get("loadSummary", {}) as Dictionary
	)
	var copy := summary.get("copy", {}) as Dictionary
	var condition := str(summary.get("condition", "healthy"))

	_kicker.text = str(copy.get("kicker", ""))
	_title.text = str(copy.get("title", ""))
	_body.text = str(copy.get("body", ""))
	_consequence.text = str(copy.get("consequence", ""))
	_summary.text = _summary_copy(summary)
	_apply_emblem(condition)
	_apply_operation_feedback(condition)
	_apply_actions(summary, condition)
	_queue_layout()


func _apply_emblem(condition: String) -> void:
	var path := str(
		EMBLEM_PATHS.get(
			condition,
			EMBLEM_PATHS["unavailable"]
		)
	)
	_emblem.texture = ResourceLoader.load(path, "Texture2D") as Texture2D
	_emblem.set_meta("asset_path", path)
	match condition:
		"corrupt":
			_emblem.tooltip_text = "存档损坏：纸页断裂徽记"
		"incompatible":
			_emblem.tooltip_text = "版本不兼容：双页迁移徽记"
		"healthy":
			_emblem.tooltip_text = "已有可用存档：完整小镇徽记"
		_:
			_emblem.tooltip_text = "存档能力当前不可用"


func _summary_copy(summary: Dictionary) -> String:
	if _mode() == "continue_recovery":
		return "\n".join([
			"恢复时间　%s" % str(summary.get("savedAtLabel", "—")),
			"恢复进度　%s" % str(summary.get("townSummary", "—")),
		])
	if _mode() == "delete_save":
		return "\n".join([
			"存档时间　%s" % str(summary.get("savedAtLabel", "—")),
			"小镇近况　%s" % str(summary.get("townSummary", "—")),
		])
	var save_version := str(summary.get("saveVersion", "—"))
	var required_save := str(
		summary.get("requiredSaveVersion", "—")
	)
	var map_version := str(summary.get("mapVersion", "—"))
	var required_map := str(
		summary.get("requiredMapVersion", "—")
	)
	var save_line := "存档版本　%s" % save_version
	var map_line := "地图版本　%s" % map_version
	if save_version != required_save:
		save_line += "　→　需要 %s" % required_save
	if map_version != required_map:
		map_line += "　→　需要 %s" % required_map
	return "\n".join([
		"上次保存　%s" % str(summary.get("savedAtLabel", "—")),
		"小镇近况　%s" % str(summary.get("townSummary", "—")),
		save_line,
		map_line,
		"保留内容　模型设置和游戏设置",
	])


func _apply_operation_feedback(condition: String) -> void:
	var operation_status := UiViewModel.operation_status(_view_model)
	var error_message := UiViewModel.error_message(_view_model)
	var continue_recovery := _mode() == "continue_recovery"
	var delete_save := _mode() == "delete_save"
	match operation_status:
		&"loading":
			var operation := UiViewModel.operation(_view_model)
			var intent := str(operation.get("intent", ""))
			_feedback.text = (
				"正在使用最近完整存档，请稍候……"
				if continue_recovery
				else "正在安全删除小镇存档，请稍候……"
				if delete_save
				else "正在重试恢复，请稍候……"
				if intent.contains("restore")
				else "正在准备新的小镇，请稍候……"
			)
			_feedback.theme_type_variation = &"OverwriteFeedback"
		&"success":
			_feedback.text = (
				"恢复确认已完成，等待进入小镇。"
				if continue_recovery
				else "小镇存档已从游戏中删除。"
				if delete_save
				else "操作已完成，等待启动流程确认。"
			)
			_feedback.theme_type_variation = &"OverwriteSuccess"
		&"rejected":
			_feedback.text = (
				error_message
				if not error_message.is_empty()
				else (
					"存档情况已经变化，本次恢复没有执行。请重新确认。"
					if continue_recovery
					else "存档情况已经变化，本次删除没有执行。请重新确认。"
					if delete_save
					else "存档已经变化，本次覆盖没有执行。请重新确认。"
				)
			)
			_feedback.theme_type_variation = &"OverwriteError"
		&"error":
			_feedback.text = (
				error_message
				if not error_message.is_empty()
				else "操作暂时失败；原存档仍然保留。"
			)
			_feedback.theme_type_variation = &"OverwriteError"
		&"disabled":
			_feedback.text = _disabled_feedback()
			_feedback.theme_type_variation = &"OverwriteDisabled"
		_:
			if _mode() == "continue_recovery":
				_feedback.text = "可重新检查存档，也可确认执行当前修复计划。"
			elif delete_save:
				_feedback.text = "删除前会先安全归档；取消不会改变存档。"
			else:
				match condition:
					"corrupt":
						_feedback.text = "恢复入口可用，也可以明确选择覆盖。"
					"incompatible":
						_feedback.text = "需要迁移检查；可以先重试恢复。"
					"unavailable":
						_feedback.text = "正式存档接口尚未接通。"
					_:
						_feedback.text = "已有存档 · 等待选择"
			_feedback.theme_type_variation = &"OverwriteFeedback"


func _disabled_feedback() -> String:
	var relevant_actions: Array[String] = ["retryRestore"]
	if _mode() != "continue_recovery":
		relevant_actions.push_front("confirmOverwrite")
	for action_key: String in relevant_actions:
		var reason := UiViewModel.disabled_reason(
			UiViewModel.action(_view_model, action_key)
		)
		if not reason.is_empty():
			return "当前不可执行：%s" % reason
	return "正式存档接口尚未接通；取消仍可使用。"


func _apply_actions(
	summary: Dictionary,
	condition: String
) -> void:
	var copy := summary.get("copy", {}) as Dictionary
	_configure_action_button(
		_cancel_button,
		"cancel",
		str(copy.get("cancel", "取消"))
	)
	_configure_action_button(
		_retry_button,
		"retryRestore",
		str(copy.get("retryRestore", "重试恢复"))
	)
	_configure_action_button(
		_overwrite_button,
		"confirmOverwrite",
		str(copy.get("confirmOverwrite", "覆盖并开始"))
	)
	_configure_action_button(
		_rediagnose_button,
		"rediagnose",
		str(copy.get("rediagnose", "重新诊断"))
	)
	_retry_button.visible = _action_is_exposed("retryRestore", condition)
	_overwrite_button.visible = _action_is_exposed(
		"confirmOverwrite",
		condition
	)
	_rediagnose_button.visible = _action_is_exposed("rediagnose", condition)
	_update_action_grid()
	_update_focus_chain()
	_remeasure_text_slots()


func _mode() -> String:
	return str(_render_data.get("mode", "new_game_overwrite"))


func _remeasure_text_slots() -> void:
	var content_width := maxf(
		1.0,
		_content.custom_minimum_size.x
	)
	var heading_width := (
		content_width
		if _layout_mode == LayoutMode.COMPACT_PORTRAIT
		else content_width - _emblem.custom_minimum_size.x - 22.0
	)
	var paper_width := maxf(1.0, content_width - 36.0)
	_measure_label_height(_kicker, heading_width, 35.0)
	_measure_label_height(_title, heading_width, 70.0)
	_measure_label_height(_body, paper_width, 35.0)
	_measure_label_height(_consequence, paper_width, 35.0)
	_measure_label_height(
		_summary,
		paper_width,
		80.0 if _mode() in ["continue_recovery", "delete_save"] else 175.0
	)
	_measure_label_height(_feedback, paper_width, 35.0)


func _measure_label_height(
	label: Label,
	available_width: float,
	minimum_height: float
) -> void:
	var font := label.get_theme_font(&"font")
	var font_size := label.get_theme_font_size(&"font_size")
	if font == null or label.text.is_empty():
		label.custom_minimum_size.y = minimum_height
		return
	var measured := font.get_multiline_string_size(
		label.text,
		HORIZONTAL_ALIGNMENT_LEFT,
		maxf(1.0, floorf(available_width)),
		font_size,
		label.max_lines_visible
	)
	var line_height := maxf(1.0, font.get_height(font_size))
	var line_count := maxi(1, ceili(measured.y / line_height))
	var line_spacing := label.get_theme_constant(&"line_spacing")
	var measured_height := (
		measured.y
		+ float(maxi(0, line_count - 1)) * line_spacing
	)
	label.custom_minimum_size.y = ceilf(
		maxf(minimum_height, measured_height)
	)


func _configure_action_button(
	button: Button,
	action_key: String,
	copy: String
) -> void:
	var action := UiViewModel.action(_view_model, action_key)
	button.text = _visible_action_copy(action_key, copy)
	button.disabled = not UiViewModel.action_enabled(action)
	var disabled_reason := UiViewModel.disabled_reason(action)
	button.tooltip_text = (
		"完整操作：%s" % copy
		if not button.disabled
		else "完整操作：%s\n不可用：%s" % [copy, disabled_reason]
	)
	button.set_meta("full_copy", copy)
	button.set_meta("intent", str(action.get("intent", "")))


func _visible_action_copy(action_key: String, full_copy: String) -> String:
	if (
		_mode() == "continue_recovery"
		and action_key in ["retryRestore", "rediagnose"]
	):
		return full_copy
	var maximum_characters := 7
	if full_copy.length() <= maximum_characters:
		return full_copy
	match action_key:
		"cancel":
			return "取消返回"
		"retryRestore":
			return "重试恢复"
		_:
			return "覆盖并开始"


func _update_action_grid() -> void:
	var visible_actions := 0
	for button: Button in [
		_cancel_button,
		_retry_button,
		_overwrite_button,
		_rediagnose_button,
	]:
		if button.visible:
			visible_actions += 1
	_actions.columns = (
		1
		if _layout_mode in [
			LayoutMode.COMPACT_LANDSCAPE,
			LayoutMode.COMPACT_PORTRAIT,
		]
		else maxi(1, visible_actions)
	)


func _action_is_exposed(action_key: String, condition := "") -> bool:
	var resolved_condition := condition
	if resolved_condition.is_empty():
		resolved_condition = str(
			(
				_render_data.get("loadSummary", {}) as Dictionary
			).get("condition", "unavailable")
		)
	match action_key:
		"cancel":
			return true
		"retryRestore":
			return (
				_mode() != "delete_save"
				and (
					_mode() == "continue_recovery"
				or resolved_condition in [
					"corrupt",
					"incompatible",
					"unavailable",
				]
				)
			)
		"confirmOverwrite":
			return _mode() in ["new_game_overwrite", "delete_save"]
		"rediagnose":
			return _mode() == "continue_recovery"
		_:
			return false


func _update_focus_chain() -> void:
	var focus_chain: Array[Button] = []
	for button: Button in [
		_cancel_button,
		_retry_button,
		_overwrite_button,
		_rediagnose_button,
	]:
		if button.visible and not button.disabled:
			focus_chain.append(button)
	for index: int in focus_chain.size():
		var current := focus_chain[index]
		var previous := focus_chain[
			(index - 1 + focus_chain.size()) % focus_chain.size()
		]
		var next := focus_chain[
			(index + 1) % focus_chain.size()
		]
		current.focus_neighbor_left = current.get_path_to(previous)
		current.focus_neighbor_right = current.get_path_to(next)
		current.focus_neighbor_top = current.get_path_to(previous)
		current.focus_neighbor_bottom = current.get_path_to(next)
	var focus_owner := get_viewport().gui_get_focus_owner()
	var focus_is_valid := (
		focus_owner != null
		and focus_chain.has(focus_owner)
	)
	if focus_is_valid:
		return
	if focus_owner is Control and is_ancestor_of(focus_owner):
		(focus_owner as Control).release_focus()
	if focus_chain.is_empty():
		return
	var preferred := (
		_cancel_button
		if focus_chain.has(_cancel_button)
		else focus_chain[0]
	)
	preferred.grab_focus.call_deferred()


func _request_action(action_key: String) -> bool:
	if _view_model.is_empty():
		action_blocked.emit(&"", "VIEW_MODEL_UNAVAILABLE")
		return false
	var action := UiViewModel.action(_view_model, action_key)
	var intent := StringName(action.get("intent", ""))
	if intent.is_empty():
		action_blocked.emit(intent, "MISSING_INTENT")
		return false
	if not _action_is_exposed(action_key):
		action_blocked.emit(intent, "ACTION_NOT_AVAILABLE_IN_MODE")
		return false
	if not UiViewModel.action_enabled(action):
		action_blocked.emit(
			intent,
			(
				UiViewModel.disabled_reason(action)
				if not UiViewModel.disabled_reason(action).is_empty()
				else "ACTION_DISABLED"
			)
		)
		return false
	if not _pending_action_intent.is_empty():
		action_blocked.emit(intent, "DUPLICATE_REQUEST_PENDING")
		return false
	var summary := (
		_render_data.get("loadSummary", {}) as Dictionary
	)
	_pending_action_intent = str(intent)
	intent_requested.emit(intent, {
		"scope": str(SCOPE),
		"revision": _current_revision,
		"promptId": str(summary.get("promptId", "")),
		"saveId": str(summary.get("saveId", "")),
		"saveRevision": int(summary.get("saveRevision", 0)),
		"formalReady": bool(
			_render_data.get("formalReady", false)
		),
	})
	return true


func _button_for_action(action_key: String) -> Button:
	match action_key:
		"cancel":
			return _cancel_button
		"retryRestore":
			return _retry_button
		"rediagnose":
			return _rediagnose_button
		_:
			return _overwrite_button


func _queue_layout() -> void:
	if _layout_queued:
		return
	_layout_queued = true
	_apply_responsive_layout.call_deferred()


func _apply_responsive_layout() -> void:
	_layout_queued = false
	if not is_instance_valid(_dialog):
		return
	var viewport_size := size.round()
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	_layout_mode = _select_layout_mode(viewport_size)
	var safe_margin := _safe_margins(_layout_mode)
	_safe_rect = Rect2(
		Vector2(safe_margin.x, safe_margin.y),
		viewport_size - Vector2(
			safe_margin.x + safe_margin.z,
			safe_margin.y + safe_margin.w
		)
	)
	var target_size := _dialog_target_size(
		_layout_mode,
		_safe_rect.size
	)
	_dialog.position = (
		_safe_rect.position
		+ ((_safe_rect.size - target_size) * 0.5)
	).round()
	_dialog.size = target_size.round()
	var content_margins := _content_margins(_layout_mode)
	_scroll.position = Vector2(
		content_margins.x,
		content_margins.y
	)
	var desired_scroll_size := Vector2(
		_dialog.size.x - content_margins.x - content_margins.z,
		_dialog.size.y - content_margins.y - content_margins.w
	).round()
	# 先解除上一断点留下的宽度，再写入新视口；否则 ScrollContainer
	# 会用旧 child minimum 反向钳制窄屏尺寸。
	_content.custom_minimum_size.x = 0.0
	_scroll.size = desired_scroll_size
	_content.custom_minimum_size.x = maxi(
		240,
		int(desired_scroll_size.x) - 18
	)
	_scroll.size = desired_scroll_size
	_header.columns = (
		1
		if _layout_mode == LayoutMode.COMPACT_PORTRAIT
		else 2
	)
	_emblem.custom_minimum_size = (
		Vector2(80, 80)
		if _layout_mode == LayoutMode.COMPACT_PORTRAIT
		else Vector2(96, 96)
	)
	if _layout_mode == LayoutMode.COMPACT_PORTRAIT:
		_kicker.max_lines_visible = 3
		_title.max_lines_visible = 5
		_body.max_lines_visible = 9
		_consequence.max_lines_visible = 7
		_summary.max_lines_visible = 14
		_feedback.max_lines_visible = 5
	else:
		_kicker.max_lines_visible = 2
		_title.max_lines_visible = 3
		_body.max_lines_visible = 6
		_consequence.max_lines_visible = 5
		_summary.max_lines_visible = 10
		_feedback.max_lines_visible = 4
	_content.add_theme_constant_override(
		&"separation",
		14
		if _layout_mode in [
			LayoutMode.WIDE,
			LayoutMode.COMPACT_LANDSCAPE,
			LayoutMode.COMPACT_PORTRAIT,
		]
		else 18
	)
	_update_action_grid()
	_update_focus_chain()
	_remeasure_text_slots()


func _select_layout_mode(viewport_size: Vector2) -> LayoutMode:
	var profile_size := viewport_size
	if _layout_profile_size_override.x > 0.0:
		profile_size = _layout_profile_size_override
	var aspect := profile_size.x / maxf(1.0, profile_size.y)
	if (
		profile_size.x >= 1180.0
		and profile_size.y >= 720.0
	):
		return LayoutMode.WIDE
	if aspect < 0.9:
		return LayoutMode.COMPACT_PORTRAIT
	if profile_size.y < 420.0 and profile_size.x >= 560.0:
		return LayoutMode.COMPACT_LANDSCAPE
	if aspect > 2.0:
		return LayoutMode.COMPACT_LANDSCAPE
	if profile_size.x >= 560.0:
		return LayoutMode.STANDARD
	return LayoutMode.COMPACT_PORTRAIT


func _safe_margins(layout_mode: LayoutMode) -> Vector4:
	var base: Vector4
	match layout_mode:
		LayoutMode.WIDE:
			base = Vector4(80, 64, 80, 64)
		LayoutMode.STANDARD:
			base = Vector4(40, 32, 40, 32)
		LayoutMode.COMPACT_LANDSCAPE:
			base = Vector4(24, 18, 24, 18)
		_:
			base = Vector4(16, 16, 16, 16)
	if _safe_insets_override.x < 0.0:
		return base
	return Vector4(
		maxf(base.x, _safe_insets_override.x),
		maxf(base.y, _safe_insets_override.y),
		maxf(base.z, _safe_insets_override.z),
		maxf(base.w, _safe_insets_override.w)
	)


func _dialog_target_size(
	layout_mode: LayoutMode,
	available: Vector2
) -> Vector2:
	match layout_mode:
		LayoutMode.WIDE:
			return Vector2(
				minf(1104.0, available.x),
				minf(876.0, available.y)
			)
		LayoutMode.STANDARD:
			return Vector2(
				minf(900.0, available.x),
				minf(760.0, available.y)
			)
		_:
			return available


func _content_margins(layout_mode: LayoutMode) -> Vector4:
	match layout_mode:
		LayoutMode.WIDE:
			return Vector4(86, 100, 86, 36)
		LayoutMode.STANDARD:
			return Vector4(64, 104, 64, 48)
		LayoutMode.COMPACT_LANDSCAPE:
			return Vector4(54, 94, 54, 42)
		_:
			return Vector4(36, 92, 36, 42)


func _rect_array(rect: Rect2) -> Array:
	return [
		roundi(rect.position.x),
		roundi(rect.position.y),
		roundi(rect.size.x),
		roundi(rect.size.y),
	]
