class_name ProviderSettingsCompositeDesktop
extends Control


const UiNodeRetirement := preload("res://ui/common/AiTownUiNodeRetirement.gd")


signal ui_action(action: StringName, payload: Dictionary)
signal controls_rebuilt
signal pagination_changed(provider_page: int, model_page: int)

const UiViewModel = preload("res://ui/common/AiTownUiViewModel.gd")
const ProviderTheme = preload(
	"res://ui/provider_settings/ProviderSettingsTheme.gd"
)
const ProviderButtonMotion = preload(
	"res://ui/provider_settings/ProviderSettingsButtonMotion.gd"
)
const SOURCE_SIZE := Vector2(1672.0, 941.0)
const REFERENCE_VIEWPORT := Vector2(1920.0, 1080.0)
const MINIMUM_TOUCH_SIZE := Vector2(48.0, 48.0)
const CLOCK_HANDS_RECT := Rect2(795.0, 49.0, 82.0, 82.0)
const ASSET_PATH := ProviderTheme.COMPOSITE_DYNAMIC_CARD_BACKGROUND_PATH
const CONTRACT_PATH := (
	"res://assets/ui/provider_settings/composite_reference/"
	+ "provider_settings_page_composite_user_reference_v1_contract.json"
)
const PROVIDERS_PER_PAGE := 3
const MODELS_PER_PAGE := 2
const VERTICAL_STRETCH_SOURCE_TOP := 729.0
const VERTICAL_STRETCH_SOURCE_BOTTOM := 730.0
const SETTINGS_BOARD_SOURCE_LEFT := 154.0
const SETTINGS_BOARD_SOURCE_DIVIDER := 641.0
const SETTINGS_BOARD_SOURCE_RIGHT := 1518.0
const SELECTOR_STRETCH_SAMPLE_Y := 720.0
const DETAIL_STRETCH_SAMPLE_Y := 735.0
const CUSTOM_CONNECTION_LABEL_RECT := Rect2(690.0, 302.0, 124.0, 31.0)
const CUSTOM_CONNECTION_INPUT_RECT := Rect2(690.0, 343.0, 548.0, 39.0)
const CUSTOM_CONNECTION_SAVE_RECT := Rect2(1254.0, 334.0, 174.0, 56.0)
const CUSTOM_OTHER_HEADING_RECT := Rect2(690.0, 296.0, 180.0, 35.0)
const CUSTOM_OTHER_BASE_LABEL_RECT := Rect2(690.0, 335.0, 116.0, 46.0)
const CUSTOM_OTHER_BASE_INPUT_RECT := Rect2(814.0, 335.0, 608.0, 46.0)
const CUSTOM_OTHER_KEY_LABEL_RECT := Rect2(690.0, 386.0, 116.0, 50.0)
const CUSTOM_OTHER_KEY_INPUT_RECT := Rect2(814.0, 386.0, 430.0, 52.0)
const CUSTOM_OTHER_SAVE_RECT := Rect2(1306.0, 296.0, 116.0, 46.0)
const CUSTOM_OTHER_REVEAL_RECT := Rect2(1258.0, 386.0, 76.0, 52.0)
const CUSTOM_OTHER_DELETE_RECT := Rect2(1347.0, 386.0, 76.0, 52.0)
const CUSTOM_OTHER_MODEL_LABEL_RECT := Rect2(690.0, 471.0, 180.0, 31.0)
const CUSTOM_OTHER_MODEL_INPUT_RECT := Rect2(690.0, 529.0, 413.0, 39.0)
const CUSTOM_OTHER_MODEL_DISCOVER_RECT := Rect2(1128.0, 509.0, 136.0, 63.0)
const CUSTOM_OTHER_MODEL_ADD_RECT := Rect2(1292.0, 509.0, 126.0, 63.0)
const CUSTOM_MODEL_INPUT_RECT := Rect2(690.0, 473.0, 398.0, 39.0)
const CUSTOM_MODEL_DISCOVER_RECT := Rect2(1101.0, 464.0, 143.0, 56.0)
const CUSTOM_MODEL_ADD_RECT := Rect2(1260.0, 464.0, 162.0, 56.0)
const CUSTOM_LOCAL_CONNECTION_HEADING_RECT := Rect2(690.0, 302.0, 180.0, 31.0)
const CUSTOM_LOCAL_BASE_LABEL_RECT := Rect2(690.0, 340.0, 180.0, 28.0)
const CUSTOM_LOCAL_BASE_INPUT_RECT := Rect2(690.0, 371.0, 578.0, 42.0)
const CUSTOM_LOCAL_SAVE_RECT := Rect2(1295.0, 348.0, 126.0, 58.0)
const CUSTOM_LOCAL_ADD_HEADING_RECT := Rect2(690.0, 452.0, 180.0, 31.0)
const CUSTOM_LOCAL_MODEL_LABEL_RECT := Rect2(690.0, 486.0, 180.0, 27.0)
const CUSTOM_LOCAL_MODEL_INPUT_RECT := Rect2(690.0, 514.0, 414.0, 41.0)
const CUSTOM_LOCAL_DISCOVER_RECT := Rect2(1128.0, 493.0, 136.0, 63.0)
const CUSTOM_LOCAL_ADD_RECT := Rect2(1295.0, 493.0, 126.0, 63.0)
const CUSTOM_MODELS_LABEL_RECT := Rect2(690.0, 591.0, 142.0, 31.0)
const CUSTOM_MODEL_PAGE_RECT := Rect2(1245.0, 589.0, 108.0, 34.0)
const CUSTOM_MODEL_PAGE_PREVIOUS_RECT := Rect2(1190.0, 587.0, 46.0, 42.0)
const CUSTOM_MODEL_PAGE_NEXT_RECT := Rect2(1362.0, 587.0, 46.0, 42.0)
const CUSTOM_MODEL_CARD_Y := 630.0
const CUSTOM_MODEL_CARD_HEIGHT := 106.0
const CUSTOM_MODEL_NAME_Y := 637.0
const CUSTOM_MODEL_ORIGIN_Y := 681.0
const STANDARD_DYNAMIC_MODEL_INPUT_RECT := Rect2(850.0, 548.0, 300.0, 42.0)
const STANDARD_DYNAMIC_MODEL_ADD_RECT := Rect2(1160.0, 544.0, 125.0, 50.0)
const STANDARD_DYNAMIC_MODEL_PREVIOUS_RECT := Rect2(1290.0, 548.0, 38.0, 38.0)
const STANDARD_DYNAMIC_MODEL_PAGE_RECT := Rect2(1330.0, 550.0, 55.0, 34.0)
const STANDARD_DYNAMIC_MODEL_NEXT_RECT := Rect2(1385.0, 548.0, 38.0, 38.0)
const FORMAL_STATUS_ICON_RECT := Rect2(1390.0, 139.0, 46.0, 46.0)
const BACK_ARROW_RECT := Rect2(250.0, 145.0, 38.0, 38.0)

var key_edit: LineEdit
var base_url_edit: LineEdit
var api_model_edit: LineEdit
var status_label: Label
var check_button: Button
var formal_badge: Label
var provider_selector: Control
var provider_detail: Control

var _view_model: Dictionary
var _data: Dictionary
var _selected_provider_id := ""
var _draft_key := ""
var _draft_key_dirty := false
var _draft_base_url := ""
var _draft_api_model := ""
var _show_key := false
var _contract: Dictionary
var _slots: Dictionary
var _hit_targets: Dictionary
var _regions: Dictionary
var _scale := Vector2.ONE
var _design_scale := 1.0
var _vertical_extra := 0.0
var _provider_page := 0
var _model_page := 0
var _pagination_rebuild_queued := false
var _pagination_focus_target := ""


func configure(
	view_model: Dictionary,
	render_data: Dictionary,
	selected_provider_id: String,
	draft_key: String,
	draft_key_dirty: bool,
	draft_base_url: String,
	draft_api_model: String,
	show_key: bool,
	provider_page: int,
	model_page: int,
	viewport_size: Vector2
) -> bool:
	_view_model = view_model.duplicate(true)
	_data = render_data.duplicate(true)
	_selected_provider_id = selected_provider_id
	_draft_key = draft_key
	_draft_key_dirty = draft_key_dirty
	_draft_base_url = draft_base_url
	_draft_api_model = draft_api_model
	_show_key = show_key
	_contract = _load_json(CONTRACT_PATH)
	if _contract.is_empty():
		return false
	_slots = _contract.get("slots", {}) as Dictionary
	_hit_targets = (
		_contract.get("transparentHitTargets", {}) as Dictionary
	)
	_regions = _contract.get("layoutRegions", {}) as Dictionary
	var uniform_scale := minf(
		viewport_size.x / SOURCE_SIZE.x,
		viewport_size.y / SOURCE_SIZE.y,
	)
	_scale = Vector2.ONE * uniform_scale
	_vertical_extra = maxf(
		0.0,
		viewport_size.y - SOURCE_SIZE.y * uniform_scale,
	)
	_design_scale = minf(
		viewport_size.x / REFERENCE_VIEWPORT.x,
		viewport_size.y / REFERENCE_VIEWPORT.y,
	)
	_provider_page = (
		provider_page if provider_page >= 0 else _selected_provider_page()
	)
	_model_page = model_page if model_page >= 0 else _selected_model_page()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build()
	return true


func _build() -> void:
	var provider := _find_provider(_selected_provider_id)
	# 自定义模型只新增顶部连接下拉；页面其余区域继续使用原版模型设置底图。
	var background_path := ASSET_PATH
	var texture := ResourceLoader.load(
		background_path,
		"Texture2D",
	) as Texture2D
	_build_composite_background(texture)
	_add_header_clock_hands()

	var board_rect := _region_rect("settings_board")
	var board := _owner_control(
		self,
		Rect2(Vector2.ZERO, size),
		board_rect,
		"SettingsBoard",
		"settings_board",
		"page_shell",
		"ui.provider-settings.composite.page-user-reference.v1",
		"page-specific-composite"
	)
	_build_header(board, board_rect)
	_build_provider_selector(board, board_rect)
	_build_provider_detail(board, board_rect)


func _build_composite_background(texture: Texture2D) -> void:
	if _vertical_extra <= 0.0:
		_add_background_slice(
			texture,
			Rect2(Vector2.ZERO, SOURCE_SIZE),
			Rect2(Vector2.ZERO, size),
			"ProviderSettingsPageCompositeTexture",
		)
		return
	var scaled_top := _scaled_y(VERTICAL_STRETCH_SOURCE_TOP)
	var scaled_bottom := _scaled_y(VERTICAL_STRETCH_SOURCE_BOTTOM)
	_add_background_slice(
		texture,
		Rect2(0.0, 0.0, SOURCE_SIZE.x, VERTICAL_STRETCH_SOURCE_TOP),
		Rect2(0.0, 0.0, size.x, scaled_top),
		"ProviderSettingsPageCompositeTexture",
	)
	_add_vertical_fill_slice(
		texture,
		SETTINGS_BOARD_SOURCE_LEFT,
		SETTINGS_BOARD_SOURCE_DIVIDER,
		SELECTOR_STRETCH_SAMPLE_Y,
		scaled_top,
		scaled_bottom,
		"ProviderSettingsPageCompositeSelectorFill",
	)
	_add_vertical_fill_slice(
		texture,
		SETTINGS_BOARD_SOURCE_DIVIDER,
		SETTINGS_BOARD_SOURCE_RIGHT,
		DETAIL_STRETCH_SAMPLE_Y,
		scaled_top,
		scaled_bottom,
		"ProviderSettingsPageCompositeDetailFill",
	)
	_add_background_slice(
		texture,
		Rect2(
			0.0,
			VERTICAL_STRETCH_SOURCE_BOTTOM,
			SOURCE_SIZE.x,
			SOURCE_SIZE.y - VERTICAL_STRETCH_SOURCE_BOTTOM,
		),
		Rect2(
			0.0,
			scaled_bottom,
			size.x,
			size.y - scaled_bottom,
		),
		"ProviderSettingsPageCompositeBottom",
	)


func _add_vertical_fill_slice(
	texture: Texture2D,
	source_left: float,
	source_right: float,
	sample_y: float,
	target_top: float,
	target_bottom: float,
	node_name: String,
) -> void:
	_add_background_slice(
		texture,
		Rect2(
			source_left,
			sample_y,
			source_right - source_left,
			1.0,
		),
		Rect2(
			roundf(source_left * _scale.x),
			target_top,
			roundf((source_right - source_left) * _scale.x),
			target_bottom - target_top,
		),
		node_name,
	)


func _add_background_slice(
	texture: Texture2D,
	source_rect: Rect2,
	target_rect: Rect2,
	node_name: String,
) -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = source_rect
	var slice := TextureRect.new()
	slice.name = node_name
	slice.position = target_rect.position
	slice.size = target_rect.size
	slice.texture = atlas
	slice.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	slice.stretch_mode = TextureRect.STRETCH_SCALE
	slice.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	slice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(slice)


func _add_header_clock_hands() -> void:
	var texture := ResourceLoader.load(
		ProviderTheme.PROVIDER_CLOCK_HANDS_PATH,
		"Texture2D",
	) as Texture2D
	if texture == null:
		return
	var hands := TextureRect.new()
	hands.name = "ProviderClockHands"
	_place(
		hands,
		_scaled_rect(CLOCK_HANDS_RECT),
		Rect2(Vector2.ZERO, size),
	)
	hands.texture = texture
	hands.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hands.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hands.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hands.add_to_group("provider_settings_content_surface")
	hands.set_meta("gate_id", "provider_clock_hands")
	add_child(hands)


func _build_header(board: Control, board_rect: Rect2) -> void:
	var header_rect := _region_rect("header")
	var header := _owner_control(
		board,
		board_rect,
		header_rect,
		"Header",
		"header",
		"section_frame",
		"ui.provider-settings.composite.header-subregion.v1",
		"composite-subregion"
	)
	_add_slot_label(
		header,
		header_rect,
		"page_title",
		str(_data.get("pageTitle", "模型设置")),
		ProviderTheme.COMPOSITE_INK
	)
	var custom_layout := bool(
		_find_provider(_selected_provider_id).get("customGroup", false)
	)
	var formal_tone := _formal_status_tone()
	formal_badge = _add_slot_label(
		header,
		header_rect,
		"formal_status",
		_formal_status_text(),
		(
			_tone_color(formal_tone)
			if custom_layout
			else ProviderTheme.COMPOSITE_WARNING
		)
	)
	var back := _hit_button(
		header,
		header_rect,
		"back",
		"BackButton",
		"back",
		"operation_control",
		"ui.provider-settings.composite.back-control.v1"
	)
	back.tooltip_text = "返回"
	back.pressed.connect(func() -> void:
		ui_action.emit(&"provider_settings.back", {})
	)


func _add_formal_status_icon(
	parent: Control,
	parent_rect: Rect2,
	tone: String,
) -> void:
	var texture := ProviderTheme.provider_formal_status_texture(tone)
	if texture == null:
		return
	var icon := TextureRect.new()
	icon.name = "FormalStatusIcon"
	_place(icon, _scaled_rect(FORMAL_STATUS_ICON_RECT), parent_rect)
	icon.texture = texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.pivot_offset = icon.size * 0.5
	parent.add_child(icon)
	if tone == "loading":
		var tween := icon.create_tween().set_loops()
		tween.tween_property(icon, "rotation", TAU, 1.2)
		tween.tween_callback(func() -> void: icon.rotation = 0.0)


func _add_back_arrow(button: BaseButton) -> void:
	var texture := ProviderTheme.provider_back_arrow_texture()
	if texture == null:
		return
	var icon := TextureRect.new()
	icon.name = "BackArrowArt"
	var absolute_rect := _scaled_rect(BACK_ARROW_RECT)
	var button_rect := _hit_rect("back")
	icon.position = absolute_rect.position - button_rect.position
	icon.size = absolute_rect.size
	icon.texture = texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)


func _build_provider_selector(
	board: Control,
	board_rect: Rect2
) -> void:
	var selector_rect := _region_rect("provider_selector")
	provider_selector = _owner_control(
		board,
		board_rect,
		selector_rect,
		"ProviderSelector",
		"provider_selector",
		"section_frame",
		"ui.provider-settings.composite.provider-selector.v1",
		"composite-subregion"
	)
	_add_slot_label(
		provider_selector,
		selector_rect,
		"provider_section",
		"服务商",
		ProviderTheme.COMPOSITE_INK
	)
	var providers := _data.get("providers", []) as Array
	var page_count := _page_count(providers.size(), PROVIDERS_PER_PAGE)
	_provider_page = clampi(_provider_page, 0, page_count - 1)
	var page_start := _provider_page * PROVIDERS_PER_PAGE
	var page_end := mini(page_start + PROVIDERS_PER_PAGE, providers.size())
	for index: int in range(page_end - page_start):
		var provider := providers[page_start + index] as Dictionary
		var provider_id := str(provider.get("providerId", ""))
		var card_rect := _hit_rect("provider_%d" % index)
		var card := _hit_button_from_rect(
			provider_selector,
			selector_rect,
			card_rect,
			"Provider_%s" % provider_id,
			"provider_%s" % provider_id,
			"content_slot",
			(
				"ui.provider-settings.composite.provider-card-%d.v1"
				% index
			),
			"composite-subregion"
		)
		card.disabled = not _action_enabled("selectProvider")
		card.tooltip_text = "选择 %s" % str(
			provider.get("displayName", "")
		)
		card.pressed.connect(func() -> void:
			ui_action.emit(
				&"provider_settings.select_provider",
				{"providerId": provider_id}
			)
		)
		var connection := (
			provider.get("connection", {}) as Dictionary
		)
		_apply_provider_card_skin(card, provider, connection)
		_add_provider_identity_medallion(
			card,
			card_rect,
			provider_id,
			bool(provider.get("customGroup", false)),
		)
		_add_slot_label(
			card,
			card_rect,
			"provider_%d_name" % index,
			str(provider.get("displayName", "")),
			ProviderTheme.COMPOSITE_INK
		)
		_add_slot_label(
			card,
			card_rect,
			"provider_%d_status" % index,
			_compact_provider_status_label(
				str(connection.get("status", "not_configured")),
				str(connection.get("label", "待配置"))
			),
			_status_color(str(connection.get("status", "")))
		)
		var toggle := _hit_button(
			card,
			card_rect,
			"provider_toggle_%d" % index,
			"ProviderToggle_%s" % provider_id,
			"provider_toggle_%s" % provider_id,
			"operation_control",
			(
				"ui.provider-settings.composite.provider-toggle-%d.v1"
				% index
			)
		)
		toggle.disabled = (
			not _action_enabled("setProviderEnabled")
			or _operation_loading()
		)
		toggle.tooltip_text = (
			"停用 %s" if bool(provider.get("enabled", false))
			else "启用 %s"
		) % str(provider.get("displayName", "Provider"))
		_decorate_toggle(
			toggle,
			bool(provider.get("enabled", false)),
		)
		toggle.pressed.connect(func() -> void:
			ui_action.emit(
				&"provider_settings.set_enabled",
				{
					"providerId": provider_id,
					"enabled": not bool(
						provider.get("enabled", false)
					),
				}
			)
		)

	var summary_rect := _region_rect("provider_summary")
	var summary_owner := _owner_control(
		provider_selector,
		selector_rect,
		summary_rect,
		"ProviderSummary",
		"provider_summary",
		"content_slot",
		"ui.provider-settings.composite.provider-summary.v1",
		"composite-subregion"
	)
	var summary := _data.get("summary", {}) as Dictionary
	_add_slot_label(
		summary_owner,
		summary_rect,
		"provider_summary",
		"可用 %d · 已启用模型 %d"
		% [
			int(summary.get("availableProviderCount", 0)),
			int(summary.get("enabledModelCount", 0)),
		],
		ProviderTheme.COMPOSITE_MUTED
	)
	_add_slot_label(
		summary_owner,
		summary_rect,
		"provider_page",
		"%d / %d" % [_provider_page + 1, page_count],
		ProviderTheme.COMPOSITE_INK
	)
	var previous := _pagination_button(
		summary_owner,
		summary_rect,
		"provider_page_previous",
		"ProviderPagePrevious",
		"上一页服务商",
		false,
		_provider_page <= 0,
	)
	previous.pressed.connect(func() -> void:
		_change_provider_page(_provider_page - 1)
	)
	var next := _pagination_button(
		summary_owner,
		summary_rect,
		"provider_page_next",
		"ProviderPageNext",
		"下一页服务商",
		true,
		_provider_page >= page_count - 1,
	)
	next.pressed.connect(func() -> void:
		_change_provider_page(_provider_page + 1)
	)


func _build_provider_detail(
	board: Control,
	board_rect: Rect2
) -> void:
	var detail_rect := _region_rect("provider_detail")
	provider_detail = _owner_control(
		board,
		board_rect,
		detail_rect,
		"ProviderDetail",
		"provider_detail",
		"section_frame",
		"ui.provider-settings.composite.provider-detail.v1",
		"composite-subregion"
	)
	var provider := _find_provider(_selected_provider_id)
	if provider.is_empty():
		return
	_build_selected_header(provider, detail_rect)
	if bool(provider.get("customGroup", false)):
		_build_key_section(provider, detail_rect)
		_build_base_url_section(provider, detail_rect)
	else:
		_build_key_section(provider, detail_rect)
		_build_base_url_section(provider, detail_rect)
	_build_models_section(provider, detail_rect)
	_build_connection_section(provider, detail_rect)


func _build_selected_header(
	provider: Dictionary,
	detail_rect: Rect2
) -> void:
	var region_rect := _region_rect("selected_provider_header")
	var owner := _owner_control(
		provider_detail,
		detail_rect,
		region_rect,
		"ProviderHeaderPanel",
		"selected_provider_header",
		"content_slot",
		"ui.provider-settings.composite.selected-provider-header.v1",
		"composite-subregion"
	)
	if bool(provider.get("customGroup", false)):
		_build_custom_connection_selector(provider, owner, region_rect)
	else:
		_add_slot_label(
			owner,
			region_rect,
			"selected_provider",
			str(provider.get("displayName", "Provider")),
			ProviderTheme.COMPOSITE_INK
		)
	var toggle := _hit_button(
		provider_detail,
		detail_rect,
		"selected_provider_toggle",
		"ProviderEnabledButton",
		"provider_enabled",
		"operation_control",
		"ui.provider-settings.composite.selected-provider-toggle.v1"
	)
	toggle.disabled = (
		not _action_enabled("setProviderEnabled")
		or _operation_loading()
	)
	toggle.tooltip_text = (
		"停用当前 Provider"
		if bool(provider.get("enabled", false))
		else "启用当前 Provider"
	)
	_decorate_toggle(
		toggle,
		bool(provider.get("enabled", false)),
	)
	toggle.pressed.connect(func() -> void:
		ui_action.emit(
			&"provider_settings.set_enabled",
			{
				"providerId": str(provider.get("providerId", "")),
				"enabled": not bool(provider.get("enabled", false)),
			}
		)
	)


func _build_custom_connection_selector(
	provider: Dictionary,
	owner: Control,
	region_rect: Rect2,
) -> void:
	var slot := _slots.get("selected_provider", {}) as Dictionary
	var target_rect := _scaled_rect(
		_rect(slot.get("wellRect", slot.get("rect", [])))
	)
	var connections := provider.get("customConnections", []) as Array
	var selected_name := "自定义模型"
	for connection_value: Variant in connections:
		var connection := connection_value as Dictionary
		if str(connection.get("providerId", "")) == str(
			provider.get("providerId", "")
		):
			selected_name = str(connection.get("displayName", "兼容接口"))
			break
	var selector := Button.new()
	selector.name = "CustomConnectionSelector"
	_place(selector, target_rect, region_rect)
	selector.focus_mode = Control.FOCUS_ALL
	selector.mouse_filter = Control.MOUSE_FILTER_STOP
	selector.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	selector.text = ""
	for state: String in [
		"normal",
		"hover",
		"pressed",
		"hover_pressed",
		"focus",
		"disabled",
	]:
		selector.add_theme_stylebox_override(
			state,
			ProviderTheme.transparent_input_style(),
		)
	selector.add_theme_constant_override("outline_size", 0)
	selector.add_theme_constant_override("h_separation", 0)
	selector.add_to_group("provider_settings_touch_target")
	selector.set_meta("gate_id", "custom_connection_selector")
	_register_owner(
		selector,
		"custom_connection_selector",
		"operation_control",
		"ui.provider-settings.composite.custom-connection-selector.v1",
		"composite-transparent-control",
	)
	_mark_surface(selector)
	owner.add_child(selector)
	_add_slot_label(
		owner,
		region_rect,
		"selected_provider",
		"自定义模型 · %s" % selected_name,
		ProviderTheme.COMPOSITE_INK,
	)
	_add_custom_selector_chevron(selector)
	var dropdown := PopupPanel.new()
	dropdown.name = "CustomConnectionDropdown"
	var dropdown_row_count := connections.size() + 1
	if bool(provider.get("deletableConnection", false)):
		dropdown_row_count += 2
	var dropdown_rect := _scaled_rect(Rect2(
		662.0,
		274.0,
		636.0,
		208.0,
	))
	dropdown.add_theme_stylebox_override(
		"panel",
		ProviderTheme.custom_dropdown_panel_style(),
	)
	dropdown.position = Vector2i(dropdown_rect.position.round())
	dropdown.size = Vector2i(dropdown_rect.size.round())
	dropdown.unresizable = true
	dropdown.exclusive = false
	dropdown.set_meta("gate_id", "custom_connection_dropdown")
	add_child(dropdown)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var popup_margin := _scaled_spacing(6.0)
	scroll.offset_left = popup_margin
	scroll.offset_top = popup_margin
	scroll.offset_right = -popup_margin
	scroll.offset_bottom = -popup_margin
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	dropdown.add_child(scroll)
	var scroll_bar := scroll.get_v_scroll_bar()
	scroll_bar.custom_minimum_size.x = _scaled_spacing(20.0)
	scroll_bar.add_theme_constant_override(
		"minimum_grabber_size",
		int(_scaled_spacing(48.0)),
	)
	for style_name: String in ["scroll", "scroll_focus"]:
		scroll_bar.add_theme_stylebox_override(
			style_name,
			ProviderTheme.custom_dropdown_scroll_track_style(),
		)
	for style_name: String in [
		"grabber",
		"grabber_highlight",
		"grabber_pressed",
	]:
		scroll_bar.add_theme_stylebox_override(
			style_name,
			ProviderTheme.custom_dropdown_scroll_thumb_style(),
		)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	rows.custom_minimum_size.y = _scaled_spacing(48.0 * dropdown_row_count)
	rows.add_theme_constant_override("separation", 0)
	scroll.add_child(rows)
	for connection_value: Variant in connections:
		var connection := connection_value as Dictionary
		_add_custom_selector_row(
			rows,
			str(connection.get("displayName", "兼容接口")),
			str(connection.get("providerId", "")),
			str(connection.get("providerId", "")) == str(
				provider.get("providerId", "")
			),
			dropdown,
		)
	_add_custom_selector_action_row(
		rows,
		"＋ 新建兼容连接",
		"create",
		provider,
		dropdown,
	)
	if bool(provider.get("deletableConnection", false)):
		_add_custom_selector_action_row(
			rows,
			"重命名当前连接",
			"rename",
			provider,
			dropdown,
		)
		_add_custom_selector_action_row(
			rows,
			"删除当前兼容连接",
			"delete",
			provider,
			dropdown,
		)
	_hide_custom_selector_last_separator(rows)
	selector.pressed.connect(
		_toggle_custom_connection_dropdown.bind(dropdown, dropdown_rect)
	)


func _toggle_custom_connection_dropdown(
	dropdown: PopupPanel,
	dropdown_rect: Rect2,
) -> void:
	if dropdown == null or not is_instance_valid(dropdown):
		return
	if dropdown.visible:
		dropdown.hide()
		return
	var popup_rect := Rect2i(
		Vector2i(dropdown_rect.position.round()),
		Vector2i(dropdown_rect.size.round()),
	)
	dropdown.popup(popup_rect)
	var first_row := dropdown.find_child(
		"CustomConnection_*",
		true,
		false,
	) as Control
	if first_row != null and first_row.focus_mode != Control.FOCUS_NONE:
		first_row.grab_focus()


func _add_custom_selector_chevron(selector: Button) -> void:
	var texture := ProviderTheme.custom_connection_chevron_texture()
	if texture == null:
		return
	var chevron := TextureRect.new()
	chevron.name = "CustomConnectionChevron"
	chevron.position = Vector2(
		selector.size.x - _scaled_spacing(48.0),
		(selector.size.y - _scaled_spacing(18.0)) * 0.5,
	)
	chevron.size = Vector2(_scaled_spacing(28.0), _scaled_spacing(18.0))
	chevron.texture = texture
	chevron.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chevron.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chevron.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selector.add_child(chevron)


func _add_custom_selector_row(
	rows: VBoxContainer,
	display_name: String,
	provider_id: String,
	selected: bool,
	dropdown: Window,
) -> void:
	var row := Button.new()
	row.name = "CustomConnection_%s" % provider_id
	row.text = ""
	row.clip_contents = true
	row.custom_minimum_size = Vector2(0.0, _scaled_spacing(48.0))
	row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_style_custom_selector_row(row, selected)
	_add_custom_selector_row_label(row, display_name, selected)
	_add_custom_selector_row_separator(row)
	if selected:
		var check := Label.new()
		check.name = "SelectedCheck"
		check.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		check.offset_left = -_scaled_spacing(52.0)
		check.offset_right = -_scaled_spacing(18.0)
		check.text = "✓"
		check.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		check.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		check.add_theme_font_override(
			"font",
			ProviderTheme.composite_font("body"),
		)
		check.add_theme_font_size_override("font_size", _scaled_font_size(24))
		check.add_theme_color_override(
			"font_color",
			ProviderTheme.COMPOSITE_SUCCESS,
		)
		check.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(check)
	row.pressed.connect(func() -> void:
		dropdown.visible = false
		ui_action.emit(
			&"provider_settings.select_provider",
			{"providerId": provider_id},
		)
	)
	rows.add_child(row)


func _add_custom_selector_action_row(
	rows: VBoxContainer,
	label: String,
	action: String,
	provider: Dictionary,
	dropdown: Window,
) -> void:
	var row := Button.new()
	row.name = "CustomConnectionAction_%s" % action
	row.text = ""
	row.clip_contents = true
	row.custom_minimum_size = Vector2(0.0, _scaled_spacing(48.0))
	row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_style_custom_selector_row(row, false)
	_add_custom_selector_row_label(row, label, false)
	_add_custom_selector_row_separator(row)
	row.pressed.connect(func() -> void:
		dropdown.visible = false
		if action == "create":
			ui_action.emit(
				&"ui.request_create_compatible_connection",
				{},
			)
		elif action == "rename":
			ui_action.emit(
				&"ui.request_rename_compatible_connection",
				{
					"providerId": str(provider.get("providerId", "")),
					"displayName": str(
						provider.get("displayName", "兼容接口")
					),
				},
			)
		else:
			ui_action.emit(
				&"ui.request_delete_compatible_connection",
				{
					"providerId": str(provider.get("providerId", "")),
					"displayName": str(provider.get("displayName", "兼容接口")),
				},
			)
	)
	rows.add_child(row)


func _add_custom_selector_row_separator(row: Control) -> void:
	var separator_shadow := ColorRect.new()
	separator_shadow.name = "RowSeparatorShadow"
	separator_shadow.anchor_top = 1.0
	separator_shadow.anchor_right = 1.0
	separator_shadow.anchor_bottom = 1.0
	separator_shadow.offset_left = _scaled_spacing(8.0)
	separator_shadow.offset_top = -_scaled_spacing(2.0)
	separator_shadow.offset_right = -_scaled_spacing(24.0)
	separator_shadow.offset_bottom = -_scaled_spacing(1.0)
	separator_shadow.color = Color("a56e32")
	separator_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(separator_shadow)
	var separator_light := ColorRect.new()
	separator_light.name = "RowSeparatorLight"
	separator_light.anchor_top = 1.0
	separator_light.anchor_right = 1.0
	separator_light.anchor_bottom = 1.0
	separator_light.offset_left = _scaled_spacing(8.0)
	separator_light.offset_top = -_scaled_spacing(1.0)
	separator_light.offset_right = -_scaled_spacing(24.0)
	separator_light.offset_bottom = 0.0
	separator_light.color = Color("f2cd9e")
	separator_light.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(separator_light)


func _hide_custom_selector_last_separator(rows: Control) -> void:
	if rows.get_child_count() <= 0:
		return
	var last_row := rows.get_child(rows.get_child_count() - 1) as Control
	if last_row == null:
		return
	for separator_name: String in ["RowSeparatorShadow", "RowSeparatorLight"]:
		var separator := last_row.get_node_or_null(separator_name) as Control
		if separator != null:
			separator.visible = false


func _style_custom_selector_row(row: Button, selected: bool) -> void:
	row.add_theme_font_override("font", ProviderTheme.composite_font("body"))
	row.add_theme_font_size_override("font_size", _scaled_font_size(22))
	for color_id: String in [
		"font_color", "font_hover_color", "font_pressed_color", "font_focus_color",
	]:
		row.add_theme_color_override(
			color_id,
			ProviderTheme.COMPOSITE_SUCCESS if selected else ProviderTheme.COMPOSITE_INK,
		)
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style: StyleBox = ProviderTheme.custom_dropdown_neutral_row_style()
		if selected:
			style = ProviderTheme.custom_dropdown_selected_style()
		row.add_theme_stylebox_override(state, style)


func _add_custom_selector_row_label(
	row: Button,
	text_value: String,
	selected: bool,
) -> void:
	var label := Label.new()
	label.name = "RowLabel"
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_left = _scaled_spacing(18.0)
	label.offset_right = -_scaled_spacing(54.0 if selected else 18.0)
	label.text = text_value
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_override("font", ProviderTheme.composite_font("body"))
	label.add_theme_font_size_override("font_size", _scaled_font_size(20))
	label.add_theme_color_override(
		"font_color",
		ProviderTheme.COMPOSITE_SUCCESS if selected else ProviderTheme.COMPOSITE_INK,
	)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)


func _build_custom_connection_section(
	provider: Dictionary,
	detail_rect: Rect2,
) -> void:
	if str(provider.get("providerId", "")) == "302-ai":
		_build_key_section(provider, detail_rect)
		return
	var provider_id := str(provider.get("providerId", ""))
	var compatible := (
		provider_id == "openai-compatible"
		or provider_id == "ollama-cloud"
		or bool(provider.get("deletableConnection", false))
	)
	var region_rect := _region_rect("api_key_section")
	var owner := _custom_section_owner(
		region_rect,
		detail_rect,
		"CustomConnectionPanel",
		"custom_connection_section",
		(
			"custom_connection_two_row"
			if compatible
			else "custom_connection"
		),
	)
	if compatible:
		_build_custom_connection_label(
			owner,
			region_rect,
			CUSTOM_OTHER_HEADING_RECT,
			"连接设置",
			"custom_connection_heading",
		)
		_build_custom_connection_label(
			owner,
			region_rect,
			CUSTOM_OTHER_BASE_LABEL_RECT,
			"Base URL",
			"custom_base_url_label",
		)
		base_url_edit = _custom_connection_input(
			owner,
			region_rect,
			CUSTOM_OTHER_BASE_INPUT_RECT,
			"BaseUrlInput",
			"custom_base_url_input",
		)
		_configure_custom_base_url_edit(provider, base_url_edit)
		_build_custom_connection_label(
			owner,
			region_rect,
			CUSTOM_OTHER_KEY_LABEL_RECT,
			"API Key",
			"custom_api_key_label",
		)
		key_edit = _custom_connection_input(
			owner,
			region_rect,
			CUSTOM_OTHER_KEY_INPUT_RECT,
			"ApiKeyInput",
			"custom_api_key_input",
		)
		_configure_custom_key_edit(provider, key_edit)
		_add_custom_compatible_actions(provider, owner, region_rect)
		return
	_build_custom_connection_label(
		owner,
		region_rect,
		CUSTOM_LOCAL_CONNECTION_HEADING_RECT,
		"连接设置",
		"custom_connection_heading",
	)
	_build_custom_connection_label(
		owner,
		region_rect,
		CUSTOM_LOCAL_BASE_LABEL_RECT,
		"Base URL",
		"custom_base_url_label",
	)
	base_url_edit = _custom_connection_input(
		owner,
		region_rect,
		CUSTOM_LOCAL_BASE_INPUT_RECT,
		"BaseUrlInput",
		"custom_base_url_input",
	)
	_configure_custom_base_url_edit(provider, base_url_edit)
	_add_custom_connection_save_button(
		provider,
		owner,
		region_rect,
		CUSTOM_LOCAL_SAVE_RECT,
	)


func _build_custom_model_add_section(
	provider: Dictionary,
	detail_rect: Rect2,
) -> void:
	var region_rect := _region_rect("base_url_section")
	var owner := _custom_section_owner(
		region_rect,
		detail_rect,
		"CustomModelAddPanel",
		"custom_model_add_section",
		"custom_model_add",
	)
	var compatible := (
		str(provider.get("providerId", "")) == "openai-compatible"
		or bool(provider.get("deletableConnection", false))
	)
	var label_rect := (
		CUSTOM_OTHER_MODEL_LABEL_RECT
		if compatible
		else CUSTOM_LOCAL_ADD_HEADING_RECT
	)
	var input_rect := (
		CUSTOM_OTHER_MODEL_INPUT_RECT
		if compatible
		else CUSTOM_LOCAL_MODEL_INPUT_RECT
	)
	var add_rect := (
		CUSTOM_OTHER_MODEL_ADD_RECT
		if compatible
		else CUSTOM_LOCAL_ADD_RECT
	)
	var discover_rect := (
		CUSTOM_OTHER_MODEL_DISCOVER_RECT
		if compatible
		else CUSTOM_LOCAL_DISCOVER_RECT
	)
	_build_custom_connection_label(
		owner,
		region_rect,
		label_rect,
		"添加模型",
		"custom_model_add_label",
	)
	if not compatible:
		_build_custom_connection_label(
			owner,
			region_rect,
			CUSTOM_LOCAL_MODEL_LABEL_RECT,
			"模型 ID",
			"custom_model_id_label",
		)
	api_model_edit = _custom_connection_input(
		owner,
		region_rect,
		input_rect,
		"ApiModelInput",
		"api_model_input",
	)
	api_model_edit.text = _draft_api_model
	api_model_edit.placeholder_text = _custom_model_placeholder(provider)
	var add := _custom_action_button(
		owner,
		region_rect,
		add_rect,
		"AddApiModelButton",
		"api_model_add",
		"添加",
		"success",
	)
	add.disabled = (
		_draft_api_model.strip_edges().is_empty()
		or not _action_enabled("saveApiModel")
		or _operation_loading()
	)
	add.tooltip_text = "添加并选用这个模型 ID"
	add.pressed.connect(func() -> void:
		ui_action.emit(
			&"provider_settings.save_api_model",
			{
				"providerId": str(provider.get("providerId", "")),
				"apiModel": api_model_edit.text,
			},
		)
	)
	api_model_edit.text_changed.connect(func(value: String) -> void:
		_draft_api_model = value
		ui_action.emit(&"ui.draft_api_model", {"value": value})
		add.disabled = (
			value.strip_edges().is_empty()
			or not _action_enabled("saveApiModel")
			or _operation_loading()
		)
	)
	api_model_edit.text_submitted.connect(func(value: String) -> void:
		if not add.disabled:
			ui_action.emit(
				&"provider_settings.save_api_model",
				{
					"providerId": str(provider.get("providerId", "")),
					"apiModel": value,
				},
			)
	)
	var discover := _custom_action_button(
		owner,
		region_rect,
		discover_rect,
		"DiscoverModelsButton",
		"api_model_discover",
		"获取模型",
		"quiet",
	)
	discover.disabled = (
		not _action_enabled("discoverModels")
		or _operation_loading()
		or (
			bool(provider.get("authRequired", true))
			and not bool(
				(provider.get("key", {}) as Dictionary).get("saved", false)
			)
		)
	)
	discover.tooltip_text = "从当前连接获取模型列表；失败时仍可手动填写"
	discover.pressed.connect(func() -> void:
		ui_action.emit(
			&"provider_settings.discover_models",
			{"providerId": str(provider.get("providerId", ""))},
		)
	)
	var discovered_models := provider.get("discoveredModels", []) as Array
	if not discovered_models.is_empty():
		_build_discovered_model_panel(provider, discovered_models, add)


func _build_discovered_model_panel(
	provider: Dictionary,
	discovered_models: Array,
	add_button: Button,
) -> void:
	var texture := ProviderTheme.custom_model_discovery_texture()
	if texture == null:
		return
	var panel_rect := _scaled_rect(Rect2(690.0, 512.0, 580.0, 126.0))
	var panel := Control.new()
	panel.name = "DiscoveredModelPanel"
	panel.position = panel_rect.position
	panel.size = panel_rect.size
	panel.z_index = 40
	panel.z_as_relative = false
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_to_group("provider_settings_content_surface")
	panel.set_meta("gate_id", "discovered_model_panel")
	_register_owner(
		panel,
		"discovered_model_panel",
		"operation_control",
		"ui.provider-settings.custom-model-discovery-panel.v1",
		"imagegen_dropdown_panel",
	)
	add_child(panel)

	var art := TextureRect.new()
	art.name = "DiscoveredModelPanelArt"
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(art)

	var scroll := ScrollContainer.new()
	scroll.name = "DiscoveredModelScroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.add_theme_stylebox_override("panel", ProviderTheme.empty_style())
	panel.add_child(scroll)

	var rows := VBoxContainer.new()
	rows.name = "DiscoveredModelRows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 0)
	rows.custom_minimum_size = Vector2(
		panel_rect.size.x,
		maxf(panel_rect.size.y, panel_rect.size.y / 3.0 * discovered_models.size()),
	)
	scroll.add_child(rows)
	var provider_label := _custom_model_discovery_source_label(provider)
	for value: Variant in discovered_models:
		if typeof(value) != TYPE_STRING:
			continue
		var model_id := String(value).strip_edges()
		if model_id.is_empty():
			continue
		_add_discovered_model_row(
			rows,
			model_id,
			provider_label,
			panel_rect.size.y / 3.0,
			panel,
			add_button,
		)


func _add_discovered_model_row(
	parent: VBoxContainer,
	model_id: String,
	provider_label: String,
	row_height: float,
	panel: Control,
	add_button: Button,
) -> void:
	var row := Control.new()
	row.custom_minimum_size = Vector2(0.0, row_height)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(row)

	var button := Button.new()
	button.name = "DiscoveredModel_%s" % model_id.validate_node_name()
	button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state: String in [
		"normal",
		"hover",
		"pressed",
		"hover_pressed",
		"focus",
		"disabled",
	]:
		button.add_theme_stylebox_override(state, ProviderTheme.empty_style())
	row.add_child(button)

	var model_label := Label.new()
	model_label.anchor_right = 1.0
	model_label.offset_left = _design_scale * 16.0
	model_label.offset_right = -_design_scale * 140.0
	model_label.offset_bottom = row_height
	model_label.text = model_id
	model_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	model_label.add_theme_font_override("font", ProviderTheme.composite_font("body"))
	model_label.add_theme_font_size_override("font_size", _scaled_font_size(19))
	model_label.add_theme_color_override("font_color", ProviderTheme.COMPOSITE_INK)
	model_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(model_label)

	var source_label := Label.new()
	source_label.anchor_left = 1.0
	source_label.anchor_right = 1.0
	source_label.offset_left = -_design_scale * 130.0
	source_label.offset_right = -_design_scale * 18.0
	source_label.offset_bottom = row_height
	source_label.text = provider_label
	source_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	source_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	source_label.add_theme_font_override("font", ProviderTheme.composite_font("body"))
	source_label.add_theme_font_size_override("font_size", _scaled_font_size(15))
	source_label.add_theme_color_override("font_color", ProviderTheme.COMPOSITE_MUTED)
	source_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(source_label)

	button.pressed.connect(func() -> void:
		_draft_api_model = model_id
		api_model_edit.text = model_id
		api_model_edit.caret_column = model_id.length()
		add_button.disabled = false
		ui_action.emit(&"ui.draft_api_model", {"value": model_id})
		panel.queue_free()
		api_model_edit.grab_focus()
	)


func _custom_section_owner(
	region_rect: Rect2,
	detail_rect: Rect2,
	node_name: String,
	gate_id: String,
	section_id: String,
) -> Control:
	var panel := Control.new()
	panel.name = node_name
	_place(panel, region_rect, detail_rect)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_to_group("provider_settings_region")
	panel.set_meta("gate_id", gate_id)
	_register_owner(
		panel,
		gate_id,
		"section_frame",
		"ui.provider-settings.%s.v2" % section_id.replace("_", "-"),
		"imagegen-composite-background-owner",
	)
	_mark_surface(panel)
	provider_detail.add_child(panel)
	return panel


func _build_custom_connection_label(
	parent: Control,
	parent_rect: Rect2,
	source_rect: Rect2,
	text_value: String,
	gate_id: String,
) -> Label:
	var label := Label.new()
	label.name = gate_id.to_pascal_case()
	label.text = text_value
	_place(label, _scaled_rect(source_rect), parent_rect)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override(
		"font",
		ProviderTheme.composite_font("small"),
	)
	label.add_theme_font_size_override("font_size", _scaled_font_size(20))
	label.add_theme_color_override("font_color", ProviderTheme.COMPOSITE_INK)
	label.add_to_group("provider_settings_text_slot")
	label.set_meta("gate_id", gate_id)
	parent.add_child(label)
	return label


func _custom_connection_input(
	parent: Control,
	parent_rect: Rect2,
	source_rect: Rect2,
	node_name: String,
	gate_id: String,
	draw_background: bool = false,
) -> LineEdit:
	var edit := LineEdit.new()
	edit.name = node_name
	_place(edit, _scaled_rect(source_rect), parent_rect)
	edit.focus_mode = Control.FOCUS_ALL
	edit.add_theme_font_override(
		"font",
		ProviderTheme.composite_font("body"),
	)
	edit.add_theme_font_size_override("font_size", _scaled_font_size(21))
	edit.add_theme_color_override("font_color", ProviderTheme.COMPOSITE_INK)
	edit.add_theme_color_override(
		"font_placeholder_color",
		ProviderTheme.COMPOSITE_MUTED,
	)
	for state: String in ["normal", "focus", "read_only"]:
		var style: StyleBox = (
			ProviderTheme.custom_input_field_style()
			if draw_background
			else ProviderTheme.custom_input_overlay_style(state == "focus")
		)
		edit.add_theme_stylebox_override(state, style)
	edit.add_to_group("provider_settings_touch_target")
	edit.set_meta("gate_id", gate_id)
	_register_owner(
		edit,
		gate_id,
		"content_slot",
		"ui.provider-settings.content-slot.v1",
		"composite-input",
	)
	_mark_surface(edit)
	parent.add_child(edit)
	return edit


func _configure_custom_base_url_edit(
	provider: Dictionary,
	edit: LineEdit,
) -> void:
	edit.text = (
		_draft_base_url
		if not _draft_base_url.is_empty()
		else str(provider.get("defaultBaseUrl", ""))
	)
	edit.placeholder_text = "例如 http://localhost:11434/v1"
	edit.text_changed.connect(func(value: String) -> void:
		ui_action.emit(&"ui.draft_base_url", {"value": value})
	)


func _configure_custom_key_edit(
	provider: Dictionary,
	edit: LineEdit,
) -> void:
	var key_data := provider.get("key", {}) as Dictionary
	edit.secret = not _show_key
	edit.secret_character = "•"
	edit.text = _draft_key
	edit.placeholder_text = (
		str(key_data.get("maskedValue", "••••••••••••"))
		if bool(key_data.get("saved", false))
		else "请输入 API Key"
	)
	edit.text_changed.connect(func(value: String) -> void:
		ui_action.emit(&"ui.draft_key", {"value": value})
		var reveal := edit.get_parent().find_child(
			"RevealCustomKeyButton",
			true,
			false,
		) as Button
		if reveal != null:
			reveal.disabled = (
				value.is_empty()
				and not bool(key_data.get("saved", false))
			)
	)


func _add_custom_compatible_actions(
	provider: Dictionary,
	parent: Control,
	parent_rect: Rect2,
) -> void:
	var key_data := provider.get("key", {}) as Dictionary
	var save := _custom_action_button(
		parent,
		parent_rect,
		CUSTOM_OTHER_SAVE_RECT,
		"SaveCustomConnectionButton",
		"custom_connection_save",
		"保存连接",
		"success",
	)
	save.disabled = (
		not _action_enabled("saveConnection")
		or _operation_loading()
		or (
			bool(provider.get("authRequired", true))
			and _draft_key.is_empty()
			and not bool(key_data.get("saved", false))
		)
	)
	save.tooltip_text = "保存连接"
	save.pressed.connect(func() -> void:
		ui_action.emit(
			&"provider_settings.save_connection",
			{
				"providerId": str(provider.get("providerId", "")),
				"baseUrl": base_url_edit.text if base_url_edit != null else "",
				"apiKey": key_edit.text if key_edit != null else "",
			},
		)
	)
	var reveal := _custom_icon_button(
		parent,
		parent_rect,
		CUSTOM_OTHER_REVEAL_RECT,
		"RevealCustomKeyButton",
		"custom_key_reveal",
		ProviderTheme.custom_key_reveal_texture(),
	)
	reveal.disabled = (
		_draft_key.is_empty()
		and not bool(key_data.get("saved", false))
	)
	reveal.tooltip_text = "隐藏 Key" if _show_key else "显示 Key"
	reveal.pressed.connect(func() -> void:
		ui_action.emit(&"ui.toggle_key_visibility", {})
	)
	var delete := _custom_icon_button(
		parent,
		parent_rect,
		CUSTOM_OTHER_DELETE_RECT,
		"DeleteCustomKeyButton",
		"custom_key_delete",
		ProviderTheme.custom_key_delete_texture(),
	)
	delete.disabled = (
		not _action_enabled("deleteKey")
		or not bool(key_data.get("saved", false))
		or _operation_loading()
	)
	delete.tooltip_text = "删除已保存的 API Key"
	delete.pressed.connect(func() -> void:
		ui_action.emit(
			&"provider_settings.delete_key",
			{"providerId": str(provider.get("providerId", ""))},
		)
	)


func _custom_icon_button(
	parent: Control,
	parent_rect: Rect2,
	source_rect: Rect2,
	node_name: String,
	gate_id: String,
	art_texture: Texture2D,
) -> Button:
	var button := Button.new()
	button.name = node_name
	_place(button, _scaled_rect(source_rect), parent_rect)
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_to_group("provider_settings_touch_target")
	button.set_meta("gate_id", gate_id)
	_register_owner(
		button,
		gate_id,
		"operation_control",
		"ui.provider-settings.custom-model-delete.v1",
		"texture-button",
	)
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(
			state,
			ProviderTheme.transparent_hit_style(state),
		)
	parent.add_child(button)
	if art_texture != null:
		_add_button_art(button, art_texture, "ActionArt")
	ProviderButtonMotion.attach(button)
	return button


func _add_button_art(
	button: BaseButton,
	art_texture: Texture2D,
	art_name: String,
) -> void:
	var art := TextureRect.new()
	art.name = art_name
	_apply_visual_rect(art, button)
	art.texture = art_texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(art)


func _add_custom_connection_save_button(
	provider: Dictionary,
	parent: Control,
	parent_rect: Rect2,
	source_rect: Rect2,
) -> void:
	var save := _custom_action_button(
		parent,
		parent_rect,
		source_rect,
		"SaveCustomConnectionButton",
		"custom_connection_save",
		"保存连接",
		"success",
	)
	var key_data := provider.get("key", {}) as Dictionary
	save.disabled = (
		not _action_enabled("saveConnection")
		or _operation_loading()
		or (
			bool(provider.get("authRequired", true))
			and _draft_key.is_empty()
			and not bool(key_data.get("saved", false))
		)
	)
	save.tooltip_text = "保存当前连接地址和凭证"
	save.pressed.connect(func() -> void:
		ui_action.emit(
			&"provider_settings.save_connection",
			{
				"providerId": str(provider.get("providerId", "")),
				"baseUrl": base_url_edit.text if base_url_edit != null else "",
				"apiKey": key_edit.text if key_edit != null else "",
			},
		)
	)


func _custom_action_button(
	parent: Control,
	parent_rect: Rect2,
	source_rect: Rect2,
	node_name: String,
	gate_id: String,
	text_value: String,
	variant: String,
) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text_value
	_place(button, _scaled_rect(source_rect), parent_rect)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_override(
		"font",
		ProviderTheme.composite_font("small"),
	)
	button.add_theme_font_size_override("font_size", _scaled_font_size(20))
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := ProviderTheme.exact_action_button_style(
			gate_id,
			"disabled" if state == "disabled" else "normal",
		)
		button.add_theme_stylebox_override(
			state,
			style,
		)
	for color_id: String in [
		"font_color",
		"font_hover_color",
		"font_pressed_color",
		"font_focus_color",
	]:
		button.add_theme_color_override(
			color_id,
			(
				ProviderTheme.COMPOSITE_INK
				if variant == "quiet"
				else ProviderTheme.PAPER_LIGHT
			),
		)
	button.add_theme_color_override(
		"font_disabled_color",
		ProviderTheme.COMPOSITE_MUTED,
	)
	button.add_to_group("provider_settings_touch_target")
	button.set_meta("gate_id", gate_id)
	_register_owner(
		button,
		gate_id,
		"operation_control",
		"ui.provider-settings.button.state-set.v1",
		"base_ninepatch_state_set",
	)
	_mark_surface(button)
	parent.add_child(button)
	ProviderButtonMotion.attach(button)
	return button


func _custom_model_placeholder(provider: Dictionary) -> String:
	match str(provider.get("providerId", "")):
		"ollama":
			return "例如 qwen3:8b"
		"ollama-cloud":
			return "例如 gpt-oss:120b"
		"lm-studio":
			return "例如 local-model"
		"302-ai":
			return "例如 gpt-4.1-mini"
		_:
			return "例如 my-model-id"


func _custom_model_origin_label(provider: Dictionary) -> String:
	match str(provider.get("providerId", "")):
		"ollama":
			return "Ollama · 本地"
		"ollama-cloud":
			return "Ollama · 云端"
		"lm-studio":
			return "LM Studio · 本地"
		"302-ai":
			return "302.AI"
		_:
			return "兼容接口"


func _custom_model_discovery_source_label(provider: Dictionary) -> String:
	match str(provider.get("providerId", "")):
		"ollama":
			return "Ollama"
		"ollama-cloud":
			return "Ollama Cloud"
		"lm-studio":
			return "LM Studio"
		"302-ai":
			return "302.AI"
		_:
			return "兼容接口"


func _add_custom_model_delete_button(
	provider: Dictionary,
	card: Control,
	card_rect: Rect2,
	model_id: String,
	index: int,
) -> void:
	var button_size := Vector2(
		roundf(48.0 * _scale.x),
		roundf(48.0 * _scale.y),
	)
	var margin := Vector2(
		roundf(10.0 * _scale.x),
		roundf(12.0 * _scale.y),
	)
	var source_rect := Rect2(
		card_rect.end - button_size - margin,
		button_size,
	)
	var button := Button.new()
	button.name = "DeleteApiModelButton_%d" % index
	button.text = ""
	_place(button, source_rect, card_rect)
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.disabled = (
		not _action_enabled("deleteApiModel")
		or _operation_loading()
	)
	button.tooltip_text = "删除 %s" % model_id
	button.add_to_group("provider_settings_touch_target")
	button.set_meta("gate_id", "api_model_delete_%d" % index)
	_register_owner(
		button,
		"api_model_delete_%d" % index,
		"operation_control",
		"ui.provider-settings.custom-model-delete.v1",
		"texture-button",
	)
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(
			state,
			ProviderTheme.transparent_hit_style(state),
		)
	card.add_child(button)
	var art := TextureRect.new()
	art.name = "DeleteArt"
	_apply_visual_rect(art, button)
	art.texture = ProviderTheme.custom_model_delete_texture()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.modulate = Color(1.0, 1.0, 1.0, 0.48) if button.disabled else Color.WHITE
	button.add_child(art)
	button.pressed.connect(func() -> void:
		ui_action.emit(
			&"ui.request_delete_api_model",
			{
				"providerId": str(provider.get("providerId", "")),
				"apiModel": model_id,
			},
		)
	)
	ProviderButtonMotion.attach(button)


func _build_key_section(
	provider: Dictionary,
	detail_rect: Rect2
) -> void:
	var custom_group := bool(provider.get("customGroup", false))
	var auth_required := bool(provider.get("authRequired", true))
	var region_rect := _region_rect("api_key_section")
	var owner := _owner_control(
		provider_detail,
		detail_rect,
		region_rect,
		"ApiKeyPanel",
		"api_key_section",
		"content_slot",
		"ui.provider-settings.composite.api-key-section.v1",
		"composite-subregion"
	)
	_add_slot_label(
		owner,
		region_rect,
		"api_key_label",
		"API Key",
		ProviderTheme.COMPOSITE_INK
	)
	var key_data := provider.get("key", {}) as Dictionary
	key_edit = _line_edit_for_slot(
		owner,
		region_rect,
		"api_key_value",
		"ApiKeyInput",
		"api_key_input",
		"ui.provider-settings.composite.api-key-input.v1"
	)
	key_edit.secret = not _show_key
	key_edit.secret_character = "•"
	key_edit.text = _draft_key
	key_edit.placeholder_text = (
		"本地服务无需填写"
		if custom_group and not auth_required
		else
		str(key_data.get("maskedValue", "••••••••••••"))
		if bool(key_data.get("saved", false))
		else "请输入 API Key"
	)
	if custom_group and not auth_required:
		key_edit.secret = false
		key_edit.editable = false
	key_edit.text_changed.connect(func(value: String) -> void:
		ui_action.emit(&"ui.draft_key", {"value": value})
		var reveal_button := find_child(
			"RevealKeyButton",
			true,
			false
		) as Button
		if reveal_button != null:
			reveal_button.disabled = (
				value.is_empty()
				and not bool(key_data.get("saved", false))
			)
	)
	var reveal := _hit_button(
		owner,
		region_rect,
		"show_key",
		"RevealKeyButton",
		"key_reveal",
		"operation_control",
		"ui.provider-settings.composite.key-reveal.v1"
	)
	reveal.disabled = not auth_required or (
		_draft_key.is_empty()
		and not bool(key_data.get("saved", false))
	)
	reveal.tooltip_text = "隐藏 Key" if _show_key else "显示 Key"
	reveal.pressed.connect(func() -> void:
		ui_action.emit(&"ui.toggle_key_visibility", {})
	)
	var save := _hit_button(
		owner,
		region_rect,
		"save_key",
		"SaveKeyButton",
		"key_save",
		"operation_control",
		"ui.provider-settings.composite.key-save.v1"
	)
	save.disabled = (
		(
			not _action_enabled("saveConnection")
			or _operation_loading()
			or (
				auth_required
				and _draft_key.is_empty()
				and not bool(key_data.get("saved", false))
			)
		)
		if custom_group
		else (
			_draft_key.is_empty()
			or not _draft_key_dirty
			or not _action_enabled("saveKey")
			or _operation_loading()
		)
	)
	save.tooltip_text = (
		"保存连接并读取模型" if custom_group else "保存 Key"
	)
	save.pressed.connect(func() -> void:
		if custom_group:
			ui_action.emit(
				&"provider_settings.save_connection",
				{
					"providerId": str(provider.get("providerId", "")),
					"baseUrl": (
						base_url_edit.text
						if base_url_edit != null
						else ""
					),
					"apiKey": key_edit.text if auth_required else "",
				},
			)
		else:
			ui_action.emit(
				&"ui.save_key",
				{
					"providerId": str(provider.get("providerId", "")),
					"apiKey": key_edit.text,
				}
			)
	)
	var delete := _hit_button(
		owner,
		region_rect,
		"delete_key",
		"DeleteKeyButton",
		"key_delete",
		"operation_control",
		"ui.provider-settings.composite.key-delete.v1"
	)
	delete.disabled = not auth_required or (
		not _action_enabled("deleteKey")
		or not bool(key_data.get("saved", false))
		or _operation_loading()
	)
	delete.tooltip_text = "删除 Key"
	delete.pressed.connect(func() -> void:
		ui_action.emit(
			&"provider_settings.delete_key",
			{"providerId": str(provider.get("providerId", ""))}
		)
	)


func _add_key_actions(
	provider: Dictionary,
	parent: Control,
	parent_rect: Rect2,
) -> void:
	var key_data := provider.get("key", {}) as Dictionary
	var save := _custom_icon_button(
		parent,
		parent_rect,
		_rect(_hit_targets.get("show_key", [])),
		"SaveKeyButton",
		"key_save",
		ProviderTheme.custom_key_save_texture(),
	)
	save.disabled = (
		_draft_key.is_empty()
		or not _draft_key_dirty
		or not _action_enabled("saveKey")
		or _operation_loading()
	)
	save.tooltip_text = "保存 Key"
	save.pressed.connect(func() -> void:
		ui_action.emit(
			&"ui.save_key",
			{
				"providerId": str(provider.get("providerId", "")),
				"apiKey": key_edit.text,
			},
		)
	)
	var reveal := _custom_icon_button(
		parent,
		parent_rect,
		_rect(_hit_targets.get("save_key", [])),
		"RevealKeyButton",
		"key_reveal",
		ProviderTheme.custom_key_reveal_texture(),
	)
	reveal.disabled = (
		_draft_key.is_empty()
		and not bool(key_data.get("saved", false))
	)
	reveal.tooltip_text = "隐藏 Key" if _show_key else "显示 Key"
	reveal.pressed.connect(func() -> void:
		ui_action.emit(&"ui.toggle_key_visibility", {})
	)
	var delete := _custom_icon_button(
		parent,
		parent_rect,
		_rect(_hit_targets.get("delete_key", [])),
		"DeleteKeyButton",
		"key_delete",
		ProviderTheme.custom_key_delete_texture(),
	)
	delete.disabled = (
		not _action_enabled("deleteKey")
		or not bool(key_data.get("saved", false))
		or _operation_loading()
	)
	delete.tooltip_text = "删除 Key"
	delete.pressed.connect(func() -> void:
		ui_action.emit(
			&"provider_settings.delete_key",
			{"providerId": str(provider.get("providerId", ""))},
		)
	)


func _build_base_url_section(
	provider: Dictionary,
	detail_rect: Rect2
) -> void:
	var custom_group := bool(provider.get("customGroup", false))
	var region_rect := _region_rect("base_url_section")
	var owner := _owner_control(
		provider_detail,
		detail_rect,
		region_rect,
		"BaseUrlPanel",
		"base_url_section",
		"content_slot",
		"ui.provider-settings.composite.base-url-section.v1",
		"composite-subregion"
	)
	_add_slot_label(
		owner,
		region_rect,
		"base_url_label",
		"Base URL",
		ProviderTheme.COMPOSITE_INK
	)
	base_url_edit = _line_edit_for_slot(
		owner,
		region_rect,
		"base_url_value",
		"BaseUrlInput",
		"base_url_input",
		"ui.provider-settings.composite.base-url-input.v1"
	)
	base_url_edit.text = _draft_base_url
	base_url_edit.placeholder_text = _base_url_placeholder(provider, custom_group)
	base_url_edit.text_changed.connect(func(value: String) -> void:
		ui_action.emit(&"ui.draft_base_url", {"value": value})
	)
	base_url_edit.text_submitted.connect(func(value: String) -> void:
		if custom_group:
			ui_action.emit(
				&"provider_settings.save_connection",
				{
					"providerId": str(provider.get("providerId", "")),
					"baseUrl": value,
					"apiKey": key_edit.text if key_edit != null else "",
				},
			)
		else:
			ui_action.emit(
				&"provider_settings.save_base_url",
				{
					"providerId": str(provider.get("providerId", "")),
					"baseUrl": value,
				}
			)
	)
	var hidden_save := Button.new()
	hidden_save.name = "SaveBaseUrlButton"
	hidden_save.visible = false
	hidden_save.disabled = (
		not _action_enabled("saveBaseUrl")
		or _operation_loading()
	)
	hidden_save.pressed.connect(func() -> void:
		ui_action.emit(
			&"provider_settings.save_base_url",
			{
				"providerId": str(provider.get("providerId", "")),
				"baseUrl": base_url_edit.text,
			}
		)
	)
	owner.add_child(hidden_save)


func _base_url_placeholder(provider: Dictionary, custom_group: bool) -> String:
	if not custom_group:
		var default_url := str(provider.get("defaultBaseUrl", "")).strip_edges()
		return (
			"例如 %s" % default_url
			if not default_url.is_empty()
			else "请输入服务地址"
		)
	match str(provider.get("providerId", "")):
		"ollama":
			return "例如 http://127.0.0.1:11434/v1"
		"ollama-cloud":
			return "例如 https://ollama.com/api"
		"lm-studio":
			return "例如 http://127.0.0.1:1234/v1"
		"302-ai":
			return "例如 https://api.302.ai/v1"
		_:
			return "例如 https://api.example.com/v1"


func _build_standard_dynamic_model_editor(
	provider: Dictionary,
	owner: Control,
	region_rect: Rect2,
) -> void:
	api_model_edit = _custom_connection_input(
		owner,
		region_rect,
		STANDARD_DYNAMIC_MODEL_INPUT_RECT,
		"ApiModelInput",
		"api_model_input",
		true,
	)
	api_model_edit.text = _draft_api_model
	api_model_edit.placeholder_text = (
		"例如 ep-2026xxxx"
		if str(provider.get("providerId", "")) == "volcengine-ark"
		else "例如 my-model-id"
	)
	api_model_edit.text_changed.connect(func(value: String) -> void:
		_draft_api_model = value
		ui_action.emit(&"ui.draft_api_model", {"value": value})
	)
	var add := _custom_action_button(
		owner,
		region_rect,
		STANDARD_DYNAMIC_MODEL_ADD_RECT,
		"SaveApiModelButton",
		"api_model_add",
		"添加",
		"success",
	)
	add.disabled = (
		not _action_enabled("saveApiModel")
		or _operation_loading()
		or _draft_api_model.strip_edges().is_empty()
	)
	add.tooltip_text = "添加并选用这个模型或推理接入点"
	var submit_model := func(value: String) -> void:
		if value.strip_edges().is_empty():
			return
		ui_action.emit(
			&"provider_settings.save_api_model",
			{
				"providerId": str(provider.get("providerId", "")),
				"apiModel": value,
			},
		)
	add.pressed.connect(func() -> void:
		var value := api_model_edit.text
		if value.strip_edges().is_empty():
			return
		ui_action.emit(
			&"provider_settings.save_api_model",
			{
				"providerId": str(provider.get("providerId", "")),
				"apiModel": value,
			},
		)
	)
	api_model_edit.text_submitted.connect(submit_model)


func _build_models_section(
	provider: Dictionary,
	detail_rect: Rect2
) -> void:
	var provider_id := str(provider.get("providerId", ""))
	var auto_catalog_models := (
		provider_id == "volcengine-ark"
		or bool(provider.get("customGroup", false))
	)
	var dynamic_models := (
		bool(provider.get("customModels", false))
		and not auto_catalog_models
	)
	var custom_layout := false
	var region_rect := _region_rect("models_section")
	var owner := _owner_control(
		provider_detail,
		detail_rect,
		region_rect,
		"ModelsPanel",
		"models_section",
		"content_slot",
		"ui.provider-settings.composite.models-section.v1",
		"composite-subregion"
	)
	_add_slot_label(
		owner,
		region_rect,
		"models_label",
		"推理接入点 ID" if dynamic_models and not custom_layout else "模型与能力",
		ProviderTheme.COMPOSITE_INK,
		(
			CUSTOM_MODELS_LABEL_RECT
			if custom_layout
			else Rect2()
		),
	)
	if dynamic_models and not custom_layout:
		_build_standard_dynamic_model_editor(provider, owner, region_rect)
	var models := provider.get("models", []) as Array
	var page_count := _page_count(models.size(), MODELS_PER_PAGE)
	_model_page = clampi(_model_page, 0, page_count - 1)
	var page_start := _model_page * MODELS_PER_PAGE
	var page_end := mini(page_start + MODELS_PER_PAGE, models.size())
	_add_slot_label(
		owner,
		region_rect,
		"model_page",
		"%d / %d" % [_model_page + 1, page_count],
		ProviderTheme.COMPOSITE_INK,
		(
			CUSTOM_MODEL_PAGE_RECT
			if custom_layout
			else STANDARD_DYNAMIC_MODEL_PAGE_RECT
			if dynamic_models
			else Rect2()
		),
	)
	var previous := _pagination_button(
		owner,
		region_rect,
		"model_page_previous",
		"ModelPagePrevious",
		"上一页模型",
		false,
		_model_page <= 0,
		(
			CUSTOM_MODEL_PAGE_PREVIOUS_RECT
			if custom_layout
			else STANDARD_DYNAMIC_MODEL_PREVIOUS_RECT
			if dynamic_models
			else Rect2()
		),
	)
	previous.pressed.connect(func() -> void:
		_change_model_page(_model_page - 1)
	)
	var next := _pagination_button(
		owner,
		region_rect,
		"model_page_next",
		"ModelPageNext",
		"下一页模型",
		true,
		_model_page >= page_count - 1,
		(
			CUSTOM_MODEL_PAGE_NEXT_RECT
			if custom_layout
			else STANDARD_DYNAMIC_MODEL_NEXT_RECT
			if dynamic_models
			else Rect2()
		),
	)
	next.pressed.connect(func() -> void:
		_change_model_page(_model_page + 1)
	)
	for index: int in range(page_end - page_start):
		var model := models[page_start + index] as Dictionary
		var model_id := str(model.get("modelId", ""))
		var card_rect := (
			_scaled_rect(Rect2(
				682.0 if index == 0 else 1066.0,
				CUSTOM_MODEL_CARD_Y,
				363.0,
				CUSTOM_MODEL_CARD_HEIGHT,
			))
			if custom_layout
			else _hit_rect("model_%d" % index)
		)
		var card := _hit_button_from_rect(
			owner,
			region_rect,
			card_rect,
			"Model_%s" % model_id,
			"model_%s" % model_id,
			"content_slot",
			"ui.provider-settings.composite.model-card-%d.v1" % index,
			"composite-subregion"
		)
		card.disabled = (
			not _action_enabled("selectModel")
			or _operation_loading()
		)
		card.tooltip_text = (
			"停用 %s" if bool(model.get("enabled", false))
			else "启用 %s"
		) % str(model.get("displayName", "模型"))
		_apply_model_card_skin(card, bool(model.get("enabled", false)))
		card.pressed.connect(func() -> void:
			ui_action.emit(
				&"provider_settings.select_model",
				{
					"providerId": str(
						provider.get("providerId", "")
					),
					"modelId": model_id,
					"enabled": not bool(
						model.get("enabled", false)
					),
				}
			)
		)
		var name_label := _add_slot_label(
			card,
			card_rect,
			"model_%d_name" % index,
			str(model.get("displayName", "")),
			(
				ProviderTheme.COMPOSITE_SUCCESS
				if bool(model.get("enabled", false))
				else ProviderTheme.COMPOSITE_INK
			),
			(
				Rect2(
						710.0 if index == 0 else 1109.0,
						CUSTOM_MODEL_NAME_Y,
						270.0,
						38.0,
					)
				if custom_layout
				else Rect2()
			),
		)
		var capability_label := _add_slot_label(
			card,
			card_rect,
			"model_%d_capabilities" % index,
			(
				_custom_model_origin_label(provider)
				if custom_layout
				else _capability_labels(
					model.get("capabilities", []) as Array
				)
			),
			(
				ProviderTheme.COMPOSITE_SUCCESS
				if bool(model.get("enabled", false))
				else ProviderTheme.COMPOSITE_MUTED
			),
			(
				Rect2(
						710.0 if index == 0 else 1109.0,
						CUSTOM_MODEL_ORIGIN_Y,
						305.0,
						45.0,
					)
				if custom_layout
				else Rect2()
			),
		)
		if bool(model.get("enabled", false)):
			_apply_selected_model_typography(name_label, "body")
			_apply_selected_model_typography(capability_label, "small")
		if custom_layout and bool(model.get("custom", false)):
			_add_custom_model_delete_button(
				provider,
				card,
				card_rect,
				model_id,
				index,
			)
	if models.is_empty() and custom_layout:
		var empty_texture := ProviderTheme.custom_model_empty_texture()
		if empty_texture != null:
			var empty_art := TextureRect.new()
			empty_art.name = "CustomModelEmptyPanelArt"
			var empty_rect := _scaled_rect(Rect2(678.0, 585.0, 752.0, 154.0))
			_place(empty_art, empty_rect, region_rect)
			empty_art.texture = empty_texture
			empty_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			empty_art.stretch_mode = TextureRect.STRETCH_SCALE
			empty_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			empty_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
			empty_art.add_to_group("provider_settings_surface")
			empty_art.set_meta("gate_id", "custom_model_empty_panel")
			owner.add_child(empty_art)
		var empty_title := _add_slot_label(
			owner,
			region_rect,
			"model_0_name",
			"还没有添加模型",
			ProviderTheme.COMPOSITE_MUTED,
			Rect2(700.0, 648.0, 708.0, 35.0),
		)
		empty_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var empty_message := _add_slot_label(
			owner,
			region_rect,
			"model_0_capabilities",
			"填写模型 ID，或从当前连接获取模型",
			ProviderTheme.COMPOSITE_MUTED,
			Rect2(700.0, 684.0, 708.0, 34.0),
		)
		empty_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if models.is_empty() and auto_catalog_models:
		var catalog_loading := _is_model_catalog_operation(provider) and (
			str((_view_model.get("operation", {}) as Dictionary).get("status", ""))
			== "loading"
		)
		var catalog_failed := _is_model_catalog_operation(provider) and (
			str((_view_model.get("operation", {}) as Dictionary).get("status", ""))
			in ["error", "rejected"]
		)
		_add_slot_label(
			owner,
			region_rect,
			"model_0_name",
			(
				"正在读取可用模型…"
				if catalog_loading
				else "模型读取失败"
				if catalog_failed
				else "尚未获取模型"
			),
			ProviderTheme.COMPOSITE_MUTED,
		)
		_add_slot_label(
			owner,
			region_rect,
			"model_0_capabilities",
			(
				"请稍候"
				if catalog_loading
				else _public_operation_error_message(
					_view_model.get("error", {}) as Dictionary
				)
				if catalog_failed
				else "填写并保存 API Key 后自动读取"
			),
			ProviderTheme.COMPOSITE_MUTED,
		)
	if models.size() == 1 and _model_page == 0:
		_add_slot_label(
			owner,
			region_rect,
			"model_1_name",
			"暂无其他模型",
			ProviderTheme.COMPOSITE_MUTED,
			Rect2(),
		)
		_add_slot_label(
			owner,
			region_rect,
			"model_1_capabilities",
			(
				"可继续添加更多自定义模型"
				if custom_layout
				else "该服务商当前仅提供一个居民模型"
			),
			ProviderTheme.COMPOSITE_MUTED,
			Rect2(),
		)


func _pagination_button(
	parent: Control,
	parent_rect: Rect2,
	hit_id: String,
	node_name: String,
	tooltip: String,
	point_right: bool,
	disabled: bool,
	source_rect_override: Rect2 = Rect2(),
	embedded_well: bool = false,
) -> Button:
	var button := _hit_button_from_rect(
		parent,
		parent_rect,
		(
			_scaled_rect(source_rect_override)
			if source_rect_override.size != Vector2.ZERO
			else _hit_rect(hit_id)
		),
		node_name,
		hit_id,
		"operation_control",
		"ui.provider-settings.composite.%s.v1" % hit_id,
		"composite-transparent-control",
	)
	button.tooltip_text = tooltip
	button.disabled = disabled
	var art := TextureRect.new()
	art.name = "PaginationArt"
	_apply_visual_rect(art, button)
	art.texture = (
		ProviderTheme.provider_back_arrow_texture()
		if embedded_well
		else ProviderTheme.pagination_texture()
	)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.flip_h = point_right
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.modulate = Color(1.0, 1.0, 1.0, 0.48) if disabled else Color.WHITE
	button.add_child(art)
	button.set_meta("pagination_asset_path", ProviderTheme.PAGINATION_LEFT_PATH)
	button.set_meta("pagination_points_right", point_right)
	return button


func _change_provider_page(page: int) -> void:
	var providers := _data.get("providers", []) as Array
	var page_count := _page_count(providers.size(), PROVIDERS_PER_PAGE)
	var next_page := clampi(page, 0, page_count - 1)
	if next_page == _provider_page:
		return
	var moving_forward := next_page > _provider_page
	_provider_page = next_page
	pagination_changed.emit(_provider_page, _model_page)
	_pagination_focus_target = (
		"ProviderPageNext"
		if moving_forward and _provider_page < page_count - 1
		else "ProviderPagePrevious"
		if moving_forward
		else "ProviderPagePrevious"
		if _provider_page > 0
		else "ProviderPageNext"
	)
	_queue_pagination_rebuild()


func _change_model_page(page: int) -> void:
	var provider := _find_provider(_selected_provider_id)
	var models := provider.get("models", []) as Array
	var page_count := _page_count(models.size(), MODELS_PER_PAGE)
	var next_page := clampi(page, 0, page_count - 1)
	if next_page == _model_page:
		return
	var moving_forward := next_page > _model_page
	_model_page = next_page
	pagination_changed.emit(_provider_page, _model_page)
	_pagination_focus_target = (
		"ModelPageNext"
		if moving_forward and _model_page < page_count - 1
		else "ModelPagePrevious"
		if moving_forward
		else "ModelPagePrevious"
		if _model_page > 0
		else "ModelPageNext"
	)
	_queue_pagination_rebuild()


func _queue_pagination_rebuild() -> void:
	if key_edit != null:
		_draft_key = key_edit.text
	if base_url_edit != null:
		_draft_base_url = base_url_edit.text
	if api_model_edit != null:
		_draft_api_model = api_model_edit.text
	if _pagination_rebuild_queued:
		return
	_pagination_rebuild_queued = true
	call_deferred("_rebuild_after_pagination")


func _rebuild_after_pagination() -> void:
	_pagination_rebuild_queued = false
	UiNodeRetirement.retire_children(self)
	key_edit = null
	base_url_edit = null
	api_model_edit = null
	status_label = null
	check_button = null
	formal_badge = null
	provider_selector = null
	provider_detail = null
	_build()
	controls_rebuilt.emit()
	call_deferred("_restore_pagination_focus")


func _restore_pagination_focus() -> void:
	if _pagination_focus_target.is_empty():
		return
	var target := find_child(
		_pagination_focus_target,
		true,
		false,
	) as BaseButton
	_pagination_focus_target = ""
	if target != null and not target.disabled:
		target.grab_focus()


func _page_count(item_count: int, per_page: int) -> int:
	return maxi(1, ceili(float(item_count) / float(per_page)))


func _selected_provider_page() -> int:
	var providers := _data.get("providers", []) as Array
	for index: int in range(providers.size()):
		var provider := providers[index] as Dictionary
		if str(provider.get("providerId", "")) == _selected_provider_id:
			return floori(float(index) / float(PROVIDERS_PER_PAGE))
	return 0


func _selected_model_page() -> int:
	var provider := _find_provider(_selected_provider_id)
	var models := provider.get("models", []) as Array
	for index: int in range(models.size()):
		var model := models[index] as Dictionary
		if bool(model.get("enabled", false)):
			return floori(float(index) / float(MODELS_PER_PAGE))
	return 0


func _build_connection_section(
	provider: Dictionary,
	detail_rect: Rect2
) -> void:
	var region_rect := _region_rect("connection_section")
	var owner := _owner_control(
		provider_detail,
		detail_rect,
		region_rect,
		"ConnectionStatusPanel",
		"connection_status",
		"content_slot",
		"ui.provider-settings.composite.connection-section.v1",
		"composite-subregion"
	)
	var connection := provider.get("connection", {}) as Dictionary
	var operation := _view_model.get("operation", {}) as Dictionary
	var error_value: Variant = _view_model.get("error", null)
	var error_data := (
		error_value as Dictionary
		if typeof(error_value) == TYPE_DICTIONARY
		else {}
	)
	var catalog_operation := _is_model_catalog_operation(provider)
	var connection_operation := (
		{"status": "idle"}
		if catalog_operation
		else operation
	)
	var connection_error_data := {} if catalog_operation else error_data
	var connection_loading := _operation_loading() and not catalog_operation
	var custom_layout := false
	var tone := (
		_operation_tone(
			str(connection_operation.get("status", "idle")),
			str(connection_error_data.get("kind", "")),
			str(connection.get("status", "")),
		)
		if custom_layout
		else _standard_operation_tone(
			str(connection_operation.get("status", "idle")),
			str(connection_error_data.get("kind", "")),
			str(connection.get("status", "")),
		)
	)
	var display_tone := "loading" if connection_loading else tone
	if custom_layout:
		_add_connection_status_plate(
			owner,
			region_rect,
			display_tone,
		)
	status_label = _add_slot_label(
		owner,
		region_rect,
		"connection_title",
		(
			_operation_title(
				connection_operation,
				connection,
				connection_error_data,
			)
			if custom_layout
			else _standard_operation_title(
				connection_operation,
				connection,
				connection_error_data,
			)
		),
		_tone_color(display_tone),
	)
	var status_message := _add_slot_label(
		owner,
		region_rect,
		"connection_message",
		(
			"正在等待 %s 响应" % _checking_provider_name(provider)
			if custom_layout and connection_loading
			else _operation_message(
				connection_operation,
				connection,
				connection_error_data,
			)
		),
		ProviderTheme.COMPOSITE_MUTED,
	)
	if custom_layout:
		for label: Label in [status_label, status_message]:
			label.position.x += _scaled_spacing(28.0)
			label.size.x = maxf(
				0.0,
				label.size.x - _scaled_spacing(28.0),
			)
	check_button = _hit_button(
		owner,
		region_rect,
		"check_connection",
		"CheckConnectionButton",
		"check_connection",
		"operation_control",
		"ui.provider-settings.composite.check-connection.v1"
	)
	check_button.text = (
		"检查中…"
		if connection_loading
		else "重新检查"
		if custom_layout and display_tone in ["error", "warning"]
		else "检查连接"
	)
	if custom_layout:
		for state: String in ["normal", "hover", "pressed", "focus"]:
			check_button.add_theme_stylebox_override(
				state,
				ProviderTheme.exact_action_button_style(
					"check_connection_normal",
					"normal",
				),
			)
		check_button.add_theme_stylebox_override(
			"disabled",
			ProviderTheme.exact_action_button_style(
				"check_connection_loading"
			),
		)
	check_button.disabled = (
		not _action_enabled("checkConnection")
		or _operation_loading()
	)
	check_button.tooltip_text = "检查连接"
	if custom_layout and connection_loading:
		check_button.add_theme_stylebox_override(
			"disabled",
			ProviderTheme.exact_action_button_style(
				"check_connection_loading"
			),
		)
		check_button.add_theme_color_override(
			"font_disabled_color",
			ProviderTheme.PAPER_LIGHT,
		)
	_apply_button_typography(check_button)
	check_button.pressed.connect(func() -> void:
		ui_action.emit(
			&"provider_settings.check_connection",
			{"providerId": str(provider.get("providerId", ""))}
		)
	)
	ProviderButtonMotion.set_loading_state(
		check_button,
		connection_loading,
	)


func _is_model_catalog_operation(provider: Dictionary) -> bool:
	var operation := _view_model.get("operation", {}) as Dictionary
	var intent := str(operation.get("intent", ""))
	if str(provider.get("providerId", "")) == "volcengine-ark":
		return intent in [
			"provider_settings.save_key",
			"provider_settings.discover_models",
		]
	return (
		bool(provider.get("customGroup", false))
		and intent in [
			"provider_settings.save_connection",
			"provider_settings.discover_models",
		]
	)


func _standard_operation_title(
	operation: Dictionary,
	connection: Dictionary,
	error_data: Dictionary,
) -> String:
	match str(operation.get("status", "idle")):
		"loading":
			return "正在检查连接"
		"success":
			return (
				"开发预览检查通过"
				if _is_placeholder_data()
				else "连接检查通过"
			)
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
			return str(connection.get("label", "等待检查"))


func _standard_operation_tone(
	operation_status: String,
	error_kind: String,
	provider_status: String,
) -> String:
	if operation_status == "success" or provider_status == "available":
		return "success"
	if operation_status == "disabled":
		return "disabled"
	if (
		operation_status == "rejected"
		or error_kind == "rate_limit"
		or provider_status in ["rate_limited", "checking"]
	):
		return "warning"
	if operation_status == "error":
		return "error"
	return (
		"error"
		if provider_status in [
			"auth_failed",
			"timeout",
			"network_unavailable",
		]
		else "warning"
	)


func _add_connection_status_plate(
	owner: Control,
	region_rect: Rect2,
	tone: String,
) -> void:
	var texture := ProviderTheme.connection_status_texture(tone)
	if texture == null:
		return
	var plate := TextureRect.new()
	plate.name = "ConnectionStatusPlate"
	var plate_rect := _scaled_rect(Rect2(662.0, 741.0, 506.0, 94.0))
	_place(plate, plate_rect, region_rect)
	plate.texture = texture
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.stretch_mode = TextureRect.STRETCH_SCALE
	plate.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_to_group("provider_settings_surface")
	plate.set_meta("gate_id", "connection_status_%s_plate" % tone)
	owner.add_child(plate)
	if tone == "loading":
		var tween := plate.create_tween().set_loops()
		tween.tween_property(
			plate,
			"modulate",
			Color(1.0, 1.0, 1.0, 0.72),
			0.58,
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(
			plate,
			"modulate",
			Color.WHITE,
			0.58,
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _add_checking_status_icon(owner: Control, region_rect: Rect2) -> void:
	var texture := ProviderTheme.provider_checking_connection_texture()
	if texture == null:
		return
	var icon := TextureRect.new()
	icon.name = "ConnectionCheckingIndicator"
	var icon_rect := _scaled_rect(Rect2(678.0, 755.0, 54.0, 54.0))
	_place(icon, icon_rect, region_rect)
	icon.texture = texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.pivot_offset = icon.size * 0.5
	icon.add_to_group("provider_settings_icon_owner")
	icon.set_meta("gate_id", "connection_status_checking_icon")
	owner.add_child(icon)
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


func _owner_control(
	parent: Control,
	parent_rect: Rect2,
	target_rect: Rect2,
	node_name: String,
	gate_id: String,
	owner_level: String,
	asset_id: String,
	component_type: String
) -> Control:
	var control := Control.new()
	control.name = node_name
	_place(control, target_rect, parent_rect)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_register_owner(
		control,
		gate_id,
		owner_level,
		asset_id,
		component_type
	)
	_mark_surface(control)
	control.add_to_group("provider_settings_region")
	control.set_meta("gate_id", gate_id)
	parent.add_child(control)
	return control


func _hit_button(
	parent: Control,
	parent_rect: Rect2,
	hit_id: String,
	node_name: String,
	gate_id: String,
	owner_level: String,
	asset_id: String
) -> Button:
	return _hit_button_from_rect(
		parent,
		parent_rect,
		_hit_rect(hit_id),
		node_name,
		gate_id,
		owner_level,
		asset_id,
		"composite-transparent-control"
	)


func _hit_button_from_rect(
	parent: Control,
	parent_rect: Rect2,
	target_rect: Rect2,
	node_name: String,
	gate_id: String,
	owner_level: String,
	asset_id: String,
	component_type: String
) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = ""
	var touch_rect := _minimum_touch_rect(target_rect, parent_rect)
	_place(
		button,
		touch_rect,
		parent_rect,
	)
	button.set_meta(
		"visual_rect_local",
		Rect2(target_rect.position - touch_rect.position, target_rect.size),
	)
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	button.add_to_group("provider_settings_touch_target")
	button.set_meta("gate_id", gate_id)
	_register_owner(
		button,
		gate_id,
		owner_level,
		asset_id,
		component_type
	)
	_mark_surface(button)
	for state: String in [
		"normal",
		"hover",
		"pressed",
		"focus",
		"disabled",
	]:
		button.add_theme_stylebox_override(
			state,
			ProviderTheme.transparent_hit_style(state)
		)
	parent.add_child(button)
	ProviderButtonMotion.attach(button)
	return button


func _decorate_toggle(
	button: BaseButton,
	enabled: bool,
) -> void:
	var texture := ProviderTheme.provider_toggle_texture(enabled)
	if texture == null:
		return
	var art := TextureRect.new()
	art.name = "ToggleArt"
	_apply_visual_rect(art, button)
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(art)
	button.set_meta("provider_toggle_art", true)
	button.set_meta("provider_toggle_enabled", enabled)


func _apply_provider_card_skin(
	card: BaseButton,
	provider: Dictionary,
	connection: Dictionary,
) -> void:
	var selected := (
		String(provider.get("providerId", "")) == _selected_provider_id
	)
	var tone := _operation_tone(
		"idle",
		"",
		String(connection.get("status", "not_configured")),
	)
	if not bool(provider.get("enabled", true)):
		tone = "disabled"
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		card.add_theme_stylebox_override(
			state,
			ProviderTheme.provider_card_style(selected, tone, state),
		)
	card.set_meta("provider_card_selected", selected)


func _apply_model_card_skin(card: BaseButton, selected: bool) -> void:
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		card.add_theme_stylebox_override(
			state,
			ProviderTheme.transparent_hit_style(state),
		)
	card.set_meta("model_card_selected", selected)
	card.set_meta("model_selection_presentation", "bold_green_text")


func _apply_selected_model_typography(label: Label, token: String) -> void:
	label.add_theme_font_override(
		"font",
		ProviderTheme.composite_selected_font(token),
	)
	label.add_theme_color_override(
		"font_color",
		ProviderTheme.COMPOSITE_SUCCESS,
	)


func _add_provider_identity_medallion(
	card: Control,
	card_rect: Rect2,
	provider_id: String,
	custom_group := false,
) -> void:
	var texture := ProviderTheme.provider_identity_medallion(
		provider_id,
		custom_group,
	)
	if texture == null:
		return
	var offset := Vector2(
		roundf(18.0 * _scale.x),
		roundf(22.0 * _scale.y),
	)
	var medallion_size := Vector2(
		roundf(88.0 * _scale.x),
		roundf(88.0 * _scale.y),
	)
	var medallion := TextureRect.new()
	medallion.name = "ProviderMedallion_%s" % provider_id
	_place(
		medallion,
		Rect2(card_rect.position + offset, medallion_size),
		card_rect,
	)
	medallion.texture = texture
	medallion.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	medallion.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	medallion.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	medallion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(medallion)


func _add_provider_available_indicator(
	card: Control,
	card_rect: Rect2,
) -> void:
	var texture := ProviderTheme.provider_available_indicator_texture()
	if texture == null:
		return
	var icon := TextureRect.new()
	icon.name = "ProviderAvailableIndicator"
	var icon_size := Vector2(
		roundf(38.0 * _scale.x),
		roundf(30.0 * _scale.y),
	)
	var icon_rect := Rect2(
		card_rect.position
		+ Vector2(
			roundf(330.0 * _scale.x),
			roundf(25.0 * _scale.y),
		),
		icon_size,
	)
	_place(icon, icon_rect, card_rect)
	icon.texture = texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(icon)


func _line_edit_for_slot(
	parent: Control,
	parent_rect: Rect2,
	slot_id: String,
	node_name: String,
	gate_id: String,
	asset_id: String
) -> LineEdit:
	var slot := _slots.get(slot_id, {}) as Dictionary
	var target_rect := _scaled_rect(
		_rect(slot.get("wellRect", slot.get("rect", [])))
	)
	var touch_rect := _minimum_touch_rect(target_rect, parent_rect)
	var edit := LineEdit.new()
	edit.name = node_name
	_place(edit, touch_rect, parent_rect)
	edit.focus_mode = Control.FOCUS_ALL
	edit.add_to_group("provider_settings_touch_target")
	edit.set_meta("gate_id", gate_id)
	_register_owner(
		edit,
		gate_id,
		"content_slot",
		asset_id,
		"composite-transparent-input"
	)
	var font := ProviderTheme.composite_font("body")
	edit.add_theme_font_override("font", font)
	edit.add_theme_font_size_override(
		"font_size",
		_scaled_font_size(24),
	)
	edit.add_theme_color_override(
		"font_color",
		ProviderTheme.COMPOSITE_INK
	)
	edit.add_theme_color_override(
		"font_placeholder_color",
		ProviderTheme.COMPOSITE_MUTED
	)
	edit.add_theme_color_override(
		"caret_color",
		ProviderTheme.COMPOSITE_ERROR
	)
	edit.add_theme_color_override(
		"selection_color",
		Color(ProviderTheme.COMPOSITE_SUCCESS, 0.32)
	)
	for state: String in ["normal", "focus", "read_only"]:
		var style: StyleBox = ProviderTheme.transparent_input_style()
		style.content_margin_left = _scaled_spacing(26.0)
		style.content_margin_top = _scaled_spacing(4.0)
		style.content_margin_right = _scaled_spacing(20.0)
		style.content_margin_bottom = _scaled_spacing(4.0)
		edit.add_theme_stylebox_override(state, style)
	parent.add_child(edit)
	return edit


func _add_slot_label(
	parent: Control,
	parent_rect: Rect2,
	slot_id: String,
	text_value: String,
	color: Color,
	source_rect_override: Rect2 = Rect2(),
) -> Label:
	var slot := _slots.get(slot_id, {}) as Dictionary
	var target_rect := _scaled_rect(
		source_rect_override
		if source_rect_override.size != Vector2.ZERO
		else _rect(slot.get("rect", []))
	)
	target_rect.position.y += _scaled_spacing(
		float(slot.get("opticalYOffsetAt1920", 0))
	)
	var token_id := str(slot.get("fontToken", "small"))
	var tokens := (
		(_contract.get("typography", {}) as Dictionary).get(
			"tokens",
			{}
		) as Dictionary
	)
	var token := tokens.get(token_id, {}) as Dictionary
	var label := Label.new()
	label.name = "LiveText_%s" % slot_id
	_place(label, target_rect, parent_rect)
	label.text = text_value
	label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
		if str(slot.get("alignment", "left")) == "center"
		else HORIZONTAL_ALIGNMENT_LEFT
	)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override(
		"font",
		ProviderTheme.composite_font(token_id)
	)
	label.add_theme_font_size_override(
		"font_size",
		_scaled_font_size(int(token.get("fontSizeAt1920", 16)))
	)
	label.add_theme_color_override("font_color", color)
	var outline_size := int(token.get("outlineSize", 0))
	if outline_size > 0:
		label.add_theme_constant_override(
			"outline_size",
			maxi(1, _scaled_font_size(outline_size))
		)
		label.add_theme_color_override(
			"font_outline_color",
			Color(
				str(
					token.get(
						"outlineColor",
						"#68260f"
					)
				)
			)
		)
	label.add_to_group("provider_settings_text_slot")
	label.set_meta("gate_id", slot_id)
	parent.add_child(label)
	return label


func _apply_button_typography(button: Button) -> void:
	button.add_theme_font_override(
		"font",
		ProviderTheme.composite_font("primary-button")
	)
	button.add_theme_font_size_override(
		"font_size",
		_scaled_font_size(32),
	)
	button.add_theme_constant_override(
		"outline_size",
		maxi(1, _scaled_font_size(1)),
	)
	for color_id: String in [
		"font_color",
		"font_hover_color",
		"font_pressed_color",
		"font_focus_color",
	]:
		button.add_theme_color_override(
			color_id,
			ProviderTheme.COMPOSITE_BUTTON_TEXT
		)
	button.add_theme_color_override(
		"font_outline_color",
		ProviderTheme.COMPOSITE_BUTTON_OUTLINE
	)


func _register_owner(
	control: Control,
	ownership_id: String,
	owner_level: String,
	asset_id: String,
	component_type: String
) -> void:
	control.add_to_group("provider_settings_border_owner")
	control.set_meta("ownership_id", ownership_id)
	control.set_meta("owner_level", owner_level)
	control.set_meta("asset_id", asset_id)
	control.set_meta("component_type", component_type)
	control.set_meta("paper_insets", [0, 0, 0, 0])


func _mark_surface(control: Control) -> void:
	control.add_to_group("provider_settings_content_surface")


func _place(
	control: Control,
	target_rect: Rect2,
	parent_rect: Rect2
) -> void:
	control.position = target_rect.position - parent_rect.position
	control.size = target_rect.size


func _region_rect(id: String) -> Rect2:
	return _scaled_rect(_rect(_regions.get(id, [])))


func _hit_rect(id: String) -> Rect2:
	return _scaled_rect(_rect(_hit_targets.get(id, [])))


func _scaled_rect(source_rect: Rect2) -> Rect2:
	var start := Vector2(
		roundf(source_rect.position.x * _scale.x),
		_scaled_y(source_rect.position.y)
	)
	var finish := Vector2(
		roundf(source_rect.end.x * _scale.x),
		_scaled_y(source_rect.end.y)
	)
	return Rect2(start, finish - start)


func _scaled_y(source_y: float) -> float:
	if _vertical_extra <= 0.0 or source_y <= VERTICAL_STRETCH_SOURCE_TOP:
		return roundf(source_y * _scale.y)
	if source_y >= VERTICAL_STRETCH_SOURCE_BOTTOM:
		return roundf(source_y * _scale.y + _vertical_extra)
	var progress := inverse_lerp(
		VERTICAL_STRETCH_SOURCE_TOP,
		VERTICAL_STRETCH_SOURCE_BOTTOM,
		source_y,
	)
	return roundf(source_y * _scale.y + _vertical_extra * progress)


func _scaled_font_size(size_at_1920: int) -> int:
	return maxi(1, roundi(float(size_at_1920) * _design_scale))


func _scaled_spacing(value_at_1920: float) -> float:
	return roundf(value_at_1920 * _design_scale)


func _apply_visual_rect(control: Control, button: BaseButton) -> void:
	var visual_value: Variant = button.get_meta(
		"visual_rect_local",
		Rect2(Vector2.ZERO, button.size),
	)
	var visual_rect := (
		visual_value as Rect2
		if visual_value is Rect2
		else Rect2(Vector2.ZERO, button.size)
	)
	control.position = visual_rect.position
	control.size = visual_rect.size


func _minimum_touch_rect(target_rect: Rect2, parent_rect: Rect2) -> Rect2:
	var desired_size := Vector2(
		maxf(target_rect.size.x, MINIMUM_TOUCH_SIZE.x),
		maxf(target_rect.size.y, MINIMUM_TOUCH_SIZE.y),
	)
	var position := target_rect.get_center() - desired_size * 0.5
	if desired_size.x <= parent_rect.size.x:
		position.x = clampf(
			position.x,
			parent_rect.position.x,
			parent_rect.end.x - desired_size.x,
		)
	if desired_size.y <= parent_rect.size.y:
		position.y = clampf(
			position.y,
			parent_rect.position.y,
			parent_rect.end.y - desired_size.y,
		)
	return Rect2(position.round(), desired_size.round())


func _rect(value: Variant) -> Rect2:
	if typeof(value) != TYPE_ARRAY:
		return Rect2()
	var values := value as Array
	if values.size() != 4:
		return Rect2()
	return Rect2(
		float(values[0]),
		float(values[1]),
		float(values[2]),
		float(values[3])
	)


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}


func _find_provider(provider_id: String) -> Dictionary:
	for value: Variant in _data.get("providers", []) as Array:
		var provider := value as Dictionary
		if str(provider.get("providerId", "")) == provider_id:
			return provider
	var providers := _data.get("providers", []) as Array
	return providers[0] as Dictionary if not providers.is_empty() else {}


func _action_enabled(action_key: String) -> bool:
	return UiViewModel.action_enabled(
		UiViewModel.action(_view_model, action_key)
	)


func _operation_loading() -> bool:
	return UiViewModel.operation_status(_view_model) == &"loading"


func _is_placeholder_data() -> bool:
	return (
		str(_data.get("source", "")) == "placeholder"
		or str(_data.get("capabilityMode", "")) == "placeholder"
	)


func _formal_status_text() -> String:
	var provider := _find_provider(_selected_provider_id)
	if bool(provider.get("customGroup", false)):
		match str(
			(_view_model.get("operation", {}) as Dictionary).get(
				"status",
				"idle",
			)
		):
			"loading":
				return "正在检查"
			"error", "rejected":
				return "需要处理"
	var published := str(
		_data.get("formalStatusLabel", "")
	).strip_edges()
	if not published.is_empty():
		return published
	if _is_placeholder_data():
		return "开发预览"
	return (
		"连接已通过"
		if bool(_data.get("formalReady", false))
		else "请完成模型设置"
	)


func _formal_status_tone() -> String:
	var operation := _view_model.get("operation", {}) as Dictionary
	var operation_status := str(operation.get("status", "idle"))
	if operation_status == "loading":
		return "loading"
	if operation_status in ["error", "rejected"]:
		return "error"
	var provider := _find_provider(_selected_provider_id)
	var connection := provider.get("connection", {}) as Dictionary
	var provider_status := str(connection.get("status", ""))
	if operation_status == "success" or provider_status == "available":
		return "success"
	if provider_status in ["auth_failed", "timeout", "network_unavailable"]:
		return "error"
	return "warning"


func _compact_provider_status_label(
	status: String,
	fallback: String
) -> String:
	match status:
		"available":
			return "连接可用"
		"checking":
			return "检查中"
		"unchecked":
			return "待检查"
		"auth_failed":
			return "鉴权失败"
		"billing_failed":
			return "账户异常"
		"rate_limited":
			return "请求过于频繁"
		"timeout":
			return "请求超时"
		"network_unavailable":
			return "网络不可用"
		"disabled":
			return "已停用"
		"unavailable":
			return "不可用"
		_:
			return fallback


func _status_color(status: String) -> Color:
	match status:
		"available":
			return ProviderTheme.COMPOSITE_SUCCESS
		"auth_failed", "timeout", "network_unavailable":
			return ProviderTheme.COMPOSITE_ERROR
		_:
			return ProviderTheme.COMPOSITE_WARNING


func _tone_color(tone: String) -> Color:
	match tone:
		"success":
			return ProviderTheme.COMPOSITE_SUCCESS
		"error":
			return ProviderTheme.COMPOSITE_ERROR
		"warning":
			return ProviderTheme.COMPOSITE_WARNING
		_:
			return ProviderTheme.COMPOSITE_MUTED


func _operation_title(
	operation: Dictionary,
	connection: Dictionary,
	error_data: Dictionary
) -> String:
	match str(operation.get("status", "idle")):
		"loading":
			return "正在检查连接"
		"success":
			return (
				"开发预览检查通过"
				if _is_placeholder_data()
				else "连接检查通过"
			)
		"rejected":
			return "配置需要修正"
		"error":
			return "连接检查失败"
		"disabled":
			return (
				"开发预览不可用"
				if _is_placeholder_data()
				else "当前无法检查连接"
			)
		_:
			return (
				"连接正常"
				if str(connection.get("status", "")) == "available"
				else str(connection.get("label", "等待检查"))
			)


func _operation_message(
	operation: Dictionary,
	connection: Dictionary,
	error_data: Dictionary
) -> String:
	if _is_placeholder_data():
		match str(operation.get("status", "idle")):
			"loading":
				return "占位数据，正在执行同结构检查。"
			"rejected":
				return "保留上次确认配置，请修正后重试。"
			"error":
				return _public_operation_error_message(error_data)
			"disabled":
				return "等待 TownUiAdapter 提供正式接口。"
			_:
				return "占位数据，未连接真实 Provider。"
	if not error_data.is_empty():
		return _public_operation_error_message(error_data)
	var operation_message := str(operation.get("message", ""))
	if not operation_message.is_empty():
		return operation_message
	return str(connection.get("message", "等待检查。"))


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
	if operation_status == "error":
		return "error"
	if operation_status == "success" or provider_status == "available":
		return "success"
	if operation_status == "disabled":
		return "disabled"
	if (
		operation_status == "rejected"
		or error_kind == "rate_limit"
		or provider_status in ["rate_limited", "checking"]
	):
		return "warning"
	return (
		"error"
		if provider_status in [
			"auth_failed",
			"timeout",
			"network_error",
			"network_unavailable",
		]
		else "warning"
	)


func _capability_labels(capabilities: Array) -> String:
	var labels: Array[String] = []
	for value: Variant in capabilities:
		match str(value):
			"decision_json":
				labels.append("JSON")
			"dialogue":
				labels.append("对话")
			"memory_summary":
				labels.append("记忆")
			"streaming":
				labels.append("流式")
			"image_understanding":
				labels.append("图像")
			_:
				pass
	return " · ".join(labels)
