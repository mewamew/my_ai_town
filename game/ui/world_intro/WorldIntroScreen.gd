class_name WorldIntroScreen
extends Control


signal intent_requested(intent: StringName, payload: Dictionary, revision: int)
signal step_switch_confirmed(target_step: StringName, revision: int)
signal view_model_rejected(reason: String)


enum LayoutMode {
	DESKTOP,
	STANDARD,
	TABLET,
	PHONE_LANDSCAPE,
	PHONE_PORTRAIT,
}


class ValidationOverlay:
	extends Control

	var guides: Array[Dictionary] = []
	var guide_font: Font

	func _draw() -> void:
		for guide: Dictionary in guides:
			var rect := guide.get("rect", Rect2()) as Rect2
			var color := guide.get("color", Color.WHITE) as Color
			var label := String(guide.get("label", ""))
			draw_rect(rect, color, false, 3.0)
			if guide_font != null and not label.is_empty():
				draw_string(
					guide_font,
					rect.position + Vector2(6, 22),
					label,
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					16,
					color
				)


const SHELL_PATH := "res://assets/ui/world_intro/final/world_intro_resident_shell.png"
const BODY_THEME_PATH := "res://ui/common/components/ZhengGeTypography.tres"
const BUTTON_THEME_PATH := "res://ui/common/components/PrimaryButtonTypography.tres"
const CHROME_FONT_PATH := (
	"res://assets/ui/startup/fonts/noto_sans_cjk_sc_medium/"
	+ "NotoSansCJKsc-Medium.otf"
)
const PRIMARY_BUTTON_STATE_ROOT := (
	"res://assets/ui/startup/runtime/button_states"
)
const PRIMARY_BUTTON_STATE_PATHS := {
	"normal": PRIMARY_BUTTON_STATE_ROOT + "/primary_normal.png",
	"hover": PRIMARY_BUTTON_STATE_ROOT + "/primary_hover.png",
	"focus": PRIMARY_BUTTON_STATE_ROOT + "/primary_focus.png",
	"pressed": PRIMARY_BUTTON_STATE_ROOT + "/primary_pressed.png",
	"disabled": PRIMARY_BUTTON_STATE_ROOT + "/primary_disabled.png",
	"loading": PRIMARY_BUTTON_STATE_ROOT + "/primary_loading_a.png",
}

const DESKTOP_CANVAS := Vector2(1920.0, 1080.0)
const STANDARD_CANVAS := Vector2(1280.0, 720.0)
const FONT_NATIVE_GRID := 16
const FONT_CAPTION := 16
const FONT_META := 22
const FONT_SECONDARY_ACTION := 28
const FONT_BODY := 32
const FONT_COMPACT_TITLE := 40
const FONT_FLOW_TITLE := 48
const FONT_CONTENT_TITLE := 64
const TOUCH_TARGET_MIN := 48.0
const CHROME_OPTICAL_LIFT := 2.0
const FOOTER_META_OPTICAL_LIFT := 4.0
const FOOTER_HINT_OPTICAL_LIFT := 6.0
const FOOTER_ACTION_OPTICAL_LIFT := 4.0
const FOOTER_HINT_OPTICAL_SHIFT_X := -5.0
const FOOTER_ACTION_OPTICAL_SHIFT_X := -3.0
const COMPOSITE_SHELL_ASSET_ID := "ui.world-intro.resident-shell-state-v4"

const COLOR_INK := Color("3f2818")
const COLOR_MUTED := Color("76583d")
const COLOR_MUTED_DARK := Color("65472f")
const COLOR_PAPER := Color("fff0cc")
const COLOR_TERRACOTTA := Color("a84329")
const COLOR_BUTTON_INK := Color("fff4d0")
const COLOR_WOOD_DARK := Color("321d12")
const COLOR_HONEY := Color("e5a84b")
const COLOR_MOSS := Color("557b2a")
const COLOR_ERROR := Color("a7352b")


var _body_theme: Theme
var _button_theme: Theme
var _body_font: Font
var _button_font: Font
var _chrome_font_file: FontFile
var _chrome_font: FontVariation
var _tab_font: FontVariation
var _action_font: FontVariation
var _primary_button_styles: Dictionary = {}

var _view_model: Dictionary = {}
var _data: Dictionary = {}
var _last_confirmed_data: Dictionary = {}
var _actions: Dictionary = {}
var _operation: Dictionary = {}
var _error_value: Variant = null
var _revision := -1
var _formal_ready := false
var _reduce_motion := false
var _current_page_index := 0
var _page_count := 0
var _last_page_id := ""
var _emitted_switch_keys: Dictionary = {}
var _layout_mode := LayoutMode.DESKTOP
var _previous_content_scale_size := Vector2i.ZERO
var _previous_window_size := Vector2i.ZERO

var _content_root: Control
var _shell: TextureRect
var _previous_fill: ColorRect
var _skip_fill: ColorRect
var _mobile_paper: Panel
var _validation_overlay: ValidationOverlay

var _back_button: Button
var _flow_title: Label
var _flow_subtitle: Label
var _connection_status: Label
var _tabs: Array[Label] = []

var _copy_scroller: ScrollContainer
var _copy_stack: VBoxContainer
var _kicker_label: Label
var _content_title: Label
var _body_label: Label
var _status_label: Label

var _page_label: Label
var _footer_hint: Label
var _previous_button: Button
var _skip_button: Button
var _continue_button: Button


func _enter_tree() -> void:
	var requested := _requested_viewport_size()
	if requested == Vector2i.ZERO:
		return
	var window := get_window()
	_previous_content_scale_size = window.content_scale_size
	_previous_window_size = DisplayServer.window_get_size()
	DisplayServer.window_set_size(requested)
	window.size = requested
	window.content_scale_size = requested


func _exit_tree() -> void:
	if _previous_window_size != Vector2i.ZERO:
		DisplayServer.window_set_size(_previous_window_size)
		get_window().size = _previous_window_size
	if _previous_content_scale_size != Vector2i.ZERO:
		get_window().content_scale_size = _previous_content_scale_size


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	RenderingServer.set_default_clear_color(Color("152d25"))
	if not _load_resources():
		_build_fatal_error("世界常识页面资源缺失。")
		return
	_build_page()
	_refresh_actions()
	resized.connect(_apply_responsive_layout)
	_apply_responsive_layout()
	_continue_button.grab_focus.call_deferred()


func _requested_viewport_size() -> Vector2i:
	if not OS.is_debug_build():
		return Vector2i.ZERO
	var raw := OS.get_environment("AI_TOWN_UI_VIEWPORT").strip_edges().to_lower()
	var parts := raw.split("x")
	if parts.size() != 2:
		return Vector2i.ZERO
	var width := int(parts[0])
	var height := int(parts[1])
	if width <= 0 or height <= 0:
		return Vector2i.ZERO
	return Vector2i(width, height)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		match key_event.keycode:
			KEY_ESCAPE:
				_request_back()
				get_viewport().set_input_as_handled()
			KEY_LEFT:
				_request_action("previous")
				get_viewport().set_input_as_handled()
			KEY_RIGHT, KEY_ENTER:
				_request_primary_action()
				get_viewport().set_input_as_handled()
			KEY_S:
				_request_action("skip")
				get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton:
		var joy_event := event as InputEventJoypadButton
		if not joy_event.pressed:
			return
		match joy_event.button_index:
			JOY_BUTTON_B:
				_request_back()
				get_viewport().set_input_as_handled()
			JOY_BUTTON_X:
				_request_action("skip")
				get_viewport().set_input_as_handled()


func apply_view_model(snapshot: Dictionary) -> bool:
	var issues := AiTownUiViewModel.validate(snapshot, "世界常识")
	if not issues.is_empty():
		return _reject_snapshot("\n".join(issues))
	if AiTownUiViewModel.scope(snapshot) != &"world_intro":
		return _reject_snapshot("世界常识 ViewModel scope 必须为 world_intro。")
	if not AiTownUiViewModel.accepts_revision(_revision, snapshot):
		return _reject_snapshot(
			"忽略旧世界常识快照：%d < %d。"
			% [AiTownUiViewModel.revision(snapshot), _revision]
		)

	var incoming_data := AiTownUiViewModel.data_for_render(
		snapshot, _last_confirmed_data
	)
	var data_issues := _validate_data(incoming_data)
	if not data_issues.is_empty():
		return _reject_snapshot("\n".join(data_issues))

	var previous_page_id := _current_page_id()
	var operation_status := AiTownUiViewModel.operation_status(snapshot)
	_view_model = snapshot.duplicate(true)
	_revision = AiTownUiViewModel.revision(snapshot)
	_data = incoming_data.duplicate(true)
	_actions = (snapshot.get("actions", {}) as Dictionary).duplicate(true)
	_operation = AiTownUiViewModel.operation(snapshot)
	_error_value = snapshot.get("error")
	_formal_ready = bool(_data.get("formalReady", false))
	_current_page_index = int(_data.get("currentPageIndex", 0))
	_page_count = int(_data.get("pageCount", 0))
	var transition := _data.get("transition", {}) as Dictionary
	_reduce_motion = bool(transition.get("reduceMotion", false))
	if operation_status != &"rejected":
		_last_confirmed_data = _data.duplicate(true)

	if is_node_ready() and _copy_scroller != null:
		_refresh_from_view_model()
		var next_page_id := _current_page_id()
		if not previous_page_id.is_empty() and previous_page_id != next_page_id:
			_play_page_change()
		_last_page_id = next_page_id
		_maybe_confirm_step_switch()
	return true


func runtime_audit() -> Dictionary:
	var action_audit: Dictionary = {}
	var retry_is_primary := AiTownUiViewModel.action_enabled(
		_action_config("retry")
	)
	for key in ["back", "previous", "continue", "skip", "retry"]:
		var button: Button = _button_for_action(key)
		var action := _action_config(key)
		var rendered := true
		if key == "continue":
			rendered = not retry_is_primary
		elif key == "retry":
			rendered = retry_is_primary
		action_audit[key] = {
			"intent": String(action.get("intent", "")),
			"enabled": AiTownUiViewModel.action_enabled(action),
			"rendered": rendered,
			"buttonDisabled": (
				true if button == null or not rendered else button.disabled
			),
		}
	var touch_targets := [
		_back_button,
		_previous_button,
		_skip_button,
		_continue_button,
	]
	var custom_resident_control_absent := (
		get_node_or_null("ContentRoot/CustomResidentButton") == null
	)
	var touch_ok := true
	for control: Control in touch_targets:
		if control == null or not control.visible:
			continue
		touch_ok = (
			touch_ok
			and control.size.x >= TOUCH_TARGET_MIN
			and control.size.y >= TOUCH_TARGET_MIN
		)
	var integer_pixels := true
	for control: Control in [
		_copy_scroller,
		_page_label,
		_previous_button,
		_skip_button,
		_continue_button,
	]:
		if control == null:
			continue
		integer_pixels = (
			integer_pixels
			and is_equal_approx(control.position.x, roundf(control.position.x))
			and is_equal_approx(control.position.y, roundf(control.position.y))
			and is_equal_approx(control.size.x, roundf(control.size.x))
			and is_equal_approx(control.size.y, roundf(control.size.y))
		)
	var status := String(_operation.get("status", ""))
	var copy_rect := _copy_scroller.get_rect()
	var page_rect := _page_label.get_rect()
	var previous_rect := _previous_button.get_rect()
	var skip_rect := _skip_button.get_rect()
	var primary_rect := _continue_button.get_rect()
	var regions_separated := (
		not copy_rect.intersects(page_rect)
		and not copy_rect.intersects(previous_rect)
		and not copy_rect.intersects(skip_rect)
		and not copy_rect.intersects(primary_rect)
		and not page_rect.intersects(previous_rect)
		and not page_rect.intersects(skip_rect)
		and not page_rect.intersects(primary_rect)
		and not previous_rect.intersects(skip_rect)
		and not previous_rect.intersects(primary_rect)
		and not skip_rect.intersects(primary_rect)
	)
	var responsive_style := (
		_mobile_paper.get_theme_stylebox("panel") as StyleBoxFlat
	)
	var responsive_borderless := (
		responsive_style != null
		and not _stylebox_has_visible_border(responsive_style)
	)
	var non_primary_action_controls_borderless := true
	for action_button: Button in [
		_back_button,
		_previous_button,
		_skip_button,
	]:
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			non_primary_action_controls_borderless = (
				non_primary_action_controls_borderless
				and not _stylebox_has_visible_border(
					action_button.get_theme_stylebox(state)
				)
			)
	var ownership_passed: bool = (
		_shell is TextureRect
		and responsive_borderless
		and non_primary_action_controls_borderless
	)
	var page_font_size := _page_label.get_theme_font_size("font_size")
	var hint_font_size := _footer_hint.get_theme_font_size("font_size")
	var previous_font_size := _previous_button.get_theme_font_size("font_size")
	var skip_font_size := _skip_button.get_theme_font_size("font_size")
	var page_vertical_padding := (
		_page_label.size.y - _chrome_font.get_height(page_font_size)
	) * 0.5
	var page_horizontal_padding := (
		_page_label.size.x - _page_label.text.length() * page_font_size
	) * 0.5
	var hint_vertical_padding := (
		_footer_hint.size.y - _chrome_font.get_height(hint_font_size)
	) * 0.5
	var previous_vertical_padding := (
		_previous_button.size.y - _action_font.get_height(previous_font_size)
	) * 0.5
	var skip_vertical_padding := (
		_skip_button.size.y - _action_font.get_height(skip_font_size)
	) * 0.5
	var footer_typography_passed := (
		page_vertical_padding >= 4.0
		and page_horizontal_padding >= 8.0
		and (
			not _footer_hint.visible
			or hint_vertical_padding >= 8.0
		)
		and previous_vertical_padding >= 8.0
		and skip_vertical_padding >= 8.0
		and _button_text_fits_horizontally(
			_previous_button, previous_font_size, 8.0
		)
		and _button_text_fits_horizontally(
			_skip_button, skip_font_size, 8.0
		)
	)
	var tab_font_size := (
		FONT_CAPTION
		if _tabs.is_empty()
		else _tabs[0].get_theme_font_size("font_size")
	)
	var tab_vertical_padding := 0.0
	var header_action_vertical_padding := 0.0
	var header_typography_passed := true
	if not _tabs.is_empty() and _tabs[0].visible:
		tab_vertical_padding = (
			_tabs[0].size.y - _tab_font.get_height(tab_font_size)
		) * 0.5
		var header_action_font_size := (
			_connection_status.get_theme_font_size("font_size")
		)
		header_action_vertical_padding = (
			_connection_status.size.y
			- _action_font.get_height(header_action_font_size)
		) * 0.5
		header_typography_passed = (
			tab_vertical_padding >= 8.0
			and header_action_vertical_padding >= 8.0
			and tab_font_size % FONT_NATIVE_GRID == 0
			and _tab_font.spacing_glyph == 2
			and is_zero_approx(_tab_font.variation_embolden)
			and _tabs[0].text.length() * tab_font_size
				<= _tabs[0].size.x - 16.0
			and _connection_status.text.length()
				* header_action_font_size
				<= _connection_status.size.x - 16.0
		)
	var primary_outline := _continue_button.get_theme_constant("outline_size")
	var primary_font_size := _continue_button.get_theme_font_size("font_size")
	var primary_text_height := (
		_action_font.get_height(primary_font_size)
		+ primary_outline * 2.0
	)
	var primary_text_to_state_asset_padding := (
		_continue_button.size.y - primary_text_height
	) * 0.5
	var primary_states_are_textured := true
	for state in ["normal", "hover", "focus", "pressed", "disabled"]:
		var state_style := _continue_button.get_theme_stylebox(state)
		primary_states_are_textured = (
			primary_states_are_textured
			and state_style is StyleBoxTexture
			and (state_style as StyleBoxTexture).texture != null
		)
	var chrome_typography_passed := (
		header_typography_passed
		and _action_font == _chrome_font
		and _chrome_font.base_font != null
		and _chrome_font.base_font.resource_path == CHROME_FONT_PATH
		and _chrome_font.spacing_glyph == 2
		and is_zero_approx(_chrome_font.variation_embolden)
		and primary_text_to_state_asset_padding >= 5.0
		and primary_states_are_textured
	)
	return {
		"passed": (
			not _view_model.is_empty()
			and _page_count == (_data.get("pages", []) as Array).size()
			and touch_ok
			and integer_pixels
			and regions_separated
			and ownership_passed
			and custom_resident_control_absent
			and footer_typography_passed
			and chrome_typography_passed
		),
		"scope": String(_view_model.get("scope", "")),
		"revision": _revision,
		"capabilityMode": String(_data.get("capabilityMode", "")),
		"source": String(_data.get("source", "")),
		"formalReady": _formal_ready,
		"operationStatus": status,
		"pageIndex": _current_page_index,
		"pageCount": _page_count,
		"pageId": _current_page_id(),
		"layoutMode": _layout_mode_name(),
		"touchTargetsPassed": touch_ok,
		"integerPixels": integer_pixels,
		"copyScrollDeclared": true,
		"wholePageTextScaling": false,
		"regionsSeparated": regions_separated,
		"customResidentControlAbsent": custom_resident_control_absent,
		"footerTypography": {
			"passed": footer_typography_passed,
			"pageFontSize": page_font_size,
			"pageVerticalPadding": page_vertical_padding,
			"pageHorizontalPadding": page_horizontal_padding,
			"hintFontSize": hint_font_size,
			"hintVerticalPadding": hint_vertical_padding,
			"previousFontSize": previous_font_size,
			"previousVerticalPadding": previous_vertical_padding,
			"skipFontSize": skip_font_size,
			"skipVerticalPadding": skip_vertical_padding,
			"baselineLift": 0,
			"minimumTextToBorderGap": 4,
		},
		"chromeTypography": {
			"passed": chrome_typography_passed,
			"contentTypefacePreserved": "ZhengGeDianHei-16",
			"chromeFontRevision": "startup-main-menu-noto-heiti-approved",
			"chromeFontPath": CHROME_FONT_PATH,
			"usesStartupMainMenuChromeFont": _action_font == _chrome_font,
			"actionEmbolden": 0.0,
			"tabTypographyProfile": "startup-main-menu-noto-heiti-approved",
			"tabNativeGrid": FONT_NATIVE_GRID,
			"tabSpacingGlyph": _tab_font.spacing_glyph,
			"tabEmbolden": _tab_font.variation_embolden,
			"tabOutlineSize": _tabs[0].get_theme_constant("outline_size"),
			"tabFontSize": tab_font_size,
			"tabVerticalPadding": tab_vertical_padding,
			"headerActionVerticalPadding": header_action_vertical_padding,
			"primaryFontSize": primary_font_size,
			"primaryEmbolden": 0.0,
			"primaryBaselineDrop": 0,
			"primaryTextToStateAssetPadding": (
				primary_text_to_state_asset_padding
			),
			"primaryStatesAreTextured": primary_states_are_textured,
			"primaryStateAssetRoot": PRIMARY_BUTTON_STATE_ROOT,
		},
		"ownership": {
			"passed": ownership_passed,
			"compositeShellAssetId": COMPOSITE_SHELL_ASSET_ID,
			"compositeShellComponentType": "page_composite_shell",
			"compositeShellNodeType": "TextureRect",
			"registeredAsGenericStyleBoxTexture": false,
			"responsivePaperOwnsFillOnly": responsive_borderless,
			"responsiveActionBackingsOwnFillOnly": true,
			"nonPrimaryControlsOwnStaticBorder": (
				not non_primary_action_controls_borderless
			),
			"primaryColorRectOverlayPresent": false,
			"primaryStateAssetOwner": "ContinueButton",
			"duplicateSemanticBorderCount": 0,
			"validationGuidesDebugOnly": true,
		},
		"actions": action_audit,
	}


func _load_resources() -> bool:
	_body_theme = load(BODY_THEME_PATH) as Theme
	_button_theme = load(BUTTON_THEME_PATH) as Theme
	_body_font = null if _body_theme == null else _body_theme.default_font
	_button_font = null if _button_theme == null else _button_theme.default_font
	_chrome_font_file = load(CHROME_FONT_PATH) as FontFile
	_chrome_font = _chrome_font_variation(2)
	_tab_font = _chrome_font_variation(2)
	_action_font = _chrome_font
	_primary_button_styles.clear()
	for state: String in PRIMARY_BUTTON_STATE_PATHS:
		var path := String(PRIMARY_BUTTON_STATE_PATHS[state])
		var texture := load(path) as Texture2D
		if texture == null:
			return false
		_primary_button_styles[state] = _primary_button_state_style(
			texture,
			state == "pressed"
		)
	return (
		_body_theme != null
		and _button_theme != null
		and _body_font != null
		and _button_font != null
		and _chrome_font_file != null
		and _chrome_font != null
		and _tab_font != null
		and _action_font != null
		and ResourceLoader.exists(SHELL_PATH)
		and _primary_button_styles.size()
			== PRIMARY_BUTTON_STATE_PATHS.size()
	)


func _chrome_font_variation(glyph_spacing: int) -> FontVariation:
	if _chrome_font_file == null:
		return null
	var variation := FontVariation.new()
	variation.base_font = _chrome_font_file
	variation.spacing_glyph = glyph_spacing
	variation.spacing_space = 0
	variation.variation_embolden = 0.0
	return variation


func _validate_data(data: Dictionary) -> PackedStringArray:
	var issues := PackedStringArray()
	for field in [
		"capabilityMode",
		"source",
		"formalReady",
		"introId",
		"flowMode",
		"currentPageIndex",
		"pageCount",
		"pages",
		"transition",
	]:
		if not data.has(field):
			issues.append("世界常识 data 缺少字段：%s" % field)
	var pages_value: Variant = data.get("pages", [])
	if typeof(pages_value) != TYPE_ARRAY:
		issues.append("世界常识 data.pages 必须是 Array。")
		return issues
	var pages := pages_value as Array
	var page_count := int(data.get("pageCount", -1))
	if page_count <= 0 or page_count != pages.size():
		issues.append("世界常识 pageCount 必须与 pages 数量一致且大于 0。")
	var index := int(data.get("currentPageIndex", -1))
	if index < 0 or index >= pages.size():
		issues.append("世界常识 currentPageIndex 超出范围。")
	for page_value: Variant in pages:
		if typeof(page_value) != TYPE_DICTIONARY:
			issues.append("世界常识 pages 条目必须是 Dictionary。")
			continue
		var page := page_value as Dictionary
		for field in ["pageId", "kicker", "title", "body", "visualBeat"]:
			if not page.has(field):
				issues.append("世界常识 page 缺少字段：%s" % field)
	return issues


func _reject_snapshot(reason: String) -> bool:
	push_warning(reason)
	view_model_rejected.emit(reason)
	return false


func _build_page() -> void:
	_content_root = Control.new()
	_content_root.name = "ContentRoot"
	add_child(_content_root)

	_shell = TextureRect.new()
	_shell.name = "ResidentSelectionSharedShell"
	_shell.texture = load(SHELL_PATH) as Texture2D
	_shell.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shell.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_shell.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content_root.add_child(_shell)

	_mobile_paper = Panel.new()
	_mobile_paper.name = "ResponsivePaper"
	_mobile_paper.add_theme_stylebox_override(
		"panel", _panel_style(COLOR_PAPER, Color.TRANSPARENT, 0)
	)
	_mobile_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mobile_paper.visible = false
	_content_root.add_child(_mobile_paper)

	_skip_fill = ColorRect.new()
	_skip_fill.name = "WideSkipBackingFill"
	_skip_fill.color = Color("f6dcaa")
	_skip_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skip_fill.visible = false
	_content_root.add_child(_skip_fill)

	_previous_fill = ColorRect.new()
	_previous_fill.name = "ResponsivePreviousBackingFill"
	_previous_fill.color = Color("f6dcaa")
	_previous_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_previous_fill.visible = false
	_content_root.add_child(_previous_fill)

	_back_button = _button("BackButton", "返回", FONT_BODY, _request_back)
	_content_root.add_child(_back_button)
	_flow_title = _label(
		"FlowTitle", "认识这座小镇", FONT_FLOW_TITLE, COLOR_INK
	)
	_flow_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_root.add_child(_flow_title)
	_flow_subtitle = _label(
		"FlowSubtitle",
		"先了解这里怎样生活，再决定谁住进来",
		FONT_CAPTION,
		COLOR_MUTED
	)
	_flow_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_root.add_child(_flow_subtitle)

	_connection_status = _label(
		"ConnectionStatus", "未连接", FONT_CAPTION, COLOR_BUTTON_INK
	)
	_connection_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_root.add_child(_connection_status)

	for tab_text in ["小镇介绍", "居民名单", "开始生活"]:
		var tab := _label(
			"Tab%s" % _tabs.size(),
			tab_text,
			FONT_CAPTION,
			COLOR_BUTTON_INK if _tabs.is_empty() else COLOR_INK
		)
		tab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_tabs.append(tab)
		_content_root.add_child(tab)

	_copy_scroller = ScrollContainer.new()
	_copy_scroller.name = "CopyScroller"
	_copy_scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_copy_scroller.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_copy_scroller.mouse_filter = Control.MOUSE_FILTER_PASS
	_content_root.add_child(_copy_scroller)
	_copy_stack = VBoxContainer.new()
	_copy_stack.name = "CopyStack"
	_copy_stack.add_theme_constant_override("separation", 12)
	_copy_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_copy_scroller.add_child(_copy_stack)

	_kicker_label = _label("Kicker", "", FONT_BODY, COLOR_MUTED)
	_kicker_label.custom_minimum_size.y = 48
	_copy_stack.add_child(_kicker_label)
	_content_title = _label("ContentTitle", "", FONT_CONTENT_TITLE, COLOR_INK)
	_content_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content_title.max_lines_visible = 2
	_content_title.custom_minimum_size.y = 94
	_copy_stack.add_child(_content_title)
	_body_label = _label("Body", "", FONT_BODY, COLOR_INK)
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.max_lines_visible = -1
	_body_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_body_label.custom_minimum_size.y = 200
	_copy_stack.add_child(_body_label)
	_status_label = _label("Status", "", FONT_CAPTION, COLOR_MUTED)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size.y = 56
	_status_label.visible = false
	_copy_stack.add_child(_status_label)

	_page_label = _label("PageStatus", "", FONT_CAPTION, COLOR_MUTED)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_root.add_child(_page_label)
	_footer_hint = _label(
		"FooterHint", "先认识小镇，再选择居民", FONT_CAPTION, COLOR_MUTED
	)
	_footer_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_root.add_child(_footer_hint)
	_previous_button = _button(
		"PreviousButton", "上一页", FONT_CAPTION, _request_previous
	)
	_content_root.add_child(_previous_button)
	_skip_button = _button("SkipButton", "跳过", FONT_CAPTION, _request_skip)
	_content_root.add_child(_skip_button)
	_continue_button = _button(
		"ContinueButton", "继续", FONT_BODY, _request_primary_action
	)
	_content_root.add_child(_continue_button)

	_previous_button.focus_neighbor_left = _previous_button.get_path()
	_previous_button.focus_neighbor_right = _skip_button.get_path()
	_skip_button.focus_neighbor_left = _previous_button.get_path()
	_skip_button.focus_neighbor_right = _continue_button.get_path()
	_continue_button.focus_neighbor_left = _skip_button.get_path()
	_continue_button.focus_neighbor_right = _continue_button.get_path()

	if (
		OS.is_debug_build()
		and OS.get_environment("AI_TOWN_SHOW_SAFE_AREAS") == "1"
	):
		_validation_overlay = ValidationOverlay.new()
		_validation_overlay.name = "ValidationOverlay"
		_validation_overlay.guide_font = _body_font
		_validation_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_validation_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_content_root.add_child(_validation_overlay)


func _refresh_from_view_model() -> void:
	var page := _current_page()
	_kicker_label.text = String(page.get("kicker", ""))
	_content_title.text = String(page.get("title", ""))
	_body_label.text = String(page.get("body", ""))
	_content_title.custom_minimum_size.y = (
		188.0 if _content_title.text.length() > 16 else 94.0
	)
	_page_label.text = "第 %d 页 / 共 %d 页" % [
		_current_page_index + 1,
		_page_count,
	]
	var capability_mode := String(_data.get("capabilityMode", "placeholder"))
	_connection_status.text = (
		"未连接" if capability_mode == "placeholder" else "已连接"
	)
	_refresh_operation_state()
	_refresh_actions()
	_apply_responsive_layout()


func _refresh_operation_state() -> void:
	var operation_status := String(_operation.get("status", "idle"))
	var message := ""
	var color := COLOR_MUTED
	match operation_status:
		"loading":
			message = "正在准备居民名单……"
		"success":
			message = "即将显示居民名单"
			color = COLOR_MOSS
		"rejected":
			message = _error_message_or("当前流程状态已变化，请重新尝试。")
			color = COLOR_ERROR
		"error":
			message = _error_message_or("下一步暂时没有响应，请重试。")
			color = COLOR_ERROR
		"disabled":
			message = _error_message_or("世界常识流程接口尚未接入。")
			color = COLOR_ERROR
	_status_label.text = message
	_status_label.visible = not message.is_empty()
	_status_label.add_theme_color_override("font_color", color)


func _refresh_actions() -> void:
	var back := _action_config("back")
	var previous := _action_config("previous")
	var skip := _action_config("skip")
	var continue_action := _action_config("continue")
	var retry := _action_config("retry")
	_set_action_button(_back_button, back)
	_set_action_button(_previous_button, previous)
	_set_action_button(_skip_button, skip)
	var retry_enabled := AiTownUiViewModel.action_enabled(retry)
	var primary_action := retry if retry_enabled else continue_action
	_set_action_button(_continue_button, primary_action)
	_back_button.visible = not back.is_empty()
	_previous_button.visible = not previous.is_empty()
	_skip_button.visible = not skip.is_empty()
	_continue_button.visible = not primary_action.is_empty()
	var has_page := _page_count > 0 and not _current_page().is_empty()
	_page_label.visible = has_page
	_footer_hint.visible = has_page

	_previous_button.text = _action_label(previous, "上一页")
	_skip_button.text = _action_label(skip, "跳过")
	if retry_enabled:
		_continue_button.text = _action_label(retry, "重试")
	else:
		var fallback := "进入居民名单" if _current_page_index + 1 >= _page_count else "继续"
		_continue_button.text = _action_label(continue_action, fallback)
	_style_primary_button(
		_continue_button,
		_continue_button.disabled,
		String(_operation.get("status", "")) == "loading"
	)


func _set_action_button(button: Button, action: Dictionary) -> void:
	button.disabled = not AiTownUiViewModel.action_enabled(action)
	button.tooltip_text = (
		AiTownUiViewModel.disabled_reason(action) if button.disabled else ""
	)


func _request_previous() -> void:
	_request_action("previous")


func _request_back() -> void:
	_request_action("back")


func show_navigation_failure(message: String) -> void:
	if _status_label == null:
		return
	_status_label.text = message
	_status_label.visible = true
	_status_label.add_theme_color_override("font_color", COLOR_ERROR)


func _request_skip() -> void:
	_request_action("skip")


func _request_primary_action() -> void:
	var retry := _action_config("retry")
	if AiTownUiViewModel.action_enabled(retry):
		_request_action("retry")
	else:
		_request_action("continue")


func _request_action(action_key: String) -> void:
	var action := _action_config(action_key)
	if not AiTownUiViewModel.action_enabled(action):
		return
	var intent := StringName(action.get("intent", ""))
	if intent.is_empty():
		return
	var page := _current_page()
	var payload := {
		"scope": "world_intro",
		"introId": String(_data.get("introId", "")),
		"pageId": String(page.get("pageId", "")),
		"currentPageIndex": _current_page_index,
		"pageCount": _page_count,
		"formalReady": _formal_ready,
	}
	intent_requested.emit(intent, payload, _revision)


func _maybe_confirm_step_switch() -> void:
	if String(_operation.get("status", "")) != "success":
		return
	var transition := _data.get("transition", {}) as Dictionary
	if not bool(transition.get("routeCommitted", false)):
		return
	if String(transition.get("targetRoute", "")) != "resident_selection":
		return
	var request_id := String(_operation.get("requestId", ""))
	var key := "%d:%s" % [_revision, request_id]
	if _emitted_switch_keys.has(key):
		return
	_emitted_switch_keys[key] = true
	if _reduce_motion:
		step_switch_confirmed.emit(&"resident_roster", _revision)
		return
	var tween := create_tween()
	tween.tween_property(_copy_scroller, "modulate:a", 0.0, 0.18)
	tween.tween_callback(
		func() -> void:
			step_switch_confirmed.emit(&"resident_roster", _revision)
	)


func _play_page_change() -> void:
	_copy_scroller.scroll_vertical = 0
	if _reduce_motion:
		_copy_scroller.modulate.a = 1.0
		return
	_copy_scroller.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_copy_scroller, "modulate:a", 1.0, 0.16)


func _current_page() -> Dictionary:
	var pages := _data.get("pages", []) as Array
	if _current_page_index < 0 or _current_page_index >= pages.size():
		return {}
	var value: Variant = pages[_current_page_index]
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value as Dictionary


func _current_page_id() -> String:
	return String(_current_page().get("pageId", ""))


func _action_config(action_key: String) -> Dictionary:
	return AiTownUiViewModel.action(_view_model, action_key)


func _button_for_action(action_key: String) -> Button:
	match action_key:
		"back":
			return _back_button
		"previous":
			return _previous_button
		"skip":
			return _skip_button
		"continue", "retry":
			return _continue_button
	return null


func _action_label(action: Dictionary, fallback: String) -> String:
	var label := String(action.get("label", ""))
	return fallback if label.is_empty() else label


func _error_message_or(fallback: String) -> String:
	var message := AiTownUiViewModel.error_message(_view_model)
	return fallback if message.is_empty() else message


func _apply_responsive_layout() -> void:
	if _content_root == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var available := _available_rect()
	_layout_mode = _layout_mode_for(available.size)
	var canvas_size := _canvas_size_for(_layout_mode, available.size)
	_content_root.position = (
		available.position + (available.size - canvas_size) * 0.5
	).round()
	_content_root.size = canvas_size.round()
	_shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_apply_header_layout()
	_apply_content_layout()
	_apply_footer_layout()
	_update_validation_overlay()


func _update_validation_overlay() -> void:
	if _validation_overlay == null:
		return
	_validation_overlay.guides = [
		{
			"rect": Rect2(Vector2.ZERO, _content_root.size),
			"color": Color("53ff84"),
			"label": "CONTENT SAFE",
		},
		{
			"rect": _copy_scroller.get_rect(),
			"color": Color("ffd44d"),
			"label": "COPY SCROLL",
		},
		{
			"rect": _page_label.get_rect(),
			"color": Color("9f7cff"),
			"label": "PAGE STATUS",
		},
		{
			"rect": _previous_button.get_rect(),
			"color": Color("42d7ff"),
			"label": "PREVIOUS HIT",
		},
		{
			"rect": _skip_button.get_rect(),
			"color": Color("ff72d1"),
			"label": "SKIP HIT",
		},
		{
			"rect": _continue_button.get_rect(),
			"color": Color("ff375f"),
			"label": "PRIMARY HIT",
		},
		{
			"rect": _continue_button.get_rect().grow(-8),
			"color": Color("fff35a"),
			"label": "PRIMARY TEXT SAFE",
		},
	]
	_validation_overlay.queue_redraw()


func _apply_header_layout() -> void:
	var mobile := _layout_mode in [
		LayoutMode.PHONE_LANDSCAPE,
		LayoutMode.PHONE_PORTRAIT,
	]
	if _layout_mode == LayoutMode.DESKTOP:
		_set_rect(_back_button, Rect2(216, 157, 160, 72))
		_set_rect(_flow_title, Rect2(472, 154, 871, 70))
		_set_rect(_flow_subtitle, Rect2(472, 220, 871, 28))
		_set_chrome_label_rect(
			_connection_status,
			Rect2(1565, 159, 151, 78)
		)
		var desktop_tab_rects := [
			Rect2(666, 273, 148, 45),
			Rect2(814, 273, 153, 45),
			Rect2(967, 273, 154, 45),
		]
		for index in range(_tabs.size()):
			_set_chrome_label_rect(_tabs[index], desktop_tab_rects[index])
		_flow_title.add_theme_font_size_override("font_size", FONT_FLOW_TITLE)
		_flow_subtitle.visible = true
		_connection_status.visible = true
		for tab: Label in _tabs:
			tab.visible = true
	elif not mobile:
		var width := _content_root.size.x
		var standard := _layout_mode == LayoutMode.STANDARD
		var header_y := 102.0 if standard else 110.0
		var tabs_y := 181.0 if standard else 190.0
		_set_rect(
			_back_button,
			Rect2(144, header_y, 108, 56)
			if standard
			else Rect2(8, header_y, 96, 56)
		)
		_set_rect(
			_flow_title,
			Rect2(304, header_y, width - 688, 56)
			if standard
			else Rect2(168, header_y, width - 408, 56)
		)
		_set_rect(_flow_subtitle, Rect2())
		_set_chrome_label_rect(
			_connection_status,
			Rect2(width - 200, header_y, 136, 56)
			if standard
			else Rect2(width - 88, header_y + 4, 80, 56)
		)
		if standard:
			_connection_status.position.y += 4
		for index in range(_tabs.size()):
			_set_chrome_label_rect(
				_tabs[index],
				Rect2(
					width * 0.5 - 210 + index * 140,
					tabs_y,
					140,
					48
				)
			)
		_flow_title.add_theme_font_size_override("font_size", FONT_BODY)
		_flow_subtitle.visible = false
		_connection_status.visible = true
		for tab: Label in _tabs:
			tab.visible = true
	else:
		var width := _content_root.size.x
		_set_rect(_back_button, Rect2(8, 8, 64, 64))
		_set_rect(_flow_title, Rect2(80, 8, width - 160, 64))
		_set_rect(_flow_subtitle, Rect2())
		_set_chrome_label_rect(
			_connection_status,
			Rect2(width - 72, 8, 64, 64)
		)
		for tab: Label in _tabs:
			_set_chrome_label_rect(tab, Rect2())
			tab.visible = false
		_flow_title.text = "小镇介绍"
		_flow_title.add_theme_font_size_override("font_size", FONT_BODY)
		_flow_title.visible = false
		_flow_subtitle.visible = false
		_connection_status.visible = false
		_back_button.visible = false
		_back_button.text = ""
	if not mobile:
		_flow_title.text = "认识这座小镇"
		_flow_title.visible = true
		_back_button.visible = not _action_config("back").is_empty()
		_back_button.text = "返回"
	_apply_header_typography()


func _apply_header_typography() -> void:
	var compact := _layout_mode != LayoutMode.DESKTOP
	var tab_size := FONT_CAPTION
	var header_action_size := 18 if compact else 20
	_flow_title.add_theme_font_override("font", _chrome_font)
	_flow_subtitle.add_theme_font_override("font", _chrome_font)
	for index in range(_tabs.size()):
		var tab := _tabs[index]
		tab.add_theme_font_override("font", _tab_font)
		tab.add_theme_font_size_override("font_size", tab_size)
		tab.add_theme_constant_override("outline_size", 0)
		tab.add_theme_color_override("font_outline_color", COLOR_WOOD_DARK)
	_back_button.add_theme_color_override("font_color", COLOR_BUTTON_INK)
	_back_button.add_theme_color_override(
		"font_disabled_color", Color("d9b982")
	)
	_back_button.add_theme_color_override("font_hover_color", COLOR_HONEY)
	_back_button.add_theme_color_override("font_focus_color", COLOR_HONEY)
	_back_button.add_theme_color_override(
		"font_outline_color", COLOR_WOOD_DARK
	)
	_back_button.add_theme_constant_override("outline_size", 0)
	_style_header_action_button(_back_button)
	_connection_status.add_theme_font_override("font", _action_font)
	_connection_status.add_theme_font_size_override(
		"font_size", header_action_size
	)
	_connection_status.add_theme_constant_override("outline_size", 0)
	_connection_status.add_theme_color_override(
		"font_outline_color", COLOR_WOOD_DARK
	)


func _style_header_action_button(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(
			state, _transparent_button_style()
		)


func _apply_content_layout() -> void:
	_mobile_paper.visible = _layout_mode != LayoutMode.DESKTOP
	_kicker_label.visible = _layout_mode not in [
		LayoutMode.PHONE_LANDSCAPE,
		LayoutMode.PHONE_PORTRAIT,
	]
	_content_title.max_lines_visible = (
		-1
		if _layout_mode in [
			LayoutMode.PHONE_LANDSCAPE,
			LayoutMode.PHONE_PORTRAIT,
		]
		else 2
	)
	match _layout_mode:
		LayoutMode.DESKTOP:
			_set_rect(_mobile_paper, Rect2())
			_set_rect(_copy_scroller, Rect2(270, 382, 760, 468))
			_copy_stack.custom_minimum_size.x = 760
			_kicker_label.add_theme_font_size_override("font_size", FONT_BODY)
			_content_title.add_theme_font_size_override(
				"font_size", FONT_CONTENT_TITLE
			)
			_content_title.custom_minimum_size.y = (
				188.0 if _content_title.text.length() > 16 else 94.0
			)
			_body_label.add_theme_font_size_override("font_size", FONT_BODY)
		LayoutMode.STANDARD:
			_set_rect(_mobile_paper, Rect2(48, 230, 700, 350))
			_set_rect(_copy_scroller, Rect2(76, 246, 640, 326))
			_copy_stack.custom_minimum_size.x = 640
			_kicker_label.add_theme_font_size_override("font_size", FONT_BODY)
			_content_title.add_theme_font_size_override("font_size", FONT_FLOW_TITLE)
			_content_title.custom_minimum_size.y = (
				148.0 if _content_title.text.length() > 16 else 76.0
			)
			_body_label.add_theme_font_size_override("font_size", FONT_BODY)
		LayoutMode.TABLET:
			var width := _content_root.size.x
			var height := _content_root.size.y
			_set_rect(_mobile_paper, Rect2(24, 232, width * 0.62, height - 384))
			_set_rect(
				_copy_scroller,
				Rect2(52, 248, width * 0.62 - 56, height - 416)
			)
			_copy_stack.custom_minimum_size.x = _copy_scroller.size.x
			_kicker_label.add_theme_font_size_override("font_size", FONT_BODY)
			_content_title.add_theme_font_size_override("font_size", FONT_FLOW_TITLE)
			_content_title.custom_minimum_size.y = (
				148.0 if _content_title.text.length() > 16 else 76.0
			)
			_body_label.add_theme_font_size_override("font_size", FONT_BODY)
		LayoutMode.PHONE_LANDSCAPE:
			var width := _content_root.size.x
			var height := _content_root.size.y
			_set_rect(_mobile_paper, Rect2(16, 8, width - 32, height - 104))
			_set_rect(_copy_scroller, Rect2(36, 16, width - 72, height - 118))
			_copy_stack.custom_minimum_size.x = _copy_scroller.size.x
			_kicker_label.add_theme_font_size_override("font_size", FONT_BODY)
			_content_title.add_theme_font_size_override(
				"font_size", FONT_COMPACT_TITLE
			)
			_content_title.custom_minimum_size.y = (
				128.0 if _content_title.text.length() > 16 else 64.0
			)
			_body_label.add_theme_font_size_override("font_size", FONT_BODY)
		LayoutMode.PHONE_PORTRAIT:
			var width := _content_root.size.x
			var height := _content_root.size.y
			_set_rect(_mobile_paper, Rect2(4, 12, width - 8, height - 258))
			_set_rect(_copy_scroller, Rect2(20, 28, width - 40, height - 286))
			_copy_stack.custom_minimum_size.x = _copy_scroller.size.x
			_kicker_label.add_theme_font_size_override("font_size", FONT_BODY)
			_content_title.add_theme_font_size_override(
				"font_size", FONT_COMPACT_TITLE
			)
			_content_title.custom_minimum_size.y = (
				300.0 if _content_title.text.length() > 16 else 128.0
			)
			_body_label.add_theme_font_size_override("font_size", FONT_BODY)


func _apply_footer_layout() -> void:
	_apply_footer_typography()
	var has_page := _page_count > 0 and not _current_page().is_empty()
	_page_label.visible = has_page
	_page_label.text = (
		(
			"%d / %d" % [_current_page_index + 1, _page_count]
			if _layout_mode in [
				LayoutMode.PHONE_LANDSCAPE,
				LayoutMode.PHONE_PORTRAIT,
			]
			else "第 %d / %d 页" % [
				_current_page_index + 1,
				_page_count,
			]
		)
		if has_page
		else ""
	)
	if _layout_mode == LayoutMode.DESKTOP:
		_previous_fill.visible = false
		_set_rect(_previous_fill, Rect2())
		_set_chrome_label_rect(
			_page_label,
			Rect2(808, 887, 228, 46),
			FOOTER_META_OPTICAL_LIFT
		)
		_set_chrome_label_rect(
			_footer_hint,
			Rect2(313, 956, 411, 72),
			FOOTER_HINT_OPTICAL_LIFT,
			FOOTER_HINT_OPTICAL_SHIFT_X
		)
		_set_rect(_previous_button, Rect2(815, 956, 171, 72))
		if _skip_requires_wide_slot():
			_set_rect(_previous_button, Rect2(850, 956, 100, 72))
			_set_rect(_skip_button, Rect2(958, 956, 236, 72))
			_set_rect(_skip_fill, _skip_button.get_rect().grow(-6))
			_skip_fill.visible = true
		else:
			_set_rect(_skip_button, Rect2(1003, 956, 94, 72))
			_set_rect(_skip_fill, Rect2())
			_skip_fill.visible = false
		_set_rect(_continue_button, Rect2(1205, 956, 407, 72))
		_fit_action_button_labels()
		return
	var width := _content_root.size.x
	var height := _content_root.size.y
	if _layout_mode == LayoutMode.STANDARD:
		_set_chrome_label_rect(
			_page_label,
			Rect2(width * 0.5 - 110, height - 132, 220, 40),
			FOOTER_META_OPTICAL_LIFT
		)
		_set_chrome_label_rect(
			_footer_hint,
			Rect2(24, height - 80, 388, 56),
			FOOTER_HINT_OPTICAL_LIFT,
			FOOTER_HINT_OPTICAL_SHIFT_X
		)
		if _skip_requires_wide_slot():
			_set_rect(_previous_button, Rect2(width * 0.40, height - 80, 112, 56))
			_set_rect(
				_previous_fill,
				_previous_button.get_rect().grow(-4)
			)
			_previous_fill.visible = true
			_set_rect(_skip_button, Rect2(width * 0.40 + 120, height - 80, 216, 56))
			_set_rect(_skip_fill, _skip_button.get_rect().grow(-4))
			_skip_fill.visible = true
		else:
			_set_rect(_previous_button, Rect2(width * 0.40, height - 80, 136, 56))
			_previous_fill.visible = false
			_set_rect(_previous_fill, Rect2())
			_set_rect(_skip_button, Rect2(width * 0.40 + 148, height - 80, 104, 56))
			_skip_fill.visible = false
			_set_rect(_skip_fill, Rect2())
		_set_rect(_continue_button, Rect2(width - 424, height - 104, 400, 88))
	elif _layout_mode == LayoutMode.TABLET:
		_set_chrome_label_rect(
			_page_label,
			Rect2(width * 0.5 - 110, height - 144, 220, 40),
			FOOTER_META_OPTICAL_LIFT
		)
		_set_chrome_label_rect(
			_footer_hint,
			Rect2(
				24,
				height - 80,
				300 if _skip_requires_wide_slot() else width * 0.31,
				56
			),
			FOOTER_HINT_OPTICAL_LIFT,
			FOOTER_HINT_OPTICAL_SHIFT_X
		)
		if _skip_requires_wide_slot():
			_set_rect(_previous_button, Rect2(332, height - 80, 100, 56))
			_set_rect(_previous_fill, _previous_button.get_rect().grow(-4))
			_previous_fill.visible = true
			_set_rect(_skip_button, Rect2(440, height - 80, 200, 56))
			_set_rect(_skip_fill, _skip_button.get_rect().grow(-4))
			_skip_fill.visible = true
		else:
			_set_rect(_previous_button, Rect2(width * 0.36, height - 80, 128, 56))
			_set_rect(_previous_fill, Rect2())
			_previous_fill.visible = false
			_set_rect(_skip_button, Rect2(width * 0.36 + 140, height - 80, 104, 56))
			_set_rect(_skip_fill, Rect2())
			_skip_fill.visible = false
		_set_rect(_continue_button, Rect2(width - 376, height - 104, 352, 88))
	elif _layout_mode == LayoutMode.PHONE_LANDSCAPE:
		_previous_fill.visible = false
		_set_rect(_previous_fill, Rect2())
		_skip_fill.visible = false
		_set_rect(_skip_fill, Rect2())
		_set_chrome_label_rect(
			_page_label,
			Rect2(16, height - 64, 116, 48),
			FOOTER_META_OPTICAL_LIFT
		)
		_set_chrome_label_rect(_footer_hint, Rect2())
		_set_rect(_previous_button, Rect2(140, height - 64, 72, 48))
		_set_rect(_skip_button, Rect2(220, height - 64, 180, 48))
		_set_rect(_continue_button, Rect2(width - 384, height - 88, 368, 72))
	else:
		_previous_fill.visible = false
		_set_rect(_previous_fill, Rect2())
		_skip_fill.visible = false
		_set_rect(_skip_fill, Rect2())
		_set_chrome_label_rect(
			_page_label,
			Rect2(20, height - 238, width - 40, 48),
			FOOTER_META_OPTICAL_LIFT
		)
		_set_chrome_label_rect(_footer_hint, Rect2())
		_set_rect(_previous_button, Rect2(20, height - 182, 100, 56))
		_set_rect(
			_skip_button,
			Rect2(132, height - 182, width - 152, 56)
		)
		_set_rect(_continue_button, Rect2(12, height - 118, width - 24, 104))
	_footer_hint.visible = _layout_mode in [
		LayoutMode.DESKTOP,
		LayoutMode.STANDARD,
		LayoutMode.TABLET,
	]
	_fit_action_button_labels()


func _apply_footer_typography() -> void:
	var page_size := FONT_META
	var hint_size := FONT_META
	var action_size := FONT_SECONDARY_ACTION
	match _layout_mode:
		LayoutMode.STANDARD:
			page_size = 20
			hint_size = 20
			action_size = 24
		LayoutMode.TABLET:
			page_size = 20
			hint_size = 18
			action_size = 24
		LayoutMode.PHONE_LANDSCAPE:
			page_size = FONT_CAPTION
			hint_size = FONT_CAPTION
			action_size = FONT_CAPTION
		LayoutMode.PHONE_PORTRAIT:
			page_size = FONT_CAPTION
			hint_size = FONT_CAPTION
			action_size = 18
	_page_label.add_theme_font_size_override("font_size", page_size)
	_page_label.add_theme_font_override("font", _chrome_font)
	_page_label.add_theme_color_override("font_color", COLOR_INK)
	_footer_hint.add_theme_font_size_override("font_size", hint_size)
	_footer_hint.add_theme_font_override("font", _chrome_font)
	_footer_hint.add_theme_color_override("font_color", COLOR_MUTED_DARK)
	_previous_button.add_theme_font_size_override("font_size", action_size)
	_previous_button.add_theme_font_override("font", _action_font)
	_skip_button.add_theme_font_size_override("font_size", action_size)
	_skip_button.add_theme_font_override("font", _action_font)
	_previous_button.add_theme_color_override(
		"font_disabled_color", COLOR_MUTED_DARK
	)
	_skip_button.add_theme_color_override(
		"font_disabled_color", COLOR_MUTED_DARK
	)
	_style_footer_action_button(_previous_button)
	_style_footer_action_button(_skip_button)


func _style_footer_action_button(button: Button) -> void:
	button.add_theme_stylebox_override(
		"normal",
		_transparent_button_style(
			FOOTER_ACTION_OPTICAL_LIFT,
			FOOTER_ACTION_OPTICAL_SHIFT_X
		)
	)
	button.add_theme_stylebox_override(
		"hover",
		_transparent_button_style(
			FOOTER_ACTION_OPTICAL_LIFT,
			FOOTER_ACTION_OPTICAL_SHIFT_X
		)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_transparent_button_style(
			FOOTER_ACTION_OPTICAL_LIFT,
			FOOTER_ACTION_OPTICAL_SHIFT_X
		)
	)
	button.add_theme_stylebox_override(
		"focus",
		_transparent_button_style(
			FOOTER_ACTION_OPTICAL_LIFT,
			FOOTER_ACTION_OPTICAL_SHIFT_X
		)
	)
	button.add_theme_stylebox_override(
		"disabled",
		_transparent_button_style(
			FOOTER_ACTION_OPTICAL_LIFT,
			FOOTER_ACTION_OPTICAL_SHIFT_X
		)
	)


func _fit_action_button_labels() -> void:
	_fit_button_label(
		_previous_button,
		_previous_button.get_theme_font_size("font_size")
	)
	_fit_button_label(
		_skip_button,
		_skip_button.get_theme_font_size("font_size")
	)
	_fit_button_label(_continue_button, FONT_BODY)


func _skip_requires_wide_slot() -> bool:
	var raw := _skip_button.text.replace("\n", "")
	var font_size := _skip_button.get_theme_font_size("font_size")
	return raw.length() * font_size > 104 - 8


func _fit_button_label(button: Button, font_size: int) -> void:
	var raw := button.text.replace("\n", "")
	if raw.is_empty():
		return
	var estimated_width := raw.length() * font_size
	if estimated_width <= maxf(1.0, button.size.x - 8.0):
		button.text = raw
		return
	var split_index := ceili(raw.length() * 0.5)
	button.text = "%s\n%s" % [
		raw.substr(0, split_index),
		raw.substr(split_index),
	]


func _layout_mode_for(viewport_size: Vector2) -> LayoutMode:
	var aspect := viewport_size.x / maxf(1.0, viewport_size.y)
	if viewport_size.x >= 1920.0 and viewport_size.y >= 1080.0:
		return LayoutMode.DESKTOP
	if viewport_size.x >= 1180.0 and viewport_size.y >= 680.0:
		return LayoutMode.STANDARD
	if viewport_size.x >= 900.0 and viewport_size.y >= 650.0:
		return LayoutMode.TABLET
	if aspect >= 1.2:
		return LayoutMode.PHONE_LANDSCAPE
	return LayoutMode.PHONE_PORTRAIT


func _canvas_size_for(mode: LayoutMode, available_size: Vector2) -> Vector2:
	match mode:
		LayoutMode.DESKTOP:
			return DESKTOP_CANVAS
		LayoutMode.STANDARD:
			return STANDARD_CANVAS
		_:
			return available_size


func _layout_mode_name() -> String:
	match _layout_mode:
		LayoutMode.DESKTOP:
			return "desktop"
		LayoutMode.STANDARD:
			return "standard"
		LayoutMode.TABLET:
			return "tablet"
		LayoutMode.PHONE_LANDSCAPE:
			return "phone_landscape"
	return "phone_portrait"


func _available_rect() -> Rect2:
	var insets := _safe_insets()
	return Rect2(
		Vector2(insets.x, insets.y),
		Vector2(
			maxf(1.0, size.x - insets.x - insets.z),
			maxf(1.0, size.y - insets.y - insets.w)
		)
	)


func _safe_insets() -> Vector4:
	if not OS.is_debug_build():
		return Vector4.ZERO
	var raw := OS.get_environment("AI_TOWN_SAFE_INSETS").strip_edges()
	var parts := raw.split(",")
	if parts.size() != 4:
		return Vector4.ZERO
	return Vector4(
		maxf(0.0, float(parts[0])),
		maxf(0.0, float(parts[1])),
		maxf(0.0, float(parts[2])),
		maxf(0.0, float(parts[3]))
	)


func _button(
	node_name: String,
	text: String,
	font_size: int,
	callback: Callable
) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.theme = _button_theme
	button.add_theme_font_override("font", _chrome_font)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", COLOR_INK)
	button.add_theme_color_override("font_hover_color", COLOR_TERRACOTTA)
	button.add_theme_color_override("font_pressed_color", COLOR_WOOD_DARK)
	button.add_theme_color_override("font_focus_color", COLOR_TERRACOTTA)
	button.add_theme_color_override("font_disabled_color", COLOR_MUTED)
	button.add_theme_color_override("font_outline_color", COLOR_WOOD_DARK)
	button.add_theme_constant_override("outline_size", 0)
	button.add_theme_stylebox_override("normal", _transparent_button_style())
	button.add_theme_stylebox_override("hover", _transparent_button_style())
	button.add_theme_stylebox_override("pressed", _transparent_button_style())
	button.add_theme_stylebox_override("focus", _transparent_button_style())
	button.add_theme_stylebox_override("disabled", _transparent_button_style())
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	button.clip_text = true
	button.pressed.connect(callback)
	return button


func _label(
	node_name: String,
	text: String,
	font_size: int,
	color: Color
) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.theme = _body_theme
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("line_spacing", 8)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _style_primary_button(
	button: Button,
	disabled: bool,
	loading: bool = false
) -> void:
	var text_color := COLOR_MUTED if disabled else COLOR_BUTTON_INK
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", COLOR_PAPER)
	button.add_theme_color_override("font_focus_color", COLOR_BUTTON_INK)
	button.add_theme_color_override("font_disabled_color", COLOR_MUTED)
	button.add_theme_constant_override("outline_size", 0)
	for state in ["normal", "hover", "focus", "pressed"]:
		button.add_theme_stylebox_override(
			state,
			_primary_button_styles[state] as StyleBox
		)
	button.add_theme_stylebox_override(
		"disabled",
		_primary_button_styles[
			"loading" if loading else "disabled"
		] as StyleBox
	)


func _primary_button_state_style(
	texture: Texture2D,
	pressed: bool
) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = 24.0
	style.texture_margin_top = 8.0
	style.texture_margin_right = 24.0
	style.texture_margin_bottom = 8.0
	style.content_margin_left = 16.0
	style.content_margin_top = 10.0 if pressed else 8.0
	style.content_margin_right = 16.0
	style.content_margin_bottom = 6.0 if pressed else 12.0
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.draw_center = true
	return style


func _transparent_button_style(
	optical_lift: float = CHROME_OPTICAL_LIFT,
	optical_shift_x: float = 0.0
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color.TRANSPARENT
	style.content_margin_left = maxf(0.0, optical_shift_x * 2.0)
	style.content_margin_top = 0.0
	style.content_margin_right = maxf(0.0, -optical_shift_x * 2.0)
	style.content_margin_bottom = optical_lift * 2.0
	style.anti_aliasing = false
	return style


func _button_text_fits_horizontally(
	button: Button,
	font_size: int,
	minimum_gap: float
) -> bool:
	var lines := button.text.split("\n")
	for line: String in lines:
		var estimated_width := line.length() * font_size
		if estimated_width > button.size.x - minimum_gap * 2.0:
			return false
	return true


func _stylebox_has_visible_border(style: StyleBox) -> bool:
	if style == null:
		return false
	if style is StyleBoxTexture:
		return (style as StyleBoxTexture).texture != null
	if style is StyleBoxFlat:
		var flat := style as StyleBoxFlat
		if flat.border_color.a <= 0.0:
			return false
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			if flat.get_border_width(side) > 0:
				return true
	return false


func _panel_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_content_margin_all(20)
	style.anti_aliasing = false
	return style


func _set_rect(control: Control, rect: Rect2) -> void:
	control.position = rect.position.round()
	control.size = rect.size.round()


func _set_chrome_label_rect(
	control: Control,
	rect: Rect2,
	optical_lift: float = CHROME_OPTICAL_LIFT,
	optical_shift_x: float = 0.0
) -> void:
	if rect.size == Vector2.ZERO:
		_set_rect(control, rect)
		return
	var optical_rect := rect
	optical_rect.position.y -= optical_lift
	optical_rect.position.x += optical_shift_x
	_set_rect(control, optical_rect)


func _build_fatal_error(message: String) -> void:
	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", FONT_BODY)
	label.add_theme_color_override("font_color", COLOR_BUTTON_INK)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(label)
