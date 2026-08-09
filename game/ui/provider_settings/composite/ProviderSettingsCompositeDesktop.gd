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
const ASSET_PATH := (
	ProviderTheme.COMPOSITE_DYNAMIC_CARD_BACKGROUND_PATH
)
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

var key_edit: LineEdit
var base_url_edit: LineEdit
var model_name_edit: LineEdit
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
	var texture := ResourceLoader.load(ASSET_PATH, "Texture2D") as Texture2D
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
	formal_badge = _add_slot_label(
		header,
		header_rect,
		"formal_status",
		_formal_status_text(),
		ProviderTheme.COMPOSITE_WARNING
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


func _build_key_section(
	provider: Dictionary,
	detail_rect: Rect2
) -> void:
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
		str(key_data.get("maskedValue", "••••••••••••"))
		if bool(key_data.get("saved", false))
		else "请输入 API Key"
	)
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
	reveal.disabled = (
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
	delete.disabled = (
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


func _build_base_url_section(
	provider: Dictionary,
	detail_rect: Rect2
) -> void:
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
	base_url_edit.placeholder_text = (
		"例如：https://api.siliconflow.cn/v1/chat/completions"
		if str(provider.get("providerId", "")) == "openai-compatible"
		else "留空使用官方默认地址"
	)
	base_url_edit.tooltip_text = (
		"请填写完整的 Chat Completions API 地址，例如：https://api.siliconflow.cn/v1/chat/completions"
		if str(provider.get("providerId", "")) == "openai-compatible"
		else "留空时使用该服务商的官方默认地址"
	)
	base_url_edit.text_changed.connect(func(value: String) -> void:
		ui_action.emit(&"ui.draft_base_url", {"value": value})
	)
	base_url_edit.text_submitted.connect(func(value: String) -> void:
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


func _build_models_section(
	provider: Dictionary,
	detail_rect: Rect2
) -> void:
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
		"模型与能力",
		ProviderTheme.COMPOSITE_INK
	)
	if str(provider.get("providerId", "")) == "openai-compatible":
		_build_custom_model_name_input(owner, region_rect, provider)
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
		ProviderTheme.COMPOSITE_INK
	)
	var previous := _pagination_button(
		owner,
		region_rect,
		"model_page_previous",
		"ModelPagePrevious",
		"上一页模型",
		false,
		_model_page <= 0,
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
	)
	next.pressed.connect(func() -> void:
		_change_model_page(_model_page + 1)
	)
	for index: int in range(page_end - page_start):
		var model := models[page_start + index] as Dictionary
		var model_id := str(model.get("modelId", ""))
		var card_rect := _hit_rect("model_%d" % index)
		if (
			str(provider.get("providerId", "")) == "openai-compatible"
			and model_id == "custom"
		):
			continue
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
			)
		)
		var capability_label := _add_slot_label(
			card,
			card_rect,
			"model_%d_capabilities" % index,
			_capability_labels(
				model.get("capabilities", []) as Array
			),
			(
				ProviderTheme.COMPOSITE_SUCCESS
				if bool(model.get("enabled", false))
				else ProviderTheme.COMPOSITE_MUTED
			)
		)
		if bool(model.get("enabled", false)):
			_apply_selected_model_typography(name_label, "body")
			_apply_selected_model_typography(capability_label, "small")
	if models.size() == 1 and _model_page == 0:
		_add_slot_label(
			owner,
			region_rect,
			"model_1_name",
			"暂无其他模型",
			ProviderTheme.COMPOSITE_MUTED
		)
		_add_slot_label(
			owner,
			region_rect,
			"model_1_capabilities",
			"该服务商当前仅提供一个居民模型",
			ProviderTheme.COMPOSITE_MUTED
		)


func _build_custom_model_name_input(
	owner: Control,
	region_rect: Rect2,
	provider: Dictionary,
) -> void:
	model_name_edit = _line_edit_for_slot(
		owner,
		region_rect,
		"model_0_name",
		"ModelNameInput",
		"model_name_input",
		"ui.provider-settings.composite.model-name-input.v2",
	)
	model_name_edit.text = _draft_api_model
	model_name_edit.placeholder_text = "输入服务商模型名称"
	model_name_edit.max_length = 256
	model_name_edit.text_changed.connect(func(value: String) -> void:
		ui_action.emit(&"ui.draft_api_model", {"value": value})
	)
	model_name_edit.text_submitted.connect(func(value: String) -> void:
		ui_action.emit(
			&"provider_settings.save_api_model",
			{
				"providerId": str(provider.get("providerId", "")),
				"apiModel": value,
			},
		)
	)
	var capability_slot := _slots.get("model_0_capabilities", {}) as Dictionary
	var save_rect := _scaled_rect(
		_rect(capability_slot.get("wellRect", capability_slot.get("rect", [])))
	)
	var save := _hit_button_from_rect(
		owner,
		region_rect,
		save_rect,
		"SaveModelNameButton",
		"model_name_save",
		"operation_control",
		"ui.provider-settings.composite.model-name-save.v1",
		"composite-transparent-control",
	)
	save.text = "保存模型名称"
	save.add_theme_font_override("font", ProviderTheme.composite_font("body"))
	save.add_theme_font_size_override("font_size", _scaled_font_size(20))
	for state: String in ["font_color", "font_hover_color", "font_focus_color"]:
		save.add_theme_color_override(state, ProviderTheme.COMPOSITE_SUCCESS)
	save.add_theme_color_override(
		"font_disabled_color",
		ProviderTheme.COMPOSITE_MUTED,
	)
	save.disabled = (
		not _action_enabled("saveApiModel")
		or _operation_loading()
		or _draft_api_model.is_empty()
	)
	save.pressed.connect(func() -> void:
		ui_action.emit(
			&"provider_settings.save_api_model",
			{
				"providerId": str(provider.get("providerId", "")),
				"apiModel": model_name_edit.text,
			},
		)
	)
	model_name_edit.text_changed.connect(func(value: String) -> void:
		save.disabled = (
			not _action_enabled("saveApiModel")
			or _operation_loading()
			or value.is_empty()
		)
	)


func _pagination_button(
	parent: Control,
	parent_rect: Rect2,
	hit_id: String,
	node_name: String,
	tooltip: String,
	point_right: bool,
	disabled: bool,
) -> Button:
	var button := _hit_button(
		parent,
		parent_rect,
		hit_id,
		node_name,
		hit_id,
		"operation_control",
		"ui.provider-settings.composite.%s.v1" % hit_id,
	)
	button.tooltip_text = tooltip
	button.disabled = disabled
	var art := TextureRect.new()
	art.name = "PaginationArt"
	_apply_visual_rect(art, button)
	art.texture = ProviderTheme.pagination_texture()
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
	if _pagination_rebuild_queued:
		return
	_pagination_rebuild_queued = true
	call_deferred("_rebuild_after_pagination")


func _rebuild_after_pagination() -> void:
	_pagination_rebuild_queued = false
	UiNodeRetirement.retire_children(self)
	key_edit = null
	base_url_edit = null
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
	var tone := _operation_tone(
		str(operation.get("status", "idle")),
		str(error_data.get("kind", "")),
		str(connection.get("status", ""))
	)
	status_label = _add_slot_label(
		owner,
		region_rect,
		"connection_title",
		_operation_title(operation, connection, error_data),
		_tone_color(tone)
	)
	_add_slot_label(
		owner,
		region_rect,
		"connection_message",
		_operation_message(operation, connection, error_data),
		ProviderTheme.COMPOSITE_MUTED
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
		"检查中…" if _operation_loading() else "检查连接"
	)
	check_button.disabled = (
		not _action_enabled("checkConnection")
		or _operation_loading()
	)
	check_button.tooltip_text = "检查连接"
	_apply_button_typography(check_button)
	check_button.pressed.connect(func() -> void:
		ui_action.emit(
			&"provider_settings.check_connection",
			{"providerId": str(provider.get("providerId", ""))}
		)
	)
	ProviderButtonMotion.set_loading_state(
		check_button,
		_operation_loading(),
	)


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
) -> void:
	var texture := ProviderTheme.provider_identity_medallion(provider_id)
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
		var style := ProviderTheme.transparent_input_style()
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
	color: Color
) -> Label:
	var slot := _slots.get(slot_id, {}) as Dictionary
	var target_rect := _scaled_rect(_rect(slot.get("rect", [])))
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
