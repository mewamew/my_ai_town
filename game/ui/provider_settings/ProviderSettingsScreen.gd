class_name ProviderSettingsScreen
extends Control


const UI_VIEW_MODEL := preload(
	"res://ui/common/AiTownUiViewModel.gd"
)
const UiNodeRetirement := preload("res://ui/common/AiTownUiNodeRetirement.gd")


signal intent_requested(intent: StringName, payload: Dictionary)

const UiViewModel = preload("res://ui/common/AiTownUiViewModel.gd")
const ProviderTheme = preload(
	"res://ui/provider_settings/ProviderSettingsTheme.gd"
)
const ProviderButtonMotion = preload(
	"res://ui/provider_settings/ProviderSettingsButtonMotion.gd"
)
const CompositeDesktop = preload(
	"res://ui/provider_settings/composite/"
	+ "ProviderSettingsCompositeDesktop.gd"
)
const FormalDialog = preload(
	"res://ui/common/formal_dialog/FormalConfirmationDialog.gd"
)
const CONNECTION_NAME_INPUT_TEXTURE := preload(
	"res://assets/ui/common/formal_dialog_v1/runtime/"
	+ "formal_dialog_connection_name_input_v2_1024x192.png"
)

const SCOPE := &"provider_settings"
const MAP_TEXTURE_PATH := "res://world/maps/town/assets/town.png"
const MINIMUM_TOUCH_SIZE := Vector2(48, 48)
const CUSTOM_MODEL_GROUP_NAME := "自定义模型"

var _adapter: Object
var _view_model: Dictionary = {}
var _last_confirmed_data: Dictionary = {}
var _render_data: Dictionary = {}
var _current_revision := -1
var _selected_provider_id := ""
var _draft_key := ""
var _draft_key_baseline := ""
var _draft_key_dirty := false
var _draft_base_url := ""
var _draft_api_model := ""
var _draft_provider_id := ""
var _discard_confirmation: FormalDialog
var _delete_model_confirmation: FormalDialog
var _delete_connection_confirmation: FormalDialog
var _connection_name_dialog: FormalDialog
var _connection_name_edit: LineEdit
var _connection_name_mode := ""
var _connection_name_provider_id := ""
var _delete_model_blocked_dialog: FormalDialog
var _delete_model_blocked_revision := -1
var _pending_model_deletion: Dictionary = {}
var _last_model_deletion: Dictionary = {}
var _pending_connection_deletion: Dictionary = {}
var _last_connection_deletion: Dictionary = {}
var _blocked_model_assignment_context: Dictionary = {}
var _pending_provider_selection: Dictionary = {}
var _discard_confirmation_action := ""
var _layout_profile := ""
var _layout_root: Control
var _rebuild_queued := false
var _show_key := false
var _last_auto_discovery_request_id := ""
var _provider_page := -1
var _model_page := -1
var _key_edit: LineEdit
var _save_key_button: Button
var _base_url_edit: LineEdit
var _api_model_edit: LineEdit
var _status_label: Label
var _check_button: Button
var _formal_badge: Label
var _provider_list_root: Control
var _detail_root: Control
var _detail_scroll: ScrollContainer
var _composite_desktop: ProviderSettingsCompositeDesktop


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	theme = ProviderTheme.create()
	_build_background()
	_build_discard_confirmation()
	_build_delete_model_confirmation()
	_build_delete_connection_confirmation()
	_build_connection_name_dialog()
	_build_delete_model_blocked_dialog()
	if _view_model.is_empty():
		_view_model = _empty_view_model()
		_render_data = (
			_view_model.get("data", {}) as Dictionary
		).duplicate(true)
	resized.connect(_queue_layout_rebuild)
	_queue_layout_rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if request_back():
			get_viewport().set_input_as_handled()


func request_back() -> bool:
	if _has_unsaved_local_draft():
		_show_discard_confirmation("exit", {})
		return true
	_request_host_back()
	return true


func _build_discard_confirmation() -> void:
	if is_instance_valid(_discard_confirmation):
		return
	_discard_confirmation = FormalDialog.new()
	_discard_confirmation.name = "UnsavedProviderConfirmation"
	_discard_confirmation.title = "放弃未保存的修改？"
	_discard_confirmation.ok_button_text = "放弃修改"
	_discard_confirmation.cancel_button_text = "继续编辑"
	_discard_confirmation.confirmed.connect(_confirm_discard_action)
	add_child(_discard_confirmation)


func _build_delete_model_confirmation() -> void:
	if is_instance_valid(_delete_model_confirmation):
		return
	_delete_model_confirmation = FormalDialog.new()
	_delete_model_confirmation.name = "DeleteCustomModelConfirmation"
	_delete_model_confirmation.title = "删除这个自定义模型？"
	_delete_model_confirmation.ok_button_text = "删除模型"
	_delete_model_confirmation.cancel_button_text = "取消"
	_delete_model_confirmation.semantic_icon = (
		ProviderTheme.custom_model_delete_texture()
	)
	_delete_model_confirmation.confirmed.connect(_confirm_delete_custom_model)
	_delete_model_confirmation.canceled.connect(func() -> void:
		_pending_model_deletion.clear()
	)
	add_child(_delete_model_confirmation)


func _build_delete_model_blocked_dialog() -> void:
	if is_instance_valid(_delete_model_blocked_dialog):
		return
	_delete_model_blocked_dialog = FormalDialog.new()
	_delete_model_blocked_dialog.name = "DeleteCustomModelBlocked"
	_delete_model_blocked_dialog.title = "暂时无法删除"
	_delete_model_blocked_dialog.dialog_text = (
		"仍有居民正在使用这个模型。请先在居民模型分配页面为他们更换模型，再回来删除。"
	)
	_delete_model_blocked_dialog.ok_button_text = "去分配模型"
	_delete_model_blocked_dialog.cancel_button_text = "知道了"
	_delete_model_blocked_dialog.semantic_kind = "warning"
	_delete_model_blocked_dialog.semantic_icon = (
		ProviderTheme.custom_model_delete_blocked_texture()
	)
	_delete_model_blocked_dialog.confirmed.connect(
		_open_blocked_model_assignment
	)
	add_child(_delete_model_blocked_dialog)


func _build_delete_connection_confirmation() -> void:
	if is_instance_valid(_delete_connection_confirmation):
		return
	_delete_connection_confirmation = FormalDialog.new()
	_delete_connection_confirmation.name = "DeleteCompatibleConnectionConfirmation"
	_delete_connection_confirmation.title = "删除这个兼容连接？"
	_delete_connection_confirmation.ok_button_text = "删除连接"
	_delete_connection_confirmation.cancel_button_text = "取消"
	_delete_connection_confirmation.semantic_kind = "warning"
	_delete_connection_confirmation.semantic_icon = (
		ProviderTheme.custom_model_delete_blocked_texture()
	)
	_delete_connection_confirmation.confirmed.connect(
		_confirm_delete_compatible_connection
	)
	_delete_connection_confirmation.canceled.connect(func() -> void:
		_pending_connection_deletion.clear()
	)
	add_child(_delete_connection_confirmation)


func _build_connection_name_dialog() -> void:
	if is_instance_valid(_connection_name_dialog):
		return
	_connection_name_dialog = FormalDialog.new()
	_connection_name_dialog.name = "CompatibleConnectionNameDialog"
	_connection_name_dialog.semantic_kind = "info"
	_connection_name_dialog.custom_content_frame_texture = (
		CONNECTION_NAME_INPUT_TEXTURE
	)
	_connection_name_dialog.cancel_button_text = "取消"
	_connection_name_dialog.confirmed.connect(_confirm_connection_name)
	_connection_name_dialog.canceled.connect(_clear_connection_name_dialog)
	_connection_name_edit = LineEdit.new()
	_connection_name_edit.name = "CompatibleConnectionNameInput"
	_connection_name_edit.max_length = 48
	_connection_name_edit.placeholder_text = "例如 公司中转站"
	_connection_name_edit.text_submitted.connect(func(_value: String) -> void:
		_confirm_connection_name()
	)
	_connection_name_dialog.set_custom_content(_connection_name_edit)
	add_child(_connection_name_dialog)


func _request_create_compatible_connection() -> void:
	_connection_name_mode = "create"
	_connection_name_provider_id = ""
	_connection_name_edit.text = ""
	_connection_name_dialog.title = "新建兼容连接"
	_connection_name_dialog.dialog_text = (
		"填写一个容易识别的名称。也可以暂时留空，保存地址后会自动使用服务域名。"
	)
	_connection_name_dialog.ok_button_text = "创建连接"
	_connection_name_dialog.popup_centered()
	_connection_name_edit.grab_focus.call_deferred()


func _request_rename_compatible_connection(
	provider_id: String,
	display_name: String,
) -> void:
	if provider_id.is_empty():
		return
	_connection_name_mode = "rename"
	_connection_name_provider_id = provider_id
	_connection_name_edit.text = display_name
	_connection_name_edit.select_all()
	_connection_name_dialog.title = "重命名兼容连接"
	_connection_name_dialog.dialog_text = (
		"名称只用于区分连接，不会改变服务地址、模型或居民分配。"
	)
	_connection_name_dialog.ok_button_text = "保存名称"
	_connection_name_dialog.popup_centered()
	_connection_name_edit.grab_focus.call_deferred()


func _confirm_connection_name() -> void:
	var display_name := _connection_name_edit.text.strip_edges()
	if _connection_name_mode == "create":
		_dispatch_intent(
			&"provider_settings.create_compatible_connection",
			{"displayName": display_name},
		)
	elif _connection_name_mode == "rename":
		_dispatch_intent(
			&"provider_settings.rename_compatible_connection",
			{
				"providerId": _connection_name_provider_id,
				"displayName": display_name,
			},
		)
	_connection_name_dialog.visible = false
	_clear_connection_name_dialog()


func _clear_connection_name_dialog() -> void:
	_connection_name_mode = ""
	_connection_name_provider_id = ""
	if is_instance_valid(_connection_name_edit):
		_connection_name_edit.text = ""


func _request_delete_custom_model(provider_id: String, api_model: String) -> void:
	if provider_id.is_empty() or api_model.is_empty():
		return
	_pending_model_deletion = {
		"providerId": provider_id,
		"apiModel": api_model,
	}
	_delete_model_confirmation.dialog_text = (
		"将删除“%s”。删除后无法恢复。"
		% api_model
	)
	_delete_model_confirmation.popup_centered()


func _confirm_delete_custom_model() -> void:
	if _pending_model_deletion.is_empty():
		return
	var payload := _pending_model_deletion.duplicate(true)
	_last_model_deletion = payload.duplicate(true)
	_pending_model_deletion.clear()
	_dispatch_intent(&"provider_settings.delete_api_model", payload)


func _request_delete_compatible_connection(
	provider_id: String,
	display_name: String,
) -> void:
	if provider_id.is_empty():
		return
	_pending_connection_deletion = {
		"providerId": provider_id,
		"displayName": display_name,
	}
	_delete_connection_confirmation.dialog_text = (
		"将删除“%s”及其模型配置。删除后无法恢复。" % display_name
	)
	_delete_connection_confirmation.popup_centered()


func _confirm_delete_compatible_connection() -> void:
	if _pending_connection_deletion.is_empty():
		return
	var payload := _pending_connection_deletion.duplicate(true)
	_last_connection_deletion = payload.duplicate(true)
	_pending_connection_deletion.clear()
	_dispatch_intent(
		&"provider_settings.delete_compatible_connection",
		{"providerId": String(payload.get("providerId", ""))},
	)


func _open_blocked_model_assignment() -> void:
	if _blocked_model_assignment_context.is_empty():
		return
	_dispatch_intent(
		&"provider_settings.open_model_assignment",
		_blocked_model_assignment_context.duplicate(true),
	)


func _show_discard_confirmation(
	action: String,
	provider: Dictionary,
) -> void:
	_discard_confirmation_action = action
	_pending_provider_selection = provider.duplicate(true)
	_discard_confirmation.dialog_text = (
		"模型设置还没有保存。确定放弃修改并退出吗？"
		if action == "exit"
		else "当前模型设置还没有保存。确定放弃修改并切换服务吗？"
	)
	_discard_confirmation.popup_centered(Vector2i(620, 260))


func _confirm_discard_action() -> void:
	var action := _discard_confirmation_action
	var provider := _pending_provider_selection.duplicate(true)
	_discard_confirmation_action = ""
	_pending_provider_selection.clear()
	if action == "switch_provider":
		_perform_provider_selection(provider)
		return
	_request_host_back()


func _has_unsaved_local_draft() -> bool:
	if _draft_key_dirty:
		return true
	var selected := _find_provider(_selected_provider_id)
	if selected.is_empty():
		return false
	return (
		_draft_base_url != String(selected.get("baseUrl", ""))
		or not _draft_api_model.is_empty()
	)


func bind_adapter(adapter: Object) -> void:
	if _adapter == adapter:
		return
	if (
		_adapter != null
		and _adapter.has_signal("view_model_changed")
		and _adapter.view_model_changed.is_connected(
			_on_adapter_view_model_changed
		)
	):
		_adapter.view_model_changed.disconnect(
			_on_adapter_view_model_changed
		)
	_selected_provider_id = ""
	_draft_provider_id = ""
	_draft_key = ""
	_draft_key_baseline = ""
	_draft_key_dirty = false
	_draft_base_url = ""
	_draft_api_model = ""
	_show_key = false
	_last_auto_discovery_request_id = ""
	_provider_page = -1
	_model_page = -1
	_pending_provider_selection.clear()
	_discard_confirmation_action = ""
	_adapter = adapter
	if _adapter == null:
		return
	if _adapter.has_signal("view_model_changed"):
		_adapter.view_model_changed.connect(
			_on_adapter_view_model_changed
		)
	if _adapter.has_method("get_view_model"):
		var incoming: Variant = _adapter.call(
			"get_view_model",
			SCOPE
		)
		if typeof(incoming) == TYPE_DICTIONARY:
			apply_view_model(incoming as Dictionary)


func apply_view_model(view_model: Dictionary) -> bool:
	var issues := UiViewModel.validate(
		view_model,
		"ProviderSettingsScreen"
	)
	if not issues.is_empty():
		for issue: String in issues:
			push_error(issue)
		return false
	if UiViewModel.scope(view_model) != SCOPE:
		push_error(
			"ProviderSettingsScreen scope mismatch: %s"
			% str(UiViewModel.scope(view_model))
		)
		return false
	var incoming_revision := UiViewModel.revision(view_model)
	if (
		_current_revision >= 0
		and incoming_revision < _current_revision
	):
		return false

	var incoming_data := UiViewModel.data(view_model)
	var operation_status := UiViewModel.operation_status(view_model)
	if (
		operation_status != &"rejected"
		and not incoming_data.is_empty()
	):
		_last_confirmed_data = incoming_data.duplicate(true)
	if (
		operation_status == &"rejected"
		and not _last_confirmed_data.is_empty()
	):
		_render_data = _last_confirmed_data.duplicate(true)
	else:
		_render_data = UiViewModel.data_for_render(
			view_model,
			_last_confirmed_data
		)
	if _render_data.is_empty():
		_render_data = _last_confirmed_data.duplicate(true)
	_view_model = view_model.duplicate(true)
	_current_revision = incoming_revision
	_present_delete_model_blocked_error(view_model, incoming_revision)
	var operation := view_model.get("operation", {}) as Dictionary
	var operation_intent := String(operation.get("intent", ""))
	var operation_status_text := String(operation.get("status", ""))
	var incoming_selected := str(
		_render_data.get("selectedProviderId", "")
	)
	if (
		_selected_provider_id.is_empty()
		or _find_provider(_selected_provider_id).is_empty()
	):
		_selected_provider_id = incoming_selected
		_provider_page = -1
		_model_page = -1
	var selected := _find_provider(_selected_provider_id)
	if not selected.is_empty():
		if _draft_provider_id != _selected_provider_id:
			_draft_provider_id = _selected_provider_id
			_draft_key = ""
			_draft_key_baseline = ""
			_draft_key_dirty = false
			_show_key = false
			_draft_base_url = str(selected.get("baseUrl", ""))
			_draft_api_model = ""
		elif (
			operation_status_text == "success"
			and operation_intent == "provider_settings.save_base_url"
		):
			_draft_base_url = str(selected.get("baseUrl", ""))
		elif (
			operation_status_text == "success"
			and operation_intent == "provider_settings.save_connection"
		):
			_draft_base_url = str(selected.get("baseUrl", ""))
			_draft_key = ""
			_draft_key_baseline = ""
			_draft_key_dirty = false
			_show_key = false
			var request_id := String(operation.get("requestId", ""))
			if request_id != _last_auto_discovery_request_id:
				_last_auto_discovery_request_id = request_id
				call_deferred(
					"_auto_discover_saved_connection",
					_selected_provider_id,
				)
		elif (
			operation_status_text == "success"
			and operation_intent == "provider_settings.save_api_model"
		):
			_draft_api_model = ""
	if (
		operation_status_text == "success"
		and operation_intent == "provider_settings.save_key"
	):
		_draft_key = ""
		_draft_key_baseline = ""
		_draft_key_dirty = false
		_show_key = false
	if (
		operation_status_text == "success"
		and operation_intent == "provider_settings.delete_key"
	):
		_draft_key = ""
		_draft_key_baseline = ""
		_draft_key_dirty = false
		_show_key = false
	_queue_layout_rebuild()
	return true


func _auto_discover_saved_connection(provider_id: String) -> void:
	if provider_id.is_empty() or not is_inside_tree():
		return
	var provider := _find_provider(provider_id)
	if provider.is_empty() or not bool(provider.get("customGroup", false)):
		return
	_dispatch_intent(
		&"provider_settings.discover_models",
		{"providerId": provider_id},
	)


func _present_delete_model_blocked_error(
	view_model: Dictionary,
	revision: int,
) -> void:
	if revision == _delete_model_blocked_revision:
		return
	var error_value: Variant = view_model.get("error", null)
	if not error_value is Dictionary:
		return
	var error_data := error_value as Dictionary
	var error_code := String(error_data.get("code", ""))
	if error_code not in ["PROVIDER_API_MODEL_IN_USE", "PROVIDER_CONNECTION_IN_USE"]:
		return
	var operation := view_model.get("operation", {}) as Dictionary
	var operation_intent := String(operation.get("intent", ""))
	if operation_intent not in [
		"provider_settings.delete_api_model",
		"provider_settings.delete_compatible_connection",
	]:
		return
	_delete_model_blocked_revision = revision
	if is_instance_valid(_delete_model_blocked_dialog):
		var resident_ids := (
			error_data.get("details", []) as Array
		).duplicate(true)
		var connection_delete := error_code == "PROVIDER_CONNECTION_IN_USE"
		var model_id := (
			""
			if connection_delete
			else String(_last_model_deletion.get("apiModel", ""))
		)
		var provider_id := String(
			_last_connection_deletion.get("providerId", "")
			if connection_delete
			else _last_model_deletion.get("providerId", "")
		)
		_blocked_model_assignment_context = {
			"providerId": provider_id,
			"modelId": model_id,
			"residentIds": resident_ids,
		}
		_delete_model_blocked_dialog.dialog_text = (
			(
				"这个连接仍分配给 %d 位居民。\n请先为这些居民更换模型，再回来删除。"
				% resident_ids.size()
			)
			if connection_delete
			else (
				"“%s”仍分配给 %d 位居民。\n请先为这些居民更换模型，再回来删除。"
				% [model_id, resident_ids.size()]
			)
		)
		_delete_model_blocked_dialog.popup_centered()


func current_revision() -> int:
	return _current_revision


func current_layout_profile() -> String:
	return _layout_profile


func current_view_model() -> Dictionary:
	return _view_model.duplicate(true)


func runtime_gate_snapshot() -> Dictionary:
	var text_slots: Array = []
	var touch_targets: Array = []
	var regions: Array = []
	var content_surfaces: Array = []
	var border_owners: Array = []
	if not is_instance_valid(_layout_root):
		return {
			"profile": _layout_profile,
			"textSlots": text_slots,
			"touchTargets": touch_targets,
			"regions": regions,
		}
	for node: Node in get_tree().get_nodes_in_group(
		"provider_settings_text_slot"
	):
		if not is_ancestor_of(node):
			continue
		var label := node as Label
		if label == null or not label.is_visible_in_tree():
			continue
		var font := label.get_theme_font("font")
		var font_size := label.get_theme_font_size("font_size")
		text_slots.append({
			"id": str(label.get_meta("gate_id", label.name)),
			"text": label.text,
			"rect": _rect_to_array(
				Rect2(label.global_position, label.size)
			),
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
			"ownerRect": _gate_owner_rect(label),
			"paperRect": _gate_paper_rect(label),
		})
	for node: Node in get_tree().get_nodes_in_group(
		"provider_settings_touch_target"
	):
		if not is_ancestor_of(node):
			continue
		var control := node as Control
		if control == null or not control.is_visible_in_tree():
			continue
		touch_targets.append({
			"id": str(control.get_meta("gate_id", control.name)),
			"rect": _rect_to_array(
				Rect2(control.global_position, control.size)
			),
			"focusMode": control.focus_mode,
			"disabled": (
				bool((control as BaseButton).disabled)
				if control is BaseButton
				else false
			),
			"scrollReachable": _is_scroll_reachable(control),
			"ownerRect": _gate_parent_owner_rect(control),
		})
		if control is Button:
			var button := control as Button
			if not button.text.is_empty():
				var button_font := button.get_theme_font("font")
				var button_font_size := button.get_theme_font_size(
					"font_size"
				)
				var button_line_height := button_font.get_height(
					button_font_size
				)
				var button_text_size := button_font.get_string_size(
					button.text,
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					button_font_size
				)
				var button_paper := _gate_paper_rect(button)
				var button_paper_rect := (
					_array_to_rect(button_paper)
					if not button_paper.is_empty()
					else Rect2(button.global_position, button.size)
				)
				var rendered_button_text_width := minf(
					button_text_size.x,
					button_paper_rect.size.x
				)
				var button_text_rect := Rect2(
					button_paper_rect.position + Vector2(
						(
							button_paper_rect.size.x
							- rendered_button_text_width
						) * 0.5,
						(
							button_paper_rect.size.y
							- button_line_height
						) * 0.5
					),
					Vector2(
						rendered_button_text_width,
						button_line_height
					)
				)
				text_slots.append({
					"id": "%s_text" % str(
						control.get_meta("gate_id", control.name)
					),
					"text": button.text,
					"rect": _rect_to_array(
						button_text_rect
					),
					"fontSize": button_font_size,
					"lineHeight": button_line_height,
					"textWidth": button_text_size.x,
					"wrap": false,
					"ellipsis": true,
					"maxLines": 1,
					"ownerRect": _rect_to_array(
						Rect2(button.global_position, button.size)
					),
					"paperRect": _gate_paper_rect(button),
				})
		elif control is LineEdit:
			var edit := control as LineEdit
			var edit_gate_id := str(
				control.get_meta("gate_id", control.name)
			)
			var sensitive := edit_gate_id == "api_key_input"
			var edit_text := edit.placeholder_text
			if not edit.text.is_empty():
				edit_text = (
					"••••••••••••••••" if sensitive else edit.text
				)
			var edit_font := edit.get_theme_font("font")
			var edit_font_size := edit.get_theme_font_size(
				"font_size"
			)
			var edit_line_height := edit_font.get_height(
				edit_font_size
			)
			var edit_text_size := edit_font.get_string_size(
				edit_text,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				edit_font_size
			)
			var edit_paper := _gate_paper_rect(edit)
			var edit_paper_rect := (
				_array_to_rect(edit_paper)
				if not edit_paper.is_empty()
				else Rect2(edit.global_position, edit.size)
			)
			var edit_text_rect := Rect2(
				edit_paper_rect.position + Vector2(
					0,
					(edit_paper_rect.size.y - edit_line_height) * 0.5
				),
				Vector2(
					minf(edit_text_size.x, edit_paper_rect.size.x),
					edit_line_height
				)
			)
			text_slots.append({
				"id": "%s_text" % edit_gate_id,
				"text": edit_text,
				"sensitive": sensitive,
				"rect": _rect_to_array(edit_text_rect),
				"fontSize": edit_font_size,
				"lineHeight": edit_line_height,
				"textWidth": edit_text_size.x,
				"wrap": false,
				"ellipsis": true,
				"maxLines": 1,
				"ownerRect": _rect_to_array(
					Rect2(edit.global_position, edit.size)
				),
				"paperRect": edit_paper,
			})
	for node: Node in get_tree().get_nodes_in_group(
		"provider_settings_region"
	):
		if not is_ancestor_of(node):
			continue
		var control := node as Control
		if control == null or not control.is_visible_in_tree():
			continue
		regions.append({
			"id": str(control.get_meta("gate_id", control.name)),
			"rect": _rect_to_array(
				Rect2(control.global_position, control.size)
			),
		})
	for node: Node in get_tree().get_nodes_in_group(
		"provider_settings_content_surface"
	):
		if not is_ancestor_of(node):
			continue
		var control := node as Control
		if control == null:
			continue
		var minimum := control.get_combined_minimum_size()
		content_surfaces.append({
			"name": control.name,
			"rect": _rect_to_array(
				Rect2(control.global_position, control.size)
			),
			"minimumSize": [minimum.x, minimum.y],
		})
	for node: Node in get_tree().get_nodes_in_group(
		"provider_settings_border_owner"
	):
		if not is_ancestor_of(node):
			continue
		var control := node as Control
		if control == null or not control.is_visible_in_tree():
			continue
		border_owners.append({
			"id": str(control.get_meta("ownership_id", control.name)),
			"level": str(control.get_meta("owner_level", "")),
			"assetId": str(control.get_meta("asset_id", "")),
			"componentType": str(
				control.get_meta("component_type", "")
			),
			"rect": _rect_to_array(
				Rect2(control.global_position, control.size)
			),
			"paperRect": _gate_paper_rect(control),
			"parentOwnerId": _parent_border_owner_id(control),
		})
	return {
		"profile": _layout_profile,
		"layoutVariant": (
			"composite"
			if is_instance_valid(_composite_desktop)
			else "responsive"
		),
		"revision": _current_revision,
		"formalReady": bool(_render_data.get("formalReady", false)),
		"source": str(_render_data.get("source", "")),
		"capabilityMode": str(
			_render_data.get("capabilityMode", "")
		),
		"operationStatus": str(
			(_view_model.get("operation", {}) as Dictionary)
				.get("status", "")
		),
		"selectedProviderId": _selected_provider_id,
		"textSlots": text_slots,
		"touchTargets": touch_targets,
		"regions": regions,
		"contentSurfaces": content_surfaces,
		"borderOwners": border_owners,
		"keySecret": _key_edit.secret if _key_edit != null else true,
		"detailScrollRange": _detail_scroll_range(),
	}


func runtime_gate_scroll_to_end() -> void:
	if not is_instance_valid(_detail_scroll):
		return
	_detail_scroll.scroll_vertical = 1000000


func runtime_gate_scroll_to_start() -> void:
	if not is_instance_valid(_detail_scroll):
		return
	_detail_scroll.scroll_vertical = 0


func _build_background() -> void:
	var map_texture := ResourceLoader.load(
		MAP_TEXTURE_PATH,
		"Texture2D"
	) as Texture2D
	if map_texture != null:
		var background := TextureRect.new()
		background.name = "TownVisualAnchor"
		background.set_anchors_and_offsets_preset(
			Control.PRESET_FULL_RECT
		)
		background.texture = map_texture
		background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		background.stretch_mode = (
			TextureRect.STRETCH_KEEP_ASPECT_COVERED
		)
		background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(background)
	var shade := ColorRect.new()
	shade.name = "BackdropShade"
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = ProviderTheme.OVERLAY
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)


func _queue_layout_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("_rebuild_layout")


func _rebuild_layout() -> void:
	_rebuild_queued = false
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0 or viewport_size.y <= 0:
		return
	var input_focus_state := _capture_input_focus_state()
	_layout_profile = _profile_for(viewport_size)
	if is_instance_valid(_layout_root):
		UiNodeRetirement.retire(_layout_root)
	_layout_root = null
	_composite_desktop = null
	_key_edit = null
	_save_key_button = null
	_base_url_edit = null
	_status_label = null
	_check_button = null
	_formal_badge = null
	_provider_list_root = null
	_detail_root = null
	_detail_scroll = null
	if _use_composite_desktop(viewport_size):
		_rebuild_composite_desktop(viewport_size)
		_refresh_operation_state()
		_schedule_focus_after_rebuild(input_focus_state)
		return
	_layout_root = MarginContainer.new()
	_layout_root.name = "ResponsiveSafeMargin"
	_layout_root.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	_layout_root.add_to_group("provider_settings_region")
	_layout_root.set_meta("gate_id", "safe_margin")
	var safe := _safe_insets(viewport_size)
	var base_margin := _base_margin_for(_layout_profile)
	_layout_root.add_theme_constant_override(
		"margin_left",
		int(maxf(base_margin, safe.x))
	)
	_layout_root.add_theme_constant_override(
		"margin_top",
		int(maxf(base_margin, safe.y))
	)
	_layout_root.add_theme_constant_override(
		"margin_right",
		int(maxf(base_margin, safe.z))
	)
	_layout_root.add_theme_constant_override(
		"margin_bottom",
		int(maxf(base_margin, safe.w))
	)
	add_child(_layout_root)

	var board := PanelContainer.new()
	board.name = "SettingsBoard"
	board.add_theme_stylebox_override(
		"panel",
		ProviderTheme.board_panel(
			_layout_profile != "desktop_wide"
		)
	)
	board.add_to_group("provider_settings_region")
	board.set_meta("gate_id", "settings_board")
	_register_border_owner(
		board,
		"page_shell",
		"page_shell",
		"ui.provider-settings.page-shell.v1",
		"page_shell_composite",
		(
			[44, 28, 56, 48]
			if _layout_profile == "desktop_wide"
			else [24, 20, 24, 20]
		)
	)
	_layout_root.add_child(board)

	var page := VBoxContainer.new()
	page.name = "PageVBox"
	page.add_theme_constant_override(
		"separation",
		16 if _layout_profile == "desktop_wide" else 10
	)
	board.add_child(page)
	page.add_child(_build_header())
	var separator := HSeparator.new()
	separator.custom_minimum_size.y = 4
	_register_border_owner(
		separator,
		"header_main_divider",
		"section_frame",
		"ui.provider-settings.divider.header-main",
		"separator",
		[0, 0, 0, 0]
	)
	page.add_child(separator)
	page.add_child(_build_main())
	_refresh_operation_state()
	_schedule_focus_after_rebuild(input_focus_state)


func _capture_input_focus_state() -> Dictionary:
	if not is_inside_tree():
		return {}
	var focus_owner := get_viewport().gui_get_focus_owner()
	var field := ""
	if focus_owner == _key_edit:
		field = "api_key"
	elif focus_owner == _base_url_edit:
		field = "base_url"
	elif focus_owner == _api_model_edit:
		field = "api_model"
	if field.is_empty() or not focus_owner is LineEdit:
		return {}
	var edit := focus_owner as LineEdit
	var state := {
		"field": field,
		"caretColumn": edit.get_caret_column(),
		"hasSelection": edit.has_selection(),
	}
	if edit.has_selection():
		state["selectionFrom"] = edit.get_selection_from_column()
		state["selectionTo"] = edit.get_selection_to_column()
	return state


func _schedule_focus_after_rebuild(input_focus_state: Dictionary) -> void:
	if input_focus_state.is_empty():
		call_deferred("_focus_initial_control")
		return
	call_deferred("_restore_input_focus_state", input_focus_state)


func _restore_input_focus_state(input_focus_state: Dictionary) -> void:
	if not is_inside_tree() or not is_instance_valid(_layout_root):
		return
	var field := String(input_focus_state.get("field", ""))
	var edit := _key_edit if field == "api_key" else (
		_api_model_edit if field == "api_model" else _base_url_edit
	)
	if edit == null or not edit.is_visible_in_tree() or not edit.editable:
		_focus_initial_control()
		return
	edit.grab_focus()
	edit.set_caret_column(clampi(
		int(input_focus_state.get("caretColumn", edit.text.length())),
		0,
		edit.text.length(),
	))
	if bool(input_focus_state.get("hasSelection", false)):
		edit.select(
			clampi(int(input_focus_state.get("selectionFrom", 0)), 0, edit.text.length()),
			clampi(int(input_focus_state.get("selectionTo", 0)), 0, edit.text.length()),
		)


func _use_composite_desktop(viewport_size: Vector2) -> bool:
	return viewport_size.x >= 1280.0 and viewport_size.y >= 720.0


func _rebuild_composite_desktop(viewport_size: Vector2) -> void:
	_composite_desktop = CompositeDesktop.new()
	_composite_desktop.name = "CompositeDesktopRoot"
	_layout_root = _composite_desktop
	add_child(_layout_root)
	var composite_data := _render_data.duplicate(true)
	var visible_providers := _visible_providers()
	composite_data["providers"] = visible_providers
	var visible_available := 0
	var visible_enabled_models := 0
	for provider: Dictionary in visible_providers:
		if bool(provider.get("available", false)):
			visible_available += 1
		for model_value: Variant in provider.get("models", []) as Array:
			if (
				model_value is Dictionary
				and bool((model_value as Dictionary).get("enabled", false))
			):
				visible_enabled_models += 1
	composite_data["summary"] = {
		"availableProviderCount": visible_available,
		"enabledModelCount": visible_enabled_models,
	}
	var configured := _composite_desktop.configure(
		_view_model,
		composite_data,
		_selected_provider_id,
		_draft_key,
		_draft_key_dirty,
		_draft_base_url,
		_draft_api_model,
		_show_key,
		_provider_page,
		_model_page,
		viewport_size
	)
	if not configured:
		push_error("Provider composite desktop failed to configure.")
		return
	_composite_desktop.ui_action.connect(
		_on_composite_ui_action
	)
	_composite_desktop.controls_rebuilt.connect(
		_sync_composite_controls
	)
	_composite_desktop.pagination_changed.connect(
		_on_composite_pagination_changed
	)
	_sync_composite_controls()


func _sync_composite_controls() -> void:
	if not is_instance_valid(_composite_desktop):
		return
	_key_edit = _composite_desktop.key_edit
	_save_key_button = _composite_desktop.find_child(
		"SaveKeyButton",
		true,
		false,
	) as Button
	_base_url_edit = _composite_desktop.base_url_edit
	_api_model_edit = _composite_desktop.api_model_edit
	_status_label = _composite_desktop.status_label
	_check_button = _composite_desktop.check_button
	_formal_badge = _composite_desktop.formal_badge
	_provider_list_root = _composite_desktop.provider_selector
	_detail_root = _composite_desktop.provider_detail
	_sync_key_save_enabled()


func _on_composite_pagination_changed(
	provider_page: int,
	model_page: int,
) -> void:
	_provider_page = provider_page
	_model_page = model_page


func _on_composite_ui_action(
	action: StringName,
	payload: Dictionary
) -> void:
	match action:
		&"ui.draft_key":
			_draft_key = str(payload.get("value", ""))
			_draft_key_dirty = (
				not _draft_key.is_empty()
				and _draft_key != _draft_key_baseline
			)
			_sync_key_save_enabled()
		&"ui.draft_base_url":
			_draft_base_url = str(payload.get("value", ""))
		&"ui.draft_api_model":
			_draft_api_model = str(payload.get("value", ""))
		&"ui.request_delete_api_model":
			_request_delete_custom_model(
				str(payload.get("providerId", "")),
				str(payload.get("apiModel", "")),
			)
		&"ui.request_delete_compatible_connection":
			_request_delete_compatible_connection(
				str(payload.get("providerId", "")),
				str(payload.get("displayName", "兼容接口")),
			)
		&"ui.request_create_compatible_connection":
			_request_create_compatible_connection()
		&"ui.request_rename_compatible_connection":
			_request_rename_compatible_connection(
				str(payload.get("providerId", "")),
				str(payload.get("displayName", "兼容接口")),
			)
		&"ui.toggle_key_visibility":
			_toggle_key_visibility(_selected_provider_id)
		&"ui.save_key":
			var submitted_key := str(payload.get("apiKey", ""))
			_dispatch_intent(
				&"provider_settings.save_key",
				{
					"providerId": str(
						payload.get("providerId", "")
					),
					"apiKey": submitted_key,
				}
			)
			_queue_layout_rebuild()
		&"provider_settings.select_provider":
			var provider := _find_provider(
				str(payload.get("providerId", ""))
			)
			if not provider.is_empty():
				_select_provider(provider)
		_:
			_dispatch_intent(action, payload)


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.name = "Header"
	header.custom_minimum_size.y = _header_height()
	header.add_theme_constant_override(
		"separation",
		12 if _layout_profile == "desktop_wide" else 8
	)
	header.add_to_group("provider_settings_region")
	header.set_meta("gate_id", "header")
	_mark_content_surface(header)

	var back := _button(
		"返回",
		"quiet",
		Vector2(
			136 if _layout_profile == "desktop_wide" else 80,
			_control_height()
		)
	)
	back.name = "BackButton"
	back.set_meta("gate_id", "back")
	back.pressed.connect(func() -> void:
		request_back()
	)
	header.add_child(back)

	var title := _label(
		str(_render_data.get("pageTitle", "模型设置")),
		_page_title_font_size(),
		ProviderTheme.INK,
		"page_title"
	)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.custom_minimum_size.y = _header_height()
	header.add_child(title)

	_formal_badge = _label(
		(
			_formal_status_text()
			if not _is_phone_profile()
			else _compact_formal_status_text()
		),
		_caption_font_size(),
		ProviderTheme.WARNING,
		"formal_status"
	)
	_formal_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_formal_badge.custom_minimum_size = Vector2(
		(
			400
			if _layout_profile == "desktop_wide"
			else (220 if _layout_profile == "desktop_compact" else 72)
		),
		_control_height()
	)
	_formal_badge.text_overrun_behavior = (
		TextServer.OVERRUN_TRIM_ELLIPSIS
	)
	header.add_child(_formal_badge)
	return header


func _build_main() -> Control:
	if _layout_profile == "desktop_wide":
		var wide := HBoxContainer.new()
		wide.name = "WideMain"
		wide.size_flags_vertical = Control.SIZE_EXPAND_FILL
		wide.add_theme_constant_override("separation", 22)
		_provider_list_root = _build_provider_rail(false)
		_provider_list_root.custom_minimum_size.x = 400
		wide.add_child(_provider_list_root)
		var separator := VSeparator.new()
		separator.custom_minimum_size.x = 4
		_register_border_owner(
			separator,
			"provider_detail_divider",
			"section_frame",
			"ui.provider-settings.divider.provider-detail",
			"separator",
			[0, 0, 0, 0]
		)
		wide.add_child(separator)
		_detail_root = _build_detail_scroll()
		_detail_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wide.add_child(_detail_root)
		return wide

	var compact := VBoxContainer.new()
	compact.name = "CompactMain"
	compact.size_flags_vertical = Control.SIZE_EXPAND_FILL
	compact.add_theme_constant_override("separation", 8)
	_provider_list_root = (
		_build_provider_picker()
		if _is_phone_profile()
		else _build_compact_provider_tabs()
	)
	compact.add_child(_provider_list_root)
	_detail_root = _build_detail_scroll()
	_detail_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	compact.add_child(_detail_root)
	return compact


func _build_provider_rail(compact: bool) -> Control:
	var root := VBoxContainer.new()
	root.name = "ProviderSelector"
	root.add_theme_constant_override("separation", 10)
	root.add_to_group("provider_settings_region")
	root.set_meta("gate_id", "provider_selector")
	_mark_content_surface(root)
	if not compact:
		root.add_child(_section_heading("服务商", "Provider"))
	var scroll := ScrollContainer.new()
	scroll.name = "ProviderScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "ProviderCards"
	list.add_theme_constant_override("separation", 10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var providers := _visible_providers()
	if providers.is_empty():
		list.add_child(_empty_state(
			"等待表现层提供 Provider 列表。"
		))
	else:
		for provider_value: Variant in providers:
			var provider := provider_value as Dictionary
			list.add_child(_provider_card(provider, compact))
	var summary := _render_data.get("summary", {}) as Dictionary
	var summary_label := _label(
		"可用 %d · 已启用模型 %d"
		% [
			int(summary.get("availableProviderCount", 0)),
			int(summary.get("enabledModelCount", 0)),
		],
		_body_font_size(),
		ProviderTheme.INK_MUTED,
		"provider_summary"
	)
	summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary_label.custom_minimum_size.y = _line_slot_height()
	root.add_child(summary_label)
	return root


func _build_compact_provider_tabs() -> Control:
	var panel := PanelContainer.new()
	panel.name = "ProviderSelector"
	panel.custom_minimum_size.y = 64
	panel.add_theme_stylebox_override(
		"panel",
		ProviderTheme.section_panel()
	)
	panel.add_to_group("provider_settings_region")
	panel.set_meta("gate_id", "provider_selector")
	_register_border_owner(
		panel,
		"compact_provider_selector",
		"section_frame",
		"ui.provider-settings.section-frame.v1",
		"base_ninepatch",
		[24, 20, 24, 20]
	)
	_mark_content_surface(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var providers := _visible_providers()
	if providers.is_empty():
		row.add_child(_empty_state("等待 Provider 列表"))
		return panel
	for provider_value: Variant in providers:
		var provider := provider_value as Dictionary
		var provider_id := str(provider.get("providerId", ""))
		var connection := provider.get("connection", {}) as Dictionary
		var status := str(connection.get("status", "not_configured"))
		var selected := provider_id == _selected_provider_id
		var tab := _button(
			"%s · %s"
			% [
				str(provider.get("displayName", "")),
				str(connection.get("label", "配置待完成")),
			],
			"quiet",
			Vector2(220, 56)
		)
		tab.name = "ProviderTab_%s" % provider_id
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.set_meta("gate_id", "provider_%s" % provider_id)
		_register_border_owner(
			tab,
			"provider_tab_%s" % provider_id,
			"content_slot",
			"ui.provider-settings.provider-card.%s.v1"
			% _provider_card_asset_suffix(status, selected),
			"provider_semantic_card",
			[14, 12, 14, 12]
		)
		for state: String in [
			"normal",
			"hover",
			"pressed",
			"focus",
			"disabled",
		]:
			tab.add_theme_stylebox_override(
				state,
				ProviderTheme.provider_card_style(
					selected,
					_tone_for_provider_status(status),
					state
				)
			)
		tab.pressed.connect(func() -> void:
			_select_provider(provider)
		)
		row.add_child(tab)
	return panel


func _build_provider_picker() -> Control:
	var panel := PanelContainer.new()
	panel.name = "ProviderSelector"
	panel.custom_minimum_size.y = 56
	panel.add_theme_stylebox_override(
		"panel",
		ProviderTheme.section_panel()
	)
	panel.add_to_group("provider_settings_region")
	panel.set_meta("gate_id", "provider_selector")
	_register_border_owner(
		panel,
		"phone_provider_selector",
		"section_frame",
		"ui.provider-settings.section-frame.v1",
		"base_ninepatch",
		[24, 20, 24, 20]
	)
	_mark_content_surface(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	if _layout_profile == "short_landscape":
		var caption := _label(
			"服务商",
			_body_font_size(),
			ProviderTheme.INK_MUTED,
			"provider_picker_caption"
		)
		caption.custom_minimum_size = Vector2(
			72,
			_control_height()
		)
		row.add_child(caption)
	var picker := OptionButton.new()
	picker.name = "ProviderPicker"
	picker.fit_to_longest_item = false
	picker.custom_minimum_size = Vector2(160, _control_height())
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.focus_mode = Control.FOCUS_ALL
	picker.clip_text = true
	picker.add_theme_font_size_override(
		"font_size",
		_body_font_size()
	)
	picker.add_to_group("provider_settings_touch_target")
	picker.set_meta("gate_id", "provider_picker")
	ProviderButtonMotion.attach(picker)
	_register_border_owner(
		picker,
		"provider_picker",
		"operation_control",
		"ui.provider-settings.button.state-set.v1",
		"base_ninepatch_state_set",
		[16, 12, 16, 12]
	)
	_mark_content_surface(picker)
	var providers := _visible_providers()
	var selected_index := 0
	for index: int in range(providers.size()):
		var provider := providers[index] as Dictionary
		picker.add_item(str(provider.get("displayName", "")))
		picker.set_item_metadata(
			index,
			str(provider.get("providerId", ""))
		)
		if (
			str(provider.get("providerId", ""))
			== _selected_provider_id
		):
			selected_index = index
	if picker.item_count > 0:
		picker.select(selected_index)
	picker.item_selected.connect(func(index: int) -> void:
		var provider_id := str(picker.get_item_metadata(index))
		var provider := _find_provider(provider_id)
		if not provider.is_empty():
			_select_provider(provider)
	)
	row.add_child(picker)
	var selected := _find_provider(_selected_provider_id)
	var connection := selected.get("connection", {}) as Dictionary
	var status := _label(
		(
			str(connection.get("label", "待配置"))
			if _layout_profile == "short_landscape"
			else _compact_provider_status_label(
				str(connection.get("status", "not_configured"))
			)
		),
		_caption_font_size(),
		ProviderTheme.tone_dark_color(
			_tone_for_provider_status(
				str(connection.get("status", "not_configured"))
			)
		),
		"provider_picker_status"
	)
	status.custom_minimum_size = Vector2(
		108 if _layout_profile == "short_landscape" else 54,
		_control_height()
	)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(status)
	return panel


func _provider_card(
	provider: Dictionary,
	compact: bool
) -> Button:
	var provider_id := str(provider.get("providerId", ""))
	var connection := provider.get("connection", {}) as Dictionary
	var status := str(connection.get("status", "not_configured"))
	var tone := _tone_for_provider_status(status)
	var selected := provider_id == _selected_provider_id
	var card := Button.new()
	card.name = "Provider_%s" % provider_id
	card.text = ""
	card.focus_mode = Control.FOCUS_ALL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.custom_minimum_size = Vector2(
		260 if compact else 380,
		96 if compact else 156
	)
	card.add_to_group("provider_settings_touch_target")
	card.set_meta("gate_id", "provider_%s" % provider_id)
	_register_border_owner(
		card,
		"provider_card_%s" % provider_id,
		"content_slot",
		"ui.provider-settings.provider-card.%s.v1"
		% _provider_card_asset_suffix(status, selected),
		"provider_semantic_card",
		[24, 22, 28, 20]
	)
	_mark_content_surface(card)
	for state: String in [
		"normal",
		"hover",
		"pressed",
		"focus",
		"disabled",
	]:
		card.add_theme_stylebox_override(
			state,
			ProviderTheme.provider_card_style(
				selected,
				tone,
				state
			)
		)
	card.pressed.connect(func() -> void:
		_select_provider(provider)
	)
	ProviderButtonMotion.attach(card)

	var content := MarginContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in [
		"margin_left",
		"margin_top",
		"margin_right",
		"margin_bottom",
	]:
		content.add_theme_constant_override(
			side,
			(
				28
				if (
					_layout_profile == "desktop_wide"
					and side == "margin_right"
				)
				else (
					22
					if _layout_profile == "desktop_wide"
					else 12
				)
			)
		)
	card.add_child(content)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	content.add_child(row)
	var medallion := TextureRect.new()
	medallion.custom_minimum_size = Vector2(
		56 if compact else 72,
		56 if compact else 72
	)
	medallion.texture = ProviderTheme.medallion_texture(status)
	medallion.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	medallion.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	)
	medallion.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	medallion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(medallion)
	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.add_theme_constant_override("separation", 2)
	row.add_child(text_column)
	var name_label := _label(
		str(provider.get("displayName", "")),
		_body_font_size(),
		ProviderTheme.INK,
		"provider_%s_name" % provider_id
	)
	name_label.text_overrun_behavior = (
		TextServer.OVERRUN_TRIM_ELLIPSIS
	)
	name_label.custom_minimum_size.y = 48
	text_column.add_child(name_label)
	var status_label := _label(
		str(connection.get("label", "配置待完成")),
		_body_font_size(),
		ProviderTheme.tone_dark_color(tone),
		"provider_%s_status" % provider_id
	)
	status_label.text_overrun_behavior = (
		TextServer.OVERRUN_TRIM_ELLIPSIS
	)
	status_label.custom_minimum_size.y = 48
	text_column.add_child(status_label)
	return card


func _build_detail_scroll() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "ProviderDetailScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_to_group("provider_settings_region")
	scroll.set_meta("gate_id", "provider_detail")
	_detail_scroll = scroll
	var detail := _build_detail()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(detail)
	return scroll


func _build_detail() -> Control:
	var selected := _find_provider(_selected_provider_id)
	if selected.is_empty():
		return _empty_state(
			"请选择一个 Provider，或等待表现层提供完整数据。"
		)
	var detail := VBoxContainer.new()
	detail.name = "ProviderDetail"
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override(
		"separation",
		7
	)
	detail.add_child(_build_detail_header(selected))
	if bool(selected.get("customModels", false)):
		detail.add_child(_detail_divider())
		detail.add_child(_build_custom_connection_picker(selected))
	detail.add_child(_detail_divider())
	detail.add_child(_build_key_section(selected))
	detail.add_child(_detail_divider())
	detail.add_child(_build_base_url_section(selected))
	detail.add_child(_detail_divider())
	detail.add_child(_build_models_section(selected))
	detail.add_child(_detail_divider())
	detail.add_child(_build_status_section(selected))
	return detail


func _build_detail_header(provider: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.name = "ProviderHeaderPanel"
	panel.add_theme_stylebox_override(
		"panel",
		ProviderTheme.provider_header_panel()
	)
	_register_border_owner(
		panel,
		"provider_header",
		"section_frame",
		"ui.provider-settings.section-frame.v1",
		"base_ninepatch",
		[64, 24, 48, 24]
	)
	_mark_content_surface(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var title := _label(
		(
			CUSTOM_MODEL_GROUP_NAME
			if bool(provider.get("customModels", false))
			else str(provider.get("displayName", "Provider"))
		),
		_section_font_size(),
		ProviderTheme.INK,
		"selected_provider_name"
	)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.custom_minimum_size.y = _section_line_height()
	row.add_child(title)
	if bool(provider.get("customModels", false)):
		var source := _label(
			str(provider.get("displayName", "兼容接口")),
			_caption_font_size(),
			ProviderTheme.INK_MUTED,
			"selected_custom_connection",
		)
		source.custom_minimum_size = Vector2(180, _control_height())
		source.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(source)
	var toggle := _button(
		"",
		"success"
		if bool(provider.get("enabled", false))
		else "quiet",
		Vector2(
			112,
			_control_height()
		)
	)
	var provider_enabled := bool(provider.get("enabled", false))
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		toggle.add_theme_stylebox_override(
			state,
			ProviderTheme.transparent_hit_style(state),
		)
	var toggle_art := TextureRect.new()
	toggle_art.name = "ToggleArt"
	toggle_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	toggle_art.texture = ProviderTheme.provider_toggle_texture(provider_enabled)
	toggle_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	toggle_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	toggle_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	toggle_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toggle.add_child(toggle_art)
	toggle.name = "ProviderEnabledButton"
	toggle.set_meta("gate_id", "provider_enabled")
	toggle.set_meta("provider_toggle_art", true)
	toggle.set_meta("provider_toggle_enabled", provider_enabled)
	toggle.disabled = not _action_enabled("setProviderEnabled")
	toggle.tooltip_text = (
		"停用当前 Provider" if provider_enabled else "启用当前 Provider"
	)
	toggle.pressed.connect(func() -> void:
		_dispatch_intent(
			&"provider_settings.set_enabled",
			{
				"providerId": str(provider.get("providerId", "")),
				"enabled": not bool(provider.get("enabled", false)),
			}
		)
	)
	row.add_child(toggle)
	return panel


func _build_custom_connection_picker(selected: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.name = "CustomConnectionPanel"
	panel.add_theme_stylebox_override("panel", ProviderTheme.empty_style())
	_register_paper_surface(panel, [0, 0, 0, 0])
	_mark_content_surface(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	column.add_child(_section_heading(
		"连接来源",
		"Ollama、LM Studio、302.AI 和其他兼容接口统一归在这里",
	))
	var picker := OptionButton.new()
	picker.name = "CustomConnectionPicker"
	picker.custom_minimum_size = Vector2(
		220 if _is_phone_profile() else 320,
		_control_height(),
	)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.focus_mode = Control.FOCUS_ALL
	picker.add_theme_font_size_override("font_size", _body_font_size())
	picker.add_to_group("provider_settings_touch_target")
	picker.set_meta("gate_id", "custom_connection_picker")
	ProviderButtonMotion.attach(picker)
	var selected_index := 0
	var providers := _custom_providers()
	for index: int in range(providers.size()):
		var provider := providers[index]
		var label := str(provider.get("displayName", "兼容接口"))
		var connection := provider.get("connection", {}) as Dictionary
		picker.add_item("%s · %s" % [
			label,
			str(connection.get("label", "待配置")),
		])
		picker.set_item_metadata(index, str(provider.get("providerId", "")))
		if str(provider.get("providerId", "")) == str(selected.get("providerId", "")):
			selected_index = index
	if picker.item_count > 0:
		picker.select(selected_index)
	picker.item_selected.connect(func(index: int) -> void:
		var provider := _find_provider(str(picker.get_item_metadata(index)))
		if not provider.is_empty():
			_select_provider(provider)
	)
	column.add_child(picker)
	return panel


func _build_key_section(provider: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.name = "ApiKeyPanel"
	panel.add_theme_stylebox_override(
		"panel",
		ProviderTheme.empty_style()
	)
	_register_paper_surface(panel, [0, 0, 0, 0])
	_mark_content_surface(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	column.add_child(_section_heading(
		"API Key",
		"仅保存在本机" if bool(provider.get("authRequired", true)) else "可选，仅保存在本机",
	))

	var form: Container
	if _layout_profile == "desktop_wide":
		form = HBoxContainer.new()
	else:
		form = VBoxContainer.new()
	form.add_theme_constant_override("separation", 8)
	column.add_child(form)

	var key_data := provider.get("key", {}) as Dictionary
	_key_edit = LineEdit.new()
	_key_edit.name = "ApiKeyInput"
	_key_edit.secret = not _show_key
	_key_edit.secret_character = "•"
	_key_edit.placeholder_text = (
		"已安全保存，输入新 Key 可替换"
		if bool(key_data.get("saved", false))
		else (
			"请输入 API Key"
			if bool(provider.get("authRequired", true))
			else "本地服务通常无需填写"
		)
	)
	_key_edit.text = _draft_key
	_key_edit.custom_minimum_size = Vector2(
		220 if _is_phone_profile() else 320,
		_field_height()
	)
	_key_edit.add_theme_font_size_override(
		"font_size",
		_body_font_size()
	)
	_key_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_key_edit.focus_mode = Control.FOCUS_ALL
	_key_edit.add_to_group("provider_settings_touch_target")
	_key_edit.set_meta("gate_id", "api_key_input")
	_register_border_owner(
		_key_edit,
		"api_key_input",
		"content_slot",
		"ui.provider-settings.content-slot.v1",
		"base_ninepatch",
		[24, 12, 24, 12]
	)
	_key_edit.text_changed.connect(func(value: String) -> void:
		_draft_key = value
		_draft_key_dirty = (
			not value.is_empty()
			and value != _draft_key_baseline
		)
		_sync_key_save_enabled()
	)
	form.add_child(_key_edit)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(actions)
	var action_width := (
		112 if _layout_profile == "desktop_wide" else 80
	)
	var reveal := _button(
		"隐藏" if _show_key else "显示",
		"quiet",
		Vector2(action_width, _control_height())
	)
	reveal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reveal.name = "RevealKeyButton"
	reveal.set_meta("gate_id", "key_reveal")
	reveal.disabled = (
		_draft_key.is_empty()
		and not bool(key_data.get("saved", false))
	)
	reveal.pressed.connect(func() -> void:
		_toggle_key_visibility(
			str(provider.get("providerId", ""))
		)
	)
	actions.add_child(reveal)
	_save_key_button = _button(
		"保存",
		"primary",
		Vector2(action_width, _control_height())
	)
	_save_key_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_key_button.name = "SaveKeyButton"
	_save_key_button.set_meta("gate_id", "key_save")
	_sync_key_save_enabled()
	_save_key_button.pressed.connect(func() -> void:
		var submitted_key := _draft_key
		_dispatch_intent(
			&"provider_settings.save_key",
			{
				"providerId": str(provider.get("providerId", "")),
				"apiKey": submitted_key,
			}
		)
		_queue_layout_rebuild()
	)
	actions.add_child(_save_key_button)
	var delete := _button(
		"删除",
		"danger",
		Vector2(action_width, _control_height())
	)
	delete.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delete.name = "DeleteKeyButton"
	delete.set_meta("gate_id", "key_delete")
	delete.disabled = (
		not _action_enabled("deleteKey")
		or not bool(key_data.get("saved", false))
		or _operation_loading()
	)
	delete.pressed.connect(func() -> void:
		_dispatch_intent(
			&"provider_settings.delete_key",
			{"providerId": str(provider.get("providerId", ""))}
		)
	)
	actions.add_child(delete)
	return panel


func _build_base_url_section(provider: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.name = "BaseUrlPanel"
	panel.add_theme_stylebox_override(
		"panel",
		ProviderTheme.empty_style()
	)
	_register_paper_surface(panel, [0, 0, 0, 0])
	_mark_content_surface(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var default_base_url := String(provider.get("defaultBaseUrl", ""))
	column.add_child(_section_heading(
		"Base URL",
		"留空使用 %s" % default_base_url if not default_base_url.is_empty() else "请填写服务地址",
	))
	var row: Container
	if _is_phone_profile():
		row = VBoxContainer.new()
	else:
		row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	_base_url_edit = LineEdit.new()
	_base_url_edit.name = "BaseUrlInput"
	_base_url_edit.text = _draft_base_url
	_base_url_edit.placeholder_text = (
		default_base_url if not default_base_url.is_empty() else "例如 https://host/v1"
	)
	_base_url_edit.custom_minimum_size = Vector2(
		220 if _is_phone_profile() else 320,
		_field_height()
	)
	_base_url_edit.add_theme_font_size_override(
		"font_size",
		_body_font_size()
	)
	_base_url_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_base_url_edit.focus_mode = Control.FOCUS_ALL
	_base_url_edit.add_to_group("provider_settings_touch_target")
	_base_url_edit.set_meta("gate_id", "base_url_input")
	_register_border_owner(
		_base_url_edit,
		"base_url_input",
		"content_slot",
		"ui.provider-settings.content-slot.v1",
		"base_ninepatch",
		[24, 12, 24, 12]
	)
	_base_url_edit.text_changed.connect(func(value: String) -> void:
		_draft_base_url = value
	)
	row.add_child(_base_url_edit)
	var save := _button(
		"保存地址",
		"quiet",
		Vector2(
			176 if not _is_phone_profile() else 220,
			_control_height()
		)
	)
	if _is_phone_profile():
		save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save.name = "SaveBaseUrlButton"
	save.set_meta("gate_id", "base_url_save")
	save.disabled = (
		not _action_enabled("saveBaseUrl")
		or _operation_loading()
	)
	save.pressed.connect(func() -> void:
		_dispatch_intent(
			&"provider_settings.save_base_url",
			{
				"providerId": str(provider.get("providerId", "")),
				"baseUrl": _base_url_edit.text,
			}
		)
	)
	row.add_child(save)
	return panel


func _build_models_section(provider: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.name = "ModelsPanel"
	panel.add_theme_stylebox_override(
		"panel",
		ProviderTheme.empty_style()
	)
	_register_paper_surface(panel, [0, 0, 0, 0])
	_mark_content_surface(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	column.add_child(_section_heading(
		"模型与能力",
		"启用后参与连接检查"
	))
	if (
		bool(provider.get("customModels", false))
		and str(provider.get("providerId", "")) != "volcengine-ark"
	):
		column.add_child(_build_api_model_editor(provider))
	var grid := GridContainer.new()
	grid.name = "ModelGrid"
	grid.columns = 1 if _is_phone_profile() else 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	column.add_child(grid)
	var models := provider.get("models", []) as Array
	if models.is_empty():
		grid.add_child(_empty_state(
			(
				"正在读取可用模型……"
				if (
					str(provider.get("providerId", "")) == "volcengine-ark"
					and _operation_loading()
				)
				else "保存 API Key 后将自动读取可用模型。"
				if str(provider.get("providerId", "")) == "volcengine-ark"
				else "当前 Provider 没有可展示模型。"
			)
		))
	else:
		for model_value: Variant in models:
			grid.add_child(_model_card(
				provider,
				model_value as Dictionary
			))
	return panel


func _build_api_model_editor(provider: Dictionary) -> Control:
	var row: Container = (
		VBoxContainer.new() if _is_phone_profile() else HBoxContainer.new()
	)
	row.add_theme_constant_override("separation", 10)
	_api_model_edit = LineEdit.new()
	_api_model_edit.name = "ApiModelInput"
	_api_model_edit.text = _draft_api_model
	_api_model_edit.placeholder_text = "实际模型 ID，例如 gpt-4.1-mini 或 qwen3:8b"
	_api_model_edit.custom_minimum_size = Vector2(
		220 if _is_phone_profile() else 320,
		_field_height(),
	)
	_api_model_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_api_model_edit.add_to_group("provider_settings_touch_target")
	_api_model_edit.set_meta("gate_id", "api_model_input")
	_api_model_edit.text_changed.connect(func(value: String) -> void:
		_draft_api_model = value
	)
	row.add_child(_api_model_edit)
	var save := _button(
		"添加并选用",
		"quiet",
		Vector2(176 if not _is_phone_profile() else 220, _control_height()),
	)
	save.name = "SaveApiModelButton"
	save.disabled = not _action_enabled("saveApiModel") or _operation_loading()
	save.pressed.connect(func() -> void:
		_dispatch_intent(
			&"provider_settings.save_api_model",
			{
				"providerId": str(provider.get("providerId", "")),
				"apiModel": _api_model_edit.text,
			},
		)
	)
	row.add_child(save)
	var discover := _button(
		"自动获取",
		"quiet",
		Vector2(144 if not _is_phone_profile() else 220, _control_height()),
	)
	discover.name = "DiscoverModelsButton"
	discover.disabled = (
		not _action_enabled("discoverModels")
		or _operation_loading()
		or not bool(provider.get("modelCatalogSupported", false))
		or (
			bool(provider.get("authRequired", true))
			and not bool((provider.get("key", {}) as Dictionary).get("saved", false))
		)
	)
	discover.tooltip_text = (
		"当前服务需要手动填写推理接入点 ID"
		if not bool(provider.get("modelCatalogSupported", false))
		else "从服务读取模型列表，失败时仍可手动填写"
	)
	discover.pressed.connect(func() -> void:
		_dispatch_intent(
			&"provider_settings.discover_models",
			{"providerId": str(provider.get("providerId", ""))},
		)
	)
	row.add_child(discover)
	var selected_model := str(provider.get("apiModel", ""))
	var selected_model_is_custom := false
	for model_value: Variant in provider.get("models", []) as Array:
		if (
			model_value is Dictionary
			and str((model_value as Dictionary).get("modelId", "")) == selected_model
		):
			selected_model_is_custom = bool(
				(model_value as Dictionary).get("custom", false)
			)
			break
	var delete := _button(
		"删除当前",
		"danger",
		Vector2(144 if not _is_phone_profile() else 220, _control_height()),
	)
	delete.name = "DeleteApiModelButton"
	delete.disabled = (
		not _action_enabled("deleteApiModel")
		or _operation_loading()
		or selected_model.is_empty()
		or not selected_model_is_custom
	)
	delete.tooltip_text = "删除当前选中的自定义模型"
	delete.pressed.connect(func() -> void:
		_request_delete_custom_model(
			str(provider.get("providerId", "")),
			selected_model,
		)
	)
	row.add_child(delete)
	return row


func _model_card(
	provider: Dictionary,
	model: Dictionary
) -> Button:
	var enabled := bool(model.get("enabled", false))
	var model_id := str(model.get("modelId", ""))
	var card := Button.new()
	card.name = "Model_%s" % model_id
	card.text = ""
	card.focus_mode = Control.FOCUS_ALL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.custom_minimum_size = Vector2(
		320 if not _is_phone_profile() else 220,
		_model_card_height()
	)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_to_group("provider_settings_touch_target")
	card.set_meta("gate_id", "model_%s" % model_id)
	_register_border_owner(
		card,
		"model_card_%s" % model_id,
		"content_slot",
		"ui.provider-settings.provider-card.%s.v1"
		% ("selected" if enabled else "auth-error"),
		"provider_semantic_card",
		(
			[40, 28, 40, 16]
			if _layout_profile == "desktop_wide"
			else [14, 14, 14, 14]
		)
	)
	_mark_content_surface(card)
	card.disabled = (
		not _action_enabled("selectModel")
		or _operation_loading()
	)
	for state: String in [
		"normal",
		"hover",
		"pressed",
		"focus",
		"disabled",
	]:
		card.add_theme_stylebox_override(
			state,
			ProviderTheme.model_card_style(enabled, state)
		)
	card.pressed.connect(func() -> void:
		_dispatch_intent(
			&"provider_settings.select_model",
			{
				"providerId": str(provider.get("providerId", "")),
				"modelId": model_id,
				"enabled": not enabled,
			}
		)
	)
	ProviderButtonMotion.attach(card)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in [
		"margin_left",
		"margin_top",
		"margin_right",
		"margin_bottom",
	]:
		var desktop_margin := 28
		if side in ["margin_left", "margin_right"]:
			desktop_margin = 40
		elif side == "margin_bottom":
			desktop_margin = 16
		margin.add_theme_constant_override(
			side,
			desktop_margin
			if _layout_profile == "desktop_wide"
			else 14
		)
	card.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)
	var name_label := _label(
		"%s  %s"
		% [
			"已启用" if enabled else "未启用",
			str(model.get("displayName", "")),
		],
		_body_font_size(),
		ProviderTheme.MOSS_DARK if enabled else ProviderTheme.INK,
		"model_%s_name" % model_id
	)
	name_label.text_overrun_behavior = (
		TextServer.OVERRUN_TRIM_ELLIPSIS
	)
	name_label.custom_minimum_size.y = _line_slot_height()
	if enabled:
		name_label.add_theme_font_override(
			"font",
			ProviderTheme.composite_selected_font("body"),
		)
	content.add_child(name_label)
	var capability_labels: Array[String] = []
	for capability: Variant in model.get("capabilities", []) as Array:
		capability_labels.append(
			_capability_compact_label(str(capability))
		)
	var capability_line := _label(
		" · ".join(capability_labels),
		_caption_font_size(),
		ProviderTheme.MOSS_DARK if enabled else ProviderTheme.INK_MUTED,
		"model_%s_capabilities" % model_id
	)
	capability_line.custom_minimum_size.y = _caption_line_height()
	capability_line.text_overrun_behavior = (
		TextServer.OVERRUN_TRIM_ELLIPSIS
	)
	if enabled:
		capability_line.add_theme_font_override(
			"font",
			ProviderTheme.composite_selected_font("small"),
		)
	content.add_child(capability_line)
	return card


func _build_status_section(provider: Dictionary) -> Control:
	var connection := provider.get("connection", {}) as Dictionary
	var operation := _view_model.get("operation", {}) as Dictionary
	var error_value: Variant = _view_model.get("error", null)
	var error_data := (
		error_value as Dictionary
		if typeof(error_value) == TYPE_DICTIONARY
		else {}
	)
	var tone := _operation_tone(
		str(operation.get("status", "idle")),
		str(error_data.get("kind", "")),
		str(connection.get("status", ""))
	)
	var panel := PanelContainer.new()
	panel.name = "ConnectionStatusPanel"
	panel.add_theme_stylebox_override(
		"panel",
		ProviderTheme.status_style(tone)
	)
	_register_border_owner(
		panel,
		"connection_status",
		"content_slot",
		"ui.provider-settings.content-slot.v1",
		"base_ninepatch",
		[18, 14, 18, 14]
	)
	_mark_content_surface(panel)
	var row: Container
	if _is_phone_profile():
		row = VBoxContainer.new()
	else:
		row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	var status_icon := TextureRect.new()
	status_icon.name = "ConnectionStatusIcon"
	status_icon.custom_minimum_size = Vector2(
		84 if _layout_profile == "desktop_wide" else 56,
		84 if _layout_profile == "desktop_wide" else 56
	)
	status_icon.texture = (
		ProviderTheme.provider_checking_connection_texture()
		if _operation_loading()
		else ProviderTheme.medallion_texture(
			str(connection.get("status", "not_configured"))
		)
	)
	status_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	status_icon.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	)
	status_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	status_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_icon.add_to_group("provider_settings_icon_owner")
	status_icon.set_meta("gate_id", "connection_status_icon")
	row.add_child(status_icon)
	if _operation_loading():
		_animate_checking_status_icon(status_icon)
	var status_column := VBoxContainer.new()
	status_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_column.add_theme_constant_override("separation", 4)
	row.add_child(status_column)
	_status_label = _label(
		_operation_title(operation, connection, error_data),
		_body_font_size(),
		ProviderTheme.tone_dark_color(tone),
		"connection_status_title"
	)
	_status_label.custom_minimum_size.y = _line_slot_height()
	status_column.add_child(_status_label)
	var message := _label(
		(
			"正在等待 %s 响应" % _checking_provider_name(provider)
			if _operation_loading()
			else _operation_message(operation, connection, error_data)
		),
		_body_font_size(),
		ProviderTheme.INK_MUTED,
		"connection_status_message"
	)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.max_lines_visible = 2
	message.custom_minimum_size.y = _message_slot_height()
	status_column.add_child(message)
	_check_button = _button(
		"检查中…"
		if _operation_loading()
		else "检查连接",
		"primary",
		Vector2(
			248 if _layout_profile == "desktop_wide" else 180,
			_control_height()
		)
	)
	if _is_phone_profile():
		_check_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_check_button.name = "CheckConnectionButton"
	_check_button.set_meta("gate_id", "check_connection")
	_check_button.disabled = (
		not _action_enabled("checkConnection")
		or _operation_loading()
	)
	_check_button.pressed.connect(func() -> void:
		_dispatch_intent(
			&"provider_settings.check_connection",
			{"providerId": str(provider.get("providerId", ""))}
		)
	)
	row.add_child(_check_button)
	ProviderButtonMotion.set_loading_state(
		_check_button,
		_operation_loading(),
	)
	return panel


func _animate_checking_status_icon(icon: TextureRect) -> void:
	if icon == null or not icon.is_inside_tree():
		return
	icon.pivot_offset = icon.size * 0.5
	var tween := icon.create_tween()
	tween.set_loops()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(icon, "modulate:a", 0.66, 0.48)
	tween.parallel().tween_property(icon, "scale", Vector2(1.04, 1.04), 0.48)
	tween.tween_property(icon, "modulate:a", 1.0, 0.48)
	tween.parallel().tween_property(icon, "scale", Vector2.ONE, 0.48)


func _checking_provider_name(provider: Dictionary) -> String:
	var display_name := String(
		provider.get("displayName", provider.get("providerId", "模型服务"))
	).strip_edges()
	return display_name.replace("（本地）", "").strip_edges()


func _detail_divider() -> HSeparator:
	var divider := HSeparator.new()
	divider.custom_minimum_size.y = 4
	_register_border_owner(
		divider,
		"detail_divider_%d" % divider.get_instance_id(),
		"section_frame",
		"ui.provider-settings.divider.detail",
		"separator",
		[0, 0, 0, 0]
	)
	return divider


func _refresh_operation_state() -> void:
	_sync_key_save_enabled()
	if _formal_badge != null:
		if is_instance_valid(_composite_desktop):
			_formal_badge.text = _formal_status_text()
		else:
			_formal_badge.text = (
				_compact_formal_status_text()
				if _is_phone_profile()
				else _formal_status_text()
			)


func _sync_key_save_enabled() -> void:
	if not is_instance_valid(_save_key_button):
		return
	_save_key_button.disabled = (
		_draft_key.is_empty()
		or not _draft_key_dirty
		or not _action_enabled("saveKey")
		or _operation_loading()
	)


func _section_heading(left_text: String, right_text: String) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = _line_slot_height()
	row.add_theme_constant_override("separation", 8)
	var left := _label(
		left_text,
		_body_font_size(),
		ProviderTheme.INK,
		"%s_heading" % left_text
	)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var right := _label(
		right_text,
		_caption_font_size(),
		ProviderTheme.INK_MUTED,
		"%s_caption" % left_text
	)
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	right.custom_minimum_size.x = (
		280
		if _layout_profile == "desktop_wide"
		else (96 if _is_phone_profile() else 160)
	)
	row.add_child(right)
	return row


func _empty_state(text_value: String) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(
		"panel",
		ProviderTheme.status_style("disabled")
	)
	_register_border_owner(
		panel,
		"empty_state_%d" % panel.get_instance_id(),
		"content_slot",
		"ui.provider-settings.content-slot.v1",
		"base_ninepatch",
		[18, 14, 18, 14]
	)
	panel.custom_minimum_size = Vector2(320, 104)
	_mark_content_surface(panel)
	var label := _label(
		text_value,
		_body_font_size(),
		ProviderTheme.INK_MUTED,
		"empty_state"
	)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.max_lines_visible = 2
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return panel


func _button(
	text_value: String,
	variant: String,
	minimum_size: Vector2
) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(
		maxf(minimum_size.x, MINIMUM_TOUCH_SIZE.x),
		maxf(minimum_size.y, MINIMUM_TOUCH_SIZE.y)
	)
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.add_to_group("provider_settings_touch_target")
	button.set_meta("gate_id", text_value)
	_register_border_owner(
		button,
		"button_%d" % button.get_instance_id(),
		"operation_control",
		"ui.provider-settings.button.state-set.v1",
		"base_ninepatch_state_set",
		[16, 12, 16, 12]
	)
	button.add_theme_font_size_override(
		"font_size",
		_body_font_size()
	)
	_mark_content_surface(button)
	for state: String in [
		"normal",
		"hover",
		"pressed",
		"focus",
		"disabled",
	]:
		button.add_theme_stylebox_override(
			state,
			ProviderTheme.button_style(variant, state)
		)
	for color_id: String in [
		"font_color",
		"font_hover_color",
		"font_pressed_color",
		"font_focus_color",
	]:
		button.add_theme_color_override(
			color_id,
			ProviderTheme.PAPER_LIGHT
		)
	ProviderButtonMotion.attach(button)
	return button


func _label(
	text_value: String,
	font_size: int,
	color: Color,
	gate_id: String
) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("line_spacing", 8)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_to_group("provider_settings_text_slot")
	label.set_meta("gate_id", gate_id)
	return label


func _dispatch_intent(
	intent: StringName,
	payload: Dictionary
) -> void:
	if intent == &"provider_settings.back":
		request_back()
		return
	var envelope := payload.duplicate(true)
	envelope["revision"] = _current_revision
	if intent == &"provider_settings.open_model_assignment":
		intent_requested.emit(intent, envelope)
		return
	if _adapter != null and _adapter.has_method("dispatch"):
		_adapter.call("dispatch", intent, envelope)
	intent_requested.emit(intent, envelope)


func _toggle_key_visibility(provider_id: String) -> void:
	if _show_key:
		_show_key = false
		_queue_layout_rebuild()
		return
	if _draft_key.is_empty():
		if (
			_adapter == null
			or not _adapter.has_method("reveal_provider_api_key")
		):
			return
		var revealed := _adapter.call(
			"reveal_provider_api_key",
			provider_id,
		) as Dictionary
		if not bool(revealed.get("ok", false)):
			return
		var api_key_value: Variant = revealed.get("apiKey")
		if typeof(api_key_value) != TYPE_STRING:
			return
		_draft_key = api_key_value as String
		_draft_key_baseline = _draft_key
		_draft_key_dirty = false
	if _draft_key.is_empty():
		return
	_show_key = true
	_queue_layout_rebuild()


func _request_host_back() -> void:
	intent_requested.emit(
		&"provider_settings.back",
		{"revision": _current_revision},
	)


func _focus_initial_control() -> void:
	if not is_inside_tree() or not is_instance_valid(_layout_root):
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	if is_instance_valid(focus_owner) and is_ancestor_of(focus_owner):
		return
	var back := _layout_root.find_child("BackButton", true, false) as Control
	if (
		back != null
		and back.is_visible_in_tree()
		and back.focus_mode != Control.FOCUS_NONE
		and (not back is BaseButton or not (back as BaseButton).disabled)
	):
		back.grab_focus()


func _on_adapter_view_model_changed(
	scope_value: Variant,
	view_model: Dictionary
) -> void:
	if StringName(scope_value) != SCOPE:
		return
	apply_view_model(view_model)


func _find_provider(provider_id: String) -> Dictionary:
	for provider_value: Variant in (
		_render_data.get("providers", []) as Array
	):
		var provider := provider_value as Dictionary
		if str(provider.get("providerId", "")) == provider_id:
			return provider
	return {}


func _custom_providers() -> Array[Dictionary]:
	var discovered: Array[Dictionary] = []
	for provider_value: Variant in _render_data.get("providers", []) as Array:
		if not provider_value is Dictionary:
			continue
		var provider := provider_value as Dictionary
		if _provider_belongs_to_custom_group(provider):
			discovered.append(provider)
	var result: Array[Dictionary] = []
	for preset_id: String in [
		"ollama",
		"ollama-cloud",
		"lm-studio",
		"302-ai",
	]:
		for provider: Dictionary in discovered:
			if str(provider.get("providerId", "")) == preset_id:
				result.append(provider)
				break
	for provider: Dictionary in discovered:
		if str(provider.get("providerId", "")) in [
			"ollama",
			"ollama-cloud",
			"lm-studio",
			"302-ai",
		]:
			continue
		if str(provider.get("providerId", "")) == "openai-compatible":
			continue
		result.append(provider)
	return result


func _visible_providers() -> Array[Dictionary]:
	var official_providers: Array[Dictionary] = []
	var custom_group: Dictionary = {}
	for provider_value: Variant in _render_data.get("providers", []) as Array:
		if not provider_value is Dictionary:
			continue
		var provider := provider_value as Dictionary
		if not _provider_belongs_to_custom_group(provider):
			official_providers.append(provider)
			continue
		if str(provider.get("providerId", "")) == "openai-compatible":
			continue
		if (
			custom_group.is_empty()
			or str(provider.get("providerId", "")) == _selected_provider_id
		):
			custom_group = provider.duplicate(true)
	if not custom_group.is_empty():
		custom_group["displayName"] = CUSTOM_MODEL_GROUP_NAME
		custom_group["customGroup"] = true
		custom_group["customConnections"] = _custom_providers()
	var result: Array[Dictionary] = []
	for leading_provider_id: String in ["deepseek", "volcengine-ark"]:
		for provider: Dictionary in official_providers:
			if str(provider.get("providerId", "")) == leading_provider_id:
				result.append(provider)
				break
	if not custom_group.is_empty():
		result.append(custom_group)
	for provider: Dictionary in official_providers:
		if str(provider.get("providerId", "")) in ["deepseek", "volcengine-ark"]:
			continue
		result.append(provider)
	return result


func _provider_belongs_to_custom_group(provider: Dictionary) -> bool:
	if provider.has("customGroup"):
		return bool(provider.get("customGroup", false))
	var provider_id := str(provider.get("providerId", ""))
	return provider_id in [
		"openai-compatible",
		"302-ai",
		"ollama",
		"ollama-cloud",
		"lm-studio",
	] or provider_id.begins_with("openai-compatible-")


func _action_enabled(action_key: String) -> bool:
	var action := UiViewModel.action(_view_model, action_key)
	return UiViewModel.action_enabled(action)


func _operation_loading() -> bool:
	return UiViewModel.operation_status(_view_model) == &"loading"


func _select_provider(provider: Dictionary) -> void:
	var provider_id := str(provider.get("providerId", ""))
	if provider_id.is_empty():
		return
	if (
		provider_id != _selected_provider_id
		and _has_unsaved_local_draft()
	):
		_show_discard_confirmation("switch_provider", provider)
		return
	_perform_provider_selection(provider)


func _perform_provider_selection(provider: Dictionary) -> void:
	var provider_id := str(provider.get("providerId", ""))
	if provider_id.is_empty():
		return
	_selected_provider_id = provider_id
	_draft_provider_id = provider_id
	_provider_page = -1
	_model_page = -1
	_draft_key = ""
	_draft_key_baseline = ""
	_draft_key_dirty = false
	_show_key = false
	_draft_base_url = str(provider.get("baseUrl", ""))
	_draft_api_model = ""
	_dispatch_intent(
		&"provider_settings.select_provider",
		{"providerId": provider_id}
	)
	_queue_layout_rebuild()


func _formal_status_text() -> String:
	var published := str(
		_render_data.get("formalStatusLabel", "")
	).strip_edges()
	if not published.is_empty():
		return published
	if _is_placeholder_data():
		return "开发预览"
	return (
		"连接已通过"
		if bool(_render_data.get("formalReady", false))
		else "请完成模型设置"
	)


func _compact_formal_status_text() -> String:
	if _is_placeholder_data():
		return "开发预览"
	return (
		"已连接"
		if bool(_render_data.get("formalReady", false))
		else "待配置"
	)


func _is_placeholder_data() -> bool:
	return (
		str(_render_data.get("source", "")) == "placeholder"
		or str(_render_data.get("capabilityMode", "")) == "placeholder"
	)


func _compact_provider_status_label(status: String) -> String:
	match status:
		"available":
			return "可用"
		"checking":
			return "检查中"
		"unchecked":
			return "待检查"
		"auth_failed":
			return "鉴权失败"
		"billing_failed":
			return "账户异常"
		"rate_limited":
			return "限流"
		"timeout":
			return "超时"
		"network_unavailable":
			return "网络错误"
		"disabled":
			return "已停用"
		"unavailable":
			return "不可用"
		_:
			return "待配置"


func _operation_title(
	operation: Dictionary,
	connection: Dictionary,
	error_data: Dictionary
) -> String:
	var status := str(operation.get("status", "idle"))
	match status:
		"loading":
			return "正在检查连接"
		"success":
			return "连接检查通过"
		"rejected":
			return "配置需要修正"
		"error":
			var connection_label := str(
				connection.get("label", "")
			).strip_edges()
			return (
				connection_label
				if not connection_label.is_empty()
				else "连接检查失败"
			)
		"disabled":
			return (
				"开发预览不可用"
				if _is_placeholder_data()
				else "当前无法检查连接"
			)
		_:
			return str(
				connection.get("label", "等待检查")
			)


func _operation_message(
	operation: Dictionary,
	connection: Dictionary,
	error_data: Dictionary
) -> String:
	if not error_data.is_empty():
		return _public_operation_error_message(error_data)
	var operation_message := str(operation.get("message", ""))
	if not operation_message.is_empty():
		return operation_message
	var connection_message := str(connection.get("message", ""))
	if not connection_message.is_empty():
		return connection_message
	return "保存 Key、Base URL 和模型选择后可以检查连接。"


func _public_operation_error_message(error_data: Dictionary) -> String:
	return UiViewModel.public_operation_error_message(
		error_data,
		"连接检查失败，请稍后重试。",
	)


func _operation_tone(
	operation_status: String,
	error_kind: String,
	provider_status: String
) -> String:
	if operation_status == "success" or provider_status == "available":
		return "success"
	if operation_status == "disabled":
		return "disabled"
	if (
		operation_status == "rejected"
		or error_kind == "rate_limit"
		or provider_status == "rate_limited"
		or provider_status == "checking"
	):
		return "warning"
	if operation_status == "error":
		return "error"
	return _tone_for_provider_status(provider_status)


func _tone_for_provider_status(status: String) -> String:
	match status:
		"available":
			return "success"
		"checking", "rate_limited", "saved_unchecked":
			return "warning"
		"auth_failed", "timeout", "network_unavailable":
			return "error"
		"unavailable":
			return "disabled"
		_:
			return "quiet"


func _provider_card_asset_suffix(
	status: String,
	selected: bool
) -> String:
	if selected or status == "available":
		return "selected"
	match status:
		"auth_failed", "rate_limited":
			return "auth-error"
		"timeout", "network_unavailable":
			return "network-error"
		"unavailable":
			return "disabled"
		_:
			return "auth-error"


func _capability_compact_label(capability: String) -> String:
	var labels := {
		"decision_json": "JSON",
		"dialogue": "对话",
		"memory_summary": "记忆",
		"streaming": "流式",
		"image_understanding": "图像",
	}
	return str(labels.get(capability, capability))


func _profile_for(viewport_size: Vector2) -> String:
	if viewport_size.x < 960:
		return (
			"short_landscape"
			if viewport_size.x >= viewport_size.y
			else "phone_portrait"
		)
	if viewport_size.x < 1440 or viewport_size.y < 810:
		return "desktop_compact"
	return "desktop_wide"


func _base_margin_for(profile: String) -> float:
	match profile:
		"desktop_wide":
			return 32
		"desktop_compact":
			return 20
		_:
			return 12


func _is_phone_profile() -> bool:
	return _layout_profile in ["phone_portrait", "short_landscape"]


func _body_font_size() -> int:
	match _layout_profile:
		"desktop_wide":
			return 32
		"desktop_compact":
			return 24
		_:
			return 20


func _caption_font_size() -> int:
	match _layout_profile:
		"desktop_wide":
			return 28
		"desktop_compact":
			return 22
		_:
			return 18


func _section_font_size() -> int:
	match _layout_profile:
		"desktop_wide":
			return 40
		"desktop_compact":
			return 30
		_:
			return 24


func _page_title_font_size() -> int:
	match _layout_profile:
		"desktop_wide":
			return 44
		"desktop_compact":
			return 34
		_:
			return 26


func _line_slot_height() -> float:
	match _layout_profile:
		"desktop_wide":
			return 48
		"desktop_compact":
			return 38
		_:
			return 32


func _caption_line_height() -> float:
	match _layout_profile:
		"desktop_wide":
			return 42
		"desktop_compact":
			return 34
		_:
			return 28


func _section_line_height() -> float:
	match _layout_profile:
		"desktop_wide":
			return 60
		"desktop_compact":
			return 46
		_:
			return 36


func _header_height() -> float:
	match _layout_profile:
		"desktop_wide":
			return 68
		"desktop_compact":
			return 58
		_:
			return 52


func _control_height() -> float:
	match _layout_profile:
		"desktop_wide":
			return 64
		"desktop_compact":
			return 56
		_:
			return 48


func _field_height() -> float:
	match _layout_profile:
		"desktop_wide":
			return 68
		"desktop_compact":
			return 58
		_:
			return 52


func _message_slot_height() -> float:
	match _layout_profile:
		"desktop_wide":
			return 96
		"desktop_compact":
			return 72
		_:
			return 60


func _model_card_height() -> float:
	match _layout_profile:
		"desktop_wide":
			return 148
		"desktop_compact":
			return 166
		_:
			return 160


func _mark_content_surface(control: Control) -> void:
	control.add_to_group("provider_settings_content_surface")


func _register_border_owner(
	control: Control,
	ownership_id: String,
	owner_level: String,
	asset_id: String,
	component_type: String,
	paper_insets: Array
) -> void:
	control.add_to_group("provider_settings_border_owner")
	control.set_meta("ownership_id", ownership_id)
	control.set_meta("owner_level", owner_level)
	control.set_meta("asset_id", asset_id)
	control.set_meta("component_type", component_type)
	control.set_meta("paper_insets", paper_insets.duplicate())


func _register_paper_surface(
	control: Control,
	paper_insets: Array
) -> void:
	control.add_to_group("provider_settings_paper_surface")
	control.set_meta("paper_insets", paper_insets.duplicate())


func _gate_paper_rect(control: Control) -> Array:
	var current: Node = control
	while current != null and current != self:
		if (
			current is Control
			and (
				current.is_in_group(
					"provider_settings_paper_surface"
				)
				or current.is_in_group(
					"provider_settings_border_owner"
				)
			)
		):
			var owner := current as Control
			var insets := owner.get_meta(
				"paper_insets",
				[0, 0, 0, 0]
			) as Array
			if insets.size() != 4:
				insets = [0, 0, 0, 0]
			var rect := Rect2(owner.global_position, owner.size)
			rect.position += Vector2(
				float(insets[0]),
				float(insets[1])
			)
			rect.size -= Vector2(
				float(insets[0]) + float(insets[2]),
				float(insets[1]) + float(insets[3])
			)
			rect.size.x = maxf(0.0, rect.size.x)
			rect.size.y = maxf(0.0, rect.size.y)
			return _rect_to_array(rect)
		current = current.get_parent()
	return []


func _parent_border_owner_id(control: Control) -> String:
	var current := control.get_parent()
	while current != null and current != self:
		if (
			current is Control
			and current.is_in_group(
				"provider_settings_border_owner"
			)
		):
			return str(
				current.get_meta("ownership_id", current.name)
			)
		current = current.get_parent()
	return ""


func _gate_owner_rect(control: Control) -> Array:
	var current := control.get_parent()
	while current != null and current != self:
		if (
			current is Control
			and current.is_in_group(
				"provider_settings_content_surface"
			)
		):
			var owner := current as Control
			return _rect_to_array(
				Rect2(owner.global_position, owner.size)
			)
		current = current.get_parent()
	return []


func _gate_parent_owner_rect(control: Control) -> Array:
	return _gate_owner_rect(control)


func _is_scroll_reachable(control: Control) -> bool:
	var viewport_rect := Rect2(
		Vector2.ZERO,
		get_viewport_rect().size
	)
	var control_rect := Rect2(control.global_position, control.size)
	if (
		control_rect.position.x >= viewport_rect.position.x
		and control_rect.position.y >= viewport_rect.position.y
		and control_rect.end.x <= viewport_rect.end.x
		and control_rect.end.y <= viewport_rect.end.y
	):
		return true
	var current := control.get_parent()
	while current != null and current != self:
		if current is ScrollContainer:
			return true
		current = current.get_parent()
	return false


func _detail_scroll_range() -> float:
	if not is_instance_valid(_detail_scroll):
		return 0.0
	var bar := _detail_scroll.get_v_scroll_bar()
	if bar == null:
		return 0.0
	return maxf(0.0, bar.max_value - bar.page)


func _safe_insets(viewport_size: Vector2) -> Vector4:
	var override := ""
	if OS.is_debug_build():
		override = OS.get_environment(
			"AI_TOWN_PROVIDER_SAFE_INSETS"
		)
	if not override.is_empty():
		var parts := override.split(",")
		if parts.size() == 4:
			return Vector4(
				float(parts[0]),
				float(parts[1]),
				float(parts[2]),
				float(parts[3])
			)
	var safe_area := DisplayServer.get_display_safe_area()
	var window_size := Vector2(get_window().size)
	if (
		safe_area.size.x <= 0
		or safe_area.size.y <= 0
		or window_size.x <= 0
		or window_size.y <= 0
		or safe_area.size.x > window_size.x
		or safe_area.size.y > window_size.y
	):
		return Vector4.ZERO
	var scale := Vector2(
		viewport_size.x / window_size.x,
		viewport_size.y / window_size.y
	)
	return Vector4(
		safe_area.position.x * scale.x,
		safe_area.position.y * scale.y,
		(window_size.x - safe_area.end.x) * scale.x,
		(window_size.y - safe_area.end.y) * scale.y
	)


func _empty_view_model() -> Dictionary:
	return {
		"scope": "provider_settings",
		"status": "disabled",
		"revision": 0,
		"data": {
			"capabilityMode": "formal",
			"source": "TownUiAdapter",
			"formalReady": false,
			"pageTitle": "模型设置",
			"selectedProviderId": "",
			"formalStatusLabel": "正式接口未接入",
			"providers": [],
			"summary": {
				"availableProviderCount": 0,
				"enabledModelCount": 0,
			},
		},
		"actions": {},
		"operation": {
			"status": "disabled",
			"requestId": "",
			"intent": "",
			"message": "等待 TownUiAdapter 提供 Provider 设置 ViewModel",
		},
		"error": {
			"kind": "unavailable",
			"code": "PROVIDER_HEALTH_INTERFACE_MISSING",
			"message": "正式 Provider 公共查询尚未接入。",
			"retryable": false,
		},
	}


func _rect_to_array(rect: Rect2) -> Array:
	return UI_VIEW_MODEL.rect_to_array(rect)


func _array_to_rect(values: Array) -> Rect2:
	if values.size() != 4:
		return Rect2()
	return Rect2(
		float(values[0]),
		float(values[1]),
		float(values[2]),
		float(values[3])
	)
