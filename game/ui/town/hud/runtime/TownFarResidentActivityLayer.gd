class_name TownFarResidentActivityLayer
extends Control


const UiViewModel := preload("res://ui/common/AiTownUiViewModel.gd")
const FONT := preload(
	"res://assets/fonts/zheng_ge_dian_hei_16/"
	+ "ZhengGeDianHei-16.ttf"
)
const CONVERSATION_SHELL := preload(
	"res://assets/ui/town/hud/runtime/far_transient_components_v2/"
	+ "spectator_conversation_static.png"
)
const THOUGHT_SHELL := preload(
	"res://assets/ui/town/hud/runtime/mid_near_resident_bubbles_v1/"
	+ "public_thought_bubble.png"
)
const ELLIPSIS_SHELL := preload(
	"res://assets/ui/town/hud/runtime/far_activity_bubbles_v4/"
	+ "activity_ellipsis_shell.png"
)
const ACTION_SHELL := preload(
	"res://assets/ui/town/hud/runtime/far_activity_bubbles_v4/"
	+ "activity_action_shell.png"
)
const LEGACY_SEMANTIC_ICONS := {
	"walking": preload(
		"res://assets/ui/town/hud/runtime/action_icons_readable_v4/legacy/walking.png"
	),
	"eating": preload(
		"res://assets/ui/town/hud/runtime/action_icons_readable_v4/legacy/eating.png"
	),
	"working": preload(
		"res://assets/ui/town/hud/runtime/action_icons_readable_v4/legacy/working.png"
	),
	"tired": preload(
		"res://assets/ui/town/hud/runtime/action_icons_readable_v4/legacy/tired.png"
	),
	"happy": preload(
		"res://assets/ui/town/hud/runtime/action_icons_readable_v4/legacy/happy.png"
	),
	"angry": preload(
		"res://assets/ui/town/hud/runtime/action_icons_readable_v4/legacy/angry.png"
	),
	"observing": preload(
		"res://assets/ui/town/hud/runtime/action_icons_readable_v4/legacy/observing.png"
	),
	"reading": preload(
		"res://assets/ui/town/hud/runtime/action_icons_readable_v4/legacy/reading.png"
	),
}
const TRANSIENT_SNAPSHOT_CONTRACT_READY := true
const INITIAL_SLOT_POOL := 3
const ACTION_ICON_MANIFEST_PATH := (
	"res://assets/ui/town/hud/runtime/action_icons_readable_v4/icon_manifest.json"
)
const ACTION_ICON_FRAME_SIZE := Vector2(32.0, 32.0)
const ACTION_ICON_FRAME_MSEC := 600
const CONVERSATION_SIZE := Vector2(340.0, 133.0)
const THOUGHT_SIZE := Vector2(267.0, 88.0)
const ELLIPSIS_SIZE := Vector2(60.0, 56.0)
const ACTION_SIZE := Vector2(60.0, 56.0)
const THOUGHT_TEXT_MAX_LENGTH := 18
const THOUGHT_FONT_SIZE := 20
const SEMANTIC_THOUGHT_PAGE_MAX_UNITS := 16
const SEMANTIC_THOUGHT_PAGE_DURATION_MSEC := 2000
const SEMANTIC_ACTION_FONT_SIZE := 20
const SEMANTIC_ACTION_PAGE_MAX_UNITS := 16
const SEMANTIC_ACTION_PAGE_DURATION_MSEC := 2000
const SEMANTIC_THOUGHT_LINE_MAX_UNITS := 11.0
const SEMANTIC_ACTION_LINE_MAX_UNITS := 8.0
const SEMANTIC_ACTION_LABEL_RECT := Rect2(68.0, 7.0, 177.0, 62.0)
const SEMANTIC_BACKDROP_POSITION := Vector2(13.0, 17.0)
const SEMANTIC_BACKDROP_SIZE := Vector2(46.0, 18.0)
const SEMANTIC_ICON_SIZE := Vector2(32.0, 32.0)
const SEMANTIC_ICON_POSITION := Vector2(14.0, 7.0)
const SEMANTIC_MARKER_SIZE := Vector2(9.0, 9.0)
const SEMANTIC_MARKER_POSITION := Vector2(46.0, 7.0)
const MIN_TOUCH_SIZE := Vector2(48.0, 48.0)
const TRANSIENT_FADE_MSEC := 450
const INK := Color("#3B2416")
# The authored public-thought frame has its pointer at one quarter of the
# frame width. Other resident bubbles currently point from their horizontal
# centre. Keep these values tied to the actual artwork so the pointer, rather
# than the bubble body, follows the resident's head anchor.
const PUBLIC_THOUGHT_TAIL_X_RATIO := 0.25
const CENTERED_TAIL_X_RATIO := 0.5

signal intent_requested(intent: StringName, payload: Dictionary)
signal view_model_applied(revision: int)
signal view_model_rejected(issues: PackedStringArray)

@export var render_enabled := true:
	set(value):
		render_enabled = value
		_update_root_visibility()
@export var safe_insets := Vector4.ZERO:
	set(value):
		safe_insets = value
		if is_node_ready():
			_apply_layout()
var _current_revision := -1
var _view_model: Dictionary = {}
var _data: Dictionary = {}
var _render_input: Dictionary = {}
var _render_input_initialized := false
var _last_rejection := PackedStringArray()
var _slots: Array[Control] = []
var _slot_skins: Array[TextureRect] = []
var _slot_semantic_backdrops: Array[ColorRect] = []
var _slot_icons: Array[TextureRect] = []
var _slot_markers: Array[TextureRect] = []
var _slot_labels: Array[Label] = []
var _slot_behavior_labels: Array[Label] = []
var _slot_buttons: Array[Button] = []
var _slot_items: Array[Dictionary] = []
var _slot_semantic_preview_signatures: Array[String] = []
var _slot_semantic_preview_started_msec: Array[int] = []
var _slot_semantic_preview_pages: Array[int] = []
var _slot_semantic_action_pages: Array[int] = []
var _slot_semantic_preview_modes: Array[String] = []
var _action_icon_frames: Dictionary = {}
var _action_markers: Dictionary = {}
var _shared_animation_frame := 0
var _aggregate_label: Label
var _visible_slot_count := 0
var _render_count := 0
var _show_guides := false
var _anchor_provider: Object
var _anchor_provider_call := Callable()
# 1a:预算截断与聚合计数在消费层按帧执行的结果(供审计与验收读取)。
var _frame_aggregate_count := 0
# 语义底色取自省略号外壳贴图的实际像素；解码整张贴图只做一次。
static var _semantic_backdrop_color := Color(0.0, 0.0, 0.0, 0.0)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_action_icon_catalog()
	_build_slots()
	_build_aggregate_label()
	resized.connect(_apply_layout)
	_apply_layout()
	set_process(true)
	_update_root_visibility()


func bind_anchor_provider(provider: Object) -> void:
	_anchor_provider = (
		provider
		if (
			is_instance_valid(provider)
			and provider.has_method("get_town_hud_resident_head_anchor")
		)
		else null
	)
	_anchor_provider_call = (
		Callable(_anchor_provider, "get_town_hud_resident_head_anchor")
		if _anchor_provider != null
		else Callable()
	)


func apply_view_model(view_model: Dictionary) -> bool:
	var issues := UiViewModel.validate(
		view_model,
		"TownFarResidentActivityLayer"
	)
	if String(view_model.get("scope", "")) != "town_hud":
		issues.append("TownFarResidentActivityLayer.scope 必须为 town_hud")
	var incoming_revision := int(view_model.get("revision", -1))
	if incoming_revision < _current_revision:
		issues.append(
			"TownFarResidentActivityLayer.revision 过期：%d < %d"
			% [incoming_revision, _current_revision]
		)
	if not issues.is_empty():
		_last_rejection = issues
		view_model_rejected.emit(issues)
		return false
	_last_rejection = PackedStringArray()
	_current_revision = incoming_revision
	var next_data := _data_for_render_shallow(view_model, _data)
	var next_render_input := _render_input_for_data(next_data)
	if (
		_render_input_initialized
		and next_render_input == _render_input
	):
		_view_model = view_model.duplicate(false)
		_data = next_data
		_refresh_live_slot_fields()
		_update_root_visibility()
		view_model_applied.emit(_current_revision)
		return true
	_render_input = next_render_input
	_render_input_initialized = true
	_view_model = view_model.duplicate(false)
	_data = next_data
	_render()
	view_model_applied.emit(_current_revision)
	return true


func _data_for_render_shallow(
	view_model: Dictionary,
	last_confirmed_data: Dictionary,
) -> Dictionary:
	var incoming := view_model.get("data", {}) as Dictionary
	if (
		UiViewModel.operation_status(view_model) == &"rejected"
		and incoming.is_empty()
	):
		return last_confirmed_data.duplicate(false)
	return incoming.duplicate(false)


func _render_input_for_data(data: Dictionary) -> Dictionary:
	return {
		"farResidentActivity": _stable_overlay_section_signature(
			data.get("farResidentActivity", {}) as Dictionary
		),
		"residentOverlays": _stable_overlay_section_signature(
			data.get("residentOverlays", {}) as Dictionary
		),
		"zoomBand": String(
			(data.get("density", {}) as Dictionary).get(
				"zoomBand",
				"middle",
			)
		),
		"pauseVisible": bool(
			(data.get("pausePrompt", {}) as Dictionary).get(
				"visible",
				false,
			)
		),
	}


func _stable_overlay_section_signature(section: Dictionary) -> Dictionary:
	var items: Array[Dictionary] = []
	for value: Variant in section.get("items", []) as Array:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		# Preserve every visual and interaction field so a newly added bubble
		# property cannot accidentally bypass rendering. Only copy the dictionary
		# shell and remove the live anchor/playback fields handled in-place below.
		var item := (value as Dictionary).duplicate(false)
		for field: String in [
			"screenAnchor",
			"headScreenAnchor",
			"startedAtMsec",
			"expiresAtMsec",
			"confirmedRevision",
		]:
			item.erase(field)
		items.append(item)
	return {
		"available": bool(section.get("available", true)),
		"visibleBudget": int(
			section.get(
				"visibleBudget",
				(section.get("items", []) as Array).size(),
			)
		),
		"aggregateCount": int(section.get("aggregateCount", 0)),
		"items": items,
	}
func _refresh_live_slot_fields() -> void:
	var latest_by_overlay_id := {}
	var far_activity := _data.get("farResidentActivity", {}) as Dictionary
	for value: Variant in far_activity.get("items", []) as Array:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var item := value as Dictionary
		var overlay_id := String(item.get("overlayId", "")).strip_edges()
		if not overlay_id.is_empty():
			latest_by_overlay_id[overlay_id] = item
	var resident_overlays := (
		_data.get("residentOverlays", {}) as Dictionary
	)
	for value: Variant in resident_overlays.get("items", []) as Array:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var item := value as Dictionary
		if String(item.get("contentKind", "")) != "public_thought":
			continue
		var resident_id := String(item.get("residentId", "")).strip_edges()
		var thought_id := String(
			item.get("thoughtId", resident_id)
		).strip_edges()
		if not thought_id.is_empty():
			latest_by_overlay_id["thought:%s" % thought_id] = item
	for index: int in range(_visible_slot_count):
		var current := _slot_items[index]
		var overlay_id := String(
			current.get("overlayId", "")
		).strip_edges()
		if not latest_by_overlay_id.has(overlay_id):
			continue
		var latest := latest_by_overlay_id[overlay_id] as Dictionary
		# Only anchor/timing fields are replaced here. Keep the immutable visual
		# payload shared instead of deep-copying every bubble on each clock tick.
		var refreshed := current.duplicate(false)
		for field: String in [
			"screenAnchor",
			"headScreenAnchor",
			"startedAtMsec",
			"expiresAtMsec",
			"confirmedRevision",
		]:
			if latest.has(field):
				refreshed[field] = latest[field]
			else:
				refreshed.erase(field)
		_slot_items[index] = refreshed


func set_layout_guides_visible(value: bool) -> void:
	_show_guides = value
	queue_redraw()


func audit_snapshot() -> Dictionary:
	var slot_records: Array = []
	for index: int in range(_slots.size()):
		var item := _slot_items[index]
		slot_records.append({
			"index": index,
			"visible": _slots[index].visible,
			"rect": Rect2(_slots[index].position, _slots[index].size),
			"scale": _slots[index].scale,
			"modulate": _slots[index].modulate,
			"kind": String(item.get("kind", "")),
			"residentId": String(item.get("residentId", "")),
			"conversationId": String(item.get("conversationId", "")),
			"semanticKind": String(item.get("semanticKind", "")),
			"anchorPolicy": String(item.get("anchorPolicy", "")),
			"motionPolicy": String(item.get("motionPolicy", "")),
			"headScreenAnchor": _head_screen_anchor(item),
			"tailTip": _tail_tip(index),
			"tailToHeadDistance": _tail_to_head_distance(index, item),
			"expiresAtMsec": int(item.get("expiresAtMsec", -1)),
			"label": _slot_labels[index].text,
			"behaviorLabel": _slot_behavior_labels[index].text,
			"behaviorLabelVisible": _slot_behavior_labels[index].visible,
			"behaviorLabelRect": Rect2(
				_slot_behavior_labels[index].position,
				_slot_behavior_labels[index].size,
			),
			"semanticDisplayMode": _slot_semantic_preview_modes[index],
			"semanticThoughtPage": _slot_semantic_preview_pages[index],
			"semanticThoughtPageCount": _semantic_thought_pages(item).size(),
			"semanticThoughtPages": _semantic_thought_pages(item),
			"semanticActionPage": _slot_semantic_action_pages[index],
			"semanticActionPageCount": _semantic_action_pages(item).size(),
			"semanticActionPages": _semantic_action_pages(item),
			"labelRect": Rect2(
				_slot_labels[index].position,
				_slot_labels[index].size,
			),
			"labelAutowrapMode": _slot_labels[index].autowrap_mode,
			"labelOverrunBehavior": (
				_slot_labels[index].text_overrun_behavior
			),
			"labelClipText": _slot_labels[index].clip_text,
			"labelMaxLinesVisible": (
				_slot_labels[index].max_lines_visible
			),
			"labelFontSize": _slot_labels[index].get_theme_font_size(
				"font_size",
			),
			"labelLineCount": _slot_labels[index].get_line_count(),
			"labelVisibleLineCount": (
				_slot_labels[index].get_visible_line_count()
			),
			"behaviorLabelMaxLinesVisible": (
				_slot_behavior_labels[index].max_lines_visible
			),
			"behaviorLabelLineCount": (
				_slot_behavior_labels[index].get_line_count()
			),
			"behaviorLabelVisibleLineCount": (
				_slot_behavior_labels[index].get_visible_line_count()
			),
			"dotsVisible": false,
			"skinPath": (
				_slot_skins[index].texture.resource_path
				if _slot_skins[index].texture != null
				else ""
			),
			"iconPath": (
				_slot_icons[index].texture.resource_path
				if _slot_icons[index].texture != null
				else ""
			),
			"iconVisible": _slot_icons[index].visible,
			"iconTextureSize": (
				_slot_icons[index].texture.get_size()
				if _slot_icons[index].texture != null
				else Vector2.ZERO
			),
			"iconUsesNativeDisplaySize": (
				_slot_icons[index].texture != null
				and _slot_icons[index].texture.get_size()
					== _slot_icons[index].size
			),
			"iconAtlasPath": (
				(
					_slot_icons[index].texture as AtlasTexture
				).atlas.resource_path
				if _slot_icons[index].texture is AtlasTexture
				else ""
			),
			"markerVisible": _slot_markers[index].visible,
			"markerTextureSize": (
				_slot_markers[index].texture.get_size()
				if _slot_markers[index].texture != null
				else Vector2.ZERO
			),
			"markerUsesNativeDisplaySize": (
				_slot_markers[index].texture != null
				and _slot_markers[index].texture.get_size()
					== _slot_markers[index].size
			),
			"markerPath": (
				_slot_markers[index].texture.resource_path
				if _slot_markers[index].texture != null
				else ""
			),
			"connectorVisible": false,
			"iconRect": Rect2(
				_slot_icons[index].position,
				_slot_icons[index].size
			),
			"markerRect": Rect2(
				_slot_markers[index].position,
				_slot_markers[index].size,
			),
			"semanticIconInsideEllipsisShell": (
				String(item.get("kind", "")) == "semantic_icon"
				and _slot_skins[index].texture == ELLIPSIS_SHELL
				and _slot_icons[index].visible
			),
			"semanticIconInsideActionShell": (
				String(item.get("kind", "")) == "semantic_icon"
				and _slot_skins[index].texture == ACTION_SHELL
				and _slot_icons[index].visible
			),
			"semanticIconHasNoEllipsisBase": (
				String(item.get("kind", "")) == "semantic_icon"
				and _slot_skins[index].texture == null
				and _slot_icons[index].visible
			),
			"semanticBackdropCoversEllipsis": (
				String(item.get("kind", "")) == "semantic_icon"
				and _slot_skins[index].texture == ELLIPSIS_SHELL
				and _slot_semantic_backdrops[index].visible
				and _slot_icons[index].visible
			),
			"semanticActionShellHasClearCenter": (
				String(item.get("kind", "")) == "semantic_icon"
				and _slot_skins[index].texture == ACTION_SHELL
				and not _slot_semantic_backdrops[index].visible
				and _slot_icons[index].visible
			),
			"payload": (
				_slot_buttons[index].get_meta("intent_payload", {})
				as Dictionary
			).duplicate(true),
			"intent": String(
				_slot_buttons[index].get_meta("intent", "")
			),
			"disabled": _slot_buttons[index].disabled,
		})
	return {
		"revision": _current_revision,
		"renderCount": _render_count,
		"visible": visible,
		"renderEnabled": render_enabled,
		"visibleSlotCount": _actual_visible_count(),
		"semanticItemCount": _visible_slot_count,
		"slots": slot_records,
		"aggregateVisible": _aggregate_label.visible,
		"aggregateText": _aggregate_label.text,
		"frameAggregateCount": _frame_aggregate_count,
		"animatedEllipsisSlot": -1,
		"animationEnabled": _has_visible_action_animation(),
		"actionIconManifestPath": ACTION_ICON_MANIFEST_PATH,
		"actionIconFrameSize": ACTION_ICON_FRAME_SIZE,
		"actionIconCount": _action_icon_frames.size(),
		"actionMarkerCount": _action_markers.size(),
		"actionMarkerDisplaySize": SEMANTIC_MARKER_SIZE,
		"anchorProviderBound": is_instance_valid(_anchor_provider),
		"transientSnapshotContractReady": TRANSIENT_SNAPSHOT_CONTRACT_READY,
		"lastRejection": _last_rejection.duplicate(),
	}


func _load_action_icon_catalog() -> void:
	_action_icon_frames.clear()
	_action_markers.clear()
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(ACTION_ICON_MANIFEST_PATH)
	)
	if parsed is not Dictionary:
		return
	var manifest := parsed as Dictionary
	for value: Variant in manifest.get("items", []) as Array:
		if not value is Dictionary:
			continue
		var item := value as Dictionary
		var icon_key := String(item.get("iconKey", "")).strip_edges()
		var strip_path := String(item.get("stripPath", "")).strip_edges()
		var strip := load(strip_path) as Texture2D
		if icon_key.is_empty() or strip == null:
			continue
		var frames: Array[Texture2D] = []
		for frame_index: int in range(2):
			var frame := AtlasTexture.new()
			frame.atlas = strip
			frame.region = Rect2(
				Vector2(ACTION_ICON_FRAME_SIZE.x * frame_index, 0.0),
				ACTION_ICON_FRAME_SIZE,
			)
			frames.append(frame)
		_action_icon_frames[icon_key] = frames
	for value: Variant in manifest.get("markers", []) as Array:
		if not value is Dictionary:
			continue
		var marker := value as Dictionary
		var marker_key := String(marker.get("markerKey", "")).strip_edges()
		var marker_path := String(marker.get("path", "")).strip_edges()
		var marker_texture := load(marker_path) as Texture2D
		if not marker_key.is_empty() and marker_texture != null:
			_action_markers[marker_key] = marker_texture


func _action_icon_texture(icon_key: String, frame_index: int) -> Texture2D:
	var frames_value: Variant = _action_icon_frames.get(icon_key)
	if frames_value is Array and not (frames_value as Array).is_empty():
		var frames := frames_value as Array
		return frames[clampi(frame_index, 0, frames.size() - 1)] as Texture2D
	return LEGACY_SEMANTIC_ICONS.get(icon_key, null) as Texture2D


func _build_slots() -> void:
	_ensure_slot_count(INITIAL_SLOT_POOL)


func _ensure_slot_count(required_count: int) -> void:
	if _slots.size() >= required_count:
		return
	if _semantic_backdrop_color.a <= 0.0:
		_semantic_backdrop_color = Color("#FBE8AF")
		var ellipsis_image := ELLIPSIS_SHELL.get_image()
		if ellipsis_image != null and not ellipsis_image.is_empty():
			_semantic_backdrop_color = ellipsis_image.get_pixel(47, 22)
	var semantic_backdrop_color := _semantic_backdrop_color
	while _slots.size() < required_count:
		var index := _slots.size()
		var slot := Control.new()
		slot.name = "FarActivitySlot%d" % index
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(slot)
		_slots.append(slot)

		var skin := TextureRect.new()
		skin.name = "ApprovedVisual"
		skin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		skin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		skin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		skin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		skin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(skin)
		_slot_skins.append(skin)

		var semantic_backdrop := ColorRect.new()
		semantic_backdrop.name = "SemanticBackdrop"
		semantic_backdrop.position = SEMANTIC_BACKDROP_POSITION
		semantic_backdrop.size = SEMANTIC_BACKDROP_SIZE
		semantic_backdrop.color = semantic_backdrop_color
		semantic_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		semantic_backdrop.visible = false
		slot.add_child(semantic_backdrop)
		_slot_semantic_backdrops.append(semantic_backdrop)

		var icon := TextureRect.new()
		icon.name = "SemanticIcon"
		icon.position = SEMANTIC_ICON_POSITION
		icon.size = SEMANTIC_ICON_SIZE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.visible = false
		slot.add_child(icon)
		_slot_icons.append(icon)

		var marker := TextureRect.new()
		marker.name = "PhaseMarker"
		marker.position = SEMANTIC_MARKER_POSITION
		marker.size = SEMANTIC_MARKER_SIZE
		marker.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		marker.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		marker.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.visible = false
		slot.add_child(marker)
		_slot_markers.append(marker)

		var label := Label.new()
		label.name = "PublicLabel"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.clip_text = true
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.max_lines_visible = 3
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_override("font", FONT)
		label.add_theme_font_size_override("font_size", 32)
		label.add_theme_color_override("font_color", INK)
		label.add_theme_constant_override("outline_size", 0)
		label.add_theme_constant_override("line_spacing", 0)
		slot.add_child(label)
		_slot_labels.append(label)

		var behavior_label := Label.new()
		behavior_label.name = "BehaviorLabel"
		behavior_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		behavior_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		behavior_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		behavior_label.clip_text = true
		behavior_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		behavior_label.max_lines_visible = 2
		behavior_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		behavior_label.add_theme_font_override("font", FONT)
		behavior_label.add_theme_font_size_override(
			"font_size",
			SEMANTIC_ACTION_FONT_SIZE,
		)
		behavior_label.add_theme_color_override("font_color", INK)
		behavior_label.add_theme_constant_override("outline_size", 0)
		behavior_label.add_theme_constant_override("line_spacing", 0)
		behavior_label.position = SEMANTIC_ACTION_LABEL_RECT.position
		behavior_label.size = SEMANTIC_ACTION_LABEL_RECT.size
		behavior_label.visible = false
		slot.add_child(behavior_label)
		_slot_behavior_labels.append(behavior_label)
		_slot_semantic_preview_signatures.append("")
		_slot_semantic_preview_started_msec.append(0)
		_slot_semantic_preview_pages.append(0)
		_slot_semantic_action_pages.append(0)
		_slot_semantic_preview_modes.append("")

		var button := Button.new()
		button.name = "HitTarget"
		button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button.flat = true
		button.text = ""
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var empty := StyleBoxEmpty.new()
		for state_name: String in [
			"normal", "hover", "pressed", "disabled", "focus",
		]:
			button.add_theme_stylebox_override(state_name, empty)
		button.pressed.connect(_on_slot_pressed.bind(index))
		slot.add_child(button)
		_slot_buttons.append(button)
		_slot_items.append({})


func _build_aggregate_label() -> void:
	_aggregate_label = Label.new()
	_aggregate_label.name = "FarAggregateLabel"
	_aggregate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aggregate_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_aggregate_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aggregate_label.add_theme_font_override("font", FONT)
	_aggregate_label.add_theme_font_size_override("font_size", 32)
	_aggregate_label.add_theme_color_override("font_color", INK)
	_aggregate_label.add_theme_constant_override("outline_size", 0)
	add_child(_aggregate_label)


func _render() -> void:
	_render_count += 1
	var far_activity := _data.get("farResidentActivity", {}) as Dictionary
	if (
		not TRANSIENT_SNAPSHOT_CONTRACT_READY
		or bool(
			(_data.get("pausePrompt", {}) as Dictionary).get(
				"visible",
				false
			)
		)
	):
		_visible_slot_count = 0
		for index: int in range(_slots.size()):
			_hide_slot(index)
		_aggregate_label.visible = false
		_update_root_visibility()
		return
	var unique_items: Array[Dictionary] = []
	var owners := {}
	var far_activity_available := bool(
		far_activity.get("available", false)
	)
	# Conversation entries own their two participants. Public thought entries
	# consume only the Adapter's confirmed public surface contract.
	for value: Variant in far_activity.get("items", []) as Array:
		if not far_activity_available:
			break
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var item := value as Dictionary
		var kind := String(item.get("kind", ""))
		if kind != "spectator_conversation":
			continue
		if (
			String(item.get("anchorPolicy", ""))
			!= "live_resident_head"
			or String(item.get("motionPolicy", ""))
			!= "follow_resident"
		):
			continue
		var overlay_id := String(item.get("overlayId", "")).strip_edges()
		if overlay_id.is_empty():
			continue
		var expires_at_msec := int(item.get("expiresAtMsec", -1))
		if expires_at_msec != 0:
			continue
		var owner_key := _owner_key(item)
		if owner_key.is_empty() or owners.has(owner_key):
			continue
		owners[owner_key] = true
		for participant_id_value: Variant in (
			item.get("participantIds", []) as Array
		):
			var participant_id := String(
				participant_id_value
			).strip_edges()
			if not participant_id.is_empty():
				owners["resident:%s" % participant_id] = true
		unique_items.append(item)
	var zoom_band := String(
		(_data.get("density", {}) as Dictionary).get("zoomBand", "middle")
	)
	var compact_activity_band := zoom_band == "far"
	var now_msec := Time.get_ticks_msec()
	var resident_overlays := (
		_data.get("residentOverlays", {}) as Dictionary
	)
	# Results outrank reactions and current activity, while conversations keep
	# ownership of both participants.
	if far_activity_available:
		for value: Variant in far_activity.get("items", []) as Array:
			if typeof(value) != TYPE_DICTIONARY:
				continue
			var item := value as Dictionary
			var kind := String(item.get("kind", ""))
			var phase := String(item.get("phase", ""))
			if (
				kind != "semantic_icon"
				or phase not in ["failed", "completed", "interrupted"]
			):
				continue
			if (
				String(item.get("anchorPolicy", ""))
					!= "live_resident_head"
				or String(item.get("motionPolicy", ""))
					!= "follow_resident"
				or (
					int(item.get("expiresAtMsec", 0)) != 0
					and int(item.get("expiresAtMsec", 0))
						<= now_msec
				)
			):
				continue
			var owner_key := _owner_key(item)
			if owner_key.is_empty() or owners.has(owner_key):
				continue
			if (
				_action_icon_texture(
					String(item.get("iconType", "")),
					0,
				) == null
			):
				continue
			owners[owner_key] = true
			unique_items.append(item)
	# A resident's own completion/failure reaction must not be hidden by the
	# next persistent activity icon.
	for value: Variant in resident_overlays.get("items", []) as Array:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var public_item := value as Dictionary
		if (
			String(public_item.get("contentKind", "")) != "public_thought"
			or String(public_item.get("thoughtKind", "")) not in [
				"activity_reaction",
				"announcement_reaction",
			]
			or compact_activity_band
		):
			continue
		var resident_id := String(public_item.get("residentId", "")).strip_edges()
		var owner_key := "resident:%s" % resident_id
		var expires_at_msec := int(public_item.get("expiresAtMsec", 0))
		if (
			resident_id.is_empty()
			or owners.has(owner_key)
			or (expires_at_msec != 0 and expires_at_msec <= now_msec)
		):
			continue
		owners[owner_key] = true
		var render_item := public_item.duplicate(true)
		render_item["overlayId"] = "thought:%s" % String(
			public_item.get("thoughtId", resident_id)
		)
		render_item["kind"] = "public_thought"
		render_item["anchorPolicy"] = "live_resident_head"
		render_item["motionPolicy"] = "follow_resident"
		unique_items.append(render_item)
	# A newly confirmed decision briefly owns the resident. Only the far view
	# keeps the compact task icon; middle and near views add readable text.
	for value: Variant in resident_overlays.get("items", []) as Array:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var public_item := value as Dictionary
		var icon_key := String(public_item.get("baseIconKey", "")).strip_edges()
		if (
			String(public_item.get("contentKind", "")) != "public_thought"
			or String(public_item.get("thoughtKind", "")) != "action_intention"
			or icon_key.is_empty()
			or _action_icon_texture(icon_key, 0) == null
		):
			continue
		var resident_id := String(public_item.get("residentId", "")).strip_edges()
		var owner_key := "resident:%s" % resident_id
		var expires_at_msec := int(public_item.get("expiresAtMsec", 0))
		if (
			resident_id.is_empty()
			or owners.has(owner_key)
			or (expires_at_msec != 0 and expires_at_msec <= now_msec)
		):
			continue
		owners[owner_key] = true
		var render_item := public_item.duplicate(true)
		render_item["overlayId"] = "intention:%s" % String(
			public_item.get("thoughtId", resident_id)
		)
		render_item["kind"] = "semantic_icon"
		render_item["iconType"] = icon_key
		render_item["phase"] = "approaching"
		render_item["markerKey"] = "phase_approaching"
		var formal_action_label := String(
			public_item.get("formalActionLabel", "")
		)
		render_item["label"] = formal_action_label
		render_item["thoughtLabel"] = String(
			public_item.get("thoughtLabel", "")
		)
		render_item["showLabel"] = zoom_band in ["middle", "near"]
		render_item["animate"] = false
		render_item["anchorPolicy"] = "live_resident_head"
		render_item["motionPolicy"] = "follow_resident"
		unique_items.append(render_item)
	# Persistent current actions fill the remaining residents.
	if far_activity_available:
		for value: Variant in far_activity.get("items", []) as Array:
			if typeof(value) != TYPE_DICTIONARY:
				continue
			var item := value as Dictionary
			var kind := String(item.get("kind", ""))
			if (
				kind not in ["semantic_icon", "activity_ellipsis"]
				or String(item.get("phase", "")) in [
					"failed", "completed", "interrupted",
				]
			):
				continue
			if (
				String(item.get("anchorPolicy", "")) != "live_resident_head"
				or String(item.get("motionPolicy", "")) != "follow_resident"
				or (
					int(item.get("expiresAtMsec", 0)) != 0
					and int(item.get("expiresAtMsec", 0)) <= now_msec
				)
			):
				continue
			var owner_key := _owner_key(item)
			if owner_key.is_empty() or owners.has(owner_key):
				continue
			if (
				kind == "semantic_icon"
				and _action_icon_texture(String(item.get("iconType", "")), 0) == null
			):
				continue
			owners[owner_key] = true
			unique_items.append(item)
	# Remaining thoughts retain the existing compact density rule.
	for value: Variant in resident_overlays.get("items", []) as Array:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var public_item := value as Dictionary
		if String(public_item.get("contentKind", "")) != "public_thought":
			continue
		var thought_kind := String(public_item.get("thoughtKind", ""))
		if (
			thought_kind in ["activity_reaction", "announcement_reaction"]
			or (
				thought_kind == "action_intention"
				and not String(public_item.get("baseIconKey", "")).is_empty()
			)
		):
			continue
		if (
			compact_activity_band
			and thought_kind.begins_with(
				"social_matter_"
			)
		):
			continue
		var resident_id := String(
			public_item.get("residentId", "")
		).strip_edges()
		var owner_key := "resident:%s" % resident_id
		if resident_id.is_empty() or owners.has(owner_key):
			continue
		var expires_at_msec := int(public_item.get("expiresAtMsec", 0))
		if (
			expires_at_msec != 0
			and expires_at_msec <= now_msec
		):
			continue
		owners[owner_key] = true
		var render_item := public_item.duplicate(true)
		render_item["overlayId"] = "thought:%s" % String(
			public_item.get("thoughtId", resident_id)
		)
		render_item["kind"] = (
			"public_thought_ellipsis"
			if compact_activity_band
			else "public_thought"
		)
		render_item["anchorPolicy"] = "live_resident_head"
		render_item["motionPolicy"] = "follow_resident"
		unique_items.append(render_item)
	_visible_slot_count = unique_items.size()
	_ensure_slot_count(_visible_slot_count)
	for index: int in range(_slots.size()):
		if index >= _visible_slot_count:
			_hide_slot(index)
			continue
		var item := unique_items[index]
		_render_slot(index, item)
	_aggregate_label.text = ""
	_aggregate_label.visible = false
	_apply_layout()
	_update_root_visibility()


func _render_slot(index: int, item: Dictionary) -> void:
	_slot_items[index] = item.duplicate(true)
	var kind := String(item.get("kind", ""))
	var slot := _slots[index]
	var skin := _slot_skins[index]
	var icon := _slot_icons[index]
	var label := _slot_labels[index]
	slot.visible = render_enabled
	slot.scale = Vector2.ONE
	slot.modulate = Color.WHITE
	label.text = ""
	label.visible = false
	_slot_behavior_labels[index].text = ""
	_slot_behavior_labels[index].visible = false
	skin.modulate = Color.WHITE
	skin.texture = null
	icon.texture = null
	icon.position = SEMANTIC_ICON_POSITION
	icon.size = SEMANTIC_ICON_SIZE
	icon.visible = false
	var marker := _slot_markers[index]
	marker.texture = null
	marker.position = SEMANTIC_MARKER_POSITION
	marker.size = SEMANTIC_MARKER_SIZE
	marker.visible = false
	_slot_semantic_backdrops[index].visible = false
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	label.max_lines_visible = 2
	match kind:
		"spectator_conversation":
			slot.size = CONVERSATION_SIZE
			skin.texture = CONVERSATION_SHELL
			label.text = _normalized_bubble_line(
				String(item.get("bubbleText", item.get("label", "")))
			)
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.max_lines_visible = 2
			label.add_theme_font_size_override("font_size", 21)
			label.visible = not label.text.is_empty()
			label.position = Vector2(112, 24)
			label.size = Vector2(210, 76)
		"public_thought":
			skin.texture = THOUGHT_SHELL
			label.text = _compact_public_thought(
				String(
					item.get("thoughtLabel", item.get("label", ""))
				)
			)
			slot.size = THOUGHT_SIZE
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.add_theme_font_size_override(
				"font_size",
				THOUGHT_FONT_SIZE,
			)
			label.max_lines_visible = 2
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			label.clip_text = true
			label.visible = not label.text.is_empty()
			label.position = Vector2(14, 7)
			label.size = Vector2(239, 62)
		"public_thought_ellipsis":
			slot.size = ELLIPSIS_SIZE
			skin.texture = ELLIPSIS_SHELL
		"activity_ellipsis":
			slot.size = ELLIPSIS_SIZE
			skin.texture = ELLIPSIS_SHELL
		"semantic_icon":
			var show_label := bool(item.get("showLabel", false))
			if show_label:
				slot.size = THOUGHT_SIZE
				_render_semantic_preview(index, item, Time.get_ticks_msec())
			else:
				_reset_semantic_preview(index)
				slot.size = ACTION_SIZE
				skin.texture = ACTION_SHELL
				_slot_semantic_backdrops[index].visible = false
			icon.texture = _action_icon_texture(
				String(item.get("iconType", "")),
				_action_icon_frame_for_item(item, _shared_animation_frame),
			)
			icon.visible = icon.texture != null
			marker.texture = _action_markers.get(
				String(item.get("markerKey", "")),
				null,
			) as Texture2D
			marker.visible = marker.texture != null
			if show_label:
				var action_phase := _slot_semantic_preview_modes[index] == "action"
				icon.visible = action_phase and icon.texture != null
				marker.visible = action_phase and marker.texture != null
	_configure_slot_action(index, item)


func _render_semantic_preview(
	index: int,
	item: Dictionary,
	now_msec: int,
) -> void:
	var pages := _semantic_thought_pages(item)
	var signature := _semantic_preview_signature(item)
	if _slot_semantic_preview_signatures[index] != signature:
		_slot_semantic_preview_signatures[index] = signature
		_slot_semantic_preview_started_msec[index] = int(
			item.get("startedAtMsec", now_msec)
		)
		if _slot_semantic_preview_started_msec[index] == 0:
			_slot_semantic_preview_started_msec[index] = now_msec
		_slot_semantic_preview_pages[index] = 0
		_slot_semantic_action_pages[index] = 0
		_slot_semantic_preview_modes[index] = (
			"action" if pages.is_empty() else "thought"
		)
	var elapsed_msec := maxi(
		0,
		now_msec - _slot_semantic_preview_started_msec[index],
	)
	var thought_duration_msec := (
		pages.size() * SEMANTIC_THOUGHT_PAGE_DURATION_MSEC
	)
	if elapsed_msec >= thought_duration_msec:
		_slot_semantic_preview_modes[index] = "action"
		_slot_semantic_preview_pages[index] = pages.size()
	if _slot_semantic_preview_modes[index] == "action":
		_render_semantic_action(
			index,
			item,
			maxi(0, elapsed_msec - thought_duration_msec),
		)
		return
	var page_index := mini(
		int(elapsed_msec / SEMANTIC_THOUGHT_PAGE_DURATION_MSEC),
		pages.size() - 1,
	)
	_slot_semantic_preview_pages[index] = page_index
	_render_semantic_thought(index, pages[page_index])


func _render_semantic_thought(index: int, thought_page: String) -> void:
	var skin := _slot_skins[index]
	var label := _slot_labels[index]
	skin.texture = THOUGHT_SHELL
	label.text = _balanced_two_line_text(
		thought_page,
		SEMANTIC_THOUGHT_LINE_MAX_UNITS,
	)
	label.position = Vector2(14.0, 7.0)
	label.size = Vector2(239.0, 62.0)
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.add_theme_font_size_override("font_size", THOUGHT_FONT_SIZE)
	label.max_lines_visible = 2
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	label.clip_text = true
	label.visible = not thought_page.is_empty()
	_slot_icons[index].visible = false
	_slot_markers[index].visible = false
	_slot_behavior_labels[index].visible = false


func _render_semantic_action(
	index: int,
	item: Dictionary,
	action_elapsed_msec: int,
) -> void:
	var skin := _slot_skins[index]
	var icon := _slot_icons[index]
	var marker := _slot_markers[index]
	var behavior_label := _slot_behavior_labels[index]
	skin.texture = THOUGHT_SHELL
	icon.position = Vector2(18.0, 14.0)
	marker.position = Vector2(54.0, 8.0)
	var action_pages := _semantic_action_pages(item)
	var page_index := 0
	if action_pages.size() > 1:
		page_index = int(
			action_elapsed_msec / SEMANTIC_ACTION_PAGE_DURATION_MSEC
		) % action_pages.size()
	_slot_semantic_action_pages[index] = page_index
	behavior_label.text = (
		_balanced_two_line_text(
			action_pages[page_index],
			SEMANTIC_ACTION_LINE_MAX_UNITS,
		)
		if not action_pages.is_empty()
		else ""
	)
	behavior_label.visible = not behavior_label.text.is_empty()
	_slot_labels[index].visible = false


func _reset_semantic_preview(index: int) -> void:
	_slot_semantic_preview_signatures[index] = ""
	_slot_semantic_preview_started_msec[index] = 0
	_slot_semantic_preview_pages[index] = 0
	_slot_semantic_action_pages[index] = 0
	_slot_semantic_preview_modes[index] = ""
	_slot_behavior_labels[index].text = ""
	_slot_behavior_labels[index].visible = false


func _semantic_preview_signature(item: Dictionary) -> String:
	var resident_id := String(item.get("residentId", "")).strip_edges()
	var action_id := String(
		item.get("actionId", item.get("sourceActionId", ""))
	).strip_edges()
	return "%s|%s|%s" % [
		resident_id,
		action_id,
		"%s|%s" % [
			_normalized_public_bubble_line(String(item.get("thoughtLabel", ""))),
			_normalized_public_bubble_line(
				String(item.get("activeActionLabel", item.get("label", "")))
			),
		],
	]


func _semantic_thought_pages(item: Dictionary) -> Array[String]:
	return _split_thought_pages(String(item.get("thoughtLabel", "")))


func _split_thought_pages(value: String) -> Array[String]:
	return _split_balanced_display_pages(
		_normalized_public_bubble_line(value),
		float(SEMANTIC_THOUGHT_PAGE_MAX_UNITS),
	)


func _semantic_action_pages(item: Dictionary) -> Array[String]:
	return _split_balanced_display_pages(
		_normalized_public_bubble_line(
			String(item.get("activeActionLabel", item.get("label", "")))
		),
		float(SEMANTIC_ACTION_PAGE_MAX_UNITS),
	)


func _split_balanced_display_pages(
	value: String,
	max_units: float,
) -> Array[String]:
	var pages: Array[String] = []
	var remaining := value.strip_edges()
	while _display_units(remaining) > max_units:
		var remaining_units := _display_units(remaining)
		var remaining_pages := int(ceil(remaining_units / max_units))
		var target_units := remaining_units / float(remaining_pages)
		var split_at := _balanced_display_split_index(
			remaining,
			target_units,
			max_units,
		)
		var page := remaining.left(split_at).strip_edges()
		if page.is_empty():
			break
		pages.append(page)
		remaining = remaining.substr(split_at).strip_edges()
	if not remaining.is_empty():
		pages.append(remaining)
	return pages


func _balanced_two_line_text(value: String, line_max_units: float) -> String:
	var normalized := value.strip_edges()
	var total_units := _display_units(normalized)
	if normalized.is_empty() or total_units <= line_max_units:
		return normalized
	var split_at := _balanced_display_split_index(
		normalized,
		total_units / 2.0,
		line_max_units,
	)
	if split_at <= 0 or split_at >= normalized.length():
		return normalized
	return "%s\n%s" % [
		normalized.left(split_at).strip_edges(),
		normalized.substr(split_at).strip_edges(),
	]


func _balanced_display_split_index(
	value: String,
	target_units: float,
	max_units: float,
) -> int:
	const NATURAL_BREAKS := "。！？!?；;，,、：: "
	var minimum_units := maxf(2.0, target_units * 0.6)
	var units := 0.0
	var best_index := -1
	var best_score := INF
	var fallback_index := 1
	var fallback_distance := INF
	for index: int in value.length():
		var next_units := units + _character_display_units(value, index)
		if next_units > max_units:
			break
		units = next_units
		var distance := absf(units - target_units)
		if distance <= fallback_distance:
			fallback_distance = distance
			fallback_index = index + 1
		var character := value.substr(index, 1)
		if units < minimum_units or not NATURAL_BREAKS.contains(character):
			continue
		if (
			_display_units(value) > max_units
			and _display_units(value.substr(index + 1)) < minimum_units
		):
			continue
		var priority_bonus := (
			3.0
			if "。！？!?；;".contains(character)
			else (1.5 if "，,、：:".contains(character) else 0.5)
		)
		var score := distance - priority_bonus
		if score < best_score:
			best_score = score
			best_index = index + 1
	return best_index if best_index >= 0 else fallback_index


func _compact_public_thought(value: String) -> String:
	var normalized := value.strip_edges()
	for separator: String in ["\r", "\n", "\t"]:
		normalized = normalized.replace(separator, " ")
	while normalized.contains("  "):
		normalized = normalized.replace("  ", " ")
	return _trim_by_display_width(normalized, float(THOUGHT_TEXT_MAX_LENGTH))


func _near_semantic_label(formal_value: String, thought_value: String) -> String:
	var formal := _normalized_bubble_line(formal_value)
	var thought := _single_bubble_line(
		thought_value,
		THOUGHT_TEXT_MAX_LENGTH,
	)
	if thought.is_empty():
		return formal
	if formal.is_empty():
		return thought
	return "%s\n%s" % [formal, thought]


func _single_bubble_line(value: String, max_length: int) -> String:
	return _trim_by_display_width(
		_normalized_bubble_line(value),
		float(max_length),
	)


func _normalized_bubble_line(value: String) -> String:
	var normalized := _normalized_public_bubble_line(value)
	while normalized.ends_with("…"):
		normalized = normalized.left(normalized.length() - 1).strip_edges()
	while normalized.ends_with("..."):
		normalized = normalized.left(normalized.length() - 3).strip_edges()
	return normalized


func _normalized_public_bubble_line(value: String) -> String:
	var normalized := value.strip_edges()
	for separator: String in ["\r", "\n", "\t"]:
		normalized = normalized.replace(separator, " ")
	while normalized.contains("  "):
		normalized = normalized.replace("  ", " ")
	return normalized


# 中英混排下按字符数截断会偏差很大：拉丁字符按半个汉字宽度计。
func _trim_by_display_width(value: String, max_cjk_units: float) -> String:
	if _display_units(value) <= max_cjk_units:
		return value
	var units := 0.0
	for index: int in value.length():
		var char_units := _character_display_units(value, index)
		if units + char_units > max_cjk_units - 1.0:
			return value.substr(0, index).strip_edges() + "…"
		units += char_units
	return value


func _display_units(value: String) -> float:
	var units := 0.0
	for index: int in value.length():
		units += _character_display_units(value, index)
	return units


func _character_display_units(value: String, index: int) -> float:
	var character := value.substr(index, 1)
	return maxf(
		0.5,
		FONT.get_string_size(
			character,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			THOUGHT_FONT_SIZE,
		).x / float(THOUGHT_FONT_SIZE),
	)


func _configure_slot_action(index: int, item: Dictionary) -> void:
	var kind := String(item.get("kind", ""))
	var action := _item_action(item)
	var expected_intent := (
		"conversation.spectator.select"
		if kind == "spectator_conversation"
		else (
			"town_hud.open_town_log"
			if String(item.get("thoughtKind", "")) == "announcement_reaction"
			else "town_hud.open_resident_action"
		)
	)
	var intent := String(action.get("intent", ""))
	var enabled := (
		bool(action.get("enabled", false))
		and intent == expected_intent
	)
	var payload := (
		(action.get("payload", {}) as Dictionary).duplicate(true)
		if typeof(action.get("payload", {})) == TYPE_DICTIONARY
		else {}
	)
	if kind == "spectator_conversation":
		var conversation_id := String(
			item.get("conversationId", "")
		).strip_edges()
		if conversation_id.is_empty():
			enabled = false
		else:
			payload["conversationId"] = conversation_id
	elif intent == "town_hud.open_resident_action":
		var resident_id := String(item.get("residentId", "")).strip_edges()
		if resident_id.is_empty():
			enabled = false
		else:
			payload["residentId"] = resident_id
	var button := _slot_buttons[index]
	button.set_meta("intent", intent if enabled else "")
	button.set_meta("intent_payload", payload if enabled else {})
	button.disabled = not enabled
	button.tooltip_text = (
		"打开对话"
		if enabled and kind == "spectator_conversation"
		else (
			(
				"查看公告记录"
				if intent == "town_hud.open_town_log"
				else "查看居民"
			)
			if enabled
			else UiViewModel.player_reason(
				String(action.get("disabledReason", "入口不可用"))
			)
		)
	)


func _item_action(item: Dictionary) -> Dictionary:
	var value: Variant = item.get("action", {})
	if typeof(value) == TYPE_DICTIONARY:
		return value as Dictionary
	var actions_value: Variant = item.get("actions", {})
	if typeof(actions_value) != TYPE_DICTIONARY:
		return {}
	var actions := actions_value as Dictionary
	for key: String in ["select", "open", "activate"]:
		if typeof(actions.get(key, null)) == TYPE_DICTIONARY:
			return actions[key] as Dictionary
	return {}


func _owner_key(item: Dictionary) -> String:
	var kind := String(item.get("kind", ""))
	if kind == "spectator_conversation":
		var conversation_id := String(
			item.get("conversationId", "")
		).strip_edges()
		return (
			"conversation:%s" % conversation_id
			if not conversation_id.is_empty()
			else ""
		)
	var resident_id := String(item.get("residentId", "")).strip_edges()
	return (
		"resident:%s" % resident_id
		if not resident_id.is_empty()
		else ""
	)


func _hide_slot(index: int) -> void:
	_slots[index].visible = false
	_slot_items[index] = {}
	_slot_labels[index].text = ""
	_slot_labels[index].visible = false
	_slot_behavior_labels[index].text = ""
	_slot_behavior_labels[index].visible = false
	_reset_semantic_preview(index)
	_slot_icons[index].texture = null
	_slot_icons[index].visible = false
	_slot_markers[index].texture = null
	_slot_markers[index].visible = false
	_slot_semantic_backdrops[index].visible = false
	_slots[index].scale = Vector2.ONE
	_slots[index].modulate = Color.WHITE
	_slot_buttons[index].set_meta("intent", "")
	_slot_buttons[index].set_meta("intent_payload", {})
	_slot_buttons[index].disabled = true


# 1a:预算截断与聚合计数在消费层执行——活读锚点过滤当前不可见候选,
# 按 adapter 给定顺序应用 visibleBudget,余量记入 aggregateCount。
# 只有气泡候选(携带 thoughtKind 的 residentOverlays 项)参与预算;
# 常驻 far 图标与对话入口沿用无截断行为。
func _overlay_budget_state() -> Dictionary:
	var overlays := _data.get("residentOverlays", {}) as Dictionary
	var items := overlays.get("items", []) as Array
	var budget := int(overlays.get("visibleBudget", items.size()))
	var allowed: Dictionary = {}
	var visible_candidates := 0
	for value: Variant in items:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var item := value as Dictionary
		var resident_id := String(item.get("residentId", "")).strip_edges()
		if resident_id.is_empty():
			continue
		var anchor := (
			_provider_head_anchor(resident_id)
			if is_instance_valid(_anchor_provider)
			else _screen_anchor(item)
		)
		if not _head_is_in_visible_playfield(anchor):
			continue
		visible_candidates += 1
		if allowed.size() < budget:
			allowed["%s|%s" % [
				resident_id,
				String(item.get("thoughtId", "")),
			]] = true
	return {
		"allowed": allowed,
		"aggregateCount": maxi(visible_candidates - allowed.size(), 0),
	}


func _apply_layout() -> void:
	if not is_node_ready():
		return
	var safe := _playfield_safe_rect()
	var budget_state := _overlay_budget_state()
	var allowed := budget_state.get("allowed", {}) as Dictionary
	_frame_aggregate_count = int(budget_state.get("aggregateCount", 0))
	var laid_out: Array[Rect2] = []
	for index: int in range(_visible_slot_count):
		var item := _slot_items[index]
		var slot := _slots[index]
		var anchor := _head_screen_anchor(item)
		if anchor == Vector2.INF:
			slot.visible = false
			continue
		if item.has("thoughtKind"):
			var budget_key := "%s|%s" % [
				String(item.get("residentId", "")).strip_edges(),
				String(item.get("thoughtId", "")),
			]
			if not allowed.has(budget_key):
				slot.visible = false
				continue
		var anchor_gap := 20.0
		if String(item.get("kind", "")) in [
			"public_thought_ellipsis",
			"activity_ellipsis",
			"semantic_icon",
		]:
			anchor_gap = 0.0
		elif String(item.get("kind", "")) == "public_thought":
			# The pointer tip is the attachment point for a resident thought.
			# It should touch the live head anchor instead of floating above it.
			anchor_gap = 0.0
		var tail_local_x := _tail_local_x(item, slot.size)
		var candidate := Rect2(
			anchor - Vector2(tail_local_x, slot.size.y + anchor_gap),
			slot.size
		)
		# The live camera projection can legitimately land on half logical pixels.
		# Preserve it so the authored tail remains exactly on the resident head;
		# the physical display scale resolves that coordinate to the pixel grid.
		slot.position = candidate.position
		var rounded_size := candidate.size.round()
		if slot.size != rounded_size:
			slot.size = rounded_size
		if slot.visible != render_enabled:
			slot.visible = render_enabled
		laid_out.append(candidate)
	var aggregate_anchor := (
		laid_out[-1].end + Vector2(8, -42)
		if not laid_out.is_empty()
		else safe.position + Vector2(28, 28)
	)
	_aggregate_label.position = Vector2(
		clampf(aggregate_anchor.x, safe.position.x, safe.end.x - 84),
		clampf(aggregate_anchor.y, safe.position.y, safe.end.y - 44)
	).round()
	_aggregate_label.size = Vector2(84, 44)
	if _show_guides:
		queue_redraw()


func _process(_delta: float) -> void:
	if _visible_slot_count <= 0:
		return
	# Head anchors are presentation state, not low-frequency semantic data.
	# Re-layout every rendered frame so bubbles follow residents and the camera.
	_apply_layout()
	var now_msec := Time.get_ticks_msec()
	for index: int in range(_visible_slot_count):
		var preview_item := _slot_items[index]
		if (
			String(preview_item.get("kind", "")) == "semantic_icon"
			and bool(preview_item.get("showLabel", false))
		):
			_render_semantic_preview(index, preview_item, now_msec)
			var action_phase := _slot_semantic_preview_modes[index] == "action"
			_slot_icons[index].visible = (
				action_phase and _slot_icons[index].texture != null
			)
			_slot_markers[index].visible = (
				action_phase and _slot_markers[index].texture != null
			)
	var next_animation_frame := int(
		now_msec / ACTION_ICON_FRAME_MSEC
	) % 2
	if next_animation_frame != _shared_animation_frame:
		_shared_animation_frame = next_animation_frame
		for index: int in range(_visible_slot_count):
			var animated_item := _slot_items[index]
			if (
				_slots[index].visible
				and String(animated_item.get("kind", "")) == "semantic_icon"
				and bool(animated_item.get("animate", false))
			):
				_slot_icons[index].texture = _action_icon_texture(
					String(animated_item.get("iconType", "")),
					_action_icon_frame_for_item(
						animated_item,
						_shared_animation_frame,
					),
				)
	for index: int in range(_visible_slot_count):
		var item := _slot_items[index]
		var slot := _slots[index]
		if slot.scale != Vector2.ONE:
			slot.scale = Vector2.ONE
		var expires_at_msec := int(item.get("expiresAtMsec", 0))
		if expires_at_msec == 0:
			if slot.modulate != Color.WHITE:
				slot.modulate = Color.WHITE
			continue
		var remaining_msec := expires_at_msec - now_msec
		if remaining_msec <= 0:
			slot.visible = false
			_slot_buttons[index].disabled = true
			continue
		var alpha := clampf(
			float(remaining_msec) / float(TRANSIENT_FADE_MSEC),
			0.0,
			1.0
		)
		slot.modulate = Color(1.0, 1.0, 1.0, alpha)
		_slot_buttons[index].disabled = (
			alpha <= 0.05
			or String(
				_slot_buttons[index].get_meta("intent", "")
			).is_empty()
		)
	_update_root_visibility()


func _playfield_safe_rect() -> Rect2:
	var viewport_safe := Rect2(
		Vector2(safe_insets.x, safe_insets.y),
		Vector2(
			maxf(1.0, size.x - safe_insets.x - safe_insets.z),
			maxf(1.0, size.y - safe_insets.y - safe_insets.w)
		)
	)
	var side := 118.0 if viewport_safe.size.x >= 1500.0 else 88.0
	var top := 126.0 if viewport_safe.size.y >= 800.0 else 92.0
	var bottom := 170.0 if viewport_safe.size.y >= 800.0 else 138.0
	return Rect2(
		viewport_safe.position + Vector2(side, top),
		Vector2(
			maxf(1.0, viewport_safe.size.x - side * 2.0),
			maxf(1.0, viewport_safe.size.y - top - bottom)
		)
	)


func _screen_anchor(item: Dictionary) -> Vector2:
	var value: Variant = item.get("screenAnchor", {})
	if typeof(value) != TYPE_DICTIONARY:
		return Vector2.INF
	var anchor := value as Dictionary
	if not anchor.has("x") or not anchor.has("y"):
		return Vector2.INF
	var result := Vector2(
		float(anchor.get("x", 0)),
		float(anchor.get("y", 0))
	)
	return result if result != Vector2.ZERO else Vector2.INF


func _provider_head_anchor(resident_id: String) -> Vector2:
	if (
		resident_id.strip_edges().is_empty()
		or not is_instance_valid(_anchor_provider)
	):
		return Vector2.INF
	var anchor := _anchor_provider_call.call(resident_id) as Dictionary
	if (
		not bool(anchor.get("valid", false))
		or not bool(anchor.get("visible", true))
		or not anchor.has("x")
		or not anchor.has("y")
	):
		return Vector2.INF
	return Vector2(
		float(anchor.get("x", 0.0)),
		float(anchor.get("y", 0.0)),
	)


func _head_screen_anchor(item: Dictionary) -> Vector2:
	if is_instance_valid(_anchor_provider):
		var kind := String(item.get("kind", ""))
		if kind == "spectator_conversation":
			var participant_ids := item.get("participantIds", []) as Array
			if participant_ids.size() != 2:
				return Vector2.INF
			var first := _provider_head_anchor(String(participant_ids[0]))
			var second := _provider_head_anchor(String(participant_ids[1]))
			if (
				not _head_is_in_visible_playfield(first)
				or not _head_is_in_visible_playfield(second)
			):
				return Vector2.INF
			var midpoint := (first + second) * 0.5
			return midpoint if _head_is_in_visible_playfield(midpoint) else Vector2.INF
		var resident_id := String(item.get("residentId", "")).strip_edges()
		var live_anchor := _provider_head_anchor(resident_id)
		if live_anchor == Vector2.INF:
			return Vector2.INF
		return live_anchor if _head_is_in_visible_playfield(live_anchor) else Vector2.INF
	var fallback := _screen_anchor(item)
	return fallback if _head_is_in_visible_playfield(fallback) else Vector2.INF


func _head_is_in_visible_playfield(anchor: Vector2) -> bool:
	return (
		anchor != Vector2.INF
		and size.x > 0.0
		and size.y > 0.0
		and _playfield_safe_rect().has_point(anchor)
	)


func _tail_tip(index: int) -> Vector2:
	if index < 0 or index >= _slots.size():
		return Vector2.INF
	var slot := _slots[index]
	return slot.position + Vector2(
		_tail_local_x(_slot_items[index], slot.size),
		slot.size.y,
	)


func _tail_local_x(item: Dictionary, slot_size: Vector2) -> float:
	var kind := String(item.get("kind", ""))
	var ratio := (
		PUBLIC_THOUGHT_TAIL_X_RATIO
		if (
			kind == "public_thought"
			or (
				kind == "semantic_icon"
				and bool(item.get("showLabel", false))
			)
		)
		else CENTERED_TAIL_X_RATIO
	)
	# Keep the authored pointer on an integer pixel so rounding the bubble body
	# cannot introduce a sub-pixel gap from the resident head anchor.
	return roundf(slot_size.x * ratio)


func _tail_to_head_distance(index: int, item: Dictionary) -> float:
	var tail := _tail_tip(index)
	var head := _head_screen_anchor(item)
	if tail == Vector2.INF or head == Vector2.INF:
		return -1.0
	return tail.distance_to(head)


func _update_root_visibility() -> void:
	var has_visible_slot := false
	for index: int in range(_slots.size()):
		if _slots[index].visible:
			has_visible_slot = true
			break
	var has_content := has_visible_slot or (
		is_instance_valid(_aggregate_label) and _aggregate_label.visible
	)
	visible = render_enabled and has_content
	# 没有条目或渲染关闭时停掉逐帧布局；仍有条目但暂时全部离屏时保持运行，
	# 镜头移回后气泡才能跟着锚点自行恢复。
	set_process(render_enabled and _visible_slot_count > 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _actual_visible_count() -> int:
	var count := 0
	for slot: Control in _slots:
		if slot.visible:
			count += 1
	return count


func _has_visible_action_animation() -> bool:
	for index: int in range(_visible_slot_count):
		if (
			_slots[index].visible
			and bool(_slot_items[index].get("animate", false))
		):
			return true
	return false


func _action_icon_frame_for_item(
	item: Dictionary,
	shared_frame: int,
) -> int:
	if not bool(item.get("animate", false)):
		return 0
	var resident_id := String(item.get("residentId", ""))
	return posmod(shared_frame + absi(hash(resident_id)), 2)


func _on_slot_pressed(index: int) -> void:
	if index < 0 or index >= _slot_buttons.size():
		return
	var button := _slot_buttons[index]
	if button.disabled:
		return
	var intent := StringName(button.get_meta("intent", ""))
	var payload := (
		button.get_meta("intent_payload", {}) as Dictionary
	).duplicate(true)
	if intent == &"" or payload.is_empty():
		return
	intent_requested.emit(intent, payload)


func _draw() -> void:
	if not _show_guides:
		return
	var safe := _playfield_safe_rect()
	draw_rect(safe, Color("#42D9FF"), false, 2.0)
	for index: int in range(_visible_slot_count):
		draw_rect(
			Rect2(_slots[index].position, _slots[index].size),
			Color("#6DFF8D"),
			false,
			2.0
		)
