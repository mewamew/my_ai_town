class_name SystemFeedbackLayer
extends Control


signal intent_requested(
	intent: StringName,
	payload: Dictionary,
	scope: StringName,
	request_id: String
)
signal action_blocked(
	intent: StringName,
	reason: String,
	scope: StringName
)
signal feedback_presented(identity: String, surface: String)
signal feedback_dismissed(identity: String, surface: String)
signal presentation_rejected(issues: PackedStringArray)

const UiNodeRetirement := preload("res://ui/common/AiTownUiNodeRetirement.gd")

const UiViewModel := preload(
	"res://ui/common/AiTownUiViewModel.gd"
)
const CommonTheme := preload(
	"res://ui/common/AiTownUiTheme.gd"
)
const COMPONENT_SCENES := {
	"dialog": preload(
		"res://ui/common/system_feedback/"
		+ "SystemFeedbackDialog.tscn"
	),
	"toast": preload(
		"res://ui/common/system_feedback/"
		+ "SystemFeedbackToast.tscn"
	),
	"loading_overlay": preload(
		"res://ui/common/system_feedback/"
		+ "SystemFeedbackLoadingOverlay.tscn"
	),
	"disabled_reason": preload(
		"res://ui/common/system_feedback/"
		+ "SystemFeedbackDisabledReason.tscn"
	),
	"validation": preload(
		"res://ui/common/system_feedback/"
		+ "SystemFeedbackValidation.tscn"
	),
	"asset_placeholder": preload(
		"res://ui/common/system_feedback/"
		+ "SystemFeedbackAssetPlaceholder.tscn"
	),
	"map_anchor": preload(
		"res://ui/common/system_feedback/"
		+ "SystemFeedbackMapAnchor.tscn"
	),
}
const FORMAL_ERROR_DIALOG_SCENE := preload(
	"res://ui/common/system_feedback/SystemFeedbackFormalDialog.tscn"
)
const OBSERVED_SCOPES := [
	&"lifecycle",
	&"environment",
	&"avatar",
	&"conversation",
	&"announcements",
	&"town_hud",
	&"session",
	&"save",
	&"pause_menu",
	&"audio_display_settings",
	&"provider_settings",
	&"custom_resident_creator",
	&"resident_model_assignment",
	&"weather_control",
	&"resident_action_menu",
	&"resident_overview",
	&"resident_detail",
	&"inner_observation",
	&"place_focus",
	&"indoor",
	&"town_log",
	&"wardrobe",
]
const VALID_SURFACES := [
	"dialog",
	"toast",
	"loading_overlay",
	"disabled_reason",
	"validation",
	"asset_placeholder",
	"map_anchor",
]
const TERMINAL_OPERATION_STATUSES := [
	&"success",
	&"rejected",
	&"error",
	&"disabled",
]
const MAX_DEDUPE_HISTORY := 256
const MINIMUM_TOUCH_TARGET := Vector2(48, 48)

@export_range(1, 3, 1) var maximum_visible_toasts := 3
@export var auto_dispatch_adapter := true
@export var reduced_motion := false

var _adapter: Node
var _scope_revisions: Dictionary = {}
var _seen_identities: Dictionary = {}
var _seen_order: Array[String] = []
var _terminal_identities: Dictionary = {}
var _registered_anchors: Dictionary = {}
var _focus_fallback: WeakRef
var _explicit_safe_insets := Vector4(-1, -1, -1, -1)

var _active_toasts: Array[Dictionary] = []
var _toast_queue: Array[Dictionary] = []
var _active_modal: Dictionary = {}
var _modal_queue: Array[Dictionary] = []
var _active_loading: Dictionary = {}
var _loading_queue: Array[Dictionary] = []
var _inline_entries: Array[Dictionary] = []

var _dimmer: ColorRect
var _loading_viewport: Control
var _modal_viewport: Control
var _inline_host: Control
var _toast_host: Control
var _layout_profile := "standard_landscape"
var _safe_rect := Rect2()
var _toast_capacity := 3
var _layout_queued := false
var _feedback_sequence := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_hosts()
	if not resized.is_connected(_queue_layout):
		resized.connect(_queue_layout)
	if not get_viewport().size_changed.is_connected(_queue_layout):
		get_viewport().size_changed.connect(_queue_layout)
	_queue_layout()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if not _active_modal.is_empty():
		var component := _entry_component(_active_modal)
		if component != null:
			if component.has_method("request_cancel"):
				component.call("request_cancel")
				get_viewport().set_input_as_handled()
				return
			var cancel := component.get_node_or_null(
				"Actions/Action_cancel"
			) as Button
			if cancel != null and not cancel.disabled:
				cancel.pressed.emit()
				get_viewport().set_input_as_handled()
				return
	if not _active_loading.is_empty():
		var loading := _entry_component(_active_loading)
		if loading != null:
			var cancel := loading.get_node_or_null(
				"Actions/Action_cancel"
			) as Button
			if cancel != null and not cancel.disabled:
				cancel.pressed.emit()
				get_viewport().set_input_as_handled()


func bind_town_ui_adapter(adapter: Node) -> void:
	if _adapter == adapter:
		return
	_disconnect_adapter()
	clear_all()
	_scope_revisions.clear()
	_seen_identities.clear()
	_seen_order.clear()
	_terminal_identities.clear()
	_adapter = adapter
	if _adapter == null:
		return
	if _adapter.has_signal("view_model_changed"):
		var callback := Callable(self, "_on_view_model_changed")
		if not _adapter.is_connected("view_model_changed", callback):
			_adapter.connect("view_model_changed", callback)
	if not _adapter.has_method("get_view_model"):
		return
	for scope: StringName in OBSERVED_SCOPES:
		var incoming: Variant = _adapter.call(
			"get_view_model",
			str(scope)
		)
		if incoming is Dictionary:
			apply_view_model(incoming as Dictionary)


func unbind_town_ui_adapter() -> void:
	bind_town_ui_adapter(null)


func apply_view_model(
	view_model: Dictionary,
	anchor_override: Control = null,
	surface_override: String = "auto"
) -> PackedStringArray:
	var issues := UiViewModel.validate(
		view_model,
		"SystemFeedbackLayer"
	)
	if not issues.is_empty():
		presentation_rejected.emit(issues)
		return issues
	var scope := UiViewModel.scope(view_model)
	var revision := UiViewModel.revision(view_model)
	var current_revision := int(_scope_revisions.get(scope, -1))
	if revision < current_revision:
		issues.append(
			"SystemFeedbackLayer 收到过期 revision：%s %d < %d"
			% [str(scope), revision, current_revision]
		)
		presentation_rejected.emit(issues)
		return issues
	_scope_revisions[scope] = revision

	var data := UiViewModel.data(view_model)
	var feedback_value: Variant = data.get("feedback", null)
	if feedback_value == null:
		_retire_superseded_loading(view_model)
		return PackedStringArray()
	if typeof(feedback_value) != TYPE_DICTIONARY:
		issues.append(
			"SystemFeedbackLayer.data.feedback 必须是 null 或 Dictionary"
		)
		presentation_rejected.emit(issues)
		return issues
	_retire_superseded_loading(view_model)
	var feedback := (feedback_value as Dictionary).duplicate(true)
	# 多个页面也有自己内部使用的 data.feedback。只有明确声明公共反馈组件的
	# 数据才归常驻的全局反馈层处理。
	if not feedback.has("component"):
		return PackedStringArray()
	var surface := (
		surface_override
		if surface_override != "auto"
		else _resolve_surface(feedback)
	)
	if not VALID_SURFACES.has(surface):
		issues.append("SystemFeedbackLayer 组件类型无效：" + surface)
		presentation_rejected.emit(issues)
		return issues

	var identity := _dedupe_identity(view_model, feedback)
	if identity.is_empty():
		issues.append("SystemFeedbackLayer 无法建立反馈去重身份")
		presentation_rejected.emit(issues)
		return issues
	var existing := _find_entry(identity)
	if not existing.is_empty():
		return _update_entry(existing, view_model, feedback)
	if _seen_identities.has(identity):
		return PackedStringArray()

	var terminal_key := _terminal_key(view_model)
	if (
		not terminal_key.is_empty()
		and _terminal_identities.has(terminal_key)
	):
		return PackedStringArray()
	var dedupe_key := str(feedback.get("dedupeKey", ""))
	if surface == "toast" and not dedupe_key.is_empty():
		var dedupe_match := _find_toast_by_dedupe_key(
			dedupe_key
		)
		if not dedupe_match.is_empty():
			return _replace_toast_entry(
				dedupe_match,
				identity,
				view_model,
				feedback,
				terminal_key,
				anchor_override
			)

	var entry := {
		"identity": identity,
		"surface": surface,
		"scope": str(scope),
		"viewModel": view_model.duplicate(true),
		"feedback": feedback,
		"dedupeKey": dedupe_key,
		"terminalKey": terminal_key,
		"anchorOverride": anchor_override,
		"component": null,
		"timer": null,
		"previousFocus": null,
		"sequence": _next_feedback_sequence(),
	}
	if not terminal_key.is_empty():
		_terminal_identities[terminal_key] = identity
	match surface:
		"toast":
			_enqueue_toast(entry)
		"dialog":
			_enqueue_modal(entry)
		"loading_overlay":
			if bool(feedback.get("blocking", false)):
				_enqueue_loading(entry)
			else:
				_activate_inline(entry)
		_:
			_activate_inline(entry)
	_queue_layout()
	return PackedStringArray()


func register_anchor(anchor_id: StringName, control: Control) -> void:
	if anchor_id.is_empty():
		return
	if control == null:
		unregister_anchor(anchor_id)
		return
	var anchor_key := str(anchor_id)
	var previous := _registered_anchor_control(anchor_key)
	_registered_anchors[anchor_key] = weakref(control)
	var layout_callback := Callable(self, "_queue_layout")
	if not control.item_rect_changed.is_connected(layout_callback):
		control.item_rect_changed.connect(layout_callback)
	if previous != null and previous != control:
		_disconnect_anchor_layout_if_unused(previous)
	_queue_layout()


func unregister_anchor(anchor_id: StringName) -> void:
	var anchor_key := str(anchor_id)
	var previous := _registered_anchor_control(anchor_key)
	_registered_anchors.erase(anchor_key)
	if previous != null:
		_disconnect_anchor_layout_if_unused(previous)
	_queue_layout()


func set_focus_fallback(control: Control) -> void:
	_focus_fallback = weakref(control) if control != null else null


func set_safe_area_insets(insets: Vector4) -> void:
	_explicit_safe_insets = Vector4(
		maxf(0.0, insets.x),
		maxf(0.0, insets.y),
		maxf(0.0, insets.z),
		maxf(0.0, insets.w)
	)
	_queue_layout()


func clear_safe_area_override() -> void:
	_explicit_safe_insets = Vector4(-1, -1, -1, -1)
	_queue_layout()


func dismiss_feedback(identity: String) -> bool:
	for index: int in range(_active_toasts.size()):
		if str(_active_toasts[index].get("identity", "")) == identity:
			var toast := _active_toasts[index]
			_active_toasts.remove_at(index)
			_retire_entry(toast)
			_fill_toast_slots()
			_queue_layout()
			return true
	if (
		not _active_modal.is_empty()
		and str(_active_modal.get("identity", "")) == identity
	):
		var modal := _active_modal
		_active_modal = {}
		_retire_entry(modal, true)
		_activate_next_modal()
		_queue_layout()
		return true
	if (
		not _active_loading.is_empty()
		and str(_active_loading.get("identity", "")) == identity
	):
		var loading := _active_loading
		_active_loading = {}
		_retire_entry(loading, true)
		_activate_next_loading()
		_queue_layout()
		return true
	for index: int in range(_inline_entries.size()):
		if str(_inline_entries[index].get("identity", "")) == identity:
			var inline_entry := _inline_entries[index]
			_inline_entries.remove_at(index)
			_retire_entry(inline_entry)
			_queue_layout()
			return true
	if _remove_queued_identity(_toast_queue, identity):
		_mark_seen_identity(identity)
		return true
	if _remove_queued_identity(_modal_queue, identity):
		_mark_seen_identity(identity)
		return true
	if _remove_queued_identity(_loading_queue, identity):
		_mark_seen_identity(identity)
		return true
	return false


func clear_scope(
	scope: StringName,
	keep_global_toasts: bool = true
) -> void:
	var scope_text := str(scope)
	for index: int in range(_inline_entries.size() - 1, -1, -1):
		var entry := _inline_entries[index]
		if str(entry.get("scope", "")) == scope_text:
			_inline_entries.remove_at(index)
			_retire_entry(entry)
	for index: int in range(_active_toasts.size() - 1, -1, -1):
		var toast := _active_toasts[index]
		if str(toast.get("scope", "")) != scope_text:
			continue
		var anchor := str(
			(toast.get("feedback", {}) as Dictionary).get(
				"anchor",
				""
			)
		)
		if keep_global_toasts and anchor.begins_with("viewport"):
			continue
		_active_toasts.remove_at(index)
		_retire_entry(toast)
	_remove_queued_scope(_toast_queue, scope_text, keep_global_toasts)
	_remove_queued_scope(_modal_queue, scope_text, false)
	_remove_queued_scope(_loading_queue, scope_text, false)
	if (
		not _active_modal.is_empty()
		and str(_active_modal.get("scope", "")) == scope_text
	):
		var modal := _active_modal
		_active_modal = {}
		_retire_entry(modal, true)
		_activate_next_modal()
	if (
		not _active_loading.is_empty()
		and str(_active_loading.get("scope", "")) == scope_text
	):
		var loading := _active_loading
		_active_loading = {}
		_retire_entry(loading, true)
		_activate_next_loading()
	_fill_toast_slots()
	_queue_layout()


func clear_all() -> void:
	var identities: Array[String] = []
	for entry: Dictionary in _all_entries():
		identities.append(str(entry.get("identity", "")))
	for identity: String in identities:
		dismiss_feedback(identity)
	_toast_queue.clear()
	_modal_queue.clear()
	_loading_queue.clear()
	_queue_layout()


func debug_request_action(identity: String, action_key: String) -> bool:
	var entry := _find_entry(identity)
	if entry.is_empty():
		return false
	return _dispatch_entry_action(entry, StringName(action_key))


func runtime_gate_snapshot() -> Dictionary:
	var entries: Array = []
	var text_slots: Array = []
	var touch_targets: Array = []
	var formal_ready_values: Array = []
	for entry: Dictionary in _active_entries():
		var component := _entry_component(entry)
		if component == null or not component.is_visible_in_tree():
			continue
		var visible_rect := Rect2(
			component.global_position,
			component.size
		).intersection(_safe_rect)
		entries.append({
			"identity": entry.get("identity", ""),
			"surface": entry.get("surface", ""),
			"scope": entry.get("scope", ""),
			"rect": _rect_to_array(visible_rect),
			"componentRect": _rect_to_array(Rect2(
				component.global_position,
				component.size
			)),
			"clippedBySafeViewport": visible_rect.size != component.size,
		})
		var vm := entry.get("viewModel", {}) as Dictionary
		var data := vm.get("data", {}) as Dictionary
		formal_ready_values.append(
			bool(data.get("formalReady", false))
		)
		for child: Node in component.find_children(
			"*",
			"Label",
			true,
			false
		):
			var label := child as Label
			if label == null or not label.is_visible_in_tree():
				continue
			var font := label.get_theme_font("font")
			var font_size := label.get_theme_font_size("font_size")
			text_slots.append({
				"id": (
					str(entry.get("identity", ""))
					+ "/"
					+ str(label.name)
				),
				"rect": _rect_to_array(Rect2(
					label.global_position,
					label.size
				)),
				"fontSize": font_size,
				"lineHeight": font.get_height(font_size),
				"maxLines": label.max_lines_visible,
				"clipText": label.clip_text,
				"wholeFontShrink": false,
			})
		for child: Node in component.find_children(
			"*",
			"Button",
			true,
			false
		):
			var button := child as Button
			if button == null or not button.is_visible_in_tree():
				continue
			touch_targets.append({
				"id": (
					str(entry.get("identity", ""))
					+ "/"
					+ str(button.name)
				),
				"rect": _rect_to_array(Rect2(
					button.global_position,
					button.size
				)),
				"minimum": [
					MINIMUM_TOUCH_TARGET.x,
					MINIMUM_TOUCH_TARGET.y,
				],
				"focusMode": button.focus_mode,
				"disabled": button.disabled,
			})
	return {
		"commonRevision": CommonTheme.REVISION,
		"formalReady": (
			not formal_ready_values.is_empty()
			and not formal_ready_values.has(false)
		),
		"layoutProfile": _layout_profile,
		"wholePageScale": [scale.x, scale.y],
		"viewportRect": _rect_to_array(
			Rect2(Vector2.ZERO, size)
		),
		"safeRect": _rect_to_array(_safe_rect),
		"toastCapacity": _toast_capacity,
		"activeToastCount": _active_toasts.size(),
		"activeToastIdentities": _active_toast_identities(),
		"queuedToastCount": _toast_queue.size(),
		"activeModalIdentity": _active_modal.get("identity", ""),
		"queuedModalCount": _modal_queue.size(),
		"activeLoadingIdentity": _active_loading.get(
			"identity",
			""
		),
		"queuedLoadingCount": _loading_queue.size(),
		"blockingLoadingActive": _blocking_loading_active(),
		"blockingDimmerVisible": _dimmer.visible,
		"blockingInputCaptured": (
			_dimmer.visible
			and _dimmer.mouse_filter == Control.MOUSE_FILTER_STOP
		),
		"entries": entries,
		"textSlots": text_slots,
		"touchTargets": touch_targets,
		"ownership": {
			"pageShellOwner": "none",
			"sectionFrameOwner": "common component instance",
			"contentSlotOwner": "common component instance",
			"actionControlOwner": "common component instance",
			"blockingFillOwner": (
				"SystemFeedbackLayer/BlockingDimmer"
			),
			"pageOwnedVisibleBoundaryIds": [],
			"duplicateSemanticBoundaries": [],
			"compositeStyleBoxTextureCount": 0,
		},
	}


func _build_hosts() -> void:
	if _dimmer != null:
		return
	_dimmer = ColorRect.new()
	_dimmer.name = "BlockingDimmer"
	_dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dimmer.color = Color(0.055, 0.078, 0.061, 0.72)
	_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	_dimmer.z_index = 30
	_dimmer.visible = false
	add_child(_dimmer)

	_loading_viewport = _make_host("LoadingViewport", true)
	_modal_viewport = _make_host("ModalViewport", true)
	_inline_host = _make_host("InlineHost", false)
	_toast_host = _make_host("ToastHost", false)
	_loading_viewport.z_index = 40
	_modal_viewport.z_index = 50
	_inline_host.z_index = 10
	_toast_host.z_index = 20


func _make_host(node_name: String, clips: bool) -> Control:
	var host := Control.new()
	host.name = node_name
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.clip_contents = clips
	add_child(host)
	return host


func _enqueue_toast(entry: Dictionary) -> void:
	if (
		_blocking_loading_active()
		and _toast_is_low_priority_success(entry)
	):
		_toast_queue.push_back(entry)
		return
	if _active_toasts.size() < _toast_capacity:
		if _activate_entry(entry, _toast_host):
			_active_toasts.push_front(entry)
			_start_toast_timer(entry)
	else:
		_toast_queue.push_back(entry)


func _enqueue_modal(entry: Dictionary) -> void:
	if _active_modal.is_empty():
		if _activate_entry(entry, _modal_viewport):
			_active_modal = entry
	else:
		_modal_queue.push_back(entry)


func _enqueue_loading(entry: Dictionary) -> void:
	if _active_loading.is_empty():
		if _activate_entry(entry, _loading_viewport):
			_active_loading = entry
	else:
		_loading_queue.push_back(entry)


func _activate_inline(entry: Dictionary) -> void:
	if _activate_entry(entry, _inline_host):
		_inline_entries.push_back(entry)


func _activate_entry(entry: Dictionary, parent: Control) -> bool:
	var feedback := entry.get("feedback", {}) as Dictionary
	var scene: PackedScene
	if str(feedback.get("component", "")) == "error_dialog":
		scene = FORMAL_ERROR_DIALOG_SCENE
	else:
		scene = COMPONENT_SCENES.get(
			str(entry.get("surface", "")),
			null
		) as PackedScene
	if scene == null:
		presentation_rejected.emit(PackedStringArray([
			"SystemFeedbackLayer 缺少公共组件场景"
		]))
		return false
	_capture_previous_focus(entry)
	var component := scene.instantiate() as Control
	if component == null:
		presentation_rejected.emit(PackedStringArray([
			"SystemFeedbackLayer 无法实例化公共组件"
		]))
		return false
	component.name = _safe_node_name(
		str(entry.get("identity", ""))
	)
	component.set("reduced_motion", reduced_motion)
	component.set_meta(
		"feedback_identity",
		entry.get("identity", "")
	)
	component.action_requested.connect(
		_on_component_action.bind(component)
	)
	component.dismiss_requested.connect(
		_on_component_dismiss.bind(component)
	)
	parent.add_child(component)
	entry["component"] = component
	var issues: Variant = component.call(
		"configure",
		entry.get("viewModel", {}),
		entry.get("surface", "")
	)
	if (
		typeof(issues) != TYPE_PACKED_STRING_ARRAY
		or not (issues as PackedStringArray).is_empty()
	):
		var typed_issues := (
			issues as PackedStringArray
			if typeof(issues) == TYPE_PACKED_STRING_ARRAY
			else PackedStringArray([
				"SystemFeedbackLayer 公共组件 configure 返回无效"
			])
		)
		presentation_rejected.emit(typed_issues)
		UiNodeRetirement.retire(component)
		entry["component"] = null
		return false
	feedback_presented.emit(
		str(entry.get("identity", "")),
		str(entry.get("surface", ""))
	)
	return true


func _update_entry(
	entry: Dictionary,
	view_model: Dictionary,
	feedback: Dictionary
) -> PackedStringArray:
	entry["viewModel"] = view_model.duplicate(true)
	entry["feedback"] = feedback.duplicate(true)
	entry["dedupeKey"] = str(feedback.get("dedupeKey", ""))
	var component := _entry_component(entry)
	if component == null:
		return PackedStringArray()
	var issues: Variant = component.call(
		"configure",
		view_model,
		entry.get("surface", "")
	)
	if typeof(issues) != TYPE_PACKED_STRING_ARRAY:
		return PackedStringArray([
			"SystemFeedbackLayer 公共组件 configure 返回无效"
		])
	_queue_layout()
	return issues as PackedStringArray


func _replace_toast_entry(
	entry: Dictionary,
	identity: String,
	view_model: Dictionary,
	feedback: Dictionary,
	terminal_key: String,
	anchor_override: Control
) -> PackedStringArray:
	var old_identity := str(entry.get("identity", ""))
	if old_identity != identity:
		_mark_seen_identity(old_identity)
	entry["identity"] = identity
	entry["scope"] = str(UiViewModel.scope(view_model))
	entry["viewModel"] = view_model.duplicate(true)
	entry["feedback"] = feedback.duplicate(true)
	entry["dedupeKey"] = str(feedback.get("dedupeKey", ""))
	entry["terminalKey"] = terminal_key
	entry["anchorOverride"] = anchor_override
	entry["sequence"] = _next_feedback_sequence()
	if not terminal_key.is_empty():
		_terminal_identities[terminal_key] = identity
	var component := _entry_component(entry)
	if component != null:
		component.set_meta("feedback_identity", identity)
		var issues: Variant = component.call(
			"configure",
			view_model,
			"toast"
		)
		if typeof(issues) == TYPE_PACKED_STRING_ARRAY:
			_start_toast_timer(entry)
			_queue_layout()
			return issues as PackedStringArray
	return PackedStringArray()


func _activate_next_modal() -> void:
	while _active_modal.is_empty() and not _modal_queue.is_empty():
		var entry: Dictionary = _modal_queue.pop_front()
		if _activate_entry(entry, _modal_viewport):
			_active_modal = entry


func _activate_next_loading() -> void:
	while _active_loading.is_empty() and not _loading_queue.is_empty():
		var entry: Dictionary = _loading_queue.pop_front()
		if _activate_entry(entry, _loading_viewport):
			_active_loading = entry
	if not _blocking_loading_active():
		_fill_toast_slots()


func _fill_toast_slots() -> void:
	while (
		_active_toasts.size() < _toast_capacity
		and not _toast_queue.is_empty()
	):
		var next_index := _next_presentable_toast_index()
		if next_index < 0:
			break
		var entry: Dictionary = _toast_queue.pop_at(next_index)
		if _activate_entry(entry, _toast_host):
			_active_toasts.push_back(entry)
			_sort_active_toasts()
			_start_toast_timer(entry)


func _start_toast_timer(entry: Dictionary) -> void:
	var previous := entry.get("timer", null) as Timer
	if previous != null and is_instance_valid(previous):
		previous.stop()
		previous.queue_free()
	entry["timer"] = null
	var feedback := entry.get("feedback", {}) as Dictionary
	var duration_msec := int(feedback.get("durationMsec", 0))
	var dismiss_policy := str(feedback.get("dismissPolicy", ""))
	if (
		duration_msec <= 0
		or dismiss_policy in ["manual", "persistent", "action"]
	):
		return
	var component := _entry_component(entry)
	if component == null:
		return
	var timer := Timer.new()
	timer.name = "AutoDismissTimer"
	timer.one_shot = true
	timer.wait_time = maxf(0.25, float(duration_msec) / 1000.0)
	timer.timeout.connect(
		_on_toast_timeout.bind(component)
	)
	component.add_child(timer)
	entry["timer"] = timer
	timer.start()


func _on_toast_timeout(component: Control) -> void:
	if not is_instance_valid(component):
		return
	dismiss_feedback(
		str(component.get_meta("feedback_identity", ""))
	)


func _on_component_action(
	action_key: StringName,
	component: Control
) -> void:
	var identity := str(
		component.get_meta("feedback_identity", "")
	)
	var entry := _find_entry(identity)
	if not entry.is_empty():
		_dispatch_entry_action(entry, action_key)


func _dispatch_entry_action(
	entry: Dictionary,
	action_key: StringName
) -> bool:
	var view_model := entry.get("viewModel", {}) as Dictionary
	var action := UiViewModel.action(
		view_model,
		str(action_key)
	)
	var intent := StringName(action.get("intent", ""))
	var scope := UiViewModel.scope(view_model)
	if intent.is_empty() or not UiViewModel.action_enabled(action):
		var reason := UiViewModel.disabled_reason(action)
		action_blocked.emit(
			intent,
			reason if not reason.is_empty() else "ACTION_DISABLED",
			scope
		)
		return false
	var payload := {}
	var static_payload: Variant = action.get("payload", {})
	if static_payload is Dictionary:
		payload = (static_payload as Dictionary).duplicate(true)
	var request_id := UiViewModel.operation_request_id(view_model)
	intent_requested.emit(intent, payload.duplicate(true), scope, request_id)
	if (
		auto_dispatch_adapter
		and _adapter != null
		and _adapter.has_method("dispatch")
	):
		_adapter.call("dispatch", intent, payload)
	return true


func _on_component_dismiss(component: Control) -> void:
	if not is_instance_valid(component):
		return
	dismiss_feedback(
		str(component.get_meta("feedback_identity", ""))
	)


func _retire_entry(
	entry: Dictionary,
	restore_focus: bool = false
) -> void:
	var component := _entry_component(entry)
	if component != null:
		UiNodeRetirement.retire(component)
	entry["component"] = null
	if restore_focus:
		_restore_previous_focus(entry)
	var identity := str(entry.get("identity", ""))
	_mark_seen_identity(identity)
	feedback_dismissed.emit(
		identity,
		str(entry.get("surface", ""))
	)


func _mark_seen_identity(identity: String) -> void:
	if identity.is_empty() or _seen_identities.has(identity):
		return
	_seen_identities[identity] = true
	_seen_order.append(identity)
	while _seen_order.size() > MAX_DEDUPE_HISTORY:
		var removed: String = _seen_order.pop_front()
		_seen_identities.erase(removed)


func _resolve_surface(feedback: Dictionary) -> String:
	var component := str(feedback.get("component", ""))
	var anchor := str(feedback.get("anchor", ""))
	if component == "toast" and anchor == "map_target":
		return "map_anchor"
	match component:
		"confirmation_dialog", "error_dialog":
			return "dialog"
		"input_validation":
			return "validation"
		_:
			return component


func _dedupe_identity(
	view_model: Dictionary,
	feedback: Dictionary
) -> String:
	var feedback_id := str(feedback.get("feedbackId", ""))
	if not feedback_id.is_empty():
		return feedback_id
	return _terminal_key(view_model)


func _terminal_key(view_model: Dictionary) -> String:
	var status := UiViewModel.operation_status(view_model)
	var request_id := UiViewModel.operation_request_id(view_model)
	if (
		not TERMINAL_OPERATION_STATUSES.has(status)
		or request_id.is_empty()
	):
		return ""
	return (
		str(UiViewModel.scope(view_model))
		+ "|"
		+ request_id
		+ "|"
		+ str(status)
	)


func _find_entry(identity: String) -> Dictionary:
	for entry: Dictionary in _all_entries():
		if str(entry.get("identity", "")) == identity:
			return entry
	return {}


func _find_toast_by_dedupe_key(dedupe_key: String) -> Dictionary:
	for entry: Dictionary in _active_toasts + _toast_queue:
		if str(entry.get("dedupeKey", "")) == dedupe_key:
			return entry
	return {}


func _retire_superseded_loading(view_model: Dictionary) -> void:
	var scope_text := str(UiViewModel.scope(view_model))
	var status := UiViewModel.operation_status(view_model)
	var request_id := UiViewModel.operation_request_id(view_model)
	var identities: Array[String] = []
	for entry: Dictionary in _all_entries():
		if str(entry.get("scope", "")) != scope_text:
			continue
		if str(entry.get("surface", "")) != "loading_overlay":
			continue
		var entry_vm := entry.get("viewModel", {}) as Dictionary
		var same_request := (
			status == &"loading"
			and not request_id.is_empty()
			and UiViewModel.operation_request_id(entry_vm) == request_id
		)
		if same_request:
			continue
		identities.append(str(entry.get("identity", "")))
	for identity: String in identities:
		dismiss_feedback(identity)


func _toast_is_low_priority_success(entry: Dictionary) -> bool:
	var feedback := entry.get("feedback", {}) as Dictionary
	return str(feedback.get("tone", "")) == "success"


func _next_presentable_toast_index() -> int:
	var selected_index := -1
	var selected_sequence := -1
	for index: int in range(_toast_queue.size()):
		if (
			_blocking_loading_active()
			and _toast_is_low_priority_success(_toast_queue[index])
		):
			continue
		var sequence := int(_toast_queue[index].get("sequence", -1))
		if sequence > selected_sequence:
			selected_index = index
			selected_sequence = sequence
	return selected_index


func _sort_active_toasts() -> void:
	_active_toasts.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("sequence", -1)) > int(
			right.get("sequence", -1)
		)
	)


func _active_toast_identities() -> Array[String]:
	var identities: Array[String] = []
	for entry: Dictionary in _active_toasts:
		identities.append(str(entry.get("identity", "")))
	return identities


func _next_feedback_sequence() -> int:
	_feedback_sequence += 1
	return _feedback_sequence


func _capture_previous_focus(entry: Dictionary) -> void:
	var feedback := entry.get("feedback", {}) as Dictionary
	if not bool(feedback.get("blocking", false)):
		return
	var previous := get_viewport().gui_get_focus_owner()
	if previous != null and is_instance_valid(previous):
		entry["previousFocus"] = weakref(previous)


func _restore_previous_focus(entry: Dictionary) -> void:
	var previous_ref: Variant = entry.get("previousFocus", null)
	entry["previousFocus"] = null
	var previous: Control
	if previous_ref is WeakRef:
		previous = (previous_ref as WeakRef).get_ref() as Control
	if _can_restore_focus(previous):
		previous.grab_focus()
		return
	if _focus_fallback == null:
		return
	var fallback := _focus_fallback.get_ref() as Control
	if _can_restore_focus(fallback):
		fallback.grab_focus()


func _can_restore_focus(control: Control) -> bool:
	return (
		control != null
		and is_instance_valid(control)
		and control.is_visible_in_tree()
		and control.focus_mode != Control.FOCUS_NONE
	)


func _registered_anchor_control(anchor_id: String) -> Control:
	var weak_value: Variant = _registered_anchors.get(anchor_id, null)
	if weak_value is WeakRef:
		var control := (weak_value as WeakRef).get_ref() as Control
		if control != null and is_instance_valid(control):
			return control
	return null


func _disconnect_anchor_layout_if_unused(control: Control) -> void:
	for anchor_id: String in _registered_anchors:
		if _registered_anchor_control(anchor_id) == control:
			return
	var layout_callback := Callable(self, "_queue_layout")
	if control.item_rect_changed.is_connected(layout_callback):
		control.item_rect_changed.disconnect(layout_callback)


func _all_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.append_array(_active_toasts)
	result.append_array(_toast_queue)
	result.append_array(_modal_queue)
	result.append_array(_loading_queue)
	result.append_array(_inline_entries)
	if not _active_modal.is_empty():
		result.append(_active_modal)
	if not _active_loading.is_empty():
		result.append(_active_loading)
	return result


func _active_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.append_array(_active_toasts)
	result.append_array(_inline_entries)
	if not _active_loading.is_empty():
		result.append(_active_loading)
	if not _active_modal.is_empty():
		result.append(_active_modal)
	return result


func _entry_component(entry: Dictionary) -> Control:
	var value: Variant = entry.get("component", null)
	if value is Control and is_instance_valid(value):
		return value as Control
	return null


func _remove_queued_identity(
	queue: Array[Dictionary],
	identity: String
) -> bool:
	for index: int in range(queue.size()):
		if str(queue[index].get("identity", "")) == identity:
			queue.remove_at(index)
			return true
	return false


func _remove_queued_scope(
	queue: Array[Dictionary],
	scope: String,
	keep_global_toasts: bool
) -> void:
	for index: int in range(queue.size() - 1, -1, -1):
		var entry := queue[index]
		if str(entry.get("scope", "")) != scope:
			continue
		var feedback := entry.get("feedback", {}) as Dictionary
		var anchor := str(feedback.get("anchor", ""))
		if keep_global_toasts and anchor.begins_with("viewport"):
			continue
		_mark_seen_identity(str(entry.get("identity", "")))
		queue.remove_at(index)


func _queue_layout() -> void:
	if _layout_queued:
		return
	_layout_queued = true
	call_deferred("_apply_layout")


func _apply_layout() -> void:
	_layout_queued = false
	if _dimmer == null:
		return
	var viewport_size := Vector2(
		floorf(size.x),
		floorf(size.y)
	)
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = get_viewport_rect().size.floor()
	var insets := _read_safe_insets()
	var content_size := Vector2(
		maxf(1.0, viewport_size.x - insets.x - insets.z),
		maxf(1.0, viewport_size.y - insets.y - insets.w)
	)
	var outer_margin := _round_up_to_four(
		maxf(16.0, 0.02 * minf(content_size.x, content_size.y))
	)
	_safe_rect = Rect2(
		Vector2(
			insets.x + outer_margin,
			insets.y + outer_margin
		).floor(),
		Vector2(
			maxf(1.0, content_size.x - outer_margin * 2.0),
			maxf(1.0, content_size.y - outer_margin * 2.0)
		).floor()
	)
	_layout_profile = _resolve_layout_profile(_safe_rect.size)
	_dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dimmer.visible = _blocking_surface_visible()
	_dimmer.mouse_filter = (
		Control.MOUSE_FILTER_STOP
		if _dimmer.visible
		else Control.MOUSE_FILTER_IGNORE
	)

	_layout_toasts()
	_layout_modal()
	_layout_loading()
	_layout_inline_entries()


func _layout_toasts() -> void:
	var toast_size := _toast_size()
	var gap := 12.0
	_toast_capacity = 1 if _layout_profile == "short_landscape" else clampi(
		int(floor(
			(_safe_rect.size.y + gap) / (toast_size.y + gap)
		)),
		1,
		maximum_visible_toasts
	)
	_rebalance_toasts()
	_sort_active_toasts()
	for index: int in range(_active_toasts.size()):
		var entry := _active_toasts[index]
		var component := _entry_component(entry)
		if component == null:
			continue
		component.set(
			"expanded",
			_layout_profile != "short_landscape"
		)
		component.position = Vector2(
			floorf(_safe_rect.end.x - toast_size.x),
			floorf(
				_safe_rect.position.y
				+ float(index) * (toast_size.y + gap)
			)
		)
		component.size = toast_size.floor()


func _rebalance_toasts() -> void:
	while _active_toasts.size() > _toast_capacity:
		var entry: Dictionary = _active_toasts.pop_back()
		var component := _entry_component(entry)
		if component != null:
			UiNodeRetirement.retire(component)
			entry["component"] = null
			entry["timer"] = null
		_toast_queue.push_front(entry)
	_fill_toast_slots()


func _layout_modal() -> void:
	if _active_modal.is_empty():
		_modal_viewport.visible = false
		return
	_modal_viewport.visible = true
	_modal_viewport.position = _safe_rect.position
	_modal_viewport.size = _safe_rect.size
	var component := _entry_component(_active_modal)
	if component == null:
		return
	var requested := _dialog_size(_is_formal_error_dialog(_active_modal))
	var content_height := maxf(requested.y, _safe_rect.size.y)
	var y := (
		floorf((_safe_rect.size.y - requested.y) * 0.5)
		if requested.y <= _safe_rect.size.y
		else 0.0
	)
	component.position = Vector2(
		floorf((_safe_rect.size.x - requested.x) * 0.5),
		y
	)
	component.size = requested
	_modal_viewport.custom_minimum_size = Vector2(
		_safe_rect.size.x,
		content_height
	)


func _layout_loading() -> void:
	if _active_loading.is_empty() or not _active_modal.is_empty():
		_loading_viewport.visible = false
		return
	_loading_viewport.visible = true
	_loading_viewport.position = _safe_rect.position
	_loading_viewport.size = _safe_rect.size
	var component := _entry_component(_active_loading)
	if component == null:
		return
	var requested := Vector2(
		minf(460.0, _safe_rect.size.x),
		minf(392.0, _safe_rect.size.y)
	).floor()
	component.position = (
		(_safe_rect.size - requested) * 0.5
	).floor()
	component.size = requested


func _layout_inline_entries() -> void:
	for entry: Dictionary in _inline_entries:
		var component := _entry_component(entry)
		if component == null:
			continue
		var requested := _inline_size(
			str(entry.get("surface", ""))
		)
		requested.x = minf(requested.x, _safe_rect.size.x)
		requested.y = minf(requested.y, _safe_rect.size.y)
		var anchor_rect := _entry_anchor_rect(entry)
		var position := _inline_position(
			str(entry.get("surface", "")),
			anchor_rect,
			requested
		)
		component.position = _clamp_position_to_safe(
			position,
			requested
		).floor()
		component.size = requested.floor()


func _entry_anchor_rect(entry: Dictionary) -> Rect2:
	var anchor := entry.get("anchorOverride", null) as Control
	if anchor == null or not is_instance_valid(anchor):
		var feedback := entry.get("feedback", {}) as Dictionary
		var anchor_id := str(feedback.get("anchor", ""))
		var weak_value: Variant = _registered_anchors.get(
			anchor_id,
			null
		)
		if weak_value is WeakRef:
			anchor = (weak_value as WeakRef).get_ref() as Control
	if anchor != null and is_instance_valid(anchor):
		return Rect2(
			anchor.global_position - global_position,
			anchor.size
		)
	return Rect2(_safe_rect.get_center(), Vector2.ZERO)


func _inline_position(
	surface: String,
	anchor_rect: Rect2,
	requested: Vector2
) -> Vector2:
	match surface:
		"validation", "disabled_reason":
			return Vector2(
				anchor_rect.position.x,
				anchor_rect.end.y + 8.0
			)
		"map_anchor":
			return Vector2(
				anchor_rect.get_center().x - requested.x * 0.5,
				anchor_rect.position.y - requested.y - 12.0
			)
		"asset_placeholder":
			return (
				anchor_rect.get_center() - requested * 0.5
			)
		_:
			return (
				anchor_rect.get_center() - requested * 0.5
			)


func _clamp_position_to_safe(
	position: Vector2,
	component_size: Vector2
) -> Vector2:
	return Vector2(
		clampf(
			position.x,
			_safe_rect.position.x,
			maxf(
				_safe_rect.position.x,
				_safe_rect.end.x - component_size.x
			)
		),
		clampf(
			position.y,
			_safe_rect.position.y,
			maxf(
				_safe_rect.position.y,
				_safe_rect.end.y - component_size.y
			)
		)
	)


func _toast_size() -> Vector2:
	match _layout_profile:
		"expansive_landscape", "ultrawide":
			return Vector2(
				minf(560.0, _safe_rect.size.x),
				224.0
			)
		"short_landscape":
			return Vector2(
				minf(560.0, _safe_rect.size.x),
				minf(115.0, _safe_rect.size.y)
			)
		_:
			return Vector2(
				minf(520.0, _safe_rect.size.x),
				minf(224.0, _safe_rect.size.y)
			)


func _dialog_size(formal_error := false) -> Vector2:
	if formal_error:
		# FormalConfirmationDialog is designed at 1024x640. Keep the component at
		# that ratio so the raster panel remains uniform at every viewport size.
		var max_size := Vector2(
			minf(1024.0, _safe_rect.size.x),
			minf(640.0, _safe_rect.size.y),
		)
		var uniform_scale := minf(
			max_size.x / 1024.0,
			max_size.y / 640.0,
		)
		return (Vector2(1024.0, 640.0) * uniform_scale).floor()
	var width := 760.0
	var height := 392.0
	match _layout_profile:
		"expansive_landscape", "ultrawide":
			width = 880.0
			height = 420.0
		"standard_landscape":
			width = minf(760.0, _safe_rect.size.x * 0.72)
		"narrow":
			width = _safe_rect.size.x
			height = 430.0
		"portrait":
			width = _safe_rect.size.x
			height = 520.0
		"short_landscape":
			width = minf(720.0, _safe_rect.size.x)
			height = 430.0
	return Vector2(
		minf(width, _safe_rect.size.x),
		height
	).floor()


func _is_formal_error_dialog(entry: Dictionary) -> bool:
	var feedback := entry.get("feedback", {}) as Dictionary
	return str(feedback.get("component", "")) == "error_dialog"


func _inline_size(surface: String) -> Vector2:
	match surface:
		"disabled_reason":
			return Vector2(320, 88)
		"validation":
			return Vector2(520, 126)
		"asset_placeholder":
			return Vector2(480, 180)
		"map_anchor":
			return Vector2(320, 88)
		"loading_overlay":
			return Vector2(460, 392)
		_:
			return Vector2(320, 88)


func _resolve_layout_profile(usable_size: Vector2) -> String:
	var aspect := usable_size.x / maxf(1.0, usable_size.y)
	if usable_size.y < 568.0 and aspect >= 1.2:
		return "short_landscape"
	if usable_size.x < 720.0:
		return "portrait"
	if usable_size.x < 1000.0:
		return "narrow"
	if aspect >= 2.1 and usable_size.x >= 1600.0:
		return "ultrawide"
	if usable_size.x >= 1600.0 and usable_size.y >= 900.0:
		return "expansive_landscape"
	return "standard_landscape"


func _blocking_surface_visible() -> bool:
	if _blocking_loading_active():
		return true
	if _active_modal.is_empty():
		return false
	var feedback := _active_modal.get("feedback", {}) as Dictionary
	return bool(feedback.get("blocking", false))


func _blocking_loading_active() -> bool:
	if _active_loading.is_empty():
		return false
	var feedback := _active_loading.get("feedback", {}) as Dictionary
	return bool(feedback.get("blocking", false))


func _read_safe_insets() -> Vector4:
	if _explicit_safe_insets.x >= 0.0:
		return _explicit_safe_insets
	if not OS.is_debug_build():
		return Vector4.ZERO
	var raw := OS.get_environment(
		"AI_TOWN_SYSTEM_FEEDBACK_SAFE_INSETS"
	)
	if raw.is_empty():
		return Vector4.ZERO
	var parts := raw.split(",")
	if parts.size() != 4:
		return Vector4.ZERO
	return Vector4(
		maxf(0.0, float(parts[0])),
		maxf(0.0, float(parts[1])),
		maxf(0.0, float(parts[2])),
		maxf(0.0, float(parts[3]))
	)


func _round_up_to_four(value: float) -> float:
	return ceilf(value / 4.0) * 4.0


func _disconnect_adapter() -> void:
	if _adapter == null or not _adapter.has_signal(
		"view_model_changed"
	):
		return
	var callback := Callable(self, "_on_view_model_changed")
	if _adapter.is_connected("view_model_changed", callback):
		_adapter.disconnect("view_model_changed", callback)


func _on_view_model_changed(
	_scope: StringName,
	view_model: Dictionary
) -> void:
	apply_view_model(view_model)


func _safe_node_name(identity: String) -> String:
	var safe := identity.validate_node_name()
	if safe.is_empty():
		return "Feedback"
	return "Feedback_" + safe


func _rect_to_array(rect: Rect2) -> Array:
	return [
		floorf(rect.position.x),
		floorf(rect.position.y),
		floorf(rect.size.x),
		floorf(rect.size.y),
	]
