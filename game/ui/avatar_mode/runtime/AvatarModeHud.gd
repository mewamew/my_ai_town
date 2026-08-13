extends Control

signal intent_requested(intent: String, payload: Dictionary)
signal movement_input_changed(value: Vector2)

const UI_SIGNALS := preload(
	"res://ui/common/AiTownUiSignals.gd"
)
const UI_VIEW_MODEL := preload("res://ui/common/AiTownUiViewModel.gd")
const UI_NODE_RETIREMENT := preload("res://ui/common/AiTownUiNodeRetirement.gd")
const MOBILE_UI_PROFILE := preload("res://ui/mobile/MobileUiProfile.gd")
const VIRTUAL_JOYSTICK := preload("res://ui/mobile/VirtualJoystick.gd")
const REQUIRED_ADAPTER_SCOPES := ["avatar", "conversation"]
const TIME_HUD_SCOPE := "town_hud"

const FONT_PATH := (
	"res://assets/fonts/"
	+ "zheng_ge_dian_hei_16/ZhengGeDianHei-16.ttf"
)
const BASIC_FRAME_PATH := (
	"res://assets/ui/avatar_mode/runtime/basic_frames/"
	+ "avatar_mode_basic_frame_9slice.png"
)
const TARGET_SWITCHER_PATH := (
	"res://assets/ui/avatar_mode/runtime/composites/"
	+ "avatar_mode_target_switcher.png"
)
const CONTROL_ATLAS_PATH := (
	"res://assets/ui/avatar_mode/runtime/control_parts/"
	+ "avatar_mode_control_parts_runtime_atlas.png"
)
const ICON_ATLAS_PATH := (
	"res://assets/ui/avatar_mode/runtime/icons/"
	+ "avatar_mode_context_icons_runtime_atlas.png"
)
const ATTACK_BUTTON_NORMAL_PATH := (
	"res://assets/ui/avatar_mode/runtime/attack_button_v1/"
	+ "avatar_rising_uppercut_button_normal.png"
)
const ATTACK_BUTTON_HOVER_PATH := (
	"res://assets/ui/avatar_mode/runtime/attack_button_v1/"
	+ "avatar_rising_uppercut_button_hover.png"
)
const ATTACK_BUTTON_PRESSED_PATH := (
	"res://assets/ui/avatar_mode/runtime/attack_button_v1/"
	+ "avatar_rising_uppercut_button_pressed.png"
)
const ATTACK_BUTTON_DISABLED_PATH := (
	"res://assets/ui/avatar_mode/runtime/attack_button_v1/"
	+ "avatar_rising_uppercut_button_disabled.png"
)
const AVATAR_ATTACK_SKILLS: Array[Dictionary] = [
	{
		"actionId": "skill_attack_1",
		"attackKind": "unarmed",
		"label": "升空重拳",
		"key": "1",
		"assetFolder": "",
		"assetStem": "avatar_rising_uppercut_button",
	},
	{
		"actionId": "skill_attack_2",
		"attackKind": "avatar_susanoo_strike",
		"label": "须佐重击",
		"key": "2",
		"assetFolder": "avatar_susanoo_strike",
		"assetStem": "avatar_susanoo_strike_button",
	},
	{
		"actionId": "skill_attack_3",
		"attackKind": "avatar_rasengan",
		"label": "螺旋丸",
		"key": "3",
		"assetFolder": "avatar_rasengan",
		"assetStem": "avatar_rasengan_button",
	},
	{
		"actionId": "skill_attack_4",
		"attackKind": "avatar_kamehameha",
		"label": "龟波气功",
		"key": "4",
		"assetFolder": "avatar_kamehameha",
		"assetStem": "avatar_kamehameha_button",
	},
]
const NEARBY_TALK_PROMPT_SHELL_PATH := (
	"res://assets/ui/avatar_mode/runtime/minimal_v2/"
	+ "avatar_nearby_talk_prompt_shell_v2.png"
)
const SKILLBAR_SHELL_PATH := (
	"res://assets/ui/avatar_mode/runtime/minimal_v2/"
	+ "avatar_skillbar_shell_v2.png"
)
const SKILLBAR_LOGICAL_SIZE := Vector2(310, 86)
const SKILL_SLOT_CENTERS := [47.0, 119.0, 191.0, 263.0]
const SKILL_ART_SIZE := Vector2(58, 58)
const SKILL_BUTTON_SIZE := Vector2(68, 68)
const SKILL_KEY_SIZE := Vector2(20, 20)
const MOBILE_JOYSTICK_BASE_PATH := "res://assets/ui/avatar_mode/runtime/mobile_joystick/mobile_joystick_base_v2.png"
const MOBILE_JOYSTICK_KNOB_PATH := "res://assets/ui/avatar_mode/runtime/mobile_joystick/mobile_joystick_knob_v2.png"
const MOBILE_TALK_ACTION_PATH := "res://assets/ui/avatar_mode/runtime/mobile_context_actions/mobile_talk_action_v1.png"
const MOBILE_PET_CAT_ACTION_PATH := "res://assets/ui/avatar_mode/runtime/mobile_context_actions/mobile_pet_cat_action_v1.png"
const TOUCH_JOYSTICK_MIN_SIZE := 276.0
const TOUCH_JOYSTICK_MAX_SIZE := 336.0
const TOUCH_SKILLBAR_SIZE := Vector2(496.0, 138.0)
const MOBILE_CONTEXT_ACTION_SIZE := Vector2(144.0, 144.0)
const MOBILE_PET_ACTION_SIZE := Vector2(224.0, 224.0)
const MOBILE_CONTEXT_ACTION_GAP := 16.0
const OBSERVER_SHELL_TEXTURE := preload(
	"res://assets/ui/town/hud/runtime/composite/"
	+ "observer_hud_v5_time_panel_detached_v6_rgba.png"
)
const TIME_CONTROL_PANEL_TEXTURES := {
	"time_pause": preload(
		"res://assets/ui/town/hud/runtime/time_controls/"
		+ "time_panel_time_pause_selected_v10.png"
	),
	"time_speed_1": preload(
		"res://assets/ui/town/hud/runtime/time_controls/"
		+ "time_panel_time_speed_1_selected_v10.png"
	),
	"time_speed_2": preload(
		"res://assets/ui/town/hud/runtime/time_controls/"
		+ "time_panel_time_speed_2_selected_v10.png"
	),
	"time_speed_3": preload(
		"res://assets/ui/town/hud/runtime/time_controls/"
		+ "time_panel_time_speed_3_selected_v10.png"
	),
}
const HUD_REFERENCE_SIZE := Vector2(1672.0, 941.0)
const HUD_REFERENCE_ASPECT := HUD_REFERENCE_SIZE.x / HUD_REFERENCE_SIZE.y
const TIME_STATUS_SOURCE_RECT := Rect2(575.0, 20.0, 540.0, 88.0)
const TIME_STATUS_TEXT_RECT := Rect2(35.0, 14.0, 382.0, 60.0)
const WEATHER_CONTROL_BUTTON_RECT := Rect2(420.0, 8.0, 94.0, 76.0)
const TIME_CONTROL_REFERENCE_RECT := Rect2(1552.0, 340.0, 120.0, 401.0)
const TIME_CONTROL_SOURCE_RECT := Rect2(37.0, 0.0, 120.0, 401.0)
const TIME_CONTROL_BUTTON_RECTS := {
	"time_pause": Rect2(16.0, 52.0, 68.0, 68.0),
	"time_speed_1": Rect2(16.0, 129.0, 68.0, 68.0),
	"time_speed_2": Rect2(16.0, 205.0, 68.0, 68.0),
	"time_speed_3": Rect2(16.0, 281.0, 68.0, 68.0),
}
const TIME_CONTROL_BACKGROUND_MASK_SHADER := """
shader_type canvas_item;

void fragment() {
	vec4 sampled = texture(TEXTURE, UV);
	float brightest = max(sampled.r, max(sampled.g, sampled.b));
	float darkest = min(sampled.r, min(sampled.g, sampled.b));
	float chroma = brightest - darkest;
	float neutral_dark_background =
		(1.0 - step(0.18, brightest)) * (1.0 - step(0.035, chroma));
	COLOR = vec4(sampled.rgb, sampled.a * (1.0 - neutral_dark_background));
}
"""

const INK := Color("#3f2818")
const MUTED := Color("#76583d")
const PAPER_LIGHT := Color("#fff8e6")
const DISABLED_INK := Color("#826f5b")
const ERROR_INK := Color("#8d2d22")
const SUCCESS_INK := Color("#496b28")
const TINT_PRIMARY := Color("#ffd7c5")
const TINT_DISABLED := Color(0.72, 0.72, 0.72, 0.88)

const CONTROL_CELL := Vector2i(256, 216)
const ICON_CELL := Vector2i(256, 256)
const LIST_30_INTENTS := [
	"avatar.invite",
	"avatar.reveal_secret",
	"avatar.create_misunderstanding",
	"avatar.trigger_public_event",
]
const INTENTIONALLY_UNSUPPORTED_PRODUCT_INTENTS := [
	"avatar.enter_place",
	"avatar.inspect_object",
]

var _view_models: Dictionary = {}
var _fixture: Dictionary = {
	"inputMode": "keyboard_mouse",
	"safeInsets": {"top": 0, "right": 0, "bottom": 0, "left": 0},
	"copyScale": 1.0,
}
var _theme: Theme
var _font: FontVariation
var _basic_frame: Texture2D
var _target_switcher: Texture2D
var _control_parts: Array[Texture2D] = []
var _icons: Array[Texture2D] = []
var _attack_button_normal: Texture2D
var _attack_button_hover: Texture2D
var _attack_button_pressed: Texture2D
var _attack_button_disabled: Texture2D
var _attack_skill_textures: Dictionary = {}
var _nearby_talk_prompt_shell: Texture2D
var _skillbar_shell: Texture2D
var _mobile_joystick_base: Texture2D
var _mobile_joystick_knob: Texture2D
var _mobile_talk_action: Texture2D
var _mobile_pet_cat_action: Texture2D
var _component_nodes: Dictionary = {}
var _text_nodes: Dictionary = {}
var _intent_nodes: Dictionary = {}
var _action_nodes: Dictionary = {}
var _focus_buttons: Array[Button] = []
var _portrait_nodes: Dictionary = {}
var _portrait_fallback_reasons: Dictionary = {}
var _adapter: Node
var _adapter_head_anchor_call := Callable()
var _using_placeholder := true
var _binding_batch := false
var _revision_by_scope: Dictionary = {}
var _last_confirmed_data_by_scope: Dictionary = {}
var _adapter_contract_gaps: Dictionary = {}
var _last_dispatch_result: Dictionary = {}
var _configured := false
var _should_unmount := false
var _movement_hint_dismissed := false
var _feedback_active_key := ""
var _feedback_hidden_key := ""
var _feedback_expire_at_msec := 0
const FEEDBACK_PAGE_DURATION_SECONDS := 2.0
const FEEDBACK_PAGE_MAX_UNITS := 30.0
const FEEDBACK_LINE_MAX_UNITS := 15.0
var _feedback_pages: Array[String] = []
var _feedback_page_index := 0
var _feedback_page_elapsed := 0.0
var _feedback_full_text := ""
var _time_control_panel_face: TextureRect
var _touch_joystick: AiTownVirtualJoystick
var _touch_movement := Vector2.ZERO
var _rebuild_after_joystick_release := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_fit_root_to_viewport()
	get_viewport().size_changed.connect(_fit_root_to_viewport)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_runtime_theme()
	_load_runtime_assets()
	resized.connect(_layout_runtime)
	_request_rebuild_preserving_joystick()


func _fit_root_to_viewport() -> void:
	# The formal HUD is mounted directly below TownRuntime (Node2D). Anchors
	# alone therefore resolve to a zero-sized rectangle.
	position = Vector2.ZERO
	var parent_control := get_parent() as Control
	size = (
		parent_control.size
		if is_instance_valid(parent_control)
		and parent_control.size.x > 0.0
		and parent_control.size.y > 0.0
		else get_viewport_rect().size
	)
	_fixture["inputMode"] = MOBILE_UI_PROFILE.input_mode(size)
	_fixture["safeInsets"] = MOBILE_UI_PROFILE.safe_insets(size, get_window())
	_fixture["copyScale"] = 1.15 if MOBILE_UI_PROFILE.is_phone_landscape(size) else 1.0


func _exit_tree() -> void:
	_set_touch_movement(Vector2.ZERO)
	_disconnect_adapter()


func set_mobile_fixture(viewport_size: Vector2) -> void:
	if viewport_size.x > 0.0 and viewport_size.y > 0.0:
		size = viewport_size
	_fixture["inputMode"] = MOBILE_UI_PROFILE.input_mode(viewport_size)
	_fixture["safeInsets"] = MOBILE_UI_PROFILE.safe_insets(viewport_size, get_window())
	_fixture["copyScale"] = 1.15 if MOBILE_UI_PROFILE.is_phone_landscape(viewport_size) else 1.0
	if is_node_ready():
		_request_rebuild_preserving_joystick()


func _input(event: InputEvent) -> void:
	if not _can_accept_interaction_input():
		return
	var input_mode := str(_fixture.get("inputMode", "keyboard_mouse"))
	var action_id := ""
	if event is InputEventKey and input_mode == "keyboard_mouse":
		var key_event := event as InputEventKey
		if (
			not key_event.pressed
			or key_event.echo
			or key_event.alt_pressed
			or key_event.ctrl_pressed
			or key_event.meta_pressed
		):
			return
		match key_event.keycode:
			KEY_E:
				action_id = "resident_prompt"
			KEY_F, KEY_1:
				action_id = "skill_attack_1"
			KEY_2:
				action_id = "skill_attack_2"
			KEY_3:
				action_id = "skill_attack_3"
			KEY_4:
				action_id = "skill_attack_4"
			KEY_R:
				action_id = "retry"
	elif event is InputEventJoypadButton and input_mode == "gamepad":
		var button_event := event as InputEventJoypadButton
		if not button_event.pressed:
			return
		match button_event.button_index:
			JOY_BUTTON_A:
				if _activate_focused_button():
					get_viewport().set_input_as_handled()
				return
			JOY_BUTTON_B:
				action_id = "exitMode"
	if not action_id.is_empty() and debug_activate_action(action_id):
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_sync_live_resident_prompt_anchor()
	_update_operation_feedback_page(delta)
	if (
		_feedback_expire_at_msec <= 0
		or Time.get_ticks_msec() < _feedback_expire_at_msec
	):
		return
	_feedback_hidden_key = _feedback_active_key
	_feedback_expire_at_msec = 0
	_request_rebuild_preserving_joystick()


func configure(view_models: Dictionary, fixture: Dictionary) -> void:
	_disconnect_adapter()
	_adapter = null
	_adapter_head_anchor_call = Callable()
	_view_models = view_models.duplicate(true)
	_fixture = fixture.duplicate(true)
	_using_placeholder = true
	_revision_by_scope.clear()
	_last_confirmed_data_by_scope.clear()
	for scope: String in REQUIRED_ADAPTER_SCOPES:
		var view_model_value: Variant = _view_models.get(scope)
		if not view_model_value is Dictionary:
			continue
		var view_model := view_model_value as Dictionary
		_revision_by_scope[scope] = int(view_model.get("revision", -1))
		var data_value: Variant = view_model.get("data", {})
		if data_value is Dictionary and not (data_value as Dictionary).is_empty():
			_last_confirmed_data_by_scope[scope] = (
				data_value as Dictionary
			).duplicate(true)
	var town_hud_view_model := _view_models.get(TIME_HUD_SCOPE, {}) as Dictionary
	if not town_hud_view_model.is_empty():
		var town_data_value: Variant = town_hud_view_model.get("data", {})
		if (
			town_data_value is Dictionary
			and not (town_data_value as Dictionary).is_empty()
		):
			_last_confirmed_data_by_scope[TIME_HUD_SCOPE] = (
				town_data_value as Dictionary
			).duplicate(true)
		_revision_by_scope[TIME_HUD_SCOPE] = int(
			town_hud_view_model.get("revision", -1)
		)
	_configured = true
	if is_node_ready():
		_request_rebuild_preserving_joystick()


func bind_town_ui_adapter(adapter: Node) -> PackedStringArray:
	var issues := PackedStringArray()
	if adapter == null:
		issues.append("AvatarModeHud adapter 不能为空")
		return issues
	for method_name: String in ["get_view_model", "dispatch"]:
		if not adapter.has_method(method_name):
			issues.append("AvatarModeHud adapter 缺少 %s" % method_name)
	if not adapter.has_signal("view_model_changed"):
		issues.append("AvatarModeHud adapter 缺少 view_model_changed")
	if not issues.is_empty():
		return issues
	_disconnect_adapter()
	_adapter = adapter
	_adapter_head_anchor_call = (
		Callable(adapter, "get_town_hud_resident_head_anchor")
		if adapter.has_method("get_town_hud_resident_head_anchor")
		else Callable()
	)
	_using_placeholder = false
	_configured = true
	_view_models.clear()
	_revision_by_scope.clear()
	_last_confirmed_data_by_scope.clear()
	_adapter_contract_gaps.clear()
	_last_dispatch_result.clear()
	var callback := Callable(self, "_on_adapter_view_model_changed")
	if not _adapter.is_connected("view_model_changed", callback):
		_adapter.connect("view_model_changed", callback)
	_binding_batch = true
	for scope: String in REQUIRED_ADAPTER_SCOPES:
		var incoming: Variant = _adapter.call("get_view_model", scope)
		if not incoming is Dictionary:
			issues.append(
				"TownUiAdapter.%s 必须返回完整 Dictionary ViewModel" % scope
			)
			continue
		var scope_issues := apply_view_model(incoming as Dictionary)
		issues.append_array(scope_issues)
	var town_hud_incoming: Variant = _adapter.call(
		"get_view_model",
		TIME_HUD_SCOPE,
	)
	if town_hud_incoming is Dictionary:
		# 时间条是化身 HUD 的附加投影；即使旧适配器暂时没有 town_hud，
		# 也不能因此阻断 avatar / conversation 两个必需作用域的挂载。
		_apply_time_hud_view_model(town_hud_incoming as Dictionary)
	_binding_batch = false
	if is_node_ready():
		_request_rebuild_preserving_joystick()
	return issues


func unbind_town_ui_adapter() -> void:
	_disconnect_adapter()
	_adapter = null
	_adapter_head_anchor_call = Callable()
	_using_placeholder = false
	_configured = false
	_view_models.clear()
	_revision_by_scope.clear()
	_last_confirmed_data_by_scope.clear()
	_adapter_contract_gaps.clear()
	_last_dispatch_result.clear()
	if is_node_ready():
		_request_rebuild_preserving_joystick()


func apply_view_model(view_model: Dictionary) -> PackedStringArray:
	var issues: PackedStringArray = UI_VIEW_MODEL.validate(view_model, "AvatarModeHud")
	var scope: String = str(view_model.get("scope", ""))
	if scope not in REQUIRED_ADAPTER_SCOPES:
		issues.append("AvatarModeHud 拒绝未知 scope：%s" % scope)
	if not issues.is_empty():
		return issues
	var incoming_revision: int = int(view_model.get("revision", -1))
	var current_revision: int = int(_revision_by_scope.get(scope, -1))
	if incoming_revision < current_revision:
		return PackedStringArray([
			"AvatarModeHud 丢弃过期 %s revision=%d，当前=%d"
			% [scope, incoming_revision, current_revision]
		])
	var previous_render_projection: Dictionary = _render_projection(
		scope,
		_view_models.get(scope, {}) as Dictionary,
	)
	var incoming_data: Dictionary = {}
	var incoming_data_raw: Variant = view_model.get("data", {})
	if incoming_data_raw is Dictionary:
		incoming_data = (incoming_data_raw as Dictionary).duplicate(true)
	var last_confirmed: Dictionary = {}
	var last_confirmed_raw: Variant = _last_confirmed_data_by_scope.get(scope, {})
	if last_confirmed_raw is Dictionary:
		last_confirmed = (last_confirmed_raw as Dictionary).duplicate(true)
	var operation_status: String = str(
		(view_model.get("operation", {}) as Dictionary).get("status", "")
	)
	var render_data: Dictionary = {}
	if not incoming_data.is_empty():
		render_data = incoming_data.duplicate(true)
	if operation_status == "rejected" and not last_confirmed.is_empty():
		render_data = last_confirmed
	elif incoming_data.is_empty() and not last_confirmed.is_empty():
		render_data = last_confirmed
	elif not incoming_data.is_empty():
		_last_confirmed_data_by_scope[scope] = incoming_data.duplicate(true)
	var render_snapshot := view_model.duplicate(true)
	render_snapshot["data"] = render_data
	_view_models[scope] = render_snapshot
	_revision_by_scope[scope] = incoming_revision
	_update_adapter_contract_gaps(scope, view_model)
	var render_changed := (
		previous_render_projection
		!= _render_projection(scope, render_snapshot)
	)
	if is_node_ready() and not _binding_batch and render_changed:
		if (
			scope == "conversation"
			and bool(
				_render_projection(scope, render_snapshot).get(
					"open",
					false,
				)
			)
		):
			# The chat page covers this HUD. Hiding the existing tree is enough;
			# rebuilding it just to retire every child delays the chat's first frame.
			visible = false
			mouse_filter = Control.MOUSE_FILTER_IGNORE
		else:
			_request_rebuild_preserving_joystick()
	return issues


func _apply_time_hud_view_model(view_model: Dictionary) -> PackedStringArray:
	var issues: PackedStringArray = UI_VIEW_MODEL.validate(view_model, "AvatarModeHud.town_hud")
	if str(view_model.get("scope", "")) != TIME_HUD_SCOPE:
		issues.append("AvatarModeHud.town_hud scope 无效")
	if not issues.is_empty():
		return issues
	var incoming_revision: int = int(view_model.get("revision", -1))
	var current_revision: int = int(_revision_by_scope.get(TIME_HUD_SCOPE, -1))
	if incoming_revision < current_revision:
		return PackedStringArray([
			"AvatarModeHud 丢弃过期 town_hud revision=%d，当前=%d"
			% [incoming_revision, current_revision]
		])
	var render_snapshot: Dictionary = view_model.duplicate(true)
	var incoming_data_value: Variant = view_model.get("data", {})
	var incoming_data: Dictionary = {}
	if incoming_data_value is Dictionary:
		incoming_data = incoming_data_value as Dictionary
	var last_confirmed_raw: Variant = _last_confirmed_data_by_scope.get(
		TIME_HUD_SCOPE,
		{},
	)
	var last_confirmed: Dictionary = {}
	if last_confirmed_raw is Dictionary:
		last_confirmed = (last_confirmed_raw as Dictionary).duplicate(true)
	var render_data: Dictionary = {}
	if not incoming_data.is_empty():
		render_data = incoming_data.duplicate(true)
	var operation_status: String = str(
		(view_model.get("operation", {}) as Dictionary).get("status", "")
	)
	if operation_status in ["rejected", "error"] and not last_confirmed.is_empty():
		render_data = last_confirmed.duplicate(true)
	elif render_data.is_empty() and not last_confirmed.is_empty():
		render_data = last_confirmed.duplicate(true)
	else:
		var incoming_time_weather_value: Variant = render_data.get(
			"timeWeather",
			{},
		)
		var incoming_time_weather: Dictionary = {}
		var has_time_weather: bool = incoming_time_weather_value is Dictionary
		if incoming_time_weather_value is Dictionary:
			incoming_time_weather = incoming_time_weather_value as Dictionary
		var has_time_weather_data: bool = has_time_weather and not (
			incoming_time_weather as Dictionary
		).is_empty()
		var last_time_weather_value: Variant = last_confirmed.get("timeWeather", {})
		var last_time_weather: Dictionary = {}
		if last_time_weather_value is Dictionary:
			last_time_weather = last_time_weather_value as Dictionary
		var last_has_time_weather_data: bool = not last_time_weather.is_empty()
		if (
			not has_time_weather
			and last_has_time_weather_data
		) or (
			has_time_weather
			and not last_confirmed.is_empty()
			and not has_time_weather_data
		):
			render_data["timeWeather"] = (last_time_weather as Dictionary).duplicate(
				true
			)
	if not render_data.is_empty():
		_last_confirmed_data_by_scope[TIME_HUD_SCOPE] = render_data.duplicate(true)
	render_snapshot["data"] = render_data
	_view_models[TIME_HUD_SCOPE] = render_snapshot
	_revision_by_scope[TIME_HUD_SCOPE] = incoming_revision
	if is_node_ready() and not _binding_batch and not _conversation_open():
		_request_rebuild_preserving_joystick()
	return PackedStringArray()


func _render_projection(scope: String, view_model: Dictionary) -> Dictionary:
	if view_model.is_empty():
		return {}
	if scope == "conversation":
		var conversation_data := (
			view_model.get("data", {}) as Dictionary
		)
		return {
			"open": (
				str(view_model.get("status", ""))
				in ["ready", "loading", "error"]
				and not str(
					conversation_data.get("conversationId", "")
				).is_empty()
			),
		}
	var projection := view_model.duplicate(true)
	projection.erase("revision")
	var data := projection.get("data", {}) as Dictionary
	# Position and head anchors change while people walk, but the HUD structure
	# does not. The resident prompt already reads its live anchor every frame.
	data.erase("position")
	for field_name: String in [
		"nearbyTargets",
		"contextTargets",
	]:
		var values := data.get(field_name, []) as Array
		for index: int in values.size():
			if values[index] is Dictionary:
				var target := (values[index] as Dictionary).duplicate(true)
				target.erase("screenAnchor")
				values[index] = target
		data[field_name] = values
	for field_name: String in ["currentTarget", "nextTarget"]:
		var target := (
			data.get(field_name, {}) as Dictionary
		).duplicate(true)
		target.erase("screenAnchor")
		data[field_name] = target
	projection["data"] = data
	return projection


func get_adapter_integration_snapshot() -> Dictionary:
	var avatar: Dictionary = _view_models.get("avatar", {})
	var avatar_data: Dictionary = avatar.get("data", {})
	var gap_values: Array[String] = []
	for gap_path: String in _adapter_contract_gaps:
		gap_values.append(str(_adapter_contract_gaps[gap_path]))
	gap_values.sort()
	var focus_names: Array[String] = []
	for button: Button in _focus_buttons:
		if is_instance_valid(button) and not button.disabled:
			focus_names.append(str(button.name))
	var portrait_modes := {}
	for portrait_id: String in _portrait_nodes:
		var node: Control = _portrait_nodes[portrait_id]
		portrait_modes[portrait_id] = {
			"mode": "texture" if node is TextureRect else "initial_fallback",
			"fallbackReason": str(
				_portrait_fallback_reasons.get(portrait_id, "")
			),
			"drawsVisibleBorder": bool(
				node.get_meta("draws_visible_border", false)
			),
		}
	return {
		"sourceMode": "placeholder" if _using_placeholder else "town_ui_adapter",
		"adapterBound": _adapter != null,
		"adapterInstanceId": _adapter.get_instance_id() if _adapter != null else 0,
		"requiredScopes": REQUIRED_ADAPTER_SCOPES.duplicate(),
		"revisions": _revision_by_scope.duplicate(true),
		"formalReady": bool(avatar_data.get("formalReady", false)),
		"contractGaps": gap_values,
		"lastConfirmedDataByScope": _last_confirmed_data_by_scope.duplicate(true),
		"portraitSlots": portrait_modes,
		"focusOrder": focus_names,
		"lastDispatchResult": _last_dispatch_result.duplicate(true),
	}


func debug_activate_action(action_id: String) -> bool:
	if not _action_nodes.has(action_id):
		return false
	var button: Button = _action_nodes[action_id]
	if not is_instance_valid(button) or button.disabled:
		return false
	button.pressed.emit()
	return true


func focus_default_control() -> bool:
	if not visible or mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return false
	for button: Button in _focus_buttons:
		if (
			is_instance_valid(button)
			and button.is_visible_in_tree()
			and not button.disabled
			and button.focus_mode != Control.FOCUS_NONE
		):
			button.grab_focus()
			return true
	return false


func get_runtime_snapshot() -> Dictionary:
	var avatar: Dictionary = _view_models.get("avatar", {})
	var data: Dictionary = avatar.get("data", {})
	var current_target := _target_dictionary(data.get("currentTarget", {}), {})
	var next_target := _target_dictionary(data.get("nextTarget", {}), {})
	var intents: Array[String] = []
	for intent_id: String in _intent_nodes:
		intents.append(intent_id)
	intents.sort()
	var action_ids: Array[String] = []
	for action_id: String in _action_nodes:
		action_ids.append(action_id)
	action_ids.sort()
	var list_30_exposed := false
	for forbidden: String in LIST_30_INTENTS:
		list_30_exposed = list_30_exposed or forbidden in intents
	return {
		"pageId": "avatar_mode",
		"avatarMode": str(data.get("mode", "")),
		"inputLocked": not _can_accept_interaction_input(),
		"interactionInputEnabled": _can_accept_interaction_input(),
		"formalReady": bool(data.get("formalReady", false)),
		"source": str(data.get("source", "")),
		"capabilityMode": str(data.get("capabilityMode", "")),
		"inputMode": str(_fixture.get("inputMode", "keyboard_mouse")),
		"copyScale": float(_fixture.get("copyScale", 1.0)),
		"viewport": [size.x, size.y],
		"shouldUnmount": _should_unmount,
		"joystickVisible": _component_nodes.has("touch_joystick"),
		"wasdVisible": false,
		"gamepadVisible": _component_nodes.has("gamepad_movement"),
		"movementHintDismissed": true,
		"nearestResidentPromptOnly": true,
		"targetSwitcherExposed": _component_nodes.has("target_switcher"),
		"skillbarVisible": _component_nodes.has("skillbar"),
		"suppressedByConversation": _conversation_open(),
		"focusedTargetId": str(data.get("focusedTargetId", "")),
		"currentTargetId": str(current_target.get("targetId", "")),
		"nextTargetId": str(next_target.get("targetId", "")),
		"list30Exposed": list_30_exposed,
		"intentionallyUnsupportedProductIntents": (
			INTENTIONALLY_UNSUPPORTED_PRODUCT_INTENTS.duplicate()
		),
		"intentIds": intents,
		"actionIds": action_ids,
		"componentRects": get_component_rects(),
		"skillbarChildRects": _skillbar_child_rects(),
		"ownership": audit_runtime_ownership(),
		"assetContract": {
			"completeCompositePreviewLoaded": false,
			"basicNinepatchPath": BASIC_FRAME_PATH,
			"nearbyTalkPromptShellPath": NEARBY_TALK_PROMPT_SHELL_PATH,
			"skillbarShellPath": SKILLBAR_SHELL_PATH,
			"controlPartsPath": CONTROL_ATLAS_PATH,
			"iconSetPath": ICON_ATLAS_PATH,
			"attackButtonNormalPath": ATTACK_BUTTON_NORMAL_PATH,
			"attackButtonLogicalSize": [58, 58],
			"functionalTextNodeCount": _text_nodes.size(),
		},
		"adapterIntegration": get_adapter_integration_snapshot(),
	}


func get_component_rects() -> Array:
	var rects: Array = []
	for component_id: String in _component_nodes:
		var node: Control = _component_nodes[component_id]
		if is_instance_valid(node) and node.visible:
			rects.append(
				{
					"id": component_id,
					"rect": [
						node.position.x,
						node.position.y,
						node.size.x,
						node.size.y,
					],
				}
			)
	return rects


func get_text_rects() -> Array:
	var rects: Array = []
	for text_id: String in _text_nodes:
		var node: Label = _text_nodes[text_id]
		if is_instance_valid(node) and node.visible:
			var global_rect := node.get_global_rect()
			var local_position := global_rect.position - global_position
			rects.append(
				{
					"id": text_id,
					"text": node.text,
					"fontSize": node.get_theme_font_size("font_size"),
					"fullText": String(node.get_meta("full_text", node.text)),
					"maxLines": node.max_lines_visible,
					"lineCount": node.get_line_count(),
					"visibleLineCount": node.get_visible_line_count(),
					"overrun": node.text_overrun_behavior,
					"pageCount": int(node.get_meta("page_count", 1)),
					"pageIndex": int(node.get_meta("page_index", 0)),
					"rect": [
						local_position.x,
						local_position.y,
						global_rect.size.x,
						global_rect.size.y,
					],
				}
			)
	return rects


func operation_feedback_snapshot() -> Dictionary:
	var label := _text_nodes.get("operation_feedback_label") as Label
	return {
		"fullText": _feedback_full_text,
		"pages": _feedback_pages.duplicate(),
		"pageIndex": _feedback_page_index,
		"visibleText": label.text if label != null else "",
		"maxLines": label.max_lines_visible if label != null else 0,
		"visibleLines": label.get_visible_line_count() if label != null else 0,
		"overrun": (
			label.text_overrun_behavior
			if label != null
			else TextServer.OVERRUN_NO_TRIMMING
		),
	}


func get_portrait_rects() -> Array:
	var rects: Array = []
	for portrait_id: String in _portrait_nodes:
		var node: Control = _portrait_nodes[portrait_id]
		if not is_instance_valid(node) or not node.visible:
			continue
		var global_rect := node.get_global_rect()
		var local_position := global_rect.position - global_position
		rects.append(
			{
				"id": portrait_id,
				"kind": "texture" if node is TextureRect else "initial_fallback",
				"fontSize": (
					(node as Label).get_theme_font_size("font_size")
					if node is Label
					else 0
				),
				"drawsVisibleBorder": bool(
					node.get_meta("draws_visible_border", false)
				),
				"rect": [
					local_position.x,
					local_position.y,
					global_rect.size.x,
					global_rect.size.y,
				],
			}
		)
	return rects


func audit_runtime_ownership() -> Dictionary:
	var owners: Dictionary = {}
	var duplicate_semantics: Array[String] = []
	var unowned_border_nodes: Array[String] = []
	var nine_patch_count := 0
	var composite_count := 0
	var operation_border_count := 0
	for node: Node in find_children("*", "", true, false):
		if node is NinePatchRect:
			nine_patch_count += 1
			if not node.has_meta("visible_border_owner"):
				unowned_border_nodes.append(str(node.get_path()))
		if node is TextureRect and str(node.get_meta("component_type", "")) == "composite_container":
			composite_count += 1
		if not node.has_meta("visible_border_owner"):
			continue
		var semantic := str(node.get_meta("border_semantic", ""))
		var owner := str(node.get_meta("visible_border_owner", ""))
		if semantic.is_empty() or owner.is_empty():
			unowned_border_nodes.append(str(node.get_path()))
			continue
		if owners.has(semantic):
			duplicate_semantics.append(semantic)
		else:
			owners[semantic] = owner
		if str(node.get_meta("ownership_layer", "")) == "operation_control":
			operation_border_count += 1
	return {
		"status": (
			"recorded_no_duplicate_owner"
			if duplicate_semantics.is_empty() and unowned_border_nodes.is_empty()
			else "ownership_gate_failed"
		),
		"hierarchy": [
			"page_shell",
			"section_frame",
			"content_slot",
			"operation_control",
		],
		"visibleBorderOwnerCount": owners.size(),
		"duplicateVisibleBorderOwners": duplicate_semantics.size(),
		"duplicateSemantics": duplicate_semantics,
		"unownedVisibleBorderNodes": unowned_border_nodes,
		"ninePatchCount": nine_patch_count,
		"compositeContainerCount": composite_count,
		"operationBorderCount": operation_border_count,
		"childRepeatsSameSemanticBorder": not duplicate_semantics.is_empty(),
		"completeCompositeRegisteredAsStyleBoxTexture": false,
		"debugOverlayIncluded": false,
	}


func _rebuild() -> void:
	UI_NODE_RETIREMENT.retire_children(self)
	_component_nodes.clear()
	_text_nodes.clear()
	_intent_nodes.clear()
	_action_nodes.clear()
	_focus_buttons.clear()
	_portrait_nodes.clear()
	_portrait_fallback_reasons.clear()
	_should_unmount = false
	if not _configured or _theme == null or _basic_frame == null:
		return
	var avatar: Dictionary = _view_models.get("avatar", {})
	var data: Dictionary = avatar.get("data", {})
	var mode := str(data.get("mode", ""))
	_should_unmount = mode not in ["avatar_descent", "avatar_active"]
	if _should_unmount:
		_movement_hint_dismissed = false
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		return
	visible = true
	var input_enabled := mode == "avatar_active"
	mouse_filter = (
		Control.MOUSE_FILTER_PASS
		if input_enabled
		else Control.MOUSE_FILTER_IGNORE
	)
	var conversation_open := _conversation_open()
	if conversation_open:
		# 玩家对话页是当前唯一 UI owner；化身 HUD 不在其背后重复显示。
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		return
	_build_mode_panel(data)
	if not input_enabled:
		_movement_hint_dismissed = false
		# avatar_descent 只保留降落状态。页面不显示或注册任何移动、
		# 近身操作、目标切换、退出和重试控件。
		_layout_runtime()
		return
	_build_time_hud()
	var disabled := (
		str(avatar.get("status", "")) == "disabled"
	)
	if not disabled:
		_build_exit_panel(avatar)
	if not disabled:
		if str(_fixture.get("inputMode", "keyboard_mouse")) == "touch":
			_build_touch_joystick()
		else:
			_build_context_prompts(data)
		_build_skillbar(data, avatar)
		if str(_fixture.get("inputMode", "keyboard_mouse")) == "touch":
			_build_mobile_context_actions(data, avatar)
	_build_operation_feedback(avatar)
	_layout_runtime()
	_configure_focus_chain()


func _build_runtime_theme() -> void:
	var base_font := load(FONT_PATH) as Font
	if base_font == null:
		return
	_font = FontVariation.new()
	_font.base_font = base_font
	_font.spacing_glyph = 2
	_font.variation_embolden = 0.0
	_theme = Theme.new()
	_theme.default_font = _font
	_theme.default_font_size = 28
	var empty := StyleBoxEmpty.new()
	for state: String in [
		"normal",
		"hover",
		"pressed",
		"focus",
		"disabled",
	]:
		_theme.set_stylebox(state, "Button", empty)
	_theme.set_color("font_color", "Label", INK)
	theme = _theme


func _load_runtime_assets() -> void:
	_basic_frame = load(BASIC_FRAME_PATH) as Texture2D
	_target_switcher = load(TARGET_SWITCHER_PATH) as Texture2D
	_control_parts = _load_atlas_parts(CONTROL_ATLAS_PATH, CONTROL_CELL, 3, 2)
	_icons = _load_atlas_parts(ICON_ATLAS_PATH, ICON_CELL, 3, 2)
	_attack_button_normal = load(ATTACK_BUTTON_NORMAL_PATH) as Texture2D
	_attack_button_hover = load(ATTACK_BUTTON_HOVER_PATH) as Texture2D
	_attack_button_pressed = load(ATTACK_BUTTON_PRESSED_PATH) as Texture2D
	_attack_button_disabled = load(ATTACK_BUTTON_DISABLED_PATH) as Texture2D
	_attack_skill_textures.clear()
	for skill: Dictionary in AVATAR_ATTACK_SKILLS:
		var attack_kind := String(skill.get("attackKind", "unarmed"))
		var folder := String(skill.get("assetFolder", ""))
		var stem := String(skill.get("assetStem", ""))
		var prefix := "res://assets/ui/avatar_mode/runtime/attack_button_v1/"
		if not folder.is_empty():
			prefix += "%s/" % folder
		_attack_skill_textures[attack_kind] = {
			"normal": load("%s%s_normal.png" % [prefix, stem]) as Texture2D,
			"hover": load("%s%s_hover.png" % [prefix, stem]) as Texture2D,
			"pressed": load("%s%s_pressed.png" % [prefix, stem]) as Texture2D,
			"disabled": load("%s%s_disabled.png" % [prefix, stem]) as Texture2D,
		}
	_nearby_talk_prompt_shell = load(NEARBY_TALK_PROMPT_SHELL_PATH) as Texture2D
	_skillbar_shell = load(SKILLBAR_SHELL_PATH) as Texture2D
	_mobile_joystick_base = load(MOBILE_JOYSTICK_BASE_PATH) as Texture2D
	_mobile_joystick_knob = load(MOBILE_JOYSTICK_KNOB_PATH) as Texture2D
	_mobile_talk_action = load(MOBILE_TALK_ACTION_PATH) as Texture2D
	_mobile_pet_cat_action = load(MOBILE_PET_CAT_ACTION_PATH) as Texture2D


func _load_atlas_parts(
	path: String,
	cell_size: Vector2i,
	columns: int,
	rows: int
) -> Array[Texture2D]:
	var parts: Array[Texture2D] = []
	var image: Image = null
	if ResourceLoader.exists(path, "Texture2D"):
		var texture := ResourceLoader.load(path, "Texture2D") as Texture2D
		if texture != null:
			image = texture.get_image()
	elif FileAccess.file_exists(path):
		image = Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		push_error("Avatar 模式图集无法读取：%s" % path)
		return parts
	for row: int in rows:
		for column: int in columns:
			var cell_rect := Rect2i(
				column * cell_size.x,
				row * cell_size.y,
				cell_size.x,
				cell_size.y
			)
			var cell := image.get_region(cell_rect)
			var used := cell.get_used_rect()
			var cropped := cell.get_region(used) if used.has_area() else cell
			parts.append(ImageTexture.create_from_image(cropped))
	return parts


func _build_mode_panel(data: Dictionary) -> void:
	var panel := _new_section_frame(
		"mode_place",
		"ui.avatar-mode.basic-ninepatch.primary-frame",
		"section.mode_place"
	)
	var margin := _new_margin(panel, 26, 18, 26, 18)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	margin.add_child(column)
	if str(data.get("mode", "")) == "avatar_descent":
		var descent_title := _new_label(
			"descent_title",
			"正在降落…",
			32,
			INK
		)
		column.add_child(descent_title)
		var descent_status := _new_label(
			"descent_status",
			"请稍候",
			24,
			MUTED
		)
		column.add_child(descent_status)
		return
	var compact_status := _new_label(
		"mode_title",
		"化身",
		24,
		INK
	)
	compact_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(compact_status)


func _build_time_hud() -> void:
	var town_hud: Dictionary = _view_models.get(TIME_HUD_SCOPE, {})
	var town_data: Dictionary = town_hud.get("data", {})
	var time_weather: Dictionary = town_data.get("timeWeather", {})
	if time_weather.is_empty():
		return

	var status_panel := TextureRect.new()
	status_panel.name = "AvatarTimeStatus"
	status_panel.texture = _atlas_texture(
		OBSERVER_SHELL_TEXTURE,
		TIME_STATUS_SOURCE_RECT,
	)
	status_panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	status_panel.stretch_mode = TextureRect.STRETCH_SCALE
	status_panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_owner_meta(
		status_panel,
		"ui.town.hud.observer-shell.time-status-crop-v6",
		"avatar.time.status",
		"section_frame",
		"complete_composite",
	)
	_register_component("time_status", status_panel)
	add_child(status_panel)
	var status_label := _new_label(
		"time_weather",
		_format_time_weather(time_weather),
		32,
		INK,
	)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_panel.add_child(status_label)
	var weather_action := _town_hud_action(
		town_hud,
		["openWeather", "weatherChange"]
	)
	_add_intent_button(status_panel, weather_action, "weatherChange")
	var weather_button := _action_nodes.get("weatherChange") as Button
	if weather_button != null:
		weather_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		weather_button.position = WEATHER_CONTROL_BUTTON_RECT.position
		weather_button.size = WEATHER_CONTROL_BUTTON_RECT.size
		weather_button.tooltip_text = "天气与时间"

	var control_panel := Control.new()
	control_panel.name = "AvatarTimeControls"
	control_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_owner_meta(
		control_panel,
		"ui.town.hud.observer-shell.time-controls-crop-v10",
		"avatar.time.controls",
		"operation_control",
		"complete_composite",
	)
	_register_component("time_controls", control_panel)
	add_child(control_panel)
	_time_control_panel_face = TextureRect.new()
	_time_control_panel_face.name = "AvatarTimeControlsVisual"
	_time_control_panel_face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_time_control_panel_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_time_control_panel_face.stretch_mode = TextureRect.STRETCH_SCALE
	_time_control_panel_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var time_panel_material := ShaderMaterial.new()
	var time_panel_shader := Shader.new()
	time_panel_shader.code = TIME_CONTROL_BACKGROUND_MASK_SHADER
	time_panel_material.shader = time_panel_shader
	_time_control_panel_face.material = time_panel_material
	control_panel.add_child(_time_control_panel_face)

	var paused := bool(
		(town_data.get("pausePrompt", {}) as Dictionary).get("visible", false)
	)
	var selected_id := "time_pause" if paused else _time_speed_id(time_weather)
	_time_control_panel_face.texture = _time_control_panel_texture(selected_id)
	for action_id: String in TIME_CONTROL_BUTTON_RECTS:
		var action_key := _time_control_action_key(action_id, paused)
		var action_keys: Array[String] = [action_key]
		if action_id == "time_pause":
			action_keys.append("resume" if action_key == "pause" else "pause")
		var action := _town_hud_action(town_hud, action_keys)
		_add_intent_button(control_panel, action, action_id)
		var button := _action_nodes.get(action_id) as Button
		if button == null:
			continue
		button.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		button.position = (TIME_CONTROL_BUTTON_RECTS[action_id] as Rect2).position
		button.size = (TIME_CONTROL_BUTTON_RECTS[action_id] as Rect2).size
		button.tooltip_text = _time_control_tooltip(action_id)


func _atlas_texture(source: Texture2D, region: Rect2) -> AtlasTexture:
	var cropped := AtlasTexture.new()
	cropped.atlas = source
	cropped.region = region
	return cropped


func _town_hud_action(
	view_model: Dictionary,
	ordered_keys: Array[String]
) -> Dictionary:
	for key: String in ordered_keys:
		var action := UI_VIEW_MODEL.action(view_model, key)
		if not action.is_empty():
			return action
	return {}


func _format_time_weather(time_weather: Dictionary) -> String:
	var parts: Array[String] = []
	var day := int(time_weather.get("day", 0))
	var clock := String(time_weather.get("clock", ""))
	var period_label := String(time_weather.get("periodLabel", "")).strip_edges()
	var weather_label := String(time_weather.get("weatherLabel", "")).strip_edges()
	if day > 0:
		parts.append("第%d天" % day)
	if not clock.is_empty():
		parts.append(clock)
	if not period_label.is_empty():
		parts.append(period_label)
	if not weather_label.is_empty():
		parts.append(weather_label)
	return " ".join(parts) if not parts.is_empty() else "时间未就绪"


func _time_speed_id(time_weather: Dictionary) -> String:
	var speed := clampi(int(round(float(time_weather.get("simulationSpeed", 1)))), 1, 3)
	return "time_speed_%d" % speed


func _time_control_action_key(action_id: String, paused: bool) -> String:
	if action_id == "time_pause":
		return "resume" if paused else "pause"
	return action_id.replace("time_speed_", "timeSpeed")


func _time_control_tooltip(action_id: String) -> String:
	match action_id:
		"time_pause":
			return "继续小镇时间" if _time_control_is_paused() else "暂停小镇时间"
		"time_speed_1":
			return "切换为 1 倍速度"
		"time_speed_2":
			return "切换为 2 倍速度"
		"time_speed_3":
			return "切换为 3 倍速度"
	return action_id


func _time_control_is_paused() -> bool:
	var town_hud: Dictionary = _view_models.get(TIME_HUD_SCOPE, {})
	var town_data: Dictionary = town_hud.get("data", {})
	return bool(
		(town_data.get("pausePrompt", {}) as Dictionary).get("visible", false)
	)


func _time_control_panel_texture(control_id: String) -> AtlasTexture:
	var source := TIME_CONTROL_PANEL_TEXTURES.get(control_id) as Texture2D
	if source == null:
		return null
	return _atlas_texture(source, TIME_CONTROL_SOURCE_RECT)


func _build_exit_panel(avatar: Dictionary) -> void:
	var action: Dictionary = avatar.get("actions", {}).get("exitMode", {})
	var panel := _new_section_frame(
		"exit",
		"ui.avatar-mode.basic-ninepatch.primary-frame",
		"section.exit"
	)
	if not bool(action.get("enabled", false)):
		panel.modulate = TINT_DISABLED
	_add_intent_button(panel, action, "exitMode")
	var margin := _new_margin(panel, 16, 10, 16, 10)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	var label := _new_label(
		"exit_label",
		"返回观察",
		24,
		INK if bool(action.get("enabled", false)) else DISABLED_INK
	)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(label)


func _build_context_prompts(data: Dictionary) -> void:
	var targets: Array = data.get("contextTargets", [])
	for target_value: Variant in targets:
		if not target_value is Dictionary:
			continue
		var target: Dictionary = target_value
		var kind := str(target.get("kind", ""))
		if kind != "resident":
			continue
		var action: Dictionary = target.get("primaryAction", {})
		# Keep the proximity affordance mounted while a skill is playing. The
		# action remains disabled and explains the temporary lock; removing the
		# whole prompt makes the avatar HUD appear to blink out of existence.
		var action_payload := _target_action_payload(target)
		var screen_anchor := Vector2(-1, -1)
		var anchor_visible := true
		var anchor_value: Variant = target.get("screenAnchor", {})
		if anchor_value is Dictionary:
			var anchor := anchor_value as Dictionary
			if (
				not _using_placeholder
				and is_instance_valid(_adapter)
				and _adapter.has_method(
					"get_town_hud_resident_head_anchor"
				)
				and (
					not bool(anchor.get("valid", false))
					or not bool(anchor.get("visible", false))
				)
			):
				anchor_visible = false
			screen_anchor = Vector2(
				float(anchor.get("x", -1)),
				float(anchor.get("y", -1))
			)
		_build_nearby_talk_prompt(
			action,
			action_payload,
			screen_anchor,
			anchor_visible,
		)
		# contextTargets 已按距离排序且只投影当前目标；页面不再提供 Tab
		# 目标切换，因此第一个居民就是唯一的头顶交谈提示。
		return


func _build_nearby_talk_prompt(
	action: Dictionary,
	action_payload: Dictionary,
	screen_anchor: Vector2,
	initial_visible: bool,
) -> void:
	var root := TextureRect.new()
	root.name = "NearbyTalkPrompt"
	root.texture = _nearby_talk_prompt_shell
	root.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	root.stretch_mode = TextureRect.STRETCH_SCALE
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.visible = initial_visible
	root.set_meta("screen_anchor", screen_anchor)
	root.set_meta(
		"resident_id",
		String(action_payload.get("residentId", "")).strip_edges(),
	)
	_set_owner_meta(
		root,
		"ui.avatar-mode.nearby-talk-prompt-shell-v2",
		"section.prompt.resident",
		"operation_control",
		"complete_composite",
	)
	_register_component("resident_prompt", root)
	add_child(root)
	_add_intent_button(root, action, "resident_prompt", action_payload)
	var key := _new_label("resident_prompt_key", "E", 18, INK)
	key.visible = str(_fixture.get("inputMode", "keyboard_mouse")) != "touch"
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(key)
	var copy := _new_label("resident_prompt_label", "交谈", 20, INK)
	copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	copy.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(copy)
	if not bool(action.get("enabled", false)):
		root.modulate = TINT_DISABLED
	var button := _action_nodes.get("resident_prompt") as Button
	if button != null:
		button.tooltip_text = _resident_prompt_copy(
			String(action_payload.get("residentName", "")),
			1,
			action,
		)


func _build_skillbar(data: Dictionary, avatar: Dictionary) -> void:
	var touch_mode := str(_fixture.get("inputMode", "keyboard_mouse")) == "touch"
	var root := TextureRect.new()
	root.name = "AvatarSkillbar"
	root.texture = _skillbar_shell
	root.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	root.stretch_mode = TextureRect.STRETCH_SCALE
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_owner_meta(
		root,
		"ui.avatar-mode.skillbar-shell-v2",
		"section.skillbar",
		"operation_control",
		"complete_composite",
	)
	_register_component("skillbar", root)
	add_child(root)

	var base_action := avatar.get("actions", {}).get("attackTarget", {}) as Dictionary
	for skill_index: int in AVATAR_ATTACK_SKILLS.size():
		var skill: Dictionary = AVATAR_ATTACK_SKILLS[skill_index]
		var action := base_action.duplicate(true)
		var action_payload := {}
		var attack_kind := String(skill.get("attackKind", "unarmed"))
		action_payload["attackKind"] = attack_kind
		action["payload"] = action_payload.duplicate(true)
		var textures := _attack_skill_textures.get(attack_kind, {}) as Dictionary
		var skill_art := TextureRect.new()
		var action_id := String(skill.get("actionId", ""))
		skill_art.name = "%sArt" % action_id.to_pascal_case()
		skill_art.texture = textures.get(
			"normal" if bool(action.get("enabled", false)) else "disabled",
		) as Texture2D
		skill_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		skill_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		skill_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		skill_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var slot_center_x := float(SKILL_SLOT_CENTERS[skill_index])
		skill_art.position = Vector2(
			slot_center_x - SKILL_ART_SIZE.x * 0.5,
			14,
		)
		skill_art.size = SKILL_ART_SIZE
		root.add_child(skill_art)
		_add_intent_button(root, action, action_id, action_payload)
		var button := _action_nodes.get(action_id) as Button
		if button != null:
			button.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			button.position = Vector2(
				slot_center_x - SKILL_BUTTON_SIZE.x * 0.5,
				9,
			)
			button.size = SKILL_BUTTON_SIZE
			button.tooltip_text = (
				"%s · %s" % [skill.get("key", ""), skill.get("label", "")]
				if bool(action.get("enabled", false))
				else _attack_prompt_copy(action)
			)
			if not button.disabled and not touch_mode:
				button.mouse_entered.connect(
					func() -> void: skill_art.texture = textures.get("hover") as Texture2D
				)
				button.mouse_exited.connect(
					func() -> void: skill_art.texture = textures.get("normal") as Texture2D
				)
				button.button_down.connect(
					func() -> void: skill_art.texture = textures.get("pressed") as Texture2D
				)
				button.button_up.connect(
					func() -> void:
						skill_art.texture = textures.get(
							"normal" if touch_mode else ("hover" if button.is_hovered() else "normal"),
						) as Texture2D
				)
		var key := _new_label(
			"%s_key" % action_id,
			String(skill.get("key", "")),
			16,
			PAPER_LIGHT,
		)
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		key.add_theme_color_override("font_outline_color", INK)
		key.add_theme_constant_override("outline_size", 3)
		key.position = Vector2(slot_center_x + 15, 56)
		key.size = SKILL_KEY_SIZE
		key.visible = not touch_mode
		root.add_child(key)


func _build_mobile_context_actions(data: Dictionary, avatar: Dictionary) -> void:
	var entries: Array[Dictionary] = []
	for target_value: Variant in data.get("contextTargets", []) as Array:
		if not target_value is Dictionary:
			continue
		var target := target_value as Dictionary
		if String(target.get("kind", "")) != "resident":
			continue
		var talk_action := target.get("primaryAction", {}) as Dictionary
		if bool(talk_action.get("enabled", false)):
			entries.append({
				"id": "touch_talk_action",
				"texture": _mobile_talk_action,
				"size": MOBILE_CONTEXT_ACTION_SIZE,
				"action": talk_action,
				"payload": _target_action_payload(target),
			})
		break
	var actions := avatar.get("actions", {}) as Dictionary
	var pet_action := actions.get("petAnimal", {}) as Dictionary
	if bool(pet_action.get("enabled", false)):
		entries.append({
			"id": "touch_pet_action",
			"texture": _mobile_pet_cat_action,
			"size": MOBILE_PET_ACTION_SIZE,
			"action": pet_action,
			"payload": {},
		})
	if entries.is_empty():
		return
	var root := Control.new()
	root.name = "MobileContextActions"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var total_width := 0.0
	var maximum_height := 0.0
	for entry: Dictionary in entries:
		var entry_size := entry.get("size", MOBILE_CONTEXT_ACTION_SIZE) as Vector2
		total_width += entry_size.x
		maximum_height = maxf(maximum_height, entry_size.y)
	total_width += MOBILE_CONTEXT_ACTION_GAP * maxi(0, entries.size() - 1)
	root.size = Vector2(total_width, maximum_height)
	_register_component("mobile_context_actions", root)
	add_child(root)
	for entry_index: int in entries.size():
		var entry := entries[entry_index]
		var action_id := String(entry.get("id", ""))
		var slot := TextureRect.new()
		slot.name = "%sSlot" % action_id.to_pascal_case()
		var entry_size := entry.get("size", MOBILE_CONTEXT_ACTION_SIZE) as Vector2
		var entry_x := 0.0
		for previous_index: int in entry_index:
			entry_x += (entries[previous_index].get("size", MOBILE_CONTEXT_ACTION_SIZE) as Vector2).x + MOBILE_CONTEXT_ACTION_GAP
		slot.position = Vector2(entry_x, root.size.y - entry_size.y)
		slot.size = entry_size
		slot.texture = entry.get("texture") as Texture2D
		slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(slot)
		_add_intent_button(slot, entry.get("action", {}) as Dictionary, action_id, entry.get("payload", {}) as Dictionary)


func _skillbar_child_rects() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var skillbar := _component_nodes.get("skillbar") as Control
	if skillbar == null:
		return result
	for child: Node in skillbar.get_children():
		if not child is Control:
			continue
		var control := child as Control
		result.append({
			"name": control.name,
			"rect": [
				control.position.x,
				control.position.y,
				control.size.x,
				control.size.y,
			],
			"insideShell": Rect2(Vector2.ZERO, SKILLBAR_LOGICAL_SIZE).encloses(
				Rect2(control.position, control.size)
			),
		})
	return result


func _resident_prompt_copy(
	resident_name: String,
	resident_count: int,
	action: Dictionary
) -> String:
	if bool(action.get("enabled", false)):
		return "交谈" if resident_count > 1 else "与%s交谈" % resident_name
	match str(action.get("disabledReason", "")):
		"TARGET_OUT_OF_RANGE", "NO_CONNECTED_NEARBY_TARGET", "NO_NEARBY_TARGET":
			return "再靠近一些"
		"RESIDENT_IDENTITY_UNAVAILABLE":
			return "居民资料暂不可用"
		"CONVERSATION_ALREADY_OPEN":
			return "对话进行中"
		"AVATAR_CONFLICT_ACTIVE":
			return "打斗进行中"
		"AVATAR_ATTACK_ANIMATION_ACTIVE":
			return "招式施放中"
		_:
			return "暂时不能交谈"


func _attack_prompt_copy(action: Dictionary) -> String:
	if bool(action.get("enabled", false)):
		return "攻击"
	match str(action.get("disabledReason", "")):
		"NO_NEARBY_TARGET", "AVATAR_TARGET_NOT_NEARBY":
			return "目标不在附近"
		"AVATAR_CONVERSATION_ACTIVE":
			return "对话中不能攻击"
		"AVATAR_CONFLICT_ACTIVE":
			return "打斗进行中"
		"AVATAR_ATTACK_ANIMATION_ACTIVE":
			return "招式施放中"
		"AVATAR_MODE_NOT_ACTIVE":
			return "尚未进入化身模式"
		"AVATAR_ATTACK_INTERFACE_MISSING":
			return "攻击暂不可用"
		_:
			return "暂时不能攻击"


func _build_context_prompt(
	component_id: String,
	border_semantic: String,
	key_text: String,
	icon_index: int,
	copy: String,
	action: Dictionary,
	action_payload: Dictionary,
	primary: bool,
	screen_anchor: Vector2 = Vector2(-1, -1),
	initial_visible: bool = true,
) -> void:
	var panel := _new_section_frame(
		component_id,
		"ui.avatar-mode.basic-ninepatch.primary-frame",
		border_semantic
	)
	if primary:
		panel.modulate = TINT_PRIMARY
	if not bool(action.get("enabled", false)):
		panel.modulate = TINT_DISABLED
	panel.set_meta("screen_anchor", screen_anchor)
	panel.set_meta(
		"resident_id",
		String(action_payload.get("residentId", "")).strip_edges(),
	)
	panel.visible = initial_visible
	_add_intent_button(panel, action, component_id, action_payload)
	var margin := _new_margin(panel, 14, 8, 14, 8)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	row.add_child(_new_keycap("%s_key" % component_id, key_text, false))
	if icon_index >= 0:
		row.add_child(_new_icon(icon_index, Vector2(44, 44)))
	row.add_child(
		_new_label(
			"%s_label" % component_id,
			copy,
			24,
			INK if bool(action.get("enabled", false)) else DISABLED_INK
		)
	)


func _build_keyboard_movement() -> void:
	var panel := _new_section_frame(
		"keyboard_movement",
		"ui.avatar-mode.basic-ninepatch.primary-frame",
		"section.movement.keyboard"
	)
	var margin := _new_margin(panel, 14, 8, 14, 8)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	margin.add_child(row)
	for key_text: String in ["W", "A", "S", "D"]:
		row.add_child(_new_keycap("move_%s" % key_text.to_lower(), key_text, false))
	row.add_child(_new_label("move_label", "移动", 22, INK))


func _build_gamepad_movement() -> void:
	var panel := _new_section_frame(
		"gamepad_movement",
		"ui.avatar-mode.basic-ninepatch.primary-frame",
		"section.movement.gamepad"
	)
	var margin := _new_margin(panel, 20, 12, 20, 12)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)
	row.add_child(_new_control_part(2, Vector2(58, 58), "gamepad_left_stick"))
	row.add_child(_new_label("move_label", "左摇杆  移动", 26, INK))


func _build_touch_joystick() -> void:
	var root := VIRTUAL_JOYSTICK.new() as AiTownVirtualJoystick
	root.name = "TouchJoystick"
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_register_component("touch_joystick", root)
	add_child(root)
	var base := TextureRect.new()
	base.name = "TouchJoystickBase"
	base.texture = _mobile_joystick_base
	base.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	base.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	base.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base.modulate = Color(1.0, 1.0, 1.0, 0.34)
	root.add_child(base)
	var knob := TextureRect.new()
	knob.name = "TouchJoystickKnob"
	knob.texture = _mobile_joystick_knob
	knob.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	knob.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	knob.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	knob.modulate = Color(1.0, 1.0, 1.0, 0.52)
	root.add_child(knob)
	root.configure(knob)
	root.movement_changed.connect(_set_touch_movement)
	_touch_joystick = root


func _set_touch_movement(value: Vector2) -> void:
	if _touch_movement.is_equal_approx(value):
		if value.is_zero_approx() and _rebuild_after_joystick_release:
			_rebuild_after_joystick_release = false
			_rebuild.call_deferred()
		return
	_touch_movement = value
	movement_input_changed.emit(_touch_movement)
	if value.is_zero_approx() and _rebuild_after_joystick_release:
		_rebuild_after_joystick_release = false
		_rebuild.call_deferred()


func _request_rebuild_preserving_joystick() -> void:
	if is_instance_valid(_touch_joystick) and _touch_joystick.is_pointer_active():
		_rebuild_after_joystick_release = true
		return
	_rebuild()


func _build_portrait_slot(
	parent: Control,
	portrait_id: String,
	target: Dictionary,
	display_name: String,
	primary: bool
) -> void:
	var texture_value: Variant = _portrait_texture_value(target)
	if texture_value is Texture2D:
		var portrait := TextureRect.new()
		portrait.name = portrait_id.to_pascal_case()
		portrait.texture = texture_value as Texture2D
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.modulate = Color.WHITE if primary else Color(0.78, 0.74, 0.68, 0.88)
		portrait.set_meta("component_type", "resident_portrait")
		portrait.set_meta("draws_visible_border", false)
		portrait.set_meta(
			"portrait_role",
			"current_target" if primary else "next_nearby_target"
		)
		parent.add_child(portrait)
		_portrait_nodes[portrait_id] = portrait
		_portrait_fallback_reasons[portrait_id] = ""
		return
	var fallback_copy := str(target.get("portraitFallbackText", ""))
	if fallback_copy.is_empty():
		fallback_copy = display_name.left(1) if not display_name.is_empty() else "—"
	var fallback := _new_label(
		portrait_id,
		fallback_copy,
		28 if primary else 26,
		INK if primary else MUTED
	)
	fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fallback.set_meta("component_type", "resident_portrait_fallback")
	parent.add_child(fallback)
	_portrait_nodes[portrait_id] = fallback
	_portrait_fallback_reasons[portrait_id] = (
		str(target.get("portraitStatus", "unavailable"))
		if not target.is_empty()
		else "portrait_target_missing"
	)


func _portrait_texture_value(target: Dictionary) -> Variant:
	for field_name: String in [
		"portraitTexture",
		"portraitResource",
		"portraitRef",
	]:
		var value: Variant = target.get(field_name, null)
		if value is Texture2D:
			return value
	return null


func _order_residents_for_focus(
	residents: Array,
	focused_target_id: String
) -> Array:
	var ordered := residents.duplicate(true)
	if focused_target_id.is_empty():
		return ordered
	var focused_index := -1
	for index: int in ordered.size():
		if not ordered[index] is Dictionary:
			continue
		var resident: Dictionary = ordered[index]
		var resident_id := str(resident.get("residentId", ""))
		if focused_target_id in [resident_id, "resident:%s" % resident_id]:
			focused_index = index
			break
	if focused_index > 0:
		var focused_value: Variant = ordered[focused_index]
		ordered.remove_at(focused_index)
		ordered.push_front(focused_value)
	return ordered


func _target_action_payload(target: Dictionary) -> Dictionary:
	var payload := {}
	var target_id := str(target.get("targetId", ""))
	var resident_id := str(target.get("residentId", ""))
	if not target_id.is_empty():
		payload["targetId"] = target_id
	if not resident_id.is_empty():
		payload["residentId"] = resident_id
	return payload


func _target_dictionary(value: Variant, fallback: Variant) -> Dictionary:
	if value is Dictionary and not (value as Dictionary).is_empty():
		return (value as Dictionary).duplicate(true)
	if fallback is Dictionary:
		return (fallback as Dictionary).duplicate(true)
	return {}


func _target_display_name(target: Dictionary, fallback: String) -> String:
	for field_name: String in ["residentName", "name", "label"]:
		var value := str(target.get(field_name, ""))
		if not value.is_empty():
			return value
	return fallback


func _build_operation_feedback(avatar: Dictionary) -> void:
	var operation: Dictionary = avatar.get("operation", {})
	var status := str(operation.get("status", "idle"))
	var data: Dictionary = avatar.get("data", {})
	var message := ""
	var ink := MUTED
	if status == "loading":
		message = _operation_loading_copy(str(operation.get("intent", "")))
	elif status == "success":
		message = "操作已确认"
		ink = SUCCESS_INK
	elif status in ["rejected", "error"]:
		message = str(avatar.get("error", {}).get("message", "操作未完成，请稍后重试。"))
		ink = ERROR_INK
	elif status == "disabled":
		message = str(data.get("prompt", {}).get("message", "化身模式暂不可用。"))
	if message.is_empty():
		if status == "idle":
			_feedback_active_key = ""
			_feedback_hidden_key = ""
			_feedback_expire_at_msec = 0
			_feedback_pages.clear()
			_feedback_page_index = 0
			_feedback_page_elapsed = 0.0
			_feedback_full_text = ""
			return
	var error_value: Variant = avatar.get("error", {})
	var error: Dictionary = {}
	if error_value is Dictionary:
		error = error_value as Dictionary
	var feedback_key := "%s|%s|%s|%s" % [
		str(operation.get("requestId", "")),
		status,
		str(operation.get("intent", "")),
		str(error.get("code", "")),
	]
	if feedback_key == _feedback_hidden_key:
		return
	if feedback_key != _feedback_active_key:
		_feedback_active_key = feedback_key
		_feedback_hidden_key = ""
		_feedback_full_text = message
		_feedback_pages = _split_feedback_pages(message)
		_feedback_page_index = 0
		_feedback_page_elapsed = 0.0
		var lifetime_msec := 0
		if status in ["success", "rejected", "error"]:
			lifetime_msec = 1800 if status == "success" else 4000
		if _feedback_pages.size() > 1:
			lifetime_msec = maxi(
				lifetime_msec,
				int(ceil(
					_feedback_pages.size()
					* FEEDBACK_PAGE_DURATION_SECONDS
					* 1000.0
				)) + 500,
			)
		_feedback_expire_at_msec = (
			Time.get_ticks_msec() + lifetime_msec
			if lifetime_msec > 0
			else 0
		)
	var retry_action: Dictionary = avatar.get("actions", {}).get("retry", {})
	if bool(retry_action.get("enabled", false)):
		match str(_fixture.get("inputMode", "keyboard_mouse")):
			"touch":
				message += "　点按重试"
			"gamepad":
				message += "　A 重试"
			_:
				message += "　R 重试"
	if message != _feedback_full_text:
		_feedback_full_text = message
		_feedback_pages = _split_feedback_pages(message)
		_feedback_page_index = 0
		_feedback_page_elapsed = 0.0
		if status in ["rejected", "error"] and _feedback_pages.size() > 1:
			_feedback_expire_at_msec = Time.get_ticks_msec() + int(ceil(
				_feedback_pages.size()
				* FEEDBACK_PAGE_DURATION_SECONDS
				* 1000.0
			)) + 500
	var panel := _new_section_frame(
		"operation_feedback",
		"ui.avatar-mode.basic-ninepatch.primary-frame",
		"section.operation_feedback"
	)
	if bool(retry_action.get("enabled", false)):
		_add_intent_button(panel, retry_action, "retry")
	panel.set_meta("feedback_status", status)
	var visible_message := (
		_balanced_feedback_lines(_feedback_pages[_feedback_page_index])
		if not _feedback_pages.is_empty()
		else message
	)
	var label := _new_label("operation_feedback_label", visible_message, 24, ink)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.max_lines_visible = 2
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	label.tooltip_text = _feedback_full_text
	label.set_meta("full_text", _feedback_full_text)
	label.set_meta("page_count", _feedback_pages.size())
	label.set_meta("page_index", _feedback_page_index)
	panel.add_child(label)


func _update_operation_feedback_page(delta: float) -> void:
	if _feedback_pages.size() <= 1:
		return
	_feedback_page_elapsed += delta
	var next_index := int(floor(
		_feedback_page_elapsed / FEEDBACK_PAGE_DURATION_SECONDS
	)) % _feedback_pages.size()
	if next_index == _feedback_page_index:
		return
	_feedback_page_index = next_index
	var label := _text_nodes.get("operation_feedback_label") as Label
	if label == null:
		return
	label.text = _balanced_feedback_lines(_feedback_pages[_feedback_page_index])
	label.set_meta("page_index", _feedback_page_index)


func _split_feedback_pages(value: String) -> Array[String]:
	var normalized := _normalize_feedback_text(value)
	var pages: Array[String] = []
	var remaining := normalized
	while _feedback_display_units(remaining) > FEEDBACK_PAGE_MAX_UNITS:
		var remaining_units := _feedback_display_units(remaining)
		var page_count := int(ceil(
			remaining_units / FEEDBACK_PAGE_MAX_UNITS
		))
		var split_at := _feedback_split_index(
			remaining,
			remaining_units / float(page_count),
			FEEDBACK_PAGE_MAX_UNITS,
		)
		pages.append(remaining.left(split_at).strip_edges())
		remaining = remaining.substr(split_at).strip_edges()
	if not remaining.is_empty():
		pages.append(remaining)
	return pages


func _balanced_feedback_lines(value: String) -> String:
	var units := _feedback_display_units(value)
	if units <= FEEDBACK_LINE_MAX_UNITS:
		return value
	var split_at := _feedback_split_index(
		value,
		units / 2.0,
		FEEDBACK_LINE_MAX_UNITS,
	)
	return "%s\n%s" % [
		value.left(split_at).strip_edges(),
		value.substr(split_at).strip_edges(),
	]


func _feedback_split_index(
	value: String,
	target_units: float,
	max_units: float,
) -> int:
	const BREAKS := "。！？!?；;，,、：: "
	var minimum_units := maxf(2.0, target_units * 0.6)
	var units := 0.0
	var fallback := 1
	var fallback_distance := INF
	var best := -1
	var best_score := INF
	for index: int in value.length():
		var next_units := units + _feedback_character_units(value, index)
		if next_units > max_units:
			break
		units = next_units
		var distance := absf(units - target_units)
		if distance <= fallback_distance:
			fallback_distance = distance
			fallback = index + 1
		var character := value.substr(index, 1)
		if units < minimum_units or not BREAKS.contains(character):
			continue
		if _feedback_display_units(value.substr(index + 1)) < minimum_units:
			continue
		var score := distance - (2.0 if "。！？!?；;".contains(character) else 0.5)
		if score < best_score:
			best_score = score
			best = index + 1
	return best if best >= 0 else fallback


func _normalize_feedback_text(value: String) -> String:
	var normalized := value.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
	while normalized.contains("  "):
		normalized = normalized.replace("  ", " ")
	return normalized.strip_edges()


func _feedback_display_units(value: String) -> float:
	var units := 0.0
	for index: int in value.length():
		units += _feedback_character_units(value, index)
	return units


func _feedback_character_units(value: String, index: int) -> float:
	var character := value.substr(index, 1)
	if _font != null:
		return maxf(
			0.5,
			_font.get_string_size(
				character,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1.0,
				24,
			).x / 24.0,
		)
	return 1.0 if value.unicode_at(index) > 0x2E7F else 0.5


func _layout_runtime() -> void:
	if not is_node_ready() or _component_nodes.is_empty():
		return
	var safe := _safe_rect()
	if safe.size.x <= 0.0 or safe.size.y <= 0.0:
		return
	var copy_scale := clampf(float(_fixture.get("copyScale", 1.0)), 1.0, 1.3)
	var avatar: Dictionary = _view_models.get("avatar", {})
	var data: Dictionary = avatar.get("data", {})
	var descent := str(data.get("mode", "")) == "avatar_descent"
	var mode_size := (
		Vector2(300, 120) * Vector2(copy_scale, copy_scale)
		if descent
		else Vector2(126, 64)
	)
	var exit_size := Vector2(168, 64)
	var narrow_top := safe.size.x < 700
	if narrow_top:
		mode_size.x = safe.size.x - 32
		exit_size.x = minf(180, safe.size.x - 32)
		_place("mode_place", safe.position + Vector2(16, 16), mode_size)
		_place(
			"exit",
			Vector2(safe.end.x - exit_size.x - 16, safe.position.y + mode_size.y + 12),
			exit_size
		)
	else:
		_place("mode_place", safe.position + Vector2(16, 16), mode_size)
		_place(
			"exit",
			Vector2(safe.end.x - exit_size.x - 16, safe.position.y + 16),
			exit_size
		)
	_layout_time_hud(safe)
	var touch_mode := str(_fixture.get("inputMode", "keyboard_mouse")) == "touch"
	var joystick_size := (
		minf(TOUCH_JOYSTICK_MAX_SIZE, maxf(TOUCH_JOYSTICK_MIN_SIZE, safe.size.y * 0.46))
		if touch_mode
		else minf(168.0, maxf(132.0, safe.size.y * 0.28))
	)
	_place(
		"touch_joystick",
		Vector2(safe.position.x + 4.0, safe.end.y - joystick_size - 4.0),
		Vector2.ONE * joystick_size,
	)
	if is_instance_valid(_touch_joystick):
		_touch_joystick.visible = touch_mode
		var base := _touch_joystick.get_node_or_null("TouchJoystickBase") as Control
		var knob := _touch_joystick.get_node_or_null("TouchJoystickKnob") as Control
		if is_instance_valid(base):
			base.position = Vector2.ZERO
			base.size = Vector2.ONE * joystick_size
		if is_instance_valid(knob):
			var knob_size := Vector2.ONE * roundf(joystick_size * 0.48)
			knob.size = knob_size
			knob.position = (Vector2.ONE * joystick_size - knob_size) * 0.5
	var skillbar_size := TOUCH_SKILLBAR_SIZE if touch_mode else Vector2(310, 86)
	skillbar_size.x = minf(skillbar_size.x, safe.size.x - 24)
	skillbar_size.y = roundf(skillbar_size.x * 86.0 / 310.0)
	_place(
		"skillbar",
		Vector2(
			safe.position.x + (safe.size.x - skillbar_size.x) * 0.5,
			safe.end.y - skillbar_size.y - 12
		),
		skillbar_size
	)
	if _component_nodes.has("mobile_context_actions"):
		var context_actions := _component_nodes["mobile_context_actions"] as Control
		_place(
			"mobile_context_actions",
			Vector2(safe.end.x - context_actions.size.x - 2.0, safe.end.y - context_actions.size.y - 6.0),
			context_actions.size,
		)
	_layout_resident_prompt(safe)
	_layout_feedback(safe)


func _layout_time_hud(safe: Rect2) -> void:
	if (
		not _component_nodes.has("time_status")
		or not _component_nodes.has("time_controls")
	):
		return
	var uniform_scale := _hud_reference_scale(safe)
	var shell_origin := _hud_reference_origin(safe, uniform_scale)
	_place(
		"time_status",
		shell_origin + TIME_STATUS_SOURCE_RECT.position * uniform_scale,
		TIME_STATUS_SOURCE_RECT.size * uniform_scale,
	)
	_set_child_rect(
		"time_weather",
		Rect2(
			TIME_STATUS_TEXT_RECT.position * uniform_scale,
			TIME_STATUS_TEXT_RECT.size * uniform_scale,
		),
	)
	var weather_button := _action_nodes.get("weatherChange") as Button
	if weather_button != null:
		weather_button.position = WEATHER_CONTROL_BUTTON_RECT.position * uniform_scale
		weather_button.size = WEATHER_CONTROL_BUTTON_RECT.size * uniform_scale
	_place(
		"time_controls",
		_hud_right_anchored_position(
			safe,
			TIME_CONTROL_REFERENCE_RECT,
			uniform_scale,
		),
		TIME_CONTROL_REFERENCE_RECT.size * uniform_scale,
	)
	var control_panel := _component_nodes["time_controls"] as Control
	if is_instance_valid(_time_control_panel_face):
		_time_control_panel_face.position = Vector2.ZERO
		_time_control_panel_face.size = control_panel.size
	for action_id: String in TIME_CONTROL_BUTTON_RECTS:
		var button := _action_nodes.get(action_id) as Button
		if button == null:
			continue
		var button_rect := TIME_CONTROL_BUTTON_RECTS[action_id] as Rect2
		button.position = button_rect.position * uniform_scale
		button.size = button_rect.size * uniform_scale


func _hud_reference_scale(safe: Rect2) -> float:
	var uniform_scale := minf(
		safe.size.x / HUD_REFERENCE_SIZE.x,
		safe.size.y / HUD_REFERENCE_SIZE.y,
	)
	var aspect := safe.size.x / maxf(1.0, safe.size.y)
	if aspect < HUD_REFERENCE_ASPECT:
		return safe.size.x / HUD_REFERENCE_SIZE.x
	return uniform_scale


func _hud_reference_origin(safe: Rect2, uniform_scale: float) -> Vector2:
	var aspect := safe.size.x / maxf(1.0, safe.size.y)
	if aspect < HUD_REFERENCE_ASPECT:
		return safe.position
	return safe.position + (
		safe.size - HUD_REFERENCE_SIZE * uniform_scale
	) * 0.5


func _hud_right_anchored_position(
	safe: Rect2,
	reference_rect: Rect2,
	uniform_scale: float,
) -> Vector2:
	var aspect := safe.size.x / maxf(1.0, safe.size.y)
	if aspect < HUD_REFERENCE_ASPECT:
		return safe.position + reference_rect.position * uniform_scale
	var right_inset := (
		HUD_REFERENCE_SIZE.x - reference_rect.end.x
	) * uniform_scale
	return Vector2(
		safe.end.x - right_inset - reference_rect.size.x * uniform_scale,
		safe.position.y + reference_rect.position.y * uniform_scale,
	)


func _layout_resident_prompt(safe: Rect2) -> void:
	if not _component_nodes.has("resident_prompt"):
		return
	var prompt := _component_nodes["resident_prompt"] as Control
	var anchor: Vector2 = prompt.get_meta("screen_anchor", Vector2(-1, -1))
	var touch_prompt := str(_fixture.get("inputMode", "keyboard_mouse")) == "touch"
	var group_size := (
		Vector2(minf(184.0, safe.size.x - 24.0), 76.0)
		if touch_prompt
		else Vector2(minf(156.0, safe.size.x - 24.0), 60.0)
	)
	var position := Vector2(
		safe.position.x + (safe.size.x - group_size.x) * 0.5,
		safe.position.y + safe.size.y * 0.38,
	)
	if anchor.x >= 0 and anchor.y >= 0:
		position = Vector2(
			anchor.x - group_size.x * 0.5,
			anchor.y - group_size.y - 22.0,
		)
	position.x = clampf(
		position.x,
		safe.position.x + 8.0,
		safe.end.x - group_size.x - 8.0,
	)
	position.y = clampf(
		position.y,
		safe.position.y + 84.0,
		safe.end.y - group_size.y - 12.0,
	)
	_place("resident_prompt", position, group_size)
	_set_child_rect("resident_prompt_key", Rect2(17, 17, 0 if touch_prompt else 35, 28))
	_set_child_rect("resident_prompt_label", Rect2(18 if touch_prompt else 58, 14, 148 if touch_prompt else 82, 48 if touch_prompt else 32))


func _sync_live_resident_prompt_anchor() -> void:
	if (
		_using_placeholder
		or not _adapter_head_anchor_call.is_valid()
		or not _component_nodes.has("resident_prompt")
	):
		return
	var prompt := _component_nodes.get("resident_prompt") as Control
	if not is_instance_valid(prompt):
		return
	var resident_id := String(
		prompt.get_meta("resident_id", "")
	).strip_edges()
	if resident_id.is_empty():
		prompt.visible = false
		return
	var anchor := _adapter_head_anchor_call.call(resident_id) as Dictionary
	var visible := (
		bool(anchor.get("valid", false))
		and bool(anchor.get("visible", false))
		and anchor.has("x")
		and anchor.has("y")
	)
	prompt.visible = visible
	if not visible:
		return
	prompt.set_meta(
		"screen_anchor",
		Vector2(
			float(anchor.get("x", -1.0)),
			float(anchor.get("y", -1.0)),
		),
	)
	_layout_resident_prompt(_safe_rect())


func _layout_feedback(safe: Rect2) -> void:
	if not _component_nodes.has("operation_feedback"):
		return
	var panel: Control = _component_nodes["operation_feedback"]
	var status := str(panel.get_meta("feedback_status", ""))
	var feedback_size := (
		Vector2(minf(460, safe.size.x - 32), 84)
		if status in ["rejected", "error", "disabled"]
		else Vector2(minf(300, safe.size.x - 32), 88)
	)
	var bottom_anchor := safe.end.y - 18
	if _component_nodes.has("skillbar"):
		var skillbar: Control = _component_nodes["skillbar"]
		bottom_anchor = skillbar.position.y - 8
	_place(
		"operation_feedback",
		Vector2(
			safe.position.x + (safe.size.x - feedback_size.x) * 0.5,
			bottom_anchor - feedback_size.y
		),
		feedback_size
	)
	_set_child_rect(
		"operation_feedback_label",
		Rect2(18, 8, feedback_size.x - 36, feedback_size.y - 16)
	)


func _place(component_id: String, position: Vector2, component_size: Vector2) -> void:
	if not _component_nodes.has(component_id):
		return
	var node: Control = _component_nodes[component_id]
	node.position = position.round()
	node.size = component_size.round()


func _set_child_rect(text_id: String, rect: Rect2) -> void:
	if not _text_nodes.has(text_id):
		return
	var label: Label = _text_nodes[text_id]
	label.position = rect.position.round()
	label.size = rect.size.round()


func _set_portrait_rect(
	portrait_id: String,
	fallback_rect: Rect2,
	texture_rect: Rect2
) -> void:
	if not _portrait_nodes.has(portrait_id):
		return
	var node: Control = _portrait_nodes[portrait_id]
	var rect := texture_rect if node is TextureRect else fallback_rect
	node.position = rect.position.round()
	node.size = rect.size.round()


func _safe_rect() -> Rect2:
	var safe: Dictionary = _fixture.get("safeInsets", {})
	var left := float(safe.get("left", 0))
	var top := float(safe.get("top", 0))
	var right := float(safe.get("right", 0))
	var bottom := float(safe.get("bottom", 0))
	return Rect2(left, top, maxf(1, size.x - left - right), maxf(1, size.y - top - bottom))


func _new_section_frame(
	component_id: String,
	asset_id: String,
	border_semantic: String
) -> NinePatchRect:
	var panel := NinePatchRect.new()
	panel.name = component_id.to_pascal_case()
	panel.texture = _basic_frame
	panel.draw_center = true
	panel.patch_margin_left = 44
	panel.patch_margin_top = 44
	panel.patch_margin_right = 44
	panel.patch_margin_bottom = 44
	panel.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	panel.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 装饰壳本身不吞地图输入；需要交互的组件由其透明 Button 子节点
	# 单独拥有命中区。
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_owner_meta(panel, asset_id, border_semantic, "section_frame", "basic_ninepatch")
	_register_component(component_id, panel)
	add_child(panel)
	return panel


func _new_margin(
	parent: Control,
	left: int,
	top: int,
	right: int,
	bottom: int
) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", left)
	margin.add_theme_constant_override("margin_top", top)
	margin.add_theme_constant_override("margin_right", right)
	margin.add_theme_constant_override("margin_bottom", bottom)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(margin)
	return margin


func _new_label(
	text_id: String,
	copy: String,
	font_size: int,
	color: Color
) -> Label:
	var label := Label.new()
	label.name = text_id.to_pascal_case()
	label.text = copy
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_meta("draws_visible_border", false)
	_text_nodes[text_id] = label
	return label


func _new_keycap(text_id: String, copy: String, wide: bool) -> Control:
	var root := Control.new()
	root.name = text_id.to_pascal_case()
	root.custom_minimum_size = Vector2(74 if wide else 54, 54)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var texture := TextureRect.new()
	texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture.texture = _control_parts[1 if wide else 0]
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_owner_meta(
		texture,
		"ui.avatar-mode.control-parts.input",
		"operation.keycap.%s" % text_id,
		"operation_control",
		"control_part"
	)
	root.add_child(texture)
	var label := _new_label(text_id, copy, 22 if wide else 24, INK)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(label)
	return root


func _new_control_part(index: int, part_size: Vector2, semantic: String) -> TextureRect:
	var texture := TextureRect.new()
	texture.name = semantic.to_pascal_case()
	texture.custom_minimum_size = part_size
	texture.size = part_size
	texture.texture = _control_parts[index]
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_owner_meta(
		texture,
		"ui.avatar-mode.control-parts.input",
		"operation.%s" % semantic,
		"operation_control",
		"control_part"
	)
	return texture


func _new_icon(index: int, icon_size: Vector2) -> TextureRect:
	var texture := TextureRect.new()
	texture.custom_minimum_size = icon_size
	texture.size = icon_size
	texture.texture = _icons[index]
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture.set_meta("component_type", "icon")
	texture.set_meta("draws_visible_border", false)
	return texture


func _add_intent_button(
	parent: Control,
	action: Dictionary,
	action_id: String,
	extra_payload: Dictionary = {}
) -> void:
	var button := Button.new()
	button.name = "%sButton" % action_id.to_pascal_case()
	button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.text = ""
	button.flat = true
	button.disabled = (
		not bool(action.get("enabled", false))
		or _action_is_loading(str(action.get("intent", "")))
	)
	button.focus_mode = Control.FOCUS_NONE if button.disabled else Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.set_meta("draws_visible_border", false)
	button.set_meta("action_id", action_id)
	_action_nodes[action_id] = button
	var intent := str(action.get("intent", ""))
	if not intent.is_empty():
		_intent_nodes[intent] = button
		button.pressed.connect(
			func() -> void:
				_request_action(action, action_id, extra_payload)
		)
	if not button.disabled and not intent.is_empty():
		_focus_buttons.append(button)
	parent.add_child(button)


func _action_is_loading(intent: String) -> bool:
	if intent.is_empty():
		return false
	for scope: String in REQUIRED_ADAPTER_SCOPES + [TIME_HUD_SCOPE]:
		var view_model: Dictionary = _view_models.get(scope, {})
		var operation: Dictionary = view_model.get("operation", {})
		if (
			str(operation.get("status", "")) == "loading"
			and str(operation.get("intent", "")) == intent
		):
			return true
	return false


func _request_action(
	action: Dictionary,
	action_id: String,
	extra_payload: Dictionary
) -> void:
	var intent := str(action.get("intent", ""))
	if intent.is_empty() or not bool(action.get("enabled", false)):
		return
	var payload := {}
	var action_payload: Variant = action.get("payload", {})
	if action_payload is Dictionary:
		payload = (action_payload as Dictionary).duplicate(true)
	for key: Variant in extra_payload:
		if not payload.has(key):
			payload[key] = extra_payload[key]
	payload["actionId"] = action_id
	intent_requested.emit(intent, payload.duplicate(true))
	if _adapter != null and _adapter.has_method("dispatch"):
		var result: Variant = _adapter.call("dispatch", intent, payload.duplicate(true))
		_last_dispatch_result = (
			(result as Dictionary).duplicate(true)
			if result is Dictionary
			else {
				"ok": false,
				"accepted": false,
				"errorCode": "ADAPTER_DISPATCH_RESULT_INVALID",
			}
		)


func _disconnect_adapter() -> void:
	UI_SIGNALS.disconnect_view_model(
		_adapter,
		Callable(self, "_on_adapter_view_model_changed"),
	)


func _on_adapter_view_model_changed(
	scope: String,
	view_model: Dictionary
) -> void:
	if scope == TIME_HUD_SCOPE:
		var time_issues := _apply_time_hud_view_model(view_model)
		for issue: String in time_issues:
			if not issue.contains("丢弃过期"):
				push_error(issue)
		return
	if scope not in REQUIRED_ADAPTER_SCOPES:
		return
	var issues := apply_view_model(view_model)
	for issue: String in issues:
		if not issue.contains("丢弃过期"):
			push_error(issue)


func _update_adapter_contract_gaps(
	scope: String,
	view_model: Dictionary
) -> void:
	for gap_path: String in _adapter_contract_gaps.keys():
		if gap_path.begins_with("%s." % scope):
			_adapter_contract_gaps.erase(gap_path)
	if scope != "avatar":
		return
	var data: Dictionary = view_model.get("data", {})
	var actions: Dictionary = view_model.get("actions", {})
	for field_name: String in [
		"mode",
		"focusedTargetId",
		"currentTarget",
		"nextTarget",
		"contextTargets",
	]:
		if not data.has(field_name):
			_set_contract_gap(
				"avatar.data.%s" % field_name,
				"TownUiAdapter.avatar.data 缺少 %s；页面停止该字段，不从 World 或页面状态推断。"
				% field_name
			)
	for metadata_name: String in [
		"source",
		"capabilityMode",
		"formalReady",
	]:
		if not data.has(metadata_name):
			_set_contract_gap(
				"avatar.data.%s" % metadata_name,
				"TownUiAdapter.avatar.data 缺少 %s；页面默认保持 formalReady=false，不自动升级 placeholder。"
				% metadata_name
			)
	for action_name: String in [
		"attackTarget",
		"exitMode",
		"retry",
	]:
		if not actions.has(action_name):
			_set_contract_gap(
				"avatar.actions.%s" % action_name,
				"TownUiAdapter.avatar.actions 缺少 %s；页面不派发对应 avatar.* intent。"
				% action_name
			)


func _set_contract_gap(path: String, message: String) -> void:
	_adapter_contract_gaps[path] = "%s — %s" % [path, message]


func _configure_focus_chain() -> void:
	var enabled_buttons: Array[Button] = []
	for button: Button in _focus_buttons:
		if is_instance_valid(button) and not button.disabled:
			enabled_buttons.append(button)
	if enabled_buttons.is_empty():
		return
	enabled_buttons.sort_custom(
		func(first: Button, second: Button) -> bool:
			return _focus_priority(first) < _focus_priority(second)
	)
	_focus_buttons.clear()
	_focus_buttons.append_array(enabled_buttons)
	for index: int in enabled_buttons.size():
		var current := enabled_buttons[index]
		var previous := enabled_buttons[
			(index - 1 + enabled_buttons.size()) % enabled_buttons.size()
		]
		var next := enabled_buttons[(index + 1) % enabled_buttons.size()]
		current.focus_previous = current.get_path_to(previous)
		current.focus_next = current.get_path_to(next)
		current.focus_neighbor_left = current.get_path_to(previous)
		current.focus_neighbor_top = current.get_path_to(previous)
		current.focus_neighbor_right = current.get_path_to(next)
		current.focus_neighbor_bottom = current.get_path_to(next)


func _focus_priority(button: Button) -> int:
	var order := [
		"weatherChange",
		"time_pause",
		"time_speed_1",
		"time_speed_2",
		"time_speed_3",
		"resident_prompt",
		"skill_attack_1",
		"skill_attack_2",
		"skill_attack_3",
		"skill_attack_4",
		"retry",
		"exitMode",
	]
	var index := order.find(str(button.get_meta("action_id", "")))
	return index if index >= 0 else order.size()


func _activate_focused_button() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner() as Button
	if (
		focus_owner != null
		and is_ancestor_of(focus_owner)
		and not focus_owner.disabled
	):
		focus_owner.pressed.emit()
		return true
	if focus_default_control():
		return false
	return debug_activate_action("resident_prompt")


func _can_accept_interaction_input() -> bool:
	if not _configured or not visible or mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return false
	var avatar: Dictionary = _view_models.get("avatar", {})
	var data: Dictionary = avatar.get("data", {})
	return (
		str(data.get("mode", "")) == "avatar_active"
		and str(avatar.get("status", "")) != "disabled"
		and not _conversation_open()
	)


func _set_owner_meta(
	node: Control,
	owner: String,
	semantic: String,
	layer: String,
	component_type: String
) -> void:
	node.set_meta("visible_border_owner", owner)
	node.set_meta("border_semantic", semantic)
	node.set_meta("ownership_layer", layer)
	node.set_meta("component_type", component_type)


func _register_component(component_id: String, node: Control) -> void:
	_component_nodes[component_id] = node


func _resident_name(residents: Array, index: int, fallback: String) -> String:
	if index < residents.size() and residents[index] is Dictionary:
		return str((residents[index] as Dictionary).get("name", fallback))
	return fallback


func _target_switch_copy() -> String:
	var compact := size.x < 700
	match str(_fixture.get("inputMode", "keyboard_mouse")):
		"touch":
			return "点按切换" if compact else "点按头像切换目标"
		"gamepad":
			return "LB/RB 切换" if compact else "LB / RB  切换目标"
		_:
			return "Tab 切换" if compact else "Tab  切换目标"


func _operation_loading_copy(intent: String) -> String:
	match intent:
		"avatar.focus_target":
			return "正在切换目标…"
		"avatar.attack_target":
			return "正在确认攻击…"
		"avatar.exit_mode":
			return "正在退出化身模式…"
		_:
			return "正在处理操作…"


func _conversation_open() -> bool:
	var conversation: Dictionary = _view_models.get("conversation", {})
	var data: Dictionary = conversation.get("data", {})
	return (
		str(conversation.get("status", "")) in ["ready", "loading", "error"]
		and not str(data.get("conversationId", "")).is_empty()
	)
