class_name TownHudOverlay
extends Control


const UiViewModel := preload("res://ui/common/AiTownUiViewModel.gd")
const Typography := preload(
	"res://ui/town/hud/runtime/TownHudTypographyContract.gd"
)
const RESIDENT_DIRECTORY_SCENE := preload(
	"res://ui/town/hud/runtime/ResidentDirectoryDrawer.tscn"
)
const PLACE_DIRECTORY_SCENE := preload(
	"res://ui/town/hud/runtime/PlaceDirectoryDrawer.tscn"
)
const FAR_RESIDENT_ACTIVITY_SCENE := preload(
	"res://ui/town/hud/runtime/TownFarResidentActivityLayer.tscn"
)
const RUNTIME_VISUAL_STATUS := &"observer_v5_static_shell_runtime_ready"
const ORIGINAL_SOURCE_PROVENANCE_PATH := (
	"res://assets/ui/town/hud/runtime/source/provenance.json"
)
const ASSET_REGISTRY_PATH := (
	"res://assets/ui/town/hud/runtime/hud_runtime_asset_registry.json"
)
const RUNTIME_FONT_PATH := (
	"res://assets/fonts/zheng_ge_dian_hei_16/"
	+ "ZhengGeDianHei-16.ttf"
)
const OUTER_SHELL_TEXTURE := preload(
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
const TIME_CONTROL_PANEL_SOURCE_RECT := Rect2(1552.0, 340.0, 120.0, 401.0)
const TIME_SPEED_CONTROLS := {
	"time_speed_1": {"actionKey": "timeSpeed1", "multiplier": 1},
	"time_speed_2": {"actionKey": "timeSpeed2", "multiplier": 2},
	"time_speed_3": {"actionKey": "timeSpeed3", "multiplier": 3},
}
const HUD_REFERENCE_SIZE := Vector2(1672.0, 941.0)
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

signal intent_requested(intent: StringName, payload: Dictionary)
signal view_model_applied(revision: int, operation_status: StringName)
signal view_model_rejected(issues: PackedStringArray)

@export var require_formal_ready := true
@export var preview_font: Font
@export var safe_insets := Vector4.ZERO
@export var physical_scale := Vector2.ONE

var _current_revision := -1
var _view_model: Dictionary = {}
var _data: Dictionary = {}
var _actions: Dictionary = {}
var _layout: Dictionary = {}
var _labels: Dictionary = {}
var _buttons: Dictionary = {}
var _button_action_keys: Dictionary = {}
var _button_payloads: Dictionary = {}
var _button_labels: Dictionary = {}
var _time_speed_group := ButtonGroup.new()
var _last_rejection := PackedStringArray()
var _asset_registry: Dictionary = {}
var _asset_registry_ready := false
var _skin_root: Control
var _skin_nodes: Dictionary = {}
var _time_control_panel_face: TextureRect
var _selected_time_control_id := ""
var _time_control_state_tween: Tween
var _guide_overlay: Control
var _show_layout_guides := false
var _avatar_mode_active := false
var _resident_directory: ResidentDirectoryDrawer
var _place_directory: PlaceDirectoryDrawer
var _far_resident_activity_layer: TownFarResidentActivityLayer
var _anchor_provider: Object
var _indoor_focus_active := false
# A1 探针:仅 AI_TOWN_UI_FRAME_PROBE=1 时加载,关闭时保持 null、零开销。
var _frame_probe: GDScript = null


func _ready() -> void:
	if OS.get_environment("AI_TOWN_UI_FRAME_PROBE") == "1":
		_frame_probe = load("res://world/presentation/ui/TownUiFrameProbe.gd")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_time_speed_group.allow_unpress = false
	_load_asset_registry()
	_build_runtime_skin()
	_build_resident_directory()
	_build_place_directory()
	_build_controls()
	_build_far_resident_activity_layer()
	if _layout_guides_allowed():
		_build_guide_overlay()
		_show_layout_guides = (
			OS.get_environment("AI_TOWN_HUD_RUNTIME_GUIDES") == "1"
		)
	resized.connect(_apply_layout)
	_apply_layout()


func bind_town_ui_adapter(adapter: Object) -> void:
	_anchor_provider = adapter if is_instance_valid(adapter) else null
	if is_instance_valid(_far_resident_activity_layer):
		_far_resident_activity_layer.bind_anchor_provider(_anchor_provider)


func _build_resident_directory() -> void:
	_resident_directory = RESIDENT_DIRECTORY_SCENE.instantiate() as ResidentDirectoryDrawer
	_resident_directory.name = &"ResidentDirectoryDrawer"
	_resident_directory.visible = false
	_resident_directory.resident_requested.connect(
		_on_resident_directory_resident_requested
	)
	add_child(_resident_directory)


func _build_place_directory() -> void:
	_place_directory = PLACE_DIRECTORY_SCENE.instantiate() as PlaceDirectoryDrawer
	_place_directory.name = &"PlaceDirectoryDrawer"
	_place_directory.visible = false
	_place_directory.place_requested.connect(_on_place_directory_place_requested)
	add_child(_place_directory)


func apply_view_model(view_model: Dictionary) -> bool:
	var probe_started_usec := (
		Time.get_ticks_usec() if _frame_probe != null else 0
	)
	var issues := UiViewModel.validate(view_model, "TownHudOverlay")
	if String(view_model.get("scope", "")) != "town_hud":
		issues.append("TownHudOverlay.scope 必须为 town_hud")
	var data_value: Variant = view_model.get("data", {})
	var data := data_value as Dictionary
	issues.append_array(Typography.validate_data_sections(data))
	if require_formal_ready and not bool(data.get("formalReady", false)):
		issues.append("正式 HUD 只接受 data.formalReady=true")
	var incoming_revision := int(view_model.get("revision", -1))
	if incoming_revision < _current_revision:
		issues.append(
			"TownHudOverlay.revision 过期：%d < %d"
			% [incoming_revision, _current_revision]
		)
	if not issues.is_empty():
		_last_rejection = issues
		view_model_rejected.emit(issues)
		if probe_started_usec > 0:
			_frame_probe.record(
				Engine.get_process_frames(),
				"hudApplyUsec",
				Time.get_ticks_usec() - probe_started_usec,
			)
		return false
	_last_rejection = PackedStringArray()
	_current_revision = incoming_revision
	_view_model = view_model.duplicate(true)
	_data = UiViewModel.data_for_render(_view_model, _data)
	_actions = (_view_model.get("actions", {}) as Dictionary).duplicate(true)
	_render()
	if is_instance_valid(_far_resident_activity_layer):
		_far_resident_activity_layer.apply_view_model(_view_model)
	view_model_applied.emit(
		_current_revision,
		UiViewModel.operation_status(_view_model)
	)
	if probe_started_usec > 0:
		_frame_probe.record(
			Engine.get_process_frames(),
			"hudApplyUsec",
			Time.get_ticks_usec() - probe_started_usec,
		)
	return true


func current_revision() -> int:
	return _current_revision


func last_rejection() -> PackedStringArray:
	return _last_rejection.duplicate()


func is_formal_ready() -> bool:
	return (
		_asset_registry_ready
		and Typography.FORMAL_READY
		and preview_font != null
	)


func audit_snapshot() -> Dictionary:
	var label_records: Array = []
	for id: String in _labels:
		var label := _labels[id] as Label
		label_records.append({
			"id": id,
			"rect": label.get_rect(),
			"visible": label.visible,
			"text": label.text,
			"fontSize": label.get_theme_font_size("font_size"),
			"drawsVisibleBorder": false,
		})
	var button_records: Array = []
	for id: String in _buttons:
		var button := _buttons[id] as Button
		button_records.append({
			"id": id,
			"rect": button.get_rect(),
			"visible": button.visible,
			"disabled": button.disabled,
			"toggleMode": button.toggle_mode,
			"buttonPressed": button.button_pressed,
			"actionKey": String(_button_action_keys.get(id, "")),
			"payload": (
				(_button_payloads.get(id, {}) as Dictionary).duplicate(true)
			),
			"toolbarSlotId": String(button.get_meta("toolbar_slot_id", "")),
			"toolbarToolId": String(button.get_meta("toolbar_tool_id", "")),
			"drawsVisibleBorder": false,
			"focusFeedback": "fill_only",
		})
	var selected_time_control_face := _time_control_panel_face
	return {
		"revision": _current_revision,
		"formalReady": is_formal_ready(),
		"rootVisible": visible,
		"visibleInTree": is_visible_in_tree(),
		"mouseFilter": mouse_filter,
		"lastRejection": Array(_last_rejection),
		"typographyRevision": Typography.REVISION,
		"typographyFormalReady": Typography.FORMAL_READY,
		"runtimeThemePath": RUNTIME_FONT_PATH,
		"runtimePanelPath": ASSET_REGISTRY_PATH,
		"runtimeShellPath": OUTER_SHELL_TEXTURE.resource_path,
		"assetRegistryPath": ASSET_REGISTRY_PATH,
		"assetRegistryReady": _asset_registry_ready,
		"assetRegistryId": String(_asset_registry.get("registryId", "")),
		"originalSourceProvenancePath": ORIGINAL_SOURCE_PROVENANCE_PATH,
		"visualStatus": RUNTIME_VISUAL_STATUS,
		"invalidSubstituteRemoved": true,
		"breakpoint": _layout.get("breakpoint", &""),
		"rootScale": scale,
		"layoutMode": _layout.get("layoutMode", ""),
		"safeRect": _layout.get("safeRect", Rect2()),
		"textSlots": Typography.text_slots(_layout),
		"targetSlots": Typography.target_slots(_layout),
		"labels": label_records,
		# Kept as an empty compatibility field for existing report readers.
		# The retired far-marker labels are no longer mounted.
		"lodLabels": [],
		"buttons": button_records,
		"timeControlPressedState": {
			"buttonId": _selected_time_control_id,
			"visible": (
				is_instance_valid(selected_time_control_face)
				and selected_time_control_face.visible
			),
			"rect": (
				selected_time_control_face.get_rect()
				if is_instance_valid(selected_time_control_face)
				else Rect2()
			),
			"assetPath": (
				_time_control_asset_path(selected_time_control_face.texture)
				if (
					is_instance_valid(selected_time_control_face)
					and selected_time_control_face.texture != null
				)
				else ""
			),
			"feedback": "confirmed_raised_to_recessed_texture_swap",
			"stateDesign": "imagegen_complete_panel_selected_state_assets",
			"renderMode": "detached_single_panel_texture_swap",
			"mountedFaceCount": 1 if is_instance_valid(_time_control_panel_face) else 0,
			"baseShellHasBakedTimeControls": false,
			"overlapSourcePx": 0,
			"sourceRectsOverlap": false,
			"renderOrderMutation": false,
		},
		"densityBand": _density_band(),
		"residentOverlayCount": (
			((_data.get("residentOverlays", {}) as Dictionary)
			.get("items", []) as Array).size()
		),
		"residentAggregateCount": int(
			(_data.get("residentOverlays", {}) as Dictionary)
			.get("aggregateCount", 0)
		),
		"offscreenActivityCount": (
			((_data.get("offscreenActivity", {}) as Dictionary)
			.get("items", []) as Array).size()
		),
		"offscreenActivityAggregateCount": int(
			(_data.get("offscreenActivity", {}) as Dictionary)
			.get("aggregateCount", 0)
		),
		"visibleBorderOwnerCount": _visible_border_owner_count(),
		"registeredStyleBoxTextureCount": 0,
		"runtimeSkinNodeCount": _runtime_skin_node_count(self),
		"runtimeVisualReady": is_formal_ready(),
		"layoutGuidesMounted": is_instance_valid(_guide_overlay),
		"layoutGuidesVisible": _show_layout_guides,
		"indoorFocusActive": _indoor_focus_active,
		"runtimeSkinVisible": (
			is_instance_valid(_skin_root) and _skin_root.visible
		),
		"retiredOverlayNodeCount": 0,
		"singleResidentBubbleOwner": is_instance_valid(
			_far_resident_activity_layer
		),
		"sourceHashes": _registered_source_hashes(),
		"farResidentActivityLayer": (
			_far_resident_activity_layer.audit_snapshot()
			if is_instance_valid(_far_resident_activity_layer)
			else {}
		),
		"residentBubbleLayer": {},
	}


func _time_control_asset_path(texture: Texture2D) -> String:
	if texture is AtlasTexture:
		var atlas := (texture as AtlasTexture).atlas
		return atlas.resource_path if atlas != null else ""
	return texture.resource_path if texture != null else ""


func set_layout_guides_visible(enabled: bool) -> void:
	_show_layout_guides = enabled and _layout_guides_allowed()
	if is_instance_valid(_guide_overlay):
		_guide_overlay.visible = _show_layout_guides
		_guide_overlay.queue_redraw()
	if is_instance_valid(_far_resident_activity_layer):
		_far_resident_activity_layer.set_layout_guides_visible(
			_show_layout_guides
		)


func set_indoor_focus_active(active: bool) -> void:
	if _indoor_focus_active == active:
		return
	_indoor_focus_active = active
	if active:
		if is_instance_valid(_resident_directory):
			_resident_directory.visible = false
		if is_instance_valid(_place_directory):
			_place_directory.visible = false
	_update_visibility()
	_update_runtime_skin_visibility()


func _build_far_resident_activity_layer() -> void:
	_far_resident_activity_layer = (
		FAR_RESIDENT_ACTIVITY_SCENE.instantiate()
		as TownFarResidentActivityLayer
	)
	_far_resident_activity_layer.name = &"FarResidentActivityLayer"
	# Keep map-semantic bubbles in the ordinary HUD stacking context. Formal
	# pages are mounted after the persistent HUD and must always cover them.
	_far_resident_activity_layer.z_index = 0
	_far_resident_activity_layer.safe_insets = safe_insets
	_far_resident_activity_layer.bind_anchor_provider(_anchor_provider)
	_far_resident_activity_layer.intent_requested.connect(
		_on_far_resident_activity_intent_requested
	)
	add_child(_far_resident_activity_layer)


func _on_far_resident_activity_intent_requested(
	intent: StringName,
	payload: Dictionary
) -> void:
	intent_requested.emit(intent, payload.duplicate(true))


func _layout_guides_allowed() -> bool:
	# Runtime guides belong only to explicit HUD capture/preflight processes.
	# A shipped formal session must stay free of debug geometry even when a
	# stale shell environment still contains AI_TOWN_HUD_RUNTIME_GUIDES=1.
	return (
		OS.get_environment("AI_TOWN_INTERNAL_PLAYTEST") == "1"
		or not require_formal_ready
	)


func _load_asset_registry() -> void:
	_asset_registry = {}
	_asset_registry_ready = false
	if not FileAccess.file_exists(ASSET_REGISTRY_PATH):
		push_error("HUD runtime asset registry missing: %s" % ASSET_REGISTRY_PATH)
		return
	var file := FileAccess.open(ASSET_REGISTRY_PATH, FileAccess.READ)
	if file == null:
		push_error("HUD runtime asset registry cannot be opened")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("HUD runtime asset registry must be a Dictionary")
		return
	_asset_registry = (parsed as Dictionary).duplicate(true)
	var rules := _asset_registry.get("rules", {}) as Dictionary
	_asset_registry_ready = (
		String(_asset_registry.get("runtimeScene", ""))
		== "res://ui/town/hud/runtime/TownHudOverlay.tscn"
		and not bool(rules.get("wholeReviewScreenshotUsed", true))
		and not bool(rules.get("commonPaperWoodUsed", true))
		and not bool(rules.get("codeDrawnFrameUsed", true))
		and not bool(rules.get("defaultThemeUsed", true))
		and not bool(rules.get("sourceBytesModified", true))
	)
	if not _asset_registry_ready:
		push_error("HUD runtime asset registry violates the original-asset gate")


func _build_runtime_skin() -> void:
	_skin_root = Control.new()
	_skin_root.name = &"OriginalHudRuntimeSkin"
	_skin_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_skin_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_skin_root)

	var outer := NinePatchRect.new()
	outer.name = &"ConfirmedObserverV5StaticShell"
	outer.texture = OUTER_SHELL_TEXTURE
	outer.patch_margin_left = 20
	outer.patch_margin_top = 740
	outer.patch_margin_right = 20
	outer.patch_margin_bottom = 200
	outer.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	outer.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	outer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.set_meta(
		"asset_id",
		"ui.town.hud.observer-shell.time-panel-detached-v6",
	)
	outer.set_meta("visible_border_owner", true)
	_skin_root.add_child(outer)
	_skin_nodes["outer_shell"] = outer

	_time_control_panel_face = TextureRect.new()
	_time_control_panel_face.name = &"TimeControlPanelVisual"
	_time_control_panel_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_time_control_panel_face.stretch_mode = TextureRect.STRETCH_SCALE
	_time_control_panel_face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_time_control_panel_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var time_panel_material := ShaderMaterial.new()
	var time_panel_shader := Shader.new()
	time_panel_shader.code = TIME_CONTROL_BACKGROUND_MASK_SHADER
	time_panel_material.shader = time_panel_shader
	_time_control_panel_face.material = time_panel_material
	_time_control_panel_face.visible = false
	_time_control_panel_face.set_meta(
		"asset_id",
		"ui.town.hud.time-control-panel.imagegen-v10",
	)
	_time_control_panel_face.set_meta("visible_border_owner", false)
	_skin_root.add_child(_time_control_panel_face)
	_skin_nodes["time_control_panel_face"] = _time_control_panel_face


func _build_guide_overlay() -> void:
	_guide_overlay = Control.new()
	_guide_overlay.name = &"HudRuntimeSafeAreaGuides"
	_guide_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_guide_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_guide_overlay.z_index = 1000
	_guide_overlay.visible = false
	_guide_overlay.draw.connect(_draw_layout_guides.bind(_guide_overlay))
	add_child(_guide_overlay)


func _draw_layout_guides(canvas: Control) -> void:
	if not _show_layout_guides:
		return
	var safe_rect := _layout.get("safeRect", Rect2()) as Rect2
	canvas.draw_rect(safe_rect, Color("42d9ff"), false, 2.0)
	for frame_value: Variant in (_layout.get("frames", {}) as Dictionary).values():
		var frame_rect := frame_value as Rect2
		if frame_rect.has_area():
			canvas.draw_rect(frame_rect, Color("ffd166"), false, 2.0)
	for slot_value: Variant in _layout.get("textSlots", []):
		var slot := slot_value as Dictionary
		var rect := slot.get("rect", Rect2()) as Rect2
		if rect.has_area():
			canvas.draw_rect(rect, Color("6dff8d"), false, 2.0)
	for target_value: Variant in _layout.get("targets", []):
		var target := target_value as Dictionary
		var rect := target.get("rect", Rect2()) as Rect2
		if rect.has_area():
			canvas.draw_rect(rect, Color("ff5ad6"), false, 1.0)


func _visible_border_owner_count() -> int:
	var count := 0
	for value: Variant in _skin_nodes.values():
		var node := value as CanvasItem
		if (
			node != null
			and node.visible
			and bool(node.get_meta("visible_border_owner", false))
		):
			count += 1
	return count


func _registered_source_hashes() -> Dictionary:
	var hashes := {}
	for source_value: Variant in _asset_registry.get("sources", []):
		var source := source_value as Dictionary
		hashes[String(source.get("path", ""))] = String(
			source.get("sha256", "")
		)
	return hashes


func _runtime_skin_node_count(node: Node) -> int:
	var count := 0
	for child: Node in node.get_children():
		if (
			child is TextureRect
			or child is NinePatchRect
			or child is Panel
			or child is PanelContainer
		):
			count += 1
		count += _runtime_skin_node_count(child)
	return count


func _build_controls() -> void:
	_make_label("time_weather", &"hud_body", HORIZONTAL_ALIGNMENT_CENTER)
	for target_id: String in [
		"weatherChange",
		"nav_residents",
		"nav_places",
		"nav_relationships",
		"nav_log",
		"nav_bulletin",
		"nav_settings",
		"camera_fit",
		"camera_zoom_in",
		"camera_zoom_out",
		"time_pause",
		"time_speed_1",
		"time_speed_2",
		"time_speed_3",
		"avatar_toggle",
	]:
		_make_button(target_id)


func _make_label(
	id: String,
	role: StringName,
	alignment: HorizontalAlignment
) -> void:
	var label := Label.new()
	label.name = StringName(id.to_pascal_case())
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.set_meta("font_role", role)
	label.set_meta("draws_visible_border", false)
	Typography.configure_label(label, role, preview_font)
	add_child(label)
	_labels[id] = label


func focus_default_control() -> void:
	for button_id: String in [
		"weatherChange",
		"nav_bulletin",
		"nav_log",
		"avatar_toggle",
		"camera_fit",
	]:
		if not _buttons.has(button_id):
			continue
		var button := _buttons[button_id] as Button
		if button.visible and not button.disabled and button.focus_mode != Control.FOCUS_NONE:
			button.grab_focus()
			return


func _make_button(id: String) -> void:
	var button := Button.new()
	button.name = StringName("%sHitTarget" % id.to_pascal_case())
	button.text = ""
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.set_meta("draws_visible_border", false)
	button.set_meta("focus_feedback", "fill_only")
	if id == "time_pause" or id.begins_with("time_speed_"):
		# These controls play only after World confirms the operation, avoiding
		# duplicate button-down and operation-success cues.
		button.add_to_group("audio_silent")
	var empty := StyleBoxEmpty.new()
	for state_name: String in [
		"normal",
		"hover",
		"pressed",
		"disabled",
		"focus",
	]:
		button.add_theme_stylebox_override(state_name, empty)
	button.pressed.connect(_on_button_pressed.bind(id))
	add_child(button)
	_buttons[id] = button


func _apply_layout() -> void:
	_layout = Typography.layout_for(size, safe_insets, physical_scale)
	if is_instance_valid(_far_resident_activity_layer):
		_far_resident_activity_layer.safe_insets = safe_insets
	_apply_runtime_skin_layout()
	_apply_resident_directory_layout()
	_apply_place_directory_layout()
	for slot_value: Variant in _layout.get("textSlots", []):
		var slot := slot_value as Dictionary
		var id := String(slot["id"])
		if not _labels.has(id):
			continue
		var label := _labels[id] as Label
		var rect := slot["rect"] as Rect2
		label.position = rect.position
		label.size = rect.size
		label.visible = not rect.has_area() and false
		if rect.has_area():
			label.visible = _label_should_be_visible(id)
	for target_value: Variant in _layout.get("targets", []):
		var target := target_value as Dictionary
		var id := String(target["id"])
		if not _buttons.has(id):
			continue
		var button := _buttons[id] as Button
		var rect := target["rect"] as Rect2
		button.position = rect.position
		button.size = rect.size
		button.visible = rect.has_area() and _button_should_be_visible(id)
	if is_instance_valid(_guide_overlay):
		_guide_overlay.visible = _show_layout_guides
		_guide_overlay.queue_redraw()
	if not _view_model.is_empty():
		_render()


func _apply_resident_directory_layout() -> void:
	if not is_instance_valid(_resident_directory):
		return
	var safe := _layout.get("safeRect", Rect2(Vector2.ZERO, size)) as Rect2
	var nav_rect := _layout_target_rect("nav_residents")
	var breakpoint_id := StringName(_layout.get("breakpoint", &""))
	var drawer_height: float
	var drawer_width: float
	var drawer_position: Vector2
	if breakpoint_id == &"compact_portrait":
		drawer_height = minf(720.0, safe.size.y - 24.0)
		drawer_width = minf(safe.size.x - 24.0, drawer_height * 0.666667)
		drawer_position = Vector2(
			safe.get_center().x - drawer_width * 0.5,
			safe.get_center().y - drawer_height * 0.5,
		)
	else:
		drawer_height = minf(720.0, safe.size.y - 164.0)
		drawer_height = maxf(drawer_height, 480.0)
		drawer_width = drawer_height * 0.666667
		drawer_position = Vector2(
			nav_rect.end.x + 8.0,
			maxf(safe.position.y + 72.0, nav_rect.position.y - 8.0),
		)
		if drawer_position.x + drawer_width > safe.end.x - 120.0:
			drawer_width = maxf(320.0, safe.end.x - 120.0 - drawer_position.x)
	_resident_directory.position = drawer_position.round()
	_resident_directory.size = Vector2(drawer_width, drawer_height).round()


func _apply_place_directory_layout() -> void:
	if not is_instance_valid(_place_directory):
		return
	var safe := _layout.get("safeRect", Rect2(Vector2.ZERO, size)) as Rect2
	var nav_rect := _layout_target_rect("nav_places")
	var breakpoint_id := StringName(_layout.get("breakpoint", &""))
	var drawer_height: float
	var drawer_width: float
	var drawer_position: Vector2
	if breakpoint_id == &"compact_portrait":
		drawer_height = minf(720.0, safe.size.y - 24.0)
		drawer_width = minf(safe.size.x - 24.0, drawer_height * 0.666667)
		drawer_position = Vector2(
			safe.get_center().x - drawer_width * 0.5,
			safe.get_center().y - drawer_height * 0.5,
		)
	else:
		drawer_height = minf(720.0, safe.size.y - 164.0)
		drawer_height = maxf(drawer_height, 480.0)
		drawer_width = drawer_height * 0.666667
		drawer_position = Vector2(
			nav_rect.end.x + 8.0,
			maxf(safe.position.y + 72.0, nav_rect.position.y - 107.0),
		)
		if drawer_position.x + drawer_width > safe.end.x - 120.0:
			drawer_width = maxf(320.0, safe.end.x - 120.0 - drawer_position.x)
	_place_directory.position = drawer_position.round()
	_place_directory.size = Vector2(drawer_width, drawer_height).round()


func _apply_runtime_skin_layout() -> void:
	if not is_instance_valid(_skin_root):
		return
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var outer := _skin_nodes.get("outer_shell") as NinePatchRect
	if outer == null:
		return
	var uniform_scale := minf(
		size.x / HUD_REFERENCE_SIZE.x,
		size.y / HUD_REFERENCE_SIZE.y,
	)
	if size.x / size.y < HUD_REFERENCE_SIZE.x / HUD_REFERENCE_SIZE.y:
		uniform_scale = size.x / HUD_REFERENCE_SIZE.x
		outer.position = Vector2.ZERO
		outer.size = Vector2(
			HUD_REFERENCE_SIZE.x,
			size.y / uniform_scale,
		)
	else:
		outer.position = (size - HUD_REFERENCE_SIZE * uniform_scale) * 0.5
		outer.size = HUD_REFERENCE_SIZE
	outer.scale = Vector2.ONE * uniform_scale


func _density_band() -> String:
	var value := String(
		(_data.get("density", {}) as Dictionary).get("zoomBand", "")
	)
	return value if value in ["far", "middle", "near"] else "near"


func _render() -> void:
	if _data.is_empty():
		return
	var time_weather := _data.get("timeWeather", {}) as Dictionary
	var day := int(time_weather.get("day", 0))
	var clock := String(time_weather.get("clock", ""))
	var period_label := String(time_weather.get("periodLabel", "")).strip_edges()
	var weather_label := String(time_weather.get("weatherLabel", "")).strip_edges()
	var status_parts: Array[String] = []
	if day > 0:
		status_parts.append("第%d天" % day)
	if not clock.is_empty():
		status_parts.append(clock)
	if StringName(_layout.get("breakpoint", &"")) == &"desktop_wide":
		if not period_label.is_empty():
			status_parts.append(period_label)
	if not weather_label.is_empty():
		status_parts.append(weather_label)
	_set_text(
		"time_weather",
		" ".join(status_parts) if not status_parts.is_empty() else "时间未就绪"
	)
	if is_instance_valid(_resident_directory):
		_resident_directory.apply_directory(
			_data.get("residentDirectory", {}) as Dictionary
		)
	if is_instance_valid(_place_directory):
		_place_directory.apply_directory(
			_data.get("placeDirectory", {}) as Dictionary
		)
	_apply_runtime_skin_layout()
	_update_visibility()
	_configure_actions()
	_update_runtime_skin_visibility()


func _configure_actions() -> void:
	_configure_button("weatherChange", "weatherChange", {})
	_configure_resident_directory_button()
	_configure_place_directory_button()
	_configure_button("nav_relationships", "openResidentManagement", {})
	_configure_button("nav_log", "openTownLog", {})
	_configure_button("nav_bulletin", "openBulletin", {})
	_configure_button("nav_settings", "openMore", {})
	_configure_button("avatar_toggle", "toggleAvatar", {})
	_configure_button("camera_fit", "cameraReset", {})
	_configure_button("camera_zoom_in", "cameraZoomIn", {})
	_configure_button("camera_zoom_out", "cameraZoomOut", {})
	var paused := bool(
		(_data.get("pausePrompt", {}) as Dictionary).get("visible", false)
	)
	_configure_button("time_pause", "resume" if paused else "pause", {})
	_configure_time_speed_buttons()
	_update_time_control_pressed_state(paused)
	_set_control_tooltips()


func _configure_time_speed_buttons() -> void:
	var time_weather := _data.get("timeWeather", {}) as Dictionary
	var current_speed := int(round(float(time_weather.get("simulationSpeed", 1))))
	for button_id: String in TIME_SPEED_CONTROLS:
		var config := TIME_SPEED_CONTROLS[button_id] as Dictionary
		var multiplier := int(config.get("multiplier", 1))
		_configure_button(
			button_id,
			String(config.get("actionKey", "")),
			{"multiplier": multiplier},
		)
		var button := _buttons.get(button_id) as Button
		if button == null:
			continue
		button.toggle_mode = true
		button.button_group = _time_speed_group
		button.set_pressed_no_signal(current_speed == multiplier)


func _update_time_control_pressed_state(paused: bool) -> void:
	var next_id := "time_pause" if paused else _confirmed_time_speed_button_id()
	if (
		next_id.is_empty()
		or not TIME_CONTROL_PANEL_TEXTURES.has(next_id)
		or not _button_should_be_visible(next_id)
	):
		next_id = ""
	var changed := next_id != _selected_time_control_id
	_selected_time_control_id = next_id
	var visual_rect := _time_control_panel_visual_rect()
	_time_control_panel_face.texture = _time_control_panel_texture(next_id)
	_time_control_panel_face.position = visual_rect.position
	_time_control_panel_face.size = visual_rect.size
	_time_control_panel_face.pivot_offset = visual_rect.size * 0.5
	_time_control_panel_face.visible = (
		visual_rect.has_area()
		and not next_id.is_empty()
	)
	_time_control_panel_face.modulate = Color.WHITE
	if not changed:
		return
	if _time_control_state_tween != null:
		_time_control_state_tween.kill()
	var selected_face := _time_control_panel_face
	if not is_instance_valid(selected_face):
		return
	selected_face.modulate = Color(1.16, 1.08, 0.92, 1.0)
	_time_control_state_tween = create_tween()
	_time_control_state_tween.tween_property(
		selected_face,
		"modulate",
		Color.WHITE,
		0.09,
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _time_control_panel_texture(control_id: String) -> Texture2D:
	var source := TIME_CONTROL_PANEL_TEXTURES.get(control_id) as Texture2D
	if source == null:
		return null
	var cropped := AtlasTexture.new()
	cropped.atlas = source
	cropped.region = Rect2(37.0, 0.0, 120.0, 401.0)
	return cropped


func _confirmed_time_speed_button_id() -> String:
	var time_weather := _data.get("timeWeather", {}) as Dictionary
	var current_speed := int(round(float(time_weather.get("simulationSpeed", 1))))
	return "time_speed_%d" % clampi(current_speed, 1, 3)


func _time_control_panel_visual_rect() -> Rect2:
	if size.x <= 0.0 or size.y <= 0.0:
		return Rect2()
	var uniform_scale := minf(
		size.x / HUD_REFERENCE_SIZE.x,
		size.y / HUD_REFERENCE_SIZE.y,
	)
	if size.x / size.y < HUD_REFERENCE_SIZE.x / HUD_REFERENCE_SIZE.y:
		return Rect2(
			TIME_CONTROL_PANEL_SOURCE_RECT.position * uniform_scale,
			TIME_CONTROL_PANEL_SOURCE_RECT.size * uniform_scale,
		)
	var shell_size := HUD_REFERENCE_SIZE * uniform_scale
	var shell_origin := (size - shell_size) * 0.5
	return Rect2(
		shell_origin + TIME_CONTROL_PANEL_SOURCE_RECT.position * uniform_scale,
		TIME_CONTROL_PANEL_SOURCE_RECT.size * uniform_scale,
	)


func _configure_resident_directory_button() -> void:
	if not _buttons.has("nav_residents"):
		return
	var directory := _data.get("residentDirectory", {}) as Dictionary
	var enabled := (
		bool(directory.get("available", false))
		and not (directory.get("items", []) as Array).is_empty()
	)
	var button := _buttons["nav_residents"] as Button
	button.disabled = not enabled
	button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	button.tooltip_text = "居民目录" if enabled else "居民目录暂不可用"
	_button_action_keys["nav_residents"] = "__resident_directory"
	_button_payloads["nav_residents"] = {}


func _configure_place_directory_button() -> void:
	if not _buttons.has("nav_places"):
		return
	var directory := _data.get("placeDirectory", {}) as Dictionary
	var enabled := (
		bool(directory.get("available", false))
		and not (directory.get("items", []) as Array).is_empty()
	)
	var button := _buttons["nav_places"] as Button
	button.disabled = not enabled
	button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	button.tooltip_text = "地点与房屋" if enabled else "地点目录暂不可用"
	_button_action_keys["nav_places"] = "__place_directory"
	_button_payloads["nav_places"] = {}


func _set_control_tooltips() -> void:
	var tooltips := {
		"weatherChange": "天气与时间",
		"nav_places": "地点与房屋",
		"nav_log": "小镇日志",
		"nav_relationships": "居民管理",
		"nav_bulletin": "公告栏",
		"nav_settings": "局内设置",
		"avatar_toggle": "进入化身模式",
		"camera_fit": "显示完整小镇",
		"camera_zoom_in": "放大观察",
		"camera_zoom_out": "缩小观察",
		"time_pause": "暂停或继续小镇时间",
		"time_speed_1": "切换为 1 倍速度",
		"time_speed_2": "切换为 2 倍速度",
		"time_speed_3": "切换为 3 倍速度",
	}
	for button_id: String in tooltips:
		if not _buttons.has(button_id):
			continue
		var button := _buttons[button_id] as Button
		if not button.disabled:
			button.tooltip_text = String(tooltips[button_id])


func _configure_button(
	button_id: String,
	action_key: String,
	payload: Dictionary
) -> void:
	if not _buttons.has(button_id):
		return
	var button := _buttons[button_id] as Button
	var action := UiViewModel.action(_view_model, action_key)
	var enabled := UiViewModel.action_enabled(action)
	button.disabled = not enabled
	button.focus_mode = (
		Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	)
	button.tooltip_text = (
		UiViewModel.disabled_reason(action) if not enabled else action_key
	)
	_button_action_keys[button_id] = action_key
	_button_payloads[button_id] = payload.duplicate(true)


func _on_button_pressed(button_id: String) -> void:
	var action_key := String(_button_action_keys.get(button_id, ""))
	if action_key.is_empty():
		return
	if action_key == "__resident_directory":
		_toggle_resident_directory()
		return
	if action_key == "__place_directory":
		_toggle_place_directory()
		return
	if button_id == "nav_relationships":
		_close_directories()
	var action := UiViewModel.action(_view_model, action_key)
	if not UiViewModel.action_enabled(action):
		return
	var intent := StringName(action.get("intent", ""))
	if intent == &"":
		return
	intent_requested.emit(
		intent,
		(_button_payloads.get(button_id, {}) as Dictionary).duplicate(true)
	)


func _on_resident_directory_resident_requested(resident_id: String) -> void:
	var action := UiViewModel.action(_view_model, "cameraFollow")
	if not UiViewModel.action_enabled(action):
		return
	var intent := StringName(action.get("intent", ""))
	if intent == &"":
		return
	intent_requested.emit(intent, {"residentId": resident_id})


func _on_place_directory_place_requested(place_name: String) -> void:
	var action := UiViewModel.action(_view_model, "openPlaceFocus")
	if not UiViewModel.action_enabled(action):
		return
	var intent := StringName(action.get("intent", ""))
	if intent == &"":
		return
	_close_directories()
	intent_requested.emit(intent, {"placeName": place_name})


func _toggle_resident_directory() -> void:
	if not is_instance_valid(_resident_directory):
		return
	var opening := not _resident_directory.visible
	if is_instance_valid(_place_directory):
		_place_directory.visible = false
	if opening:
		_resident_directory.open()
	else:
		_resident_directory.close()
	_update_visibility()
	_update_runtime_skin_visibility()


func _toggle_place_directory() -> void:
	if not is_instance_valid(_place_directory):
		return
	var opening := not _place_directory.visible
	if is_instance_valid(_resident_directory):
		_resident_directory.visible = false
	if opening:
		_place_directory.open()
	else:
		_place_directory.close()
	_update_visibility()
	_update_runtime_skin_visibility()


func _close_directories() -> void:
	if is_instance_valid(_resident_directory):
		_resident_directory.visible = false
	if is_instance_valid(_place_directory):
		_place_directory.visible = false
	_update_visibility()
	_update_runtime_skin_visibility()


func set_presentation_mode(mode: String) -> void:
	var next := mode.strip_edges().to_lower() == "avatar"
	if _avatar_mode_active == next:
		return
	_avatar_mode_active = next
	if _avatar_mode_active:
		if is_instance_valid(_resident_directory):
			_resident_directory.visible = false
		if is_instance_valid(_place_directory):
			_place_directory.visible = false
	_update_visibility()
	_update_runtime_skin_visibility()


func _update_visibility() -> void:
	for id: String in _labels:
		var label := _labels[id] as Label
		label.visible = (
			not _avatar_mode_active
			and _layout_text_rect(id).has_area()
			and _label_should_be_visible(id)
		)
	for id: String in _buttons:
		var button := _buttons[id] as Button
		button.visible = (
			not _avatar_mode_active
			and _layout_target_rect(id).has_area()
			and _button_should_be_visible(id)
		)
	if is_instance_valid(_far_resident_activity_layer):
		_far_resident_activity_layer.render_enabled = (
			not _resident_directory_open()
		)


func _update_runtime_skin_visibility() -> void:
	if is_instance_valid(_skin_root):
		_skin_root.visible = not _avatar_mode_active
	if _data.is_empty():
		for id: String in _skin_nodes:
			(_skin_nodes[id] as CanvasItem).visible = (
				not _avatar_mode_active and id == "outer_shell"
			)
		return
	_set_skin_visibility("outer_shell", true)


func _resident_directory_open() -> bool:
	return (
		(is_instance_valid(_resident_directory) and _resident_directory.visible)
		or (is_instance_valid(_place_directory) and _place_directory.visible)
	)


func _set_skin_visibility(id: String, value: bool) -> void:
	if not _skin_nodes.has(id):
		return
	var node := _skin_nodes[id] as Control
	node.visible = value and node.size.x > 0.0 and node.size.y > 0.0


func _layout_text_rect(id: String) -> Rect2:
	for slot_value: Variant in _layout.get("textSlots", []):
		var slot := slot_value as Dictionary
		if String(slot.get("id", "")) == id:
			return slot.get("rect", Rect2()) as Rect2
	return Rect2()


func _layout_target_rect(id: String) -> Rect2:
	for target_value: Variant in _layout.get("targets", []):
		var target := target_value as Dictionary
		if String(target.get("id", "")) == id:
			return target.get("rect", Rect2()) as Rect2
	return Rect2()


func _label_should_be_visible(id: String) -> bool:
	return (
		not _data.is_empty()
		and Typography.FORMAL_READY
		and id == "time_weather"
	)


func _button_should_be_visible(_id: String) -> bool:
	return not _data.is_empty() and Typography.FORMAL_READY


func _set_text(id: String, text_value: String) -> void:
	if _labels.has(id):
		(_labels[id] as Label).text = text_value
