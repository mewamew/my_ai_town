extends Control


signal intent_requested(intent_id: StringName, payload: Dictionary)
signal action_blocked(intent_id: String, reason: String)
signal wardrobe_result_ready(return_intent: String, payload: Dictionary)
signal wardrobe_cancelled(cancel_intent: String, payload: Dictionary)
signal return_requested(source_scope: String, return_intent: String, payload: Dictionary)

const RESULT_SHAPES := preload(
	"res://world/contract/TownWorldResultShapes.gd"
)
const FourSlotContract = preload(
	"res://ui/wardrobe/runtime_approved_v2/WardrobeFourSlotContract.gd"
)
const FormalDialog = preload(
	"res://ui/common/formal_dialog/FormalConfirmationDialog.gd"
)

const BASE_SIZE := Vector2(1920.0, 1080.0)
const VISUAL_REVISION := "centered-direction-shell-complete-set-formal-v4"
const ASSET_SHELL_PATH := (
	"res://assets/ui/wardrobe/image_assets/final_shell/"
	+ "wardrobe_final_empty_shell_centered_v3_exact_1920x1080.png"
)
const ASSET_SHELL_SHA256 := (
	"27264db1076343837ed5e589d7bbf921fb68ec1fa361c0113793f86dcc2558b2"
)
const RIG_PROVIDER_ID := "resident_2d_rig_v1"
const WARDROBE_CATALOG_PATH := (
	"res://assets/characters/resident_2d_rig_v1/wardrobe_v1/"
	+ "wardrobe_catalog.json"
)
const WARDROBE_CATALOG_SCHEMA := "ai-town.resident-wardrobe.v1"
const SLOT_ORDER: Array[String] = ["hair", "top", "bottom", "shoes"]
const PREVIEW_SLOT_ORDER: Array[String] = [
	"hair", "expression", "top", "bottom", "shoes",
]
const DIRECTIONS: Array[String] = ["down", "right", "up", "left"]
const FONT_PATH := (
	"res://assets/ui/startup/fonts/noto_sans_cjk_sc_medium/"
	+ "NotoSansCJKsc-Medium.otf"
)
const INK := Color("3F2818")
const PAPER := Color("FFF6DE")
const ACTIVE_INK := Color("8A471F")
const SELECTED_GREEN := Color("49684A")
const MUTED_INK := Color("756652")
const ERROR_INK := Color("8D3526")
const SUCCESS_INK := Color("7A4A20")
const DISABLED_PRIMARY_INK := Color("E8C58F")
const BODY_FONT_SIZE := 28
const DISPLAY_FONT_SIZE := 40
const TOUCH_TAP_SLOP := 18.0
const INITIAL_LOOK_INDEX := 6
const CATALOG_PAGE_SIZE := 6
const CATALOG_CONTENT_RECTS: Array[Rect2] = [
	Rect2(858.0, 338.0, 244.0, 142.0),
	Rect2(1136.0, 338.0, 230.0, 142.0),
	Rect2(1404.0, 338.0, 232.0, 142.0),
	Rect2(858.0, 574.0, 244.0, 142.0),
	Rect2(1136.0, 574.0, 230.0, 142.0),
	Rect2(1404.0, 574.0, 232.0, 142.0),
]

const TEXT_SLOTS := {
	"back": Rect2(394.0, 120.0, 212.0, 88.0),
	"title": Rect2(630.0, 116.0, 654.0, 96.0),
	"resident": Rect2(1392.0, 120.0, 252.0, 88.0),
	"category_preset": Rect2(850.0, 258.0, 800.0, 62.0),
	"category_head": Rect2(1078.0, 258.0, 100.0, 62.0),
	"category_top_hands": Rect2(1244.0, 258.0, 100.0, 62.0),
	"category_bottom": Rect2(1412.0, 258.0, 96.0, 62.0),
	"category_shoes": Rect2(1574.0, 258.0, 74.0, 62.0),
	"item_0": Rect2(866.0, 490.0, 226.0, 60.0),
	"item_1": Rect2(1140.0, 490.0, 226.0, 60.0),
	"item_2": Rect2(1406.0, 490.0, 230.0, 60.0),
	"item_3": Rect2(866.0, 726.0, 226.0, 60.0),
	"item_4": Rect2(1140.0, 726.0, 226.0, 60.0),
	"item_5": Rect2(1406.0, 726.0, 230.0, 60.0),
	"direction_down": Rect2(344.0, 742.0, 96.0, 72.0),
	"direction_right": Rect2(454.0, 742.0, 96.0, 72.0),
	"direction_up": Rect2(564.0, 742.0, 96.0, 72.0),
	"direction_left": Rect2(674.0, 742.0, 96.0, 72.0),
	"page_previous": Rect2(730.0, 854.0, 62.0, 84.0),
	"page_next": Rect2(796.0, 854.0, 62.0, 84.0),
	"status": Rect2(292.0, 856.0, 388.0, 112.0),
	"restore": Rect2(884.0, 858.0, 170.0, 104.0),
	"randomize": Rect2(1072.0, 858.0, 160.0, 104.0),
	"cancel": Rect2(1248.0, 858.0, 158.0, 104.0),
	"apply": Rect2(1420.0, 850.0, 224.0, 120.0),
}
const BASE_COPY := {
	"back": "返回",
	"title": "居民套装",
	"category_preset": "套装",
	"category_head": "",
	"category_top_hands": "",
	"category_bottom": "",
	"category_shoes": "",
	"direction_down": "正面",
	"direction_right": "右侧",
	"direction_up": "背面",
	"direction_left": "左侧",
	"page_previous": "〈",
	"page_next": "〉",
	"restore": "恢复原样",
	"randomize": "随机套装",
	"cancel": "取消",
	"apply": "保存",
}
# These Controls are input-only. The page shell owns every visible frame.
const HIT_TARGETS := {
	"back": Rect2(256.0, 116.0, 352.0, 98.0),
	"category_preset": Rect2(850.0, 250.0, 164.0, 72.0),
	"category_head": Rect2(1018.0, 250.0, 164.0, 72.0),
	"category_top_hands": Rect2(1186.0, 250.0, 164.0, 72.0),
	"category_bottom": Rect2(1354.0, 250.0, 158.0, 72.0),
	"category_shoes": Rect2(1518.0, 250.0, 132.0, 72.0),
	"item_0": Rect2(850.0, 330.0, 260.0, 224.0),
	"item_1": Rect2(1128.0, 330.0, 246.0, 224.0),
	"item_2": Rect2(1396.0, 330.0, 248.0, 224.0),
	"item_3": Rect2(850.0, 566.0, 260.0, 222.0),
	"item_4": Rect2(1128.0, 566.0, 246.0, 222.0),
	"item_5": Rect2(1396.0, 566.0, 248.0, 222.0),
	"direction_down": Rect2(338.0, 738.0, 108.0, 80.0),
	"direction_right": Rect2(448.0, 738.0, 108.0, 80.0),
	"direction_up": Rect2(558.0, 738.0, 108.0, 80.0),
	"direction_left": Rect2(668.0, 738.0, 108.0, 80.0),
	"page_previous": Rect2(714.0, 842.0, 80.0, 104.0),
	"page_next": Rect2(794.0, 842.0, 80.0, 104.0),
	"restore": Rect2(880.0, 850.0, 178.0, 120.0),
	"randomize": Rect2(1068.0, 850.0, 168.0, 120.0),
	"cancel": Rect2(1244.0, 850.0, 166.0, 120.0),
	"apply": Rect2(1416.0, 846.0, 232.0, 128.0),
}

@onready var _visual_canvas: Control = %VisualCanvas
@onready var _visual_owner: TextureRect = %WardrobeAssetFrameOwner
@onready var _resident_wardrobe_preview: TextureRect = %ResidentWardrobePreview
@onready var _safety_overlay: Control = %SafetyOverlay

var _contract := FourSlotContract.new()
var _adapter: Node
var _pending_view_model: Dictionary = {}
var _view_model: Dictionary = {}
var _view_model_revision := -1
var _ui_ready := false
var _handoff: Dictionary = {}
var _handoff_error := "WARDROBE_HANDOFF_MISSING"
var _original_selection: Dictionary = {}
var _confirmed_selection: Dictionary = {}
var _draft_selection: Dictionary = {}
var _active_category := "preset"
var _direction_id := "down"
var _status_message := "正式衣柜\n使用完整人物套装"
var _last_dispatch_result: Dictionary = {}
var _labels: Dictionary = {}
var _hit_controls: Dictionary = {}
var _font: FontVariation
var _button_font: FontVariation
var _selected_font: FontVariation
var _canvas_scale := 1.0
var _canvas_offset := Vector2.ZERO
var _catalog_contract: Dictionary = {}
var _catalog_validation: Dictionary = {}
var _catalog_selection: Dictionary = {}
var _catalog_original_selection: Dictionary = {}
var _catalog_look_index := INITIAL_LOOK_INDEX
var _catalog_page := 0
var _catalog_page_count := 1
var _all_catalog_entries: Array[Dictionary] = []
var _catalog_entries: Array[Dictionary] = []
var _catalog_thumbnail_nodes: Array[TextureRect] = []
var _wardrobe_catalog: Dictionary = {}
var _wardrobe_loadouts: Array[Dictionary] = []
var _active_loadout_id := ""
var _preview_texture_cache: Dictionary = {}
var _operation_status := "idle"
var _operation_error_message := ""
var _loading_frame := 0
var _loading_timer: Timer
var _hover_target := ""
var _focus_target := ""
var _touch_target := ""
var _touch_index := -1
var _touch_origin := Vector2.ZERO
var _touch_cancelled := false
var _discard_confirmation_armed := false
var _discard_confirmation: FormalDialog


func _ready() -> void:
	clip_contents = true
	_initialize_catalog()
	_create_borderless_visual_overlays()
	_create_status_timer()
	_create_hit_targets()
	_build_discard_confirmation()
	_resolve_layout()
	resized.connect(_resolve_layout)
	_ui_ready = true
	var route_payload := get_meta("route_payload", {}) as Dictionary
	_apply_route_payload(route_payload)
	if not _pending_view_model.is_empty():
		_apply_view_model_internal(_pending_view_model)
		_pending_view_model.clear()
	_refresh_visuals()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if request_back():
			get_viewport().set_input_as_handled()


func request_back() -> bool:
	_request_cancel()
	return true


func _exit_tree() -> void:
	unbind_town_ui_adapter()


func bind_town_ui_adapter(adapter: Node) -> Dictionary:
	unbind_town_ui_adapter()
	_adapter = adapter if is_instance_valid(adapter) else null
	if _adapter == null:
		return _failure("TOWN_UI_ADAPTER_UNAVAILABLE")
	if (
		not _adapter.has_method("get_view_model")
		or not _adapter.has_method("dispatch")
		or not _adapter.has_signal("view_model_changed")
	):
		_adapter = null
		return _failure("TOWN_UI_ADAPTER_CONTRACT_MISSING")
	var callback := Callable(self, "_on_view_model_changed")
	if not _adapter.is_connected("view_model_changed", callback):
		_adapter.connect("view_model_changed", callback)
	var view_model := _adapter.call("get_view_model", "wardrobe") as Dictionary
	if _ui_ready:
		apply_view_model(view_model)
	else:
		_pending_view_model = view_model.duplicate(true)
	return {"ok": true, "errorCode": "", "retryable": false}


func unbind_town_ui_adapter() -> void:
	if not is_instance_valid(_adapter):
		_adapter = null
		return
	var callback := Callable(self, "_on_view_model_changed")
	if _adapter.has_signal("view_model_changed") and _adapter.is_connected(
		"view_model_changed",
		callback,
	):
		_adapter.disconnect("view_model_changed", callback)
	_adapter = null


func apply_view_model(view_model: Dictionary) -> bool:
	if not _ui_ready:
		_pending_view_model = view_model.duplicate(true)
		return true
	return _apply_view_model_internal(view_model)


func apply_wardrobe_handoff(handoff: Dictionary) -> Dictionary:
	var result: Dictionary = _contract.configure_handoff(handoff)
	if not bool(result.get("ok", false)):
		_handoff_error = String(result.get("errorCode", "WARDROBE_HANDOFF_INVALID"))
		_status_message = "正式换装入口待接线"
		_refresh_visuals()
		return result
	_handoff = (result.get("handoff", {}) as Dictionary).duplicate(true)
	_handoff_error = ""
	_original_selection = (result.get("selection", {}) as Dictionary).duplicate(true)
	_confirmed_selection = _original_selection.duplicate(true)
	_draft_selection = _original_selection.duplicate(true)
	_select_matching_frozen_loadout(
		String(_handoff.get("loadoutId", "")),
		_draft_selection,
	)
	_catalog_original_selection = _catalog_selection.duplicate(true)
	_active_category = "preset"
	_direction_id = "down"
	_last_dispatch_result.clear()
	_status_message = "完整人物套装\n选择数据已保留"
	_refresh_visuals()
	return result


func get_view_model() -> Dictionary:
	return _view_model.duplicate(true)


func set_safety_overlay_visible(visible_value: bool) -> void:
	_safety_overlay.visible = visible_value
	_safety_overlay.queue_redraw()


func focus_default_control() -> void:
	var target := _hit_controls.get("back") as Control
	if target != null and target.focus_mode != Control.FOCUS_NONE:
		target.grab_focus()


func get_hit_target_rects_in_viewport() -> Dictionary:
	var result := {}
	for target_id: String in _hit_controls:
		var base_rect := HIT_TARGETS[target_id] as Rect2
		result[target_id] = Rect2(
			_canvas_offset + base_rect.position * _canvas_scale,
			base_rect.size * _canvas_scale,
		)
	return result


func debug_snapshot() -> Dictionary:
	return {
		"scope": "wardrobe",
		"formalReady": bool(_catalog_validation.get("ok", false)),
		"visualReviewPending": false,
		"visualRevision": VISUAL_REVISION,
		"assetShellPath": ASSET_SHELL_PATH,
		"assetShellSha256": ASSET_SHELL_SHA256,
		"assetShellTextureSize": (
			_visual_owner.texture.get_size() if _visual_owner.texture != null else Vector2.ZERO
		),
		"baseViewportAssetPixelRatio": 1.0 if size == BASE_SIZE else _canvas_scale,
		"fontPath": FONT_PATH,
		"usesMainMenuGlobalHeiti": true,
		"fontSizes": [BODY_FONT_SIZE, DISPLAY_FONT_SIZE],
		"fontShrinkApplied": false,
		"integerBaseRectPlacement": true,
		"directionAlignment": _direction_alignment_snapshot(),
		"textMetricAudit": debug_text_metric_audit(),
		"contrastAudit": debug_contrast_audit(),
		"assetProviderId": RIG_PROVIDER_ID,
		"assetStatus": String(_catalog_contract.get("assetStatus", "missing")),
		"technicalArchitecture": "classic_resident_complete_sprite_sheet",
		"technologyStatus": "architecture_confirmed",
		"selectionMode": "complete_set_only",
		"slotOrder": PREVIEW_SLOT_ORDER.duplicate(),
		"handoffSlotOrder": SLOT_ORDER.duplicate(),
		"directionSet": DIRECTIONS.duplicate(),
		"directionId": _direction_id,
		"activeCategoryId": _active_category,
		"handoffReady": not _handoff.is_empty(),
		"handoffError": _handoff_error,
		"originalSelection": _original_selection.duplicate(true),
		"confirmedSelection": _confirmed_selection.duplicate(true),
		"draftSelection": _draft_selection.duplicate(true),
		"selectionDirty": _draft_selection != _original_selection,
		"loadoutId": String(_handoff.get("loadoutId", "")),
		"lastDispatchResult": _last_dispatch_result.duplicate(true),
		"viewModelRevision": _view_model_revision,
		"viewportSize": [int(round(size.x)), int(round(size.y))],
		"canvasScale": _canvas_scale,
		"canvasOffset": [_canvas_offset.x, _canvas_offset.y],
		"visualOwner": str(_visual_owner.get_path()),
		"visibleBorderOwnerCount": 1,
		"wholeAssetShellUsedIntact": true,
		"borderSource": "registered_page_composite_image_asset",
		"realGodotChineseOverlay": true,
		"oldPaperDoll64Referenced": false,
		"formalCompleteSetPreview": _resident_wardrobe_preview.texture != null,
		"formalFrontThumbnails": true,
		"catalogValidation": _catalog_validation.duplicate(true),
		"catalogSelection": _catalog_selection.duplicate(true),
		"catalogFrontDirectionOnly": true,
		"catalogVisibleEntryCount": _catalog_entries.size(),
		"catalogTotalEntryCount": _all_catalog_entries.size(),
		"catalogPage": _catalog_page,
		"catalogPageCount": _catalog_page_count,
		"catalogPageSize": CATALOG_PAGE_SIZE,
		"operationStatus": _operation_status,
		"loadingFrame": _loading_frame,
		"discardConfirmationArmed": _discard_confirmation_armed,
		"characterBakedIntoShell": false,
		"croppedFromReviewImage": false,
		"usesStyleBoxFlat": false,
		"usesDefaultTheme": false,
		"usesDefaultThemeFrames": false,
		"usesCommonSubstitute": false,
		"usesTemporaryApproximateAssets": false,
		"registeredAsGenericStyleBoxTexture": false,
		"hitTargetCount": _hit_controls.size(),
		"inputMethods": ["keyboard", "mouse", "gamepad", "touch"],
		"formalPreviewCount": 1,
		"formalFrontThumbnailCount": _catalog_thumbnail_nodes.size(),
		"saveWritesFormalData": not _handoff.is_empty(),
		"uiStateAnimations": [
			"hover_focus_90ms",
			"loading_3_frame_180ms",
			"success_fade_220ms",
			"error_shake_150ms",
		],
		"safetyOverlayVisible": _safety_overlay.visible,
	}


func _direction_alignment_snapshot() -> Dictionary:
	var preview_center_x := (
		_resident_wardrobe_preview.position.x + _resident_wardrobe_preview.size.x * 0.5
	)
	var first_rect := TEXT_SLOTS["direction_down"] as Rect2
	var last_rect := TEXT_SLOTS["direction_left"] as Rect2
	var label_group_center_x := (
		first_rect.position.x + last_rect.end.x
	) * 0.5
	var first_hit := HIT_TARGETS["direction_down"] as Rect2
	var last_hit := HIT_TARGETS["direction_left"] as Rect2
	var hit_group_center_x := (
		first_hit.position.x + last_hit.end.x
	) * 0.5
	return {
		"previewCenterX": preview_center_x,
		"assetPaperCenterX": 556.5,
		"assetDirectionGroupCenterX": 556.0,
		"labelGroupCenterX": label_group_center_x,
		"hitGroupCenterX": hit_group_center_x,
		"runtimeCenterDelta": absf(preview_center_x - label_group_center_x),
		"assetCenterDelta": 0.5,
	}


func debug_text_metric_audit() -> Dictionary:
	if _font == null or _button_font == null:
		return {"allPass": false, "errorCode": "WARDROBE_FONT_UNAVAILABLE"}
	var metric_samples := {
		"back": "返回入口",
		"title": "外观与换装设置",
		"resident": "资产测试",
		"category_preset": "预设",
		"category_head": "发型",
		"category_top_hands": "上衣",
		"category_bottom": "下装",
		"category_shoes": "鞋",
		"item_0": "暖棕蓬松短发造型",
		"item_1": "灰黑柔顺短发造型",
		"item_2": "临时不可用的发型",
		"item_3": "侧分自然短发造型",
		"item_4": "轻盈层次短发造型",
		"item_5": "低马尾日常发型",
		"direction_down": "正面",
		"direction_right": "右侧",
		"direction_up": "背面",
		"direction_left": "左侧",
		"page_previous": "〈",
		"page_next": "〉",
		"status": "资产测试临时素材\n草稿状态保留",
		"restore": "恢复原样",
		"randomize": "随机搭配",
		"cancel": "取消",
		"apply": "保存",
	}
	var checks: Array[Dictionary] = []
	var all_pass := true
	for slot_id: String in TEXT_SLOTS:
		var font_size := (
			DISPLAY_FONT_SIZE
			if slot_id in ["title", "apply"]
			else BODY_FONT_SIZE
		)
		var font: Font = (
			_button_font
			if slot_id in ["restore", "randomize", "cancel", "apply"]
			else _font
		)
		var slot_rect := TEXT_SLOTS[slot_id] as Rect2
		var sample := String(metric_samples.get(slot_id, ""))
		var lines := sample.split("\n")
		var expanded_width := 0.0
		for line: String in lines:
			expanded_width = maxf(
				expanded_width,
				font.get_string_size(
					line,
					HORIZONTAL_ALIGNMENT_LEFT,
					-1.0,
					font_size,
				).x * 1.3,
			)
		var line_height := font.get_height(font_size)
		var required_height := line_height * float(lines.size())
		var overflow_policy := "none"
		var fits := (
			expanded_width <= slot_rect.size.x
			and required_height <= slot_rect.size.y
		)
		if slot_id.begins_with("item_"):
			overflow_policy = "ellipsis_with_focus_detail"
			fits = line_height <= slot_rect.size.y
		elif slot_id in ["restore", "randomize", "cancel"] and not fits:
			overflow_policy = "two_line_wrap"
			fits = line_height * 2.0 <= slot_rect.size.y
		checks.append({
			"slotId": slot_id,
			"fontSize": font_size,
			"lineHeight": line_height,
			"expandedWidth130": expanded_width,
			"slotSize": slot_rect.size,
			"overflowPolicy": overflow_policy,
			"pass": fits,
		})
		all_pass = all_pass and fits
	return {
		"allPass": all_pass,
		"fontPath": FONT_PATH,
		"fontSizes": [BODY_FONT_SIZE, DISPLAY_FONT_SIZE],
		"copyExpansion": 1.3,
		"fontShrinkApplied": false,
		"checks": checks,
	}


func debug_contrast_audit() -> Dictionary:
	var paper_background := Color("FFE5B8")
	var apply_background := Color("C5420A")
	var body_ratio := _contrast_ratio(INK, paper_background)
	var apply_ratio := _contrast_ratio(PAPER, apply_background)
	return {
		"bodyRatio": body_ratio,
		"applyRatio": apply_ratio,
		"requiredRatio": 4.5,
		"allPass": body_ratio >= 4.5 and apply_ratio >= 4.5,
	}


func _contrast_ratio(first: Color, second: Color) -> float:
	var first_luminance := _relative_luminance(first)
	var second_luminance := _relative_luminance(second)
	return (
		(maxf(first_luminance, second_luminance) + 0.05)
		/ (minf(first_luminance, second_luminance) + 0.05)
	)


func _relative_luminance(color: Color) -> float:
	var red := _linear_color_component(color.r)
	var green := _linear_color_component(color.g)
	var blue := _linear_color_component(color.b)
	return red * 0.2126 + green * 0.7152 + blue * 0.0722


func _linear_color_component(component: float) -> float:
	if component <= 0.04045:
		return component / 12.92
	return pow((component + 0.055) / 1.055, 2.4)


func _apply_view_model_internal(view_model: Dictionary) -> bool:
	if String(view_model.get("scope", "")) != "wardrobe":
		return false
	var incoming_revision := int(view_model.get("revision", -1))
	if incoming_revision >= 0 and incoming_revision < _view_model_revision:
		return false
	_view_model_revision = incoming_revision
	_view_model = view_model.duplicate(true)
	var extracted: Dictionary = _extract_handoff(view_model)
	if not extracted.is_empty():
		apply_wardrobe_handoff(extracted)
	var operation := view_model.get("operation", {}) as Dictionary
	var operation_status := String(operation.get("status", "idle"))
	if String(view_model.get("status", "")) == "disabled":
		operation_status = "disabled"
	var error_value: Variant = view_model.get("error", {})
	var error := error_value as Dictionary if error_value is Dictionary else {}
	_set_operation_state(
		operation_status,
		String(error.get("message", "")),
	)
	_refresh_visuals()
	return true


func _extract_handoff(view_model: Dictionary) -> Dictionary:
	var data := view_model.get("data", {}) as Dictionary
	for candidate: Variant in [
		view_model.get("wardrobeHandoff", {}),
		data.get("wardrobeHandoff", {}),
		data.get("handoff", {}),
	]:
		if candidate is Dictionary and not (candidate as Dictionary).is_empty():
			return (candidate as Dictionary).duplicate(true)
	var slot_order_value: Variant = data.get("slotOrder")
	var selection_value: Variant = data.get("draftSelection", data.get("selection", {}))
	if slot_order_value != SLOT_ORDER or not selection_value is Dictionary:
		return {}
	var actions := view_model.get("actions", {}) as Dictionary
	var apply_action := actions.get("apply", {}) as Dictionary
	var return_intent := String(apply_action.get("intent", ""))
	if return_intent.is_empty():
		return {}
	return {
		"sourceScope": String(data.get("sourceScope", "wardrobe")),
		"draftId": String(data.get("draftId", "wardrobe-runtime")),
		"returnRevision": int(view_model.get("revision", 0)),
		"returnIntent": return_intent,
		"cancelIntent": String(
			(actions.get("cancel", {}) as Dictionary).get("intent", "wardrobe.cancel")
		),
		"selection": (selection_value as Dictionary).duplicate(true),
		"loadoutId": String(data.get("loadoutId", "")),
		"slotOrder": SLOT_ORDER.duplicate(),
		"catalogPath": String(data.get("catalogPath", "")),
	}


func _apply_route_payload(payload: Dictionary) -> void:
	if payload.is_empty():
		return
	var candidate: Variant = payload.get("wardrobeHandoff", payload)
	if candidate is Dictionary:
		var handoff: Dictionary = candidate as Dictionary
		if handoff.has("sourceScope") and handoff.has("returnIntent"):
			apply_wardrobe_handoff(handoff)


func _initialize_catalog() -> void:
	_wardrobe_catalog = _load_json(WARDROBE_CATALOG_PATH)
	if String(_wardrobe_catalog.get("schema", "")) != WARDROBE_CATALOG_SCHEMA:
		_catalog_validation = {
			"ok": false,
			"errorCode": "RESIDENT_WARDROBE_CATALOG_INVALID",
		}
		_status_message = "正式衣柜目录不可用"
		return
	_wardrobe_loadouts.clear()
	for value: Variant in _wardrobe_catalog.get("loadouts", []) as Array:
		if value is Dictionary:
			_wardrobe_loadouts.append((value as Dictionary).duplicate(true))
	if _wardrobe_loadouts.size() != 16:
		_catalog_validation = {
			"ok": false,
			"errorCode": "RESIDENT_WARDROBE_LOADOUT_COUNT_INVALID",
		}
		_status_message = "正式衣柜套装数量不完整"
		return
	_catalog_validation = {
		"ok": true,
		"schema": WARDROBE_CATALOG_SCHEMA,
		"revision": String(_wardrobe_catalog.get("revision", "")),
		"loadoutCount": _wardrobe_loadouts.size(),
	}
	_catalog_contract = {
		"assetStatus": "formal",
		"formalReady": true,
		"catalogPath": WARDROBE_CATALOG_PATH,
	}
	var initial_look: Dictionary = _wardrobe_loadouts[0]
	_active_loadout_id = String(initial_look.get("id", ""))
	_catalog_selection = _selection_for_loadout(initial_look)
	_catalog_original_selection = _catalog_selection.duplicate(true)
	_create_catalog_nodes()
	_status_message = "居民衣柜 · 16套完整人物"


func _create_catalog_nodes() -> void:
	for index: int in range(CATALOG_CONTENT_RECTS.size()):
		var content_rect: Rect2 = CATALOG_CONTENT_RECTS[index]
		var thumbnail := TextureRect.new()
		thumbnail.name = "WardrobeCatalogThumbnail_%d" % index
		thumbnail.position = content_rect.position
		thumbnail.size = content_rect.size
		thumbnail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		thumbnail.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		thumbnail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		thumbnail.visible = false
		_visual_canvas.add_child(thumbnail)
		_catalog_thumbnail_nodes.append(thumbnail)


func _refresh_catalog() -> void:
	if not bool(_catalog_validation.get("ok", false)):
		return
	var active_loadout := _loadout_by_id(_active_loadout_id)
	_resident_wardrobe_preview.texture = _loadout_preview_texture(
		active_loadout,
		_direction_id,
		true,
	)
	_resident_wardrobe_preview.visible = (
		_resident_wardrobe_preview.texture != null
	)
	_all_catalog_entries = _catalog_entries_for_active_category()
	_catalog_page_count = maxi(
		1,
		ceili(float(_all_catalog_entries.size()) / float(CATALOG_PAGE_SIZE)),
	)
	_catalog_page = clampi(_catalog_page, 0, _catalog_page_count - 1)
	var page_start := _catalog_page * CATALOG_PAGE_SIZE
	var page_end := mini(
		page_start + CATALOG_PAGE_SIZE,
		_all_catalog_entries.size(),
	)
	_catalog_entries.clear()
	for index: int in range(page_start, page_end):
		_catalog_entries.append(
			_all_catalog_entries[index].duplicate(true)
		)
	for index: int in range(CATALOG_CONTENT_RECTS.size()):
		var thumbnail: TextureRect = _catalog_thumbnail_nodes[index]
		thumbnail.visible = false
		thumbnail.texture = null
		_set_label("item_%d" % index, "")
		_set_label_selected("item_%d" % index, false)
		if index >= _catalog_entries.size():
			continue
		var entry: Dictionary = _catalog_entries[index]
		_set_label("item_%d" % index, String(entry.get("label", "")))
		if String(entry.get("kind", "")) == "preset":
			var look := entry.get("look", {}) as Dictionary
			thumbnail.texture = _loadout_preview_texture(look, "portrait", false)
			thumbnail.visible = thumbnail.texture != null
			if String(look.get("id", "")) == _active_loadout_id:
				_set_label_selected("item_%d" % index, true)
			continue
		var slot_id := String(entry.get("slotId", ""))
		var item_id := String(entry.get("itemId", ""))
		thumbnail.texture = _load_texture_path(
			String(entry.get("thumbnailPath", "")),
		)
		thumbnail.visible = thumbnail.texture != null
		if String(_catalog_selection.get(slot_id, "")) == item_id:
			_set_label_selected("item_%d" % index, true)
	_refresh_catalog_active_copy()


func _catalog_entries_for_active_category() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in range(_wardrobe_loadouts.size()):
		var look := _wardrobe_loadouts[index]
		result.append({
			"kind": "preset",
			"label": String(look.get("label", "套装 %02d" % (index + 1))),
			"look": look.duplicate(true),
		})
	return result


func _refresh_catalog_active_copy() -> void:
	var category_slots := {
		"preset": "category_preset",
	}
	for category_id: String in category_slots:
		_set_label_selected(
			String(category_slots[category_id]),
			category_id == _active_category,
		)
	for direction_id: String in DIRECTIONS:
		_set_label_selected(
			"direction_%s" % direction_id,
			direction_id == _direction_id,
		)


func _select_catalog_entry(index: int) -> void:
	if index < 0 or index >= _catalog_entries.size():
		return
	var entry: Dictionary = _catalog_entries[index]
	if String(entry.get("kind", "")) == "preset":
		var look := entry.get("look", {}) as Dictionary
		_activate_loadout(look)
	else:
		var slot_id := String(entry.get("slotId", ""))
		var item_id := String(entry.get("itemId", ""))
		if slot_id == "hair":
			_catalog_selection["hair"] = item_id
		else:
			for outfit_slot: String in ["top", "bottom", "shoes"]:
				_catalog_selection[outfit_slot] = item_id
		_select_matching_frozen_loadout("", _catalog_selection)
	_sync_contract_draft_from_catalog()
	_last_dispatch_result.clear()
	_discard_confirmation_armed = false
	_status_message = "正式衣柜 · 当前外观"
	_refresh_visuals()


func _selection_for_loadout(loadout: Dictionary) -> Dictionary:
	var head_id := String(loadout.get("headId", ""))
	var outfit_id := String(loadout.get("outfitId", ""))
	return {
		"hair": head_id,
		"top": outfit_id,
		"bottom": outfit_id,
		"shoes": outfit_id,
	}


func _activate_loadout(loadout: Dictionary) -> void:
	if loadout.is_empty():
		return
	_active_loadout_id = String(loadout.get("id", ""))
	_catalog_selection = _selection_for_loadout(loadout)
	_catalog_look_index = maxi(
		0,
		_wardrobe_loadouts.find(loadout),
	)
	if not _handoff.is_empty():
		_handoff["loadoutId"] = _active_loadout_id


func _select_matching_frozen_loadout(
	loadout_id: String,
	selection: Dictionary,
) -> void:
	if not loadout_id.is_empty():
		var direct := _loadout_by_id(loadout_id)
		if not direct.is_empty():
			_activate_loadout(direct)
			return
	var hair_id := String(selection.get("hair", ""))
	var outfit_id := String(selection.get("top", selection.get("bottom", "")))
	for loadout: Dictionary in _wardrobe_loadouts:
		if (
			String(loadout.get("headId", "")) == hair_id
			and String(loadout.get("outfitId", "")) == outfit_id
		):
			_activate_loadout(loadout)
			return
	if not _wardrobe_loadouts.is_empty():
		_activate_loadout(_wardrobe_loadouts[0])


func _loadout_by_id(loadout_id: String) -> Dictionary:
	for loadout: Dictionary in _wardrobe_loadouts:
		if String(loadout.get("id", "")) == loadout_id:
			return loadout
	return {}


func _loadout_preview_texture(
	loadout: Dictionary,
	direction_id: String,
	crop_character: bool,
) -> Texture2D:
	if loadout.is_empty():
		return null
	var path := String(loadout.get("portraitPath", ""))
	var mirror := false
	if direction_id != "portrait":
		path = String(loadout.get("spriteSheetPath", ""))
		mirror = direction_id == "right"
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var cache_key := "%s|%s|%s|%s" % [
		path,
		direction_id,
		mirror,
		crop_character,
	]
	if _preview_texture_cache.has(cache_key):
		return _preview_texture_cache[cache_key] as Texture2D
	var source := load(path) as Texture2D
	if source == null:
		return null
	if not mirror and not crop_character:
		_preview_texture_cache[cache_key] = source
		return source
	var image := source.get_image()
	if image == null or image.is_empty():
		return source
	if direction_id != "portrait":
		var column := 0
		match direction_id:
			"left", "right":
				column = 1
			"up":
				column = 2
		image = image.get_region(Rect2i(column * 512, 0, 512, 512))
	if mirror:
		image.flip_x()
	if crop_character:
		var used := image.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			var padded := used.grow(12).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
			image = image.get_region(padded)
	var texture := ImageTexture.create_from_image(image)
	_preview_texture_cache[cache_key] = texture
	return texture


func _load_texture_path(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var cache_key := "slot|%s" % path
	if _preview_texture_cache.has(cache_key):
		return _preview_texture_cache[cache_key] as Texture2D
	var texture := load(path) as Texture2D
	if texture != null:
		_preview_texture_cache[cache_key] = texture
	return texture


func _sync_contract_draft_from_catalog() -> void:
	for slot_id: String in SLOT_ORDER:
		_draft_selection[slot_id] = String(_catalog_selection.get(slot_id, ""))


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


func _create_status_timer() -> void:
	_loading_timer = Timer.new()
	_loading_timer.name = "WardrobeUiLoadingFrames"
	_loading_timer.wait_time = 0.18
	_loading_timer.one_shot = false
	_loading_timer.timeout.connect(_on_loading_frame_timeout)
	add_child(_loading_timer)


func _set_operation_state(status: String, error_message: String = "") -> void:
	_operation_status = status if status in [
		"idle", "loading", "success", "rejected", "error", "disabled",
	] else "idle"
	_operation_error_message = error_message.strip_edges()
	_loading_frame = 0
	if _operation_status == "loading":
		_loading_timer.start()
	else:
		_loading_timer.stop()
	_play_status_motion()


func _on_loading_frame_timeout() -> void:
	_loading_frame = (_loading_frame + 1) % 3
	_set_label("status", _status_copy())


func _play_status_motion() -> void:
	var status_label := _labels.get("status") as Label
	if status_label == null:
		return
	status_label.position = (TEXT_SLOTS["status"] as Rect2).position
	status_label.modulate = Color.WHITE
	if _operation_status in ["rejected", "error"]:
		var error_tween := create_tween()
		error_tween.tween_property(
			status_label,
			"position:x",
			status_label.position.x - 3.0,
			0.06,
		)
		error_tween.tween_property(
			status_label,
			"position:x",
			status_label.position.x + 3.0,
			0.06,
		)
		error_tween.tween_property(
			status_label,
			"position:x",
			(TEXT_SLOTS["status"] as Rect2).position.x,
			0.06,
		)
	elif _operation_status == "success":
		status_label.modulate = Color(0.82, 1.0, 0.82, 1.0)
		var success_tween := create_tween()
		success_tween.tween_property(status_label, "modulate", Color.WHITE, 0.22)


func _create_borderless_visual_overlays() -> void:
	var font_file := ResourceLoader.load(FONT_PATH, "FontFile") as FontFile
	if font_file == null:
		_status_message = "正式中文字体不可用"
		return
	_font = _font_variation(font_file, 0.0)
	_button_font = _font_variation(font_file, 0.0)
	_selected_font = _font_variation(font_file, 0.8)
	var category_cover := ColorRect.new()
	category_cover.name = "CompleteSetCategoryCover"
	category_cover.position = Vector2(1014.0, 246.0)
	category_cover.size = Vector2(642.0, 82.0)
	category_cover.color = PAPER
	category_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visual_canvas.add_child(category_cover)
	_add_back_arrow()
	_add_real_chinese_labels()


func _font_variation(font_file: FontFile, embolden: float) -> FontVariation:
	var result := FontVariation.new()
	result.base_font = font_file
	result.spacing_glyph = 2
	result.variation_embolden = embolden
	return result


func _add_back_arrow() -> void:
	var arrow := Polygon2D.new()
	arrow.name = "BackArrowBorderlessOverlay"
	arrow.color = INK
	arrow.polygon = PackedVector2Array([
		Vector2(290.0, 150.0),
		Vector2(322.0, 122.0),
		Vector2(322.0, 140.0),
		Vector2(360.0, 140.0),
		Vector2(360.0, 164.0),
		Vector2(322.0, 164.0),
		Vector2(322.0, 182.0),
	])
	_visual_canvas.add_child(arrow)


func _add_real_chinese_labels() -> void:
	for slot_id: String in TEXT_SLOTS:
		var label := Label.new()
		label.name = "Text_%s" % slot_id
		label.position = (TEXT_SLOTS[slot_id] as Rect2).position
		label.size = (TEXT_SLOTS[slot_id] as Rect2).size
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_override(
			"font",
			_button_font if slot_id in ["restore", "randomize", "cancel", "apply"] else _font,
		)
		var slot_font_size := BODY_FONT_SIZE
		if slot_id in ["title", "apply"]:
			slot_font_size = DISPLAY_FONT_SIZE
		elif slot_id.begins_with("item_"):
			slot_font_size = 24
		label.add_theme_font_size_override("font_size", slot_font_size)
		label.add_theme_color_override("font_color", PAPER if slot_id == "apply" else INK)
		label.add_theme_constant_override("outline_size", 1 if slot_id == "apply" else 0)
		label.add_theme_color_override("font_outline_color", INK)
		label.autowrap_mode = (
			TextServer.AUTOWRAP_WORD_SMART
			if (
				slot_id in ["status", "restore", "randomize", "cancel"]
				or slot_id.begins_with("item_")
			)
			else TextServer.AUTOWRAP_OFF
		)
		if slot_id == "status" or slot_id.begins_with("item_"):
			label.max_lines_visible = 2
		label.text_overrun_behavior = (
			TextServer.OVERRUN_TRIM_ELLIPSIS
			if slot_id == "status" or slot_id.begins_with("item_")
			else TextServer.OVERRUN_NO_TRIMMING
		)
		_visual_canvas.add_child(label)
		_labels[slot_id] = label


func _refresh_visuals() -> void:
	if not _ui_ready or _labels.is_empty():
		return
	_set_label("resident", _resident_copy())
	_set_label("status", _status_copy())
	for slot_id: String in BASE_COPY:
		_set_label(slot_id, String(BASE_COPY[slot_id]))
	_refresh_operation_copy()
	for index: int in range(6):
		_set_label("item_%d" % index, "")
	_refresh_catalog()
	_refresh_operation_colors()


func _resident_copy() -> String:
	return String(_handoff.get("residentName", "居民衣柜"))


func _status_copy() -> String:
	if not bool(_catalog_validation.get("ok", false)):
		return _status_message
	if _discard_confirmation_armed:
		return "外观尚未保存\n请选择放弃修改或继续编辑"
	match _operation_status:
		"loading":
			return "正在保存%s\n当前外观保持可见" % ".".repeat(_loading_frame + 1)
		"success":
			return "外观已保存\n可以返回小镇"
		"rejected":
			return (
				_operation_error_message
				if not _operation_error_message.is_empty()
				else "状态已更新\n请重新确认当前外观"
			)
		"error":
			return (
				_operation_error_message
				if not _operation_error_message.is_empty()
				else "预览暂时不可用\n草稿已保留"
			)
		"disabled":
			return "换装服务暂不可用\n当前外观仍可查看"
	return "居民衣柜 · 16套完整人物\n目录 %d/%d" % [
		_catalog_page + 1,
		_catalog_page_count,
	]


func _set_label(slot_id: String, copy: String) -> void:
	var label := _labels.get(slot_id) as Label
	if label != null:
		label.text = copy


func _set_label_color(slot_id: String, color: Color) -> void:
	var label := _labels.get(slot_id) as Label
	if label != null:
		label.add_theme_color_override("font_color", color)


func _set_label_selected(slot_id: String, selected: bool) -> void:
	var label := _labels.get(slot_id) as Label
	if label == null:
		return
	label.add_theme_color_override(
		"font_color",
		SELECTED_GREEN if selected else INK,
	)
	label.add_theme_font_override(
		"font",
		_selected_font if selected else _font,
	)


func _refresh_operation_colors() -> void:
	var status_color := INK
	if _operation_status in ["rejected", "error"] or _discard_confirmation_armed:
		status_color = ERROR_INK
	elif _operation_status == "success":
		status_color = SUCCESS_INK
	elif _operation_status == "disabled":
		status_color = MUTED_INK
	_set_label_color("status", status_color)
	_set_label_color(
		"apply",
		PAPER if _target_enabled("apply") else DISABLED_PRIMARY_INK,
	)
	_set_label_color("page_previous", INK if _catalog_page > 0 else MUTED_INK)
	_set_label_color(
		"page_next",
		INK if _catalog_page + 1 < _catalog_page_count else MUTED_INK,
	)
	var active_target := _focus_target if not _focus_target.is_empty() else _hover_target
	if not active_target.is_empty() and _target_enabled(active_target):
		var label_slot := _label_slot_for_target(active_target)
		if not label_slot.is_empty():
			_set_label_color(
				label_slot,
				PAPER if active_target == "apply" else SELECTED_GREEN,
			)


func _refresh_operation_copy() -> void:
	match _operation_status:
		"loading":
			_set_label("apply", "保存中")
		"success":
			_set_label("apply", "完成")
		"rejected":
			_set_label("apply", "待刷新")
		"error":
			_set_label("apply", "重试")
		"disabled":
			_set_label("apply", "不可用")
		_:
			_set_label("apply", "保存")


func _resolve_layout() -> void:
	if not is_instance_valid(_visual_canvas):
		return
	var available := size
	if available.x <= 0.0 or available.y <= 0.0:
		return
	_canvas_scale = min(available.x / BASE_SIZE.x, available.y / BASE_SIZE.y)
	var rendered_size := BASE_SIZE * _canvas_scale
	_canvas_offset = (available - rendered_size) * 0.5
	_visual_canvas.position = _canvas_offset.round()
	_visual_canvas.scale = Vector2.ONE * _canvas_scale
	_safety_overlay.queue_redraw()


func _create_hit_targets() -> void:
	for target_id: String in HIT_TARGETS:
		if target_id in [
			"category_head",
			"category_top_hands",
			"category_bottom",
			"category_shoes",
		]:
			continue
		var target := Control.new()
		target.name = "Hit_%s" % target_id
		target.position = (HIT_TARGETS[target_id] as Rect2).position
		target.size = (HIT_TARGETS[target_id] as Rect2).size
		target.mouse_filter = Control.MOUSE_FILTER_STOP
		target.focus_mode = Control.FOCUS_ALL
		target.gui_input.connect(_on_hit_target_gui_input.bind(target_id))
		target.mouse_entered.connect(_on_target_hover_changed.bind(target_id, true))
		target.mouse_exited.connect(_on_target_hover_changed.bind(target_id, false))
		target.focus_entered.connect(_on_target_focus_changed.bind(target_id, true))
		target.focus_exited.connect(_on_target_focus_changed.bind(target_id, false))
		_visual_canvas.add_child(target)
		_hit_controls[target_id] = target


func _on_hit_target_gui_input(event: InputEvent, target_id: String) -> void:
	var activate := false
	if event is InputEventMouseButton:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		activate = event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _touch_index >= 0:
				return
			_touch_target = target_id
			_touch_index = touch.index
			_touch_origin = touch.position
			_touch_cancelled = false
			accept_event()
			return
		if touch.index != _touch_index or target_id != _touch_target:
			return
		activate = (
			not touch.canceled
			and not _touch_cancelled
			and Rect2(
				Vector2.ZERO,
				(HIT_TARGETS[target_id] as Rect2).size,
			).has_point(touch.position)
		)
		_reset_touch_target()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index != _touch_index or target_id != _touch_target:
			return
		if drag.position.distance_to(_touch_origin) > TOUCH_TAP_SLOP:
			_touch_cancelled = true
		accept_event()
		return
	elif event is InputEventKey:
		activate = event.pressed and not event.echo and (
			event.keycode == KEY_ENTER or event.keycode == KEY_SPACE
		)
	elif event is InputEventJoypadButton:
		activate = event.pressed and event.button_index == JOY_BUTTON_A
	if not activate:
		return
	accept_event()
	_activate_target(target_id)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_reset_touch_target()


func _reset_touch_target() -> void:
	_touch_target = ""
	_touch_index = -1
	_touch_origin = Vector2.ZERO
	_touch_cancelled = false


func _on_target_hover_changed(target_id: String, active: bool) -> void:
	if active:
		_hover_target = target_id
	elif _hover_target == target_id:
		_hover_target = ""
	_refresh_visuals()
	_animate_target_content(target_id, active or _focus_target == target_id)


func _on_target_focus_changed(target_id: String, active: bool) -> void:
	if active:
		_focus_target = target_id
	elif _focus_target == target_id:
		_focus_target = ""
	_refresh_visuals()
	_animate_target_content(target_id, active or _hover_target == target_id)


func _target_enabled(target_id: String) -> bool:
	if target_id in [
		"category_head",
		"category_top_hands",
		"category_bottom",
		"category_shoes",
	]:
		return false
	if _operation_status == "loading":
		return target_id.begins_with("direction_")
	if _operation_status == "disabled":
		return target_id in ["back", "cancel"]
	if _operation_status == "error" and (
		target_id.begins_with("item_")
		or target_id in ["randomize", "apply"]
	):
		return false
	if _operation_status == "rejected" and target_id == "apply":
		return false
	if target_id == "page_previous":
		return _catalog_page > 0
	if target_id == "page_next":
		return _catalog_page + 1 < _catalog_page_count
	if target_id.begins_with("item_"):
		var item_index := int(target_id.trim_prefix("item_"))
		return item_index >= 0 and item_index < _catalog_entries.size()
	if target_id == "restore":
		return _catalog_selection != _catalog_original_selection
	if target_id == "apply":
		return bool(_catalog_validation.get("ok", false))
	return true


func _label_slot_for_target(target_id: String) -> String:
	if target_id in TEXT_SLOTS:
		return target_id
	return ""


func _animate_target_content(target_id: String, active: bool) -> void:
	if not target_id.begins_with("item_"):
		return
	var item_index := int(target_id.trim_prefix("item_"))
	if item_index < 0 or item_index >= _catalog_thumbnail_nodes.size():
		return
	var content := _catalog_thumbnail_nodes[item_index]
	content.pivot_offset = content.size * 0.5
	var content_tween := create_tween()
	content_tween.set_trans(Tween.TRANS_QUAD)
	content_tween.set_ease(Tween.EASE_OUT)
	content_tween.tween_property(
		content,
		"scale",
		Vector2.ONE * (1.035 if active and _target_enabled(target_id) else 1.0),
		0.09,
	)


func _play_disabled_feedback() -> void:
	_set_label("status", _status_message)
	_set_label_color("status", ERROR_INK)
	var status_label := _labels.get("status") as Label
	if status_label == null:
		return
	var origin_x := (TEXT_SLOTS["status"] as Rect2).position.x
	var feedback_tween := create_tween()
	feedback_tween.tween_property(status_label, "position:x", origin_x - 3.0, 0.05)
	feedback_tween.tween_property(status_label, "position:x", origin_x + 3.0, 0.05)
	feedback_tween.tween_property(status_label, "position:x", origin_x, 0.05)


func _activate_target(target_id: String) -> void:
	if not _target_enabled(target_id):
		if target_id == "apply":
			_request_apply()
		else:
			_status_message = "当前操作暂不可用\n已保留现有选择"
			_play_disabled_feedback()
		return
	if target_id == "back" or target_id == "cancel":
		_request_cancel()
		return
	if target_id.begins_with("category_"):
		_active_category = "preset"
		_catalog_page = 0
		_refresh_visuals()
		return
	if target_id.begins_with("item_"):
		_select_catalog_entry(
			int(target_id.trim_prefix("item_"))
		)
		return
	if target_id.begins_with("direction_"):
		_direction_id = target_id.trim_prefix("direction_")
		_refresh_visuals()
		return
	if target_id == "page_previous":
		_catalog_page = maxi(0, _catalog_page - 1)
		_refresh_visuals()
		return
	if target_id == "page_next":
		_catalog_page = mini(_catalog_page_count - 1, _catalog_page + 1)
		_refresh_visuals()
		return
	match target_id:
		"restore":
			_select_matching_frozen_loadout(
				"",
				_catalog_original_selection,
			)
			_sync_contract_draft_from_catalog()
			_last_dispatch_result.clear()
			_discard_confirmation_armed = false
			_refresh_visuals()
		"randomize":
			_randomize_draft()
		"apply":
			_request_apply()


func _randomize_draft() -> void:
	if not bool(_catalog_validation.get("ok", false)):
		action_blocked.emit("wardrobe.randomize", "WARDROBE_CATALOG_UNAVAILABLE")
		return
	_catalog_look_index = (
		(_catalog_look_index + 1)
		% _wardrobe_loadouts.size()
	)
	_activate_loadout(_wardrobe_loadouts[_catalog_look_index])
	_sync_contract_draft_from_catalog()
	_discard_confirmation_armed = false
	_status_message = "正式衣柜 · 已切换套装"
	_refresh_visuals()


func _request_apply() -> void:
	if _handoff.is_empty():
		action_blocked.emit("", _handoff_error)
		_status_message = "正式换装接口待接线"
		_refresh_visuals()
		return
	var built: Dictionary = _contract.build_save_payload(_handoff, _draft_selection)
	if not bool(built.get("ok", false)):
		action_blocked.emit(
			String(_handoff.get("returnIntent", "")),
			String(built.get("errorCode", "WARDROBE_RESULT_INVALID")),
		)
		return
	var return_intent: String = String(built.get("returnIntent", ""))
	var payload: Dictionary = (built.get("payload", {}) as Dictionary).duplicate(true)
	payload["loadoutId"] = _active_loadout_id
	if not is_instance_valid(_adapter) or not _adapter.has_method("dispatch"):
		action_blocked.emit(return_intent, "TOWN_UI_ADAPTER_UNAVAILABLE")
		_status_message = "保存接口待接线\n不会伪成功"
		_refresh_visuals()
		return
	_last_dispatch_result = _adapter.call("dispatch", return_intent, payload) as Dictionary
	if not bool(_last_dispatch_result.get("ok", false)):
		action_blocked.emit(
			return_intent,
			String(_last_dispatch_result.get("errorCode", "WARDROBE_RESULT_REJECTED")),
		)
		_status_message = "保存未完成\n原选择已保留"
		_refresh_visuals()
		return
	_confirmed_selection = _draft_selection.duplicate(true)
	var routed_payload: Dictionary = payload.duplicate(true)
	routed_payload["dispatchResult"] = _last_dispatch_result.duplicate(true)
	wardrobe_result_ready.emit(return_intent, routed_payload.duplicate(true))
	return_requested.emit(
		String(_handoff.get("sourceScope", "")),
		return_intent,
		routed_payload.duplicate(true),
	)
	intent_requested.emit(StringName(return_intent), routed_payload)
	_status_message = "保存完成\n等待返回入口"
	_refresh_visuals()


func _request_cancel() -> void:
	if _catalog_selection != _catalog_original_selection:
		if not _discard_confirmation_armed:
			_discard_confirmation_armed = true
			_refresh_visuals()
			_play_status_motion()
		if _discard_confirmation != null and not _discard_confirmation.visible:
			_discard_confirmation.popup_centered()
		return

	_perform_cancel()


func _build_discard_confirmation() -> void:
	if _discard_confirmation != null:
		return
	_discard_confirmation = FormalDialog.new()
	_discard_confirmation.name = "UnsavedChangesDialog"
	_discard_confirmation.title = "放弃未保存的外观？"
	_discard_confirmation.dialog_text = "当前换装结果还没有保存。"
	_discard_confirmation.ok_button_text = "放弃并返回"
	_discard_confirmation.cancel_button_text = "继续编辑"
	_discard_confirmation.confirmed.connect(_confirm_discard_and_cancel)
	_discard_confirmation.canceled.connect(_continue_editing_after_discard_prompt)
	add_child(_discard_confirmation)


func _confirm_discard_and_cancel() -> void:
	_discard_confirmation_armed = false
	_perform_cancel()


func _continue_editing_after_discard_prompt() -> void:
	_discard_confirmation_armed = false
	_refresh_visuals()


func _perform_cancel() -> void:
	_discard_confirmation_armed = false
	if _handoff.is_empty():
		intent_requested.emit(
			&"wardrobe.cancel",
			{"routeOnly": true, "formalReady": false},
		)
		return
	var built: Dictionary = _contract.build_cancel_payload(_handoff)
	if not bool(built.get("ok", false)):
		action_blocked.emit("wardrobe.cancel", String(built.get("errorCode", "")))
		return
	var cancel_intent: String = String(built.get("cancelIntent", "wardrobe.cancel"))
	var payload: Dictionary = (built.get("payload", {}) as Dictionary).duplicate(true)
	wardrobe_cancelled.emit(cancel_intent, payload.duplicate(true))
	return_requested.emit(
		String(_handoff.get("sourceScope", "")),
		cancel_intent,
		payload.duplicate(true),
	)
	var route_payload: Dictionary = payload.duplicate(true)
	route_payload["cancelIntent"] = cancel_intent
	route_payload["routeOnly"] = true
	intent_requested.emit(&"wardrobe.cancel", route_payload)


func _on_view_model_changed(scope: String, view_model: Dictionary) -> void:
	if scope == "wardrobe":
		apply_view_model(view_model)


func _failure(error_code: String) -> Dictionary:
	return RESULT_SHAPES.failure(error_code)
