class_name CustomResidentCreatorScreen
extends Control


signal intent_requested(intent: String, payload: Dictionary)
signal action_blocked(intent: String, reason: String)


const UI_SIGNALS := preload(
	"res://ui/common/AiTownUiSignals.gd"
)
const UiNodeRetirement := preload("res://ui/common/AiTownUiNodeRetirement.gd")
const UiViewModel := preload("res://ui/common/AiTownUiViewModel.gd")
const PageTheme := preload(
	"res://ui/custom_resident_creator/CustomResidentCreatorTheme.gd"
)
const PaperDollScript := preload(
	"res://characters/paper_doll/PaperDoll64Sprite.gd"
)
const FormalDialog := preload(
	"res://ui/common/formal_dialog/FormalConfirmationDialog.gd"
)
const POINTER_INPUT := preload("res://ui/mobile/PointerInput.gd")
const MOBILE_UI_PROFILE := preload("res://ui/mobile/MobileUiProfile.gd")
const SCOPE := "custom_resident_creator"
const REFERENCE_SIZE := Vector2(1920, 1080)
const SOURCE_SIZE := Vector2(1672, 941)
const TOUCH_TARGET_MIN := 48.0
const STRUCTURAL_SHELL_PATH := (
	"res://assets/ui/custom_resident_creator/runtime/shell/"
	+ "custom_resident_creator_structural_shell.png"
)
const CONTROL_ASSET_ROOT := (
	"res://assets/ui/custom_resident_creator/runtime/controls/v4/"
)
const CONTROL_SIZE_CONTRACT_PATH := CONTROL_ASSET_ROOT + "control_size_contract.json"
const RUNTIME_ASSET_MANIFEST_PATH := (
	"res://assets/ui/custom_resident_creator/runtime/"
	+ "custom_resident_creator_v13_asset_manifest.json"
)
const DROPDOWN_POPUP_ASSET_ROOT := CONTROL_ASSET_ROOT + "dropdown_popup/"
const DROPDOWN_POPUP_SIZE := Vector2(606, 216)
const DROPDOWN_POPUP_ITEM_SIZE := Vector2(542, 48)
const DROPDOWN_POPUP_VISIBLE_ITEMS := 4
const COMMON_SCROLLBAR_ROOT := "res://assets/ui/common/scrollbar/wood_v1/"
const COMMON_SCROLLBAR_TRACK_PATH := (
	COMMON_SCROLLBAR_ROOT
	+ "variants/dropdown_short/scrollbar_track_wood_v1_dropdown_short.png"
)
const COMMON_SCROLLBAR_THUMB_PATH := (
	COMMON_SCROLLBAR_ROOT
	+ "variants/dropdown_short/scrollbar_thumb_wood_v1_dropdown_short.png"
)
const COMMON_SCROLLBAR_MANIFEST_PATH := (
	COMMON_SCROLLBAR_ROOT + "scrollbar_wood_v1_manifest.json"
)
const WARDROBE_PANEL_PATH := (
	"res://assets/ui/common/runtime/paper_wood_panel/"
	+ "paper_wood_panel_master_v1_512.png"
)
const WARDROBE_CARD_FRAME_PATH := (
	"res://assets/ui/custom_resident_creator/runtime/layers/structural_v1/"
	+ "preview_frame.png"
)
const WARDROBE_SLOTS: Array[String] = [
	"hair",
	"top",
	"bottom",
	"shoes",
]
const REQUIRED_DATA_FIELDS: Array[String] = [
	"capabilityMode",
	"source",
	"formalReady",
	"draftId",
	"candidatePoolRevision",
	"draft",
	"resolvedAppearance",
	"options",
	"validation",
]
const REQUIRED_ACTIONS: Array[String] = [
	"updateFields",
	"openWardrobe",
	"applyWardrobeResult",
	"create",
	"cancel",
	"retry",
]

const INK := Color("3f2818")
const MUTED_INK := Color("76583d")
const DISABLED_INK := Color("756652")
const LIGHT_TEXT := Color("fff4dd")
const MOSS := Color("557b2a")
const TERRACOTTA := Color("b94d2d")
const HONEY := Color("e5a84b")
const ERROR_INK := Color("a7352b")
const INFO_INK := Color("4f7790")

@export var navigation_back_available := false
@export_enum("create", "edit_existing", "admission") var presentation_mode := "create"

var _adapter: Object
var _view_model: Dictionary = {}
var _render_data: Dictionary = {}
var _local_text_drafts: Dictionary = {}
var _revision := -1
var _contract_error := ""
var _rendering := false
var _exit_confirmation: FormalDialog

var _viewport_scroll: ScrollContainer
var _mobile_backdrop: TextureRect
var _canvas_host: Control
var _canvas: Control
var _structural_shell: TextureRect
var _back_button: Button
var _name_edit: LineEdit
var _gender_option: Button
var _age_minus_button: Button
var _age_edit: LineEdit
var _age_plus_button: Button
var _desire_edit: TextEdit
var _personality_edit: TextEdit
var _speech_edit: TextEdit
var _open_wardrobe_button: Button
var _appearance_summary_label: Label
var _wardrobe_hint_label: Label
var _occupation_option: Button
var _workplace_option: Button
var _interest_option: Button
var _owned_place_option: Button
var _interest_custom_edit: LineEdit
var _interest_custom_draft := ""
var _dropdown_overlay: Control
var _dropdown_backdrop: Control
var _dropdown_panel: TextureRect
var _dropdown_scroll: ScrollContainer
var _dropdown_list: VBoxContainer
var _dropdown_track: TextureRect
var _dropdown_thumb_hit_target: Control
var _dropdown_thumb: TextureRect
var _dropdown_active_option: Button
var _dropdown_active_field := ""
var _dropdown_dragging := false
var _dropdown_drag_offset := 0.0
var _cancel_button: Button
var _create_button: Button
var _status_frame: TextureRect
var _status_icon: TextureRect
var _status_label: Label
var _status_detail: Label
var _create_decoration: TextureRect
var _appearance_preview: TextureRect
var _paper_doll: Sprite2D
var _appearance_walk_texture: AtlasTexture
var _appearance_walk_sheet_path := ""
var _appearance_walk_frame := 1
var _appearance_walk_timer: Timer
var _complete_set_popup: PopupPanel
var _complete_set_grid: GridContainer
var _complete_set_current_loadout_id := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	theme = PageTheme.create()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if _adapter != null:
		_refresh_from_adapter()
	if _view_model.is_empty():
		return
	_ensure_interface()
	_build_exit_confirmation()
	_render()
	call_deferred("_focus_initial_control")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if is_instance_valid(_complete_set_popup) and _complete_set_popup.visible:
			_complete_set_popup.hide()
			get_viewport().set_input_as_handled()
			return
		if request_back():
			get_viewport().set_input_as_handled()


func request_back() -> bool:
	if _has_unsaved_profile_changes():
		_close_dropdown_popup(false)
		if is_instance_valid(_exit_confirmation):
			_exit_confirmation.popup_centered(Vector2i(620, 260))
		return true
	_request_action("cancel")
	return true


func _has_unsaved_profile_changes() -> bool:
	if bool(_render_data.get("dirty", false)):
		return true
	var draft := _render_data.get("draft", {}) as Dictionary
	if (
		is_instance_valid(_name_edit)
		and _name_edit.text.strip_edges()
			!= String(draft.get("name", "")).strip_edges()
	):
		return true
	if is_instance_valid(_age_edit):
		var parsed_age := int(_age_edit.text)
		if parsed_age != int(draft.get("age", 0)):
			return true
	for field_and_control: Array in [
		["desire", _desire_edit],
		["personality", _personality_edit],
		["speech", _speech_edit],
	]:
		var field := String(field_and_control[0])
		var control := field_and_control[1] as TextEdit
		if (
			is_instance_valid(control)
			and control.text.strip_edges()
				!= String(draft.get(field, "")).strip_edges()
		):
			return true
	return false


func _build_exit_confirmation() -> void:
	if is_instance_valid(_exit_confirmation):
		return
	_exit_confirmation = FormalDialog.new()
	_exit_confirmation.name = "UnsavedProfileConfirmation"
	_exit_confirmation.title = "放弃未保存的修改？"
	_exit_confirmation.dialog_text = "居民资料还没有保存。确定放弃修改并返回居民名单吗？"
	_exit_confirmation.ok_button_text = "放弃并返回"
	_exit_confirmation.cancel_button_text = "继续编辑"
	_exit_confirmation.confirmed.connect(
		func() -> void: _request_action("cancel"),
	)
	add_child(_exit_confirmation)


func bind_town_ui_adapter(adapter: Object) -> void:
	if _adapter == adapter:
		return
	_disconnect_adapter()
	_adapter = adapter
	_view_model.clear()
	_render_data.clear()
	_local_text_drafts.clear()
	_interest_custom_draft = ""
	_revision = -1
	_contract_error = ""
	if _adapter != null and _adapter.has_signal("view_model_changed"):
		_adapter.connect(
			"view_model_changed",
			Callable(self, "_on_adapter_view_model_changed"),
		)
	if is_node_ready():
		_refresh_from_adapter()
		if not _view_model.is_empty():
			_ensure_interface()
			_render()


func bind_adapter(adapter: Object) -> void:
	bind_town_ui_adapter(adapter)


func unbind_town_ui_adapter() -> void:
	_disconnect_adapter()
	_adapter = null
	_view_model.clear()
	_render_data.clear()
	_local_text_drafts.clear()
	_interest_custom_draft = ""
	_revision = -1
	_contract_error = ""
	if is_node_ready():
		visible = false


func apply_view_model(view_model: Dictionary) -> bool:
	var issues := UiViewModel.validate(view_model, "自定义居民创建页")
	if String(view_model.get("scope", "")) != SCOPE:
		issues.append("自定义居民创建页 scope 必须为 custom_resident_creator。")
	if issues.is_empty():
		issues.append_array(_validate_contract(view_model))
	if not issues.is_empty():
		_contract_error = "；".join(issues)
		if is_node_ready():
			_render()
		return false
	var incoming_revision := int(view_model.get("revision", 0))
	if _revision >= 0 and incoming_revision < _revision:
		return false
	_view_model = view_model.duplicate(true)
	_render_data = (view_model.get("data", {}) as Dictionary).duplicate(true)
	_revision = incoming_revision
	_contract_error = ""
	if is_node_ready():
		_ensure_interface()
		_render()
	return true


func _ensure_interface() -> void:
	_build_exit_confirmation()
	if _name_edit != null:
		visible = true
		return
	_build_interface()
	MOBILE_UI_PROFILE.apply_mobile_typography(self, 21, 3, 34)
	_apply_responsive_layout()
	visible = true


func current_view_model() -> Dictionary:
	return _view_model.duplicate(true)


func current_revision() -> int:
	return _revision


func focus_default_control() -> bool:
	if _name_edit == null or not _name_edit.is_visible_in_tree() or not _name_edit.editable:
		return false
	_name_edit.grab_focus()
	return true


func runtime_gate_snapshot() -> Dictionary:
	var touch_targets: Array[Dictionary] = []
	var controls: Array[Control] = [
		_back_button,
		_name_edit,
		_gender_option,
		_age_minus_button,
		_age_edit,
		_age_plus_button,
		_desire_edit,
		_personality_edit,
		_speech_edit,
		_open_wardrobe_button,
		_occupation_option,
		_workplace_option,
		_owned_place_option,
		_interest_option,
		_cancel_button,
		_create_button,
	]
	for control in controls:
		if control == null or not is_instance_valid(control):
			continue
		touch_targets.append({
			"name": String(control.name),
			"rect": _rect_array(control.get_global_rect()),
			"minimumMet": (
				control.size.x >= TOUCH_TARGET_MIN
				and control.size.y >= TOUCH_TARGET_MIN
			),
			"disabled": _control_disabled(control),
		})
	var draft := _render_data.get("draft", {}) as Dictionary
	var selection := draft.get("appearanceSelection", {}) as Dictionary
	var exact_asset_contracts := _exact_asset_contracts()
	var all_exact := true
	for contract_value: Variant in exact_asset_contracts:
		var contract := contract_value as Dictionary
		if not bool(contract.get("exact", false)):
			all_exact = false
	return {
		"scope": String(_view_model.get("scope", "")),
		"status": String(_view_model.get("status", "disabled")),
		"revision": _revision,
		"candidatePoolRevision": int(_render_data.get("candidatePoolRevision", 0)),
		"formalReady": bool(_render_data.get("formalReady", false)),
		"nativeCanvas": [REFERENCE_SIZE.x, REFERENCE_SIZE.y],
		"sourceCanvas": [SOURCE_SIZE.x, SOURCE_SIZE.y],
		"canvasRect": _rect_array(_canvas.get_global_rect()),
		"wholePageScalingUsed": _canvas.scale != Vector2.ONE,
		"approvedStructuralShellPath": STRUCTURAL_SHELL_PATH,
		"structuralShellNodeType": _structural_shell.get_class(),
		"programmaticChromeCount": 0,
		"pageOwnedControlAssetRoot": CONTROL_ASSET_ROOT,
		"runtimeAssetManifestPath": RUNTIME_ASSET_MANIFEST_PATH,
		"controlSizeContractPath": CONTROL_SIZE_CONTRACT_PATH,
		"dropdownPopupImplemented": _dropdown_overlay != null,
		"dropdownPopupVisible": (
			_dropdown_overlay != null and _dropdown_overlay.visible
		),
		"dropdownPopupAssetRoot": DROPDOWN_POPUP_ASSET_ROOT,
		"dropdownPopupVisibleItemCount": DROPDOWN_POPUP_VISIBLE_ITEMS,
		"dropdownPopupIndividualRowFrames": false,
		"commonScrollbarManifestPath": COMMON_SCROLLBAR_MANIFEST_PATH,
		"commonScrollbarAssetId": "ui.common.scrollbar.wood-v1.dropdown-short",
		"dropdownScrollbarNativeRangeBinding": true,
		"dropdownScrollbarTrackClick": true,
		"dropdownScrollbarThumbDrag": true,
		"dropdownScrollbarMouseWheel": true,
		"dropdownScrollbarThumbVisualSize": [32, 72],
		"dropdownScrollbarThumbHitTargetSize": [44, 72],
		"runtimeConsumesSourceSlices": false,
		"runtimeConsumesChromaSource": false,
		"runtimeConsumesAtlas": false,
		"runtimeConsumesCandidateAssets": false,
		"runtimeTextureStretch": false,
		"focusVisualPolicy": "hover_or_selected",
		"ornamentalFocusAssetCount": 0,
		"exactControlAssetSizing": all_exact,
		"controlAssetContracts": exact_asset_contracts,
		"globalDisabledStateVisible": true,
		"genderOptions": ["女", "男"],
		"wardrobeEntryPresent": _open_wardrobe_button != null,
		"embeddedWardrobeControlCount": 0,
		"wardrobeRuntimeSlotOrder": WARDROBE_SLOTS.duplicate(),
		"wardrobeSelection": selection.duplicate(true),
		"previewLoadoutId": String(
			(_render_data.get("resolvedAppearance", {}) as Dictionary).get("loadoutId", "")
		),
		"contractError": _contract_error,
		"runtimeMockLoaded": false,
		"directWorldOrAgentRead": false,
		"touchTargets": touch_targets,
	}


func _validate_contract(view_model: Dictionary) -> PackedStringArray:
	var issues := PackedStringArray()
	var data := view_model.get("data", {}) as Dictionary
	for field in REQUIRED_DATA_FIELDS:
		if not data.has(field):
			issues.append("custom_resident_creator.data 缺少 %s" % field)
	if not issues.is_empty():
		return issues
	if not data.get("formalReady") is bool:
		issues.append("custom_resident_creator.data.formalReady 必须为 bool")
	var draft_value: Variant = data.get("draft")
	if not draft_value is Dictionary:
		issues.append("custom_resident_creator.data.draft 必须为 Dictionary")
	else:
		var draft := draft_value as Dictionary
		var required_draft_fields := [
			"name", "gender", "age", "appearanceSelection", "desire",
			"personality", "speech", "interests", "customInterests",
			"occupationId", "workplaceId",
		]
		if _is_edit_existing():
			required_draft_fields.append("ownedPlaceId")
		for field in required_draft_fields:
			if not draft.has(field):
				issues.append("custom_resident_creator.data.draft 缺少 %s" % field)
	var options_value: Variant = data.get("options")
	if not options_value is Dictionary:
		issues.append("custom_resident_creator.data.options 必须为 Dictionary")
	else:
		var options := options_value as Dictionary
		var genders := options.get("genders", []) as Array
		var gender_ids: Array[String] = []
		for value: Variant in genders:
			if value is Dictionary:
				gender_ids.append(String((value as Dictionary).get("id", "")))
		gender_ids.sort()
		if gender_ids != ["女", "男"]:
			issues.append("自定义居民性别选项必须且只能为男/女")
		var wardrobe := options.get("wardrobe", {}) as Dictionary
		if String(wardrobe.get("entryMode", "")) != "route_to_formal_wardrobe":
			issues.append("自定义居民页必须通过入口打开完整衣柜")
		if String(wardrobe.get("runtimeMode", "")) != "resident_2d_rig_v1":
			issues.append("自定义居民外观必须使用冻结居民衣柜资产")
		if wardrobe.get("slotOrder", []) != WARDROBE_SLOTS:
			issues.append("衣柜槽位必须为 hair/top/bottom/shoes")
		if wardrobe.has("slotVariants"):
			issues.append("自定义居民页不得暴露重复的衣柜槽位控件")
		if _is_edit_existing() and not options.has("ownedPlaces"):
			issues.append("居民编辑页缺少住所资料")
	var actions := view_model.get("actions", {}) as Dictionary
	var required_actions := REQUIRED_ACTIONS.duplicate()
	if _is_edit_existing():
		required_actions.erase("create")
		required_actions.append("saveExisting")
	for action_key in required_actions:
		var action_value: Variant = actions.get(action_key)
		if not action_value is Dictionary:
			issues.append("custom_resident_creator.actions 缺少 %s" % action_key)
			continue
		var action := action_value as Dictionary
		if not action.has("intent") or not action.has("enabled") or not action.has("disabledReason"):
			issues.append("custom_resident_creator.actions.%s 不完整" % action_key)
	return issues


func _build_interface() -> void:
	if MOBILE_UI_PROFILE.is_mobile_runtime():
		_mobile_backdrop = TextureRect.new()
		_mobile_backdrop.name = "CustomResidentCreatorMobileBackdrop"
		_mobile_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_mobile_backdrop.texture = load(STRUCTURAL_SHELL_PATH) as Texture2D
		_mobile_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_mobile_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_mobile_backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_mobile_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_mobile_backdrop)
	_viewport_scroll = ScrollContainer.new()
	_viewport_scroll.name = "ViewportScroll"
	_viewport_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewport_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_viewport_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(_viewport_scroll)

	_canvas_host = Control.new()
	_canvas_host.name = "CanvasHost"
	_canvas_host.custom_minimum_size = REFERENCE_SIZE
	_canvas_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_viewport_scroll.add_child(_canvas_host)

	_canvas = Control.new()
	_canvas.name = "CustomResidentCreatorCanvas"
	_canvas.size = REFERENCE_SIZE
	_canvas_host.add_child(_canvas)

	_structural_shell = TextureRect.new()
	_structural_shell.name = "ApprovedStructuralShell"
	_structural_shell.position = Vector2.ZERO
	_structural_shell.size = REFERENCE_SIZE
	_structural_shell.texture = load(STRUCTURAL_SHELL_PATH) as Texture2D
	_structural_shell.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_structural_shell.stretch_mode = TextureRect.STRETCH_SCALE
	_structural_shell.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_structural_shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_structural_shell)

	_build_header()
	_build_appearance_preview()
	_build_identity()
	_build_character_core()
	_build_work()
	_build_footer()
	_build_dropdown_overlay()
	_build_complete_set_popup()


func _build_header() -> void:
	_back_button = _state_button(
		"BackButton",
		"← 返回",
		_source_rect(215, 140, 160, 64),
		"back",
	)
	_back_button.add_theme_font_size_override("font_size", 25)
	_back_button.pressed.connect(request_back)
	_canvas.add_child(_back_button)
	_canvas.add_child(_label(
		"PageTitle",
		"修改居民资料" if _is_edit_existing() else "创建自定义居民",
		_source_rect(560, 130, 555, 54),
		43,
		INK,
		HORIZONTAL_ALIGNMENT_CENTER,
	))
	_canvas.add_child(_label(
		"PageSubtitle",
			(
				"读取当前居民资料；保存后返回居民总览"
				if _is_edit_existing()
				else "创建一名新的候选居民，完成后返回居民名单"
			),
		_source_rect(510, 178, 650, 32),
		21,
		MUTED_INK,
		HORIZONTAL_ALIGNMENT_CENTER,
	))


func _build_complete_set_popup() -> void:
	if is_instance_valid(_complete_set_popup):
		return
	_complete_set_popup = PopupPanel.new()
	_complete_set_popup.name = "CompleteSetWardrobePopup"
	_complete_set_popup.theme = theme
	var transparent_panel := StyleBoxFlat.new()
	transparent_panel.bg_color = Color.TRANSPARENT
	transparent_panel.border_width_left = 0
	transparent_panel.border_width_top = 0
	transparent_panel.border_width_right = 0
	transparent_panel.border_width_bottom = 0
	_complete_set_popup.add_theme_stylebox_override("panel", transparent_panel)
	add_child(_complete_set_popup)
	var panel_background := TextureRect.new()
	panel_background.name = "WardrobeAssetPanel"
	panel_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel_background.texture = load(WARDROBE_PANEL_PATH) as Texture2D
	panel_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	panel_background.stretch_mode = TextureRect.STRETCH_SCALE
	panel_background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	panel_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_complete_set_popup.add_child(panel_background)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 72)
	margin.add_theme_constant_override("margin_top", 55)
	margin.add_theme_constant_override("margin_right", 72)
	margin.add_theme_constant_override("margin_bottom", 52)
	_complete_set_popup.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var title := Label.new()
	title.text = "选择整套服装"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", INK)
	column.add_child(title)
	var hint := Label.new()
	hint.text = "头发、上装、下装和鞋子按完整套装一起替换"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", MUTED_INK)
	column.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(720, 455)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_complete_set_grid = GridContainer.new()
	_complete_set_grid.columns = 3
	_complete_set_grid.add_theme_constant_override("h_separation", 10)
	_complete_set_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_complete_set_grid)
	var close_button := Button.new()
	close_button.text = "返回资料编辑"
	close_button.custom_minimum_size = Vector2(260, 62)
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_button.add_theme_font_size_override("font_size", 22)
	_apply_button_family(close_button, "wardrobe")
	close_button.pressed.connect(func() -> void: _complete_set_popup.hide())
	column.add_child(close_button)


func open_complete_set_wardrobe(handoff: Dictionary) -> bool:
	var catalog_path := String(handoff.get("catalogPath", "")).strip_edges()
	if (
		catalog_path.is_empty()
		or not FileAccess.file_exists(catalog_path)
		or not is_instance_valid(_complete_set_popup)
		or not is_instance_valid(_complete_set_grid)
	):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(catalog_path))
	if not parsed is Dictionary:
		return false
	var loadouts_value: Variant = (parsed as Dictionary).get("loadouts", [])
	if not loadouts_value is Array:
		return false
	_complete_set_current_loadout_id = String(handoff.get("loadoutId", ""))
	for child in _complete_set_grid.get_children():
		child.queue_free()
	for loadout_value: Variant in loadouts_value as Array:
		if loadout_value is Dictionary:
			_add_complete_set_card((loadout_value as Dictionary).duplicate(true))
	_complete_set_popup.popup_centered(Vector2i(864, 680))
	return true


func _add_complete_set_card(loadout: Dictionary) -> void:
	var preview_button := Button.new()
	preview_button.name = "CompleteSetCard_%s" % String(loadout.get("id", ""))
	preview_button.custom_minimum_size = Vector2(233, 220)
	preview_button.tooltip_text = "选择这套形象"
	preview_button.focus_mode = Control.FOCUS_ALL
	preview_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var portrait_path := String(loadout.get("portraitPath", ""))
	if ResourceLoader.exists(portrait_path, "Texture2D"):
		preview_button.icon = load(portrait_path) as Texture2D
		preview_button.expand_icon = true
	var frame_texture := load(WARDROBE_CARD_FRAME_PATH) as Texture2D
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var frame_style := _asset_style(frame_texture, 12.0)
		frame_style.content_margin_top = 12
		frame_style.content_margin_bottom = 12
		preview_button.add_theme_stylebox_override(state, frame_style)
	var selected := (
		String(loadout.get("id", "")) == _complete_set_current_loadout_id
	)
	preview_button.modulate = Color("fff0bd") if selected else Color.WHITE
	preview_button.pressed.connect(
		_select_complete_set.bind(loadout.duplicate(true)),
	)
	_complete_set_grid.add_child(preview_button)
	if selected:
		var selected_badge := Label.new()
		selected_badge.name = "SelectedBadge"
		selected_badge.text = "✓"
		selected_badge.position = Vector2(186, 10)
		selected_badge.size = Vector2(34, 34)
		selected_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		selected_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		selected_badge.add_theme_font_size_override("font_size", 28)
		selected_badge.add_theme_color_override("font_color", MOSS)
		selected_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview_button.add_child(selected_badge)


func _select_complete_set(loadout: Dictionary) -> void:
	var head_id := String(loadout.get("headId", ""))
	var outfit_id := String(loadout.get("outfitId", ""))
	if head_id.is_empty() or outfit_id.is_empty():
		return
	_complete_set_popup.hide()
	_request_action("applyWardrobeResult", {
		"selection": {
			"hair": head_id,
			"top": outfit_id,
			"bottom": outfit_id,
			"shoes": outfit_id,
		},
		"loadoutId": String(loadout.get("id", "")),
	})


func _build_appearance_preview() -> void:
	_canvas.add_child(_section_title("外观预览", _source_rect(305, 219, 276, 38)))
	var preview_clip := Control.new()
	preview_clip.name = "FormalPaperDollPreviewClip"
	var preview_rect := _source_rect(226, 255, 448, 365)
	preview_clip.position = preview_rect.position
	preview_clip.size = preview_rect.size
	preview_clip.clip_contents = true
	preview_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(preview_clip)
	_appearance_preview = TextureRect.new()
	_appearance_preview.name = "ResidentWardrobeV1Preview"
	_appearance_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_appearance_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_appearance_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_appearance_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_appearance_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_clip.add_child(_appearance_preview)
	var anchor := Node2D.new()
	anchor.name = "LegacyPaperDollAnchor"
	anchor.position = _source_point(226, 268)
	preview_clip.add_child(anchor)
	_paper_doll = PaperDollScript.new() as Sprite2D
	_paper_doll.name = "LegacyPaperDoll64Preview"
	_paper_doll.scale = Vector2(2.6, 2.6)
	anchor.add_child(_paper_doll)
	_appearance_walk_timer = Timer.new()
	_appearance_walk_timer.name = "AppearanceWalkTimer"
	_appearance_walk_timer.wait_time = 0.16
	_appearance_walk_timer.timeout.connect(_advance_appearance_walk_frame)
	preview_clip.add_child(_appearance_walk_timer)
	_appearance_walk_timer.start()

	_canvas.add_child(_label(
		"AppearanceSummaryCaption",
		"当前外观",
		_source_rect(304, 632, 120, 36),
		20,
		INK,
		HORIZONTAL_ALIGNMENT_LEFT,
	))
	_appearance_summary_label = _label(
		"AppearanceSummaryLabel",
		"自定义搭配",
		_source_rect(430, 632, 170, 36),
		20,
		INK,
		HORIZONTAL_ALIGNMENT_LEFT,
	)
	_canvas.add_child(_appearance_summary_label)
	_open_wardrobe_button = _state_button(
		"OpenWardrobeButton",
		"打开衣柜",
		_source_rect(303, 672, 285, 78),
		"wardrobe",
	)
	_open_wardrobe_button.add_theme_font_size_override("font_size", 30)
	_open_wardrobe_button.pressed.connect(
		func() -> void: _request_action("openWardrobe")
	)
	_canvas.add_child(_open_wardrobe_button)
	_wardrobe_hint_label = _label(
		"WardrobeHint",
		"在完整衣柜中调整外观",
		_source_rect(284, 748, 324, 35),
		18,
		MUTED_INK,
		HORIZONTAL_ALIGNMENT_CENTER,
	)
	_canvas.add_child(_wardrobe_hint_label)


func _build_identity() -> void:
	_canvas.add_child(_section_title("公开身份", _source_rect(747, 220, 260, 38)))
	_canvas.add_child(_field_label("NameLabel", "名字", _source_rect(745, 260, 92, 45)))
	_name_edit = LineEdit.new()
	_name_edit.name = "NameEdit"
	_set_control_rect(_name_edit, _source_rect(850, 261, 528, 43))
	_name_edit.max_length = 24
	_name_edit.placeholder_text = "请输入唯一名字"
	_name_edit.text_submitted.connect(
		func(_value: String) -> void: _commit_text_field("name", _name_edit.text)
	)
	_name_edit.text_changed.connect(_on_line_edit_text_changed.bind("name"))
	_name_edit.focus_exited.connect(
		func() -> void: _commit_text_field("name", _name_edit.text)
	)
	_apply_input_skin(_name_edit, "name_field")
	_canvas.add_child(_name_edit)

	_canvas.add_child(_field_label("GenderLabel", "性别", _source_rect(745, 307, 92, 42)))
	_gender_option = Button.new()
	_gender_option.name = "GenderOption"
	_set_control_rect(_gender_option, _source_rect(850, 307, 528, 42))
	_gender_option.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_gender_option.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_gender_option.toggle_mode = true
	_apply_dropdown_skin(_gender_option)
	_gender_option.pressed.connect(
		_toggle_dropdown_popup.bind("gender", _gender_option),
	)
	_canvas.add_child(_gender_option)

	_canvas.add_child(_field_label("AgeLabel", "年龄", _source_rect(745, 350, 92, 44)))
	_age_minus_button = _state_button(
		"AgeMinusButton", "−", _source_rect(850, 350, 48, 44), "age_minus"
	)
	_age_edit = LineEdit.new()
	_age_edit.name = "AgeEdit"
	_set_control_rect(_age_edit, _source_rect(898, 350, 105, 44))
	_age_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_age_edit.max_length = 3
	_age_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_age_edit.text_changed.connect(_on_line_edit_text_changed.bind("age"))
	_age_edit.text_submitted.connect(func(_value: String) -> void: _commit_age_text())
	_age_edit.focus_exited.connect(_commit_age_text)
	_apply_input_skin(_age_edit, "age_value")
	_age_plus_button = _state_button(
		"AgePlusButton", "+", _source_rect(1003, 350, 48, 44), "age_plus"
	)
	_age_minus_button.pressed.connect(_step_age.bind(-1))
	_age_plus_button.pressed.connect(_step_age.bind(1))
	_canvas.add_child(_age_minus_button)
	_canvas.add_child(_age_edit)
	_canvas.add_child(_age_plus_button)
	_canvas.add_child(_label(
		"AgeUnit",
		"岁",
		_source_rect(1058, 350, 55, 44),
		19,
		INK,
		HORIZONTAL_ALIGNMENT_LEFT,
	))


func _build_character_core() -> void:
	_canvas.add_child(_section_title("人物内核", _source_rect(747, 404, 260, 38)))
	var rows := [
		["desire", "核心欲望", "这个人最想实现什么？", 447.0],
		["personality", "性格", "用一句话描述性格与矛盾", 503.0],
		["speech", "说话方式", "描述语气、节奏与表达习惯", 559.0],
	]
	for row_value: Variant in rows:
		var row := row_value as Array
		var field := String(row[0])
		var y := float(row[3])
		_canvas.add_child(_field_label(
			"CoreLabel_%s" % field,
			String(row[1]),
			_source_rect(745, y, 96, 48),
		))
		var edit := TextEdit.new()
		edit.name = "CoreEdit_%s" % field
		_set_control_rect(edit, _source_rect(850, y, 528, 48))
		edit.placeholder_text = String(row[2])
		edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		edit.scroll_fit_content_height = false
		edit.text_changed.connect(_on_text_edit_text_changed.bind(field, edit))
		edit.focus_exited.connect(_commit_core_field.bind(field, edit))
		_apply_input_skin(edit, "core_field")
		_canvas.add_child(edit)
		match field:
			"desire":
				_desire_edit = edit
			"personality":
				_personality_edit = edit
			"speech":
				_speech_edit = edit


func _build_work() -> void:
	_canvas.add_child(_section_title(
		"在小镇的资料" if _is_edit_existing() else "在小镇的工作",
		_source_rect(747, 623, 310, 38),
	))
	if _is_edit_existing():
		_canvas.add_child(_field_label(
			"OwnedPlaceLabel",
			"住所",
			_source_rect(1082, 623, 64, 38),
		))
		_owned_place_option = Button.new()
		_owned_place_option.name = "OwnedPlaceOption"
		_set_control_rect(
			_owned_place_option,
			_source_rect(1140, 623, 238, 38),
		)
		_owned_place_option.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_owned_place_option.text_overrun_behavior = (
			TextServer.OVERRUN_TRIM_ELLIPSIS
		)
		_owned_place_option.toggle_mode = true
		_apply_dropdown_skin(_owned_place_option)
		_owned_place_option.pressed.connect(
			_toggle_dropdown_popup.bind("ownedPlaceId", _owned_place_option),
		)
		_owned_place_option.tooltip_text = "可以选择本局可用住宅；保存后更新居民住所。"
		_canvas.add_child(_owned_place_option)
	var rows := [
		["OccupationOption", "职业", "occupationId", 659.0],
		["WorkplaceOption", "职业地点", "workplaceId", 701.0],
		["InterestOption", "兴趣爱好", "interests", 743.0],
	]
	for row_value: Variant in rows:
		var row := row_value as Array
		var y := float(row[3])
		_canvas.add_child(_field_label(
			"%sLabel" % String(row[0]),
			String(row[1]),
			_source_rect(745, y, 96, 40),
		))
		var option := Button.new()
		option.name = String(row[0])
		_set_control_rect(option, _source_rect(850, y, 528, 42))
		option.alignment = HORIZONTAL_ALIGNMENT_LEFT
		option.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		option.toggle_mode = true
		_apply_dropdown_skin(option)
		_canvas.add_child(option)
		var field := String(row[2])
		option.pressed.connect(_toggle_dropdown_popup.bind(field, option))
		match field:
			"occupationId":
				_occupation_option = option
			"workplaceId":
				_workplace_option = option
				option.tooltip_text = (
					"更换职业会先填入默认职业地点，也可以在这里单独选择。"
				)
			"interests":
				_interest_option = option
				option.tooltip_text = (
					"可从目录多选，也可以添加自定义兴趣；合计最多三项。"
				)


func _build_dropdown_overlay() -> void:
	_dropdown_overlay = Control.new()
	_dropdown_overlay.name = "CustomResidentDropdownOverlay"
	_dropdown_overlay.position = Vector2.ZERO
	_dropdown_overlay.size = REFERENCE_SIZE
	_dropdown_overlay.z_index = 90
	_dropdown_overlay.visible = false
	_dropdown_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_dropdown_overlay)

	_dropdown_backdrop = Control.new()
	_dropdown_backdrop.name = "DropdownDismissBackdrop"
	_dropdown_backdrop.position = Vector2.ZERO
	_dropdown_backdrop.size = REFERENCE_SIZE
	_dropdown_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_dropdown_backdrop.gui_input.connect(_on_dropdown_backdrop_input)
	_dropdown_overlay.add_child(_dropdown_backdrop)

	_dropdown_panel = TextureRect.new()
	_dropdown_panel.name = "DropdownPopupPanel"
	_dropdown_panel.size = DROPDOWN_POPUP_SIZE
	_dropdown_panel.texture = _dropdown_popup_texture("panel", "normal")
	_dropdown_panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_dropdown_panel.stretch_mode = TextureRect.STRETCH_SCALE
	_dropdown_panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_dropdown_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_dropdown_overlay.add_child(_dropdown_panel)

	_dropdown_scroll = ScrollContainer.new()
	_dropdown_scroll.name = "DropdownOptionScroll"
	_dropdown_scroll.position = Vector2(12, 12)
	_dropdown_scroll.size = Vector2(
		DROPDOWN_POPUP_ITEM_SIZE.x,
		DROPDOWN_POPUP_ITEM_SIZE.y * DROPDOWN_POPUP_VISIBLE_ITEMS,
	)
	_dropdown_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_dropdown_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_dropdown_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_dropdown_panel.add_child(_dropdown_scroll)

	_dropdown_list = VBoxContainer.new()
	_dropdown_list.name = "DropdownOptionList"
	_dropdown_list.custom_minimum_size.x = DROPDOWN_POPUP_ITEM_SIZE.x
	_dropdown_list.add_theme_constant_override("separation", 0)
	_dropdown_scroll.add_child(_dropdown_list)

	_dropdown_track = TextureRect.new()
	_dropdown_track.name = "CommonWoodScrollbarTrack"
	_dropdown_track.position = Vector2(570, 16)
	_dropdown_track.size = Vector2(24, 184)
	_dropdown_track.texture = load(COMMON_SCROLLBAR_TRACK_PATH) as Texture2D
	_dropdown_track.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_dropdown_track.stretch_mode = TextureRect.STRETCH_SCALE
	_dropdown_track.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_dropdown_track.mouse_filter = Control.MOUSE_FILTER_STOP
	_dropdown_track.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_dropdown_track.gui_input.connect(_on_dropdown_scroll_input.bind(false))
	_dropdown_panel.add_child(_dropdown_track)

	_dropdown_thumb_hit_target = Control.new()
	_dropdown_thumb_hit_target.name = "CommonWoodScrollbarThumbHitTarget"
	_dropdown_thumb_hit_target.position = Vector2(560, 16)
	_dropdown_thumb_hit_target.size = Vector2(44, 72)
	_dropdown_thumb_hit_target.mouse_filter = Control.MOUSE_FILTER_STOP
	_dropdown_thumb_hit_target.mouse_default_cursor_shape = Control.CURSOR_DRAG
	_dropdown_thumb_hit_target.gui_input.connect(_on_dropdown_scroll_input.bind(true))
	_dropdown_panel.add_child(_dropdown_thumb_hit_target)

	_dropdown_thumb = TextureRect.new()
	_dropdown_thumb.name = "CommonWoodScrollbarThumb"
	_dropdown_thumb.position = Vector2(6, 0)
	_dropdown_thumb.size = Vector2(32, 72)
	_dropdown_thumb.texture = load(COMMON_SCROLLBAR_THUMB_PATH) as Texture2D
	_dropdown_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_dropdown_thumb.stretch_mode = TextureRect.STRETCH_SCALE
	_dropdown_thumb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_dropdown_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dropdown_thumb_hit_target.add_child(_dropdown_thumb)

	var native_scrollbar := _dropdown_scroll.get_v_scroll_bar()
	native_scrollbar.modulate.a = 0.0
	native_scrollbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	native_scrollbar.value_changed.connect(_refresh_dropdown_scrollbar.unbind(1))


func _build_footer() -> void:
	_cancel_button = _state_button(
		"CancelButton", "取消", _source_rect(240, 818, 214, 60), "cancel"
	)
	_cancel_button.add_theme_font_size_override("font_size", 28)
	_cancel_button.pressed.connect(request_back)
	_canvas.add_child(_cancel_button)

	var status_rect := _source_rect(467, 818, 610, 60)
	_status_frame = TextureRect.new()
	_status_frame.name = "PageOwnedValidationStatus"
	_status_frame.position = status_rect.position
	_status_frame.size = status_rect.size
	_status_frame.texture = _control_texture("status", "disabled")
	_status_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_status_frame.stretch_mode = TextureRect.STRETCH_SCALE
	_status_frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_status_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_status_frame)
	_status_icon = TextureRect.new()
	_status_icon.name = "SemanticStatusIcon"
	_status_icon.position = _source_point(195, 13)
	_status_icon.size = _source_point(33, 33)
	_status_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_status_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_status_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_status_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_frame.add_child(_status_icon)
	_status_label = _label(
		"StatusLabel",
		"等待正式接口",
		Rect2(_source_point(242, 10), _source_point(330, 40)),
		20,
		LIGHT_TEXT,
		HORIZONTAL_ALIGNMENT_LEFT,
	)
	_status_frame.add_child(_status_label)
	_status_detail = _label(
		"StatusDetail",
		"填写完成后即可创建",
		Rect2(_source_point(72, 37), Vector2(status_rect.size.x - _source_point(90, 0).x, _source_point(0, 31).y)),
		16,
		MUTED_INK,
		HORIZONTAL_ALIGNMENT_LEFT,
	)
	_status_detail.visible = false
	_status_frame.add_child(_status_detail)

	_create_button = _primary_button(
		"CreateButton",
		_submit_button_copy(),
		_source_rect(1093, 818, 341, 60),
	)
	_create_button.pressed.connect(_on_create_button_pressed)
	_canvas.add_child(_create_button)
	_create_decoration = TextureRect.new()
	_create_decoration.name = "CreateButtonReferenceDecoration"
	_create_decoration.position = _source_point(286, 6)
	_create_decoration.size = _source_point(48, 48)
	_create_decoration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_create_decoration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_create_decoration.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_create_decoration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_create_decoration.texture = _control_texture("create_decoration", "normal")
	_create_button.add_child(_create_decoration)


func _render() -> void:
	if _name_edit == null:
		return
	_rendering = true
	var available := (
		_contract_error.is_empty()
		and bool(_render_data.get("formalReady", false))
	)
	var draft := _render_data.get("draft", {}) as Dictionary
	_reconcile_local_text_drafts(draft)
	_set_line_edit_text_preserving_caret(
		_name_edit,
		_local_or_confirmed_text("name", String(draft.get("name", ""))),
	)
	_set_line_edit_text_preserving_caret(
		_age_edit,
		_local_or_confirmed_text("age", str(int(draft.get("age", 27)))),
	)
	_set_text_edit_text_preserving_caret(
		_desire_edit,
		_local_or_confirmed_text("desire", String(draft.get("desire", ""))),
	)
	_set_text_edit_text_preserving_caret(
		_personality_edit,
		_local_or_confirmed_text("personality", String(draft.get("personality", ""))),
	)
	_set_text_edit_text_preserving_caret(
		_speech_edit,
		_local_or_confirmed_text("speech", String(draft.get("speech", ""))),
	)
	var options := _render_data.get("options", {}) as Dictionary
	_populate_option(
		_gender_option,
		options.get("genders", []) as Array,
		String(draft.get("gender", "")),
	)
	_populate_option(
		_occupation_option,
		options.get("occupations", []) as Array,
		String(draft.get("occupationId", "")),
	)
	_populate_option(
		_workplace_option,
		options.get("workplaces", []) as Array,
		String(draft.get("workplaceId", "")),
	)
	_populate_interest_option(
		options.get("interests", []) as Array,
		draft.get("interests", []) as Array,
		draft.get("customInterests", []) as Array,
		int(options.get("maxInterests", 3)),
	)
	if _owned_place_option != null:
		_populate_option(
			_owned_place_option,
			options.get("ownedPlaces", []) as Array,
			String(draft.get("ownedPlaceId", "")),
		)
	_render_preview()
	_render_validation()
	_render_actions(available)
	_rendering = false


func _on_line_edit_text_changed(value: String, field: String) -> void:
	if _rendering:
		return
	_local_text_drafts[field] = value


func _on_text_edit_text_changed(field: String, edit: TextEdit) -> void:
	if _rendering or not is_instance_valid(edit):
		return
	_local_text_drafts[field] = edit.text


func _reconcile_local_text_drafts(draft: Dictionary) -> void:
	for field_value: Variant in _local_text_drafts.keys():
		var field := String(field_value)
		var local_value := String(_local_text_drafts.get(field, ""))
		var confirmed_value := (
			str(int(draft.get("age", 27)))
			if field == "age"
			else String(draft.get(field, ""))
		)
		if (
			local_value == confirmed_value
			or (field != "age" and local_value.strip_edges() == confirmed_value)
		):
			_local_text_drafts.erase(field)


func _local_or_confirmed_text(field: String, confirmed_value: String) -> String:
	return String(_local_text_drafts.get(field, confirmed_value))


func _set_line_edit_text_preserving_caret(edit: LineEdit, value: String) -> void:
	if edit.text == value:
		return
	var caret_column := edit.get_caret_column()
	var had_selection := edit.has_selection()
	var selection_from := edit.get_selection_from_column() if had_selection else 0
	var selection_to := edit.get_selection_to_column() if had_selection else 0
	edit.text = value
	edit.set_caret_column(clampi(caret_column, 0, value.length()))
	if had_selection:
		edit.select(
			clampi(selection_from, 0, value.length()),
			clampi(selection_to, 0, value.length()),
		)


func _set_text_edit_text_preserving_caret(edit: TextEdit, value: String) -> void:
	if edit.text == value:
		return
	var caret_line := edit.get_caret_line()
	var caret_column := edit.get_caret_column()
	edit.text = value
	var restored_line := clampi(caret_line, 0, maxi(edit.get_line_count() - 1, 0))
	edit.set_caret_line(restored_line)
	edit.set_caret_column(
		mini(caret_column, edit.get_line(restored_line).length()),
	)


func _render_preview() -> void:
	var appearance := _render_data.get("resolvedAppearance", {}) as Dictionary
	var ready := bool(appearance.get("formalReady", false))
	var rest_path := String(appearance.get("restPath", ""))
	var sprite_sheet_path := String(appearance.get("spriteSheetPath", ""))
	var preview_texture: Texture2D = null
	if ready and ResourceLoader.exists(sprite_sheet_path, "Texture2D"):
		preview_texture = _set_appearance_walk_sheet(sprite_sheet_path)
	elif ready and ResourceLoader.exists(rest_path, "Texture2D"):
		_clear_appearance_walk_sheet()
		preview_texture = load(rest_path) as Texture2D
	else:
		_clear_appearance_walk_sheet()
	var new_preview_ready := ready and preview_texture != null
	_appearance_preview.texture = preview_texture
	_appearance_preview.visible = new_preview_ready
	var legacy_preview_ready := false
	if not new_preview_ready and ready and _paper_doll.has_method("set_selection"):
		legacy_preview_ready = bool(
			_paper_doll.call(
				"set_selection",
				appearance.get("selection", {}) as Dictionary,
			),
		)
		_paper_doll.call("set_preview_direction", 0)
		_paper_doll.call("set_preview_frame", 0)
	_paper_doll.visible = legacy_preview_ready
	ready = new_preview_ready or legacy_preview_ready
	_appearance_summary_label.text = String(
		appearance.get("displayName", "当前外观不可用")
	)
	_appearance_summary_label.add_theme_color_override(
		"font_color", INK if ready else ERROR_INK
	)
	_wardrobe_hint_label.text = (
		(
			"当前外观只读，暂不在此调整"
			if _is_edit_existing() and not _action_enabled("openWardrobe")
			else "在完整衣柜中调整外观"
		)
		if ready
		else "正式衣柜图集不可用，暂时无法调整"
	)
	_wardrobe_hint_label.add_theme_color_override(
		"font_color",
		MUTED_INK if ready else ERROR_INK,
	)


func _set_appearance_walk_sheet(path: String) -> Texture2D:
	if path != _appearance_walk_sheet_path or _appearance_walk_texture == null:
		var sheet := load(path) as Texture2D
		if sheet == null or sheet.get_size() != Vector2(1536, 2048):
			_clear_appearance_walk_sheet()
			return null
		_appearance_walk_texture = AtlasTexture.new()
		_appearance_walk_texture.atlas = sheet
		_appearance_walk_sheet_path = path
		_appearance_walk_frame = 1
	_update_appearance_walk_texture()
	return _appearance_walk_texture


func _clear_appearance_walk_sheet() -> void:
	_appearance_walk_texture = null
	_appearance_walk_sheet_path = ""
	_appearance_walk_frame = 1


func _advance_appearance_walk_frame() -> void:
	if (
		not visible
		or _appearance_walk_texture == null
		or (is_instance_valid(_complete_set_popup) and _complete_set_popup.visible)
	):
		return
	_appearance_walk_frame = (_appearance_walk_frame + 1) % 4
	_update_appearance_walk_texture()


func _update_appearance_walk_texture() -> void:
	if _appearance_walk_texture == null:
		return
	_appearance_walk_texture.region = Rect2(
		0.0,
		float(_appearance_walk_frame * 512),
		512.0,
		512.0,
	)


func _render_validation() -> void:
	if not _contract_error.is_empty():
		_set_status_visual("error", "正式接口合同错误", _contract_error)
		return
	var operation_status := String(
		(_view_model.get("operation", {}) as Dictionary).get("status", "idle")
	)
	if operation_status == "loading":
		_set_status_visual(
			"loading",
			"正在保存居民资料……" if _is_edit_existing() else "正在创建候选居民……",
			"请稍候，完成后会返回居民管理。" if _is_edit_existing() else "请稍候，完成后会返回居民名单。",
		)
		return
	var error_message := UiViewModel.error_message(_view_model)
	if operation_status in ["rejected", "error"] and not error_message.is_empty():
		_set_status_visual(
			"error",
			"暂时无法保存" if _is_edit_existing() else "暂时无法创建",
			error_message,
		)
		return
	var validation := _render_data.get("validation", {}) as Dictionary
	var validation_status := String(validation.get("status", "unavailable"))
	if validation_status == "valid":
		_set_status_visual(
			"success",
			(
				"资料完整，可以保存"
				if _is_edit_existing()
				else String(validation.get("summaryLabel", "资料完整，可以创建"))
			),
			(
				"保存只更新公开资料，并返回居民管理。"
				if _is_edit_existing()
				else "创建后加入本局候选池，并返回名单聚焦新居民。"
			),
		)
		return
	var issues := validation.get("issues", []) as Array
	var detail := (
		String((issues[0] as Dictionary).get("message", "请检查资料。"))
		if not issues.is_empty() and issues[0] is Dictionary
		else "请补全姓名、外观、人物内核与工作资料。"
	)
	var tone := "disabled" if validation_status == "unavailable" else "warning"
	_set_status_visual(
		tone,
		String(validation.get("summaryLabel", "资料尚未完整")),
		detail,
	)


func _render_actions(available: bool) -> void:
	var operation_status := String(
		(_view_model.get("operation", {}) as Dictionary).get("status", "idle")
	)
	var loading := operation_status == "loading"
	var update_enabled := available and _action_enabled("updateFields") and not loading
	_name_edit.editable = update_enabled and _field_editable("name")
	_age_edit.editable = update_enabled and _field_editable("age")
	_desire_edit.editable = update_enabled and _field_editable("desire")
	_personality_edit.editable = update_enabled and _field_editable("personality")
	_speech_edit.editable = update_enabled and _field_editable("speech")
	var gender_enabled := update_enabled and _field_editable("gender")
	_gender_option.disabled = not gender_enabled
	var age_enabled := update_enabled and _field_editable("age")
	_age_minus_button.disabled = not age_enabled
	_age_plus_button.disabled = not age_enabled
	_open_wardrobe_button.disabled = not (
		available and _action_enabled("openWardrobe") and not loading
	)
	_occupation_option.disabled = not (
		update_enabled and _field_editable("occupationId")
	)
	_workplace_option.disabled = not (
		update_enabled and _field_editable("workplaceId")
	)
	_interest_option.disabled = not (
		update_enabled
		and _field_editable("interests")
		and _field_editable("customInterests")
	)
	if _owned_place_option != null:
		_owned_place_option.disabled = not (
			update_enabled and _field_editable("ownedPlaceId")
		)
	if not update_enabled and _dropdown_overlay.visible:
		_close_dropdown_popup(false)
	_refresh_dropdown_arrow(_occupation_option)
	_refresh_dropdown_arrow(_workplace_option)
	_refresh_dropdown_arrow(_owned_place_option)
	_refresh_dropdown_arrow(_interest_option)
	_set_primary_loading(_create_button, loading)
	var retryable := (
		available
		and operation_status in ["rejected", "error"]
		and _action_enabled("retry")
		and not loading
	)
	_create_button.text = (
		_submit_loading_copy()
		if loading
		else (
			_submit_retry_copy()
			if retryable
			else _submit_button_copy()
		)
	)
	_create_button.disabled = not (
		retryable
		or (available and _action_enabled(_submit_action_key()) and not loading)
	)
	_create_decoration.visible = not _create_button.disabled and not loading
	_cancel_button.disabled = not (
		navigation_back_available
		or (_action_enabled("cancel") and not loading)
	)
	_back_button.disabled = _cancel_button.disabled


func _field_editable(field: String) -> bool:
	var editable_value: Variant = _render_data.get("editableFields")
	if not editable_value is Array:
		return true
	for value: Variant in editable_value as Array:
		if String(value) == field:
			return true
	return false


func _set_status_visual(tone: String, title: String, detail: String) -> void:
	var asset_state := tone
	var text_color := LIGHT_TEXT
	match tone:
		"success":
			text_color = LIGHT_TEXT
		"warning":
			text_color = INK
		"error":
			text_color = LIGHT_TEXT
		"loading":
			text_color = LIGHT_TEXT
		"disabled":
			text_color = INK
		_:
			asset_state = "disabled"
			text_color = INK
	_status_frame.texture = _control_texture("status", asset_state)
	_status_icon.texture = (
		_control_texture("status_icon_reference", "success")
		if asset_state == "success"
		else _control_texture("status_icon", asset_state)
	)
	_status_label.text = title
	_status_label.add_theme_color_override("font_color", text_color)
	_status_label.tooltip_text = detail
	_status_detail.text = detail
	_status_detail.tooltip_text = detail


func _on_create_button_pressed() -> void:
	var operation_status := String(
		(_view_model.get("operation", {}) as Dictionary).get("status", "idle")
	)
	if operation_status in ["rejected", "error"] and _action_enabled("retry"):
		_request_action("retry")
		return
	if _is_edit_existing():
		_request_action("saveExisting", {
			"residentId": String(_render_data.get("residentId", "")),
		})
		return
	_request_action("create", {
		"candidatePoolRevision": int(_render_data.get("candidatePoolRevision", -1)),
	})


func _request_action(action_key: String, extra_payload: Dictionary = {}) -> void:
	var action := UiViewModel.action(_view_model, action_key)
	var intent := String(action.get("intent", ""))
	if action_key == "cancel" and navigation_back_available and intent.is_empty():
		intent_requested.emit(_cancel_intent(), {"routeOnly": true})
		return
	if intent.is_empty() or not UiViewModel.action_enabled(action):
		if action_key == "cancel" and navigation_back_available:
			intent_requested.emit(_cancel_intent(), {"routeOnly": true})
			return
		var reason := UiViewModel.disabled_reason(action)
		action_blocked.emit(intent, reason)
		return
	var payload := {
		"revision": _revision,
		"draftId": String(_render_data.get("draftId", "")),
	}
	payload.merge(extra_payload, true)
	var dispatch_result: Dictionary = {}
	if _adapter != null and _adapter.has_method("dispatch"):
		dispatch_result = _adapter.call("dispatch", intent, payload) as Dictionary
	var routed_payload := payload.duplicate(true)
	routed_payload["dispatchResult"] = dispatch_result.duplicate(true)
	intent_requested.emit(intent, routed_payload)


func _request_update(fields: Dictionary) -> void:
	if _rendering or fields.is_empty():
		return
	_request_action("updateFields", {"fields": fields.duplicate(true)})


func _step_age(delta: int) -> void:
	var current := int((_render_data.get("draft", {}) as Dictionary).get("age", 27))
	_request_update({"age": clampi(current + delta, 1, 120)})


func _commit_age_text() -> void:
	var parsed := int(_age_edit.text)
	var current := int((_render_data.get("draft", {}) as Dictionary).get("age", 27))
	var value := clampi(parsed, 1, 120)
	if value != current:
		_local_text_drafts["age"] = str(value)
		_set_line_edit_text_preserving_caret(_age_edit, str(value))
		_request_update({"age": value})
	else:
		_local_text_drafts.erase("age")
		_set_line_edit_text_preserving_caret(_age_edit, str(current))


func _commit_text_field(field: String, value: String) -> void:
	var current := String((_render_data.get("draft", {}) as Dictionary).get(field, ""))
	var normalized := value.strip_edges()
	if normalized != current:
		_local_text_drafts[field] = normalized
		_request_update({field: normalized})
	else:
		_local_text_drafts.erase(field)


func _commit_core_field(field: String, edit: TextEdit) -> void:
	_commit_text_field(field, edit.text)


func _populate_option(option: Button, values: Array, selected_id: String) -> void:
	var normalized_values: Array[Dictionary] = []
	var selected_label := "—"
	for value: Variant in values:
		if not value is Dictionary:
			continue
		var item := (value as Dictionary).duplicate(true)
		var item_id := String(item.get("id", ""))
		if item_id.is_empty():
			continue
		normalized_values.append(item)
		if item_id == selected_id:
			selected_label = String(item.get("label", item_id))
	option.set_meta("dropdown_values", normalized_values)
	option.set_meta("selected_id", selected_id)
	option.text = selected_label
	if option == _dropdown_active_option and _dropdown_overlay.visible:
		_rebuild_dropdown_items()


func _populate_interest_option(
	option_values: Array,
	selected_values: Array,
	custom_values: Array,
	maximum: int,
) -> void:
	var values: Array[Dictionary] = []
	var labels_by_id: Dictionary = {}
	for value: Variant in option_values:
		if not value is Dictionary:
			continue
		var source := value as Dictionary
		var item_id := String(
			source.get("interestId", source.get("id", "")),
		)
		var label := String(source.get("label", item_id))
		if item_id.is_empty():
			continue
		values.append({"id": item_id, "label": label, "enabled": true})
		labels_by_id[item_id] = label
	var selected: Array[String] = []
	var labels: Array[String] = []
	for value: Variant in selected_values:
		var item_id := String(value)
		if item_id.is_empty() or selected.has(item_id):
			continue
		selected.append(item_id)
		labels.append(String(labels_by_id.get(item_id, item_id)))
	var custom: Array[String] = []
	for value: Variant in custom_values:
		var label := String(value).strip_edges()
		if label.is_empty() or custom.has(label):
			continue
		custom.append(label)
		labels.append(label)
	var total := selected.size() + custom.size()
	_interest_option.set_meta("dropdown_values", values)
	_interest_option.set_meta("selected_ids", selected)
	_interest_option.set_meta("custom_values", custom)
	_interest_option.set_meta("maximum", maxi(maximum, 1))
	_interest_option.text = (
		"暂无（0/%d）" % maximum
		if labels.is_empty()
		else "%s（%d/%d）" % ["、".join(labels), total, maximum]
	)
	if (
		_interest_option == _dropdown_active_option
		and _dropdown_overlay.visible
	):
		_rebuild_dropdown_items()


func _toggle_dropdown_popup(field: String, option: Button) -> void:
	if option.disabled:
		option.button_pressed = false
		return
	if _dropdown_overlay.visible and _dropdown_active_option == option:
		_close_dropdown_popup(true)
		return
	_open_dropdown_popup(field, option)


func _open_dropdown_popup(field: String, option: Button) -> void:
	if _dropdown_active_option != null and is_instance_valid(_dropdown_active_option):
		_dropdown_active_option.button_pressed = false
	_dropdown_active_field = field
	_dropdown_active_option = option
	_dropdown_active_option.button_pressed = true
	_rebuild_dropdown_items()
	var panel_position := option.position + Vector2(0, option.size.y - 1)
	if panel_position.y + DROPDOWN_POPUP_SIZE.y > REFERENCE_SIZE.y - 8:
		panel_position.y = option.position.y - DROPDOWN_POPUP_SIZE.y + 1
	panel_position.x = clampf(
		panel_position.x,
		8.0,
		REFERENCE_SIZE.x - DROPDOWN_POPUP_SIZE.x - 8.0,
	)
	_dropdown_panel.position = panel_position.round()
	_dropdown_scroll.scroll_vertical = 0
	_dropdown_overlay.visible = true
	_refresh_dropdown_arrow(option)
	_refresh_dropdown_scrollbar.call_deferred()
	_focus_selected_dropdown_item.call_deferred()


func _close_dropdown_popup(restore_focus: bool) -> void:
	if _dropdown_overlay == null:
		return
	_dropdown_overlay.visible = false
	_dropdown_dragging = false
	var previous := _dropdown_active_option
	_dropdown_active_option = null
	_dropdown_active_field = ""
	if previous != null and is_instance_valid(previous):
		previous.button_pressed = false
		_refresh_dropdown_arrow(previous)
		if restore_focus:
			previous.grab_focus.call_deferred()


func _rebuild_dropdown_items() -> void:
	var focus_state := _capture_dropdown_focus_state()
	UiNodeRetirement.retire_children(_dropdown_list)
	_interest_custom_edit = null
	if _dropdown_active_option == null:
		return
	if _dropdown_active_field == "interests":
		_rebuild_interest_dropdown_items()
		_restore_dropdown_focus_after_rebuild.call_deferred(focus_state)
		return
	var values := _dropdown_active_option.get_meta("dropdown_values", []) as Array
	var selected_id := String(_dropdown_active_option.get_meta("selected_id", ""))
	for index: int in values.size():
		var item := values[index] as Dictionary
		var item_id := String(item.get("id", ""))
		var row := Button.new()
		row.name = "DropdownItem_%d" % index
		row.text = String(item.get("label", item_id))
		row.custom_minimum_size = DROPDOWN_POPUP_ITEM_SIZE
		row.size = DROPDOWN_POPUP_ITEM_SIZE
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.focus_mode = Control.FOCUS_ALL
		row.disabled = not bool(item.get("enabled", true))
		row.tooltip_text = UiViewModel.player_reason(
			String(item.get("disabledReason", ""))
		)
		row.set_meta("dropdown_item_id", item_id)
		row.set_meta("dropdown_selected", item_id == selected_id)
		_apply_dropdown_popup_item_skin(row, item_id == selected_id)
		row.pressed.connect(_select_dropdown_option.bind(item_id))
		_dropdown_list.add_child(row)
		var separator := TextureRect.new()
		separator.name = "DropdownItemSeparator"
		separator.position = Vector2(0, DROPDOWN_POPUP_ITEM_SIZE.y - 2)
		separator.size = Vector2(DROPDOWN_POPUP_ITEM_SIZE.x, 2)
		separator.texture = _dropdown_popup_texture("separator", "normal")
		separator.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		separator.stretch_mode = TextureRect.STRETCH_SCALE
		separator.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
		separator.visible = index < values.size() - 1
		row.add_child(separator)
	_refresh_dropdown_scrollbar.call_deferred()
	_restore_dropdown_focus_after_rebuild.call_deferred(focus_state)


func _capture_dropdown_focus_state() -> Dictionary:
	if not is_inside_tree() or not is_instance_valid(_dropdown_list):
		return {}
	var focus_owner := get_viewport().gui_get_focus_owner()
	if not is_instance_valid(focus_owner) or not _dropdown_list.is_ancestor_of(focus_owner):
		return {}
	if focus_owner == _interest_custom_edit:
		_interest_custom_draft = _interest_custom_edit.text
		var input_state := {
			"kind": "custom_interest_input",
			"caretColumn": _interest_custom_edit.get_caret_column(),
			"hasSelection": _interest_custom_edit.has_selection(),
		}
		if _interest_custom_edit.has_selection():
			input_state["selectionFrom"] = _interest_custom_edit.get_selection_from_column()
			input_state["selectionTo"] = _interest_custom_edit.get_selection_to_column()
		return input_state
	if focus_owner is Button:
		var button := focus_owner as Button
		return {
			"kind": "button",
			"name": String(button.name),
			"itemId": String(button.get_meta("dropdown_item_id", "")),
			"customLabel": String(button.get_meta("custom_interest_label", "")),
		}
	return {}


func _restore_dropdown_focus_after_rebuild(focus_state: Dictionary) -> void:
	if focus_state.is_empty() or not _dropdown_overlay.visible:
		return
	if String(focus_state.get("kind", "")) == "custom_interest_input":
		if not is_instance_valid(_interest_custom_edit):
			return
		_interest_custom_edit.grab_focus()
		_interest_custom_edit.set_caret_column(clampi(
			int(focus_state.get("caretColumn", _interest_custom_edit.text.length())),
			0,
			_interest_custom_edit.text.length(),
		))
		if bool(focus_state.get("hasSelection", false)):
			_interest_custom_edit.select(
				clampi(
					int(focus_state.get("selectionFrom", 0)),
					0,
					_interest_custom_edit.text.length(),
				),
				clampi(
					int(focus_state.get("selectionTo", 0)),
					0,
					_interest_custom_edit.text.length(),
				),
			)
		return
	var expected_name := String(focus_state.get("name", ""))
	var expected_item_id := String(focus_state.get("itemId", ""))
	var expected_custom_label := String(focus_state.get("customLabel", ""))
	for child: Node in _dropdown_list.find_children("*", "Button", true, false):
		var button := child as Button
		if (
			(not expected_item_id.is_empty()
				and String(button.get_meta("dropdown_item_id", "")) == expected_item_id)
			or (not expected_custom_label.is_empty()
				and String(button.get_meta("custom_interest_label", "")) == expected_custom_label)
			or (expected_item_id.is_empty()
				and expected_custom_label.is_empty()
				and String(button.name) == expected_name)
		):
			if not button.disabled:
				button.grab_focus()
			return


func _rebuild_interest_dropdown_items() -> void:
	var selected := (
		_dropdown_active_option.get_meta("selected_ids", []) as Array
	).duplicate()
	var custom := (
		_dropdown_active_option.get_meta("custom_values", []) as Array
	).duplicate()
	var maximum := int(_dropdown_active_option.get_meta("maximum", 3))
	var total := selected.size() + custom.size()
	var custom_row := HBoxContainer.new()
	custom_row.name = "CustomInterestInputRow"
	custom_row.custom_minimum_size = DROPDOWN_POPUP_ITEM_SIZE
	custom_row.add_theme_constant_override("separation", 8)
	_interest_custom_edit = LineEdit.new()
	_interest_custom_edit.name = "CustomInterestEdit"
	_interest_custom_edit.custom_minimum_size = Vector2(
		DROPDOWN_POPUP_ITEM_SIZE.x - 104,
		DROPDOWN_POPUP_ITEM_SIZE.y,
	)
	_interest_custom_edit.max_length = 20
	_interest_custom_edit.placeholder_text = "输入自定义兴趣（最多20字）"
	_interest_custom_edit.add_theme_font_size_override("font_size", 19)
	_interest_custom_edit.add_theme_color_override("font_color", INK)
	_interest_custom_edit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_interest_custom_edit.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_interest_custom_edit.text = _interest_custom_draft
	_interest_custom_edit.text_changed.connect(func(value: String) -> void:
		_interest_custom_draft = value
	)
	_interest_custom_edit.text_submitted.connect(
		func(_value: String) -> void: _add_custom_interest(),
	)
	custom_row.add_child(_interest_custom_edit)
	var add_button := Button.new()
	add_button.name = "AddCustomInterestButton"
	add_button.text = "添加"
	add_button.custom_minimum_size = Vector2(96, DROPDOWN_POPUP_ITEM_SIZE.y)
	add_button.disabled = total >= maximum
	_apply_dropdown_popup_item_skin(add_button, false)
	add_button.pressed.connect(_add_custom_interest)
	custom_row.add_child(add_button)
	_dropdown_list.add_child(custom_row)
	var values := _dropdown_active_option.get_meta("dropdown_values", []) as Array
	for index: int in values.size():
		var item := values[index] as Dictionary
		var item_id := String(item.get("id", ""))
		var is_selected := selected.has(item_id)
		var row := Button.new()
		row.name = "InterestDropdownItem_%d" % index
		row.text = "%s%s" % [
			"✓ " if is_selected else "",
			String(item.get("label", item_id)),
		]
		row.custom_minimum_size = DROPDOWN_POPUP_ITEM_SIZE
		row.size = DROPDOWN_POPUP_ITEM_SIZE
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.disabled = not is_selected and total >= maximum
		row.set_meta("dropdown_item_id", item_id)
		row.set_meta("dropdown_selected", is_selected)
		_apply_dropdown_popup_item_skin(row, is_selected)
		row.pressed.connect(_toggle_catalog_interest.bind(item_id))
		_dropdown_list.add_child(row)
	for index: int in custom.size():
		var label := String(custom[index])
		var row := Button.new()
		row.name = "CustomInterestItem_%d" % index
		row.text = "✓ %s（点击移除）" % label
		row.custom_minimum_size = DROPDOWN_POPUP_ITEM_SIZE
		row.size = DROPDOWN_POPUP_ITEM_SIZE
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.set_meta("dropdown_selected", true)
		row.set_meta("custom_interest_label", label)
		_apply_dropdown_popup_item_skin(row, true)
		row.pressed.connect(_remove_custom_interest.bind(label))
		_dropdown_list.add_child(row)
	_refresh_dropdown_scrollbar.call_deferred()


func _toggle_catalog_interest(item_id: String) -> void:
	var draft := _render_data.get("draft", {}) as Dictionary
	var selected := (draft.get("interests", []) as Array).duplicate()
	if selected.has(item_id):
		selected.erase(item_id)
	else:
		selected.append(item_id)
	_request_update({"interests": selected})


func _add_custom_interest() -> void:
	if not is_instance_valid(_interest_custom_edit):
		return
	var label := _interest_custom_edit.text.strip_edges()
	if label.is_empty():
		return
	var draft := _render_data.get("draft", {}) as Dictionary
	var selected := draft.get("interests", []) as Array
	var custom := (draft.get("customInterests", []) as Array).duplicate()
	var maximum := int(_interest_option.get_meta("maximum", 3))
	if selected.size() + custom.size() >= maximum:
		return
	if not custom.has(label):
		custom.append(label)
	_interest_custom_draft = ""
	_request_update({"customInterests": custom})


func _remove_custom_interest(label: String) -> void:
	var draft := _render_data.get("draft", {}) as Dictionary
	var custom := (draft.get("customInterests", []) as Array).duplicate()
	custom.erase(label)
	_request_update({"customInterests": custom})


func _select_dropdown_option(item_id: String) -> void:
	if _rendering or _dropdown_active_field.is_empty():
		return
	var field := _dropdown_active_field
	_close_dropdown_popup(true)
	_request_update({field: item_id})


func _focus_selected_dropdown_item() -> void:
	var fallback: Button
	for child: Node in _dropdown_list.get_children():
		if not child is Button:
			continue
		var row := child as Button
		if fallback == null and not row.disabled:
			fallback = row
		if bool(row.get_meta("dropdown_selected", false)) and not row.disabled:
			row.grab_focus()
			return
	if fallback != null:
		fallback.grab_focus()


func _on_dropdown_backdrop_input(event: InputEvent) -> void:
	if POINTER_INPUT.is_primary_press(event):
		_close_dropdown_popup(true)
		get_viewport().set_input_as_handled()


func _refresh_dropdown_scrollbar() -> void:
	if (
		_dropdown_scroll == null
		or _dropdown_track == null
		or _dropdown_thumb_hit_target == null
		or _dropdown_thumb == null
	):
		return
	var bar := _dropdown_scroll.get_v_scroll_bar()
	var can_scroll := bar != null and bar.max_value > bar.page + 0.5
	_dropdown_track.visible = can_scroll
	_dropdown_thumb_hit_target.visible = can_scroll
	if not can_scroll:
		return
	var track_rect := _dropdown_track.get_rect()
	var thumb_height := 72.0
	var travel := maxf(0.0, track_rect.size.y - thumb_height)
	var scroll_range := maxf(1.0, bar.max_value - bar.page)
	var progress := clampf(bar.value / scroll_range, 0.0, 1.0)
	_dropdown_thumb_hit_target.position = Vector2(
		_dropdown_track.position.x - 10,
		_dropdown_track.position.y + travel * progress,
	).round()
	_dropdown_thumb.position = Vector2(6, 0)
	_dropdown_thumb.size = Vector2(32, 72)


func _on_dropdown_scroll_input(event: InputEvent, dragging_thumb: bool) -> void:
	if not _dropdown_overlay.visible:
		return
	var bar := _dropdown_scroll.get_v_scroll_bar()
	if bar == null:
		return
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_button.pressed:
			bar.value -= maxf(DROPDOWN_POPUP_ITEM_SIZE.y, bar.page * 0.35)
			get_viewport().set_input_as_handled()
		elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_button.pressed:
			bar.value += maxf(DROPDOWN_POPUP_ITEM_SIZE.y, bar.page * 0.35)
			get_viewport().set_input_as_handled()
		elif mouse_button.button_index == MOUSE_BUTTON_LEFT:
			_dropdown_dragging = mouse_button.pressed
			if mouse_button.pressed:
				_dropdown_drag_offset = (
					mouse_button.global_position.y
					- _dropdown_thumb.get_global_rect().position.y
					if dragging_thumb
					else _dropdown_thumb.size.y * 0.5
				)
				_set_dropdown_scroll_from_global_y(mouse_button.global_position.y)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dropdown_dragging:
		_set_dropdown_scroll_from_global_y((event as InputEventMouseMotion).global_position.y)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		_dropdown_dragging = touch.pressed
		if touch.pressed:
			_dropdown_drag_offset = (
				touch.position.y - _dropdown_thumb.get_global_rect().position.y
				if dragging_thumb
				else _dropdown_thumb.size.y * 0.5
			)
			_set_dropdown_scroll_from_global_y(touch.position.y)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and _dropdown_dragging:
		_set_dropdown_scroll_from_global_y((event as InputEventScreenDrag).position.y)
		get_viewport().set_input_as_handled()


func _set_dropdown_scroll_from_global_y(global_y: float) -> void:
	var bar := _dropdown_scroll.get_v_scroll_bar()
	if bar == null or bar.max_value <= bar.page + 0.5:
		return
	var track_rect := _dropdown_track.get_global_rect()
	var travel := maxf(1.0, track_rect.size.y - _dropdown_thumb.size.y)
	var thumb_y := global_y - track_rect.position.y - _dropdown_drag_offset
	var progress := clampf(thumb_y / travel, 0.0, 1.0)
	bar.value = progress * (bar.max_value - bar.page)


func _action_enabled(action_key: String) -> bool:
	return UiViewModel.action_enabled(UiViewModel.action(_view_model, action_key))


func _is_edit_existing() -> bool:
	return presentation_mode == "edit_existing"


func _is_admission() -> bool:
	return presentation_mode == "admission"


func _submit_button_copy() -> String:
	if _is_edit_existing():
		return "保存修改"
	return "确定" if _is_admission() else "创建并返回名单"


func _submit_loading_copy() -> String:
	if _is_edit_existing():
		return "正在保存……"
	return "正在确认……" if _is_admission() else "正在创建……"


func _submit_retry_copy() -> String:
	if _is_edit_existing():
		return "重试保存"
	return "重试确认" if _is_admission() else "重试创建"


func _submit_action_key() -> String:
	return "saveExisting" if _is_edit_existing() else "create"


func _cancel_intent() -> String:
	return (
		"resident_profile_editor.cancel"
		if _is_edit_existing()
		else "custom_resident_creator.cancel"
	)


func _refresh_from_adapter() -> void:
	if _adapter == null or not _adapter.has_method("get_view_model"):
		_contract_error = "自定义居民创建页尚未绑定 TownUiAdapter。"
		return
	var snapshot: Variant = _adapter.call("get_view_model", SCOPE)
	if not snapshot is Dictionary:
		_contract_error = "TownUiAdapter 未返回完整 custom_resident_creator ViewModel。"
		return
	apply_view_model(snapshot as Dictionary)


func _on_adapter_view_model_changed(scope: String, view_model: Dictionary) -> void:
	if scope == SCOPE:
		apply_view_model(view_model)


func _disconnect_adapter() -> void:
	UI_SIGNALS.disconnect_view_model(
		_adapter,
		Callable(self, "_on_adapter_view_model_changed"),
	)


func _apply_responsive_layout() -> void:
	if _canvas_host == null or _canvas == null:
		return
	if MOBILE_UI_PROFILE.is_mobile_runtime():
		var viewport_size := size
		if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
			viewport_size = get_viewport_rect().size
		var scale_factor := minf(
			viewport_size.x / REFERENCE_SIZE.x,
			viewport_size.y / REFERENCE_SIZE.y,
		)
		_canvas_host.custom_minimum_size = viewport_size
		_canvas.position = (viewport_size - REFERENCE_SIZE * scale_factor) * 0.5
		_canvas.size = REFERENCE_SIZE
		_canvas.scale = Vector2.ONE * scale_factor
		_viewport_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_viewport_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		return
	_canvas_host.custom_minimum_size = REFERENCE_SIZE
	_canvas.position = Vector2.ZERO
	_canvas.size = REFERENCE_SIZE
	_canvas.scale = Vector2.ONE


func _focus_initial_control() -> void:
	focus_default_control()


func _section_title(text: String, rect: Rect2) -> Label:
	return _label(
		"SectionTitle_%s" % text,
		text,
		rect,
		25,
		INK,
		HORIZONTAL_ALIGNMENT_LEFT,
	)


func _field_label(node_name: String, text: String, rect: Rect2) -> Label:
	return _label(node_name, text, rect, 19, INK, HORIZONTAL_ALIGNMENT_LEFT)


func _label(
	node_name: String,
	text: String,
	rect: Rect2,
	font_size: int,
	color: Color,
	alignment: HorizontalAlignment,
) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.position = rect.position.round()
	label.size = rect.size.round()
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _state_button(node_name: String, text: String, rect: Rect2, family: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	_set_control_rect(button, rect)
	button.focus_mode = Control.FOCUS_ALL
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_apply_button_family(button, family)
	return button


func _apply_button_family(button: Button, family: String) -> void:
	var state_assets := _button_state_assets(family)
	var light_family := family in ["back", "wardrobe", "create"]
	button.add_theme_color_override("font_color", LIGHT_TEXT if light_family else INK)
	button.add_theme_color_override("font_hover_color", Color.WHITE if light_family else INK)
	button.add_theme_color_override("font_pressed_color", LIGHT_TEXT if light_family else INK)
	button.add_theme_color_override("font_focus_color", Color.WHITE if light_family else INK)
	button.add_theme_color_override("font_disabled_color", DISABLED_INK)
	button.set_meta("visual_family", family)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var texture_state := String(state_assets.get(state, "normal"))
		button.add_theme_stylebox_override(
			state,
			_asset_style(_control_texture(family, texture_state), 12.0),
		)


func _button_state_assets(family: String) -> Dictionary:
	match family:
		"back", "cancel":
			return {
				"normal": "normal",
				"hover": "hover",
				"pressed": "pressed",
				"focus": "hover",
				"disabled": "disabled",
			}
		"wardrobe", "create":
			return {
				"normal": "normal",
				"hover": "hover",
				"pressed": "pressed",
				"focus": "hover",
				"disabled": "disabled",
			}
		"age_minus", "age_plus":
			return {
				"normal": "normal",
				"hover": "normal",
				"pressed": "pressed",
				"focus": "normal",
				"disabled": "disabled",
			}
		_:
			push_error("未知的自定义居民控件族：%s" % family)
			return {
				"normal": "normal",
				"hover": "normal",
				"pressed": "normal",
				"focus": "normal",
				"disabled": "disabled",
			}


func _primary_button(node_name: String, text: String, rect: Rect2) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	_set_control_rect(button, rect)
	button.focus_mode = Control.FOCUS_ALL
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.add_theme_font_size_override("font_size", 28)
	button.add_theme_color_override("font_color", LIGHT_TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", LIGHT_TEXT)
	button.add_theme_color_override("font_disabled_color", DISABLED_INK)
	_set_primary_loading(button, false)
	return button


func _set_primary_loading(button: Button, loading: bool) -> void:
	var state_paths := {
		"normal": "loading" if loading else "normal",
		"hover": "loading" if loading else "hover",
		"pressed": "loading" if loading else "pressed",
		"focus": "loading" if loading else "hover",
		"disabled": "loading" if loading else "disabled",
	}
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var texture := _control_texture("create", String(state_paths[state]))
		var style := _asset_style(texture, 16.0)
		style.content_margin_left = 16
		style.content_margin_right = 52
		style.content_margin_top = 10 if state == "pressed" else 8
		style.content_margin_bottom = 6 if state == "pressed" else 12
		button.add_theme_stylebox_override(state, style)


func _apply_input_skin(control: Control, family: String) -> void:
	var normal_state := "normal"
	var hover_state := "hover"
	var pressed_state := "hover"
	if family == "age_value":
		hover_state = "normal"
		pressed_state = "pressed"
	var state_assets := {
		"normal": normal_state,
		"hover": hover_state,
		"pressed": pressed_state,
		"focus": hover_state,
		"read_only": "disabled",
		"disabled": "disabled",
	}
	for state in state_assets:
		var style := _asset_style(
			_control_texture(family, String(state_assets[state])),
			12.0,
		)
		if control is Button:
			style.content_margin_top = 0
			style.content_margin_bottom = 0
			style.content_margin_right = 58
		if control is TextEdit:
			style.content_margin_top = 2
			style.content_margin_bottom = 2
		control.add_theme_stylebox_override(
			String(state),
			style,
		)
	control.add_theme_constant_override("minimum_character_width", 0)
	control.add_theme_color_override("font_color", INK)
	control.add_theme_color_override("font_disabled_color", DISABLED_INK)
	control.add_theme_color_override("font_uneditable_color", DISABLED_INK)
	control.add_theme_font_size_override(
		"font_size",
		15 if control is TextEdit else 20,
	)


func _apply_dropdown_skin(option: Button) -> void:
	_apply_input_skin(option, "dropdown_field")
	var arrow := TextureRect.new()
	arrow.name = "DropdownArrow"
	arrow.position = Vector2(option.size.x - 46, 0)
	arrow.size = Vector2(46, 48)
	arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	arrow.stretch_mode = TextureRect.STRETCH_SCALE
	arrow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	option.add_child(arrow)
	option.set_meta("dropdown_arrow", arrow)
	for signal_name in [
		"mouse_entered", "mouse_exited", "focus_entered", "focus_exited",
		"button_down", "button_up",
	]:
		option.connect(signal_name, Callable(self, "_on_dropdown_visual_changed").bind(option))
	_refresh_dropdown_arrow(option)


func _on_dropdown_visual_changed(option: Button) -> void:
	_refresh_dropdown_arrow.call_deferred(option)


func _refresh_dropdown_arrow(option: Button) -> void:
	if option == null or not is_instance_valid(option):
		return
	var state := "normal"
	if option.disabled:
		state = "disabled"
	elif option.button_pressed:
		state = "pressed"
	elif option.is_hovered() or option.has_focus():
		state = "hover"
	var arrow_value: Variant = option.get_meta("dropdown_arrow", null)
	if arrow_value is TextureRect:
		(arrow_value as TextureRect).texture = _control_texture("dropdown_arrow", state)


func _apply_dropdown_popup_item_skin(button: Button, selected: bool) -> void:
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", LIGHT_TEXT if selected else INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", LIGHT_TEXT)
	button.add_theme_color_override("font_focus_color", INK)
	button.add_theme_color_override("font_disabled_color", DISABLED_INK)
	var normal_state := "selected" if selected else "normal"
	var state_assets := {
		"normal": normal_state,
		"hover": "hover",
		"pressed": "pressed",
		"focus": "hover" if not selected else "selected",
		"disabled": "disabled",
	}
	for state_value: Variant in state_assets:
		var state := String(state_value)
		var texture_state := String(state_assets[state_value])
		var style := _asset_style(
			_dropdown_popup_texture("item", texture_state),
			18.0,
		)
		style.content_margin_top = 0
		style.content_margin_bottom = 0
		button.add_theme_stylebox_override(state, style)


func _control_texture(family: String, state: String) -> Texture2D:
	var path := CONTROL_ASSET_ROOT + family + "/" + state + ".png"
	var texture := load(path) as Texture2D
	if texture == null:
		push_error("自定义居民控件资产缺失：%s" % path)
	return texture


func _dropdown_popup_texture(family: String, state: String) -> Texture2D:
	var path := DROPDOWN_POPUP_ASSET_ROOT + family + "/" + state + ".png"
	var texture := load(path) as Texture2D
	if texture == null:
		push_error("自定义居民下拉展开层资产缺失：%s" % path)
	return texture


func _asset_style(texture: Texture2D, content_margin: float = 0.0) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = 0
	style.texture_margin_top = 0
	style.texture_margin_right = 0
	style.texture_margin_bottom = 0
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.draw_center = true
	style.content_margin_left = content_margin
	style.content_margin_top = content_margin * 0.35
	style.content_margin_right = content_margin
	style.content_margin_bottom = content_margin * 0.35
	return style


func _set_control_rect(control: Control, rect: Rect2) -> void:
	control.position = rect.position.round()
	control.size = rect.size.round()
	control.custom_minimum_size = rect.size.round()


func _source_rect(x: float, y: float, width: float, height: float) -> Rect2:
	var scale_factor := REFERENCE_SIZE / SOURCE_SIZE
	return Rect2(
		Vector2(roundf(x * scale_factor.x), roundf(y * scale_factor.y)),
		Vector2(roundf(width * scale_factor.x), roundf(height * scale_factor.y)),
	)


func _source_point(x: float, y: float) -> Vector2:
	var scale_factor := REFERENCE_SIZE / SOURCE_SIZE
	return Vector2(roundf(x * scale_factor.x), roundf(y * scale_factor.y))


func _control_disabled(control: Control) -> bool:
	if control is Button:
		return bool(control.get("disabled"))
	if control is LineEdit or control is TextEdit:
		return not bool(control.get("editable"))
	return false


func _exact_asset_contracts() -> Array[Dictionary]:
	var contracts: Array[Dictionary] = []
	for control in [
		_back_button,
		_name_edit,
		_gender_option,
		_age_minus_button,
		_age_edit,
		_age_plus_button,
		_desire_edit,
		_personality_edit,
		_speech_edit,
		_open_wardrobe_button,
		_occupation_option,
		_workplace_option,
		_owned_place_option,
		_interest_option,
		_cancel_button,
		_create_button,
	]:
		if control == null or not is_instance_valid(control):
			continue
		var typed_control := control as Control
		var texture_size := Vector2.ZERO
		var style: StyleBox = typed_control.get_theme_stylebox("normal")
		if style is StyleBoxTexture and (style as StyleBoxTexture).texture != null:
			texture_size = (style as StyleBoxTexture).texture.get_size()
		contracts.append({
			"name": String(typed_control.name),
			"controlSize": [typed_control.size.x, typed_control.size.y],
			"textureSize": [texture_size.x, texture_size.y],
			"exact": texture_size == typed_control.size,
		})
	if _status_frame != null and _status_frame.texture != null:
		var status_texture_size := _status_frame.texture.get_size()
		contracts.append({
			"name": String(_status_frame.name),
			"controlSize": [_status_frame.size.x, _status_frame.size.y],
			"textureSize": [status_texture_size.x, status_texture_size.y],
			"exact": status_texture_size == _status_frame.size,
		})
	if _dropdown_panel != null and _dropdown_panel.texture != null:
		var dropdown_panel_texture_size := _dropdown_panel.texture.get_size()
		contracts.append({
			"name": String(_dropdown_panel.name),
			"controlSize": [_dropdown_panel.size.x, _dropdown_panel.size.y],
			"textureSize": [
				dropdown_panel_texture_size.x,
				dropdown_panel_texture_size.y,
			],
			"exact": dropdown_panel_texture_size == _dropdown_panel.size,
		})
	for texture_rect_value: Variant in [_dropdown_track, _dropdown_thumb]:
		if (
			texture_rect_value == null
			or not is_instance_valid(texture_rect_value)
			or not texture_rect_value is TextureRect
		):
			continue
		var scrollbar_texture_rect := texture_rect_value as TextureRect
		if scrollbar_texture_rect.texture == null:
			continue
		var common_texture_size := scrollbar_texture_rect.texture.get_size()
		contracts.append({
			"name": String(scrollbar_texture_rect.name),
			"controlSize": [
				scrollbar_texture_rect.size.x,
				scrollbar_texture_rect.size.y,
			],
			"textureSize": [common_texture_size.x, common_texture_size.y],
			"exact": common_texture_size == scrollbar_texture_rect.size,
		})
	for texture_rect in [_status_icon, _create_decoration]:
		if texture_rect == null or not is_instance_valid(texture_rect):
			continue
		var typed_texture_rect := texture_rect as TextureRect
		if typed_texture_rect.texture == null:
			continue
		var texture_size := typed_texture_rect.texture.get_size()
		contracts.append({
			"name": String(typed_texture_rect.name),
			"controlSize": [typed_texture_rect.size.x, typed_texture_rect.size.y],
			"textureSize": [texture_size.x, texture_size.y],
			"exact": texture_size == typed_texture_rect.size,
		})
	return contracts


func _rect_array(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
