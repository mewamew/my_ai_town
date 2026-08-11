class_name ProviderSettingsTheme
extends RefCounted


const MAIN_MENU_TYPOGRAPHY := preload(
	"res://ui/startup/StartupButtonImageTheme.gd"
)
const FONT_PATH := MAIN_MENU_TYPOGRAPHY.MAIN_MENU_FONT_PATH
const MAIN_MENU_EMBOLDEN := 0.0
const RUNTIME_ASSET_ROOT := (
	"res://assets/ui/provider_settings/component_assets/runtime"
)
const REGISTRY_PATH := (
	RUNTIME_ASSET_ROOT
	+ "/provider_settings_component_registry_v2.json"
)
const PAGE_SHELL_PATH := (
	RUNTIME_ASSET_ROOT
	+ "/composite/page_shell/provider_settings_page_shell_v1.png"
)
const COMPOSITE_DYNAMIC_CARD_BACKGROUND_PATH := (
	RUNTIME_ASSET_ROOT
	+ "/composite/page_shell/provider_settings_page_dynamic_cards_v2.png"
)
const STANDARD_BACKGROUND_PATH := (
	RUNTIME_ASSET_ROOT
	+ "/composite/page_shell/provider_settings_standard_v4.png"
)
const CUSTOM_LOCAL_BACKGROUND_PATH := (
	RUNTIME_ASSET_ROOT
	+ "/composite/page_shell/provider_settings_custom_local_v4.png"
)
const CUSTOM_302_BACKGROUND_PATH := (
	RUNTIME_ASSET_ROOT
	+ "/composite/page_shell/provider_settings_custom_302_v4.png"
)
const CUSTOM_COMPATIBLE_BACKGROUND_PATH := (
	RUNTIME_ASSET_ROOT
	+ "/composite/page_shell/provider_settings_custom_compatible_v4.png"
)
const SECTION_FRAME_PATH := (
	RUNTIME_ASSET_ROOT
	+ "/base_ninepatch/section_frame/section_frame_v1.png"
)
const CONTENT_SLOT_PATH := (
	RUNTIME_ASSET_ROOT
	+ "/base_ninepatch/content_slot/content_slot_v1.png"
)
const CUSTOM_INPUT_FIELD_PATH := (
	RUNTIME_ASSET_ROOT
	+ "/base_ninepatch/custom_input_field/custom_input_field_v1.png"
)
const BUTTON_ROOT := (
	RUNTIME_ASSET_ROOT + "/base_ninepatch/buttons"
)
const SUCCESS_BUTTON_ROOT := (
	RUNTIME_ASSET_ROOT + "/base_ninepatch/buttons_success"
)
const CUSTOM_SUCCESS_BUTTON_PATH := (
	SUCCESS_BUTTON_ROOT + "/button_success_normal_v2.png"
)
const CUSTOM_SECONDARY_BUTTON_PATH := (
	RUNTIME_ASSET_ROOT
	+ "/base_ninepatch/buttons_secondary/button_secondary_normal_v2.png"
)
const CUSTOM_LOADING_BUTTON_PATH := (
	RUNTIME_ASSET_ROOT
	+ "/base_ninepatch/buttons_loading/button_loading_v2.png"
)
const EXACT_BUTTON_ROOT := RUNTIME_ASSET_ROOT + "/exact_buttons"
const SAVE_CONNECTION_DISABLED_PATH := (
	EXACT_BUTTON_ROOT + "/save_connection_disabled_v3.png"
)
const SAVE_CONNECTION_NORMAL_PATH := (
	EXACT_BUTTON_ROOT + "/save_connection_normal_v4.png"
)
const DISCOVER_MODELS_DISABLED_PATH := (
	EXACT_BUTTON_ROOT + "/discover_models_disabled_v3.png"
)
const DISCOVER_MODELS_NORMAL_PATH := (
	EXACT_BUTTON_ROOT + "/discover_models_normal_v4.png"
)
const ADD_MODEL_DISABLED_PATH := (
	EXACT_BUTTON_ROOT + "/add_model_disabled_v3.png"
)
const ADD_MODEL_NORMAL_PATH := (
	EXACT_BUTTON_ROOT + "/add_model_normal_v4.png"
)
const CHECK_CONNECTION_LOADING_PATH := (
	EXACT_BUTTON_ROOT + "/check_connection_loading_v4.png"
)
const CHECK_CONNECTION_NORMAL_PATH := (
	EXACT_BUTTON_ROOT + "/check_connection_normal_v4.png"
)
const CUSTOM_SECTION_ROOT := (
	RUNTIME_ASSET_ROOT + "/composite/custom_sections"
)
const CUSTOM_CONNECTION_ROW_PATH := (
	CUSTOM_SECTION_ROOT + "/custom_connection_row_v2.png"
)
const CUSTOM_CONNECTION_TWO_ROW_PATH := (
	CUSTOM_SECTION_ROOT + "/custom_connection_two_row_v3.png"
)
const CUSTOM_MODEL_ADD_ROW_PATH := (
	CUSTOM_SECTION_ROOT + "/custom_model_add_row_v2.png"
)
const CUSTOM_DROPDOWN_ROOT := (
	RUNTIME_ASSET_ROOT + "/composite/dropdowns"
)
const CUSTOM_DROPDOWN_PANEL_PATH := (
	CUSTOM_DROPDOWN_ROOT + "/custom_connection_dropdown_panel_clean_v2.png"
)
const CUSTOM_DROPDOWN_SELECTED_PATH := (
	CUSTOM_DROPDOWN_ROOT + "/custom_connection_dropdown_selected_v1.png"
)
const CUSTOM_DROPDOWN_SCROLL_TRACK_PATH := (
	"res://assets/ui/common/scrollbar/wood_v1/variants/dropdown_short/"
	+ "scrollbar_track_wood_v1_dropdown_short.png"
)
const CUSTOM_DROPDOWN_SCROLL_THUMB_PATH := (
	"res://assets/ui/common/scrollbar/wood_v1/variants/dropdown_short/"
	+ "scrollbar_thumb_wood_v1_dropdown_short.png"
)
const CUSTOM_MODEL_DISCOVERY_PANEL_PATH := (
	CUSTOM_DROPDOWN_ROOT + "/custom_model_discovery_panel_v1.png"
)
const CUSTOM_MODEL_EMPTY_PANEL_PATH := (
	RUNTIME_ASSET_ROOT
	+ "/composite/empty_states/custom_model_empty_panel_v1.png"
)
const STATUS_LOADING_PLATE_PATH := (
	RUNTIME_ASSET_ROOT
	+ "/composite/status_strips/status_loading_v2.png"
)
const STATUS_SUCCESS_CUSTOM_PATH := (
	RUNTIME_ASSET_ROOT
	+ "/composite/status_strips/status_success_custom_v4.png"
)
const STATUS_LOADING_CUSTOM_PATH := (
	RUNTIME_ASSET_ROOT
	+ "/composite/status_strips/status_loading_custom_v5.png"
)
const STATUS_ERROR_CUSTOM_PATH := (
	RUNTIME_ASSET_ROOT
	+ "/composite/status_strips/status_error_custom_v4.png"
)
const PROVIDER_CARD_ROOT := (
	RUNTIME_ASSET_ROOT + "/composite/provider_cards"
)
const PROVIDER_CARD_SELECTED_PATH := (
	PROVIDER_CARD_ROOT + "/provider_card_selected_v1.png"
)
const PROVIDER_CARD_NEUTRAL_PATH := (
	PROVIDER_CARD_ROOT + "/provider_card_neutral_v2.png"
)
const PROVIDER_CARD_AUTH_ERROR_PATH := (
	PROVIDER_CARD_ROOT + "/provider_card_auth_error_v1.png"
)
const PROVIDER_CARD_NETWORK_ERROR_PATH := (
	PROVIDER_CARD_ROOT + "/provider_card_network_error_v1.png"
)
const PROVIDER_CARD_DISABLED_PATH := (
	PROVIDER_CARD_ROOT + "/provider_card_disabled_v1.png"
)
const PAGINATION_LEFT_PATH := (
	RUNTIME_ASSET_ROOT
	+ "/controls/pagination/pagination_left_v1.png"
)
const MEDALLION_ROOT := (
	RUNTIME_ASSET_ROOT + "/icons/provider_medallions"
)
const CUSTOM_MODEL_DELETE_PATH := (
	RUNTIME_ASSET_ROOT + "/icons/actions/custom_model_delete_v1.png"
)
const CUSTOM_KEY_ACTION_ROOT := (
	RUNTIME_ASSET_ROOT + "/icons/custom_key_actions"
)
const CUSTOM_KEY_SAVE_PATH := (
	CUSTOM_KEY_ACTION_ROOT + "/custom_connection_save_key_v1.png"
)
const CUSTOM_KEY_REVEAL_PATH := (
	CUSTOM_KEY_ACTION_ROOT + "/custom_connection_reveal_v1.png"
)
const CUSTOM_KEY_DELETE_PATH := (
	CUSTOM_KEY_ACTION_ROOT + "/custom_connection_delete_key_v1.png"
)
const PROVIDER_CHECKING_CONNECTION_PATH := (
	RUNTIME_ASSET_ROOT + "/icons/status/provider_checking_connection_v1.png"
)
const CUSTOM_MODEL_DELETE_BLOCKED_PATH := (
	RUNTIME_ASSET_ROOT + "/icons/status/custom_model_delete_blocked_v1.png"
)
const PROVIDER_CLOCK_HANDS_PATH := (
	RUNTIME_ASSET_ROOT + "/icons/header/provider_clock_hands_v1.png"
)
const PROVIDER_BACK_ARROW_PATH := (
	RUNTIME_ASSET_ROOT + "/icons/header/provider_back_arrow_v1.png"
)
const PROVIDER_FORMAL_SUCCESS_PATH := (
	RUNTIME_ASSET_ROOT + "/icons/status/provider_formal_success_v1.png"
)
const PROVIDER_FORMAL_LOADING_PATH := (
	RUNTIME_ASSET_ROOT + "/icons/status/provider_checking_connection_v1.png"
)
const PROVIDER_FORMAL_ERROR_PATH := (
	RUNTIME_ASSET_ROOT + "/icons/status/provider_formal_error_v1.png"
)
const PROVIDER_AVAILABLE_INDICATOR_PATH := (
	RUNTIME_ASSET_ROOT + "/icons/status/provider_available_indicator_v1.png"
)
const CUSTOM_CONNECTION_CHEVRON_PATH := (
	RUNTIME_ASSET_ROOT + "/icons/actions/custom_connection_chevron_v1.png"
)
const PROVIDER_TOGGLE_ROOT := RUNTIME_ASSET_ROOT + "/controls/toggles"
const PROVIDER_TOGGLE_OFF_PATH := (
	PROVIDER_TOGGLE_ROOT + "/provider_toggle_off_v1.png"
)
const PROVIDER_TOGGLE_ON_PATH := (
	PROVIDER_TOGGLE_ROOT + "/provider_toggle_on_v1.png"
)

const INK := Color("3f2818")
const INK_MUTED := Color("76583d")
const PAPER := Color("fff0cc")
const PAPER_LIGHT := Color("fff8e6")
const PAPER_DISABLED := Color("cbbe9f")
const WOOD := Color("6c3d20")
const WOOD_DARK := Color("321d12")
const WOOD_LIGHT := Color("a96a35")
const TERRACOTTA := Color("b94d2d")
const TERRACOTTA_DARK := Color("742b1b")
const MOSS := Color("557b2a")
const MOSS_DARK := Color("36511e")
const HONEY := Color("e5a84b")
const WARNING := Color("8a611d")
const ERROR := Color("a7352b")
const ERROR_DARK := Color("69251f")
const SHADOW := Color("1e120b78")
const OVERLAY := Color("17110c8c")
const COMPOSITE_INK := Color("332014")
const COMPOSITE_MUTED := Color("5b402c")
const COMPOSITE_SUCCESS := Color("2f501b")
const COMPOSITE_ERROR := Color("762019")
const COMPOSITE_WARNING := Color("5d3e12")
const COMPOSITE_BUTTON_TEXT := Color("fff3d8")
const COMPOSITE_BUTTON_OUTLINE := Color("68260f")

static var _texture_cache: Dictionary = {}
static var _font_cache: Dictionary = {}


static func create() -> Theme:
	var page_theme := Theme.new()
	var font_file := ResourceLoader.load(FONT_PATH, "FontFile") as FontFile
	if font_file == null:
		push_error("Provider settings font failed to load: %s" % FONT_PATH)
		return page_theme
	var font := FontVariation.new()
	font.base_font = font_file
	font.spacing_glyph = 2
	font.spacing_space = 0
	font.variation_embolden = MAIN_MENU_EMBOLDEN
	page_theme.default_font = font
	page_theme.default_font_size = 32

	page_theme.set_color("font_color", "Label", INK)
	page_theme.set_color("font_shadow_color", "Label", Color.TRANSPARENT)
	page_theme.set_constant("line_spacing", "Label", 8)
	page_theme.set_constant("outline_size", "Label", 0)

	page_theme.set_color("font_color", "Button", PAPER_LIGHT)
	page_theme.set_color("font_hover_color", "Button", PAPER_LIGHT)
	page_theme.set_color("font_pressed_color", "Button", PAPER_LIGHT)
	page_theme.set_color("font_focus_color", "Button", PAPER_LIGHT)
	page_theme.set_color(
		"font_disabled_color",
		"Button",
		Color("fff8e6cc")
	)
	page_theme.set_font_size("font_size", "Button", 32)
	page_theme.set_stylebox(
		"normal",
		"Button",
		button_style("quiet", "normal")
	)
	page_theme.set_stylebox(
		"hover",
		"Button",
		button_style("quiet", "hover")
	)
	page_theme.set_stylebox(
		"pressed",
		"Button",
		button_style("quiet", "pressed")
	)
	page_theme.set_stylebox(
		"focus",
		"Button",
		button_style("quiet", "focus")
	)
	page_theme.set_stylebox(
		"disabled",
		"Button",
		button_style("quiet", "disabled")
	)

	page_theme.set_color("font_color", "LineEdit", INK)
	page_theme.set_color("font_placeholder_color", "LineEdit", INK_MUTED)
	page_theme.set_color("caret_color", "LineEdit", TERRACOTTA_DARK)
	page_theme.set_color("selection_color", "LineEdit", Color(MOSS, 0.45))
	page_theme.set_font_size("font_size", "LineEdit", 32)
	page_theme.set_stylebox("normal", "LineEdit", input_style("normal"))
	page_theme.set_stylebox("focus", "LineEdit", input_style("focus"))
	page_theme.set_stylebox(
		"read_only",
		"LineEdit",
		input_style("disabled")
	)

	page_theme.set_stylebox("panel", "PanelContainer", paper_panel())
	page_theme.set_stylebox(
		"panel",
		"ScrollContainer",
		empty_style()
	)
	page_theme.set_stylebox(
		"panel",
		"PopupMenu",
		paper_panel(WOOD, 4, 16)
	)
	page_theme.set_stylebox("normal", "CheckButton", empty_style())
	page_theme.set_stylebox("hover", "CheckButton", empty_style())
	page_theme.set_stylebox("pressed", "CheckButton", empty_style())
	page_theme.set_stylebox("focus", "CheckButton", focus_style())
	page_theme.set_stylebox("disabled", "CheckButton", empty_style())
	return page_theme


static func atlas_skin_ready() -> bool:
	return runtime_assets_ready()


static func runtime_assets_ready() -> bool:
	if not FileAccess.file_exists(REGISTRY_PATH):
		return false
	for path: String in [
		PAGE_SHELL_PATH,
		COMPOSITE_DYNAMIC_CARD_BACKGROUND_PATH,
		STANDARD_BACKGROUND_PATH,
		CUSTOM_LOCAL_BACKGROUND_PATH,
		CUSTOM_302_BACKGROUND_PATH,
		CUSTOM_COMPATIBLE_BACKGROUND_PATH,
		SECTION_FRAME_PATH,
		CONTENT_SLOT_PATH,
		CUSTOM_INPUT_FIELD_PATH,
		"%s/button_normal_v1.png" % BUTTON_ROOT,
		"%s/button_hover_v1.png" % BUTTON_ROOT,
		"%s/button_pressed_v1.png" % BUTTON_ROOT,
		"%s/button_disabled_v1.png" % BUTTON_ROOT,
		PROVIDER_CARD_SELECTED_PATH,
		PROVIDER_CARD_NEUTRAL_PATH,
		PROVIDER_CARD_AUTH_ERROR_PATH,
		PROVIDER_CARD_NETWORK_ERROR_PATH,
		PROVIDER_CARD_DISABLED_PATH,
		PAGINATION_LEFT_PATH,
		"%s/provider_medallion_success_v1.png" % MEDALLION_ROOT,
		CUSTOM_SUCCESS_BUTTON_PATH,
		CUSTOM_SECONDARY_BUTTON_PATH,
		CUSTOM_LOADING_BUTTON_PATH,
		SAVE_CONNECTION_DISABLED_PATH,
		SAVE_CONNECTION_NORMAL_PATH,
		DISCOVER_MODELS_DISABLED_PATH,
		DISCOVER_MODELS_NORMAL_PATH,
		ADD_MODEL_DISABLED_PATH,
		ADD_MODEL_NORMAL_PATH,
		CHECK_CONNECTION_LOADING_PATH,
		CHECK_CONNECTION_NORMAL_PATH,
		CUSTOM_CONNECTION_ROW_PATH,
		CUSTOM_CONNECTION_TWO_ROW_PATH,
		CUSTOM_MODEL_ADD_ROW_PATH,
		CUSTOM_DROPDOWN_PANEL_PATH,
		CUSTOM_DROPDOWN_SELECTED_PATH,
		CUSTOM_DROPDOWN_SCROLL_TRACK_PATH,
		CUSTOM_DROPDOWN_SCROLL_THUMB_PATH,
		CUSTOM_MODEL_DISCOVERY_PANEL_PATH,
		CUSTOM_MODEL_EMPTY_PANEL_PATH,
		STATUS_LOADING_PLATE_PATH,
		STATUS_SUCCESS_CUSTOM_PATH,
		STATUS_LOADING_CUSTOM_PATH,
		STATUS_ERROR_CUSTOM_PATH,
		PROVIDER_CHECKING_CONNECTION_PATH,
		CUSTOM_MODEL_DELETE_BLOCKED_PATH,
		CUSTOM_KEY_SAVE_PATH,
		CUSTOM_KEY_REVEAL_PATH,
		CUSTOM_KEY_DELETE_PATH,
		PROVIDER_CLOCK_HANDS_PATH,
		PROVIDER_BACK_ARROW_PATH,
		PROVIDER_FORMAL_SUCCESS_PATH,
		PROVIDER_FORMAL_ERROR_PATH,
		PROVIDER_AVAILABLE_INDICATOR_PATH,
		CUSTOM_CONNECTION_CHEVRON_PATH,
		PROVIDER_TOGGLE_OFF_PATH,
		PROVIDER_TOGGLE_ON_PATH,
	]:
		if _texture(path) == null:
			return false
	return true


static func composite_background_path(provider: Dictionary) -> String:
	if not bool(provider.get("customGroup", false)):
		return STANDARD_BACKGROUND_PATH
	if bool(provider.get("deletableConnection", false)):
		return CUSTOM_COMPATIBLE_BACKGROUND_PATH
	match str(provider.get("providerId", "")):
		"302-ai":
			return CUSTOM_302_BACKGROUND_PATH
		"ollama-cloud":
			return CUSTOM_COMPATIBLE_BACKGROUND_PATH
		"openai-compatible":
			return CUSTOM_COMPATIBLE_BACKGROUND_PATH
		_:
			return CUSTOM_LOCAL_BACKGROUND_PATH


static func board_panel(compact: bool = false) -> StyleBox:
	return _texture_style(
		PAGE_SHELL_PATH,
		[96, 72, 96, 72],
		(
			[24, 20, 24, 20]
			if compact
			else [44, 28, 56, 48]
		)
	)


static func paper_panel(
	accent: Color = WOOD,
	border_width: int = 6,
	margin: int = 20
) -> StyleBox:
	if runtime_assets_ready():
		return _texture_style(
			SECTION_FRAME_PATH,
			[72, 52, 72, 52],
			[margin, margin, margin, margin]
		)
	var fallback := _flat(
		PAPER_LIGHT,
		accent,
		border_width,
		margin
	)
	return fallback


static func section_panel() -> StyleBox:
	return _texture_style(
		SECTION_FRAME_PATH,
		[72, 52, 72, 52],
		[24, 20, 24, 20]
	)


static func provider_header_panel() -> StyleBox:
	return _texture_style(
		SECTION_FRAME_PATH,
		[72, 52, 72, 52],
		[64, 24, 48, 24]
	)


static func provider_card_style(
	selected: bool,
	tone: String,
	state: String
) -> StyleBox:
	var asset_path := PROVIDER_CARD_NEUTRAL_PATH
	if state == "disabled":
		asset_path = PROVIDER_CARD_DISABLED_PATH
	elif selected:
		asset_path = PROVIDER_CARD_SELECTED_PATH
	elif tone == "disabled":
		asset_path = PROVIDER_CARD_DISABLED_PATH
	elif tone == "error":
		asset_path = PROVIDER_CARD_NETWORK_ERROR_PATH
	elif tone == "warning":
		asset_path = PROVIDER_CARD_AUTH_ERROR_PATH
	var style := _texture_style(
		asset_path,
		[48, 64, 48, 36],
		[14, 12, 14, 12]
	)
	if style is StyleBoxTexture:
		var textured := style as StyleBoxTexture
		match state:
			"hover", "focus":
				textured.modulate_color = Color("fff3c2")
			"pressed":
				textured.modulate_color = Color("e8d7ad")
	return style


static func model_card_style(
	_selected: bool,
	state: String
) -> StyleBox:
	var style := _texture_style(
		CONTENT_SLOT_PATH,
		[56, 36, 56, 36],
		[14, 12, 14, 12],
	)
	if style is StyleBoxTexture:
		var textured := style as StyleBoxTexture
		match state:
			"hover", "focus":
				textured.modulate_color = Color("fff8dc")
			"pressed":
				textured.modulate_color = Color("e8d7ad")
			"disabled":
				textured.modulate_color = Color("c9bfa6")
	return style


static func pagination_texture() -> Texture2D:
	return _texture(PAGINATION_LEFT_PATH)


static func status_style(tone: String) -> StyleBox:
	var style := _texture_style(
		CONTENT_SLOT_PATH,
		[56, 36, 56, 36],
		[18, 14, 18, 14]
	)
	if style is StyleBoxTexture:
		var textured := style as StyleBoxTexture
		match tone:
			"success":
				textured.modulate_color = Color("e9f0c1")
			"warning":
				textured.modulate_color = Color("f7e1ad")
			"error":
				textured.modulate_color = Color("f4c9b2")
			"disabled":
				textured.modulate_color = Color("b8aa91")
	return style


static func medallion_texture(provider_status: String) -> Texture2D:
	var asset_id := "provider_medallion_network_v1.png"
	if provider_status == "available":
		asset_id = "provider_medallion_success_v1.png"
	elif provider_status == "auth_failed":
		asset_id = "provider_medallion_auth_v1.png"
	elif provider_status in [
		"not_configured",
		"saved_unchecked",
		"checking",
		"rate_limited",
	]:
		asset_id = "provider_medallion_auth_v1.png"
	return _texture("%s/%s" % [MEDALLION_ROOT, asset_id])


static func chip_style(tone: String = "quiet") -> StyleBox:
	return _flat(
		Color("eef0c4") if tone == "success" else Color("fff6df"),
		tone_color(tone),
		3,
		8
	)


static func input_style(state: String) -> StyleBox:
	var style := _texture_style(
		CONTENT_SLOT_PATH,
		[56, 36, 56, 36],
		[24, 12, 24, 12]
	)
	if style is StyleBoxTexture:
		var textured := style as StyleBoxTexture
		if state == "focus":
			textured.modulate_color = Color("fff4c9")
		elif state == "disabled":
			textured.modulate_color = Color("b8aa91")
	return style


static func button_style(variant: String, state: String) -> StyleBox:
	if variant in ["success", "secondary", "loading"]:
		var asset_path := CUSTOM_SUCCESS_BUTTON_PATH
		if state == "disabled" or variant == "loading":
			asset_path = CUSTOM_LOADING_BUTTON_PATH
		elif variant == "secondary":
			asset_path = CUSTOM_SECONDARY_BUTTON_PATH
		var generated_style := _texture_style(
			asset_path,
			[44, 36, 44, 36],
			[16, 12, 16, 12],
		)
		if generated_style is StyleBoxTexture:
			var textured := generated_style as StyleBoxTexture
			match state:
				"hover", "focus":
					textured.modulate_color = Color("fff4c7")
				"pressed":
					textured.modulate_color = Color("d8c18e")
		return generated_style
	var asset_id := "button_normal"
	match state:
		"hover", "focus":
			asset_id = "button_hover"
		"pressed":
			asset_id = "button_pressed"
		"disabled":
			asset_id = "button_disabled"
	return _texture_style(
		"%s/%s_v1.png" % [BUTTON_ROOT, asset_id],
		[52, 38, 52, 38],
		[16, 12, 16, 12]
	)


static func exact_action_button_style(
	action_id: String,
	state: String = "disabled",
) -> StyleBox:
	var asset_path := ""
	match action_id:
		"custom_connection_save":
			asset_path = (
				SAVE_CONNECTION_DISABLED_PATH
				if state == "disabled"
				else SAVE_CONNECTION_NORMAL_PATH
			)
		"api_model_discover":
			asset_path = (
				DISCOVER_MODELS_DISABLED_PATH
				if state == "disabled"
				else DISCOVER_MODELS_NORMAL_PATH
			)
		"api_model_add":
			asset_path = (
				ADD_MODEL_DISABLED_PATH
				if state == "disabled"
				else ADD_MODEL_NORMAL_PATH
			)
		"check_connection_loading":
			asset_path = CHECK_CONNECTION_LOADING_PATH
		"check_connection_normal":
			asset_path = CHECK_CONNECTION_NORMAL_PATH
		_:
			return button_style("loading", "disabled")
	# 四张状态图按各自按钮框的实际宽高比生成，整图缩放可保留完整边框。
	return _texture_style(asset_path, [0, 0, 0, 0], [12, 8, 12, 8])


static func provider_toggle_texture(enabled: bool) -> Texture2D:
	return _texture(
		PROVIDER_TOGGLE_ON_PATH if enabled else PROVIDER_TOGGLE_OFF_PATH
	)


static func provider_identity_medallion(
	provider_id: String,
	custom_group := false,
) -> Texture2D:
	var asset_id := "provider_medallion_network_v1.png"
	if custom_group:
		asset_id = "provider_medallion_custom_model_v1.png"
	elif provider_id == "deepseek":
		asset_id = "provider_medallion_success_v1.png"
	elif provider_id == "kimi":
		asset_id = "provider_medallion_auth_v1.png"
	return _texture("%s/%s" % [MEDALLION_ROOT, asset_id])


static func custom_model_delete_texture() -> Texture2D:
	return _texture(CUSTOM_MODEL_DELETE_PATH)


static func custom_key_save_texture() -> Texture2D:
	return _texture(CUSTOM_KEY_SAVE_PATH)


static func custom_key_reveal_texture() -> Texture2D:
	return _texture(CUSTOM_KEY_REVEAL_PATH)


static func custom_key_delete_texture() -> Texture2D:
	return _texture(CUSTOM_KEY_DELETE_PATH)


static func provider_checking_connection_texture() -> Texture2D:
	return _texture(PROVIDER_CHECKING_CONNECTION_PATH)


static func provider_back_arrow_texture() -> Texture2D:
	return _texture(PROVIDER_BACK_ARROW_PATH)


static func provider_formal_status_texture(tone: String) -> Texture2D:
	match tone:
		"loading":
			return _texture(PROVIDER_FORMAL_LOADING_PATH)
		"error", "warning":
			return _texture(PROVIDER_FORMAL_ERROR_PATH)
		_:
			return _texture(PROVIDER_FORMAL_SUCCESS_PATH)


static func provider_available_indicator_texture() -> Texture2D:
	return _texture(PROVIDER_AVAILABLE_INDICATOR_PATH)


static func custom_connection_chevron_texture() -> Texture2D:
	return _texture(CUSTOM_CONNECTION_CHEVRON_PATH)


static func custom_model_delete_blocked_texture() -> Texture2D:
	return _texture(CUSTOM_MODEL_DELETE_BLOCKED_PATH)


static func provider_loading_status_texture() -> Texture2D:
	return _texture(STATUS_LOADING_PLATE_PATH)


static func connection_status_texture(tone: String) -> Texture2D:
	match tone:
		"loading":
			return _texture(STATUS_LOADING_CUSTOM_PATH)
		"error", "warning":
			return _texture(STATUS_ERROR_CUSTOM_PATH)
		_:
			return _texture(STATUS_SUCCESS_CUSTOM_PATH)


static func custom_section_texture(section_id: String) -> Texture2D:
	match section_id:
		"custom_connection_two_row":
			return _texture(CUSTOM_CONNECTION_TWO_ROW_PATH)
		"custom_model_add":
			return _texture(CUSTOM_MODEL_ADD_ROW_PATH)
		_:
			return _texture(CUSTOM_CONNECTION_ROW_PATH)


static func custom_dropdown_panel_style() -> StyleBox:
	return _texture_style(
		CUSTOM_DROPDOWN_PANEL_PATH,
		[12, 8, 12, 8],
		[6, 6, 6, 6],
	)


static func custom_dropdown_selected_style() -> StyleBox:
	return _texture_style(
		CUSTOM_DROPDOWN_SELECTED_PATH,
		[10, 8, 10, 8],
		[10, 4, 10, 4],
	)


static func custom_dropdown_neutral_row_style() -> StyleBox:
	return StyleBoxEmpty.new()


static func custom_dropdown_scroll_track_style() -> StyleBox:
	return _texture_style(
		CUSTOM_DROPDOWN_SCROLL_TRACK_PATH,
		[8, 28, 8, 28],
		[0, 0, 0, 0],
	)


static func custom_dropdown_scroll_thumb_style() -> StyleBox:
	return _texture_style(
		CUSTOM_DROPDOWN_SCROLL_THUMB_PATH,
		[12, 24, 12, 24],
		[0, 0, 0, 0],
	)


static func custom_model_discovery_texture() -> Texture2D:
	return _texture(CUSTOM_MODEL_DISCOVERY_PANEL_PATH)


static func custom_model_empty_texture() -> Texture2D:
	return _texture(CUSTOM_MODEL_EMPTY_PANEL_PATH)


static func empty_style() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


static func custom_input_overlay_style(focused := false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.content_margin_left = 18.0
	style.content_margin_top = 8.0
	style.content_margin_right = 18.0
	style.content_margin_bottom = 8.0
	if focused:
		style.border_color = HONEY
		style.set_border_width_all(2)
		style.set_corner_radius_all(3)
	return style


static func focus_style() -> StyleBoxFlat:
	return _flat(Color.TRANSPARENT, HONEY, 4, 4)


static func composite_font(token: String) -> Font:
	if _font_cache.has(token):
		return _font_cache[token] as Font
	var base_font := ResourceLoader.load(FONT_PATH, "Font") as Font
	if base_font == null:
		return null
	var variation := FontVariation.new()
	variation.base_font = base_font
	variation.spacing_glyph = 2
	variation.spacing_space = 0
	variation.variation_embolden = MAIN_MENU_EMBOLDEN
	_font_cache[token] = variation
	return variation


static func composite_selected_font(token: String) -> Font:
	var cache_key := "selected:%s" % token
	if _font_cache.has(cache_key):
		return _font_cache[cache_key] as Font
	var base_font := ResourceLoader.load(FONT_PATH, "Font") as Font
	if base_font == null:
		return null
	var variation := FontVariation.new()
	variation.base_font = base_font
	variation.spacing_glyph = 2
	variation.spacing_space = 0
	# 选中态只通过颜色表达，字重继续服从主菜单的全局字体规范。
	# 额外加粗会让中英文宽度变化，造成模型卡文字相对底板横向漂移。
	variation.variation_embolden = MAIN_MENU_EMBOLDEN
	_font_cache[cache_key] = variation
	return variation


static func transparent_hit_style(state: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.anti_aliasing = false
	style.set_corner_radius_all(0)
	style.set_border_width_all(0)
	match state:
		"hover":
			style.bg_color = Color("ffe59a18")
		"pressed":
			style.bg_color = Color("4d281524")
		"focus":
			style.bg_color = Color("ffd56a24")
		_:
			style.bg_color = Color.TRANSPARENT
	return style


static func transparent_input_style() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


static func custom_input_field_style() -> StyleBox:
	return _texture_style(
		CUSTOM_INPUT_FIELD_PATH,
		[20, 14, 20, 14],
		[18, 8, 18, 8],
	)


static func tone_color(tone: String) -> Color:
	match tone:
		"success":
			return MOSS
		"warning":
			return WARNING
		"error":
			return ERROR
		"disabled":
			return Color("756956")
		"primary":
			return TERRACOTTA
		_:
			return WOOD_LIGHT


static func tone_dark_color(tone: String) -> Color:
	match tone:
		"success":
			return MOSS_DARK
		"warning":
			return WOOD
		"error":
			return ERROR_DARK
		"primary":
			return TERRACOTTA_DARK
		_:
			return WOOD_DARK


static func _flat(
	background: Color,
	border: Color,
	border_width: int,
	content_margin: int
) -> StyleBoxFlat:
	return shared_flat(background, border, border_width, content_margin)


static func shared_flat(
	background: Color,
	border: Color,
	border_width: int,
	content_margin: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(2)
	style.anti_aliasing = false
	style.content_margin_left = content_margin
	style.content_margin_top = content_margin
	style.content_margin_right = content_margin
	style.content_margin_bottom = content_margin
	return style


static func _texture_style(
	asset_path: String,
	patch_margins: Array,
	content_margins: Array
) -> StyleBox:
	var texture := _texture(asset_path)
	if texture == null:
		return _flat(PAPER_LIGHT, WOOD, 4, 12)
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = float(patch_margins[0])
	style.texture_margin_top = float(patch_margins[1])
	style.texture_margin_right = float(patch_margins[2])
	style.texture_margin_bottom = float(patch_margins[3])
	style.content_margin_left = float(content_margins[0])
	style.content_margin_top = float(content_margins[1])
	style.content_margin_right = float(content_margins[2])
	style.content_margin_bottom = float(content_margins[3])
	style.draw_center = true
	style.axis_stretch_horizontal = (
		StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	)
	style.axis_stretch_vertical = (
		StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	)
	return style


static func _texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path] as Texture2D
	var texture := ResourceLoader.load(path, "Texture2D") as Texture2D
	if texture != null:
		_texture_cache[path] = texture
	return texture
