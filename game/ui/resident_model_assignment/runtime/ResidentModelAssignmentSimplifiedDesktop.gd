class_name ResidentModelAssignmentSimplifiedDesktop
extends Control


signal action_requested(action_key: String, payload: Dictionary, focus_id: String)
signal back_pressed
signal assign_pressed
signal apply_pressed
signal completion_modal_return_pressed
signal completion_modal_start_pressed


const UiViewModel := preload("res://ui/common/AiTownUiViewModel.gd")
const SIZE := Vector2(1672, 941)
const FONT_PATH := (
	"res://assets/ui/startup/fonts/noto_sans_cjk_sc_medium/"
	+ "NotoSansCJKsc-Medium.otf"
)
const ASSET_ROOT := (
	"res://assets/ui/resident_model_assignment/final/simplified_v34"
)
const CONTROL_ROOT := ASSET_ROOT + "/runtime/controls"
const MODEL_CARD_ROOT := ASSET_ROOT + "/runtime/model_cards"
const SHELL_PATH := ASSET_ROOT + "/runtime/resident_model_assignment_shell_frame_v34.png"
const RESIDENT_SINGLE_NORMAL_PATH := CONTROL_ROOT + "/resident_single_normal.png"
const RESIDENT_SINGLE_FOCUS_PATH := CONTROL_ROOT + "/resident_single_focus.png"
const RESIDENT_BATCH_UNCHECKED_PATH := CONTROL_ROOT + "/resident_batch_unchecked.png"
const RESIDENT_BATCH_CHECKED_PATH := CONTROL_ROOT + "/resident_batch_checked.png"
const RESIDENT_BATCH_FOCUS_CHECKED_PATH := CONTROL_ROOT + "/resident_batch_focus_checked.png"
const RESIDENT_BATCH_FOCUS_UNCHECKED_PATH := CONTROL_ROOT + "/resident_batch_focus_unchecked.png"
const STATUS_VALID_PATH := CONTROL_ROOT + "/status_valid.png"
const STATUS_UNASSIGNED_PATH := CONTROL_ROOT + "/status_unassigned.png"
const BACK_CONTROL_PATH := CONTROL_ROOT + "/back.png"
const MODE_CONTROL_SINGLE_PATH := CONTROL_ROOT + "/mode_single.png"
const MODE_CONTROL_BATCH_PATH := CONTROL_ROOT + "/mode_batch.png"
const ACTION_CONTROL_PATH := CONTROL_ROOT + "/action.png"
const BATCH_SUMMARY_PATH := CONTROL_ROOT + "/batch_summary.png"
const BATCH_SELECT_ALL_FRAME_PATH := CONTROL_ROOT + "/batch_select_all_frame.png"
const RESIDENT_SCROLL_TRACK_PATH := CONTROL_ROOT + "/resident_scroll_track.png"
const MODEL_SCROLL_TRACK_PATH := CONTROL_ROOT + "/model_scroll_track.png"
const SCROLL_THUMB_PATH := CONTROL_ROOT + "/scroll_thumb.png"
const COMPLETION_OVERLAY_PATH := CONTROL_ROOT + "/completion_modal_frame.png"
const INK := Color("3f2818")
const INK_MUTED := Color("76583d")
const INK_LIGHT := Color("fff0d4")
const DISABLED := Color("9d8b70")

const RESIDENT_RECTS := [
	Rect2(76, 240, 575, 81),
	Rect2(76, 325, 575, 81),
	Rect2(76, 410, 575, 81),
	Rect2(76, 495, 575, 81),
	Rect2(76, 573, 575, 81),
	Rect2(76, 658, 575, 81),
]
const MODEL_RECTS := [
	Rect2(780, 450, 342, 106),
	Rect2(1175, 450, 342, 106),
	Rect2(780, 560, 342, 106),
	Rect2(1175, 560, 342, 106),
	Rect2(780, 670, 342, 106),
	Rect2(1175, 670, 342, 106),
]
const RESIDENT_SCROLL_RECT := Rect2(643, 241, 24, 487)
const MODEL_SCROLL_RECT := Rect2(1555, 450, 24, 316)


var in_session_mode := false
var single_resident_mode := false
var _font: Font
var _data: Dictionary = {}
var _actions: Dictionary = {}
var _resident_order: Array[Dictionary] = []
var _available_models: Array[Dictionary] = []
var _resident_offset := 0
var _model_offset := 0
var _completion_modal_visible := false
var _drag_kind := ""
var _drag_touch_index := -1
var _gesture_accum := {"resident": 0.0, "model": 0.0}
var _gesture_touch_index := {"resident": -1, "model": -1}
var _last_selected_resident_id := ""
var _last_selected_model_key := ""
var _last_mode := ""

var _labels: Dictionary = {}
var _buttons: Dictionary = {}
var _button_surfaces: Dictionary = {}
var _button_labels: Dictionary = {}

var _resident_surfaces: Array[TextureRect] = []
var _resident_portraits: Array[TextureRect] = []
var _resident_names: Array[Label] = []
var _resident_bindings: Array[Label] = []
var _resident_checks: Array[TextureRect] = []

var _model_surfaces: Array[TextureRect] = []
var _model_names: Array[Label] = []
var _model_meta: Array[Label] = []

var _detail_portrait: TextureRect
var _batch_summary_surface: TextureRect
var _batch_select_all_surface: TextureRect
var _mode_surface: TextureRect
var _assign_surface: TextureRect
var _scroll_tracks: Dictionary = {}
var _scroll_thumbs: Dictionary = {}
var _scroll_hits: Dictionary = {}

var _completion_backdrop: ColorRect
var _completion_overlay: TextureRect
var _completion_message_primary: Label
var _completion_message_secondary: Label
var _completion_labels: Array[Label] = []


func _ready() -> void:
	name = "ResidentModelAssignmentOriginalSimplifiedV34"
	custom_minimum_size = SIZE
	size = SIZE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var font_file := ResourceLoader.load(FONT_PATH, "FontFile") as FontFile
	var font_variation := FontVariation.new()
	font_variation.base_font = font_file
	font_variation.spacing_glyph = 2
	font_variation.spacing_space = 0
	_font = font_variation
	_build_shell()
	_build_header()
	_build_resident_list()
	_build_selected_resident_header()
	_build_model_grid()
	_build_footer()
	_build_completion_modal()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_drag_kind = ""
		_drag_touch_index = -1
		_gesture_accum = {"resident": 0.0, "model": 0.0}
		_gesture_touch_index = {"resident": -1, "model": -1}


func apply_view_model(view_model: Dictionary) -> void:
	_data = (view_model.get("data", {}) as Dictionary).duplicate(true)
	_actions = (view_model.get("actions", {}) as Dictionary).duplicate(true)
	_build_resident_order()
	_build_available_models()
	_ensure_current_selections_visible()
	_render(view_model)
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner == null or not is_ancestor_of(focus_owner):
		call_deferred("focus_initial")


func focus_initial() -> void:
	if _completion_modal_visible:
		var modal_start := _buttons.get("modal_start") as Button
		if modal_start != null and not modal_start.disabled:
			modal_start.grab_focus()
			return
	var back := _buttons.get("back") as Button
	if back != null and not back.disabled:
		back.grab_focus()


func focus_target(focus_id: String) -> Control:
	if focus_id.begins_with("resident:"):
		var resident_id := focus_id.trim_prefix("resident:")
		for index in mini(RESIDENT_RECTS.size(), _resident_order.size() - _resident_offset):
			if String(_resident_order[_resident_offset + index].get("residentId", "")) == resident_id:
				return _buttons.get("resident_%d" % index) as Control
	if focus_id.begins_with("model:"):
		var model_id := focus_id.trim_prefix("model:")
		for index in mini(MODEL_RECTS.size(), _available_models.size() - _model_offset):
			if String(_available_models[_model_offset + index].get("modelId", "")) == model_id:
				return _buttons.get("model_%d" % index) as Control
	return _buttons.get(focus_id) as Control


func set_completion_modal_visible(value: bool) -> void:
	_completion_modal_visible = value
	_completion_backdrop.visible = value
	_completion_overlay.visible = value
	for label: Label in _completion_labels:
		label.visible = value
	for id: String in ["modal_return", "modal_start"]:
		var button := _buttons.get(id) as Button
		if button != null:
			button.visible = value
	if value:
		call_deferred("focus_initial")


func completion_modal_visible() -> bool:
	return _completion_modal_visible


func set_completion_modal_message(message: String) -> void:
	var lines := message.split("\n", false)
	if _completion_message_primary != null:
		_completion_message_primary.text = lines[0] if not lines.is_empty() else ""
	if _completion_message_secondary == null:
		return
	var secondary_lines := PackedStringArray()
	for index in range(1, lines.size()):
		secondary_lines.append(lines[index])
	_completion_message_secondary.text = "\n".join(secondary_lines)


func set_asset_animation_enabled(_enabled: bool) -> void:
	pass


func advance_asset_frames_for_test() -> void:
	pass


func asset_animation_snapshot() -> Dictionary:
	var controls: Array[Dictionary] = []
	var rendered_model_assets: Array[String] = []
	for key: Variant in _buttons:
		var button := _buttons.get(key) as Button
		if button == null:
			continue
		controls.append({
			"id": String(key),
			"rect": [button.position.x, button.position.y, button.size.x, button.size.y],
			"visible": button.visible,
			"disabled": button.disabled,
			"profile": String(button.get_meta("asset_animation_profile", "")),
		})
	for surface: TextureRect in _model_surfaces:
		if surface.visible and surface.texture != null:
			rendered_model_assets.append(surface.texture.resource_path)
	return {
		"driver": "original-simplified-v34 exact image controls",
		"assetRoot": ASSET_ROOT,
		"shellPath": SHELL_PATH,
		"fontPath": FONT_PATH,
		"runtimeUsesAtlas": false,
		"runtimeTextureStretch": false,
		"controlCount": controls.size(),
		"controls": controls,
		"motionEnabled": false,
		"singleVisibleBoundaryOwner": true,
		"residentNavigation": {
			"offset": _resident_offset,
			"visibleResidentCount": mini(RESIDENT_RECTS.size(), _resident_order.size()),
			"totalResidentCount": _resident_order.size(),
			"assetScrollbarVisible": _resident_order.size() > RESIDENT_RECTS.size(),
		},
		"modelNavigation": {
			"offset": _model_offset,
			"availableCount": _available_models.size(),
			"visibleModelCount": mini(MODEL_RECTS.size(), maxi(_available_models.size() - _model_offset, 0)),
			"assetScrollbarVisible": _available_models.size() > MODEL_RECTS.size(),
			"emptySlotsInstantiated": false,
		},
		"visualSource": "single source master; exact PNG controls; complete model-card assets",
		"modelProviderAssets": [
			"deepseek",
			"kimi",
			"zhipu",
			"volcengine",
			"alibaba",
			"xiaomi",
			"openai_compatible",
		],
		"renderedModelAssets": rendered_model_assets,
		"runtimeWholePageScale": false,
		"runtimeControlScale": false,
		"duplicateAssetBoundaries": false,
	}


static func should_apply_draft(data: Dictionary, apply_enabled: bool) -> bool:
	if not apply_enabled:
		return false
	return not has_pending_rebind(data)


static func has_pending_rebind(data: Dictionary) -> bool:
	var target_binding := data.get("targetBinding", {}) as Dictionary
	var target_key := _binding_key(target_binding)
	if String(data.get("mode", "single")) == "batch":
		var selected_ids := data.get("selectedBatchResidentIds", []) as Array
		for resident_value: Variant in data.get("residents", []) as Array:
			if not resident_value is Dictionary:
				continue
			var resident := resident_value as Dictionary
			if not selected_ids.has(String(resident.get("residentId", ""))):
				continue
			var current_binding := resident.get("llmBinding", {}) as Dictionary
			if (
				_binding_key(current_binding) != target_key
				and not String(current_binding.get("providerId", "")).is_empty()
				and not String(current_binding.get("modelId", "")).is_empty()
			):
				return true
		return false
	var selected_resident := data.get("selectedResident", {}) as Dictionary
	if selected_resident.is_empty():
		return false
	var current_binding := selected_resident.get("llmBinding", {}) as Dictionary
	return (
		_binding_key(current_binding) != target_key
		and not String(current_binding.get("providerId", "")).is_empty()
		and not String(current_binding.get("modelId", "")).is_empty()
	)


static func _binding_key(binding: Dictionary) -> String:
	return "%s|%s|%s" % [
		String(binding.get("mode", "")),
		String(binding.get("providerId", "")),
		String(binding.get("modelId", "")),
	]


func _build_shell() -> void:
	var background := _texture_rect(
		"OriginalSimplifiedV34StructuralShell",
		Rect2(16, 16, 1640, 914),
		SHELL_PATH,
	)
	add_child(background)
	_register_border_owner(background, "ResidentModelAssignmentStructuralShellV34", "page_shell")


func _build_header() -> void:
	var back_control := _texture_rect(
		"BackControlAsset",
		Rect2(42, 29, 124, 105),
		BACK_CONTROL_PATH,
	)
	add_child(back_control)
	_add_hit_button(
		"back",
		Rect2(42, 29, 124, 105),
		func() -> void: back_pressed.emit(),
		"asset_icon_button",
	)
	_add_label(
		"PageTitle",
		Rect2(205, 41, 470, 76),
		"分配居民模型",
		38,
		HORIZONTAL_ALIGNMENT_CENTER,
	)
	_add_label(
		"ProgressCopy",
		Rect2(802, 43, 320, 74),
		"",
		20,
		HORIZONTAL_ALIGNMENT_CENTER,
	)
	_mode_surface = _texture_rect(
		"ModeControlAsset",
		Rect2(1243, 37, 368, 89),
		MODE_CONTROL_SINGLE_PATH,
	)
	add_child(_mode_surface)
	_add_label(
		"ModeCopy",
		Rect2(1340, 49, 250, 64),
		"批量选择",
		23,
		HORIZONTAL_ALIGNMENT_CENTER,
	)
	_add_hit_button(
		"mode",
		Rect2(1243, 37, 368, 89),
		func() -> void:
			action_requested.emit(
				"setMode",
				{"mode": "single" if String(_data.get("mode", "single")) == "batch" else "batch"},
				"mode",
			),
		"asset_text_button",
	)
	_mode_surface.visible = not single_resident_mode
	(_labels.get("ModeCopy") as Label).visible = true
	(_buttons.get("mode") as Button).visible = not single_resident_mode


func _build_resident_list() -> void:
	_add_label(
		"ResidentHeading",
		Rect2(142, 169, 507, 54),
		"居民",
		24,
		HORIZONTAL_ALIGNMENT_CENTER,
	)
	_add_label(
		"ResidentPage",
		Rect2(500, 173, 135, 46),
		"",
		16,
		HORIZONTAL_ALIGNMENT_RIGHT,
		INK_MUTED,
	)
	for index in RESIDENT_RECTS.size():
		var rect: Rect2 = RESIDENT_RECTS[index]
		var surface := _texture_rect(
			"ResidentRowSurface%d" % index,
			rect,
			RESIDENT_SINGLE_NORMAL_PATH,
		)
		add_child(surface)
		_resident_surfaces.append(surface)
		_register_border_owner(surface, "ResidentRow%d" % index, "complete_row_asset")

		var portrait := _texture_rect(
			"ResidentPortrait%d" % index,
			Rect2(rect.position + Vector2(19, 8), Vector2(74, 66)),
			"",
		)
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		add_child(portrait)
		_resident_portraits.append(portrait)

		var name_label := _add_label(
			"ResidentName%d" % index,
			Rect2(rect.position + Vector2(124, 11), Vector2(350, 58)),
			"",
			22,
			HORIZONTAL_ALIGNMENT_LEFT,
		)
		_resident_names.append(name_label)
		var binding_label := _add_label(
			"ResidentBinding%d" % index,
			Rect2(rect.position + Vector2(124, 50), Vector2(350, 24)),
			"",
			14,
			HORIZONTAL_ALIGNMENT_LEFT,
			INK_MUTED,
		)
		_resident_bindings.append(binding_label)

		var check := _texture_rect(
			"ResidentStatus%d" % index,
			Rect2(rect.position + Vector2(514, 28), Vector2(24, 24)),
			STATUS_UNASSIGNED_PATH,
		)
		check.visible = false
		add_child(check)
		_resident_checks.append(check)

		var button := _add_hit_button(
			"resident_%d" % index,
			rect,
			func() -> void: _on_resident_pressed(index),
			"resident_row_asset",
		)
		button.gui_input.connect(_on_list_gui_input.bind("resident", button))
	_build_asset_scrollbar("resident", RESIDENT_SCROLL_RECT)


func _build_selected_resident_header() -> void:
	_detail_portrait = _texture_rect(
		"SelectedResidentPortrait",
		Rect2(730, 202, 134, 134),
		"",
	)
	_detail_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_detail_portrait)
	_batch_summary_surface = _texture_rect(
		"BatchSummaryAsset",
		Rect2(696, 158, 900, 209),
		BATCH_SUMMARY_PATH,
	)
	_batch_summary_surface.visible = false
	add_child(_batch_summary_surface)
	_batch_select_all_surface = _texture_rect(
		"BatchSelectAllAsset",
		Rect2(1370, 284, 206, 66),
		BATCH_SELECT_ALL_FRAME_PATH,
	)
	_batch_select_all_surface.visible = false
	add_child(_batch_select_all_surface)
	_register_border_owner(
		_batch_select_all_surface,
		"BatchSelectAllAsset",
		"image_frame_with_runtime_main_menu_font",
	)
	var select_all_copy := _add_label(
		"BatchSelectAllCopy",
		Rect2(1380, 292, 186, 50),
		"全选",
		21,
		HORIZONTAL_ALIGNMENT_CENTER,
	)
	select_all_copy.visible = false
	_add_label(
		"SelectionKicker",
		Rect2(920, 202, 620, 26),
		"当前居民",
		16,
		HORIZONTAL_ALIGNMENT_LEFT,
		INK_MUTED,
	)
	_add_label(
		"SelectionTitle",
		Rect2(920, 223, 620, 42),
		"",
		29,
		HORIZONTAL_ALIGNMENT_LEFT,
	)
	_add_label(
		"SelectionBinding",
		Rect2(960, 294, 570, 47),
		"",
		18,
		HORIZONTAL_ALIGNMENT_LEFT,
		INK_MUTED,
	)
	var select_all_button := _add_hit_button(
		"batch_select_all",
		Rect2(1370, 284, 206, 66),
		_on_batch_select_all_pressed,
		"asset_text_button",
	)
	select_all_button.visible = false
	_add_label(
		"ModelHeading",
		Rect2(780, 380, 760, 54),
		"",
		22,
		HORIZONTAL_ALIGNMENT_CENTER,
	)


func _build_model_grid() -> void:
	for index in MODEL_RECTS.size():
		var rect: Rect2 = MODEL_RECTS[index]
		var surface := _texture_rect(
			"ModelCardSurface%d" % index,
			rect,
			MODEL_CARD_ROOT + "/model_deepseek_normal.png",
		)
		add_child(surface)
		_model_surfaces.append(surface)
		_register_border_owner(surface, "ModelCard%d" % index, "complete_model_card_asset")

		var name_label := _add_label(
			"ModelName%d" % index,
			Rect2(rect.position + Vector2(105, 25), Vector2(215, 28)),
			"",
			15,
			HORIZONTAL_ALIGNMENT_LEFT,
		)
		_model_names.append(name_label)
		var meta_label := _add_label(
			"ModelMeta%d" % index,
			Rect2(rect.position + Vector2(105, 54), Vector2(215, 24)),
			"",
			12,
			HORIZONTAL_ALIGNMENT_LEFT,
			INK_MUTED,
		)
		_model_meta.append(meta_label)

		var button := _add_hit_button(
			"model_%d" % index,
			rect,
			func() -> void: _on_model_pressed(index),
			"model_card_asset",
		)
		button.gui_input.connect(_on_list_gui_input.bind("model", button))
	_build_asset_scrollbar("model", MODEL_SCROLL_RECT)


func _build_footer() -> void:
	_add_label(
		"Operation",
		Rect2(145, 807, 500, 66),
		"",
		17,
		HORIZONTAL_ALIGNMENT_LEFT,
		INK_MUTED,
	)
	_assign_surface = _texture_rect(
		"AssignControlAsset",
		Rect2(1068, 799, 544, 96),
		ACTION_CONTROL_PATH,
	)
	add_child(_assign_surface)
	_add_label(
		"AssignCopy",
		Rect2(1180, 813, 400, 64),
		"分配给当前居民",
		24,
		HORIZONTAL_ALIGNMENT_CENTER,
		INK_LIGHT,
	)
	_add_hit_button(
		"assign",
		Rect2(1068, 799, 544, 96),
		_on_primary_action_pressed,
		"primary_action_asset",
	)
	var apply_button := _add_hit_button(
		"apply",
		Rect2(0, 0, 1, 1),
		func() -> void: apply_pressed.emit(),
		"hidden_apply_action",
	)
	apply_button.visible = false


func _build_completion_modal() -> void:
	_completion_backdrop = ColorRect.new()
	_completion_backdrop.name = "CompletionBackdrop"
	_completion_backdrop.position = Vector2.ZERO
	_completion_backdrop.size = SIZE
	_completion_backdrop.color = Color("16100bd0")
	_completion_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_completion_backdrop.visible = false
	add_child(_completion_backdrop)

	_completion_overlay = _texture_rect(
		"CompletionPanelAsset",
		Rect2(522, 166, 630, 525),
		COMPLETION_OVERLAY_PATH,
	)
	_completion_overlay.visible = false
	add_child(_completion_overlay)
	_register_border_owner(_completion_overlay, "CompletionPanelAssetV39", "modal_asset")

	var title := _add_label(
		"ModalTitle",
		Rect2(582, 335, 510, 66),
		"全部配置完成",
		26,
		HORIZONTAL_ALIGNMENT_CENTER,
	)
	title.visible = false
	_completion_labels.append(title)
	_completion_message_primary = _add_label(
		"ModalMessagePrimary",
		Rect2(596, 421, 482, 56),
		(
			"这位新居民的模型已经配置完成"
			if single_resident_mode
			else "全部居民的模型均已配置完成"
		),
		18,
		HORIZONTAL_ALIGNMENT_CENTER,
		INK_MUTED,
	)
	_completion_message_primary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_completion_message_primary.visible = false
	_completion_labels.append(_completion_message_primary)
	_completion_message_secondary = _add_label(
		"ModalMessageSecondary",
		Rect2(596, 479, 482, 47),
		(
			"确认后会立即进入小镇。"
			if single_resident_mode
			else "保存后会立即用于当前小镇。" if in_session_mode else "现在可以开始游戏。"
		),
		18,
		HORIZONTAL_ALIGNMENT_CENTER,
		INK_MUTED,
	)
	_completion_message_secondary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_completion_message_secondary.visible = false
	_completion_labels.append(_completion_message_secondary)
	_add_modal_button(
		"modal_return",
		Rect2(590, 584, 234, 70),
		"返回设置",
		func() -> void: completion_modal_return_pressed.emit(),
	)
	_add_modal_button(
		"modal_start",
		Rect2(849, 584, 234, 70),
		(
			"确认入镇"
			if single_resident_mode
			else "保存修改" if in_session_mode else "开始游戏"
		),
		func() -> void: completion_modal_start_pressed.emit(),
	)
	for id: String in ["modal_return", "modal_start"]:
		(_buttons.get(id) as Button).visible = false


func _render(view_model: Dictionary) -> void:
	var completed := int(_data.get("completedCount", 0))
	var total := int(_data.get("residentCount", 15))
	var invalid := int(_data.get("invalidCount", 0))
	var unassigned := int(_data.get("unassignedCount", 0))
	var batch_mode := String(_data.get("mode", "single")) == "batch"
	_render_return_flow_copy()
	_set_text(
		"ProgressCopy",
		(
			"%d / %d 已分配 · 已选 %d 位" % [
				completed,
				total,
				(_data.get("selectedBatchResidentIds", []) as Array).size(),
			]
			if batch_mode
			else "%d / %d 已分配" % [completed, total]
		),
	)
	_set_text(
		"ModeCopy",
		"入镇绑定" if single_resident_mode else "返回单人" if batch_mode else "批量选择",
	)
	_mode_surface.visible = not single_resident_mode
	(_labels.get("ModeCopy") as Label).visible = true
	(_buttons.get("mode") as Button).visible = not single_resident_mode
	_mode_surface.texture = _load_texture(
		MODE_CONTROL_BATCH_PATH if batch_mode else MODE_CONTROL_SINGLE_PATH
	)
	_set_text(
		"ResidentPage",
		"%d–%d / %d" % [
			mini(_resident_offset + 1, _resident_order.size()),
			mini(_resident_offset + RESIDENT_RECTS.size(), _resident_order.size()),
			_resident_order.size(),
		],
	)
	_render_residents(batch_mode)
	_render_selected_header(batch_mode)
	_render_models()
	_render_action_states(batch_mode)
	_set_text("Operation", _operation_copy(view_model))
	_render_scrollbars()


func _render_residents(batch_mode: bool) -> void:
	var selected_resident_id := String(_data.get("selectedResidentId", ""))
	var selected_batch := _data.get("selectedBatchResidentIds", []) as Array
	for index in RESIDENT_RECTS.size():
		var data_index := _resident_offset + index
		var visible := data_index < _resident_order.size()
		_set_resident_slot_visible(index, visible)
		if not visible:
			continue
		var resident := _resident_order[data_index]
		var resident_id := String(resident.get("residentId", ""))
		var selected := selected_batch.has(resident_id) if batch_mode else resident_id == selected_resident_id
		var current_focus := resident_id == selected_resident_id
		var surface := _resident_surfaces[index]
		if batch_mode:
			surface.texture = _load_texture(
				(
					RESIDENT_BATCH_FOCUS_CHECKED_PATH
					if selected
					else RESIDENT_BATCH_FOCUS_UNCHECKED_PATH
				)
				if current_focus
				else RESIDENT_BATCH_CHECKED_PATH
				if selected
				else RESIDENT_BATCH_UNCHECKED_PATH
			)
		else:
			surface.texture = _load_texture(
				RESIDENT_SINGLE_FOCUS_PATH if current_focus else RESIDENT_SINGLE_NORMAL_PATH
			)
		if current_focus:
			surface.position = Vector2(40, RESIDENT_RECTS[index].position.y - 1)
			surface.size = Vector2(612, 82)
		else:
			surface.position = RESIDENT_RECTS[index].position
			surface.size = RESIDENT_RECTS[index].size
		_resident_names[index].text = String(resident.get("displayName", ""))
		_resident_names[index].tooltip_text = _resident_names[index].text
		_resident_bindings[index].text = ""
		_render_portrait(_resident_portraits[index], resident)
		if batch_mode:
			_resident_checks[index].visible = false
		else:
			_resident_checks[index].visible = true
			_resident_checks[index].position = RESIDENT_RECTS[index].position + Vector2(514, 28)
			_resident_checks[index].size = Vector2(24, 24)
			_resident_checks[index].texture = _load_texture(
				STATUS_VALID_PATH
				if String(resident.get("bindingStatus", "unassigned")) == "valid"
				else STATUS_UNASSIGNED_PATH
			)


func _render_selected_header(batch_mode: bool) -> void:
	var resident := _data.get("selectedResident", {}) as Dictionary
	var kicker := _labels.get("SelectionKicker") as Label
	var title := _labels.get("SelectionTitle") as Label
	var binding := _labels.get("SelectionBinding") as Label
	if batch_mode:
		var selected_count := (_data.get("selectedBatchResidentIds", []) as Array).size()
		var resident_count := int(_data.get("residentCount", 0))
		var all_selected := resident_count > 0 and selected_count >= resident_count
		_detail_portrait.visible = false
		_batch_summary_surface.visible = true
		_batch_select_all_surface.visible = true
		kicker.position = Vector2(715, 188)
		kicker.size = Vector2(861, 29)
		kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.position = Vector2(715, 215)
		title.size = Vector2(861, 50)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		binding.position = Vector2(715, 284)
		binding.size = Vector2(640, 66)
		binding.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_set_text("SelectionKicker", "批量分配")
		_set_text("SelectionTitle", "已选择 %d 位居民" % selected_count)
		_set_text("SelectionBinding", "从左侧多选居民，再选择一个可用模型")
		_set_text("BatchSelectAllCopy", "取消全选" if all_selected else "全选")
		(_labels.get("BatchSelectAllCopy") as Label).visible = true
		var select_all_button := _buttons.get("batch_select_all") as Button
		select_all_button.visible = true
		_set_action_state(
			"batch_select_all",
			"clearBatchSelection" if all_selected else "selectAllBatch",
		)
		_batch_select_all_surface.self_modulate = (
			Color.WHITE if not select_all_button.disabled else Color(0.62, 0.62, 0.62)
		)
	else:
		_batch_summary_surface.visible = false
		_batch_select_all_surface.visible = false
		(_labels.get("BatchSelectAllCopy") as Label).visible = false
		(_buttons.get("batch_select_all") as Button).visible = false
		_render_portrait(_detail_portrait, resident)
		kicker.position = Vector2(920, 190)
		kicker.size = Vector2(620, 30)
		kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		title.position = Vector2(920, 201)
		title.size = Vector2(620, 54)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		binding.position = Vector2(960, 286)
		binding.size = Vector2(570, 52)
		binding.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_set_text("SelectionKicker", "")
		_set_text("SelectionTitle", String(resident.get("displayName", "未选择居民")))
		_set_text("SelectionBinding", "当前模型：%s" % _binding_summary(resident))
	_set_text(
		"ModelHeading",
		(
			"暂无可用模型"
			if _available_models.is_empty()
			else (
				"可用模型  ·  %d 个" % _available_models.size()
				if _available_models.size() > MODEL_RECTS.size()
				else "可用模型"
			)
		),
	)


func _render_models() -> void:
	var selected_provider := String(_data.get("selectedProviderId", ""))
	var selected_model := String(_data.get("selectedModelId", ""))
	var select_enabled := _action_enabled("selectModel")
	for index in MODEL_RECTS.size():
		var data_index := _model_offset + index
		var visible := data_index < _available_models.size()
		_set_model_slot_visible(index, visible)
		if not visible:
			continue
		var model := _available_models[data_index]
		var provider_id := String(model.get("providerId", ""))
		var model_id := String(model.get("modelId", ""))
		var selected := provider_id == selected_provider and model_id == selected_model
		_model_surfaces[index].texture = _load_texture(
			_model_card_path(
				provider_id,
				String(model.get("providerName", "")),
				selected,
			)
		)
		_model_names[index].text = String(model.get("displayName", model_id))
		_model_names[index].tooltip_text = _model_names[index].text
		_model_meta[index].text = String(model.get("providerName", provider_id))
		var text_width := 160.0 if selected else 215.0
		_model_names[index].size.x = text_width
		_model_meta[index].size.x = text_width
		_model_names[index].add_theme_font_size_override(
			"font_size",
			13 if selected and _model_names[index].text.length() > 15 else 15,
		)
		_model_surfaces[index].self_modulate = Color.WHITE if select_enabled else Color(0.7, 0.7, 0.7)
		(_buttons.get("model_%d" % index) as Button).disabled = not select_enabled


func _render_action_states(batch_mode: bool) -> void:
	var ready_to_start := should_apply_draft(_data, _action_enabled("applyDraft"))
	var pending_rebind := has_pending_rebind(_data)
	_set_action_state("back", "back")
	_set_action_state("mode", "setMode")
	_set_action_state(
		"assign",
		"applyDraft" if ready_to_start else ("assignBatch" if batch_mode else "assignOne"),
	)
	_set_action_state("apply", "applyDraft")
	_set_action_state("modal_start", "applyDraft")
	_set_text(
		"AssignCopy",
		(
			(
				"已全部分配 · 确认入镇"
				if single_resident_mode
				else "确认并返回模型设置"
				if _return_to_provider_settings()
				else "已全部分配 · 保存修改"
				if in_session_mode
				else "已全部分配 · 开始游戏"
			)
			if ready_to_start
			else "改绑已选 %d 人" % (_data.get("selectedBatchResidentIds", []) as Array).size()
			if pending_rebind and batch_mode
			else "分配给已选 %d 人" % (_data.get("selectedBatchResidentIds", []) as Array).size()
			if batch_mode
			else "改绑当前居民" if pending_rebind else "分配给当前居民"
		),
	)
	(_labels.get("AssignCopy") as Label).add_theme_color_override(
		"font_color",
		INK_LIGHT if not (_buttons.get("assign") as Button).disabled else DISABLED,
	)
	_assign_surface.texture = _load_texture(ACTION_CONTROL_PATH)
	_assign_surface.self_modulate = (
		Color.WHITE
		if not (_buttons.get("assign") as Button).disabled
		else Color(0.62, 0.62, 0.62)
	)
	(_buttons.get("apply") as Button).visible = false
	for index in RESIDENT_RECTS.size():
		var button := _buttons.get("resident_%d" % index) as Button
		button.disabled = not _action_enabled("selectBatchResident" if batch_mode else "selectResident")
	_refresh_asset_button("apply")


func _build_resident_order() -> void:
	_resident_order.clear()
	for value: Variant in _data.get("residents", []) as Array:
		if value is Dictionary:
			_resident_order.append((value as Dictionary).duplicate(true))
	_resident_offset = clampi(_resident_offset, 0, _resident_max_offset())


func _build_available_models() -> void:
	_available_models.clear()
	for provider_value: Variant in _data.get("providers", []) as Array:
		if not provider_value is Dictionary:
			continue
		var provider := provider_value as Dictionary
		if not bool(provider.get("available", false)):
			continue
		var provider_id := String(provider.get("providerId", ""))
		var provider_name := String(provider.get("displayName", provider_id))
		for model_value: Variant in provider.get("models", []) as Array:
			if not model_value is Dictionary:
				continue
			var model := (model_value as Dictionary).duplicate(true)
			if not bool(model.get("available", false)):
				continue
			model["providerId"] = provider_id
			model["providerName"] = provider_name
			_available_models.append(model)
	_model_offset = clampi(_model_offset, 0, _model_max_offset())


func _resident_max_offset() -> int:
	return maxi(_resident_order.size() - RESIDENT_RECTS.size(), 0)


func _model_max_offset() -> int:
	var overflow := maxi(_available_models.size() - MODEL_RECTS.size(), 0)
	return ceili(float(overflow) / 2.0) * 2


func _ensure_current_selections_visible() -> void:
	var mode := String(_data.get("mode", "single"))
	var selected_resident_id := String(_data.get("selectedResidentId", ""))
	if selected_resident_id != _last_selected_resident_id or mode != _last_mode:
		_last_selected_resident_id = selected_resident_id
		for index in _resident_order.size():
			if String(_resident_order[index].get("residentId", "")) != selected_resident_id:
				continue
			if index < _resident_offset:
				_resident_offset = index
			elif index >= _resident_offset + RESIDENT_RECTS.size():
				_resident_offset = index - RESIDENT_RECTS.size() + 2
			_resident_offset = clampi(_resident_offset, 0, _resident_max_offset())
			break
	_last_mode = mode
	var selected_model_key := "%s/%s" % [
		String(_data.get("selectedProviderId", "")),
		String(_data.get("selectedModelId", "")),
	]
	if selected_model_key == _last_selected_model_key:
		return
	_last_selected_model_key = selected_model_key
	for index in _available_models.size():
		var model := _available_models[index]
		var key := "%s/%s" % [
			String(model.get("providerId", "")),
			String(model.get("modelId", "")),
		]
		if key != selected_model_key:
			continue
		if index < _model_offset:
			_model_offset = index - (index % 2)
		elif index >= _model_offset + MODEL_RECTS.size():
			_model_offset = index - MODEL_RECTS.size() + 2
			_model_offset -= _model_offset % 2
		_model_offset = clampi(_model_offset, 0, _model_max_offset())
		break


func _on_resident_pressed(index: int) -> void:
	var data_index := _resident_offset + index
	if data_index >= _resident_order.size():
		return
	var resident_id := String(_resident_order[data_index].get("residentId", ""))
	if String(_data.get("mode", "single")) == "batch":
		var selected := (_data.get("selectedBatchResidentIds", []) as Array).has(resident_id)
		action_requested.emit(
			"selectBatchResident",
			{"residentId": resident_id, "selected": not selected},
			"resident:%s" % resident_id,
		)
	else:
		action_requested.emit("selectResident", {"residentId": resident_id}, "resident:%s" % resident_id)


func _on_model_pressed(index: int) -> void:
	var data_index := _model_offset + index
	if data_index >= _available_models.size():
		return
	var model := _available_models[data_index]
	action_requested.emit(
		"selectModel",
		{
			"providerId": String(model.get("providerId", "")),
			"modelId": String(model.get("modelId", "")),
		},
		"model:%s" % String(model.get("modelId", "")),
	)


func _on_list_gui_input(event: InputEvent, kind: String, owner: Control) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mouse := event as InputEventMouseButton
		if mouse.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll_kind(kind, -1)
			owner.accept_event()
		elif mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll_kind(kind, 1)
			owner.accept_event()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var active_index := int(_gesture_touch_index.get(kind, -1))
		if touch.pressed:
			if active_index >= 0:
				return
			_gesture_touch_index[kind] = touch.index
			_gesture_accum[kind] = 0.0
		elif touch.index == active_index:
			_gesture_touch_index[kind] = -1
			_gesture_accum[kind] = 0.0
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index != int(_gesture_touch_index.get(kind, -1)):
			return
		_gesture_accum[kind] = float(_gesture_accum.get(kind, 0.0)) + drag.relative.y
		if absf(float(_gesture_accum[kind])) >= 36.0:
			_scroll_kind(kind, -1 if float(_gesture_accum[kind]) > 0.0 else 1)
			_gesture_accum[kind] = 0.0
			owner.accept_event()


func _scroll_kind(kind: String, direction: int) -> void:
	if kind == "model":
		_scroll_models(direction * 2)
	else:
		_scroll_residents(direction)


func _scroll_residents(delta: int) -> void:
	var next := clampi(_resident_offset + delta, 0, _resident_max_offset())
	if next == _resident_offset:
		return
	_resident_offset = next
	_render({"operation": {"status": "idle"}})


func _scroll_models(delta: int) -> void:
	var next := clampi(_model_offset + delta, 0, _model_max_offset())
	next = int(round(float(next) / 2.0)) * 2
	if next == _model_offset:
		return
	_model_offset = next
	_render({"operation": {"status": "idle"}})


func _build_asset_scrollbar(kind: String, rect: Rect2) -> void:
	var track := _texture_rect(
		"%sScrollTrackAsset" % kind.capitalize(),
		Rect2(rect.position + Vector2(3, 0), Vector2(18, rect.size.y)),
		RESIDENT_SCROLL_TRACK_PATH if kind == "resident" else MODEL_SCROLL_TRACK_PATH,
	)
	add_child(track)
	_scroll_tracks[kind] = track
	var thumb := _texture_rect(
		"%sScrollThumbAsset" % kind.capitalize(),
		Rect2(rect.position, Vector2(24, 48)),
		SCROLL_THUMB_PATH,
	)
	add_child(thumb)
	_scroll_thumbs[kind] = thumb
	var hit := Control.new()
	hit.name = "%sScrollInteraction" % kind.capitalize()
	hit.position = rect.position
	hit.size = rect.size
	hit.mouse_filter = Control.MOUSE_FILTER_STOP
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit.gui_input.connect(_on_scrollbar_gui_input.bind(kind, hit))
	add_child(hit)
	_scroll_hits[kind] = hit


func _on_scrollbar_gui_input(event: InputEvent, kind: String, owner: Control) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			_drag_kind = kind if mouse.pressed else ""
			_drag_touch_index = -1
			if mouse.pressed:
				_set_scroll_from_ratio(kind, mouse.position.y / owner.size.y)
			owner.accept_event()
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll_kind(kind, -1)
			owner.accept_event()
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll_kind(kind, 1)
			owner.accept_event()
	elif event is InputEventMouseMotion and _drag_kind == kind:
		var motion := event as InputEventMouseMotion
		if motion.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_set_scroll_from_ratio(kind, motion.position.y / owner.size.y)
		owner.accept_event()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.canceled:
			if touch.index == _drag_touch_index:
				_drag_kind = ""
				_drag_touch_index = -1
			return
		if touch.pressed:
			if _drag_touch_index >= 0:
				return
			_drag_kind = kind
			_drag_touch_index = touch.index
			_set_scroll_from_ratio(kind, touch.position.y / owner.size.y)
		elif touch.index == _drag_touch_index:
			_drag_kind = ""
			_drag_touch_index = -1
		else:
			return
		owner.accept_event()
	elif event is InputEventScreenDrag and _drag_kind == kind:
		var drag := event as InputEventScreenDrag
		if drag.index != _drag_touch_index:
			return
		_set_scroll_from_ratio(kind, drag.position.y / owner.size.y)
		owner.accept_event()


func _set_scroll_from_ratio(kind: String, ratio: float) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	if kind == "model":
		var raw := int(round(ratio * float(_model_max_offset()) / 2.0)) * 2
		if raw != _model_offset:
			_model_offset = clampi(raw, 0, _model_max_offset())
			_render({"operation": {"status": "idle"}})
	else:
		var raw := int(round(ratio * float(_resident_max_offset())))
		if raw != _resident_offset:
			_resident_offset = clampi(raw, 0, _resident_max_offset())
			_render({"operation": {"status": "idle"}})


func _render_scrollbars() -> void:
	_render_scrollbar(
		"resident",
		RESIDENT_SCROLL_RECT,
		_resident_offset,
		_resident_max_offset(),
		RESIDENT_RECTS.size(),
		_resident_order.size(),
	)
	_render_scrollbar(
		"model",
		MODEL_SCROLL_RECT,
		_model_offset,
		_model_max_offset(),
		MODEL_RECTS.size(),
		_available_models.size(),
	)


func _render_scrollbar(
	kind: String,
	rect: Rect2,
	offset: int,
	max_offset: int,
	visible_count: int,
	total_count: int,
) -> void:
	var show := total_count > visible_count
	var track := _scroll_tracks.get(kind) as TextureRect
	var thumb := _scroll_thumbs.get(kind) as TextureRect
	var hit := _scroll_hits.get(kind) as Control
	track.visible = show
	thumb.visible = show
	hit.visible = show
	if not show:
		return
	var thumb_height := 48.0
	var travel := rect.size.y - thumb_height
	var progress := 0.0 if max_offset <= 0 else float(offset) / float(max_offset)
	thumb.position = Vector2(rect.position.x, rect.position.y + round(travel * progress))
	thumb.size = Vector2(24, 48)


func _render_portrait(texture_rect: TextureRect, resident: Dictionary) -> void:
	var texture := _portrait_frame(
		String(resident.get("portraitRef", "")),
		String(resident.get("portraitFrameMode", "legacy_atlas_64x80")),
	)
	texture_rect.texture = texture
	texture_rect.visible = texture != null


func _portrait_frame(path: String, frame_mode: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path, "Texture2D"):
		return null
	var sheet := ResourceLoader.load(path, "Texture2D") as Texture2D
	if sheet == null:
		return null
	if frame_mode == "full_texture":
		return sheet
	if sheet.get_width() < 64 or sheet.get_height() < 80:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(0, 0, 64, 80)
	return atlas


func _binding_summary(resident: Dictionary) -> String:
	if resident.is_empty():
		return "尚未分配"
	var provider := String(resident.get("providerDisplayName", ""))
	var model := String(resident.get("modelDisplayName", ""))
	if provider.is_empty() or model.is_empty():
		return "尚未分配"
	return "%s · %s" % [provider, model]


func _model_card_path(
	provider_id: String,
	provider_name: String,
	selected: bool,
) -> String:
	var key := ("%s %s" % [provider_id, provider_name]).to_lower()
	var provider_key := "openai_compatible"
	if "deepseek" in key:
		provider_key = "deepseek"
	elif "kimi" in key or "moonshot" in key:
		provider_key = "kimi"
	elif "zhipu" in key or "glm" in key:
		provider_key = "zhipu"
	elif "volcengine" in key or "ark" in key or "doubao" in key or "豆包" in key:
		provider_key = "volcengine"
	elif (
		"aliyun" in key
		or "alibaba" in key
		or "bailian" in key
		or "qwen" in key
		or "百炼" in key
	):
		provider_key = "alibaba"
	elif "xiaomi" in key or "mimo" in key or "小米" in key:
		provider_key = "xiaomi"
	return "%s/model_%s_%s.png" % [
		MODEL_CARD_ROOT,
		provider_key,
		"selected" if selected else "normal",
	]


func _on_primary_action_pressed() -> void:
	if should_apply_draft(_data, _action_enabled("applyDraft")):
		apply_pressed.emit()
		return
	var binding := {
		"mode": "model",
		"providerId": String(_data.get("selectedProviderId", "")),
		"modelId": String(_data.get("selectedModelId", "")),
	}
	if String(_data.get("mode", "single")) == "batch":
		action_requested.emit(
			"assignBatch",
			{
				"residentIds": (
					_data.get("selectedBatchResidentIds", []) as Array
				).duplicate(),
				"llmBinding": binding,
			},
			"assign",
		)
	else:
		action_requested.emit(
			"assignOne",
			{
				"residentId": String(_data.get("selectedResidentId", "")),
				"llmBinding": binding,
			},
			"assign",
		)


func _on_batch_select_all_pressed() -> void:
	var selected_count := (_data.get("selectedBatchResidentIds", []) as Array).size()
	var resident_count := int(_data.get("residentCount", 0))
	if resident_count > 0 and selected_count >= resident_count:
		action_requested.emit("clearBatchSelection", {}, "batch_select_all")
	else:
		action_requested.emit("selectAllBatch", {}, "batch_select_all")


func _operation_copy(view_model: Dictionary) -> String:
	var operation := view_model.get("operation", {}) as Dictionary
	var status := String(operation.get("status", "idle"))
	var error_message := UiViewModel.error_message(view_model)
	match status:
		"loading":
			return "正在更新居民模型分配…"
		"success":
			return "分配已更新，确认全部后即可继续"
		"rejected", "error":
			return error_message if not error_message.is_empty() else "操作未完成，原分配已保留"
		"disabled":
			return "当前没有可用模型"
	if has_pending_rebind(_data):
		return (
			"选中的新模型还没有应用，点击底部改绑按钮后再继续"
			if String(_data.get("mode", "single")) == "single"
			else "选中的新模型还没有应用，点击底部改绑已选居民后再继续"
		)
	if _action_enabled("applyDraft"):
		return (
			"调整完成后，点击确认返回模型设置"
			if _return_to_provider_settings()
			else "全部居民均已完成模型分配，可以保存修改"
			if in_session_mode
			else "全部居民均已完成模型分配，可以开始游戏"
		)
	return "模型来自已连接服务；此处只负责分配"


func _return_to_provider_settings() -> bool:
	return bool(_data.get("returnToProviderSettings", false))


func _render_return_flow_copy() -> void:
	if not _return_to_provider_settings():
		return
	if _completion_message_secondary != null:
		_completion_message_secondary.text = "确认后返回模型设置。"
	var modal_start_label := _button_labels.get("modal_start") as Label
	if modal_start_label != null:
		modal_start_label.text = "确认并返回"


func _action_enabled(action_key: String) -> bool:
	return bool((_actions.get(action_key, {}) as Dictionary).get("enabled", false))


func _set_action_state(button_id: String, action_key: String) -> void:
	var button := _buttons.get(button_id) as Button
	if button == null:
		return
	var action := _actions.get(action_key, {}) as Dictionary
	button.disabled = not bool(action.get("enabled", false))
	button.tooltip_text = (
		""
		if not button.disabled
		else UiViewModel.player_reason(String(action.get("disabledReason", "")))
	)


func _set_resident_slot_visible(index: int, value: bool) -> void:
	_resident_surfaces[index].visible = value
	_resident_portraits[index].visible = value
	_resident_names[index].visible = value
	_resident_bindings[index].visible = false
	_resident_checks[index].visible = value
	(_buttons.get("resident_%d" % index) as Button).visible = value


func _set_model_slot_visible(index: int, value: bool) -> void:
	_model_surfaces[index].visible = value
	_model_names[index].visible = value
	_model_meta[index].visible = value
	(_buttons.get("model_%d" % index) as Button).visible = value


func _texture_rect(id: String, rect: Rect2, path: String) -> TextureRect:
	var texture_rect := TextureRect.new()
	texture_rect.name = id
	texture_rect.position = rect.position
	texture_rect.size = rect.size
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not path.is_empty():
		texture_rect.texture = _load_texture(path)
	return texture_rect


func _load_texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path, "Texture2D"):
		return null
	return ResourceLoader.load(path, "Texture2D") as Texture2D


func _add_label(
	id: String,
	rect: Rect2,
	text_value: String,
	font_size: int,
	alignment: HorizontalAlignment,
	color := INK,
) -> Label:
	var label := Label.new()
	label.name = id
	label.position = rect.position
	label.size = rect.size
	label.text = text_value
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font != null:
		label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_to_group("resident_model_assignment_text_slot")
	label.set_meta("gate_id", "Simplified:%s" % id)
	add_child(label)
	_labels[id] = label
	return label


func _add_hit_button(
	id: String,
	rect: Rect2,
	pressed: Callable,
	profile: String,
) -> Button:
	var button := Button.new()
	button.name = "%sButton" % id.to_pascal_case()
	button.position = rect.position
	button.size = rect.size
	button.text = ""
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for style_name: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(style_name, StyleBoxEmpty.new())
	button.pressed.connect(pressed)
	_register_button(button, id, profile)
	add_child(button)
	_buttons[id] = button
	return button


func _add_modal_button(
	id: String,
	rect: Rect2,
	text_value: String,
	pressed: Callable,
) -> Button:
	var button := _add_hit_button(id, rect, pressed, "modal_action_asset")
	var copy := _button_copy("AssetCopy", rect.size, text_value, 22, INK)
	button.add_child(copy)
	_button_labels[id] = copy
	return button


func _button_copy(
	id: String,
	button_size: Vector2,
	text_value: String,
	font_size: int,
	color: Color,
) -> Label:
	var copy := Label.new()
	copy.name = id
	copy.position = Vector2.ZERO
	copy.size = button_size
	copy.text = text_value
	copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	copy.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	copy.clip_text = true
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font != null:
		copy.add_theme_font_override("font", _font)
	copy.add_theme_font_size_override("font_size", font_size)
	copy.add_theme_color_override("font_color", color)
	return copy


func _refresh_asset_button(id: String) -> void:
	var button := _buttons.get(id) as Button
	var surface := _button_surfaces.get(id) as TextureRect
	var copy := _button_labels.get(id) as Label
	if button == null or surface == null:
		return
	surface.modulate = Color(1, 1, 1, 0.52 if button.disabled else 1.0)
	if copy != null:
		copy.add_theme_color_override("font_color", DISABLED if button.disabled else INK)


func _register_button(button: Button, id: String, profile: String) -> void:
	button.add_to_group("resident_model_assignment_touch_target")
	button.set_meta("gate_id", "Simplified:%s" % id)
	button.set_meta("asset_animation_id", "simplified-v30:%s" % id)
	button.set_meta("asset_animation_profile", profile)


func _register_border_owner(control: Control, owner_id: String, level: String) -> void:
	control.add_to_group("resident_model_assignment_border_owner")
	control.set_meta("owner_id", owner_id)
	control.set_meta("owner_level", level)


func _set_text(id: String, value: String) -> void:
	var label := _labels.get(id) as Label
	if label != null:
		label.text = value
		label.tooltip_text = value
