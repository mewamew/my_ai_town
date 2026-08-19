class_name PlaceFocusPanel
extends Control


signal intent_requested(intent: StringName, payload: Dictionary)
signal action_blocked(intent: StringName, reason: String)
signal close_requested
signal view_model_rejected(reason: String)

const UI_SIGNALS := preload(
	"res://ui/common/AiTownUiSignals.gd"
)
const UiViewModel := preload("res://ui/common/AiTownUiViewModel.gd")
const PageTheme := preload("res://ui/place_focus/runtime/PlaceFocusTheme.gd")

const SCOPE := &"place_focus"
const PROFILE_1080 := "right_submenu_1920x1080"
const PROFILE_720 := "right_submenu_1280x720"
const PROFILE_UNSUPPORTED := "unsupported_resolution"
const ASSET_1080 := "res://assets/ui/place_focus/runtime/right_submenu_v8/place_focus_right_submenu_v8_640x960.png"
const ASSET_720 := "res://assets/ui/place_focus/runtime/right_submenu_v8/place_focus_right_submenu_v8_428x642.png"
const SOURCE_ASSET := ASSET_1080
const ASSET_1080_SHA256 := "493dbd0f4f3f5f30f48c81d47b7bbff0156c433d271803da4d07717bc32d541f"
const ASSET_720_SHA256 := "8c69f7478a8822415ac9e3aff67ddc1545b76a38d0dc24ae3026368768118199"
const SOURCE_SHA256 := "493dbd0f4f3f5f30f48c81d47b7bbff0156c433d271803da4d07717bc32d541f"
const DESIGN_SIZE := Vector2(640, 960)
const SIZE_1080 := Vector2(640, 960)
const SIZE_720 := Vector2(428, 642)
const SAFE_INSETS_ENV := "AI_TOWN_PLACE_FOCUS_SAFE_INSETS"
const ACTION_DEBOUNCE_MSEC := 250
const COLLAPSED_VISIBLE_WIDTH := 72.0
const PANEL_TOGGLE_RECT := Rect2(0, 420, 72, 120)
const RESIDENT_VIEWPORT_CAPACITY := 3
const RESIDENT_INPUT_RECT := Rect2(40, 180, 540, 190)
const RESIDENT_SWIPE_THRESHOLD_PX := 36.0
const RESIDENT_NAME_RECTS: Array[Rect2] = [
	Rect2(59, 307, 125, 42),
	Rect2(235, 307, 124, 42),
	Rect2(410, 307, 126, 42),
]
const RESIDENT_NAME_SAFE_RECTS: Array[Rect2] = [
	Rect2(59, 307, 125, 42),
	Rect2(235, 307, 124, 42),
	Rect2(410, 307, 126, 42),
]
const EVENT_TITLE_RECT := Rect2(198, 421, 328, 48)
const EVENT_TITLE_SAFE_RECT := Rect2(198, 421, 328, 48)
const EVENT_SUMMARY_RECT := Rect2(198, 476, 328, 56)
const EVENT_SUMMARY_SAFE_RECT := Rect2(198, 476, 328, 56)
const EVENT_TIME_RECT := Rect2(122, 541, 404, 44)
const EVENT_TIME_SAFE_RECT := Rect2(122, 541, 404, 44)
const LOG_TITLE_RECTS: Array[Rect2] = [
	Rect2(188, 606, 278, 42),
	Rect2(188, 663, 278, 42),
	Rect2(188, 720, 278, 42),
]
const LOG_TITLE_SAFE_RECTS: Array[Rect2] = [
	Rect2(188, 606, 278, 42),
	Rect2(188, 663, 278, 42),
	Rect2(188, 720, 278, 42),
]
const REQUIRED_DATA_KEYS: Array[String] = [
	"source",
	"capabilityMode",
	"formalReady",
	"place",
	"residents",
	"currentEvents",
	"recentLogs",
]
const REQUIRED_ACTION_KEYS: Array[String] = [
	"openResident",
	"openEvent",
	"openLog",
	"enterInterior",
]
const DISABLED_REASON_COPY := {
	"ACTION_DISABLED": "当前操作不可用",
	"NO_ACTIVE_EVENT": "这个地点当前没有可查看的事件",
	"NO_RESIDENT_TARGET": "这个地点当前没有可查看的居民",
	"OBSERVER_MODE_REQUIRED": "请先退出化身模式再观察室内",
	"OPERATION_IN_FLIGHT": "正在处理，请稍候",
	"PLACE_FOCUS_ADAPTER_CONTRACT_MISSING": "地点资料暂时不可用",
	"PLACE_FOCUS_CONTENT_NOT_FORMAL_READY": "地点资料暂时不可用",
	"PLACE_HAS_NO_INTERIOR": "这个地点没有可观察的室内",
	"PLACE_LOG_NOT_AVAILABLE": "这个地点当前没有可查看的日志",
	"PLACE_OBSERVATION_INTERFACE_MISSING": "室内观察暂时不可用",
	"RESIDENT_DETAIL_NOT_FORMAL_READY": "居民资料暂时不可用",
	"EVENT_DETAIL_NOT_FORMAL_READY": "事件资料暂时不可用",
	"PLACE_LOG_NOT_FORMAL_READY": "地点日志暂时不可用",
}
const OPERATION_COPY := {
	"idle": "",
	"loading": "正在处理地点操作……",
	"success": "地点操作已完成",
	"rejected": "地点操作未被接受，已保留上一份资料",
	"error": "地点资料暂时不可用",
	"disabled": "地点资料暂时不可用",
}
const HIDDEN_ACTION_LIFECYCLE_COPY: Array[String] = [
	"行动已经完成",
	"行动已经失败",
	"行动已经拒绝",
	"行动已完成",
	"行动已失败",
	"行动已拒绝",
	"行动已completed",
	"行动已rejected",
	"行动已interrupted",
	"行动已replaced",
]

var _adapter: Object
var _view_model: Dictionary = {}
var _render_data: Dictionary = {}
var _last_confirmed_data: Dictionary = {}
var _current_revision := -1
var _last_confirmed_revision := -1
var _available_rect_override := Rect2()
var _available_panes_override: Array[Rect2] = []
var _safe_insets_override := Vector4(-1, -1, -1, -1)
var _last_available_rect := Rect2()
var _last_safe_rect := Rect2()
var _layout_profile := PROFILE_UNSUPPORTED
var _layout_queued := false
var _panel_collapsed := false
var _resident_scroll_offset := 0
var _resident_place_key := ""
var _resident_swipe_tracking := false
var _resident_swipe_start := Vector2.ZERO
var _resident_swipe_pointer := -1
var _locally_pending_actions: Dictionary = {}
var _last_dispatch_msec: Dictionary = {}
var _focus_controls: Array[Control] = []
var _designed_controls: Array[Control] = []

var _panel_host: Control
var _background: TextureRect
var _content: Control
var _place_name: Label
var _place_meta: Label
var _resident_range: Label
var _resident_names: Array[Label] = []
var _resident_portrait_fallbacks: Array[Label] = []
var _event_title: Label
var _event_summary: Label
var _event_time: Label
var _log_titles: Array[Label] = []
var _enter_label: Label
var _feedback: RichTextLabel
var _close_button: Button
var _resident_buttons: Array[Button] = []
var _event_button: Button
var _log_buttons: Array[Button] = []
var _enter_button: Button
var _panel_toggle_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	theme = PageTheme.create()
	_build_interface()
	resized.connect(_queue_layout)
	get_viewport().size_changed.connect(_queue_layout)
	if _adapter != null:
		_refresh_from_adapter()
	else:
		apply_view_model(_adapter_missing_view_model())
	_queue_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_resident_swipe_tracking = false
		_resident_swipe_pointer = -1


func _exit_tree() -> void:
	_disconnect_adapter()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if not _panel_host.visible:
		return
	if event.is_action_pressed("ui_left") and _panel_focus_active():
		if scroll_residents(-1):
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_right") and _panel_focus_active():
		if scroll_residents(1):
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_focus_next"):
		_move_focus(1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_focus_prev"):
		_move_focus(-1)
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not is_instance_valid(_panel_host) or not _panel_host.visible or _panel_collapsed:
		_resident_swipe_tracking = false
		_resident_swipe_pointer = -1
		return
	var input_rect := _design_rect_to_global(RESIDENT_INPUT_RECT)
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if not mouse.pressed or not input_rect.has_point(mouse.position):
			return
		var delta := 0
		if mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
			delta = -1
		elif mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			delta = 1
		if delta != 0 and scroll_residents(delta):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _resident_swipe_pointer >= 0:
				return
			_resident_swipe_tracking = input_rect.has_point(touch.position)
			_resident_swipe_start = touch.position
			_resident_swipe_pointer = touch.index if _resident_swipe_tracking else -1
			return
		if not _resident_swipe_tracking or touch.index != _resident_swipe_pointer:
			return
		_resident_swipe_tracking = false
		_resident_swipe_pointer = -1
		if touch.canceled:
			return
		var swipe_x := touch.position.x - _resident_swipe_start.x
		if absf(swipe_x) >= RESIDENT_SWIPE_THRESHOLD_PX:
			if scroll_residents(-1 if swipe_x > 0.0 else 1):
				get_viewport().set_input_as_handled()


func bind_town_ui_adapter(adapter: Object) -> void:
	if _adapter == adapter:
		return
	_disconnect_adapter()
	_adapter = adapter
	_view_model.clear()
	_render_data.clear()
	_last_confirmed_data.clear()
	_current_revision = -1
	_last_confirmed_revision = -1
	_resident_scroll_offset = 0
	_resident_place_key = ""
	_locally_pending_actions.clear()
	_last_dispatch_msec.clear()
	if _adapter != null and _adapter.has_signal("view_model_changed"):
		var callback := Callable(self, "_on_view_model_changed")
		if not _adapter.is_connected("view_model_changed", callback):
			_adapter.connect("view_model_changed", callback)
	if is_node_ready():
		_refresh_from_adapter()


func unbind_town_ui_adapter() -> void:
	bind_town_ui_adapter(null)


func apply_view_model(snapshot: Dictionary) -> bool:
	var issues := _validate_view_model(snapshot)
	if not issues.is_empty():
		var reason := "\n".join(issues)
		for issue: String in issues:
			push_error(issue)
		view_model_rejected.emit(reason)
		return false
	var incoming_revision := UiViewModel.revision(snapshot)
	if _current_revision >= 0 and incoming_revision < _current_revision:
		view_model_rejected.emit("STALE_REVISION_%d_LT_%d" % [incoming_revision, _current_revision])
		return false

	var incoming_data := UiViewModel.data(snapshot)
	var operation_status := UiViewModel.operation_status(snapshot)
	if operation_status in [&"idle", &"success"] and not incoming_data.is_empty():
		_last_confirmed_data = incoming_data.duplicate(true)
		_last_confirmed_revision = incoming_revision
	if operation_status in [&"loading", &"rejected", &"error"] and not _last_confirmed_data.is_empty():
		_render_data = _last_confirmed_data.duplicate(true)
	else:
		_render_data = incoming_data.duplicate(true)
	if _render_data.is_empty():
		_render_data = _last_confirmed_data.duplicate(true)

	_view_model = snapshot.duplicate(true)
	_current_revision = incoming_revision
	_locally_pending_actions.clear()
	if is_node_ready():
		_render()
	return true


func current_view_model() -> Dictionary:
	return _view_model.duplicate(true)


func current_revision() -> int:
	return _current_revision


func current_layout_profile() -> String:
	return _layout_profile


func scroll_residents(delta: int) -> bool:
	var residents := _render_data.get("residents", []) as Array
	var maximum := maxi(0, residents.size() - RESIDENT_VIEWPORT_CAPACITY)
	var next_offset := clampi(_resident_scroll_offset + delta, 0, maximum)
	if next_offset == _resident_scroll_offset:
		return false
	_resident_scroll_offset = next_offset
	if is_node_ready():
		_render()
	return true


func apply_route_payload(payload: Dictionary) -> void:
	_panel_collapsed = bool(payload.get("panelCollapsed", false))
	if is_node_ready():
		_render()


func navigation_state() -> Dictionary:
	var place := _render_data.get("place", {}) as Dictionary
	var result := {
		"placeName": String(place.get("placeName", "")).strip_edges(),
		"spaceId": String(place.get("spaceId", "")).strip_edges(),
		"revision": _current_revision,
		"panelCollapsed": _panel_collapsed,
	}
	if String(result.get("placeName", "")).is_empty():
		result.erase("placeName")
	if String(result.get("spaceId", "")).is_empty():
		result.erase("spaceId")
	return result


func set_available_rect(available_rect: Rect2) -> void:
	_available_panes_override.clear()
	_available_rect_override = available_rect
	_queue_layout()


func clear_available_rect_override() -> void:
	_available_rect_override = Rect2()
	_queue_layout()


func set_available_panes(panes: Array) -> void:
	_available_panes_override.clear()
	for pane_value: Variant in panes:
		if pane_value is Rect2 and (pane_value as Rect2).has_area():
			_available_panes_override.append(pane_value as Rect2)
	_available_rect_override = Rect2()
	_queue_layout()


func clear_available_panes_override() -> void:
	_available_panes_override.clear()
	_queue_layout()


func set_safe_insets(insets: Vector4) -> void:
	_safe_insets_override = Vector4(
		maxf(0, insets.x),
		maxf(0, insets.y),
		maxf(0, insets.z),
		maxf(0, insets.w)
	)
	_queue_layout()


func clear_safe_insets_override() -> void:
	_safe_insets_override = Vector4(-1, -1, -1, -1)
	_queue_layout()


func focus_default_control() -> void:
	if _panel_collapsed and _focusable(_panel_toggle_button):
		_panel_toggle_button.grab_focus()
		return
	for control: Control in _focus_controls:
		if _focusable(control):
			control.grab_focus()
			return


func focus_default() -> void:
	focus_default_control()


func request_close() -> void:
	close_requested.emit()


func debug_request_action(action_key: String, payload: Dictionary = {}) -> bool:
	return _request_action(action_key, payload)


func runtime_gate_snapshot() -> Dictionary:
	var text_slots: Array[Dictionary] = []
	for node: Node in get_tree().get_nodes_in_group("place_focus_text_slot"):
		if not is_ancestor_of(node) or (not node is Label and not node is RichTextLabel):
			continue
		var control := node as Control
		if not control.is_visible_in_tree():
			continue
		var font: Font
		var font_size: int
		var copy := ""
		var overrun := TextServer.OVERRUN_NO_TRIMMING
		var alignment := HORIZONTAL_ALIGNMENT_LEFT
		if node is Label:
			var label := node as Label
			font = label.get_theme_font("font")
			font_size = label.get_theme_font_size("font_size")
			copy = label.text
			overrun = label.text_overrun_behavior
			alignment = label.horizontal_alignment
		else:
			var rich := node as RichTextLabel
			font = rich.get_theme_font("normal_font")
			font_size = rich.get_theme_font_size("normal_font_size")
			copy = rich.get_parsed_text()
		var rect := Rect2(control.global_position, control.size)
		var painted_safe_rect := _design_rect_to_global(
			control.get_meta(
				"painted_safe_rect",
				control.get_meta("design_rect", Rect2()),
			) as Rect2,
		)
		var measured_width := (
			font.get_string_size(copy, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			if font != null and not copy.is_empty()
			else 0.0
		)
		var displayed_width := minf(measured_width, rect.size.x)
		var ink_x := rect.position.x
		if alignment == HORIZONTAL_ALIGNMENT_CENTER:
			ink_x += (rect.size.x - displayed_width) * 0.5
		elif alignment == HORIZONTAL_ALIGNMENT_RIGHT:
			ink_x += rect.size.x - displayed_width
		var line_height := font.get_height(font_size) if font != null else 0.0
		var ink_rect := Rect2(
			Vector2(ink_x, rect.position.y + (rect.size.y - line_height) * 0.5),
			Vector2(displayed_width, line_height),
		)
		text_slots.append({
			"id": String(control.get_meta("gate_id", control.name)),
			"owner": String(control.get_meta("slot_owner", control.name)),
			"text": copy,
			"rect": _rect_to_array(rect),
			"paintedSafeRect": _rect_to_array(painted_safe_rect),
			"inkRect": _rect_to_array(ink_rect),
			"fontSize": font_size,
			"lineHeight": line_height,
			"measuredWidth": measured_width,
			"displayedWidth": displayed_width,
			"ellipsisRequired": measured_width > rect.size.x,
			"overrun": overrun,
			"clipText": (
				(node as Label).clip_text if node is Label else true
			),
			"verticalAlignment": (
				(node as Label).vertical_alignment
				if node is Label
				else VERTICAL_ALIGNMENT_CENTER
			),
		})
	var touch_targets: Array[Dictionary] = []
	for node: Node in get_tree().get_nodes_in_group("place_focus_touch_target"):
		if not is_ancestor_of(node) or not node is Control:
			continue
		var control := node as Control
		if not control.is_visible_in_tree():
			continue
		touch_targets.append({
			"id": String(control.get_meta("gate_id", control.name)),
			"rect": _rect_to_array(Rect2(control.global_position, control.size)),
			"focusMode": control.focus_mode,
			"disabled": (control as BaseButton).disabled if control is BaseButton else false,
			"actionKey": String(control.get_meta("action_key", "")),
		})
	var place := _render_data.get("place", {}) as Dictionary
	var asset_path := _asset_path_for_profile(_layout_profile)
	var native_size := _asset_size_for_profile(_layout_profile)
	return {
		"scope": String(_view_model.get("scope", "")),
		"status": String(_view_model.get("status", "")),
		"revision": _current_revision,
		"lastConfirmedRevision": _last_confirmed_revision,
		"operationStatus": String(UiViewModel.operation_status(_view_model)),
		"sourceMode": _source_mode(),
		"source": String(_render_data.get("source", "")),
		"capabilityMode": String(_render_data.get("capabilityMode", "")),
		"formalReady": bool(_render_data.get("formalReady", false)),
		"layoutProfile": _layout_profile,
		"supportedResolution": _layout_profile != PROFILE_UNSUPPORTED,
		"wholePageScale": [scale.x, scale.y],
		"panelTextureScale": [1.0, 1.0],
		"availableRect": _rect_to_array(_last_available_rect),
		"safeRect": _rect_to_array(_last_safe_rect),
		"panelRect": _rect_to_array(Rect2(_panel_host.global_position, _panel_host.size)) if _panel_host.visible else [0.0, 0.0, 0.0, 0.0],
		"runtimeRevision": "ui.place-focus.runtime-v8",
		"runtimeStatus": "formal_approved",
		"runtimeAsset": asset_path,
		"runtimeAssetNativeSize": [native_size.x, native_size.y],
		"runtimeSourceAsset": SOURCE_ASSET,
		"runtimeSourceSha256": SOURCE_SHA256,
		"runtimeAssetSha256": _asset_sha_for_profile(_layout_profile),
		"fixtureAutoLoad": false,
		"legacyFallbackPresent": false,
		"reviewImageCropPresent": false,
		"panelMouseFilter": _panel_host.mouse_filter,
		"rootMouseFilter": mouse_filter,
		"panelCollapsed": _panel_collapsed,
		"collapsedVisibleWidth": (
			COLLAPSED_VISIBLE_WIDTH
			* native_size.x
			/ DESIGN_SIZE.x
		),
		"mapInputOutsidePanelPasses": mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"mapInputInsidePanelBlocked": _panel_host.mouse_filter == Control.MOUSE_FILTER_STOP,
		"placeName": String(place.get("placeName", "")),
		"residentCount": (_render_data.get("residents", []) as Array).size(),
		"residentScrollOffset": _resident_scroll_offset,
		"residentVisibleRange": _resident_visible_range(),
		"eventCount": (_render_data.get("currentEvents", []) as Array).size(),
		"logCount": _public_recent_logs().size(),
		"textSlots": text_slots,
		"touchTargets": touch_targets,
		"focusChain": _focus_chain_ids(),
		"fontShrink": false,
		"runtimeGuideNodeCount": _runtime_guide_node_count(),
		"ownership": _ownership_snapshot(),
		"worldReads": [],
	}


func _build_interface() -> void:
	_panel_host = Control.new()
	_panel_host.name = "PlaceFocusInputOwner"
	_panel_host.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel_host.clip_contents = true
	add_child(_panel_host)

	_background = TextureRect.new()
	_background.name = "PlaceFocusRightSubmenuPanel"
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP
	_background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.set_meta("asset_id", "ui.place-focus.right-submenu.v8")
	_background.set_meta("component_type", "TextureRect/page_specific_runtime_raster")
	_background.set_meta("ownership_level", "page_shell")
	_background.set_meta("border_owner", true)
	_panel_host.add_child(_background)

	_content = Control.new()
	_content.name = "RightSubmenuRuntimeContent"
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_host.add_child(_content)
	_build_text_slots()
	_build_hit_targets()


func _build_text_slots() -> void:
	_place_name = _stable_label(
		"PlaceName",
		Rect2(155, 39, 334, 80),
		"Title",
		HORIZONTAL_ALIGNMENT_CENTER,
	)
	_place_meta = _stable_label(
		"PlaceMeta",
		Rect2(157, 133, 230, 32),
		"Compact",
		HORIZONTAL_ALIGNMENT_CENTER,
	)
	_resident_range = _stable_label(
		"ResidentRange",
		Rect2(390, 133, 100, 32),
		"Compact",
		HORIZONTAL_ALIGNMENT_RIGHT,
	)
	for index: int in 3:
		_resident_portrait_fallbacks.append(_stable_label(
			"ResidentPortraitFallback%d" % index,
			Rect2(55 + index * 176, 205, 140, 96),
			"Title",
			HORIZONTAL_ALIGNMENT_CENTER,
		))
		_resident_names.append(_stable_label(
			"ResidentName%d" % index,
			RESIDENT_NAME_RECTS[index],
			"Body",
			HORIZONTAL_ALIGNMENT_CENTER,
			RESIDENT_NAME_SAFE_RECTS[index],
			"resident_name_%d" % index,
		))
	_event_title = _stable_label(
		"EventTitle",
		EVENT_TITLE_RECT,
		"Event",
		HORIZONTAL_ALIGNMENT_LEFT,
		EVENT_TITLE_SAFE_RECT,
		"current_event_title",
	)
	_event_summary = _stable_label(
		"EventSummary",
		EVENT_SUMMARY_RECT,
		"Compact",
		HORIZONTAL_ALIGNMENT_LEFT,
		EVENT_SUMMARY_SAFE_RECT,
		"current_event_summary",
	)
	_event_summary.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_event_summary.max_lines_visible = 2
	_event_time = _stable_label(
		"EventTime",
		EVENT_TIME_RECT,
		"Compact",
		HORIZONTAL_ALIGNMENT_CENTER,
		EVENT_TIME_SAFE_RECT,
		"current_event_time",
	)
	for index: int in 3:
		_log_titles.append(_stable_label(
			"LogTitle%d" % index,
			LOG_TITLE_RECTS[index],
			"Compact",
			HORIZONTAL_ALIGNMENT_LEFT,
			LOG_TITLE_SAFE_RECTS[index],
			"recent_log_title_%d" % index,
		))
	_enter_label = _stable_label(
		"EnterInteriorLabel",
		Rect2(165, 812, 380, 64),
		"Enter",
		HORIZONTAL_ALIGNMENT_CENTER,
	)
	_feedback = _stable_rich_label(
		"Feedback",
		Rect2(105, 896, 440, 44),
	)


func _build_hit_targets() -> void:
	_close_button = _hit_button("CloseButton", Rect2(522, 38, 70, 70), "close")
	_close_button.pressed.connect(request_close)
	for index: int in 3:
		var button := _hit_button(
			"ResidentButton%d" % index,
			Rect2(45 + index * 176, 188, 156, 190),
			"openResident"
		)
		button.pressed.connect(_on_resident_pressed.bind(index))
		_resident_buttons.append(button)
	_event_button = _hit_button(
		"EventButton",
		Rect2(45, 410, 550, 180),
		"openEvent",
	)
	_event_button.pressed.connect(_on_event_pressed)
	for index: int in 3:
		var button := _hit_button(
			"LogButton%d" % index,
			Rect2(45, 604 + index * 57, 550, 48),
			"openLog"
		)
		button.pressed.connect(_on_log_pressed.bind(index))
		_log_buttons.append(button)
	_enter_button = _hit_button(
		"EnterInterior",
		Rect2(37, 804, 566, 82),
		"enterInterior",
	)
	_enter_button.pressed.connect(_on_enter_pressed)

	_panel_toggle_button = Button.new()
	_panel_toggle_button.name = "PanelToggle"
	_panel_toggle_button.theme_type_variation = &"PlaceFocusPanelToggle"
	_panel_toggle_button.focus_mode = Control.FOCUS_ALL
	_panel_toggle_button.mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND
	)
	_panel_toggle_button.add_to_group("place_focus_touch_target")
	_panel_toggle_button.set_meta("gate_id", "toggle_panel")
	_panel_toggle_button.set_meta("action_key", "togglePanel")
	_panel_toggle_button.set_meta("design_rect", PANEL_TOGGLE_RECT)
	_panel_toggle_button.set_meta("border_owner", false)
	_panel_toggle_button.set_meta(
		"component_type",
		"local_presentation_toggle",
	)
	_panel_toggle_button.pressed.connect(_on_panel_toggle_pressed)
	_panel_toggle_button.z_index = 30
	_content.add_child(_panel_toggle_button)
	_designed_controls.append(_panel_toggle_button)


func _render() -> void:
	if _view_model.is_empty():
		return
	var place := _render_data.get("place", {}) as Dictionary
	var residents := _render_data.get("residents", []) as Array
	var events := _render_data.get("currentEvents", []) as Array
	var logs := _public_recent_logs()
	var place_name := String(place.get("placeName", "暂无资料"))
	var place_key := String(place.get("spaceId", "")).strip_edges()
	if place_key.is_empty():
		place_key = place_name
	if place_key != _resident_place_key:
		_resident_place_key = place_key
		_resident_scroll_offset = 0
	_resident_scroll_offset = clampi(
		_resident_scroll_offset,
		0,
		maxi(0, residents.size() - RESIDENT_VIEWPORT_CAPACITY),
	)
	var place_meta := "%s · %d 位居民" % [
		String(place.get("placeType", "未知")),
		int(place.get("residentCount", residents.size())),
	]
	_place_name.text = place_name
	_place_meta.text = place_meta
	var visible_end := mini(
		_resident_scroll_offset + RESIDENT_VIEWPORT_CAPACITY,
		residents.size(),
	)
	_resident_range.text = (
		"%d-%d/%d" % [_resident_scroll_offset + 1, visible_end, residents.size()]
		if residents.size() > RESIDENT_VIEWPORT_CAPACITY
		else ""
	)
	_resident_range.tooltip_text = (
		"滚轮、左右滑动或方向键查看其他在场居民"
		if residents.size() > RESIDENT_VIEWPORT_CAPACITY
		else ""
	)

	for index: int in RESIDENT_VIEWPORT_CAPACITY:
		var resident_index := _resident_scroll_offset + index
		var resident := (
			residents[resident_index] as Dictionary
			if (
				resident_index < residents.size()
				and residents[resident_index] is Dictionary
			)
			else {}
		)
		var resident_name := String(
			resident.get(
				"residentName",
				"暂无居民" if index == 0 and residents.is_empty() else "",
			)
		)
		_resident_names[index].text = resident_name
		_resident_portrait_fallbacks[index].text = (
			resident_name.left(1) if not resident_name.is_empty() else ""
		)
		_apply_entity_button_state(_resident_buttons[index], "openResident", not resident.is_empty() and bool(resident.get("canOpen", false)), String(resident.get("disabledReason", "")))

	var event := events[0] as Dictionary if not events.is_empty() and events[0] is Dictionary else {}
	_event_title.text = String(event.get("title", "当前没有事件"))
	_event_summary.text = String(event.get("summary", ""))
	_event_time.text = String(event.get("timeLabel", "--:--"))
	_apply_entity_button_state(_event_button, "openEvent", not event.is_empty() and bool(event.get("canOpen", false)), String(event.get("disabledReason", "")))

	for index: int in 3:
		var log_entry := logs[index] as Dictionary if index < logs.size() and logs[index] is Dictionary else {}
		_log_titles[index].text = String(log_entry.get("title", "暂无日志" if index == 0 and logs.is_empty() else ""))
		_apply_entity_button_state(_log_buttons[index], "openLog", not log_entry.is_empty() and bool(log_entry.get("canOpen", false)), String(log_entry.get("disabledReason", "")))

	var operation_status := String(UiViewModel.operation_status(_view_model))
	_enter_label.text = "正在进入……" if operation_status == "loading" else "进入室内"
	_apply_entity_button_state(_enter_button, "enterInterior", bool(place.get("hasInterior", false)), "")
	_set_feedback_text(_feedback_copy())
	_apply_profile_theme()
	_apply_panel_presentation_state()
	_queue_layout()


func _feedback_copy() -> String:
	var operation_status := String(UiViewModel.operation_status(_view_model))
	var error_message := UiViewModel.error_message(_view_model)
	if operation_status in ["rejected", "error"] and not error_message.is_empty():
		return error_message
	var operation_copy := String(OPERATION_COPY.get(operation_status, ""))
	if not operation_copy.is_empty():
		return operation_copy
	if not bool(_render_data.get("formalReady", false)):
		return "地点资料暂时不可用"
	return "地点资料已同步"


func _apply_entity_button_state(button: Button, action_key: String, entity_enabled: bool, entity_reason: String) -> void:
	var action := UiViewModel.action(_view_model, action_key)
	var formal_ready := bool(_render_data.get("formalReady", false))
	var operation_loading := UiViewModel.operation_status(_view_model) == &"loading"
	var enabled := formal_ready and entity_enabled and UiViewModel.action_enabled(action) and not operation_loading
	button.disabled = not enabled
	button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	var reason := entity_reason
	if not formal_ready:
		reason = "PLACE_FOCUS_CONTENT_NOT_FORMAL_READY"
	elif operation_loading:
		reason = "OPERATION_IN_FLIGHT"
	elif reason.is_empty():
		reason = UiViewModel.disabled_reason(action)
	button.tooltip_text = _player_reason(reason)


func _request_action(action_key: String, payload: Dictionary) -> bool:
	var action := UiViewModel.action(_view_model, action_key)
	var intent := StringName(action.get("intent", ""))
	var reason := UiViewModel.disabled_reason(action)
	var formal_ready := bool(_render_data.get("formalReady", false))
	var now_msec := Time.get_ticks_msec()
	var last_msec := int(_last_dispatch_msec.get(action_key, -ACTION_DEBOUNCE_MSEC))
	if _locally_pending_actions.has(action_key) or now_msec - last_msec < ACTION_DEBOUNCE_MSEC:
		action_blocked.emit(intent, "REQUEST_ALREADY_SUBMITTED")
		return false
	if not formal_ready or intent == &"" or not UiViewModel.action_enabled(action):
		if not formal_ready:
			reason = "PLACE_FOCUS_CONTENT_NOT_FORMAL_READY"
		action_blocked.emit(intent, reason if not reason.is_empty() else "ACTION_DISABLED")
		return false
	var envelope: Dictionary = {}
	var static_payload: Variant = action.get("payload", {})
	if static_payload is Dictionary:
		envelope = (static_payload as Dictionary).duplicate(true)
	envelope.merge(payload, true)
	var place := _render_data.get("place", {}) as Dictionary
	var space_id := String(place.get("spaceId", ""))
	if not space_id.is_empty():
		envelope["spaceId"] = space_id
	envelope["revision"] = _current_revision
	_locally_pending_actions[action_key] = true
	_last_dispatch_msec[action_key] = now_msec
	if _adapter != null and _adapter.has_method("dispatch"):
		var dispatch_result: Variant = _adapter.call(
			"dispatch",
			String(intent),
			envelope.duplicate(true),
		)
		if (
			dispatch_result is Dictionary
			and (dispatch_result as Dictionary).has("ok")
			and not bool((dispatch_result as Dictionary).get("ok", false))
		):
			_locally_pending_actions.erase(action_key)
			var dispatch_reason := String(
				(dispatch_result as Dictionary).get(
					"errorCode",
					"ACTION_REJECTED",
				)
			)
			action_blocked.emit(intent, dispatch_reason)
			return false
	# Route hosts may replace this page synchronously. Emit only after the
	# authoritative Adapter has accepted the action so navigation cannot
	# prevent the source page from submitting its resident/log selection.
	intent_requested.emit(intent, envelope.duplicate(true))
	return true


func _on_resident_pressed(index: int) -> void:
	var residents := _render_data.get("residents", []) as Array
	var resident_index := _resident_scroll_offset + index
	if resident_index >= residents.size() or not residents[resident_index] is Dictionary:
		return
	_request_action(
		"openResident",
		{
			"residentId": String(
				(residents[resident_index] as Dictionary).get(
					"residentId",
					"",
				)
			),
		},
	)


func _panel_focus_active() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return focused != null and is_ancestor_of(focused)


func _resident_visible_range() -> Array[int]:
	var residents := _render_data.get("residents", []) as Array
	if residents.is_empty():
		return [0, 0]
	return [
		_resident_scroll_offset,
		mini(_resident_scroll_offset + RESIDENT_VIEWPORT_CAPACITY, residents.size()),
	]


func _on_event_pressed() -> void:
	var events := _render_data.get("currentEvents", []) as Array
	if events.is_empty() or not events[0] is Dictionary:
		return
	_request_action("openEvent", {"eventId": String((events[0] as Dictionary).get("eventId", ""))})


func _on_log_pressed(index: int) -> void:
	var logs := _public_recent_logs()
	if index >= logs.size() or not logs[index] is Dictionary:
		return
	_request_action("openLog", {"logEntryId": String((logs[index] as Dictionary).get("logEntryId", ""))})


func _public_recent_logs() -> Array[Dictionary]:
	var visible_logs: Array[Dictionary] = []
	for value: Variant in _render_data.get("recentLogs", []) as Array:
		if not value is Dictionary:
			continue
		var log_entry := value as Dictionary
		var title := String(log_entry.get("title", "")).strip_edges()
		var internal_lifecycle := false
		for blocked_copy: String in HIDDEN_ACTION_LIFECYCLE_COPY:
			if title.contains(blocked_copy):
				internal_lifecycle = true
				break
		if internal_lifecycle:
			continue
		visible_logs.append(log_entry)
		if visible_logs.size() >= 3:
			break
	return visible_logs


func _on_enter_pressed() -> void:
	_request_action("enterInterior", {})


func _on_panel_toggle_pressed() -> void:
	_panel_collapsed = not _panel_collapsed
	if not _panel_collapsed:
		_render()
	else:
		_apply_panel_presentation_state()
		_queue_layout()
		_update_focus_chain()
	_panel_toggle_button.grab_focus()


func _apply_panel_presentation_state() -> void:
	if _panel_toggle_button == null:
		return
	_panel_toggle_button.text = "展开" if _panel_collapsed else "收起"
	_panel_toggle_button.tooltip_text = (
		"展开地点面板" if _panel_collapsed else "收起地点面板"
	)
	_panel_toggle_button.set_meta(
		"accessibility_label",
		_panel_toggle_button.tooltip_text,
	)
	if _panel_collapsed:
		_close_button.focus_mode = Control.FOCUS_NONE
		for button: Button in _resident_buttons:
			button.focus_mode = Control.FOCUS_NONE
		_event_button.focus_mode = Control.FOCUS_NONE
		for button: Button in _log_buttons:
			button.focus_mode = Control.FOCUS_NONE
		_enter_button.focus_mode = Control.FOCUS_NONE
	else:
		_close_button.focus_mode = Control.FOCUS_ALL
	_panel_toggle_button.focus_mode = Control.FOCUS_ALL


func _queue_layout() -> void:
	if _layout_queued:
		return
	_layout_queued = true
	call_deferred("_apply_queued_layout")


func _apply_queued_layout() -> void:
	_layout_queued = false
	if not is_node_ready():
		return
	var available := _available_rect()
	var insets := _safe_insets()
	var safe := Rect2(
		available.position + Vector2(insets.x, insets.y),
		available.size - Vector2(insets.x + insets.z, insets.y + insets.w)
	)
	safe.size.x = maxf(1, safe.size.x)
	safe.size.y = maxf(1, safe.size.y)
	if not _available_panes_override.is_empty():
		var candidate := _available_panes_override[0]
		for pane: Rect2 in _available_panes_override:
			if pane.get_area() > candidate.get_area():
				candidate = pane
		safe = candidate
	_last_available_rect = available
	_last_safe_rect = safe
	_layout_profile = _profile_for_rect(safe)
	if _layout_profile == PROFILE_UNSUPPORTED:
		_panel_host.visible = false
		_focus_controls.clear()
		return

	var panel_size := _asset_size_for_profile(_layout_profile)
	var margin_right := 48.0 if _layout_profile == PROFILE_1080 else 32.0
	var expanded_position := Vector2(
		safe.end.x - panel_size.x - margin_right,
		safe.position.y + (safe.size.y - panel_size.y) * 0.5
	).round()
	var factor := panel_size.x / DESIGN_SIZE.x
	_panel_host.position = (
		Vector2(
			safe.end.x - COLLAPSED_VISIBLE_WIDTH * factor,
			expanded_position.y,
		).round()
		if _panel_collapsed
		else expanded_position
	)
	_panel_host.size = panel_size
	_panel_host.visible = true
	_background.position = Vector2.ZERO
	_background.size = panel_size
	_background.texture = load(_asset_path_for_profile(_layout_profile)) as Texture2D
	_content.position = Vector2.ZERO
	_content.size = panel_size
	for control: Control in _designed_controls:
		var design_rect := control.get_meta("design_rect") as Rect2
		control.position = (design_rect.position * factor).round()
		control.size = (design_rect.size * factor).round()
	_apply_profile_theme()
	_update_focus_chain()


func _profile_for_rect(safe: Rect2) -> String:
	if safe.size.x >= 1920 and safe.size.y >= 1080:
		return PROFILE_1080
	if safe.size.x >= 1280 and safe.size.y >= 720:
		return PROFILE_720
	return PROFILE_UNSUPPORTED


func _apply_profile_theme() -> void:
	var prefix := "PlaceFocus1080" if _layout_profile == PROFILE_1080 else "PlaceFocus720"
	for control: Control in _designed_controls:
		if control is Label:
			var label := control as Label
			var role := String(label.get_meta("theme_role", "Compact"))
			label.theme_type_variation = StringName(prefix + role)
	var operation_status := String(UiViewModel.operation_status(_view_model))
	if _feedback != null:
		if _layout_profile == PROFILE_1080:
			_feedback.theme_type_variation = &"PlaceFocus1080FeedbackError" if operation_status in ["rejected", "error"] else &"PlaceFocus1080Feedback"
		else:
			_feedback.theme_type_variation = &"PlaceFocus720FeedbackError" if operation_status in ["rejected", "error"] else &"PlaceFocus720Feedback"


func _update_focus_chain() -> void:
	_focus_controls.clear()
	if not _panel_host.visible:
		return
	if _panel_collapsed:
		_focus_controls.append(_panel_toggle_button)
		_panel_toggle_button.focus_next = NodePath()
		_panel_toggle_button.focus_previous = NodePath()
		return
	_focus_controls.append(_close_button)
	for button: Button in _resident_buttons:
		if _focusable(button):
			_focus_controls.append(button)
	if _focusable(_event_button):
		_focus_controls.append(_event_button)
	for button: Button in _log_buttons:
		if _focusable(button):
			_focus_controls.append(button)
	if _focusable(_enter_button):
		_focus_controls.append(_enter_button)
	_focus_controls.append(_panel_toggle_button)
	for index: int in _focus_controls.size():
		var control := _focus_controls[index]
		var next := _focus_controls[(index + 1) % _focus_controls.size()]
		var previous := _focus_controls[(index - 1 + _focus_controls.size()) % _focus_controls.size()]
		control.focus_next = control.get_path_to(next)
		control.focus_previous = control.get_path_to(previous)
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null or not is_ancestor_of(focused) or not _focusable(focused as Control):
		call_deferred("focus_default_control")


func _move_focus(direction: int) -> void:
	var available: Array[Control] = []
	for control: Control in _focus_controls:
		if _focusable(control):
			available.append(control)
	if available.is_empty():
		return
	var focused := get_viewport().gui_get_focus_owner()
	var index := available.find(focused)
	index = posmod(index + direction, available.size())
	available[index].grab_focus()


func _focusable(control: Control) -> bool:
	return control != null and control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE and (not control is BaseButton or not (control as BaseButton).disabled)


func _focus_chain_ids() -> Array[String]:
	var result: Array[String] = []
	for control: Control in _focus_controls:
		if _focusable(control):
			result.append(String(control.get_meta("gate_id", control.name)))
	return result


func _available_rect() -> Rect2:
	if _available_rect_override.has_area():
		return _available_rect_override
	return Rect2(Vector2.ZERO, size)


func _safe_insets() -> Vector4:
	if _safe_insets_override.x >= 0:
		return _safe_insets_override
	if not OS.is_debug_build():
		return Vector4.ZERO
	var raw := OS.get_environment(SAFE_INSETS_ENV)
	if raw.is_empty():
		return Vector4.ZERO
	var parts := raw.split(",", false)
	if parts.size() != 4:
		return Vector4.ZERO
	return Vector4(maxf(0, float(parts[0])), maxf(0, float(parts[1])), maxf(0, float(parts[2])), maxf(0, float(parts[3])))


func _refresh_from_adapter() -> void:
	if _adapter == null or not _adapter.has_method("get_view_model"):
		apply_view_model(_adapter_missing_view_model())
		return
	var snapshot: Variant = _adapter.call("get_view_model", String(SCOPE))
	if snapshot is Dictionary and _validate_view_model(snapshot as Dictionary).is_empty():
		apply_view_model(snapshot as Dictionary)
	else:
		apply_view_model(_adapter_missing_view_model())


func _on_view_model_changed(scope_value: Variant, snapshot: Dictionary) -> void:
	if StringName(scope_value) == SCOPE:
		apply_view_model(snapshot)


func _disconnect_adapter() -> void:
	UI_SIGNALS.disconnect_view_model(
		_adapter,
		Callable(self, "_on_view_model_changed"),
	)


func _validate_view_model(snapshot: Dictionary) -> PackedStringArray:
	var issues := UiViewModel.validate(snapshot, "地点聚焦")
	if UiViewModel.scope(snapshot) != SCOPE:
		issues.append("地点聚焦.scope 必须是 place_focus")
	var data_value: Variant = snapshot.get("data", {})
	if not data_value is Dictionary:
		return issues
	var data := data_value as Dictionary
	for key: String in REQUIRED_DATA_KEYS:
		if not data.has(key):
			issues.append("地点聚焦.data 缺少字段：%s" % key)
	if typeof(data.get("formalReady", false)) != TYPE_BOOL:
		issues.append("地点聚焦.data.formalReady 必须是布尔值")
	if not data.get("place", {}) is Dictionary:
		issues.append("地点聚焦.data.place 必须是 Dictionary")
	for key: String in ["residents", "currentEvents", "recentLogs"]:
		if not data.get(key, []) is Array:
			issues.append("地点聚焦.data.%s 必须是 Array" % key)
	var actions := snapshot.get("actions", {}) as Dictionary
	for action_key: String in REQUIRED_ACTION_KEYS:
		if not actions.has(action_key):
			issues.append("地点聚焦.actions 缺少字段：%s" % action_key)
			continue
		var action_value: Variant = actions.get(action_key)
		if not action_value is Dictionary:
			issues.append("地点聚焦.actions.%s 必须是 Dictionary" % action_key)
			continue
		var action := action_value as Dictionary
		if typeof(action.get("intent", "")) not in [TYPE_STRING, TYPE_STRING_NAME]:
			issues.append("地点聚焦.actions.%s.intent 必须是字符串" % action_key)
		if typeof(action.get("enabled", false)) != TYPE_BOOL:
			issues.append("地点聚焦.actions.%s.enabled 必须是布尔值" % action_key)
	return issues


func _adapter_missing_view_model() -> Dictionary:
	var actions: Dictionary = {}
	var intents := {
		"openResident": "place_focus.open_resident",
		"openEvent": "place_focus.open_event",
		"openLog": "place_focus.open_log",
		"enterInterior": "place_focus.enter_interior",
	}
	for action_key: String in intents:
		actions[action_key] = {
			"intent": String(intents[action_key]),
			"enabled": false,
			"disabledReason": "PLACE_FOCUS_ADAPTER_CONTRACT_MISSING",
		}
	return {
		"scope": "place_focus",
		"status": "disabled",
		"revision": maxi(_current_revision, 0),
		"data": {
			"source": "adapter_missing",
			"capabilityMode": "disabled",
			"formalReady": false,
			"place": {"placeName": "暂无资料", "placeType": "未知", "spaceId": "", "summary": "", "hasInterior": false, "residentCount": 0},
			"residents": [],
			"currentEvents": [],
			"recentLogs": [],
		},
		"actions": actions,
		"operation": {"requestId": "", "intent": "", "status": "disabled", "submittedAtMsec": 0, "completedAtMsec": 0},
		"error": {"code": "PLACE_FOCUS_ADAPTER_CONTRACT_MISSING", "message": "地点资料暂时不可用。", "retryable": false},
	}


func _stable_label(
	node_name: String,
	rect: Rect2,
	role: String,
	alignment: HorizontalAlignment,
	painted_safe_rect: Rect2 = Rect2(),
	slot_owner: String = "",
) -> Label:
	var label := Label.new()
	label.name = node_name
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_to_group("place_focus_text_slot")
	label.set_meta("gate_id", node_name.to_snake_case())
	label.set_meta("design_rect", rect)
	label.set_meta(
		"painted_safe_rect",
		painted_safe_rect if painted_safe_rect.has_area() else rect,
	)
	label.set_meta(
		"slot_owner",
		slot_owner if not slot_owner.is_empty() else node_name.to_snake_case(),
	)
	label.set_meta("theme_role", role)
	_content.add_child(label)
	_designed_controls.append(label)
	return label


func _stable_rich_label(node_name: String, rect: Rect2) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.name = node_name
	label.position = rect.position
	label.size = rect.size
	label.bbcode_enabled = true
	label.fit_content = false
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_to_group("place_focus_text_slot")
	label.set_meta("gate_id", node_name.to_snake_case())
	label.set_meta("design_rect", rect)
	_content.add_child(label)
	_designed_controls.append(label)
	return label


func _set_feedback_text(copy: String) -> void:
	_feedback.text = "[center]%s[/center]" % copy.replace("[", "［").replace("]", "］")


func _hit_button(node_name: String, rect: Rect2, action_key: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.position = rect.position
	button.size = rect.size
	button.theme_type_variation = &"PlaceFocusRightSubmenuHit"
	# Keep keyboard focus and the full click target without ever exposing the
	# invisible hit rectangle as a yellow outline.
	for state: StringName in [
		&"normal",
		&"disabled",
		&"hover",
		&"pressed",
		&"focus",
	]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_to_group("place_focus_touch_target")
	button.set_meta("gate_id", node_name.to_snake_case())
	button.set_meta("action_key", action_key)
	button.set_meta("design_rect", rect)
	button.set_meta("border_owner", false)
	_content.add_child(button)
	_designed_controls.append(button)
	return button


func _player_reason(reason: String) -> String:
	if reason.is_empty():
		return ""
	return String(DISABLED_REASON_COPY.get(reason, "当前操作不可用"))


func _source_mode() -> String:
	if String(_render_data.get("source", "")) == "adapter_missing":
		return "adapter_missing"
	return "town_ui_adapter" if _adapter != null else "external_validation_fixture"


func _asset_path_for_profile(profile: String) -> String:
	if profile == PROFILE_1080:
		return ASSET_1080
	if profile == PROFILE_720:
		return ASSET_720
	return ""


func _asset_size_for_profile(profile: String) -> Vector2:
	if profile == PROFILE_1080:
		return SIZE_1080
	if profile == PROFILE_720:
		return SIZE_720
	return Vector2.ZERO


func _asset_sha_for_profile(profile: String) -> String:
	if profile == PROFILE_1080:
		return ASSET_1080_SHA256
	if profile == PROFILE_720:
		return ASSET_720_SHA256
	return ""


func _ownership_snapshot() -> Array[Dictionary]:
	return [
		{
			"id": "right_submenu_page_shell_and_static_frames",
			"level": "page_shell_to_operation_frame",
			"owner": "PlaceFocusInputOwner/PlaceFocusRightSubmenuPanel",
			"active": _panel_host.visible,
			"assetId": "ui.place-focus.right-submenu.v8.%s" % _layout_profile,
			"componentType": "TextureRect/page_specific_runtime_raster",
			"childStaticBorderCount": 0,
			"duplicateOwner": false,
		},
		{
			"id": "interaction_state_overlay",
			"level": "operation_control_state_only",
			"owner": "PlaceFocusRightSubmenuHit Button",
			"active": _panel_host.visible,
			"ownsStaticFrame": false,
			"duplicateOwner": false,
		},
		{
			"id": "time_event_and_log_text",
			"level": "dynamic_text_only",
			"owner": (
				"EventTime/EventTitle/EventSummary/"
				+ "LogTitle0/LogTitle1/LogTitle2"
			),
			"active": _panel_host.visible,
			"ownsStaticFrame": false,
			"duplicateOwner": false,
		},
		{
			"id": "event_log_icons_and_arrows",
			"level": "static_icon_and_arrow_slots",
			"owner": "PlaceFocusInputOwner/PlaceFocusRightSubmenuPanel",
			"active": _panel_host.visible,
			"ownsStaticFrame": true,
			"duplicateOwner": false,
		},
	]


func _design_rect_to_global(design_rect: Rect2) -> Rect2:
	if not design_rect.has_area() or not is_instance_valid(_panel_host):
		return Rect2()
	var factor := _panel_host.size.x / DESIGN_SIZE.x
	return Rect2(
		_panel_host.global_position + (design_rect.position * factor).round(),
		(design_rect.size * factor).round(),
	)


func _runtime_guide_node_count() -> int:
	var count := 0
	for node: Node in find_children("*", "CanvasItem", true, false):
		if (
			bool(node.get_meta("capture_only", false))
			or String(node.name).to_lower().contains("guide")
		):
			count += 1
	return count


func _rect_to_array(rect: Rect2) -> Array[float]:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
