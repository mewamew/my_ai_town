class_name ResidentModelAssignmentScreen
extends Control


signal intent_requested(intent: String, payload: Dictionary)
signal action_dispatch_started(intent: String, payload: Dictionary)
signal action_blocked(intent: String, reason: String)
signal back_requested(revision: int)


var return_to_provider_settings := false


const UI_SIGNALS := preload(
	"res://ui/common/AiTownUiSignals.gd"
)
const MOBILE_UI_PROFILE := preload("res://ui/mobile/MobileUiProfile.gd")
const UiViewModel = preload("res://ui/common/AiTownUiViewModel.gd")
const UiNodeRetirement = preload("res://ui/common/AiTownUiNodeRetirement.gd")
const PageTheme = preload(
	"res://ui/resident_model_assignment/runtime/ResidentModelAssignmentTheme.gd"
)
const CompositeDesktop = preload(
	"res://ui/resident_model_assignment/runtime/ResidentModelAssignmentSimplifiedDesktop.gd"
)
const FormalDialog = preload(
	"res://ui/common/formal_dialog/FormalConfirmationDialog.gd"
)

const SCOPE := "resident_model_assignment"
const MAP_TEXTURE_PATH := (
	"res://assets/ui/opening_flow/shared/background/opening_flow_town_background_v1.png"
)
const TOUCH_TARGET_MIN := 48.0
const SLOT_COUNT := 15
const PROVIDER_AUTO_REFRESH_INTERVAL_SECONDS := 0.75
const PROVIDER_AUTO_REFRESH_MAX_ATTEMPTS := 20
const PROVIDER_AUTO_REFRESH_EXHAUSTED_MESSAGE := "模型连接检查超时，请手动刷新重试。"
const REQUIRED_DATA_FIELDS: Array[String] = [
	"capabilityMode",
	"source",
	"formalReady",
	"draftRevision",
	"residentCount",
	"completedCount",
	"invalidCount",
	"unassignedCount",
	"dirty",
	"mode",
	"filter",
	"selectedResidentId",
	"selectedProviderId",
	"selectedModelId",
	"selectedBatchResidentIds",
	"residents",
	"providers",
	"targetBinding",
	"selectedResident",
]
const REQUIRED_ACTIONS: Array[String] = [
	"selectResident",
	"setFilter",
	"setMode",
	"selectBatchResident",
	"selectAllBatch",
	"selectInvalid",
	"selectUnassigned",
	"clearBatchSelection",
	"selectProvider",
	"selectModel",
	"assignOne",
	"assignBatch",
	"applyDraft",
	"refresh",
	"back",
]


var in_session_mode := false
var single_resident_mode := false
var _adapter: Object
var _view_model: Dictionary = {}
var _render_data: Dictionary = {}
var _last_confirmed_data: Dictionary = {}
var _revision := -1
var _contract_error := ""
var _layout_profile := "wide"
var _rendering := false
var _pending_focus_id := ""
var _native_motion_tweens: Dictionary = {}
var _provider_auto_refresh_timer: Timer
var _provider_auto_refresh_attempts := 0
var _provider_auto_refresh_dispatching := false
var _provider_auto_refresh_exhausted := false
var _completion_modal_open := false
var _layout_queued := false

var _page_scroll: ScrollContainer
var _native_root: Control
var _composite_host: CenterContainer
var _composite_desktop: Control
var _page_panel: PanelContainer
var _page_content: VBoxContainer
var _header_top: BoxContainer
var _summary_grid: GridContainer
var _body: BoxContainer
var _resident_section: PanelContainer
var _catalog_section: PanelContainer
var _inspector_section: PanelContainer
var _resident_scroll: ScrollContainer
var _model_scroll: ScrollContainer
var _resident_list: VBoxContainer
var _provider_list: BoxContainer
var _model_list: VBoxContainer
var _resident_buttons: Dictionary = {}
var _provider_buttons: Dictionary = {}
var _model_buttons: Dictionary = {}
var _filter_buttons: Dictionary = {}
var _model_id_detail: Label
var _model_status_detail: Label
var _model_source_detail: Label
var _mode_button: Button
var _back_button: Button
var _refresh_button: Button
var _assign_button: Button
var _apply_button: Button
var _selected_count_label: Label
var _inspector_title: Label
var _current_binding_label: Label
var _target_binding_label: Label
var _warning_label: Label
var _operation_label: Label
var _completion_label: Label
var _invalid_label: Label
var _unassigned_label: Label
var _progress: ProgressBar
var _contract_label: Label
var _native_modal_backdrop: ColorRect
var _native_modal_panel: PanelContainer
var _native_modal_body: Label
var _native_modal_return_button: Button
var _native_modal_start_button: Button
var _exit_confirmation: FormalDialog


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	theme = PageTheme.create()
	_build_interface()
	_build_exit_confirmation()
	_build_provider_auto_refresh_timer()
	resized.connect(_queue_responsive_layout)
	get_viewport().size_changed.connect(_queue_responsive_layout)
	_apply_responsive_layout()
	if _adapter != null:
		_refresh_from_adapter()
	_render()
	_update_provider_auto_refresh()
	call_deferred("_focus_initial_control")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		request_back()
		get_viewport().set_input_as_handled()


func apply_route_payload(payload: Dictionary) -> void:
	var route_mode := String(payload.get("mode", ""))
	in_session_mode = route_mode in ["in_session", "resident_admission"]
	single_resident_mode = route_mode == "resident_admission"
	return_to_provider_settings = bool(
		payload.get("returnToProviderSettings", false)
	)


func request_back() -> bool:
	if bool(_render_data.get("dirty", false)):
		if _exit_confirmation != null and not _exit_confirmation.visible:
			_exit_confirmation.popup_centered()
		return true
	_dispatch_back()
	return true


func _build_exit_confirmation() -> void:
	if _exit_confirmation != null:
		return
	_exit_confirmation = FormalDialog.new()
	_exit_confirmation.name = "UnsavedChangesDialog"
	_exit_confirmation.title = (
		"返回居民资料？"
		if single_resident_mode
		else "返回模型设置？"
		if return_to_provider_settings
		else "返回暂停菜单？"
		if in_session_mode
		else "返回居民选择？"
	)
	_exit_confirmation.dialog_text = "当前模型分配还没有应用，返回后仍会保留草稿。"
	_exit_confirmation.ok_button_text = "返回"
	_exit_confirmation.cancel_button_text = "继续编辑"
	_exit_confirmation.confirmed.connect(_dispatch_back)
	add_child(_exit_confirmation)


func bind_town_ui_adapter(adapter: Object) -> void:
	if _adapter == adapter:
		return
	_disconnect_adapter()
	_adapter = adapter
	_view_model.clear()
	_render_data.clear()
	_last_confirmed_data.clear()
	_revision = -1
	_contract_error = ""
	_completion_modal_open = false
	_reset_provider_auto_refresh()
	if _adapter != null and _adapter.has_signal("view_model_changed"):
		_adapter.connect(
			"view_model_changed",
			Callable(self, "_on_adapter_view_model_changed"),
		)
	if is_node_ready():
		_refresh_from_adapter()
		_render()


func bind_adapter(adapter: Object) -> void:
	bind_town_ui_adapter(adapter)


func unbind_town_ui_adapter() -> void:
	_disconnect_adapter()
	_adapter = null
	_view_model.clear()
	_render_data.clear()
	_last_confirmed_data.clear()
	_revision = -1
	_contract_error = ""
	_completion_modal_open = false
	_reset_provider_auto_refresh()
	if is_node_ready():
		_render()


func apply_view_model(view_model: Dictionary) -> bool:
	var issues := UiViewModel.validate(view_model, "居民模型分配")
	if String(view_model.get("scope", "")) != SCOPE:
		issues.append("居民模型分配 scope 必须为 resident_model_assignment。")
	if not issues.is_empty():
		_set_contract_error("；".join(issues))
		return false
	var incoming_revision := int(view_model.get("revision", 0))
	if _revision >= 0 and incoming_revision < _revision:
		return false
	var incoming_data := view_model.get("data", {}) as Dictionary
	var operation_status := String((view_model.get("operation", {}) as Dictionary).get("status", "idle"))
	var candidate_data := incoming_data
	if (
		incoming_data.is_empty()
		and operation_status in ["rejected", "error"]
		and not _last_confirmed_data.is_empty()
	):
		candidate_data = _last_confirmed_data
	var contract_issues := _validate_contract(view_model, candidate_data)
	if not contract_issues.is_empty():
		_set_contract_error("；".join(contract_issues))
		return false
	if not incoming_data.is_empty() and operation_status not in ["rejected", "error"]:
		_last_confirmed_data = incoming_data.duplicate(true)
	_render_data = candidate_data.duplicate(true)
	_view_model = view_model.duplicate(true)
	_view_model["data"] = _render_data.duplicate(true)
	_revision = incoming_revision
	_contract_error = ""
	if is_node_ready():
		_render()
		_update_provider_auto_refresh()
	return true


func current_view_model() -> Dictionary:
	return _view_model.duplicate(true)


func current_revision() -> int:
	return _revision


func current_layout_profile() -> String:
	return _layout_profile


func layout_profile_for_size(viewport_size: Vector2) -> String:
	if viewport_size.x >= 1600.0 and viewport_size.y >= 840.0:
		return "wide"
	if viewport_size.x >= 1100.0:
		return "standard"
	if viewport_size.x >= 720.0:
		return "compact"
	return "narrow_landscape" if viewport_size.x >= viewport_size.y else "portrait"


func runtime_gate_snapshot() -> Dictionary:
	var text_slots: Array[Dictionary] = []
	var touch_targets: Array[Dictionary] = []
	var border_owners: Array[Dictionary] = []
	for node: Node in get_tree().get_nodes_in_group("resident_model_assignment_text_slot"):
		if not is_ancestor_of(node) or not node is Label or not (node as Label).is_visible_in_tree():
			continue
		var label := node as Label
		text_slots.append({
			"id": String(label.get_meta("gate_id", label.name)),
			"text": label.text,
			"rect": _rect_array(label.get_global_rect()),
			"fontSize": label.get_theme_font_size("font_size"),
			"clip": label.clip_text,
		})
	for node: Node in get_tree().get_nodes_in_group("resident_model_assignment_touch_target"):
		if not is_ancestor_of(node) or not node is Control or not (node as Control).is_visible_in_tree():
			continue
		var control := node as Control
		touch_targets.append({
			"id": String(control.get_meta("gate_id", control.name)),
			"rect": _rect_array(control.get_global_rect()),
			"minimumMet": control.size.x >= TOUCH_TARGET_MIN and control.size.y >= TOUCH_TARGET_MIN,
			"assetMotionCovered": control.has_meta("asset_animation_id"),
			"assetMotionProfile": String(control.get_meta("asset_animation_profile", "")),
		})
	for node: Node in get_tree().get_nodes_in_group("resident_model_assignment_border_owner"):
		if not is_ancestor_of(node) or not node is Control or not (node as Control).is_visible_in_tree():
			continue
		var control := node as Control
		border_owners.append({
			"id": String(control.get_meta("owner_id", control.name)),
			"level": String(control.get_meta("owner_level", "")),
			"rect": _rect_array(control.get_global_rect()),
		})
	var asset_animation: Dictionary = {}
	if is_instance_valid(_composite_desktop) and _composite_desktop.visible:
		asset_animation = _composite_desktop.call("asset_animation_snapshot") as Dictionary
	return {
		"scope": SCOPE,
		"revision": _revision,
		"profile": _layout_profile,
		"wholePageScale": false,
		"formalReady": bool(_render_data.get("formalReady", false)),
		"residentCount": int(_render_data.get("residentCount", 0)),
		"textSlots": text_slots,
		"touchTargets": touch_targets,
		"borderOwners": border_owners,
		"contractError": _contract_error,
		"completionModal": {
			"open": _completion_modal_open,
			"variant": "composite" if _composite_host.visible else "responsive",
			"returnKeepsDraft": true,
			"startIntent": "applyDraft",
		},
		"focusOwner": (
			String(get_viewport().gui_get_focus_owner().name)
			if get_viewport().gui_get_focus_owner() != null
			else ""
		),
		"assetAnimation": asset_animation,
		"providerAutoRefresh": {
			"pending": (
				_provider_catalog_pending(_render_data)
				and not _provider_auto_refresh_exhausted
			),
			"catalogPending": _provider_catalog_pending(_render_data),
			"exhausted": _provider_auto_refresh_exhausted,
			"attempts": _provider_auto_refresh_attempts,
			"maxAttempts": PROVIDER_AUTO_REFRESH_MAX_ATTEMPTS,
			"scheduled": (
				_provider_auto_refresh_timer != null
				and not _provider_auto_refresh_timer.is_stopped()
			),
		},
	}


func provider_auto_refresh_tick_for_test() -> void:
	_on_provider_auto_refresh_timeout()


func _build_interface() -> void:
	var background := TextureRect.new()
	background.name = "TownBackground"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var map_texture := ResourceLoader.load(MAP_TEXTURE_PATH, "Texture2D") as Texture2D
	if map_texture != null:
		background.texture = map_texture
	add_child(background)

	var dim := ColorRect.new()
	dim.name = "MapDim"
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = PageTheme.OVERLAY
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var outer_margin := MarginContainer.new()
	outer_margin.name = "SafeAreaMargin"
	outer_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer_margin.add_theme_constant_override("margin_left", 24)
	outer_margin.add_theme_constant_override("margin_top", 20)
	outer_margin.add_theme_constant_override("margin_right", 24)
	outer_margin.add_theme_constant_override("margin_bottom", 20)
	add_child(outer_margin)
	_native_root = outer_margin

	_page_scroll = ScrollContainer.new()
	_page_scroll.name = "ResponsivePageScroll"
	_page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_page_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	outer_margin.add_child(_page_scroll)

	_page_panel = PanelContainer.new()
	_page_panel.name = "ResidentModelAssignmentPageShell"
	_page_panel.add_theme_stylebox_override("panel", PageTheme.page_shell())
	_register_border_owner(_page_panel, "ResidentModelAssignmentPageShell", "page_shell")
	_page_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_scroll.add_child(_page_panel)

	_page_content = VBoxContainer.new()
	_page_content.name = "PageContent"
	_page_content.add_theme_constant_override("separation", 16)
	_page_panel.add_child(_page_content)

	_build_header()
	_build_body()

	_contract_label = _label("", 18, PageTheme.TERRACOTTA_DARK, "ContractError")
	_contract_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_contract_label.visible = false
	_page_content.add_child(_contract_label)

	_composite_host = CenterContainer.new()
	_composite_host.name = "AcceptedV16CompositeHost"
	_composite_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_composite_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_composite_host)
	_composite_desktop = CompositeDesktop.new()
	_composite_desktop.set("in_session_mode", in_session_mode)
	_composite_desktop.set("single_resident_mode", single_resident_mode)
	_composite_host.add_child(_composite_desktop)
	_composite_desktop.connect("action_requested", Callable(self, "_request_action"))
	_composite_desktop.connect("back_pressed", Callable(self, "_request_back"))
	_composite_desktop.connect("assign_pressed", Callable(self, "_assign_target"))
	_composite_desktop.connect("apply_pressed", Callable(self, "_open_completion_modal"))
	_composite_desktop.connect(
		"completion_modal_return_pressed",
		Callable(self, "_close_completion_modal"),
	)
	_composite_desktop.connect(
		"completion_modal_start_pressed",
		Callable(self, "_start_game_from_completion_modal"),
	)
	_build_native_completion_modal()


func _build_provider_auto_refresh_timer() -> void:
	_provider_auto_refresh_timer = Timer.new()
	_provider_auto_refresh_timer.name = "ProviderCatalogAutoRefreshTimer"
	_provider_auto_refresh_timer.one_shot = true
	_provider_auto_refresh_timer.wait_time = PROVIDER_AUTO_REFRESH_INTERVAL_SECONDS
	_provider_auto_refresh_timer.timeout.connect(_on_provider_auto_refresh_timeout)
	add_child(_provider_auto_refresh_timer)


func _build_native_completion_modal() -> void:
	_native_modal_backdrop = ColorRect.new()
	_native_modal_backdrop.name = "ResponsiveCompletionModalBackdrop"
	_native_modal_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_native_modal_backdrop.color = PageTheme.OVERLAY
	_native_modal_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_native_modal_backdrop.visible = false
	add_child(_native_modal_backdrop)

	_native_modal_panel = PanelContainer.new()
	_native_modal_panel.name = "ResponsiveCompletionModalPanel"
	_native_modal_panel.set_anchors_preset(Control.PRESET_CENTER)
	_native_modal_panel.add_theme_stylebox_override("panel", PageTheme.page_shell())
	_register_border_owner(
		_native_modal_panel,
		"ResidentModelAssignmentResponsiveCompletionModal",
		"modal_shell",
	)
	_native_modal_backdrop.add_child(_native_modal_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_bottom", 28)
	_native_modal_panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 18)
	margin.add_child(stack)

	var title := _label("全部配置完成", 30, PageTheme.INK, "ResponsiveModalTitle")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.custom_minimum_size.y = 52
	stack.add_child(title)
	_native_modal_body = _label(
		(
			"这位新居民的模型已经配置完成，可以确认入镇。"
			if single_resident_mode
			else "居民模型分配已更新，确认后返回模型设置。"
			if return_to_provider_settings
			else "15 位居民的模型均已配置完成，可以保存到当前小镇。"
			if in_session_mode
			else "15 位居民的模型均已配置完成，现在可以开始游戏。"
		),
		20,
		PageTheme.INK_MUTED,
		"ResponsiveModalBody",
	)
	_native_modal_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_native_modal_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_native_modal_body.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_native_modal_body.custom_minimum_size.y = 100
	stack.add_child(_native_modal_body)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 16)
	stack.add_child(actions)
	_native_modal_return_button = _button("返回设置", 22, "paper", "ResponsiveModalReturn")
	_native_modal_return_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_native_modal_return_button.pressed.connect(_close_completion_modal)
	actions.add_child(_native_modal_return_button)
	_native_modal_start_button = _button(
		(
			"确认入镇"
			if single_resident_mode
			else "确认并返回"
			if return_to_provider_settings
			else "保存修改"
			if in_session_mode
			else "开始游戏"
		),
		22,
		"success",
		"ResponsiveModalStart",
	)
	_native_modal_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_native_modal_start_button.pressed.connect(_start_game_from_completion_modal)
	actions.add_child(_native_modal_start_button)


func _reset_provider_auto_refresh() -> void:
	_provider_auto_refresh_attempts = 0
	_provider_auto_refresh_dispatching = false
	_provider_auto_refresh_exhausted = false
	if _provider_auto_refresh_timer != null:
		_provider_auto_refresh_timer.stop()


func _provider_catalog_pending(data: Dictionary) -> bool:
	if data.is_empty() or bool(data.get("formalReady", false)):
		return false
	for provider_value: Variant in data.get("providers", []) as Array:
		if not provider_value is Dictionary:
			continue
		var provider := provider_value as Dictionary
		if _provider_entry_pending(provider):
			return true
		for model_value: Variant in provider.get("models", []) as Array:
			if model_value is Dictionary and _provider_entry_pending(model_value as Dictionary):
				return true
	return false


func _provider_entry_pending(entry: Dictionary) -> bool:
	var status := String(entry.get("status", "")).to_lower()
	var error_code := String(entry.get("errorCode", "")).to_upper()
	return (
		status in ["checking", "pending"]
		or error_code in [
			"PROVIDER_HEALTH_CHECK_REQUIRED",
			"PROVIDER_HEALTH_CHECK_PENDING",
		]
	)


func _update_provider_auto_refresh() -> void:
	if _provider_auto_refresh_timer == null:
		return
	if not _provider_catalog_pending(_render_data):
		var was_exhausted := _provider_auto_refresh_exhausted
		_provider_auto_refresh_timer.stop()
		_provider_auto_refresh_exhausted = false
		if bool(_render_data.get("formalReady", false)):
			_provider_auto_refresh_attempts = 0
		if was_exhausted:
			_render()
		return
	if _provider_auto_refresh_attempts >= PROVIDER_AUTO_REFRESH_MAX_ATTEMPTS:
		_provider_auto_refresh_exhausted = true
		_provider_auto_refresh_timer.stop()
		_render_provider_auto_refresh_feedback()
		return
	if _adapter == null or _provider_auto_refresh_dispatching:
		_provider_auto_refresh_timer.stop()
		return
	var operation_status := String(
		(_view_model.get("operation", {}) as Dictionary).get("status", "idle")
	)
	if operation_status == "loading":
		_provider_auto_refresh_timer.stop()
		return
	var refresh_action := UiViewModel.action(_view_model, "refresh")
	if not UiViewModel.action_enabled(refresh_action):
		_provider_auto_refresh_timer.stop()
		return
	if _provider_auto_refresh_timer.is_stopped():
		_provider_auto_refresh_timer.start()


func _on_provider_auto_refresh_timeout() -> void:
	if (
		_provider_auto_refresh_dispatching
		or not _provider_catalog_pending(_render_data)
		or _provider_auto_refresh_attempts >= PROVIDER_AUTO_REFRESH_MAX_ATTEMPTS
	):
		_update_provider_auto_refresh()
		return
	_provider_auto_refresh_attempts += 1
	_provider_auto_refresh_dispatching = true
	_request_action("refresh", {}, _current_focus_id_for_refresh())
	_provider_auto_refresh_dispatching = false
	_update_provider_auto_refresh()


func _request_manual_provider_refresh() -> void:
	_provider_auto_refresh_attempts = 0
	_provider_auto_refresh_exhausted = false
	_request_action("refresh", {}, "refresh")


func _current_focus_id_for_refresh() -> String:
	if not is_inside_tree():
		return ""
	var focus_owner := get_viewport().gui_get_focus_owner()
	if not is_instance_valid(focus_owner):
		return ""
	if is_instance_valid(_composite_desktop) and _composite_desktop.is_ancestor_of(focus_owner):
		# The approved desktop surface updates controls in place, so leaving the
		# pending id empty keeps its current focus without an unnecessary jump.
		return ""
	for fixed: Array in [
		["back", _back_button],
		["mode", _mode_button],
		["refresh", _refresh_button],
		["assign", _assign_button],
		["apply", _apply_button],
	]:
		if focus_owner == fixed[1]:
			return String(fixed[0])
	for resident_id: Variant in _resident_buttons:
		if focus_owner == _resident_buttons[resident_id]:
			return "resident:%s" % String(resident_id)
	for provider_id: Variant in _provider_buttons:
		if focus_owner == _provider_buttons[provider_id]:
			return "provider:%s" % String(provider_id)
	for model_id: Variant in _model_buttons:
		if focus_owner == _model_buttons[model_id]:
			return "model:%s" % String(model_id)
	for filter_id: Variant in _filter_buttons:
		if focus_owner == _filter_buttons[filter_id]:
			return "filter:%s" % String(filter_id)
	return ""


func _presentation_view_model() -> Dictionary:
	var presentation := _view_model.duplicate(true)
	var presentation_data := (
		presentation.get("data", {}) as Dictionary
	).duplicate(true)
	presentation_data["returnToProviderSettings"] = return_to_provider_settings
	presentation["data"] = presentation_data
	if not _provider_auto_refresh_exhausted:
		return presentation
	var operation := (presentation.get("operation", {}) as Dictionary).duplicate(true)
	operation["status"] = "error"
	presentation["operation"] = operation
	presentation["error"] = {
		"code": "PROVIDER_AUTO_REFRESH_EXHAUSTED",
		"playerMessage": PROVIDER_AUTO_REFRESH_EXHAUSTED_MESSAGE,
		"retryable": true,
	}
	return presentation


func _render_provider_auto_refresh_feedback() -> void:
	if is_instance_valid(_operation_label):
		_operation_label.text = PROVIDER_AUTO_REFRESH_EXHAUSTED_MESSAGE
	if is_instance_valid(_composite_desktop):
		_composite_desktop.call("apply_view_model", _presentation_view_model())


func _build_header() -> void:
	var header_section := PanelContainer.new()
	header_section.name = "HeaderSectionFrame"
	header_section.add_theme_stylebox_override("panel", PageTheme.section(PageTheme.WOOD_LIGHT))
	_register_border_owner(header_section, "HeaderSectionFrame", "section_frame")
	_page_content.add_child(header_section)

	var header_stack := VBoxContainer.new()
	header_stack.add_theme_constant_override("separation", 10)
	header_section.add_child(header_stack)

	_header_top = BoxContainer.new()
	_header_top.name = "HeaderTop"
	_header_top.vertical = false
	_header_top.add_theme_constant_override("separation", 14)
	header_stack.add_child(_header_top)

	_back_button = _button(
		"← 返回模型设置" if return_to_provider_settings else "← 返回居民选择",
		20,
		"paper",
		"BackButton",
	)
	_back_button.custom_minimum_size = Vector2(210, 56)
	_back_button.pressed.connect(_request_back)
	_header_top.add_child(_back_button)

	var title := _label("居民模型工作台", 42, PageTheme.INK, "PageTitle")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = false
	_header_top.add_child(title)

	_mode_button = _button("切换批量模式", 20, "blue", "ModeButton")
	_mode_button.custom_minimum_size = Vector2(190, 56)
	_mode_button.pressed.connect(_toggle_mode)
	_header_top.add_child(_mode_button)
	_mode_button.visible = not single_resident_mode

	_summary_grid = GridContainer.new()
	_summary_grid.name = "SummaryGrid"
	_summary_grid.columns = 4
	_summary_grid.add_theme_constant_override("h_separation", 12)
	_summary_grid.add_theme_constant_override("v_separation", 8)
	header_stack.add_child(_summary_grid)
	_completion_label = _summary_badge("完成 0/15", "success", "CompletionSummary")
	_invalid_label = _summary_badge("失效 0", "warning", "InvalidSummary")
	_unassigned_label = _summary_badge("未分配 0", "normal", "UnassignedSummary")
	_summary_grid.add_child(_completion_label.get_parent())
	_summary_grid.add_child(_invalid_label.get_parent())
	_summary_grid.add_child(_unassigned_label.get_parent())
	_progress = ProgressBar.new()
	_progress.name = "CompletionProgress"
	_progress.min_value = 0
	_progress.max_value = SLOT_COUNT
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(280, 48)
	_progress.add_theme_stylebox_override("background", PageTheme.progress_background())
	_progress.add_theme_stylebox_override("fill", PageTheme.progress_fill())
	_summary_grid.add_child(_progress)


func _build_body() -> void:
	_body = BoxContainer.new()
	_body.name = "ResponsiveBody"
	_body.vertical = false
	_body.add_theme_constant_override("separation", 16)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_content.add_child(_body)

	_resident_section = _section_panel("ResidentQueueSectionFrame", PageTheme.WOOD)
	_catalog_section = _section_panel("ModelCatalogSectionFrame", PageTheme.BLUE_DARK)
	_inspector_section = _section_panel("BindingInspectorSectionFrame", PageTheme.MOSS_DARK)
	_body.add_child(_resident_section)
	_body.add_child(_catalog_section)
	_body.add_child(_inspector_section)
	_build_resident_section()
	_build_catalog_section()
	_build_inspector_section()


func _build_resident_section() -> void:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	_resident_section.add_child(stack)
	stack.add_child(_section_title(
		"入镇居民" if single_resident_mode else "居民队列 · 15人",
		"ResidentQueueTitle",
	))

	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	stack.add_child(filters)
	for spec in [["all", "全部"], ["invalid", "失效"], ["unassigned", "未分配"]]:
		var button := _button(String(spec[1]), 17, "quiet", "Filter_%s" % String(spec[0]))
		button.custom_minimum_size = Vector2(76 if spec[0] != "unassigned" else 104, 48)
		button.pressed.connect(_on_quick_filter_pressed.bind(String(spec[0])))
		filters.add_child(button)
		_filter_buttons[String(spec[0])] = button

	_selected_count_label = _label("单人模式", 17, PageTheme.INK_MUTED, "SelectionModeSummary")
	stack.add_child(_selected_count_label)

	_resident_scroll = ScrollContainer.new()
	_resident_scroll.name = "ResidentQueueScroll"
	_resident_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_resident_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_resident_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_resident_scroll.custom_minimum_size = Vector2(0, 540)
	stack.add_child(_resident_scroll)
	_resident_list = VBoxContainer.new()
	_resident_list.name = "ResidentRows"
	_resident_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resident_list.add_theme_constant_override("separation", 8)
	_resident_scroll.add_child(_resident_list)


func _build_catalog_section() -> void:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	_catalog_section.add_child(stack)
	stack.add_child(_section_title("Provider / 模型目录", "CatalogTitle"))

	_provider_list = BoxContainer.new()
	_provider_list.name = "ProviderRail"
	_provider_list.vertical = false
	_provider_list.add_theme_constant_override("separation", 8)
	stack.add_child(_provider_list)

	var divider := HSeparator.new()
	divider.name = "ProviderModelDivider"
	divider.add_theme_constant_override("separation", 12)
	divider.add_to_group("resident_model_assignment_border_owner")
	divider.set_meta("owner_id", "ProviderModelDivider")
	divider.set_meta("owner_level", "section_divider")
	stack.add_child(divider)

	_model_scroll = ScrollContainer.new()
	_model_scroll.name = "ModelCatalogScroll"
	_model_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_model_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_model_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_model_scroll.custom_minimum_size = Vector2(0, 220)
	stack.add_child(_model_scroll)
	_model_list = VBoxContainer.new()
	_model_list.name = "ModelCards"
	_model_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_model_list.add_theme_constant_override("separation", 10)
	_model_scroll.add_child(_model_list)

	var detail_stack := VBoxContainer.new()
	detail_stack.name = "SelectedModelDetails"
	detail_stack.add_theme_constant_override("separation", 8)
	stack.add_child(detail_stack)
	_model_id_detail = _inline_info_row(detail_stack, "模型标识", "—", "CatalogModelId")
	_model_status_detail = _inline_info_row(detail_stack, "状态", "—", "CatalogModelStatus")
	_model_source_detail = _inline_info_row(detail_stack, "来源", "正式运行目录", "CatalogModelSource")


func _build_inspector_section() -> void:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	_inspector_section.add_child(stack)
	_inspector_title = _section_title("当前居民", "InspectorTitle")
	stack.add_child(_inspector_title)
	_current_binding_label = _info_row(stack, "当前绑定", "尚未选择居民", "CurrentBinding", "normal")
	_target_binding_label = _info_row(stack, "目标绑定", "请选择可用模型", "TargetBinding", "success")
	_warning_label = _info_row(stack, "绑定检查", "等待正式 Provider 状态", "BindingWarning", "warning")
	_operation_label = _info_row(stack, "操作状态", "可以开始分配", "OperationStatus", "normal")

	_refresh_button = _button("刷新正式目录", 18, "paper", "RefreshButton")
	_refresh_button.custom_minimum_size = Vector2(180, 52)
	_refresh_button.pressed.connect(_request_manual_provider_refresh)
	stack.add_child(_refresh_button)

	_assign_button = _button("更新当前居民草稿", 22, "success", "AssignButton")
	_assign_button.custom_minimum_size = Vector2(0, 64)
	_assign_button.pressed.connect(_assign_target)
	stack.add_child(_assign_button)

	_apply_button = _button("确认 15 人模型分配", 22, "primary", "ApplyDraftButton")
	_apply_button.custom_minimum_size = Vector2(0, 64)
	_apply_button.pressed.connect(_open_completion_modal)
	stack.add_child(_apply_button)


func _render() -> void:
	if not is_node_ready() or _rendering:
		return
	_rendering = true
	_contract_label.visible = not _contract_error.is_empty()
	_contract_label.text = _contract_error
	var has_data := not _render_data.is_empty()
	var completed := int(_render_data.get("completedCount", 0)) if has_data else 0
	var resident_count := int(_render_data.get("residentCount", SLOT_COUNT)) if has_data else SLOT_COUNT
	var invalid := int(_render_data.get("invalidCount", 0)) if has_data else 0
	var unassigned := int(_render_data.get("unassignedCount", SLOT_COUNT)) if has_data else SLOT_COUNT
	_completion_label.text = "完成 %d/%d" % [completed, resident_count]
	_invalid_label.text = "失效 %d" % invalid
	_unassigned_label.text = "未分配 %d" % unassigned
	_progress.max_value = resident_count
	_progress.value = completed
	var mode := String(_render_data.get("mode", "single"))
	_mode_button.text = "返回单人模式" if mode == "batch" else "切换批量模式"
	_mode_button.visible = not single_resident_mode
	_selected_count_label.text = (
		"仅显示本次入镇居民"
		if single_resident_mode
		else "批量已选 %d 人" % (_render_data.get("selectedBatchResidentIds", []) as Array).size()
		if mode == "batch"
		else "单人模式 · 点击居民查看绑定"
	)
	_render_filters()
	_render_resident_rows()
	_render_provider_rail()
	_render_model_cards()
	_render_inspector()
	_render_action_states()
	if is_instance_valid(_composite_desktop):
		_composite_desktop.call("apply_view_model", _presentation_view_model())
	_sync_completion_modal_visibility()
	_rendering = false
	if MOBILE_UI_PROFILE.is_mobile_runtime():
		_queue_responsive_layout()
	call_deferred("_restore_pending_focus")


func _render_filters() -> void:
	var active := String(_render_data.get("filter", "all"))
	var batch_mode := String(_render_data.get("mode", "single")) == "batch"
	for key: Variant in _filter_buttons:
		var button := _filter_buttons[key] as Button
		var filter_id := String(key)
		if batch_mode:
			button.text = String({
				"all": "清空",
				"invalid": "失效",
				"unassigned": "未分配",
			}.get(filter_id, filter_id))
			button.button_pressed = _batch_selection_matches_status(filter_id)
			var action_key := String({
				"all": "clearBatchSelection",
				"invalid": "selectInvalid",
				"unassigned": "selectUnassigned",
			}.get(filter_id, ""))
			_apply_action_state(button, action_key)
			if not button.disabled:
				button.tooltip_text = String({
					"all": "清空当前批量选择",
					"invalid": "选择全部失效居民",
					"unassigned": "选择全部未分配居民",
				}.get(filter_id, ""))
		else:
			button.text = String({
				"all": "全部",
				"invalid": "失效",
				"unassigned": "未分配",
			}.get(filter_id, filter_id))
			button.button_pressed = filter_id == active
			_apply_action_state(button, "setFilter")
		PageTheme.apply_button(button, "blue" if button.button_pressed else "quiet")


func _render_resident_rows() -> void:
	_clear_children(_resident_list)
	_resident_buttons.clear()
	var filter_value := String(_render_data.get("filter", "all"))
	var selected_resident := String(_render_data.get("selectedResidentId", ""))
	var mode := String(_render_data.get("mode", "single"))
	var batch_ids := _render_data.get("selectedBatchResidentIds", []) as Array
	for value: Variant in _render_data.get("residents", []) as Array:
		if not value is Dictionary:
			continue
		var resident := value as Dictionary
		var status := String(resident.get("bindingStatus", "unassigned"))
		if filter_value != "all" and status != filter_value:
			continue
		var resident_id := String(resident.get("residentId", ""))
		var selected := batch_ids.has(resident_id) if mode == "batch" else resident_id == selected_resident
		var row := _resident_row(resident, selected, mode)
		_resident_list.add_child(row)
		_resident_buttons[resident_id] = row


func _resident_row(resident: Dictionary, selected: bool, mode: String) -> Button:
	var resident_id := String(resident.get("residentId", ""))
	var status := String(resident.get("bindingStatus", "unassigned"))
	var variant := "blue" if selected else "paper"
	var button := _button("", 17, variant, "Resident_%s" % resident_id)
	button.name = "Resident_%s" % resident_id
	button.custom_minimum_size = Vector2(0, 82)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.set_meta("resident_id", resident_id)
	var resident_action := "selectBatchResident" if mode == "batch" else "selectResident"
	var resident_action_contract := UiViewModel.action(_view_model, resident_action)
	button.disabled = not UiViewModel.action_enabled(resident_action_contract)
	button.tooltip_text = (
		""
		if not button.disabled
		else UiViewModel.disabled_reason(resident_action_contract)
	)
	_refresh_native_asset_motion(button, true)
	button.pressed.connect(_on_resident_pressed.bind(resident_id))
	_register_border_owner(button, "ResidentRow:%s" % resident_id, "content_slot")

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 8)
	button.add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)

	var marker := _label("✓" if selected else _status_symbol(status), 22, _status_color(status), "ResidentMarker:%s" % resident_id)
	marker.custom_minimum_size = Vector2(30, 48)
	marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(marker)

	var text_stack := VBoxContainer.new()
	text_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_stack.add_theme_constant_override("separation", 4)
	row.add_child(text_stack)
	var name_prefix := "[多选] " if mode == "batch" and selected else ""
	var selected_ink := Color.WHITE if selected else PageTheme.INK
	var selected_muted := Color("f7e5bb") if selected else PageTheme.INK_MUTED
	var name_label := _label(name_prefix + String(resident.get("displayName", resident_id)), 20, selected_ink, "ResidentName:%s" % resident_id)
	text_stack.add_child(name_label)
	var binding_text := _binding_summary(resident)
	var binding_label := _label(binding_text, 17, selected_muted, "ResidentBinding:%s" % resident_id)
	binding_label.tooltip_text = binding_text
	text_stack.add_child(binding_label)
	var status_label := _label(String(resident.get("bindingStatusLabel", "")), 17, Color("f3e29c") if selected else _status_color(status), "ResidentStatus:%s" % resident_id)
	status_label.custom_minimum_size = Vector2(74, 48)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(status_label)
	return button


func _render_provider_rail() -> void:
	_clear_children(_provider_list)
	_provider_buttons.clear()
	var selected_id := String(_render_data.get("selectedProviderId", ""))
	for value: Variant in _render_data.get("providers", []) as Array:
		if not value is Dictionary:
			continue
		var provider := value as Dictionary
		var provider_id := String(provider.get("providerId", ""))
		var selected := provider_id == selected_id
		var button := _button(
			String(provider.get("displayName", provider_id)),
			18,
			"blue" if selected else "paper",
			"Provider_%s" % provider_id,
		)
		button.custom_minimum_size = Vector2(132, 56)
		button.disabled = (
			not bool(provider.get("available", false))
			or not UiViewModel.action_enabled(UiViewModel.action(_view_model, "selectProvider"))
		)
		_refresh_native_asset_motion(button, true)
		button.tooltip_text = (
			"连接可用"
			if bool(provider.get("available", false))
			else UiViewModel.player_reason(
				String(
					provider.get(
						"errorCode",
						"PROVIDER_UNAVAILABLE",
					)
				)
			)
		)
		button.pressed.connect(_request_action.bind("selectProvider", {"providerId": provider_id}, "provider:%s" % provider_id))
		_register_border_owner(button, "ProviderCard:%s" % provider_id, "content_slot")
		_provider_list.add_child(button)
		_provider_buttons[provider_id] = button


func _render_model_cards() -> void:
	_clear_children(_model_list)
	_model_buttons.clear()
	var selected_provider_id := String(_render_data.get("selectedProviderId", ""))
	var selected_model_id := String(_render_data.get("selectedModelId", ""))
	var provider := _find_provider(selected_provider_id)
	var models := provider.get("models", []) as Array
	if models.is_empty():
		var empty_label := _label("这个 Provider 当前没有可分配模型", 20, PageTheme.TERRACOTTA_DARK, "ModelCatalogEmpty")
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_model_list.add_child(empty_label)
		_model_id_detail.text = "—"
		_model_status_detail.text = "无可分配模型"
		_model_source_detail.text = "正式运行目录"
		return
	for value: Variant in models:
		if not value is Dictionary:
			continue
		var model := value as Dictionary
		var model_id := String(model.get("modelId", ""))
		var selected := model_id == selected_model_id
		var available := bool(model.get("available", false))
		var button := _button("", 18, "blue" if selected else "paper", "Model_%s" % model_id)
		button.name = "Model_%s" % model_id.replace("/", "_").replace(".", "_")
		button.custom_minimum_size = Vector2(0, 132)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = (
			not available
			or not UiViewModel.action_enabled(UiViewModel.action(_view_model, "selectModel"))
		)
		_refresh_native_asset_motion(button, true)
		button.tooltip_text = (
			String(model.get("displayName", model_id))
			if available
			else UiViewModel.player_reason(
				String(
					model.get(
						"errorCode",
						"LLM_MODEL_UNAVAILABLE",
					)
				)
			)
		)
		button.pressed.connect(_request_action.bind(
			"selectModel",
			{"providerId": selected_provider_id, "modelId": model_id},
			"model:%s" % model_id,
		))
		_register_border_owner(button, "ModelCard:%s" % model_id, "content_slot")
		var margin := MarginContainer.new()
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		margin.add_theme_constant_override("margin_left", 16)
		margin.add_theme_constant_override("margin_top", 10)
		margin.add_theme_constant_override("margin_right", 16)
		margin.add_theme_constant_override("margin_bottom", 10)
		button.add_child(margin)
		var stack := VBoxContainer.new()
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_theme_constant_override("separation", 4)
		margin.add_child(stack)
		var primary_ink := Color.WHITE if selected else PageTheme.INK
		var secondary_ink := Color("f7e5bb") if selected else PageTheme.INK_MUTED
		stack.add_child(_label(String(model.get("displayName", model_id)), 22, primary_ink, "ModelName:%s" % model_id))
		var id_label := _label(model_id, 17, secondary_ink, "ModelId:%s" % model_id)
		id_label.tooltip_text = model_id
		stack.add_child(id_label)
		stack.add_child(_label("可分配" if available else "不可用", 17, Color("e5eea0") if selected and available else PageTheme.MOSS if available else PageTheme.TERRACOTTA, "ModelStatus:%s" % model_id))
		_model_list.add_child(button)
		_model_buttons[model_id] = button
	var selected_model := _find_model(selected_provider_id, selected_model_id)
	_model_id_detail.text = String(selected_model.get("modelId", "—"))
	_model_id_detail.tooltip_text = _model_id_detail.text
	_model_status_detail.text = "可分配" if bool(selected_model.get("available", false)) else "当前不可用"
	_model_source_detail.text = "正式 Provider 公共目录"


func _render_inspector() -> void:
	var resident := _render_data.get("selectedResident", {}) as Dictionary
	var mode := String(_render_data.get("mode", "single"))
	var batch_count := (_render_data.get("selectedBatchResidentIds", []) as Array).size()
	_inspector_title.text = (
		"批量分配 · 已选 %d 人" % batch_count
		if mode == "batch"
		else "当前居民 · %s" % String(resident.get("displayName", "未选择"))
	)
	_current_binding_label.text = (
		("已选 %d 人" % batch_count)
		if mode == "batch"
		else (_binding_summary(resident) if not resident.is_empty() else "尚未选择居民")
	)
	var target := _render_data.get("targetBinding", {}) as Dictionary
	var target_provider := _find_provider(String(target.get("providerId", "")))
	var target_model := _find_model(
		String(target.get("providerId", "")),
		String(target.get("modelId", "")),
	)
	_target_binding_label.text = (
		"%s / %s" % [
			String(target_provider.get("displayName", target.get("providerId", ""))),
			String(target_model.get("displayName", target.get("modelId", ""))),
		]
		if not String(target.get("modelId", "")).is_empty()
		else "请选择可用 Provider 与模型"
	)
	if mode == "batch":
		var breakdown := _selected_batch_status_counts()
		_warning_label.text = (
			"尚未选择批量居民，可用快捷项或居民行选择。"
			if batch_count == 0
			else "将更新 %d 人：失效 %d，未分配 %d。" % [
				batch_count,
				int(breakdown.get("invalid", 0)),
				int(breakdown.get("unassigned", 0)),
			]
		)
	else:
		var status := String(resident.get("bindingStatus", "unassigned"))
		match status:
			"valid":
				_warning_label.text = "当前绑定可用，可以保持或切换模型。"
			"invalid":
				_warning_label.text = "原绑定模型已失效，请选择当前可用模型。"
			_:
				_warning_label.text = "这位居民尚未完成模型分配。"
	if _provider_auto_refresh_exhausted:
		_operation_label.text = PROVIDER_AUTO_REFRESH_EXHAUSTED_MESSAGE
	else:
		var operation := _view_model.get("operation", {}) as Dictionary
		var operation_status := String(operation.get("status", "idle"))
		var error_message := UiViewModel.error_message(_view_model)
		match operation_status:
			"loading":
				_operation_label.text = "正在更新正式分配状态…"
			"success":
				_operation_label.text = "操作完成，草稿与完成数已更新。"
			"rejected":
				_operation_label.text = error_message if not error_message.is_empty() else "操作被拒绝，原数据已保留。"
			"error":
				_operation_label.text = error_message if not error_message.is_empty() else "连接异常，原数据已保留。"
			"disabled":
				_operation_label.text = "正式接口不可用。"
			_:
				_operation_label.text = "选择居民和可用模型后更新草稿。"
	var pending_rebind := CompositeDesktop.has_pending_rebind(_render_data)
	_assign_button.text = (
		("改绑已选 %d 人" if pending_rebind else "应用到已选 %d 人") % batch_count
		if mode == "batch"
		else ("改绑当前居民" if pending_rebind else "更新当前居民草稿")
	)
	_apply_button.text = (
		"确认入镇"
		if single_resident_mode
		else "确认并返回模型设置"
		if return_to_provider_settings
		else "保存模型分配"
		if in_session_mode
		else "确认 15 人模型分配"
	)


func _render_action_states() -> void:
	_apply_action_state(_back_button, "back")
	_apply_action_state(_mode_button, "setMode")
	_apply_action_state(_refresh_button, "refresh")
	_apply_action_state(_assign_button, "assignBatch" if String(_render_data.get("mode", "single")) == "batch" else "assignOne")
	_apply_action_state(_apply_button, "applyDraft")
	_apply_action_state(_native_modal_start_button, "applyDraft")
	var apply_enabled := CompositeDesktop.should_apply_draft(
		_render_data,
		UiViewModel.action_enabled(UiViewModel.action(_view_model, "applyDraft")),
	)
	_apply_button.disabled = not apply_enabled
	_native_modal_start_button.disabled = not apply_enabled
	_native_modal_return_button.disabled = false
	var loading := String((_view_model.get("operation", {}) as Dictionary).get("status", "")) == "loading"
	if loading:
		_assign_button.disabled = true
		_apply_button.disabled = true
		_native_modal_start_button.disabled = true
		_refresh_button.disabled = true
	for button in [
		_back_button,
		_mode_button,
		_refresh_button,
		_assign_button,
		_apply_button,
		_native_modal_return_button,
		_native_modal_start_button,
	]:
		_refresh_native_asset_motion(button)


func _apply_action_state(button: Button, action_key: String) -> void:
	var action := UiViewModel.action(_view_model, action_key)
	var enabled := UiViewModel.action_enabled(action)
	button.disabled = not enabled
	button.tooltip_text = (
		""
		if enabled
		else UiViewModel.player_reason(UiViewModel.disabled_reason(action))
	)
	_refresh_native_asset_motion(button)


func _request_action(
	action_key: String,
	extra_payload: Dictionary = {},
	focus_id := "",
) -> Dictionary:
	var action := UiViewModel.action(_view_model, action_key)
	var intent := String(action.get("intent", ""))
	if intent.is_empty() or not UiViewModel.action_enabled(action):
		var reason := UiViewModel.disabled_reason(action)
		if reason.is_empty():
			reason = "RESIDENT_MODEL_ASSIGNMENT_INTERFACE_MISSING"
		action_blocked.emit(intent, reason)
		return {
			"ok": false,
			"accepted": false,
			"errorCode": reason,
			"retryable": false,
		}
	_pending_focus_id = focus_id
	var payload := {"revision": _revision}
	payload.merge(extra_payload, true)
	action_dispatch_started.emit(intent, payload.duplicate(true))
	return _dispatch_prepared_action(intent, payload)


func _dispatch_prepared_action(intent: String, payload: Dictionary) -> Dictionary:
	var dispatch_result := {
		"ok": false,
		"accepted": false,
		"errorCode": "RESIDENT_MODEL_ASSIGNMENT_ADAPTER_NOT_BOUND",
		"retryable": false,
	}
	if _adapter != null and _adapter.has_method("dispatch"):
		dispatch_result = _adapter.call("dispatch", intent, payload.duplicate(true)) as Dictionary
	var routed_payload := payload.duplicate(true)
	routed_payload["dispatchResult"] = dispatch_result.duplicate(true)
	intent_requested.emit(intent, routed_payload)
	return dispatch_result


func _request_back() -> void:
	request_back()


func _dispatch_back() -> void:
	var dispatch_result := _request_action("back", {}, "back")
	if (
		bool(dispatch_result.get("ok", false))
		and bool(dispatch_result.get("accepted", false))
	):
		back_requested.emit(_revision)


func _toggle_mode() -> void:
	var current := String(_render_data.get("mode", "single"))
	_request_action("setMode", {"mode": "single" if current == "batch" else "batch"}, "mode")


func _on_resident_pressed(resident_id: String) -> void:
	if String(_render_data.get("mode", "single")) == "batch":
		var selected := (_render_data.get("selectedBatchResidentIds", []) as Array).has(resident_id)
		_request_action(
			"selectBatchResident",
			{"residentId": resident_id, "selected": not selected},
			"resident:%s" % resident_id,
		)
	else:
		_request_action("selectResident", {"residentId": resident_id}, "resident:%s" % resident_id)


func _on_quick_filter_pressed(filter_value: String) -> void:
	if String(_render_data.get("mode", "single")) != "batch":
		_request_action("setFilter", {"filter": filter_value}, "filter:%s" % filter_value)
		return
	match filter_value:
		"all":
			_request_action("clearBatchSelection", {}, "filter:all")
		"invalid":
			_request_action("selectInvalid", {}, "filter:invalid")
		"unassigned":
			_request_action("selectUnassigned", {}, "filter:unassigned")


func _batch_selection_matches_status(status: String) -> bool:
	if status == "all":
		return false
	var selected := _render_data.get("selectedBatchResidentIds", []) as Array
	if selected.is_empty():
		return false
	var expected: Array[String] = []
	for value: Variant in _render_data.get("residents", []) as Array:
		if value is Dictionary and String((value as Dictionary).get("bindingStatus", "")) == status:
			expected.append(String((value as Dictionary).get("residentId", "")))
	if expected.is_empty() or expected.size() != selected.size():
		return false
	for resident_id: String in expected:
		if not selected.has(resident_id):
			return false
	return true


func _selected_batch_status_counts() -> Dictionary:
	var counts := {"valid": 0, "invalid": 0, "unassigned": 0}
	var selected := _render_data.get("selectedBatchResidentIds", []) as Array
	for value: Variant in _render_data.get("residents", []) as Array:
		if not value is Dictionary:
			continue
		var resident := value as Dictionary
		if not selected.has(String(resident.get("residentId", ""))):
			continue
		var status := String(resident.get("bindingStatus", "unassigned"))
		counts[status] = int(counts.get(status, 0)) + 1
	return counts


func _assign_target() -> void:
	var target := _render_data.get("targetBinding", {}) as Dictionary
	var mode := String(_render_data.get("mode", "single"))
	if mode == "batch":
		_request_action(
			"assignBatch",
			{
				"residentIds": (_render_data.get("selectedBatchResidentIds", []) as Array).duplicate(),
				"llmBinding": _intent_binding(target),
			},
			"assign",
		)
	else:
		_request_action(
			"assignOne",
			{
				"residentId": String(_render_data.get("selectedResidentId", "")),
				"llmBinding": _intent_binding(target),
			},
			"assign",
		)


func _apply_draft() -> void:
	_request_action("applyDraft", {}, "apply")


func _open_completion_modal() -> void:
	var action := UiViewModel.action(_view_model, "applyDraft")
	if not CompositeDesktop.should_apply_draft(
		_render_data,
		UiViewModel.action_enabled(action),
	):
		var reason := UiViewModel.disabled_reason(action)
		if reason.is_empty():
			reason = (
			"选中的新模型还没有应用，请先完成改绑"
			if CompositeDesktop.has_pending_rebind(_render_data)
			else "仍有居民未完成有效模型分配"
		)
		action_blocked.emit(String(action.get("intent", "")), reason)
		return
	_completion_modal_open = true
	_set_completion_modal_message(
		(
			"这位新居民的模型已经配置完成\n确认后会立即进入小镇。"
			if single_resident_mode
			else "居民模型分配已更新\n确认后返回模型设置。"
			if return_to_provider_settings
			else "15 位居民的模型均已配置完成\n保存后会立即用于当前小镇。"
			if in_session_mode
			else "15 位居民的模型均已配置完成\n现在可以开始游戏。"
		)
	)
	_sync_completion_modal_visibility()


func _close_completion_modal() -> void:
	_completion_modal_open = false
	_sync_completion_modal_visibility()
	call_deferred("_restore_apply_focus")


func _start_game_from_completion_modal() -> void:
	if not _completion_modal_open:
		return
	var action := UiViewModel.action(_view_model, "applyDraft")
	var intent := String(action.get("intent", ""))
	if intent.is_empty() or not UiViewModel.action_enabled(action):
		var blocked_reason := UiViewModel.disabled_reason(action)
		if blocked_reason.is_empty():
			blocked_reason = "RESIDENT_MODEL_ASSIGNMENT_INTERFACE_MISSING"
		action_blocked.emit(intent, blocked_reason)
		_set_completion_modal_message(
			(
				"暂时无法保存模型分配\n%s\n当前草稿已保留。"
				if in_session_mode or return_to_provider_settings
				else "暂时无法开始游戏\n%s\n当前草稿已保留。"
			)
			% UiViewModel.player_reason(blocked_reason)
		)
		return
	_pending_focus_id = "modal_start"
	var payload := {"revision": _revision}
	action_dispatch_started.emit(intent, payload.duplicate(true))
	# Let the shared loading overlay draw once before synchronous Provider/model
	# validation begins, otherwise the accepted click appears to freeze.
	await get_tree().process_frame
	if not _completion_modal_open:
		return
	var result := _dispatch_prepared_action(intent, payload)
	if bool(result.get("ok", false)) and bool(result.get("accepted", false)):
		# Draft acceptance only confirms the assignment. The Host owns the
		# remaining startup transition and may still need this modal to report a
		# validation/runtime failure without racing a local close.
		return
	var reason := UiViewModel.error_message(_view_model)
	if reason.is_empty():
		reason = UiViewModel.player_reason(
			String(result.get("errorCode", "ACTION_REJECTED"))
		)
	_set_completion_modal_message(
		(
			"暂时无法保存模型分配\n%s\n当前草稿已保留。"
			if in_session_mode or return_to_provider_settings
			else "暂时无法开始游戏\n%s\n当前草稿已保留。"
		)
		% reason
	)


func _set_completion_modal_message(message: String) -> void:
	if _native_modal_body != null:
		_native_modal_body.text = message
	if is_instance_valid(_composite_desktop):
		_composite_desktop.call("set_completion_modal_message", message)


func _sync_completion_modal_visibility() -> void:
	var composite_visible := is_instance_valid(_composite_host) and _composite_host.visible
	if is_instance_valid(_composite_desktop):
		_composite_desktop.call(
			"set_completion_modal_visible",
			_completion_modal_open and composite_visible,
		)
	if _native_modal_backdrop != null:
		_native_modal_backdrop.visible = _completion_modal_open and not composite_visible
	if _completion_modal_open and composite_visible:
		_composite_desktop.call_deferred("focus_initial")
	elif (
		_completion_modal_open
		and _native_modal_start_button != null
		and not _native_modal_start_button.disabled
	):
		_native_modal_start_button.call_deferred("grab_focus")


func _restore_apply_focus() -> void:
	if is_instance_valid(_composite_host) and _composite_host.visible:
		var target := _composite_desktop.call("focus_target", "apply") as Control
		if target != null and not (target as Button).disabled:
			target.grab_focus()
	elif _apply_button != null and not _apply_button.disabled:
		_apply_button.grab_focus()


func _intent_binding(binding: Dictionary) -> Dictionary:
	return {
		"mode": "model",
		"providerId": String(binding.get("providerId", "")),
		"modelId": String(binding.get("modelId", "")),
	}


func _apply_responsive_layout() -> void:
	if not is_node_ready():
		_layout_queued = false
		return
	_apply_responsive_layout_for_size(get_viewport_rect().size)
	_layout_queued = false


func _queue_responsive_layout() -> void:
	if _layout_queued:
		return
	_layout_queued = true
	_apply_responsive_layout.call_deferred()


func _apply_responsive_layout_for_size(viewport_size: Vector2) -> void:
	_layout_profile = layout_profile_for_size(viewport_size)
	var mobile_runtime := MOBILE_UI_PROFILE.is_mobile_runtime()
	var use_accepted_composite := (
		not mobile_runtime
		and viewport_size.x >= 1720.0
		and viewport_size.y >= 981.0
	)
	_native_root.visible = not use_accepted_composite
	_composite_host.visible = use_accepted_composite
	if _native_modal_panel != null:
		var modal_width := clampf(viewport_size.x - 48.0, 300.0, 720.0)
		var modal_height := clampf(viewport_size.y - 48.0, 320.0, 420.0)
		_native_modal_panel.offset_left = -round(modal_width * 0.5)
		_native_modal_panel.offset_top = -round(modal_height * 0.5)
		_native_modal_panel.offset_right = round(modal_width * 0.5)
		_native_modal_panel.offset_bottom = round(modal_height * 0.5)
	var stacked := mobile_runtime or _layout_profile in ["compact", "narrow_landscape", "portrait"]
	_body.vertical = stacked
	_header_top.vertical = mobile_runtime or _layout_profile in ["narrow_landscape", "portrait"]
	_summary_grid.columns = (
		1
		if mobile_runtime or _layout_profile in ["narrow_landscape", "portrait"]
		else 2 if _layout_profile == "compact" else 4
	)
	_provider_list.vertical = mobile_runtime or _layout_profile in ["narrow_landscape", "portrait"]
	_page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_page_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	if stacked:
		_page_panel.custom_minimum_size = Vector2(
			maxf(viewport_size.x - (32.0 if mobile_runtime else 48.0), 320.0),
			2020.0,
		)
		for section in [_resident_section, _catalog_section, _inspector_section]:
			section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			section.custom_minimum_size = Vector2(0, 580)
	else:
		_page_panel.custom_minimum_size = Vector2(minf(maxf(viewport_size.x - 48.0, 1060.0), 1840.0), maxf(viewport_size.y - 40.0, 820.0))
		_resident_section.custom_minimum_size = Vector2(360 if _layout_profile == "wide" else 320, 0)
		_catalog_section.custom_minimum_size = Vector2(560 if _layout_profile == "wide" else 440, 0)
		_inspector_section.custom_minimum_size = Vector2(430 if _layout_profile == "wide" else 360, 0)
		_resident_section.size_flags_horizontal = Control.SIZE_FILL
		_catalog_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_inspector_section.size_flags_horizontal = Control.SIZE_FILL
	if mobile_runtime:
		_apply_mobile_section_minimum_sizes()
	if _resident_scroll != null:
		_resident_scroll.vertical_scroll_mode = (
			ScrollContainer.SCROLL_MODE_DISABLED
			if mobile_runtime
			else ScrollContainer.SCROLL_MODE_AUTO
		)
	if _model_scroll != null:
		_model_scroll.vertical_scroll_mode = (
			ScrollContainer.SCROLL_MODE_DISABLED
			if mobile_runtime
			else ScrollContainer.SCROLL_MODE_AUTO
		)
	_sync_completion_modal_visibility()


func _apply_mobile_section_minimum_sizes() -> void:
	if _resident_list == null or _model_list == null:
		return
	# The two desktop list panes become ordinary content on a phone. Give the
	# outer page enough height for their rows so a finger can move through one
	# continuous page instead of having to find a nested scrollbar.
	var resident_height := maxf(
		580.0,
		210.0 + float(_resident_list.get_child_count()) * 90.0,
	)
	var catalog_height := maxf(
		580.0,
		320.0
			+ float(_provider_list.get_child_count()) * 66.0
			+ float(_model_list.get_child_count()) * 142.0,
	)
	var inspector_height := 820.0
	_resident_section.custom_minimum_size.y = resident_height
	_catalog_section.custom_minimum_size.y = catalog_height
	_inspector_section.custom_minimum_size.y = inspector_height
	_page_panel.custom_minimum_size.y = (
		resident_height + catalog_height + inspector_height + 180.0
	)


func _refresh_from_adapter() -> void:
	if _adapter == null or not _adapter.has_method("get_view_model"):
		_set_contract_error("TownUiAdapter 未提供 resident_model_assignment ViewModel。")
		return
	var incoming: Variant = _adapter.call("get_view_model", SCOPE)
	if not incoming is Dictionary:
		_set_contract_error("TownUiAdapter 返回了无效 ViewModel。")
		return
	apply_view_model(incoming as Dictionary)


func _on_adapter_view_model_changed(scope: String, view_model: Dictionary) -> void:
	if scope == SCOPE:
		apply_view_model(view_model)


func _disconnect_adapter() -> void:
	UI_SIGNALS.disconnect_view_model(
		_adapter,
		Callable(self, "_on_adapter_view_model_changed"),
	)


func _validate_contract(view_model: Dictionary, data: Dictionary) -> PackedStringArray:
	var issues := PackedStringArray()
	for field in REQUIRED_DATA_FIELDS:
		if not data.has(field):
			issues.append("resident_model_assignment.data 缺少 %s" % field)
	var status := String(view_model.get("status", ""))
	if status == "disabled" and (data.get("residents", []) as Array).is_empty():
		return issues
	if String(data.get("capabilityMode", "")) != "formal":
		issues.append("capabilityMode 必须为 formal")
	if String(data.get("source", "")) != "runtime":
		issues.append("source 必须为 runtime")
	var expected_count := 1 if single_resident_mode else SLOT_COUNT
	if int(data.get("residentCount", 0)) != expected_count:
		issues.append("residentCount 必须为 %d" % expected_count)
	var residents_value: Variant = data.get("residents", [])
	if not residents_value is Array or (residents_value as Array).size() != expected_count:
		issues.append("residents 必须包含 %d 个槽位" % expected_count)
	else:
		for value: Variant in residents_value as Array:
			if not value is Dictionary:
				issues.append("resident 必须为 Dictionary")
				continue
			var resident := value as Dictionary
			var binding_value: Variant = resident.get("llmBinding", {})
			if not binding_value is Dictionary:
				issues.append("resident.llmBinding 必须为 Dictionary")
				continue
			var binding := binding_value as Dictionary
			if String(binding.get("mode", "")) != "model":
				issues.append("resident.llmBinding.mode 必须为 model")
	var actions := view_model.get("actions", {}) as Dictionary
	for action_key in REQUIRED_ACTIONS:
		if not actions.get(action_key, {}) is Dictionary:
			issues.append("resident_model_assignment.actions 缺少 %s" % action_key)
	return issues


func _set_contract_error(message: String) -> void:
	_contract_error = message
	if is_node_ready():
		_contract_label.visible = true
		_contract_label.text = message


func _section_panel(owner_id: String, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = owner_id
	panel.add_theme_stylebox_override("panel", PageTheme.section(accent))
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_register_border_owner(panel, owner_id, "section_frame")
	return panel


func _section_title(text_value: String, gate_id: String) -> Label:
	var label := _label(text_value, 26, PageTheme.INK, gate_id)
	label.custom_minimum_size.y = 48
	return label


func _summary_badge(text_value: String, tone: String, gate_id: String) -> Label:
	var panel := PanelContainer.new()
	panel.name = "%sSlot" % gate_id
	panel.add_theme_stylebox_override("panel", PageTheme.inset(tone))
	panel.custom_minimum_size = Vector2(180, 48)
	_register_border_owner(panel, "%sSlot" % gate_id, "content_slot")
	var label := _label(text_value, 18, PageTheme.INK, gate_id)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return label


func _info_row(
	parent: Control,
	caption: String,
	value: String,
	gate_id: String,
	tone: String,
) -> Label:
	var panel := PanelContainer.new()
	panel.name = "%sRow" % gate_id
	panel.add_theme_stylebox_override("panel", PageTheme.inset(tone))
	panel.custom_minimum_size = Vector2(0, 108)
	_register_border_owner(panel, "InspectorInfoRow:%s" % gate_id, "content_slot")
	parent.add_child(panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	panel.add_child(stack)
	var caption_label := _label(caption, 17, PageTheme.INK_MUTED, "%sCaption" % gate_id)
	stack.add_child(caption_label)
	var value_label := _label(value, 18, PageTheme.INK, gate_id)
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value_label.max_lines_visible = 2
	value_label.custom_minimum_size.y = 52
	stack.add_child(value_label)
	return value_label


func _inline_info_row(
	parent: Control,
	caption: String,
	value: String,
	gate_id: String,
) -> Label:
	var panel := PanelContainer.new()
	panel.name = "%sRow" % gate_id
	panel.add_theme_stylebox_override("panel", PageTheme.inset("normal"))
	panel.custom_minimum_size = Vector2(0, 64)
	_register_border_owner(panel, "ModelDetailRow:%s" % gate_id, "content_slot")
	parent.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	var caption_label := _label(caption, 17, PageTheme.INK_MUTED, "%sCaption" % gate_id)
	caption_label.custom_minimum_size.x = 96
	row.add_child(caption_label)
	var value_label := _label(value, 18, PageTheme.INK, gate_id)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.tooltip_text = value
	row.add_child(value_label)
	return value_label


func _label(text_value: String, font_size: int, color: Color, gate_id: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("line_spacing", maxi(2, int(ceil(font_size * 0.125))))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_to_group("resident_model_assignment_text_slot")
	label.set_meta("gate_id", gate_id)
	return label


func _button(text_value: String, font_size: int, variant: String, gate_id: String) -> Button:
	var button := Button.new()
	button.name = gate_id
	button.text = text_value
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size.y = TOUCH_TARGET_MIN
	button.add_theme_font_size_override("font_size", font_size)
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.clip_text = true
	PageTheme.apply_button(button, variant)
	button.add_to_group("resident_model_assignment_touch_target")
	button.set_meta("gate_id", gate_id)
	_attach_native_asset_motion(button, gate_id)
	return button


func _attach_native_asset_motion(button: Button, gate_id: String) -> void:
	button.set_meta("asset_animation_id", "native:%s" % gate_id)
	button.set_meta("asset_animation_profile", "responsive_theme_skin")
	button.set_meta("native_motion_hovered", false)
	button.set_meta("native_motion_focused", false)
	button.set_meta("native_motion_pressed", false)
	button.mouse_entered.connect(_on_native_motion_flag.bind(button, "hovered", true))
	button.mouse_exited.connect(_on_native_motion_flag.bind(button, "hovered", false))
	button.focus_entered.connect(_on_native_motion_flag.bind(button, "focused", true))
	button.focus_exited.connect(_on_native_motion_flag.bind(button, "focused", false))
	button.button_down.connect(_on_native_motion_flag.bind(button, "pressed", true))
	button.button_up.connect(_on_native_motion_flag.bind(button, "pressed", false))


func _on_native_motion_flag(button: Button, flag: String, enabled: bool) -> void:
	if not is_instance_valid(button):
		return
	button.set_meta("native_motion_%s" % flag, enabled)
	_refresh_native_asset_motion(button)


func _refresh_native_asset_motion(button: Button, immediate := false) -> void:
	if not is_instance_valid(button):
		return
	var target := Color.WHITE
	if button.disabled:
		target = Color(0.82, 0.80, 0.74, 1.0)
	elif bool(button.get_meta("native_motion_pressed", false)):
		target = Color(0.88, 0.86, 0.80, 1.0)
	elif (
		bool(button.get_meta("native_motion_hovered", false))
		or bool(button.get_meta("native_motion_focused", false))
	):
		target = Color(1.05, 1.025, 0.97, 1.0)
	var instance_id := button.get_instance_id()
	var existing := _native_motion_tweens.get(instance_id) as Tween
	if existing != null and existing.is_valid():
		existing.kill()
	var reduced_motion := bool(ProjectSettings.get_setting("accessibility/reduce_ui_motion", false))
	if immediate or reduced_motion or not button.is_inside_tree():
		button.self_modulate = target
		return
	var tween := button.create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "self_modulate", target, 0.11)
	_native_motion_tweens[instance_id] = tween


func _register_border_owner(control: Control, owner_id: String, level: String) -> void:
	control.add_to_group("resident_model_assignment_border_owner")
	control.set_meta("owner_id", owner_id)
	control.set_meta("owner_level", level)


func _binding_summary(resident: Dictionary) -> String:
	if resident.is_empty():
		return "尚未分配"
	var provider := String(resident.get("providerDisplayName", ""))
	var model := String(resident.get("modelDisplayName", ""))
	if provider.is_empty() or model.is_empty():
		return "尚未分配"
	return "%s / %s" % [provider, model]


func _status_symbol(status: String) -> String:
	match status:
		"valid":
			return "●"
		"invalid":
			return "!"
	return "○"


func _status_color(status: String) -> Color:
	match status:
		"valid":
			return PageTheme.MOSS
		"invalid":
			return PageTheme.TERRACOTTA
	return PageTheme.INK_MUTED


func _find_provider(provider_id: String) -> Dictionary:
	for value: Variant in _render_data.get("providers", []) as Array:
		if value is Dictionary and String((value as Dictionary).get("providerId", "")) == provider_id:
			return (value as Dictionary).duplicate(true)
	return {}


func _find_model(provider_id: String, model_id: String) -> Dictionary:
	var provider := _find_provider(provider_id)
	for value: Variant in provider.get("models", []) as Array:
		if value is Dictionary and String((value as Dictionary).get("modelId", "")) == model_id:
			return (value as Dictionary).duplicate(true)
	return {}


func _clear_children(parent: Node) -> void:
	UiNodeRetirement.retire_children(parent)


func _focus_initial_control() -> void:
	if is_instance_valid(_composite_desktop) and _composite_desktop.is_visible_in_tree():
		_composite_desktop.call("focus_initial")
		return
	if is_instance_valid(_back_button) and not _back_button.disabled:
		_back_button.grab_focus()


func _restore_pending_focus() -> void:
	if _pending_focus_id.is_empty() or not is_inside_tree():
		return
	var target: Control
	if is_instance_valid(_composite_desktop) and _composite_desktop.is_visible_in_tree():
		target = _composite_desktop.call("focus_target", _pending_focus_id) as Control
	if _pending_focus_id == "back":
		target = target if target != null else _back_button
	elif _pending_focus_id == "mode":
		target = target if target != null else _mode_button
	elif _pending_focus_id == "refresh":
		target = target if target != null else _refresh_button
	elif _pending_focus_id == "assign":
		target = target if target != null else _assign_button
	elif _pending_focus_id == "apply":
		target = target if target != null else _apply_button
	elif _pending_focus_id.begins_with("resident:"):
		target = target if target != null else _resident_buttons.get(_pending_focus_id.trim_prefix("resident:")) as Control
	elif _pending_focus_id.begins_with("provider:"):
		target = target if target != null else _provider_buttons.get(_pending_focus_id.trim_prefix("provider:")) as Control
	elif _pending_focus_id.begins_with("model:"):
		target = target if target != null else _model_buttons.get(_pending_focus_id.trim_prefix("model:")) as Control
	elif _pending_focus_id.begins_with("filter:"):
		target = target if target != null else _filter_buttons.get(_pending_focus_id.trim_prefix("filter:")) as Control
	_pending_focus_id = ""
	if target != null and is_instance_valid(target) and target.is_visible_in_tree() and not (target is BaseButton and (target as BaseButton).disabled):
		target.grab_focus()


func _rect_array(rect: Rect2) -> Array[float]:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
