class_name StartupScreen
extends Control


signal intent_requested(intent: StringName, payload: Dictionary)
signal action_blocked(intent: StringName, reason: String)
signal view_model_rejected(reason: String)


const NEW_GAME_INTENT := &"session.new_game"
const CONTINUE_INTENT := &"session.continue"
const RETURN_INTENT := &"startup.back"
const CONNECTION_SETTINGS_INTENT := &"startup.open_connection_settings"
const GAME_SETTINGS_INTENT := &"startup.open_game_settings"
const LOAD_GAME_INTENT := &"startup.open_load_game"
const QUIT_GAME_INTENT := &"startup.quit_game"
const RESIDENT_MESSAGES_SHOWN_INTENT := &"startup.resident_messages_shown"
const UiNodeRetirement := preload("res://ui/common/AiTownUiNodeRetirement.gd")

const STARTUP_BACKGROUND_TEXTURE_PATH := (
	"res://assets/ui/startup/final/startup_town_background.png"
)
const STARTUP_TITLE_PATH := "res://assets/ui/startup/final/startup_title_sign.png"
const STARTUP_COMPONENT_DIR := "res://assets/ui/startup/final/components_v1"
const STARTUP_EXACT_COMPONENT_DIR := (
	"res://assets/ui/startup/runtime"
)
const STARTUP_MENU_SHELL_PATH := STARTUP_COMPONENT_DIR + "/startup_menu_shell_v1.png"
const STARTUP_SUMMARY_PLAQUE_PATH := (
	STARTUP_EXACT_COMPONENT_DIR
	+ "/startup_save_summary_plaque_v2_exact_460x63.png"
)
const RESIDENT_MESSAGE_ASSET_DIR := (
	STARTUP_EXACT_COMPONENT_DIR + "/resident_messages/v1"
)
const RESIDENT_MESSAGE_SHELL_PATH := (
	RESIDENT_MESSAGE_ASSET_DIR + "/resident_message_shell_clean_v2.png"
)
const RESIDENT_MESSAGE_TOP_CARD_PATH := (
	RESIDENT_MESSAGE_ASSET_DIR + "/resident_message_card_top_v2.png"
)
const RESIDENT_MESSAGE_BOTTOM_CARD_PATH := (
	RESIDENT_MESSAGE_ASSET_DIR + "/resident_message_card_bottom_v2.png"
)
const RESIDENT_MESSAGE_CLOSE_BUTTON_PATH := (
	RESIDENT_MESSAGE_ASSET_DIR + "/resident_message_close_button_v2.png"
)
const STARTUP_BUTTON_THEME := preload(
	"res://ui/startup/StartupButtonImageTheme.gd"
)
const STARTUP_HELP_FEEDBACK_PANEL := preload(
	"res://ui/startup/StartupHelpFeedbackPanel.gd"
)
const SOCIAL_LINK_LABEL_FONT := preload(
	"res://assets/fonts/zheng_ge_dian_hei_16/ZhengGeDianHei-16.ttf"
)

const REFERENCE_VIEWPORT := Vector2(1920.0, 1080.0)
const MAIN_MENU_SCALE := 0.86
const MAIN_MENU_PIVOT := Vector2(960.0, 570.0)
const STARTUP_BACKGROUND_SIZE := Vector2(1920.0, 1080.0)
const DAY_CYCLE_SECONDS := 48.0
const WEATHER_BLEND_SPEED := 0.50
const WEATHER_NAMES: Array[String] = ["晴天", "雨天", "雪天", "雷暴"]
const DAY_PHASE_NAMES: Array[String] = ["白天", "傍晚", "夜晚", "清晨"]

const TITLE_RECT := Rect2(558.0, 82.0, 804.0, 264.0)
const MENU_SHELL_RECT := Rect2(600.0, 350.0, 720.0, 710.0)
const SAVE_SUMMARY_RECT := Rect2(690.0, 449.0, 540.0, 73.9565)
const CONTINUE_RECT := Rect2(690.0, 538.9565, 540.0, 82.3529)
const NEW_GAME_RECT := Rect2(690.0, 637.3094, 540.0, 82.3529)
const LOAD_GAME_RECT := Rect2(690.0, 735.6623, 540.0, 82.3529)
const CONNECTION_RECT := Rect2(690.0, 834.0152, 258.0, 80.1892)
const SETTINGS_RECT := Rect2(972.0, 834.0152, 258.0, 80.1892)
const EXIT_RECT := Rect2(690.0, 930.2044, 540.0, 76.9737)
const GITHUB_BUTTON_RECT := Rect2(1476.0, 24.0, 96.0, 94.0)
const BILIBILI_BUTTON_RECT := Rect2(1574.0, 24.0, 96.0, 94.0)
const HELP_FEEDBACK_BUTTON_RECT := Rect2(1672.0, 24.0, 96.0, 94.0)
const HELP_FEEDBACK_PANEL_RECT := Rect2(1616.0, 118.0, 208.0, 116.5)
const SOCIAL_LINK_ASSET_DIR := (
	"res://assets/ui/startup/runtime/social_links"
)
const GITHUB_URL := "https://github.com/mewamew/my_ai_town"
const BILIBILI_URL := "https://space.bilibili.com/3546572358945017"

const BACKGROUND_SHADER_CODE := """
shader_type canvas_item;
render_mode unshaded;

uniform float day_cycle = 0.0;

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec3 tint = vec3(1.0);
	float brightness = 1.0;

	if (day_cycle < 0.25) {
		float t = smoothstep(0.0, 1.0, day_cycle / 0.25);
		tint = mix(vec3(1.0), vec3(1.05, 0.78, 0.58), t);
		brightness = mix(1.0, 0.88, t);
	} else if (day_cycle < 0.50) {
		float t = smoothstep(0.0, 1.0, (day_cycle - 0.25) / 0.25);
		tint = mix(vec3(1.05, 0.78, 0.58), vec3(0.38, 0.49, 0.72), t);
		brightness = mix(0.88, 0.56, t);
	} else if (day_cycle < 0.75) {
		float t = smoothstep(0.0, 1.0, (day_cycle - 0.50) / 0.25);
		tint = mix(vec3(0.38, 0.49, 0.72), vec3(0.78, 0.66, 0.82), t);
		brightness = mix(0.56, 0.75, t);
	} else {
		float t = smoothstep(0.0, 1.0, (day_cycle - 0.75) / 0.25);
		tint = mix(vec3(0.78, 0.66, 0.82), vec3(1.0), t);
		brightness = mix(0.75, 1.0, t);
	}

	vec3 color = source.rgb * tint * brightness;
	float night = smoothstep(0.32, 0.50, day_cycle) * (1.0 - smoothstep(0.70, 0.88, day_cycle));
	color = mix(color, color * vec3(0.72, 0.82, 1.04), night * 0.28);
	COLOR = vec4(color, source.a);
}
"""

const WEATHER_SHADER_CODE := """
shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform float weather_time = 0.0;
uniform float rain_intensity = 0.0;
uniform float snow_intensity = 0.0;
uniform float storm_intensity = 0.0;
uniform float lightning_flash = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float rain_layer(vec2 uv, float scale, float speed, float seed) {
	vec2 space = vec2(uv.x + uv.y * 0.13, uv.y) * vec2(92.0, 46.0) * scale;
	space += vec2(weather_time * 5.5, -weather_time * speed) + seed;
	vec2 cell = floor(space);
	vec2 local = fract(space);
	float gate = step(0.72, hash21(cell + seed));
	float line = 1.0 - smoothstep(0.025, 0.085, abs(local.x - 0.5));
	line *= 1.0 - smoothstep(0.40, 0.94, local.y);
	return line * gate;
}

float snow_layer(vec2 uv, float scale, float speed, float seed) {
	vec2 space = uv * vec2(34.0, 20.0) * scale;
	space += vec2(sin(weather_time * 0.42 + seed) * 1.7, weather_time * speed);
	vec2 cell = floor(space);
	vec2 local = fract(space) - vec2(0.5);
	float random = hash21(cell + seed);
	local.x += sin(weather_time * 0.9 + random * 12.0) * 0.20;
	float flake = 1.0 - smoothstep(0.055, 0.15, length(local));
	return flake * step(0.70, random);
}

void fragment() {
	float storm_on = clamp(storm_intensity, 0.0, 1.0);
	float rain_on = clamp(rain_intensity + storm_on, 0.0, 1.0);
	float snow_on = clamp(snow_intensity, 0.0, 1.0);

	float rain = 0.0;
	if (rain_on > 0.001) {
		rain = rain_layer(UV, 1.0, 15.0, 0.0) * 0.66;
		rain += rain_layer(UV, 1.45, 21.0, 17.0) * 0.34;
		rain *= rain_on;
	}

	float snow = 0.0;
	if (snow_on > 0.001) {
		snow = snow_layer(UV, 0.75, 1.25, 4.0) * 0.48;
		snow += snow_layer(UV, 1.15, 1.75, 19.0) * 0.36;
		snow += snow_layer(UV, 1.60, 2.20, 37.0) * 0.22;
		snow *= snow_on;
	}

	float bad_weather = max(rain_on, snow_on);
	vec3 shade = mix(vec3(0.18, 0.24, 0.30), vec3(0.09, 0.13, 0.20), storm_on);
	vec3 color = shade;
	color = mix(color, vec3(0.68, 0.84, 0.98), clamp(rain, 0.0, 1.0));
	color = mix(color, vec3(0.96, 0.98, 1.0), clamp(snow, 0.0, 1.0));
	color = mix(color, vec3(0.94, 0.97, 1.0), lightning_flash * storm_on);

	vec2 vignette_uv = (UV - vec2(0.5)) * vec2(1.0, 0.72);
	float vignette = smoothstep(0.35, 0.72, length(vignette_uv));
	float shade_alpha = bad_weather * (0.10 + storm_on * 0.12) + vignette * bad_weather * 0.08;
	float alpha = clamp(shade_alpha + rain * 0.62 + snow * 0.88 + lightning_flash * 0.78, 0.0, 0.86);
	COLOR = vec4(color, alpha);
}
"""

var _background_material: ShaderMaterial
var _weather_material: ShaderMaterial
var _weather_overlay: ColorRect
var _background_preview: Node2D
var _save_summary_label: Label
var _continue_button: Button
var _new_game_button: Button
var _load_game_button: Button
var _connection_button: Button
var _settings_button: Button
var _exit_button: Button
var _github_button: TextureButton
var _bilibili_button: TextureButton
var _help_feedback_button: TextureButton
var _help_feedback_panel: Control
var _notice_tween: Tween
var _host_request_pending_intent := &""
var _resident_message_layer: CanvasLayer
var _resident_message_overlay: Control
var _resident_message_batch_key := ""
var _resident_message_pending_receipt: Dictionary = {}

var _session_view_model: Dictionary = {}
var _save_view_model: Dictionary = {}
var _session_revision := -1
var _save_revision := -1
var _route_status_text := "正在读取启动资料"

var _rng := RandomNumberGenerator.new()
var _elapsed := 0.0
var _weather_elapsed := 0.0
var _weather_hold := 35.0
var _weather_index := 0
var _rain_intensity := 0.0
var _snow_intensity := 0.0
var _storm_intensity := 0.0
var _lightning_wait := 1.0
var _lightning_flash := 0.0
var _lightning_flashes_remaining := 0
var _interface_theme_scale := -1.0


func _ready() -> void:
	_rng.randomize()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	RenderingServer.set_default_clear_color(Color("152d25"))
	_build_background()
	_build_interface()
	resized.connect(_sync_interface_theme)
	_sync_interface_theme()
	_choose_next_weather(true)


func _process(delta: float) -> void:
	_elapsed += delta
	_weather_elapsed += delta
	var cycle := fmod(_elapsed / DAY_CYCLE_SECONDS, 1.0)
	_background_material.set_shader_parameter("day_cycle", cycle)
	_weather_material.set_shader_parameter("weather_time", _elapsed)
	_update_weather_blend(delta)

	if _weather_elapsed >= _weather_hold:
		_choose_next_weather(false)

	if (
		_weather_index == 3
		and _storm_intensity >= 0.65
		and _lightning_flashes_remaining > 0
	):
		_lightning_wait -= delta
		if _lightning_wait <= 0.0:
			_lightning_flash = 1.0
			_lightning_flashes_remaining -= 1
			_lightning_wait = _rng.randf_range(2.8, 4.8)
	_lightning_flash = move_toward(_lightning_flash, 0.0, delta * 4.8)
	_weather_material.set_shader_parameter("lightning_flash", _lightning_flash)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if is_instance_valid(_resident_message_overlay):
		get_viewport().set_input_as_handled()
		if event.keycode == KEY_ESCAPE:
			request_return_to_host()
		return
	match event.keycode:
		KEY_N:
			get_viewport().set_input_as_handled()
			_request_action("newGame")
		KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			if _host_request_pending_intent != &"":
				_show_notice("正在处理，请稍候。")
				return
			request_return_to_host()


func _build_background() -> void:
	var background_shader := Shader.new()
	background_shader.code = BACKGROUND_SHADER_CODE
	_background_material = ShaderMaterial.new()
	_background_material.shader = background_shader
	_build_startup_background()

	_weather_overlay = ColorRect.new()
	_weather_overlay.name = "WeatherOverlay"
	_weather_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_weather_overlay.color = Color.WHITE
	_weather_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weather_overlay.z_index = 500
	var weather_shader := Shader.new()
	weather_shader.code = WEATHER_SHADER_CODE
	_weather_material = ShaderMaterial.new()
	_weather_material.shader = weather_shader
	_weather_overlay.material = _weather_material
	add_child(_weather_overlay)
	resized.connect(_layout_startup_background)
	_layout_startup_background()


func _build_startup_background() -> void:
	_background_preview = Node2D.new()
	_background_preview.name = "StartupTownPreview"
	add_child(_background_preview)

	var town_map := Sprite2D.new()
	town_map.name = "TownMap"
	town_map.centered = false
	town_map.texture = _load_texture(STARTUP_BACKGROUND_TEXTURE_PATH)
	town_map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	town_map.material = _background_material
	town_map.z_index = -200
	_background_preview.add_child(town_map)


func _layout_startup_background() -> void:
	if _background_preview == null:
		return
	var viewport_size := size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = get_viewport_rect().size
	var cover_scale := maxf(
		viewport_size.x / STARTUP_BACKGROUND_SIZE.x,
		viewport_size.y / STARTUP_BACKGROUND_SIZE.y
	)
	_background_preview.scale = Vector2.ONE * cover_scale
	_background_preview.position = (
		viewport_size - STARTUP_BACKGROUND_SIZE * cover_scale
	) * 0.5


func _build_interface() -> void:
	theme = STARTUP_BUTTON_THEME.create()
	_interface_theme_scale = 1.0
	_add_texture_layer("StartupTitle", STARTUP_TITLE_PATH, TITLE_RECT, true)
	_add_texture_layer(
		"StartupMenuShell",
		STARTUP_MENU_SHELL_PATH,
		MENU_SHELL_RECT,
		false,
	)
	_add_texture_layer(
		"StartupSaveSummaryPlaque",
		STARTUP_SUMMARY_PLAQUE_PATH,
		SAVE_SUMMARY_RECT,
		true,
	)
	_save_summary_label = _add_interface_label(
		"SaveSummary",
		SAVE_SUMMARY_RECT,
		&"StartupSaveSummary",
	)

	_continue_button = _add_image_button(
		"ContinueGameButton",
		"继续游戏",
		CONTINUE_RECT,
		&"StartupPrimaryButton",
		_request_action.bind("continue"),
	)
	_new_game_button = _add_image_button(
		"NewGameButton",
		"开始新游戏",
		NEW_GAME_RECT,
		&"StartupPrimaryButton",
		_request_action.bind("newGame"),
	)
	_load_game_button = _add_image_button(
		"LoadGameButton",
		"加载游戏",
		LOAD_GAME_RECT,
		&"StartupPrimaryButton",
		request_load_game_to_host,
	)
	_connection_button = _add_image_button(
		"ConnectionSettingsButton",
		"模型设置",
		CONNECTION_RECT,
		&"StartupSecondaryButton",
		_request_startup_route.bind(CONNECTION_SETTINGS_INTENT),
	)
	_settings_button = _add_image_button(
		"GameSettingsButton",
		"游戏设置",
		SETTINGS_RECT,
		&"StartupSecondaryButton",
		_request_startup_route.bind(GAME_SETTINGS_INTENT),
	)
	_exit_button = _add_image_button(
		"ExitGameButton",
		"退出游戏",
		EXIT_RECT,
		&"StartupQuietButton",
		request_quit_to_host,
	)
	_github_button = _add_social_link_button(
		"GitHubButton",
		"打开 GitHub 项目主页",
		"github",
		GITHUB_BUTTON_RECT,
		_open_external_url.bind(GITHUB_URL, "GitHub 项目主页"),
	)
	_bilibili_button = _add_social_link_button(
		"BilibiliButton",
		"打开哔哩哔哩主页",
		"bilibili",
		BILIBILI_BUTTON_RECT,
		_open_external_url.bind(BILIBILI_URL, "哔哩哔哩主页"),
	)
	_help_feedback_button = _add_social_link_button(
		"HelpFeedbackButton",
		"打开帮助与反馈选项",
		"feedback",
		HELP_FEEDBACK_BUTTON_RECT,
		_open_help_feedback_panel,
		"反馈",
	)
	_wire_main_menu_focus_neighbors()
	_sync_route_state()


func _sync_interface_theme() -> void:
	var viewport_size := size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = get_viewport_rect().size
	var layout_scale := maxf(
		minf(
			viewport_size.x / REFERENCE_VIEWPORT.x,
			viewport_size.y / REFERENCE_VIEWPORT.y,
		),
		0.5,
	)
	_layout_interface_controls(viewport_size, layout_scale)
	# Window responsiveness is applied as one CanvasItem transform below. Keep
	# the logical controls and theme at their approved size so Godot's minimum-size
	# calculation cannot enlarge individual buttons and break their gaps.
	var theme_scale := 1.0
	if is_equal_approx(theme_scale, _interface_theme_scale):
		return
	theme = STARTUP_BUTTON_THEME.create(0.0, theme_scale)
	_interface_theme_scale = theme_scale


func _main_menu_rect(reference_rect: Rect2) -> Rect2:
	return Rect2(
		MAIN_MENU_PIVOT + (
			reference_rect.position - MAIN_MENU_PIVOT
		) * MAIN_MENU_SCALE,
		reference_rect.size * MAIN_MENU_SCALE,
	)


func _layout_interface_controls(
	viewport_size: Vector2,
	layout_scale: float,
) -> void:
	var canvas_offset := (
		viewport_size - REFERENCE_VIEWPORT * layout_scale
	) * 0.5
	for child: Node in get_children():
		if not child is Control or not child.has_meta("startup_reference_rect"):
			continue
		var control := child as Control
		var reference_rect := control.get_meta(
			"startup_reference_rect",
		) as Rect2
		var keep_reference_scale := bool(
			control.get_meta("startup_keep_reference_scale", false)
		)
		var visual_rect := (
			reference_rect
			if keep_reference_scale
			else _main_menu_rect(reference_rect)
		)
		control.position = canvas_offset + visual_rect.position * layout_scale
		control.size = reference_rect.size
		control.scale = Vector2.ONE * layout_scale * (
			1.0 if keep_reference_scale else MAIN_MENU_SCALE
		)


func _wire_main_menu_focus_neighbors() -> void:
	var ordered: Array[BaseButton] = [
		_continue_button,
		_new_game_button,
		_load_game_button,
		_connection_button,
		_settings_button,
		_exit_button,
		_github_button,
		_bilibili_button,
		_help_feedback_button,
	]
	for index: int in range(ordered.size()):
		var button := ordered[index] as BaseButton
		var previous := ordered[(index - 1 + ordered.size()) % ordered.size()]
		var next := ordered[(index + 1) % ordered.size()]
		button.focus_previous = button.get_path_to(previous)
		button.focus_next = button.get_path_to(next)
	_continue_button.focus_neighbor_top = _continue_button.get_path_to(_github_button)
	_continue_button.focus_neighbor_bottom = _continue_button.get_path_to(_new_game_button)
	_new_game_button.focus_neighbor_top = _new_game_button.get_path_to(_continue_button)
	_new_game_button.focus_neighbor_bottom = _new_game_button.get_path_to(_load_game_button)
	_load_game_button.focus_neighbor_top = _load_game_button.get_path_to(_new_game_button)
	_load_game_button.focus_neighbor_bottom = _load_game_button.get_path_to(_connection_button)
	_connection_button.focus_neighbor_top = _connection_button.get_path_to(_load_game_button)
	_connection_button.focus_neighbor_right = _connection_button.get_path_to(_settings_button)
	_connection_button.focus_neighbor_bottom = _connection_button.get_path_to(_exit_button)
	_settings_button.focus_neighbor_top = _settings_button.get_path_to(_load_game_button)
	_settings_button.focus_neighbor_left = _settings_button.get_path_to(_connection_button)
	_settings_button.focus_neighbor_bottom = _settings_button.get_path_to(_exit_button)
	_exit_button.focus_neighbor_top = _exit_button.get_path_to(_connection_button)
	_exit_button.focus_neighbor_bottom = _exit_button.get_path_to(_github_button)
	_github_button.focus_neighbor_left = _github_button.get_path_to(_help_feedback_button)
	_github_button.focus_neighbor_right = _github_button.get_path_to(_bilibili_button)
	_github_button.focus_neighbor_bottom = _github_button.get_path_to(_continue_button)
	_bilibili_button.focus_neighbor_left = _bilibili_button.get_path_to(_github_button)
	_bilibili_button.focus_neighbor_right = _bilibili_button.get_path_to(_help_feedback_button)
	_bilibili_button.focus_neighbor_bottom = _bilibili_button.get_path_to(_continue_button)
	_help_feedback_button.focus_neighbor_left = (
		_help_feedback_button.get_path_to(_bilibili_button)
	)
	_help_feedback_button.focus_neighbor_right = (
		_help_feedback_button.get_path_to(_github_button)
	)
	_help_feedback_button.focus_neighbor_bottom = (
		_help_feedback_button.get_path_to(_continue_button)
	)


func _add_texture_layer(
	node_name: String,
	texture_path: String,
	reference_rect: Rect2,
	keep_aspect: bool = false
) -> void:
	var texture_rect := TextureRect.new()
	texture_rect.name = node_name
	_apply_reference_rect(texture_rect, reference_rect)
	texture_rect.texture = _load_texture(texture_path)
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if keep_aspect
		else TextureRect.STRETCH_SCALE
	)
	texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_rect.z_index = 1000
	add_child(texture_rect)


func _add_image_button(
	node_name: String,
	button_text: String,
	reference_rect: Rect2,
	variation: StringName,
	callback: Callable,
) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = button_text
	button.tooltip_text = button_text
	button.theme_type_variation = variation
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.z_index = 1001
	_apply_reference_rect(button, reference_rect)
	button.pressed.connect(callback)
	add_child(button)
	return button


func _add_social_link_button(
	node_name: String,
	accessible_label: String,
	asset_name: String,
	reference_rect: Rect2,
	callback: Callable,
	caption_text := "",
) -> TextureButton:
	var button := TextureButton.new()
	button.name = node_name
	button.tooltip_text = accessible_label
	button.texture_normal = _load_texture(
		"%s/%s_default.png" % [SOCIAL_LINK_ASSET_DIR, asset_name]
	)
	button.texture_hover = _load_texture(
		"%s/%s_hover.png" % [SOCIAL_LINK_ASSET_DIR, asset_name]
	)
	button.texture_pressed = button.texture_hover
	button.texture_focused = button.texture_hover
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_SCALE
	button.clip_contents = true
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.z_index = 1001
	_apply_reference_rect(button, reference_rect)
	button.set_meta("startup_keep_reference_scale", true)
	button.pressed.connect(callback)
	add_child(button)
	if not caption_text.is_empty():
		var caption := Label.new()
		caption.name = "ButtonCaption"
		caption.position = Vector2(0.0, 63.0)
		caption.size = Vector2(96.0, 16.0)
		caption.text = caption_text
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		caption.add_theme_font_override("font", SOCIAL_LINK_LABEL_FONT)
		caption.add_theme_font_size_override("font_size", 10)
		caption.add_theme_color_override("font_color", Color("3f2818"))
		caption.add_theme_color_override("font_outline_color", Color("fff0cc"))
		caption.add_theme_constant_override("outline_size", 2)
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(caption)
	return button


func _open_help_feedback_panel() -> void:
	if is_instance_valid(_help_feedback_panel):
		_help_feedback_panel.queue_free()
		return
	var help_feedback_panel := (
		STARTUP_HELP_FEEDBACK_PANEL.new() as StartupHelpFeedbackPanel
	)
	help_feedback_panel.external_open_failed.connect(_show_notice)
	_help_feedback_panel = help_feedback_panel
	_apply_reference_rect(_help_feedback_panel, HELP_FEEDBACK_PANEL_RECT)
	_help_feedback_panel.set_meta("startup_keep_reference_scale", true)
	_help_feedback_panel.z_index = 1010
	_help_feedback_panel.tree_exiting.connect(_on_help_feedback_panel_closed)
	add_child(_help_feedback_panel)
	_sync_interface_theme()


func _on_help_feedback_panel_closed() -> void:
	_help_feedback_panel = null
	if is_instance_valid(_help_feedback_button):
		_help_feedback_button.grab_focus.call_deferred()


func _open_external_url(url: String, destination_name: String) -> void:
	var open_error := OS.shell_open(url)
	if open_error == OK:
		return
	_show_notice("暂时无法打开%s，请稍后再试。" % destination_name)
	push_warning(
		"启动页无法打开外部链接：%s (%s)"
		% [url, error_string(open_error)]
	)


func _add_interface_label(
	node_name: String,
	reference_rect: Rect2,
	variation: StringName,
) -> Label:
	var label := Label.new()
	label.name = node_name
	label.theme_type_variation = variation
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 1002
	_apply_reference_rect(label, reference_rect)
	add_child(label)
	return label


func _apply_reference_rect(control: Control, reference_rect: Rect2) -> void:
	control.set_meta("startup_reference_rect", reference_rect)
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 0.0
	control.anchor_bottom = 0.0
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = reference_rect.size.x
	control.offset_bottom = reference_rect.size.y
	control.position = reference_rect.position


func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path, "Texture2D"):
		var imported := ResourceLoader.load(path, "Texture2D") as Texture2D
		if imported != null:
			return imported
	var image := Image.new()
	var error := image.load(ProjectSettings.globalize_path(path))
	if error != OK:
		push_error("启动页无法读取资产：%s (%s)" % [path, error_string(error)])
		return null
	return ImageTexture.create_from_image(image)


func _choose_next_weather(initial: bool) -> void:
	var previous := _weather_index
	if initial:
		_weather_index = 0
		_weather_hold = _rng.randf_range(8.0, 11.0)
	elif previous != 0:
		_weather_index = 0
		_weather_hold = _rng.randf_range(8.0, 12.0)
	else:
		var roll := _rng.randf()
		if roll < 0.82:
			_weather_index = 0
			_weather_hold = _rng.randf_range(8.0, 13.0)
		elif roll < 0.92:
			_weather_index = 1
			_weather_hold = _rng.randf_range(6.0, 9.0)
		elif roll < 0.98:
			_weather_index = 2
			_weather_hold = _rng.randf_range(7.0, 10.0)
		else:
			_weather_index = 3
			_weather_hold = _rng.randf_range(3.5, 4.5)
	_weather_elapsed = 0.0
	_lightning_wait = _rng.randf_range(1.4, 2.6)
	_lightning_flashes_remaining = _rng.randi_range(1, 2) if _weather_index == 3 else 0
	if _weather_index != 3:
		_lightning_flash = 0.0
	if initial:
		_set_weather_blend_immediate()


func _update_weather_blend(delta: float) -> void:
	var rain_target := 1.0 if _weather_index == 1 else 0.0
	var snow_target := 1.0 if _weather_index == 2 else 0.0
	var storm_target := 1.0 if _weather_index == 3 else 0.0
	var blend_step := WEATHER_BLEND_SPEED * delta
	_rain_intensity = move_toward(_rain_intensity, rain_target, blend_step)
	_snow_intensity = move_toward(_snow_intensity, snow_target, blend_step)
	_storm_intensity = move_toward(_storm_intensity, storm_target, blend_step)
	_sync_weather_shader()


func _set_weather_blend_immediate() -> void:
	_rain_intensity = 1.0 if _weather_index == 1 else 0.0
	_snow_intensity = 1.0 if _weather_index == 2 else 0.0
	_storm_intensity = 1.0 if _weather_index == 3 else 0.0
	_sync_weather_shader()


func _sync_weather_shader() -> void:
	_weather_material.set_shader_parameter("rain_intensity", _rain_intensity)
	_weather_material.set_shader_parameter("snow_intensity", _snow_intensity)
	_weather_material.set_shader_parameter("storm_intensity", _storm_intensity)
	if _weather_overlay != null:
		_weather_overlay.visible = maxf(
			_rain_intensity,
			maxf(_snow_intensity, _storm_intensity),
		) > 0.001


func _show_notice(message: String) -> void:
	if _save_summary_label == null:
		return
	if _notice_tween != null and _notice_tween.is_valid():
		_notice_tween.kill()
	_save_summary_label.text = message
	_save_summary_label.tooltip_text = message
	_save_summary_label.modulate.a = 1.0
	_notice_tween = create_tween()
	_notice_tween.tween_interval(1.8)
	_notice_tween.tween_property(_save_summary_label, "modulate:a", 0.0, 0.35)
	_notice_tween.tween_callback(_restore_save_summary)


func _restore_save_summary() -> void:
	if _save_summary_label == null:
		return
	var data := _session_view_model.get("data", {}) as Dictionary
	_save_summary_label.text = _compact_save_summary(data)
	_save_summary_label.tooltip_text = _save_summary_label.text
	_save_summary_label.modulate.a = 1.0


func apply_view_models(
	session_snapshot: Dictionary,
	save_snapshot: Dictionary,
) -> bool:
	var issues := PackedStringArray()
	issues.append_array(
		AiTownUiViewModel.validate(session_snapshot, "启动页 session")
	)
	issues.append_array(
		AiTownUiViewModel.validate(save_snapshot, "启动页 save")
	)
	if AiTownUiViewModel.scope(session_snapshot) != &"session":
		issues.append("启动页 session ViewModel scope 必须为 session。")
	if AiTownUiViewModel.scope(save_snapshot) != &"save":
		issues.append("启动页 save ViewModel scope 必须为 save。")
	if not AiTownUiViewModel.accepts_revision(
		_session_revision,
		session_snapshot,
	):
		issues.append("启动页拒绝旧 session revision。")
	if not AiTownUiViewModel.accepts_revision(_save_revision, save_snapshot):
		issues.append("启动页拒绝旧 save revision。")
	issues.append_array(_validate_startup_contract(session_snapshot, save_snapshot))
	if not issues.is_empty():
		var reason := "\n".join(issues)
		view_model_rejected.emit(reason)
		return false
	var incoming_session_revision := AiTownUiViewModel.revision(session_snapshot)
	if (
		_host_request_pending_intent != &""
		and incoming_session_revision > _session_revision
	):
		# A newer Host-owned snapshot is also a response. This matters when the
		# Host refreshes the same Startup page instead of changing scenes, such
		# as after save discovery or a recoverable startup rejection.
		_host_request_pending_intent = &""
	_session_view_model = session_snapshot.duplicate(true)
	_save_view_model = save_snapshot.duplicate(true)
	_session_revision = incoming_session_revision
	_save_revision = AiTownUiViewModel.revision(save_snapshot)
	_sync_route_state()
	_sync_resident_message_popup()
	return true


func _sync_resident_message_popup() -> void:
	var data := _session_view_model.get("data", {}) as Dictionary
	var slot_id := String(data.get("residentMessageSlotId", "")).strip_edges()
	var messages_value: Variant = data.get("residentMessages", [])
	if slot_id.is_empty() or not messages_value is Array:
		return
	var messages := messages_value as Array
	if messages.is_empty():
		return
	var message_ids: Array[String] = []
	for message_value: Variant in messages:
		if not message_value is Dictionary:
			return
		var message := message_value as Dictionary
		var message_id := String(message.get("message_id", "")).strip_edges()
		if message_id.is_empty() or message_ids.has(message_id):
			return
		message_ids.append(message_id)
	var batch_key := "%s:%s" % [slot_id, ",".join(message_ids)]
	if batch_key == _resident_message_batch_key:
		return
	_close_resident_message_popup(false)
	_resident_message_batch_key = batch_key
	_resident_message_layer = CanvasLayer.new()
	_resident_message_layer.name = "ResidentMessagePopup"
	_resident_message_layer.layer = 100
	_resident_message_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_resident_message_overlay = _build_resident_message_popup(messages)
	_resident_message_layer.add_child(_resident_message_overlay)
	add_child(_resident_message_layer)
	_resident_message_pending_receipt = {
		"slotId": slot_id,
		"messageIds": message_ids.duplicate(),
		"batchKey": batch_key,
	}


func _build_resident_message_popup(messages: Array) -> Control:
	var overlay := ColorRect.new()
	overlay.name = "ModalBackdrop"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.06, 0.055, 0.04, 0.52)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var card_count := clampi(messages.size(), 1, 2)
	var single_message := card_count == 1
	var panel_width := 620.0
	var panel_height := 341.0 if single_message else 495.0
	var panel := Control.new()
	panel.name = "ResidentMessagePanel"
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -panel_width * 0.5
	panel.offset_top = -panel_height * 0.5 + 25.0
	panel.offset_right = panel_width * 0.5
	panel.offset_bottom = panel_height * 0.5 + 25.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.z_index = 1
	overlay.add_child(panel)

	if single_message:
		var compact_shell := NinePatchRect.new()
		compact_shell.name = "ResidentMessageShell"
		compact_shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		compact_shell.texture = _load_texture(RESIDENT_MESSAGE_SHELL_PATH)
		compact_shell.patch_margin_left = 60
		compact_shell.patch_margin_top = 96
		compact_shell.patch_margin_right = 60
		compact_shell.patch_margin_bottom = 83
		compact_shell.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		compact_shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(compact_shell)
	else:
		var shell := TextureRect.new()
		shell.name = "ResidentMessageShell"
		shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shell.texture = _load_texture(RESIDENT_MESSAGE_SHELL_PATH)
		shell.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shell.stretch_mode = TextureRect.STRETCH_SCALE
		shell.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(shell)

	var title := Label.new()
	title.text = "镇上的留言"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.position = Vector2(86.0, 19.0)
	title.size = Vector2(448.0, 47.0)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("#4c351f"))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(title)

	var card_area := (
		Rect2(49.0, 70.0, 522.0, 190.0)
		if single_message
		else Rect2(49.0, 72.0, 522.0, 338.0)
	)
	var gap := 0.0 if single_message else -24.0
	var card_height := 178.0
	var cards_height := card_height * float(card_count) + gap * float(card_count - 1)
	var first_y := card_area.position.y + (card_area.size.y - cards_height) * 0.5
	for index in card_count:
		var message_value: Variant = messages[index]
		var message := message_value as Dictionary
		var card := Control.new()
		card.name = "ResidentMessageCard%d" % (index + 1)
		var x_offset := (
			2.0
			if single_message
			else (3.0 if index == 0 else -3.0)
		)
		card.position = Vector2(
			card_area.position.x + x_offset,
			first_y + float(index) * (card_height + gap),
		)
		card.size = Vector2(card_area.size.x, card_height)
		var paper_rotation_degrees := (
			0.75
			if single_message
			else (1.30 if index == 0 else -1.10)
		)
		card.z_index = card_count - index
		panel.add_child(card)

		var paper := TextureRect.new()
		paper.name = "Paper"
		paper.position = Vector2.ZERO
		paper.size = card.size
		paper.pivot_offset = paper.size * 0.5
		paper.rotation_degrees = paper_rotation_degrees
		paper.texture = _load_texture(
			RESIDENT_MESSAGE_TOP_CARD_PATH
			if single_message or index == 0
			else RESIDENT_MESSAGE_BOTTOM_CARD_PATH
		)
		paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		paper.stretch_mode = TextureRect.STRETCH_SCALE
		paper.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(paper)

		var text_center := CenterContainer.new()
		text_center.name = "TextCenter"
		text_center.position = Vector2(44.0, 8.0)
		text_center.size = Vector2(428.0, 150.0)
		text_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(text_center)

		var text_stack := VBoxContainer.new()
		text_stack.name = "TextStack"
		text_stack.custom_minimum_size = Vector2(428.0, 0.0)
		text_stack.add_theme_constant_override("separation", 2)
		text_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text_center.add_child(text_stack)

		var resident_name := Label.new()
		resident_name.name = "ResidentName"
		resident_name.text = String(message.get("resident_name", "镇上的居民"))
		resident_name.custom_minimum_size = Vector2(428.0, 27.0)
		resident_name.add_theme_font_size_override(
			"font_size",
			20,
		)
		resident_name.add_theme_color_override("font_color", Color("#55713c"))
		resident_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text_stack.add_child(resident_name)

		var content := Label.new()
		content.name = "Message"
		content.text = String(message.get("content", ""))
		content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		content.custom_minimum_size = Vector2(428.0, 70.0)
		content.add_theme_font_size_override(
			"font_size",
			21,
		)
		content.add_theme_color_override("font_color", Color("#3f3025"))
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text_stack.add_child(content)

	var close_button := Button.new()
	close_button.name = "ResidentMessageCloseButton"
	close_button.text = "收下了"
	close_button.position = Vector2(130.0, 265.0 if single_message else 419.0)
	close_button.size = Vector2(360.0, 68.0)
	close_button.focus_mode = Control.FOCUS_ALL
	close_button.add_theme_font_size_override("font_size", 28)
	close_button.add_theme_color_override("font_color", Color("#fff6df"))
	close_button.add_theme_color_override("font_hover_color", Color.WHITE)
	close_button.add_theme_color_override("font_pressed_color", Color("#eadfc6"))
	var button_texture := _load_texture(RESIDENT_MESSAGE_CLOSE_BUTTON_PATH)
	close_button.add_theme_stylebox_override(
		"normal",
		_resident_message_button_style(button_texture, Color.WHITE),
	)
	close_button.add_theme_stylebox_override(
		"hover",
		_resident_message_button_style(
			button_texture,
			Color(1.07, 1.07, 1.02, 1.0),
		),
	)
	close_button.add_theme_stylebox_override(
		"pressed",
		_resident_message_button_style(
			button_texture,
			Color(0.84, 0.84, 0.80, 1.0),
		),
	)
	close_button.add_theme_stylebox_override(
		"disabled",
		_resident_message_button_style(
			button_texture,
			Color(0.62, 0.62, 0.58, 1.0),
		),
	)
	close_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	close_button.pressed.connect(_close_resident_message_popup)
	panel.add_child(close_button)
	close_button.grab_focus.call_deferred()
	return overlay


func _resident_message_button_style(
	texture: Texture2D,
	modulate: Color,
) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.modulate_color = modulate
	style.texture_margin_left = 30.0
	style.texture_margin_top = 8.0
	style.texture_margin_right = 30.0
	style.texture_margin_bottom = 8.0
	return style


func _confirm_resident_messages_accepted() -> void:
	if _resident_message_pending_receipt.is_empty():
		return
	var receipt := _resident_message_pending_receipt.duplicate(true)
	_resident_message_pending_receipt.clear()
	intent_requested.emit(RESIDENT_MESSAGES_SHOWN_INTENT, {
		"scope": "startup",
		"slotId": String(receipt.get("slotId", "")),
		"messageIds": (
			receipt.get("messageIds", []) as Array
		).duplicate(),
		"revision": _session_revision,
	})


func _close_resident_message_popup(restore_startup_focus := true) -> void:
	if restore_startup_focus:
		_confirm_resident_messages_accepted()
	else:
		_resident_message_pending_receipt.clear()
	if is_instance_valid(_resident_message_layer):
		UiNodeRetirement.retire(_resident_message_layer)
	elif is_instance_valid(_resident_message_overlay):
		UiNodeRetirement.retire(_resident_message_overlay)
	_resident_message_layer = null
	_resident_message_overlay = null
	if restore_startup_focus:
		_restore_startup_focus.call_deferred()


func _startup_action_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	for candidate: Button in [
		_continue_button,
		_new_game_button,
		_load_game_button,
		_connection_button,
		_settings_button,
		_exit_button,
	]:
		if is_instance_valid(candidate):
			buttons.append(candidate)
	return buttons


func _restore_startup_focus() -> void:
	for button: Button in _startup_action_buttons():
		if (
			button.visible
			and not button.disabled
		):
			button.grab_focus()
			return


func _validate_startup_contract(
	session_snapshot: Dictionary,
	save_snapshot: Dictionary,
) -> PackedStringArray:
	var issues := PackedStringArray()
	var session_data := session_snapshot.get("data", {}) as Dictionary
	for key: String in [
		"source",
		"capabilityMode",
		"formalReady",
		"validationMode",
	]:
		if not session_data.has(key):
			issues.append("启动页 session.data 缺少 %s。" % key)
	for action_key: String in ["newGame", "continue"]:
		var action := AiTownUiViewModel.action(session_snapshot, action_key)
		if action.is_empty():
			issues.append("启动页 session.actions 缺少 %s。" % action_key)
		elif String(action.get("intent", "")).is_empty():
			issues.append("启动页 session.actions.%s 缺少 intent。" % action_key)
	var save_data := save_snapshot.get("data", {}) as Dictionary
	for key: String in ["source", "capabilityMode", "formalReady", "canContinue"]:
		if not save_data.has(key):
			issues.append("启动页 save.data 缺少 %s。" % key)
	var save_continue := AiTownUiViewModel.action(save_snapshot, "continue")
	if save_continue.is_empty():
		issues.append("启动页 save.actions 缺少 continue。")
	return issues


func _request_action(action_key: String) -> bool:
	if _session_view_model.is_empty():
		return _block_action(&"", "VIEW_MODEL_UNAVAILABLE")
	var action := AiTownUiViewModel.action(_session_view_model, action_key)
	var intent := StringName(action.get("intent", ""))
	if action_key == "continue":
		if intent != CONTINUE_INTENT:
			return _block_action(intent, "STARTUP_CONTINUE_INTENT_MISMATCH")
		var continue_gate := _continue_gate()
		if not bool(continue_gate.get("enabled", false)):
			var continue_disabled_reason := String(
				continue_gate.get(
					"disabledReason",
					"SESSION_SAVE_NO_PUBLISHED_REVISION",
				)
			)
			return _block_action(
				intent,
				(
					continue_disabled_reason
					if not continue_disabled_reason.is_empty()
					else "ACTION_DISABLED"
				),
			)
		if _host_request_pending_intent != &"":
			return _block_action(intent, "STARTUP_REQUEST_ALREADY_PENDING")
		if intent_requested.get_connections().is_empty():
			return _block_action(intent, "STARTUP_HOST_NOT_CONNECTED")
		_begin_host_request(intent, "正在载入小镇…")
		intent_requested.emit(intent, {
			"scope": "session",
			"actionKey": "continue",
			"revision": _session_revision,
			"routeOrigin": "startup",
		})
		return true
	if action_key != "newGame":
		return _block_action(intent, "STARTUP_ACTION_NOT_AVAILABLE")
	if intent != NEW_GAME_INTENT:
		return _block_action(intent, "STARTUP_NEW_GAME_INTENT_MISMATCH")
	if not AiTownUiViewModel.action_enabled(action):
		var disabled_reason := AiTownUiViewModel.disabled_reason(action)
		return _block_action(
			intent,
			disabled_reason if not disabled_reason.is_empty() else "ACTION_DISABLED",
		)
	var authorization := _new_game_authorization()
	if not bool(authorization.get("allowed", false)):
		return _block_action(
			intent,
			String(authorization.get("reason", "STARTUP_NEW_GAME_NOT_AUTHORIZED")),
		)
	if _host_request_pending_intent != &"":
		return _block_action(intent, "STARTUP_REQUEST_ALREADY_PENDING")
	if intent_requested.get_connections().is_empty():
		return _block_action(intent, "STARTUP_HOST_NOT_CONNECTED")
	var data := _session_view_model.get("data", {}) as Dictionary
	var payload := {
		"scope": "session",
		"actionKey": "newGame",
		"revision": _session_revision,
		"routeOrigin": "startup",
		"source": String(data.get("source", "")),
		"capabilityMode": String(data.get("capabilityMode", "")),
		"validationMode": String(data.get("validationMode", "")),
		"formalReady": bool(data.get("formalReady", false)),
		"internalPlaytest": bool(data.get("internalPlaytest", false)),
		"internalLivePlaytest": bool(data.get("internalLivePlaytest", false)),
	}
	_begin_host_request(intent, "正在准备新游戏…")
	intent_requested.emit(intent, payload.duplicate(true))
	return true


func request_new_game_to_host() -> bool:
	return _request_action("newGame")


func request_continue_to_host() -> bool:
	return _request_action("continue")


func request_load_game_to_host() -> bool:
	var action := AiTownUiViewModel.action(_session_view_model, "loadGame")
	if action.is_empty():
		return _block_action(LOAD_GAME_INTENT, "STARTUP_LOAD_GAME_NOT_AVAILABLE")
	if StringName(action.get("intent", "")) != LOAD_GAME_INTENT:
		return _block_action(LOAD_GAME_INTENT, "STARTUP_LOAD_GAME_INTENT_MISMATCH")
	if not AiTownUiViewModel.action_enabled(action):
		return _block_action(
			LOAD_GAME_INTENT,
			AiTownUiViewModel.disabled_reason(action),
		)
	_request_startup_route(LOAD_GAME_INTENT)
	return true


func request_return_to_host() -> bool:
	if _host_request_pending_intent != &"":
		_show_notice("正在处理，请稍候。")
		return false
	var data := _session_view_model.get("data", {}) as Dictionary
	intent_requested.emit(RETURN_INTENT, {
		"scope": "startup",
		"actionKey": "back",
		"revision": _session_revision,
		"routeOrigin": "startup",
		"source": String(data.get("source", "unavailable")),
		"capabilityMode": String(data.get("capabilityMode", "unavailable")),
		"formalReady": bool(data.get("formalReady", false)),
	})
	_show_notice("正在退出…")
	return true


func request_quit_to_host() -> bool:
	var data := _session_view_model.get("data", {}) as Dictionary
	intent_requested.emit(QUIT_GAME_INTENT, {
		"scope": "startup",
		"actionKey": "quitGame",
		"revision": _session_revision,
		"routeOrigin": "startup",
		"source": String(data.get("source", "runtime")),
		"capabilityMode": String(data.get("capabilityMode", "formal")),
		"formalReady": bool(data.get("formalReady", false)),
	})
	return true


func _request_startup_route(intent: StringName) -> void:
	var data := _session_view_model.get("data", {}) as Dictionary
	intent_requested.emit(intent, {
		"scope": "startup",
		"revision": _session_revision,
		"routeOrigin": "startup",
		"source": String(data.get("source", "formal")),
		"capabilityMode": String(data.get("capabilityMode", "formal")),
		"formalReady": bool(data.get("formalReady", false)),
	})


func _block_action(intent: StringName, reason: String) -> bool:
	action_blocked.emit(intent, reason)
	_show_notice(_blocked_copy(reason))
	return false


func _blocked_copy(reason: String) -> String:
	match reason:
		"AGENT_SAVE_INTERFACE_MISSING", "SESSION_SAVE_NO_PUBLISHED_REVISION":
			return "当前没有可继续的已发布存档。"
		"STARTUP_HOST_NOT_CONNECTED":
			return "启动流程尚未连接，请稍后重试。"
		"STARTUP_REQUEST_ALREADY_PENDING":
			return "正在处理，请稍候。"
		"PROVIDER_HEALTH_INTERFACE_MISSING":
			return "正式 Provider 检查未接入；不会静默降级为开发入口。"
		"VIEW_MODEL_UNAVAILABLE":
			return "启动资料尚未接入，当前操作不可用。"
	return AiTownUiViewModel.player_reason(reason)


func _begin_host_request(intent: StringName, player_message: String) -> void:
	_host_request_pending_intent = intent
	_sync_route_state()
	_show_notice(player_message)


func present_host_result(intent: StringName, result: Dictionary) -> void:
	if (
		_host_request_pending_intent != &""
		and intent != _host_request_pending_intent
	):
		return
	_host_request_pending_intent = &""
	_sync_route_state()
	if bool(result.get("ok", false)):
		_show_notice("正在进入…")
		return
	_show_notice(_host_failure_copy(result))


func _host_failure_copy(result: Dictionary) -> String:
	var explicit_message := String(
		result.get("playerMessage", "")
	).strip_edges()
	if not explicit_message.is_empty():
		return explicit_message
	var error_code := String(
		result.get("errorCode", "STARTUP_ROUTE_FAILED")
	).strip_edges()
	match error_code:
		"STARTUP_SAVE_SLOT_ID_INVALID":
			return "没有找到可用的存档位置，请打开“加载游戏”检查。"
		"STARTUP_SAVE_CATALOG_CONTRACT_INVALID", \
		"STARTUP_SAVE_CATALOG_UNAVAILABLE":
			return "暂时无法读取小镇存档，请稍后重试。"
		"FORMAL_SLOT_ARCHIVE_RECOVERY_CONTRACT_MISSING", \
		"FORMAL_SLOT_ARCHIVE_RECOVERY_METADATA_INVALID", \
		"FORMAL_SLOT_ARCHIVE_RECOVERY_FAILED":
			return "上次存档处理尚未完成，请稍后重试。"
		"GAME_FLOW_WORLD_INTRO_ROUTE_FAILED":
			return "小镇介绍页暂时无法打开，请重试。"
		"STARTUP_NEW_GAME_NOT_AUTHORIZED", "FORMAL_ENTRY_NOT_READY":
			return "新游戏尚未准备好，请稍后重试。"
	var player_reason := AiTownUiViewModel.player_reason(error_code).strip_edges()
	if player_reason.is_empty() or player_reason == "当前操作暂不可用":
		return "暂时无法开始新游戏，请重试。"
	return player_reason


func _new_game_authorization() -> Dictionary:
	if _session_view_model.is_empty():
		return {"allowed": false, "reason": "VIEW_MODEL_UNAVAILABLE"}
	var data := _session_view_model.get("data", {}) as Dictionary
	var source := String(data.get("source", ""))
	var capability_mode := String(data.get("capabilityMode", ""))
	var validation_mode := String(data.get("validationMode", ""))
	var formal_ready := bool(data.get("formalReady", false))
	var internal_playtest := bool(data.get("internalPlaytest", false))
	var internal_live_playtest := bool(data.get("internalLivePlaytest", false))
	var formal_allowed := (
		formal_ready
		and source == "formal"
		and capability_mode == "formal"
	)
	var development_allowed := (
		not formal_ready
		and internal_playtest
		and validation_mode == "development"
		and capability_mode == "development"
		and source == "placeholder"
	)
	var live_playtest_allowed := (
		not formal_ready
		and internal_live_playtest
		and validation_mode in ["development", "formal"]
		and capability_mode == "formal"
		and source == "runtime"
	)
	if formal_allowed or development_allowed or live_playtest_allowed:
		return {
			"allowed": true,
			"mode": (
				"formal"
				if formal_allowed
				else "live_playtest" if live_playtest_allowed else "development"
			),
			"reason": "",
		}
	if source == "formal" and not formal_ready:
		return {"allowed": false, "reason": "FORMAL_ENTRY_NOT_READY"}
	return {"allowed": false, "reason": "DEVELOPMENT_MODE_NOT_EXPLICIT"}


func _sync_route_state() -> void:
	var authorization := _new_game_authorization()
	var new_game_action := AiTownUiViewModel.action(
		_session_view_model,
		"newGame",
	)
	var new_game_enabled := (
		AiTownUiViewModel.action_enabled(new_game_action)
		and bool(authorization.get("allowed", false))
		and _host_request_pending_intent == &""
	)
	if _new_game_button != null:
		_new_game_button.disabled = not new_game_enabled
		_new_game_button.tooltip_text = (
			"开发内测入口 · formalReady=false"
			if String(authorization.get("mode", "")) == "development"
			else (
				"开始新游戏"
				if new_game_enabled
				else _blocked_copy(String(authorization.get("reason", "ACTION_DISABLED")))
			)
		)
	if _continue_button != null:
		var continue_gate := _continue_gate()
		var continue_enabled := (
			bool(continue_gate.get("enabled", false))
			and _host_request_pending_intent == &""
		)
		var continue_disabled_reason := String(
			continue_gate.get("disabledReason", "")
		)
		_continue_button.disabled = not continue_enabled
		_continue_button.tooltip_text = (
			"继续游戏"
			if continue_enabled
			else _blocked_copy(
				continue_disabled_reason
				if not continue_disabled_reason.is_empty()
				else "ACTION_DISABLED"
			)
		)
	if _load_game_button != null:
		var load_action := AiTownUiViewModel.action(
			_session_view_model,
			"loadGame",
		)
		var load_enabled := (
			AiTownUiViewModel.action_enabled(load_action)
			and _host_request_pending_intent == &""
		)
		_load_game_button.disabled = not load_enabled
		_load_game_button.tooltip_text = (
			"加载游戏"
			if load_enabled
			else _blocked_copy(
				AiTownUiViewModel.disabled_reason(load_action)
			)
		)
	var data := _session_view_model.get("data", {}) as Dictionary
	var mode := String(authorization.get("mode", ""))
	if mode in ["development", "live_playtest"]:
		_route_status_text = ""
	elif bool(data.get("formalReady", false)):
		_route_status_text = _provider_status_copy(
			String(data.get("providerStatus", "available"))
		)
	elif String(data.get("source", "")) == "formal":
		_route_status_text = _provider_status_copy(
			String(data.get("providerStatus", "configuration_required"))
		)
	else:
		_route_status_text = "启动资料暂不可用"
	if _save_summary_label != null:
		_cancel_notice_tween()
		var continue_error_message := _continue_public_error_message()
		_save_summary_label.text = (
			continue_error_message
			if not continue_error_message.is_empty()
			else _compact_save_summary(data)
		)
		_save_summary_label.tooltip_text = _save_summary_label.text
		_save_summary_label.modulate.a = 1.0
	if _connection_button != null:
		_connection_button.tooltip_text = (
			"模型设置"
			if _route_status_text.is_empty()
			else _route_status_text
		)
	_sync_loading_visuals()


func _compact_save_summary(session_data: Dictionary) -> String:
	var load_summary := session_data.get("loadSummary", {}) as Dictionary
	var compact := String(load_summary.get("compactTownSummary", "")).strip_edges()
	if not compact.is_empty():
		return compact
	return "暂无可继续的小镇"


func _provider_status_copy(status: String) -> String:
	match status:
		"available", "healthy":
			return ""
		"checking", "loading":
			return "正在检查连接"
		"auth_failed", "invalid_authentication":
			return "连接已失效"
		"rate_limited":
			return "连接繁忙"
		"timeout", "network_failed", "unavailable":
			return "暂时无法连接"
		"development_placeholder":
			return "需要模型设置"
	return "需要模型设置"


func _continue_public_error_message() -> String:
	for snapshot: Dictionary in [
		_session_view_model,
		_save_view_model,
	]:
		var operation := snapshot.get("operation", {}) as Dictionary
		if String(operation.get("status", "")) not in ["rejected", "error"]:
			continue
		var operation_intent := String(operation.get("intent", ""))
		var operation_action_key := String(
			operation.get("actionKey", "")
		)
		if (
			operation_intent != String(CONTINUE_INTENT)
			and operation_action_key != "continue"
		):
			continue
		var error_value: Variant = snapshot.get("error")
		if not error_value is Dictionary:
			continue
		var public_message := (
			AiTownUiViewModel.public_error_message(snapshot)
		)
		if not public_message.is_empty():
			return public_message
		return "继续游戏暂未完成，请重试。"
	return ""


func _cancel_notice_tween() -> void:
	if _notice_tween != null and _notice_tween.is_valid():
		_notice_tween.kill()
	_notice_tween = null


func _sync_loading_visuals() -> void:
	var operation := _session_view_model.get("operation", {}) as Dictionary
	var loading := String(operation.get("status", "idle")) == "loading"
	var action_key := String(operation.get("actionKey", ""))
	var operation_intent := String(operation.get("intent", ""))
	_set_button_loading(
		_continue_button,
		&"StartupPrimaryButton",
		&"StartupPrimaryLoadingButton",
		loading and (
			action_key == "continue"
			or operation_intent == String(CONTINUE_INTENT)
		) or _host_request_pending_intent == CONTINUE_INTENT,
	)
	_set_button_loading(
		_new_game_button,
		&"StartupPrimaryButton",
		&"StartupPrimaryLoadingButton",
		loading and (
			action_key == "newGame"
			or operation_intent == String(NEW_GAME_INTENT)
		) or _host_request_pending_intent == NEW_GAME_INTENT,
	)
	_set_button_loading(
		_load_game_button,
		&"StartupPrimaryButton",
		&"StartupPrimaryLoadingButton",
		loading and (
			action_key == "loadGame"
			or operation_intent == String(LOAD_GAME_INTENT)
		),
	)


func _set_button_loading(
	button: Button,
	normal_variation: StringName,
	loading_variation: StringName,
	loading: bool,
) -> void:
	if button == null:
		return
	button.theme_type_variation = (
		loading_variation if loading else normal_variation
	)


func get_route_contract_snapshot() -> Dictionary:
	var authorization := _new_game_authorization()
	var new_game_action := AiTownUiViewModel.action(
		_session_view_model,
		"newGame",
	)
	var continue_gate := _continue_gate()
	return {
		"contractId": "ui.startup.game-flow-intents.rev2",
		"host": "GameFlowHost",
		"signal": "intent_requested(intent, payload)",
		"intents": {
			"newGame": String(NEW_GAME_INTENT),
			"back": String(RETURN_INTENT),
			"continue": String(CONTINUE_INTENT),
			"loadGame": String(LOAD_GAME_INTENT),
			"connectionSettings": String(CONNECTION_SETTINGS_INTENT),
			"gameSettings": String(GAME_SETTINGS_INTENT),
			"quitGame": String(QUIT_GAME_INTENT),
		},
		"newGameEnabled": (
			AiTownUiViewModel.action_enabled(new_game_action)
			and bool(authorization.get("allowed", false))
		),
		"newGameMode": String(authorization.get("mode", "")),
		"continueEnabled": bool(continue_gate.get("enabled", false)),
		"continueDisabledReason": String(
			continue_gate.get("disabledReason", "")
		),
		"hasPublishedSaveSummary": bool(
			continue_gate.get("hasPublishedSaveSummary", false)
		),
		"formalReady": bool(
			(_session_view_model.get("data", {}) as Dictionary).get(
				"formalReady",
				false,
			)
		),
		"directSceneNavigation": false,
		"silentFallback": false,
		"imageButtonThemeRevision": STARTUP_BUTTON_THEME.REVISION,
		"componentAssemblyPending": false,
		"componentAssemblyApproved": true,
		"menuShellPath": STARTUP_MENU_SHELL_PATH,
		"summaryPlaquePath": STARTUP_SUMMARY_PLAQUE_PATH,
		"statusText": _route_status_text,
		"continueErrorText": _continue_public_error_message(),
		"hostRequestPending": _host_request_pending_intent != &"",
		"hostRequestIntent": String(_host_request_pending_intent),
		"noticeText": (
			_save_summary_label.text if _save_summary_label != null else ""
		),
	}


func _continue_gate() -> Dictionary:
	var session_action := AiTownUiViewModel.action(
		_session_view_model,
		"continue",
	)
	var save_action := AiTownUiViewModel.action(
		_save_view_model,
		"continue",
	)
	var save_data := _save_view_model.get("data", {}) as Dictionary
	var slots := save_data.get("slots", []) as Array
	var selected_save_id := String(
		save_data.get("selectedSaveId", "")
	).strip_edges()
	var has_published_summary := false
	for value: Variant in slots:
		if not value is Dictionary:
			continue
		var summary := value as Dictionary
		var slot_id := String(summary.get("slotId", "")).strip_edges()
		var session_id := String(summary.get("sessionId", "")).strip_edges()
		var revision := int(summary.get("saveRevision", 0))
		var summary_id := "%s:%d" % [slot_id, revision]
		if (
			not slot_id.is_empty()
			and not session_id.is_empty()
			and revision > 0
			and summary_id == selected_save_id
		):
			has_published_summary = true
			break
	var session_enabled := AiTownUiViewModel.action_enabled(session_action)
	var save_enabled := AiTownUiViewModel.action_enabled(save_action)
	var can_continue := bool(save_data.get("canContinue", false))
	var enabled := (
		session_enabled
		and save_enabled
		and can_continue
		and has_published_summary
	)
	var disabled_reason := ""
	if not enabled:
		disabled_reason = AiTownUiViewModel.disabled_reason(session_action)
		if disabled_reason.is_empty():
			disabled_reason = AiTownUiViewModel.disabled_reason(save_action)
		if disabled_reason.is_empty():
			disabled_reason = "SESSION_SAVE_NO_PUBLISHED_REVISION"
	return {
		"enabled": enabled,
		"disabledReason": disabled_reason,
		"hasPublishedSaveSummary": has_published_summary,
	}


func get_weather_name() -> String:
	return WEATHER_NAMES[_weather_index]


func get_day_phase_name() -> String:
	var phase := int(floor(fmod(_elapsed / DAY_CYCLE_SECONDS, 1.0) * 4.0)) % 4
	return DAY_PHASE_NAMES[phase]


func force_weather(weather_index: int) -> void:
	_weather_index = posmod(weather_index, WEATHER_NAMES.size())
	_weather_elapsed = 0.0
	_lightning_wait = _rng.randf_range(1.4, 2.6)
	_lightning_flashes_remaining = _rng.randi_range(1, 2) if _weather_index == 3 else 0
	_lightning_flash = 0.0
	_set_weather_blend_immediate()
