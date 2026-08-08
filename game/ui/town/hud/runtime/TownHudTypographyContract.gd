class_name TownHudTypographyContract
extends RefCounted


const REVISION := "ui.town.hud.typography-layout.observer-v4-runtime-v3-16x10"
const FORMAL_READY := true
const REFERENCE_SIZE := Vector2(1672.0, 941.0)
const FONT_NATIVE_SIZE := 16
const FONT_ROLE_SIZES := {
	&"hud_title": 48,
	&"hud_body": 32,
	&"hud_resident_name": 32,
	&"hud_resident_action": 32,
	&"hud_compact": 32,
}
const FONT_ROLE_VARIATIONS := {
	&"hud_title": &"Label",
	&"hud_body": &"Label",
	&"hud_resident_name": &"Label",
	&"hud_resident_action": &"Label",
	&"hud_compact": &"Label",
}
const ALLOWED_FONT_SIZES := [32, 48]
const INK := Color("#3B2416")
const ERROR_INK := Color("#7A281D")
const DISABLED_INK := Color("#76563B")
const MINIMUM_TOUCH_TARGET := Vector2(48.0, 48.0)
const REQUIRED_DATA_SECTIONS := [
	"timeWeather",
	"toolbar",
	"camera",
	"pausePrompt",
	"residentOverlays",
	"residentDirectory",
	"mapInteraction",
	"indoorMarkers",
	"eventOverlay",
	"offscreenActivity",
	"density",
]


static func breakpoint_for(viewport_size: Vector2) -> StringName:
	if viewport_size.x >= 1520.0 and viewport_size.y >= 800.0:
		return &"desktop_wide"
	if viewport_size.x >= 960.0:
		return &"desktop_compact"
	if viewport_size.x >= 700.0:
		return &"compact_landscape"
	return &"compact_portrait"


static func layout_for(
	viewport_size: Vector2,
	safe_insets: Vector4 = Vector4.ZERO,
	physical_scale: Vector2 = Vector2.ONE
) -> Dictionary:
	var safe := Rect2(
		Vector2(safe_insets.x, safe_insets.y),
		Vector2(
			viewport_size.x - safe_insets.x - safe_insets.z,
			viewport_size.y - safe_insets.y - safe_insets.w
		)
	)
	var breakpoint_id := breakpoint_for(safe.size)
	var layout: Dictionary
	match breakpoint_id:
		&"desktop_wide":
			layout = _desktop_wide_layout(safe)
		&"desktop_compact":
			layout = _desktop_compact_layout(safe)
		&"compact_landscape":
			layout = _compact_landscape_layout(safe)
		_:
			layout = _compact_portrait_layout(safe)
	return _snap_layout_to_physical(layout, physical_scale)


static func configure_label(
	label: Label,
	role: StringName,
	preview_font: Font = null
) -> void:
	label.theme_type_variation = FONT_ROLE_VARIATIONS.get(role, &"Label")
	label.add_theme_font_size_override(
		"font_size",
		int(FONT_ROLE_SIZES.get(role, 32))
	)
	label.add_theme_color_override("font_color", INK)
	label.add_theme_constant_override("outline_size", 0)
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 0)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	if preview_font != null:
		label.add_theme_font_override("font", preview_font)


static func validate_data_sections(data: Dictionary) -> PackedStringArray:
	var issues := PackedStringArray()
	for section: String in REQUIRED_DATA_SECTIONS:
		if not data.has(section):
			issues.append("data.%s 缺失" % section)
		elif typeof(data[section]) != TYPE_DICTIONARY:
			issues.append("data.%s 必须是 Dictionary" % section)
	return issues


static func text_slots(layout: Dictionary) -> Array:
	return (layout.get("textSlots", []) as Array).duplicate(true)


static func target_slots(layout: Dictionary) -> Array:
	return (layout.get("targets", []) as Array).duplicate(true)


static func _desktop_wide_layout(safe: Rect2) -> Dictionary:
	var center_x := floorf(safe.get_center().x)
	var left := safe.position.x
	var top := safe.position.y
	var right := safe.end.x
	var bottom := safe.end.y
	var top_frame := _v4_rect(safe, Rect2(575, 20, 540, 88))
	var event_frame := Rect2(right - 392, top + 116, 348, 84)
	var primary_frame := Rect2(center_x - 318, top + 396, 322, 108)
	var nearby_frame := Rect2(right - 526, top + 558, 304, 110)
	var map_frame := Rect2(center_x - 148, bottom - 241, 296, 84)
	var toolbar_frame := Rect2(center_x - 276, bottom - 161, 552, 154)
	var camera_frame := Rect2(right - 128, bottom - 409, 86, 324)
	var indoor_frame := Rect2(right - 184, top + 290, 84, 108)
	var offscreen_frame := Rect2(left + 44, top + 220, 348, 214)
	var text_slots := [
		_text_slot(
			"time_weather",
			_v4_rect(safe, Rect2(610, 34, 382, 60)),
			&"hud_body",
			"center",
			top_frame,
			Vector4(18, 10, 18, 10)
		),
		_text_slot(
			"event",
			Rect2(event_frame.position + Vector2(83, 14), Vector2(188, 54)),
			&"hud_body",
			"center",
			event_frame,
			Vector4(12, 6, 12, 6),
			Rect2(
				event_frame.position + Vector2(94, 20),
				Vector2(164, 40)
			),
			Rect2(
				event_frame.position + Vector2(129, 29),
				Vector2(94, 22)
			)
		),
		_text_slot(
			"resident_primary_name",
			Rect2(primary_frame.position + Vector2(122, 18), Vector2(194, 40)),
			&"hud_resident_name",
			"left",
			primary_frame,
			Vector4(6, 0, 2, 0)
		),
		_text_slot(
			"resident_primary_action",
			Rect2(primary_frame.position + Vector2(122, 62), Vector2(194, 40)),
			&"hud_resident_action",
			"left",
			primary_frame,
			Vector4(6, 0, 2, 0)
		),
		_text_slot(
			"resident_nearby_name",
			Rect2(nearby_frame.position + Vector2(112, 24), Vector2(178, 40)),
			&"hud_resident_name",
			"left",
			nearby_frame,
			Vector4(6, 0, 2, 0)
		),
		_text_slot(
			"resident_nearby_action",
			Rect2(nearby_frame.position + Vector2(112, 68), Vector2(178, 40)),
			&"hud_resident_action",
			"left",
			nearby_frame,
			Vector4(6, 0, 2, 0)
		),
		_text_slot(
			"map_prompt",
			Rect2(map_frame.position + Vector2(22, 33), Vector2(242, 36)),
			&"hud_body",
			"center",
			map_frame,
			Vector4(2, 3, 2, 3)
		),
		_text_slot(
			"pause_prompt",
			Rect2(center_x - 250, top + 158, 500, 56),
			&"hud_body",
			"center",
			Rect2(center_x - 270, top + 146, 540, 80),
			Vector4(20, 12, 20, 12)
		),
		_text_slot(
			"indoor_marker",
			Rect2(indoor_frame.position + Vector2(-116, 26), Vector2(112, 56)),
			&"hud_compact",
			"right",
			Rect2(indoor_frame.position + Vector2(-128, 14), Vector2(128, 80)),
			Vector4(8, 12, 8, 12)
		),
		_text_slot(
			"operation_state",
			Rect2(left + 24, top + 150, 360, 48),
			&"hud_compact",
			"left",
			Rect2(left + 12, top + 140, 384, 68),
			Vector4(12, 10, 12, 10)
		),
	]
	var targets := [
		_target("openEvent", event_frame),
		_target("focusResident", primary_frame),
		_target("focusResidentNearby", nearby_frame),
		_target("openMapTarget", map_frame),
		_target("openIndoorTarget", indoor_frame),
		_target("resume", Rect2(center_x - 270, top + 146, 540, 80)),
	]
	_append_observer_v4_targets(targets, safe)
	_append_offscreen_activity_layout(
		text_slots,
		targets,
		offscreen_frame,
		true
	)
	return _layout(
		&"desktop_wide",
		safe,
		text_slots,
		targets,
		{
			"topStatus": top_frame,
			"event": event_frame,
			"residentPrimary": primary_frame,
			"residentNearby": nearby_frame,
			"mapPrompt": map_frame,
			"toolbar": toolbar_frame,
			"camera": camera_frame,
			"indoor": indoor_frame,
			"offscreenActivity": offscreen_frame,
		}
	)


static func _desktop_compact_layout(safe: Rect2) -> Dictionary:
	var left := safe.position.x + 16
	var top := safe.position.y + 14
	var right := safe.end.x - 16
	var bottom := safe.end.y - 12
	var center_x := floorf(safe.get_center().x)
	var status_frame := _v4_rect(safe, Rect2(575, 20, 540, 88))
	var event_frame := Rect2(right - 304, top, 304, 72)
	var primary_frame := Rect2(center_x - 250, top + 200, 320, 112)
	var nearby_frame := Rect2(center_x + 84, top + 278, 292, 112)
	var map_frame := Rect2(center_x - 160, bottom - 160, 320, 72)
	var offscreen_frame := Rect2(left, top + 188, 304, 188)
	var text_slots := [
		_text_slot("time_weather", _v4_rect(safe, Rect2(610, 34, 382, 60)), &"hud_body", "center", status_frame, Vector4(16, 12, 16, 12)),
		_text_slot("event", event_frame.grow(-12), &"hud_body", "center", event_frame, Vector4(12, 12, 12, 12)),
		_text_slot("resident_primary_name", Rect2(primary_frame.position + Vector2(112, 12), Vector2(192, 40)), &"hud_resident_name", "left", primary_frame, Vector4(8, 0, 8, 0)),
		_text_slot("resident_primary_action", Rect2(primary_frame.position + Vector2(112, 58), Vector2(192, 40)), &"hud_resident_action", "left", primary_frame, Vector4(8, 0, 8, 0)),
		_text_slot("resident_nearby_name", Rect2(nearby_frame.position + Vector2(104, 12), Vector2(172, 40)), &"hud_resident_name", "left", nearby_frame, Vector4(8, 0, 8, 0)),
		_text_slot("resident_nearby_action", Rect2(nearby_frame.position + Vector2(104, 58), Vector2(172, 40)), &"hud_resident_action", "left", nearby_frame, Vector4(8, 0, 8, 0)),
		_text_slot("map_prompt", map_frame.grow(-12), &"hud_body", "center", map_frame, Vector4(12, 12, 12, 12)),
		_text_slot("pause_prompt", Rect2(center_x - 220, top + 126, 440, 56), &"hud_body", "center", Rect2(center_x - 236, top + 114, 472, 80), Vector4(16, 12, 16, 12)),
		_text_slot("indoor_marker", Rect2(left, bottom - 252, 264, 56), &"hud_compact", "center", Rect2(left, bottom - 264, 264, 80), Vector4(12, 12, 12, 12)),
		_text_slot("operation_state", Rect2(left, top + 126, 320, 48), &"hud_compact", "left", Rect2(left, top + 116, 336, 68), Vector4(8, 10, 8, 10)),
	]
	var targets := [
		_target("openEvent", event_frame),
		_target("focusResident", primary_frame),
		_target("focusResidentNearby", nearby_frame),
		_target("openMapTarget", map_frame),
		_target("openIndoorTarget", Rect2(left, bottom - 264, 264, 80)),
		_target("resume", Rect2(center_x - 236, top + 114, 472, 80)),
	]
	_append_observer_v4_targets(targets, safe)
	_append_offscreen_activity_layout(
		text_slots,
		targets,
		offscreen_frame,
		true
	)
	return _layout(
		&"desktop_compact",
		safe,
		text_slots,
		targets,
		{
			"topStatus": status_frame,
			"event": event_frame,
			"residentPrimary": primary_frame,
			"residentNearby": nearby_frame,
			"mapPrompt": map_frame,
			"indoor": Rect2(left, bottom - 264, 264, 80),
			"offscreenActivity": offscreen_frame,
		}
	)


static func _compact_landscape_layout(safe: Rect2) -> Dictionary:
	var left := safe.position.x + 8
	var top := safe.position.y + 8
	var right := safe.end.x - 8
	var bottom := safe.end.y - 8
	var center_x := floorf(safe.get_center().x)
	var status_frame := _v4_rect(safe, Rect2(575, 20, 540, 88))
	var event_frame := Rect2(left + 288, top, minf(248, right - left - 288), 64)
	var resident_frame := Rect2(left + 40, top + 132, 220, 68)
	var map_frame := Rect2(center_x - 140, bottom - 136, 280, 64)
	var offscreen_frame := Rect2(left + 280, top + 132, 300, 56)
	var text_slots := [
		_text_slot("time_weather", _v4_rect(safe, Rect2(610, 34, 382, 60)), &"hud_body", "center", status_frame, Vector4(8, 8, 8, 8)),
		_text_slot("event", event_frame.grow(-8), &"hud_body", "center", event_frame, Vector4(8, 8, 8, 8)),
		_text_slot("resident_primary_name", resident_frame.grow(-8), &"hud_resident_name", "left", resident_frame, Vector4(8, 8, 8, 8)),
		_text_slot("resident_primary_action", Rect2(), &"hud_resident_action", "left", resident_frame, Vector4.ZERO),
		_text_slot("resident_nearby_name", Rect2(), &"hud_resident_name", "left", Rect2(), Vector4.ZERO),
		_text_slot("resident_nearby_action", Rect2(), &"hud_resident_action", "left", Rect2(), Vector4.ZERO),
		_text_slot("map_prompt", map_frame.grow(-8), &"hud_body", "center", map_frame, Vector4(8, 8, 8, 8)),
		_text_slot("pause_prompt", event_frame.grow(-8), &"hud_body", "center", event_frame, Vector4(8, 8, 8, 8)),
		_text_slot("indoor_marker", resident_frame.grow(-8), &"hud_compact", "center", resident_frame, Vector4(8, 8, 8, 8)),
		_text_slot("operation_state", Rect2(left, top + 76, 248, 48), &"hud_compact", "left", Rect2(left, top + 72, 264, 56), Vector4(8, 4, 8, 4)),
	]
	var targets := [
		_target("openEvent", event_frame),
		_target("focusResident", resident_frame),
		_target("openMapTarget", map_frame),
		_target("openIndoorTarget", resident_frame),
		_target("resume", event_frame),
	]
	_append_observer_v4_targets(targets, safe)
	_append_offscreen_activity_layout(
		text_slots,
		targets,
		offscreen_frame,
		false
	)
	return _layout(&"compact_landscape", safe, text_slots, targets, {
		"topStatus": status_frame,
		"event": event_frame,
		"residentPrimary": resident_frame,
		"residentNearby": Rect2(),
		"mapPrompt": map_frame,
		"indoor": resident_frame,
		"offscreenActivity": offscreen_frame,
	})


static func _compact_portrait_layout(safe: Rect2) -> Dictionary:
	var left := safe.position.x + 8
	var top := safe.position.y + 8
	var right := safe.end.x - 8
	var bottom := safe.end.y - 8
	var width := right - left
	var status_frame := _v4_rect(safe, Rect2(575, 20, 540, 88))
	var event_frame := Rect2(left, top + 88, width, 72)
	var resident_frame := Rect2(left, top + 232, width - 72, 104)
	var map_frame := Rect2(left, top + 348, width - 72, 72)
	var indoor_frame := Rect2(left, top + 432, width - 72, 72)
	var offscreen_frame := Rect2(left, top + 232, width - 72, 56)
	var text_slots := [
		_text_slot("time_weather", _v4_rect(safe, Rect2(610, 34, 382, 60)), &"hud_body", "center", status_frame, Vector4(8, 8, 8, 8)),
		_text_slot("event", event_frame.grow(-8), &"hud_body", "center", event_frame, Vector4(8, 8, 8, 8)),
		_text_slot("resident_primary_name", Rect2(resident_frame.position + Vector2(8, 8), Vector2(resident_frame.size.x - 16, 40)), &"hud_resident_name", "left", resident_frame, Vector4(8, 8, 8, 0)),
		_text_slot("resident_primary_action", Rect2(resident_frame.position + Vector2(8, 54), Vector2(resident_frame.size.x - 16, 40)), &"hud_resident_action", "left", resident_frame, Vector4(8, 0, 8, 10)),
		_text_slot("resident_nearby_name", Rect2(), &"hud_resident_name", "left", Rect2(), Vector4.ZERO),
		_text_slot("resident_nearby_action", Rect2(), &"hud_resident_action", "left", Rect2(), Vector4.ZERO),
		_text_slot("map_prompt", map_frame.grow(-8), &"hud_body", "center", map_frame, Vector4(8, 8, 8, 8)),
		_text_slot("pause_prompt", Rect2(left, top + 88, width, 112).grow(-8), &"hud_body", "center", Rect2(left, top + 88, width, 112), Vector4(8, 8, 8, 8)),
		_text_slot("indoor_marker", indoor_frame.grow(-8), &"hud_compact", "center", indoor_frame, Vector4(8, 8, 8, 8)),
		_text_slot("operation_state", Rect2(left, top + 172, width - 72, 48), &"hud_compact", "left", Rect2(left, top + 168, width - 72, 56), Vector4(8, 4, 8, 4)),
	]
	var targets := [
		_target("openEvent", event_frame),
		_target("focusResident", resident_frame),
		_target("openMapTarget", map_frame),
		_target("openIndoorTarget", indoor_frame),
		_target("resume", Rect2(left, top + 88, width, 112)),
	]
	_append_observer_v4_targets(targets, safe)
	_append_offscreen_activity_layout(
		text_slots,
		targets,
		offscreen_frame,
		false
	)
	return _layout(&"compact_portrait", safe, text_slots, targets, {
		"topStatus": status_frame,
		"event": event_frame,
		"residentPrimary": resident_frame,
		"residentNearby": Rect2(),
		"mapPrompt": map_frame,
		"indoor": indoor_frame,
		"offscreenActivity": offscreen_frame,
	})


static func _append_observer_v4_targets(
	targets: Array,
	safe: Rect2
) -> void:
	var reference_targets := {
		"weatherChange": Rect2(995, 28, 94, 76),
		"nav_residents": Rect2(28, 89, 88, 86),
		"nav_places": Rect2(28, 190, 88, 84),
		"nav_relationships": Rect2(28, 289, 88, 84),
		"nav_log": Rect2(28, 386, 88, 84),
		"nav_bulletin": Rect2(28, 484, 88, 84),
		"nav_settings": Rect2(28, 584, 88, 84),
		"camera_fit": Rect2(1574, 92, 68, 74),
		"camera_zoom_in": Rect2(1574, 184, 68, 74),
		"camera_zoom_out": Rect2(1574, 277, 68, 74),
		"time_pause": Rect2(1568, 392, 68, 68),
		"time_speed_1": Rect2(1568, 469, 68, 68),
		"time_speed_2": Rect2(1568, 545, 68, 68),
		"time_speed_3": Rect2(1568, 621, 68, 68),
		"avatar_toggle": Rect2(775, 831, 126, 96),
	}
	for id: String in reference_targets:
		var reference_rect := reference_targets[id] as Rect2
		var resolved_rect := (
			_bottom_anchored_rect(safe, reference_rect)
			if id == "avatar_toggle"
			else _v4_rect(safe, reference_rect)
		)
		targets.append(_target(
			id,
			_touch_rect(
				resolved_rect,
				safe
			)
		))


static func _v4_rect(safe: Rect2, reference_rect: Rect2) -> Rect2:
	if safe.size.x / safe.size.y < REFERENCE_SIZE.x / REFERENCE_SIZE.y:
		var uniform_scale := safe.size.x / REFERENCE_SIZE.x
		return Rect2(
			safe.position + reference_rect.position * uniform_scale,
			reference_rect.size * uniform_scale,
		)
	var scale := Vector2(
		safe.size.x / REFERENCE_SIZE.x,
		safe.size.y / REFERENCE_SIZE.y
	)
	return Rect2(
		safe.position + reference_rect.position * scale,
		reference_rect.size * scale
	)


static func _bottom_anchored_rect(safe: Rect2, reference_rect: Rect2) -> Rect2:
	if safe.size.x / safe.size.y >= REFERENCE_SIZE.x / REFERENCE_SIZE.y:
		return _v4_rect(safe, reference_rect)
	var uniform_scale := safe.size.x / REFERENCE_SIZE.x
	var scaled_size := reference_rect.size * uniform_scale
	var bottom_inset := (
		REFERENCE_SIZE.y - reference_rect.end.y
	) * uniform_scale
	return Rect2(
		Vector2(
			safe.position.x + reference_rect.position.x * uniform_scale,
			safe.end.y - bottom_inset - scaled_size.y,
		),
		scaled_size,
	)
static func _touch_rect(rect: Rect2, safe: Rect2) -> Rect2:
	var resolved_size := Vector2(
		maxf(rect.size.x, MINIMUM_TOUCH_TARGET.x + 2.0),
		maxf(rect.size.y, MINIMUM_TOUCH_TARGET.y + 2.0)
	)
	var resolved_position := rect.get_center() - resolved_size * 0.5
	resolved_position.x = clampf(
		resolved_position.x,
		safe.position.x,
		maxf(safe.position.x, safe.end.x - resolved_size.x)
	)
	resolved_position.y = clampf(
		resolved_position.y,
		safe.position.y,
		maxf(safe.position.y, safe.end.y - resolved_size.y)
	)
	return Rect2(resolved_position, resolved_size)


static func _append_offscreen_activity_layout(
	text_slots: Array,
	targets: Array,
	frame: Rect2,
	expanded: bool
) -> void:
	if expanded:
		var row_height := floorf(frame.size.y / 3.0)
		var text_x := frame.position.x + roundf(frame.size.x * 0.22)
		var direction_width := 44.0
		var direction_x := frame.end.x - direction_width - 8.0
		var summary_width := maxf(48.0, direction_x - text_x - 8.0)
		for index: int in range(2):
			var row_frame := Rect2(
				Vector2(frame.position.x, frame.position.y + index * row_height),
				Vector2(frame.size.x, row_height)
			)
			text_slots.append(_text_slot(
				"offscreen_%d_summary" % index,
				Rect2(
					Vector2(text_x, row_frame.position.y + 8),
					Vector2(summary_width, row_height - 16)
				),
				&"hud_compact",
				"left",
				row_frame,
				Vector4(8, 8, 8, 8)
			))
			text_slots.append(_text_slot(
				"offscreen_%d_direction" % index,
				Rect2(
					Vector2(direction_x, row_frame.position.y + 8),
					Vector2(direction_width, row_height - 16)
				),
				&"hud_compact",
				"center",
				row_frame,
				Vector4(8, 8, 8, 8)
			))
			targets.append(_target(
				"offscreenActivity%d" % index,
				row_frame
			))
		var aggregate_frame := Rect2(
			Vector2(frame.position.x, frame.position.y + row_height * 2.0),
			Vector2(frame.size.x, frame.size.y - row_height * 2.0)
		)
		text_slots.append(_text_slot(
			"offscreen_aggregate",
			aggregate_frame.grow(-8),
			&"hud_compact",
			"center",
			aggregate_frame,
			Vector4(8, 8, 8, 8)
		))
		return
	text_slots.append(_text_slot(
		"offscreen_0_summary",
		Rect2(
			frame.position + Vector2(52, 6),
			Vector2(maxf(48.0, frame.size.x - 108), frame.size.y - 12)
		),
		&"hud_compact",
		"left",
		frame,
		Vector4(8, 6, 8, 6)
	))
	text_slots.append(_text_slot(
		"offscreen_0_direction",
		Rect2(
			Vector2(frame.end.x - 48, frame.position.y + 6),
			Vector2(40, frame.size.y - 12)
		),
		&"hud_compact",
		"center",
		frame,
		Vector4(8, 6, 8, 6)
	))
	for id: String in [
		"offscreen_1_summary",
		"offscreen_1_direction",
		"offscreen_aggregate",
	]:
		text_slots.append(_text_slot(
			id,
			Rect2(),
			&"hud_compact",
			"left",
			frame,
			Vector4.ZERO
		))
	targets.append(_target("offscreenActivity0", frame))
	targets.append(_target("offscreenActivity1", Rect2()))


static func _layout(
	breakpoint_id: StringName,
	safe: Rect2,
	text_slots_value: Array,
	targets_value: Array,
	frames: Dictionary
) -> Dictionary:
	return {
		"revision": REVISION,
		"formalReady": FORMAL_READY,
		"breakpoint": breakpoint_id,
		"safeRect": safe,
		"rootScale": Vector2.ONE,
		"layoutMode": "semantic_reflow",
		"textSlots": text_slots_value,
		"targets": targets_value,
		"frames": frames,
	}


static func _text_slot(
	id: String,
	rect: Rect2,
	role: StringName,
	alignment: String,
	frame_rect: Rect2,
	frame_insets: Vector4,
	painted_safe_rect: Rect2 = Rect2(),
	expected_ink_rect: Rect2 = Rect2()
) -> Dictionary:
	var resolved_safe_rect := (
		painted_safe_rect if painted_safe_rect.has_area() else rect
	)
	return {
		"id": id,
		"rect": rect,
		"paintedSafeRect": resolved_safe_rect,
		"expectedInkRect": expected_ink_rect,
		"frameRect": frame_rect,
		"frameInsets": frame_insets,
		"fontRole": role,
		"fontSize": int(FONT_ROLE_SIZES.get(role, 32)),
		"alignment": alignment,
		"drawsVisibleBorder": false,
		"borderOwner": "runtime_skin_asset",
	}


static func _target(id: String, rect: Rect2) -> Dictionary:
	return {
		"id": id,
		"rect": rect,
		"minimumSize": MINIMUM_TOUCH_TARGET,
		"drawsVisibleBorder": false,
		"focusFeedback": "fill_only",
	}


static func _snap_layout_to_physical(
	layout: Dictionary,
	physical_scale: Vector2
) -> Dictionary:
	var scale_x := physical_scale.x if physical_scale.x > 0.0 else 1.0
	var scale_y := physical_scale.y if physical_scale.y > 0.0 else 1.0
	var snapped := layout.duplicate(true)
	snapped["safeRect"] = _snap_rect(
		snapped.get("safeRect", Rect2()),
		scale_x,
		scale_y
	)
	var snapped_slots: Array = []
	for slot_value: Variant in snapped.get("textSlots", []):
		var slot := (slot_value as Dictionary).duplicate(true)
		for rect_key: String in [
			"rect",
			"paintedSafeRect",
			"expectedInkRect",
			"frameRect",
		]:
			slot[rect_key] = _snap_rect(
				slot.get(rect_key, Rect2()),
				scale_x,
				scale_y
			)
		snapped_slots.append(slot)
	snapped["textSlots"] = snapped_slots
	var snapped_targets: Array = []
	for target_value: Variant in snapped.get("targets", []):
		var target := (target_value as Dictionary).duplicate(true)
		target["rect"] = _snap_rect(
			target.get("rect", Rect2()),
			scale_x,
			scale_y
		)
		snapped_targets.append(target)
	snapped["targets"] = snapped_targets
	var snapped_frames := {}
	for frame_key: Variant in (snapped.get("frames", {}) as Dictionary):
		snapped_frames[frame_key] = _snap_rect(
			(snapped["frames"] as Dictionary)[frame_key],
			scale_x,
			scale_y
		)
	snapped["frames"] = snapped_frames
	snapped["physicalScale"] = Vector2(scale_x, scale_y)
	return snapped


static func _snap_rect(
	rect: Rect2,
	scale_x: float,
	scale_y: float
) -> Rect2:
	return Rect2(
		Vector2(
			roundf(rect.position.x * scale_x) / scale_x,
			roundf(rect.position.y * scale_y) / scale_y
		),
		Vector2(
			roundf(rect.size.x * scale_x) / scale_x,
			roundf(rect.size.y * scale_y) / scale_y
		)
	)
