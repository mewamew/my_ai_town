class_name IndoorOverlay
extends Control


signal intent_requested(intent: StringName, payload: Dictionary)
signal action_blocked(intent: StringName, reason: String)
signal view_model_rejected(reason: String)

const UI_SIGNALS := preload(
	"res://ui/common/AiTownUiSignals.gd"
)
const UiViewModel = preload("res://ui/common/AiTownUiViewModel.gd")
const MOBILE_UI_PROFILE := preload("res://ui/mobile/MobileUiProfile.gd")

const SCOPE := &"indoor"
const MAIN_MENU_FONT_PATH := (
	"res://assets/ui/startup/fonts/noto_sans_cjk_sc_medium/"
	+ "NotoSansCJKsc-Medium.otf"
)
const PANEL_ASSET_PATH := (
	"res://assets/ui/indoor_overlay/runtime/"
	+ "indoor_observation_panel_640x960.png"
)
const PANEL_TOGGLE_ASSET_PATH := (
	"res://assets/ui/indoor_overlay/runtime_skin_v21/primitives/buttons/"
	+ "indoor_panel_toggle_arrow_right_v21_64x128.png"
)
const SAFE_INSETS_ENV := "AI_TOWN_INDOOR_SAFE_INSETS"
const PANEL_SIZE := Vector2(640.0, 960.0)
const DESKTOP_RIGHT_MARGIN := 40.0
const PANEL_TOGGLE_SIZE := Vector2(64.0, 128.0)
const PANEL_TOGGLE_LOCAL_Y := 416.0
const PANEL_TOGGLE_EDGE_OVERLAP := 8.0
const RESIDENT_VIEWPORT_CAPACITY := 3
const ACTION_DEBOUNCE_MSEC := 250
const RESIDENT_SWIPE_THRESHOLD := 40.0

const INK := Color("4a2e20")
const INK_MUTED := Color("6d5138")
const RETURN_INK := Color("fff2cf")

const LOCATION_IMAGE_RECT := Rect2(65, 36, 90, 90)
const TITLE_RECT := Rect2(171, 36, 402, 44)
const STATUS_RECT := Rect2(179, 93, 230, 25)
const COUNT_RECT := Rect2(518, 93, 55, 25)
const RETURN_RECT := Rect2(76, 880, 512, 62)
const RETURN_TEXT_RECT := Rect2(100, 891, 440, 38)
const RESIDENT_VIEWPORT_RECT := Rect2(47, 157, 542, 280)
const RESIDENT_PORTRAIT_RECTS: Array[Rect2] = [
	Rect2(55, 159, 84, 86),
	Rect2(55, 251, 84, 86),
	Rect2(55, 343, 84, 86),
]
const RESIDENT_NAME_RECTS: Array[Rect2] = [
	Rect2(151, 174, 249, 23),
	Rect2(151, 266, 249, 23),
	Rect2(151, 358, 249, 24),
]
const RESIDENT_ACTION_RECTS: Array[Rect2] = [
	Rect2(151, 209, 404, 24),
	Rect2(151, 302, 404, 23),
	Rect2(151, 394, 404, 24),
]
const RESIDENT_HIT_RECTS: Array[Rect2] = [
	Rect2(48, 157, 538, 88),
	Rect2(48, 250, 538, 88),
	Rect2(48, 342, 538, 88),
]
const EVENT_TIME_RECTS: Array[Rect2] = [
	Rect2(166, 481, 106, 22),
	Rect2(166, 615, 106, 22),
	Rect2(166, 750, 106, 22),
]
const EVENT_BODY_RECTS: Array[Rect2] = [
	Rect2(171, 519, 374, 58),
	Rect2(171, 653, 374, 60),
	Rect2(171, 789, 374, 58),
]
const EVENT_HIT_RECTS: Array[Rect2] = [
	Rect2(150, 463, 408, 120),
	Rect2(150, 597, 408, 124),
	Rect2(150, 732, 408, 123),
]
const EVENT_KINDS: Array[String] = ["action", "dialogue", "important"]
const EVENT_EMPTY_COPY := {
	"action": "暂无公开行动",
	"dialogue": "暂无公开对话",
	"important": "暂无重要事件",
}
const FEEDBACK_COPY := {
	"loading": "正在更新室内观察信息……",
	"rejected": "刚才的请求未被接受",
	"error": "室内观察信息暂时不可用",
}
const SILENT_CODES: Array[String] = [
	"INDOOR_UI_INTERFACE_MISSING",
]

var _adapter: Object
var _view_model: Dictionary = {}
var _render_data: Dictionary = {}
var _last_confirmed_data: Dictionary = {}
var _current_revision := -1
var _available_rect_override := Rect2()
var _available_panes_override: Array[Rect2] = []
var _safe_insets_override := Vector4(-1, -1, -1, -1)
var _last_available_rect := Rect2()
var _layout_profile := "desktop_sidebar"
var _panel_collapsed := false
var _resident_scroll_offset := 0
var _route_resident_scroll_offset := 0
var _route_context: Dictionary = {}
var _residents: Array[Dictionary] = []
var _locally_pending_actions: Dictionary = {}
var _last_intent_dispatch_msec: Dictionary = {}
var _resident_swipe_tracking := false
var _resident_swipe_start := Vector2.ZERO
var _reflow_queued := false

var _panel_root: Control
var _mobile_page_backdrop: TextureRect
var _panel_shell: TextureRect
var _location_image: TextureRect
var _title_label: Label
var _status_label: Label
var _count_label: Label
var _resident_portraits: Array[TextureRect] = []
var _resident_name_labels: Array[Label] = []
var _resident_action_labels: Array[Label] = []
var _resident_buttons: Array[Button] = []
var _resident_scroll_track: TextureRect
var _resident_scroll_end: TextureRect
var _resident_scroll_thumb: TextureRect
var _event_time_labels: Array[Label] = []
var _event_body_labels: Array[Label] = []
var _event_buttons: Array[Button] = []
var _return_button: Button
var _panel_toggle_button: TextureButton
var _feedback_message := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	theme = _create_runtime_theme()
	_build_interface()
	get_viewport().size_changed.connect(_queue_reflow)
	_refresh_from_adapter()
	_render()


func _exit_tree() -> void:
	_disconnect_adapter()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_request_action("returnOutdoor", {})
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_page_down"):
		if scroll_residents(1):
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_page_up"):
		if scroll_residents(-1):
			get_viewport().set_input_as_handled()


func bind_town_ui_adapter(adapter: Object) -> void:
	if _adapter == adapter:
		return
	_disconnect_adapter()
	_adapter = adapter
	_reset_snapshot_state()
	if _adapter != null and _adapter.has_signal("view_model_changed"):
		var callback := Callable(self, "_on_view_model_changed")
		if not _adapter.is_connected("view_model_changed", callback):
			_adapter.connect("view_model_changed", callback)
	if is_node_ready():
		_refresh_from_adapter()
		_render()


func unbind_town_ui_adapter() -> void:
	_disconnect_adapter()
	_adapter = null
	_reset_snapshot_state()


func apply_view_model(view_model: Dictionary) -> bool:
	var issues := UiViewModel.validate(view_model, "室内观察栏")
	if UiViewModel.scope(view_model) != SCOPE:
		issues.append("室内观察栏拒绝非 indoor scope")
	issues.append_array(_validate_indoor_contract(view_model))
	if not issues.is_empty():
		var reason := "\n".join(issues)
		for issue: String in issues:
			push_error(issue)
		view_model_rejected.emit(reason)
		return false

	var incoming_revision := UiViewModel.revision(view_model)
	if _current_revision >= 0 and incoming_revision < _current_revision:
		view_model_rejected.emit(
			"STALE_REVISION_%d_LT_%d" % [
				incoming_revision,
				_current_revision,
			]
		)
		return false

	var incoming_data := UiViewModel.data(view_model)
	var operation_status := String(UiViewModel.operation_status(view_model))
	if (
		operation_status in ["idle", "success", "disabled"]
		and not incoming_data.is_empty()
	):
		_last_confirmed_data = incoming_data.duplicate(true)
	if (
		operation_status in ["loading", "rejected", "error"]
		and not _last_confirmed_data.is_empty()
	):
		_render_data = _last_confirmed_data.duplicate(true)
	else:
		_render_data = incoming_data.duplicate(true)
	if _render_data.is_empty():
		_render_data = _last_confirmed_data.duplicate(true)

	_view_model = view_model.duplicate(true)
	_current_revision = incoming_revision
	_locally_pending_actions.clear()
	_clamp_resident_scroll()
	if is_node_ready():
		_render()
	return true


func current_view_model() -> Dictionary:
	return _view_model.duplicate(true)


func current_revision() -> int:
	return _current_revision


func current_layout_profile() -> String:
	return _layout_profile


func apply_route_payload(payload: Dictionary) -> void:
	_route_context = payload.duplicate(true)
	_panel_collapsed = bool(payload.get("panelCollapsed", false))
	_route_resident_scroll_offset = maxi(
		0,
		int(payload.get("residentScrollOffset", 0)),
	)
	_resident_scroll_offset = _route_resident_scroll_offset


func navigation_state() -> Dictionary:
	var result := _route_context.duplicate(true)
	var location := _render_data.get("location", {}) as Dictionary
	var place_name := String(location.get("placeName", "")).strip_edges()
	var space_id := String(location.get("spaceId", "")).strip_edges()
	if not place_name.is_empty():
		result["placeName"] = place_name
	if not space_id.is_empty():
		result["spaceId"] = space_id
	result["residentScrollOffset"] = _resident_scroll_offset
	result["panelCollapsed"] = _panel_collapsed
	result["entryReason"] = "return_from_resident"
	return result


func set_available_rect(available_rect: Rect2) -> void:
	_available_panes_override.clear()
	_available_rect_override = available_rect
	_queue_reflow()


func clear_available_rect_override() -> void:
	_available_rect_override = Rect2()
	_queue_reflow()


func set_available_panes(panes: Array) -> void:
	_available_panes_override.clear()
	for value: Variant in panes:
		if value is Rect2 and (value as Rect2).has_area():
			_available_panes_override.append(value as Rect2)
	_available_rect_override = Rect2()
	_queue_reflow()


func clear_available_panes_override() -> void:
	_available_panes_override.clear()
	_queue_reflow()


func set_safe_insets(insets: Vector4) -> void:
	_safe_insets_override = Vector4(
		maxf(0.0, insets.x),
		maxf(0.0, insets.y),
		maxf(0.0, insets.z),
		maxf(0.0, insets.w)
	)
	_queue_reflow()


func focus_default() -> void:
	if _panel_collapsed:
		_panel_toggle_button.grab_focus()
		return
	if _return_button.visible and not _return_button.disabled:
		_return_button.grab_focus()
		return
	for button: Button in _event_buttons:
		if button.visible and not button.disabled:
			button.grab_focus()
			return
	for button: Button in _resident_buttons:
		if button.visible and not button.disabled:
			button.grab_focus()
			return


func scroll_residents(delta: int) -> bool:
	var maximum := maxi(0, _residents.size() - RESIDENT_VIEWPORT_CAPACITY)
	if maximum == 0 or delta == 0:
		return false
	var next_offset := clampi(
		_resident_scroll_offset + delta,
		0,
		maximum
	)
	if next_offset == _resident_scroll_offset:
		return false
	_resident_scroll_offset = next_offset
	_render_residents()
	_update_focus_chain()
	return true


func resident_scroll_offset() -> int:
	return _resident_scroll_offset


func runtime_gate_snapshot() -> Dictionary:
	var text_slots: Array[Dictionary] = []
	for node: Node in get_tree().get_nodes_in_group("indoor_text_slot"):
		if not is_ancestor_of(node):
			continue
		var label := node as Label
		if label == null or not label.is_visible_in_tree():
			continue
		var font := label.get_theme_font("font")
		var font_size := label.get_theme_font_size("font_size")
		text_slots.append({
			"id": String(label.get_meta("gate_id", label.name)),
			"text": label.text,
			"rect": _rect_to_array(
				Rect2(label.global_position, label.size)
			),
			"fontPath": MAIN_MENU_FONT_PATH,
			"fontSize": font_size,
			"lineHeight": font.get_height(font_size),
			"textWidth": font.get_string_size(
				label.text,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				font_size
			).x,
			"wrap": label.autowrap_mode != TextServer.AUTOWRAP_OFF,
			"ellipsis": (
				label.text_overrun_behavior
				== TextServer.OVERRUN_TRIM_ELLIPSIS
			),
			"maxLines": label.max_lines_visible,
		})

	var resident_rows: Array[Dictionary] = []
	var visible_ids: Array[String] = []
	for slot_index: int in RESIDENT_VIEWPORT_CAPACITY:
		var data_index := _resident_scroll_offset + slot_index
		if data_index >= _residents.size():
			continue
		var resident := _residents[data_index]
		var resident_id := String(resident.get("residentId", ""))
		visible_ids.append(resident_id)
		resident_rows.append({
			"slot": slot_index,
			"dataIndex": data_index,
			"residentId": resident_id,
			"targetId": String(resident.get("targetId", resident_id)),
			"name": _resident_name_labels[slot_index].text,
			"doing": _resident_action_labels[slot_index].text,
			"portraitPath": String(
				_resident_portraits[slot_index].get_meta(
					"source_path",
					""
				)
			),
			"portraitVisible": _resident_portraits[
				slot_index
			].visible,
			"clickable": (
				_resident_buttons[slot_index].visible
				and not _resident_buttons[slot_index].disabled
			),
			"rect": _rect_to_array(
				Rect2(
					_resident_buttons[slot_index].global_position,
					_resident_buttons[slot_index].size
				)
			),
		})

	var event_slots: Array[Dictionary] = []
	var events_by_kind := _normalized_events_by_kind()
	for index: int in EVENT_KINDS.size():
		var event := events_by_kind.get(
			EVENT_KINDS[index],
			{},
		) as Dictionary
		event_slots.append({
			"kind": EVENT_KINDS[index],
			"eventId": String(event.get("eventId", "")),
			"time": _event_time_labels[index].text,
			"body": _event_body_labels[index].text,
			"clickable": (
				_event_buttons[index].visible
				and not _event_buttons[index].disabled
			),
			"rect": _rect_to_array(
				Rect2(
					_event_buttons[index].global_position,
					_event_buttons[index].size
				)
			),
			"timeRect": _rect_to_array(
				Rect2(
					_event_time_labels[index].global_position,
					_event_time_labels[index].size
				)
			),
			"bodyRect": _rect_to_array(
				Rect2(
					_event_body_labels[index].global_position,
					_event_body_labels[index].size
				)
			),
		})

	var maximum_scroll := maxi(
		0,
		_residents.size() - RESIDENT_VIEWPORT_CAPACITY
	)
	var location := _render_data.get("location", {}) as Dictionary
	var operation := UiViewModel.operation(_view_model)
	return {
		"scope": String(_view_model.get("scope", "")),
		"status": String(_view_model.get("status", "")),
		"revision": _current_revision,
		"operationStatus": String(operation.get("status", "")),
		"sourceMode": "town_ui_adapter",
		"formalReady": bool(
			_render_data.get(
				"formalReady",
				_view_model.get("formalReady", false)
			)
		),
		"layoutProfile": _layout_profile,
		"availableRect": _rect_to_array(_last_available_rect),
		"panelRect": _rect_to_array(
			Rect2(_panel_root.global_position, _panel_root.size * _panel_root.scale)
		),
		"runtimeRevision": "ui.indoor-observation.runtime-v18",
		"runtimeStatus": "formal_approved",
		"panelAsset": PANEL_ASSET_PATH,
		"panelMouseFilter": _panel_root.mouse_filter,
		"rootMouseFilter": mouse_filter,
		"panelCollapsed": _panel_collapsed,
		"collapsedVisibleWidth": (
			(PANEL_TOGGLE_SIZE.x - PANEL_TOGGLE_EDGE_OVERLAP)
			* _panel_root.scale.x
		),
		"panelToggleAsset": PANEL_TOGGLE_ASSET_PATH,
		"panelToggleRect": _rect_to_array(
			Rect2(
				_panel_toggle_button.global_position,
				_panel_toggle_button.size * _panel_toggle_button.scale,
			)
		),
		"panelToggleOutsidePanel": true,
		"panelToggleDirection": (
			"left_expand" if _panel_collapsed else "right_collapse"
		),
		"worldInputOutsidePanelPasses": (
			mouse_filter == Control.MOUSE_FILTER_IGNORE
		),
		"worldInputInsidePanelBlocked": (
			_panel_root.mouse_filter == Control.MOUSE_FILTER_STOP
		),
		"fontPath": MAIN_MENU_FONT_PATH,
		"locationTitle": _title_label.text,
		"locationSubtitle": _status_label.text,
		"locationImageVisible": _location_image.visible,
		"residentCount": _residents.size(),
		"residentCountText": _count_label.text,
		"residentViewportCapacity": RESIDENT_VIEWPORT_CAPACITY,
		"residentScrollOffset": _resident_scroll_offset,
		"residentScrollMaximum": maximum_scroll,
		"residentScrollbarVisible": _resident_scroll_track.visible,
		"residentScrollbarThumbRect": _rect_to_array(
			Rect2(
				_resident_scroll_thumb.global_position,
				_resident_scroll_thumb.size
			)
		),
		"visibleResidentIds": visible_ids,
		"residentRows": resident_rows,
		"eventSlots": event_slots,
		"feedbackVisible": not _feedback_message.is_empty(),
		"feedbackMessage": _feedback_message,
		"returnOutdoor": {
			"visible": _return_button.visible,
			"disabled": _return_button.disabled,
			"text": _return_button.text,
			"intent": String(
				UiViewModel.action(
					_view_model,
					"returnOutdoor"
				).get("intent", "")
			),
			"rect": _rect_to_array(
				Rect2(_return_button.global_position, _return_button.size)
			),
		},
		"textSlots": text_slots,
		"touchTargets": _touch_target_snapshot(),
		"focusChain": _focus_chain_ids(),
		"ownership": _ownership_snapshot(),
		"genericStyleboxCount": _generic_stylebox_count(),
		"activeCapabilities": [
			"locationIdentity",
			"residentRoute",
			"publicObservationFeed",
			"eventFocus",
			"returnOutdoor",
			"panelCollapse",
		],
		"excludedCapabilities": [
			"propCards",
			"doorOperations",
			"interactionPrompts",
			"activateInteraction",
			"inspectObject",
			"enterPlace",
		],
		"worldReads": [],
	}


func _build_interface() -> void:
	if MOBILE_UI_PROFILE.is_mobile_runtime():
		_mobile_page_backdrop = TextureRect.new()
		_mobile_page_backdrop.name = "IndoorObservationMobileBackdrop"
		_mobile_page_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_mobile_page_backdrop.texture = load(PANEL_ASSET_PATH) as Texture2D
		_mobile_page_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_mobile_page_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_mobile_page_backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_mobile_page_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mobile_page_backdrop.modulate = Color(0.68, 0.68, 0.68)
		add_child(_mobile_page_backdrop)
	_panel_root = Control.new()
	_panel_root.name = "ObservationPanel"
	_panel_root.size = PANEL_SIZE
	_panel_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel_root)

	_panel_shell = TextureRect.new()
	_panel_shell.name = "ObservationPanelShell"
	_panel_shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_shell.texture = load(PANEL_ASSET_PATH) as Texture2D
	_panel_shell.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_panel_shell.stretch_mode = TextureRect.STRETCH_KEEP
	_panel_shell.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_panel_shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_shell.set_meta(
		"asset_id",
		"ui.indoor-observation.runtime-v18.page-shell"
	)
	_panel_shell.set_meta(
		"formal_status",
		"approved"
	)
	_panel_shell.set_meta("ownership_level", "page_shell")
	_panel_shell.set_meta("border_owner", true)
	_panel_shell.set_meta("component_type", "TextureRect")
	_panel_root.add_child(_panel_shell)

	_location_image = TextureRect.new()
	_location_image.name = "LocationImage"
	_place_control(_location_image, LOCATION_IMAGE_RECT)
	_location_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_location_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_location_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_location_image.clip_contents = true
	_location_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_location_image.set_meta("border_owner", false)
	_panel_root.add_child(_location_image)

	_title_label = _make_label(
		"PlaceTitle",
		&"IndoorObservationTitle",
		"place_title",
		TITLE_RECT,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_status_label = _make_label(
		"PlaceStatus",
		&"IndoorObservationStatus",
		"place_status",
		STATUS_RECT,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_count_label = _make_label(
		"ResidentCount",
		&"IndoorObservationCount",
		"resident_count",
		COUNT_RECT,
		HORIZONTAL_ALIGNMENT_CENTER
	)

	for slot_index: int in RESIDENT_VIEWPORT_CAPACITY:
		var portrait := TextureRect.new()
		portrait.name = "ResidentPortrait%d" % (slot_index + 1)
		_place_control(portrait, RESIDENT_PORTRAIT_RECTS[slot_index])
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.set_meta("border_owner", false)
		_panel_root.add_child(portrait)
		_resident_portraits.append(portrait)

		var name_label := _make_label(
			"ResidentName%d" % (slot_index + 1),
			&"IndoorObservationResidentName",
			"resident_%d_name" % (slot_index + 1),
			RESIDENT_NAME_RECTS[slot_index],
			HORIZONTAL_ALIGNMENT_LEFT
		)
		_resident_name_labels.append(name_label)
		var action_label := _make_label(
			"ResidentAction%d" % (slot_index + 1),
			&"IndoorObservationResidentAction",
			"resident_%d_action" % (slot_index + 1),
			RESIDENT_ACTION_RECTS[slot_index],
			HORIZONTAL_ALIGNMENT_LEFT
		)
		_resident_action_labels.append(action_label)

		var hit := Button.new()
		hit.name = "ResidentHit%d" % (slot_index + 1)
		hit.theme_type_variation = &"IndoorObservationResidentButton"
		hit.text = ""
		hit.focus_mode = Control.FOCUS_ALL
		hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		hit.add_to_group("indoor_touch_target")
		hit.set_meta("gate_id", "resident_%d" % (slot_index + 1))
		hit.set_meta("border_owner", false)
		_place_control(hit, RESIDENT_HIT_RECTS[slot_index])
		hit.pressed.connect(_on_resident_pressed.bind(slot_index))
		hit.gui_input.connect(_on_resident_scroll_input)
		_panel_root.add_child(hit)
		_resident_buttons.append(hit)

	_build_resident_scrollbar()

	for event_index: int in EVENT_KINDS.size():
		var time_label := _make_label(
			"EventTime%d" % (event_index + 1),
			&"IndoorObservationEventTime",
			"event_%d_time" % (event_index + 1),
			EVENT_TIME_RECTS[event_index],
			HORIZONTAL_ALIGNMENT_CENTER
		)
		_event_time_labels.append(time_label)
		var body_label := _make_label(
			"EventBody%d" % (event_index + 1),
			&"IndoorObservationEventBody",
			"event_%d_body" % (event_index + 1),
			EVENT_BODY_RECTS[event_index],
			HORIZONTAL_ALIGNMENT_LEFT
		)
		body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body_label.max_lines_visible = 2
		body_label.text_overrun_behavior = (
			TextServer.OVERRUN_TRIM_ELLIPSIS
		)
		_event_body_labels.append(body_label)

		var event_hit := Button.new()
		event_hit.name = "EventHit%d" % (event_index + 1)
		event_hit.theme_type_variation = &"IndoorObservationEventButton"
		event_hit.text = ""
		event_hit.focus_mode = Control.FOCUS_ALL
		event_hit.mouse_default_cursor_shape = (
			Control.CURSOR_POINTING_HAND
		)
		event_hit.add_to_group("indoor_touch_target")
		event_hit.set_meta(
			"gate_id",
			"event_%d" % (event_index + 1),
		)
		event_hit.set_meta("border_owner", false)
		_place_control(event_hit, EVENT_HIT_RECTS[event_index])
		event_hit.pressed.connect(
			_on_event_pressed.bind(event_index)
		)
		_panel_root.add_child(event_hit)
		_event_buttons.append(event_hit)

	_return_button = Button.new()
	_return_button.name = "ReturnOutdoor"
	_return_button.theme_type_variation = &"IndoorObservationReturnButton"
	_return_button.text = "返回户外"
	_return_button.focus_mode = Control.FOCUS_ALL
	_return_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_return_button.add_to_group("indoor_touch_target")
	_return_button.set_meta("gate_id", "return_outdoor")
	_return_button.set_meta("accessibility_label", "返回户外")
	_return_button.set_meta("border_owner", false)
	_place_control(_return_button, RETURN_RECT)
	_return_button.pressed.connect(
		_request_action.bind("returnOutdoor", {})
	)
	_panel_root.add_child(_return_button)

	_panel_toggle_button = TextureButton.new()
	_panel_toggle_button.name = "PanelToggle"
	_panel_toggle_button.texture_normal = load(
		PANEL_TOGGLE_ASSET_PATH
	) as Texture2D
	_panel_toggle_button.ignore_texture_size = true
	_panel_toggle_button.stretch_mode = (
		TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	)
	_panel_toggle_button.size = PANEL_TOGGLE_SIZE
	_panel_toggle_button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_panel_toggle_button.focus_mode = Control.FOCUS_ALL
	_panel_toggle_button.mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND
	)
	_panel_toggle_button.add_to_group("indoor_touch_target")
	_panel_toggle_button.set_meta("gate_id", "toggle_panel")
	_panel_toggle_button.set_meta(
		"component_type",
		"page_owned_external_texture_toggle",
	)
	_panel_toggle_button.set_meta(
		"asset_id",
		"ui.indoor-observation.panel-toggle.external-arrow.v21",
	)
	_panel_toggle_button.set_meta("border_owner", false)
	_panel_toggle_button.pressed.connect(_on_panel_toggle_pressed)
	_panel_toggle_button.z_index = 30
	add_child(_panel_toggle_button)


func _build_resident_scrollbar() -> void:
	var panel_texture := _panel_shell.texture
	_resident_scroll_track = _atlas_piece(
		"ResidentScrollTrack",
		panel_texture,
		Rect2i(588, 494, 8, 350),
		Rect2(595, 177, 8, 238)
	)
	_resident_scroll_end = _atlas_piece(
		"ResidentScrollEnd",
		panel_texture,
		Rect2i(582, 849, 23, 18),
		Rect2(588, 414, 21, 17)
	)
	_resident_scroll_thumb = _atlas_piece(
		"ResidentScrollThumb",
		panel_texture,
		Rect2i(582, 473, 23, 20),
		Rect2(588, 174, 21, 18)
	)
	for piece: TextureRect in [
		_resident_scroll_track,
		_resident_scroll_end,
		_resident_scroll_thumb,
	]:
		piece.set_meta(
			"asset_id",
			"ui.indoor-observation.runtime-v18.scrollbar-region"
		)
		piece.set_meta("ownership_level", "scroll_affordance")
		piece.set_meta("border_owner", false)
		_panel_root.add_child(piece)


func _render() -> void:
	if _view_model.is_empty():
		return
	var location := _render_data.get("location", {}) as Dictionary
	_title_label.text = String(
		location.get(
			"title",
			location.get("placeName", "室内观察")
		)
	)
	_status_label.text = String(
		location.get(
			"subtitle",
			location.get("placeTypeLabel", "")
		)
	)
	_status_label.tooltip_text = ""
	_render_location_image(location)
	_residents = _resident_values(_render_data)
	_clamp_resident_scroll()
	_count_label.text = "%d 人" % _residents.size()
	_render_residents()
	_render_events()
	_render_return_action()
	MOBILE_UI_PROFILE.apply_mobile_typography(self, 21, 3, 32)
	_apply_panel_presentation_state()
	_apply_responsive_layout()
	_update_focus_chain()


func _render_location_image(location: Dictionary) -> void:
	var path := String(
		location.get(
			"imagePath",
			location.get("thumbnailPath", "")
		)
	)
	_location_image.texture = _texture_from_path_and_region(
		path,
		location.get("imageRegion", [])
	)
	_location_image.visible = _location_image.texture != null
	_location_image.set_meta("source_path", path)


func _render_residents() -> void:
	if _resident_buttons.is_empty():
		return
	for slot_index: int in RESIDENT_VIEWPORT_CAPACITY:
		var data_index := _resident_scroll_offset + slot_index
		var has_resident := data_index < _residents.size()
		var portrait := _resident_portraits[slot_index]
		var name_label := _resident_name_labels[slot_index]
		var action_label := _resident_action_labels[slot_index]
		var button := _resident_buttons[slot_index]
		portrait.visible = has_resident
		name_label.visible = has_resident
		action_label.visible = has_resident
		button.visible = has_resident
		if not has_resident:
			portrait.texture = null
			portrait.set_meta("source_path", "")
			name_label.text = ""
			action_label.text = ""
			button.disabled = true
			continue
		var resident := _residents[data_index]
		var resident_id := String(resident.get("residentId", ""))
		name_label.text = String(
			resident.get(
				"name",
				resident.get("residentName", "居民")
			)
		)
		action_label.text = _resident_doing_copy(resident)
		var portrait_path := _resident_portrait_path(resident)
		portrait.texture = _texture_from_path_and_region(
			portrait_path,
			null
			if _resident_has_full_portrait(resident)
			else resident.get("portraitRegion", [0, 0, 64, 80])
		)
		portrait.visible = portrait.texture != null
		portrait.set_meta("source_path", portrait_path)
		button.disabled = (
			not bool(resident.get("canOpen", true))
			or not _action_enabled("focusTarget")
		)
		button.tooltip_text = (
			"打开%s的居民菜单" % name_label.text
			if not button.disabled
			else ""
		)
		button.set_meta("resident_id", resident_id)
		button.set_meta(
			"target_id",
			String(resident.get("targetId", resident_id))
		)

	var show_scrollbar := (
		_residents.size() > RESIDENT_VIEWPORT_CAPACITY
	)
	_resident_scroll_track.visible = show_scrollbar
	_resident_scroll_end.visible = show_scrollbar
	_resident_scroll_thumb.visible = show_scrollbar
	if show_scrollbar:
		var maximum := float(
			_residents.size() - RESIDENT_VIEWPORT_CAPACITY
		)
		var progress := float(_resident_scroll_offset) / maximum
		_resident_scroll_thumb.position.y = lerpf(174.0, 394.0, progress)


func _render_events() -> void:
	var events_by_kind := _normalized_events_by_kind()
	_feedback_message = _status_feedback_message()
	for index: int in EVENT_KINDS.size():
		var kind := EVENT_KINDS[index]
		var event := events_by_kind.get(kind, {}) as Dictionary
		var event_id := String(event.get("eventId", ""))
		_event_time_labels[index].text = String(
			event.get("timeLabel", "—")
		)
		_event_body_labels[index].text = String(
			event.get(
				"summary",
				event.get(
					"text",
					EVENT_EMPTY_COPY.get(kind, "")
				)
			)
		)
		var button := _event_buttons[index]
		button.visible = not event.is_empty()
		button.disabled = (
			event_id.is_empty()
			or not _action_enabled("focusEvent")
		)
		button.focus_mode = (
			Control.FOCUS_NONE
			if button.disabled
			else Control.FOCUS_ALL
		)
		button.mouse_default_cursor_shape = (
			Control.CURSOR_ARROW
			if button.disabled
			else Control.CURSOR_POINTING_HAND
		)
		button.tooltip_text = (
			"定位这条室内事件"
			if not button.disabled
			else ""
		)
		button.set_meta("event_id", event_id)
	if not _feedback_message.is_empty():
		# Keep the confirmed observation feed visible on loading/rejection.
		# The compact location-status slot owns local operation feedback.
		_status_label.text = _feedback_message
		_status_label.tooltip_text = _feedback_message


func _render_return_action() -> void:
	var action := UiViewModel.action(_view_model, "returnOutdoor")
	_return_button.text = String(action.get("label", "返回户外"))
	_return_button.disabled = not _action_enabled("returnOutdoor")
	var disabled_reason := UiViewModel.disabled_reason(action)
	_return_button.tooltip_text = (
		""
		if not _return_button.disabled
		else (
			"化身模式请走到室内门口离开"
			if disabled_reason == "PHYSICAL_EXIT_REQUIRED"
			else UiViewModel.player_reason(disabled_reason)
		)
	)
	_return_button.mouse_default_cursor_shape = (
		Control.CURSOR_ARROW
		if _return_button.disabled
		else Control.CURSOR_POINTING_HAND
	)


func _on_panel_toggle_pressed() -> void:
	_panel_collapsed = not _panel_collapsed
	if not _panel_collapsed:
		_render()
	else:
		_apply_panel_presentation_state()
		_apply_responsive_layout()
		_update_focus_chain()
	_panel_toggle_button.grab_focus()


func _apply_panel_presentation_state() -> void:
	_panel_toggle_button.flip_h = _panel_collapsed
	_panel_toggle_button.tooltip_text = (
		"展开室内观察面板" if _panel_collapsed else "收起室内观察面板"
	)
	_panel_toggle_button.set_meta(
		"accessibility_label",
		_panel_toggle_button.tooltip_text,
	)
	for button: Button in _resident_buttons:
		button.focus_mode = (
			Control.FOCUS_NONE
			if _panel_collapsed or button.disabled
			else Control.FOCUS_ALL
		)
	for button: Button in _event_buttons:
		button.focus_mode = (
			Control.FOCUS_NONE
			if _panel_collapsed or button.disabled
			else Control.FOCUS_ALL
		)
	_return_button.focus_mode = (
		Control.FOCUS_NONE
		if _panel_collapsed or _return_button.disabled
		else Control.FOCUS_ALL
	)
	_panel_toggle_button.focus_mode = Control.FOCUS_ALL


func _normalized_events_by_kind() -> Dictionary:
	var result := {}
	var feed_value: Variant = _render_data.get(
		"observationFeed",
		_render_data.get("publicEvents", [])
	)
	if feed_value is Array:
		for value: Variant in feed_value as Array:
			if not value is Dictionary:
				continue
			var item := (value as Dictionary).duplicate(true)
			var kind := _normalized_event_kind(
				String(item.get("kind", item.get("type", "")))
			)
			if not kind.is_empty() and not result.has(kind):
				result[kind] = item

	var event_focus := _render_data.get("eventFocus", {}) as Dictionary
	if (
		bool(event_focus.get("active", false))
		and not result.has("important")
	):
		result["important"] = {
			"eventId": String(event_focus.get("eventId", "")),
			"kind": "important",
			"timeLabel": String(event_focus.get("timeLabel", "—")),
			"summary": String(
				event_focus.get(
					"summary",
					event_focus.get("title", "重要事件")
				)
			),
		}
	return result


func _status_feedback_message() -> String:
	var current_data := UiViewModel.data(_view_model)
	var feedback := current_data.get("feedback", {}) as Dictionary
	var feedback_code := String(feedback.get("code", ""))
	var operation_status := String(UiViewModel.operation_status(_view_model))
	var error_value: Variant = _view_model.get("error", null)
	var error := (
		error_value as Dictionary
		if error_value is Dictionary
		else {}
	)
	var error_code := String(error.get("code", ""))
	if (
		SILENT_CODES.has(feedback_code)
		or SILENT_CODES.has(error_code)
	):
		return ""
	var scene_load := current_data.get(
		"sceneLoad",
		_render_data.get("sceneLoad", {})
	) as Dictionary
	var scene_status := String(scene_load.get("status", "ready"))
	if scene_status == "loading":
		return String(
			scene_load.get("progressLabel", "正在载入室内观察信息……")
		)
	if scene_status in ["failed", "error"]:
		return UiViewModel.public_operation_error_message(
			error,
			"室内观察信息暂时不可用",
		)
	if operation_status in ["loading", "rejected", "error"]:
		var message := String(feedback.get("message", ""))
		if not message.is_empty():
			return message
		if not error.is_empty():
			return UiViewModel.public_operation_error_message(
				error,
				"室内操作没有完成，请稍后重试",
			)
		return String(FEEDBACK_COPY.get(operation_status, ""))
	if operation_status == "success":
		return String(feedback.get("message", ""))
	return ""


func _on_resident_pressed(slot_index: int) -> void:
	var data_index := _resident_scroll_offset + slot_index
	if data_index >= _residents.size():
		return
	var resident := _residents[data_index]
	var resident_id := String(resident.get("residentId", ""))
	var target_id := String(resident.get("targetId", resident_id))
	_request_action(
		"focusTarget",
		{
			"residentId": resident_id,
			"targetType": "resident",
			"targetId": target_id,
		}
	)


func _on_event_pressed(event_index: int) -> void:
	if event_index < 0 or event_index >= EVENT_KINDS.size():
		return
	var event := (
		_normalized_events_by_kind().get(
			EVENT_KINDS[event_index],
			{},
		) as Dictionary
	)
	var event_id := String(event.get("eventId", ""))
	if event_id.is_empty():
		return
	_request_action("focusEvent", {"eventId": event_id})


func _on_resident_scroll_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_resident_swipe_tracking = true
			_resident_swipe_start = touch.position
			return
		if not _resident_swipe_tracking:
			return
		_resident_swipe_tracking = false
		var delta_y := touch.position.y - _resident_swipe_start.y
		if absf(delta_y) >= RESIDENT_SWIPE_THRESHOLD:
			# Consume a real swipe even when already at the first/last page;
			# otherwise the release can fall through to the resident Button and
			# accidentally focus a resident at the edge of the list.
			scroll_residents(-1 if delta_y > 0.0 else 1)
			get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if scroll_residents(1):
			get_viewport().set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		if scroll_residents(-1):
			get_viewport().set_input_as_handled()


func _request_action(action_key: String, payload: Dictionary) -> bool:
	var action := UiViewModel.action(_view_model, action_key)
	var intent := StringName(action.get("intent", ""))
	var enabled := _action_enabled(action_key)
	var reason := UiViewModel.disabled_reason(action)
	var now_msec := Time.get_ticks_msec()
	var last_dispatch_msec := int(
		_last_intent_dispatch_msec.get(
			action_key,
			-ACTION_DEBOUNCE_MSEC
		)
	)
	if (
		_locally_pending_actions.has(action_key)
		or now_msec - last_dispatch_msec < ACTION_DEBOUNCE_MSEC
	):
		_show_blocked_reason("REQUEST_ALREADY_SUBMITTED")
		action_blocked.emit(intent, "REQUEST_ALREADY_SUBMITTED")
		return false
	if not enabled or intent == &"":
		_show_blocked_reason(
			reason if not reason.is_empty() else "ACTION_DISABLED"
		)
		action_blocked.emit(
			intent,
			reason if not reason.is_empty() else "ACTION_DISABLED"
		)
		return false
	var envelope := payload.duplicate(true)
	var location := _render_data.get("location", {}) as Dictionary
	var space_id := String(location.get("spaceId", ""))
	if not space_id.is_empty():
		envelope["spaceId"] = space_id
	envelope["revision"] = _current_revision
	_locally_pending_actions[action_key] = true
	_last_intent_dispatch_msec[action_key] = now_msec
	if _adapter != null and _adapter.has_method("dispatch"):
		var dispatch_result: Variant = _adapter.call(
			"dispatch",
			str(intent),
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
			_show_blocked_reason(dispatch_reason)
			action_blocked.emit(intent, dispatch_reason)
			return false
	# The host may replace this page when a resident route opens. Submit the
	# authoritative selection first so the route transition cannot cancel it.
	intent_requested.emit(intent, envelope.duplicate(true))
	return true


func _show_blocked_reason(reason: String) -> void:
	var copy := (
		"化身模式请走到室内门口离开"
		if reason == "PHYSICAL_EXIT_REQUIRED"
		else UiViewModel.player_reason(reason)
	)
	if copy.is_empty():
		copy = "当前操作暂不可用"
	_feedback_message = copy
	if _status_label != null:
		_status_label.text = copy
		_status_label.tooltip_text = copy


func _action_enabled(action_key: String) -> bool:
	return (
		UiViewModel.operation_status(_view_model) != &"loading"
		and UiViewModel.action_enabled(
			UiViewModel.action(_view_model, action_key)
		)
	)


func _update_focus_chain() -> void:
	var controls: Array[Control] = []
	if _panel_collapsed:
		controls.append(_panel_toggle_button)
	else:
		if _return_button.visible and not _return_button.disabled:
			controls.append(_return_button)
		for button: Button in _event_buttons:
			if button.visible and not button.disabled:
				controls.append(button)
		for button: Button in _resident_buttons:
			if button.visible and not button.disabled:
				controls.append(button)
		controls.append(_panel_toggle_button)
	if controls.is_empty():
		return
	for index: int in controls.size():
		var control := controls[index]
		var next := controls[(index + 1) % controls.size()]
		var previous := controls[
			(index - 1 + controls.size()) % controls.size()
		]
		control.focus_next = next.get_path()
		control.focus_previous = previous.get_path()


func _focus_chain_ids() -> Array[String]:
	var result: Array[String] = []
	if _panel_collapsed:
		result.append("togglePanel")
		return result
	if _return_button.visible and not _return_button.disabled:
		result.append("returnOutdoor")
	for button: Button in _event_buttons:
		if button.visible and not button.disabled:
			result.append(
				"event:%s" % String(
					button.get_meta("event_id", "")
				)
			)
	for button: Button in _resident_buttons:
		if button.visible and not button.disabled:
			result.append(
				"resident:%s" % String(
					button.get_meta("resident_id", "")
				)
			)
	result.append("togglePanel")
	return result


func _apply_responsive_layout() -> void:
	if _panel_root == null:
		return
	var available := _available_rect()
	_last_available_rect = available
	if not available.has_area():
		return
	var scale_factor := minf(
		1.0,
		minf(
			available.size.x / PANEL_SIZE.x,
			available.size.y / PANEL_SIZE.y
		)
	)
	if MOBILE_UI_PROFILE.is_mobile_runtime():
		# Mobile observation replaces the map view. Scale the approved page to the
		# full height and center it; the host page blocks the remaining margins.
		scale_factor = minf(
			available.size.x / PANEL_SIZE.x,
			available.size.y / PANEL_SIZE.y,
		)
	_layout_profile = (
		"desktop_sidebar"
		if is_equal_approx(scale_factor, 1.0)
		else "scaled_sidebar"
	)
	_panel_root.scale = Vector2.ONE * scale_factor
	_panel_toggle_button.scale = Vector2.ONE * scale_factor
	var panel_display_size := PANEL_SIZE * scale_factor
	var right_margin := minf(
		DESKTOP_RIGHT_MARGIN,
		maxf(0.0, available.size.x - panel_display_size.x)
	)
	if MOBILE_UI_PROFILE.is_mobile_runtime():
		right_margin = maxf(0.0, (available.size.x - panel_display_size.x) * 0.5)
	var expanded_position := Vector2(
		available.end.x - panel_display_size.x - right_margin,
		available.position.y
		+ maxf(0.0, (available.size.y - panel_display_size.y) * 0.5)
	)
	_panel_root.position = (
		Vector2(available.end.x, expanded_position.y)
		if _panel_collapsed
		else expanded_position
	)
	_panel_toggle_button.position = Vector2(
		_panel_root.position.x
		- (PANEL_TOGGLE_SIZE.x - PANEL_TOGGLE_EDGE_OVERLAP)
		* scale_factor,
		_panel_root.position.y + PANEL_TOGGLE_LOCAL_Y * scale_factor,
	)


func _available_rect() -> Rect2:
	if not _available_panes_override.is_empty():
		var selected := _available_panes_override[0]
		for pane: Rect2 in _available_panes_override:
			if pane.end.x > selected.end.x:
				selected = pane
		return _apply_safe_insets(selected)
	if _available_rect_override.has_area():
		return _apply_safe_insets(_available_rect_override)
	return _apply_safe_insets(
		Rect2(Vector2.ZERO, Vector2(get_viewport_rect().size))
	)


func _apply_safe_insets(rect: Rect2) -> Rect2:
	var insets := _safe_insets()
	return Rect2(
		rect.position + Vector2(insets.x, insets.y),
		Vector2(
			maxf(0.0, rect.size.x - insets.x - insets.z),
			maxf(0.0, rect.size.y - insets.y - insets.w)
		)
	)


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
	return Vector4(
		maxf(0.0, float(parts[0])),
		maxf(0.0, float(parts[1])),
		maxf(0.0, float(parts[2])),
		maxf(0.0, float(parts[3]))
	)


func _queue_reflow() -> void:
	if _reflow_queued:
		return
	_reflow_queued = true
	call_deferred("_apply_queued_reflow")


func _apply_queued_reflow() -> void:
	_reflow_queued = false
	if is_node_ready():
		_apply_responsive_layout()


func _validate_indoor_contract(
	view_model: Dictionary
) -> PackedStringArray:
	var issues := PackedStringArray()
	var data_value: Variant = view_model.get("data", {})
	if not data_value is Dictionary:
		issues.append("室内观察栏.data 必须是 Dictionary")
		return issues
	var data := data_value as Dictionary
	for key: String in [
		"location",
		"sceneLoad",
		"residentTargets",
		"observationFeed",
	]:
		if not data.has(key):
			issues.append("室内观察栏.data 缺少 %s" % key)
	if not issues.is_empty():
		return issues
	if not data.get("location") is Dictionary:
		issues.append("室内观察栏.data.location 必须是 Dictionary")
	if not data.get("sceneLoad") is Dictionary:
		issues.append("室内观察栏.data.sceneLoad 必须是 Dictionary")
	if not data.get("residentTargets") is Array:
		issues.append(
			"室内观察栏.data.residentTargets 必须是 Array"
		)
	else:
		for value: Variant in data.get("residentTargets", []) as Array:
			if not value is Dictionary:
				issues.append("室内观察栏居民项必须是 Dictionary")
				continue
			var resident := value as Dictionary
			if String(resident.get("residentId", "")).is_empty():
				issues.append("室内观察栏居民项缺少稳定 residentId")
	if not data.get("observationFeed") is Array:
		issues.append(
			"室内观察栏.data.observationFeed 必须是 Array"
		)
	else:
		var observed_kinds := {}
		for value: Variant in data.get("observationFeed", []) as Array:
			if not value is Dictionary:
				issues.append("室内观察栏公开观察项必须是 Dictionary")
				continue
			var observation := value as Dictionary
			var kind := String(observation.get("kind", ""))
			if kind not in EVENT_KINDS:
				issues.append(
					"室内观察栏公开观察项 kind 无效：%s" % kind
				)
				continue
			if observed_kinds.has(kind):
				issues.append(
					"室内观察栏公开观察项 kind 重复：%s" % kind
				)
			observed_kinds[kind] = true
			if String(observation.get("summary", "")).strip_edges().is_empty():
				issues.append(
					"室内观察栏公开观察项 %s 缺少摘要" % kind
				)
	var actions_value: Variant = view_model.get("actions", {})
	if not actions_value is Dictionary:
		issues.append("室内观察栏.actions 必须是 Dictionary")
		return issues
	var actions := actions_value as Dictionary
	for key: String in ["returnOutdoor", "focusTarget", "focusEvent"]:
		if not actions.has(key):
			issues.append("室内观察栏.actions 缺少 %s" % key)
			continue
		var action_value: Variant = actions.get(key)
		if not action_value is Dictionary:
			issues.append(
				"室内观察栏.actions.%s 必须是 Dictionary" % key
			)
			continue
		var action := action_value as Dictionary
		if String(action.get("intent", "")).is_empty():
			issues.append(
				"室内观察栏.actions.%s.intent 必须非空" % key
			)
		if typeof(action.get("enabled", true)) != TYPE_BOOL:
			issues.append(
				"室内观察栏.actions.%s.enabled 必须是布尔值" % key
			)
	return issues


func _refresh_from_adapter() -> void:
	if _adapter == null or not _adapter.has_method("get_view_model"):
		apply_view_model(_adapter_missing_view_model())
		return
	var snapshot: Variant = _adapter.call("get_view_model", str(SCOPE))
	if snapshot is Dictionary and not (snapshot as Dictionary).is_empty():
		if not apply_view_model(snapshot as Dictionary):
			apply_view_model(_adapter_missing_view_model())
	else:
		apply_view_model(_adapter_missing_view_model())


func _on_view_model_changed(
	scope_value: Variant,
	view_model: Dictionary
) -> void:
	if StringName(scope_value) == SCOPE:
		apply_view_model(view_model)


func _disconnect_adapter() -> void:
	UI_SIGNALS.disconnect_view_model(
		_adapter,
		Callable(self, "_on_view_model_changed"),
	)


func _adapter_missing_view_model() -> Dictionary:
	return {
		"scope": "indoor",
		"status": "disabled",
		"revision": 0,
		"data": {
			"capabilityMode": "placeholder",
			"source": "town_ui_adapter_missing_scope",
			"formalReady": false,
			"location": {
				"spaceId": "",
				"placeName": "室内观察",
				"title": "室内观察",
				"subtitle": "",
				"imagePath": "",
			},
			"sceneLoad": {
				"status": "disabled",
				"progressLabel": "",
			},
			"residentTargets": [],
			"observationFeed": [],
		},
		"actions": {
			"returnOutdoor": {
				"intent": "indoor.return_outdoor",
				"enabled": false,
				"disabledReason": "INDOOR_UI_INTERFACE_MISSING",
			},
			"focusTarget": {
				"intent": "indoor.focus_target",
				"enabled": false,
				"disabledReason": "INDOOR_UI_INTERFACE_MISSING",
			},
			"focusEvent": {
				"intent": "indoor.focus_event",
				"enabled": false,
				"disabledReason": "INDOOR_UI_INTERFACE_MISSING",
			},
		},
		"operation": {
			"requestId": "",
			"intent": "",
			"status": "disabled",
		},
		"error": {
			"code": "INDOOR_UI_INTERFACE_MISSING",
			"message": "",
			"retryable": false,
		},
	}


func _reset_snapshot_state() -> void:
	_view_model.clear()
	_render_data.clear()
	_last_confirmed_data.clear()
	_current_revision = -1
	_residents.clear()
	_resident_scroll_offset = _route_resident_scroll_offset
	_locally_pending_actions.clear()
	_last_intent_dispatch_msec.clear()


func _resident_values(data: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in data.get("residentTargets", []) as Array:
		if value is Dictionary:
			result.append((value as Dictionary).duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("focusOrder", 9999)) < int(
			b.get("focusOrder", 9999)
		)
	)
	return result


func _resident_name_for_id(resident_id: String) -> String:
	for resident: Dictionary in _residents:
		if String(resident.get("residentId", "")) == resident_id:
			return String(
				resident.get(
					"name",
					resident.get("residentName", "")
				)
			)
	return ""


func _resident_doing_copy(resident: Dictionary) -> String:
	for key: String in [
		"doingLabel",
		"actionLabel",
		"publicAction",
		"statusLabel",
	]:
		var value := String(resident.get(key, ""))
		if not value.is_empty():
			return value
	return "正在室内活动"


func _resident_portrait_path(resident: Dictionary) -> String:
	for key: String in ["portraitPath", "spritePath"]:
		var value := String(resident.get(key, ""))
		if not value.is_empty():
			return value
	var presentation := resident.get("presentation", {}) as Dictionary
	var portrait_path := String(presentation.get("portraitPath", ""))
	return (
		portrait_path
		if not portrait_path.is_empty()
		else String(presentation.get("spritePath", ""))
	)


func _resident_has_full_portrait(resident: Dictionary) -> bool:
	if not String(resident.get("portraitPath", "")).is_empty():
		return true
	var presentation := resident.get("presentation", {}) as Dictionary
	return not String(presentation.get("portraitPath", "")).is_empty()


func _texture_from_path_and_region(
	path: String,
	region_value: Variant
) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var source := load(path) as Texture2D
	if source == null:
		return null
	if not region_value is Array:
		return source
	var values := region_value as Array
	if values.size() != 4:
		return source
	var region := Rect2(
		float(values[0]),
		float(values[1]),
		float(values[2]),
		float(values[3])
	)
	if region.size.x <= 0 or region.size.y <= 0:
		return source
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	atlas.region = region
	return atlas


func _normalized_event_kind(value: String) -> String:
	var normalized := value.to_lower()
	if normalized in ["action", "activity", "work"]:
		return "action"
	if normalized in ["dialogue", "conversation", "chat"]:
		return "dialogue"
	if normalized in ["important", "event", "notice"]:
		return "important"
	return ""


func _clamp_resident_scroll() -> void:
	var resident_values := (
		_residents
		if not _residents.is_empty()
		else _resident_values(_render_data)
	)
	_resident_scroll_offset = clampi(
		_resident_scroll_offset,
		0,
		maxi(
			0,
			resident_values.size() - RESIDENT_VIEWPORT_CAPACITY
		)
	)


func _create_runtime_theme() -> Theme:
	var result := Theme.new()
	var font := load(MAIN_MENU_FONT_PATH) as Font
	result.default_font = font
	result.default_font_size = 16
	_set_label_theme(
		result,
		&"IndoorObservationTitle",
		font,
		26,
		INK
	)
	_set_label_theme(
		result,
		&"IndoorObservationStatus",
		font,
		16,
		INK_MUTED
	)
	_set_label_theme(
		result,
		&"IndoorObservationCount",
		font,
		16,
		INK
	)
	_set_label_theme(
		result,
		&"IndoorObservationResidentName",
		font,
		18,
		INK
	)
	_set_label_theme(
		result,
		&"IndoorObservationResidentAction",
		font,
		14,
		INK_MUTED
	)
	_set_label_theme(
		result,
		&"IndoorObservationEventTime",
		font,
		14,
		INK_MUTED
	)
	_set_label_theme(
		result,
		&"IndoorObservationEventBody",
		font,
		14,
		INK
	)
	_set_empty_button_theme(
		result,
		&"IndoorObservationResidentButton",
		font,
		16,
		Color(0, 0, 0, 0)
	)
	_set_empty_button_theme(
		result,
		&"IndoorObservationEventButton",
		font,
		16,
		Color(0, 0, 0, 0)
	)
	_set_empty_button_theme(
		result,
		&"IndoorObservationReturnButton",
		font,
		24,
		RETURN_INK
	)
	_set_panel_toggle_theme(
		result,
		&"IndoorObservationPanelToggle",
		font,
	)
	return result


func _set_label_theme(
	target_theme: Theme,
	type_name: StringName,
	font: Font,
	font_size: int,
	color: Color
) -> void:
	target_theme.set_type_variation(type_name, &"Label")
	target_theme.set_font(&"font", type_name, font)
	target_theme.set_font_size(&"font_size", type_name, font_size)
	target_theme.set_color(&"font_color", type_name, color)
	target_theme.set_constant(&"outline_size", type_name, 0)
	target_theme.set_constant(&"line_spacing", type_name, 1)


func _set_empty_button_theme(
	target_theme: Theme,
	type_name: StringName,
	font: Font,
	font_size: int,
	color: Color
) -> void:
	target_theme.set_type_variation(type_name, &"Button")
	target_theme.set_font(&"font", type_name, font)
	target_theme.set_font_size(&"font_size", type_name, font_size)
	for color_name: StringName in [
		&"font_color",
		&"font_hover_color",
		&"font_pressed_color",
		&"font_focus_color",
		&"font_disabled_color",
	]:
		target_theme.set_color(color_name, type_name, color)
	for state: StringName in [
		&"normal",
		&"hover",
		&"pressed",
		&"focus",
		&"disabled",
	]:
		target_theme.set_stylebox(
			state,
			type_name,
			StyleBoxEmpty.new()
		)


func _set_panel_toggle_theme(
	target_theme: Theme,
	type_name: StringName,
	font: Font,
) -> void:
	target_theme.set_type_variation(type_name, &"Button")
	target_theme.set_font(&"font", type_name, font)
	target_theme.set_font_size(&"font_size", type_name, 18)
	target_theme.set_color(&"font_color", type_name, Color("#fff2cf"))
	target_theme.set_color(&"font_hover_color", type_name, Color.WHITE)
	target_theme.set_color(&"font_pressed_color", type_name, Color("#f0b94b"))
	target_theme.set_color(&"font_focus_color", type_name, Color.WHITE)
	target_theme.set_color(&"font_outline_color", type_name, INK)
	target_theme.set_constant(&"outline_size", type_name, 2)
	for state: StringName in [
		&"normal",
		&"hover",
		&"pressed",
		&"focus",
		&"disabled",
	]:
		target_theme.set_stylebox(
			state,
			type_name,
			StyleBoxEmpty.new(),
		)


func _make_label(
	name_value: String,
	variation: StringName,
	gate_id: String,
	rect: Rect2,
	alignment: HorizontalAlignment
) -> Label:
	var label := Label.new()
	label.name = name_value
	label.theme_type_variation = variation
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_to_group("indoor_text_slot")
	label.set_meta("gate_id", gate_id)
	label.set_meta("border_owner", false)
	_place_control(label, rect)
	_panel_root.add_child(label)
	return label


func _atlas_piece(
	name_value: String,
	source: Texture2D,
	region: Rect2i,
	rect: Rect2
) -> TextureRect:
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	atlas.region = region
	var piece := TextureRect.new()
	piece.name = name_value
	piece.texture = atlas
	piece.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	piece.stretch_mode = TextureRect.STRETCH_SCALE
	piece.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place_control(piece, rect)
	return piece


func _place_control(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size


func _touch_target_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node: Node in get_tree().get_nodes_in_group(
		"indoor_touch_target"
	):
		if not is_ancestor_of(node):
			continue
		var control := node as Control
		if control == null or not control.is_visible_in_tree():
			continue
		result.append({
			"id": String(control.get_meta("gate_id", control.name)),
			"rect": _rect_to_array(
				Rect2(control.global_position, control.size)
			),
			"disabled": (
				(control as BaseButton).disabled
				if control is BaseButton
				else false
			),
			"focusMode": control.focus_mode,
		})
	return result


func _ownership_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node: Node in _all_descendants(self):
		var control := node as Control
		if control == null or not control.is_visible_in_tree():
			continue
		if not bool(control.get_meta("border_owner", false)):
			continue
		result.append({
			"name": control.name,
			"assetId": String(control.get_meta("asset_id", "")),
			"ownershipLevel": String(
				control.get_meta("ownership_level", "")
			),
			"componentType": String(
				control.get_meta(
					"component_type",
					control.get_class()
				)
			),
			"rect": _rect_to_array(
				Rect2(control.global_position, control.size)
			),
		})
	return result


func _generic_stylebox_count() -> int:
	var count := 0
	for type_name: StringName in [
		&"IndoorObservationResidentButton",
		&"IndoorObservationEventButton",
		&"IndoorObservationReturnButton",
	]:
		for state: StringName in [
			&"normal",
			&"hover",
			&"pressed",
			&"focus",
			&"disabled",
		]:
			var style := theme.get_stylebox(state, type_name)
			if style != null and not style is StyleBoxEmpty:
				count += 1
	return count


func _all_descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child: Node in node.get_children():
		result.append(child)
		result.append_array(_all_descendants(child))
	return result


func _rect_to_array(rect: Rect2) -> Array[float]:
	return [
		rect.position.x,
		rect.position.y,
		rect.size.x,
		rect.size.y,
	]
