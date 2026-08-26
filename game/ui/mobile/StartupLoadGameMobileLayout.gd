class_name StartupLoadGameMobileLayout
extends RefCounted


const MINIMUM_TOUCH_TARGET := 48.0
const ACTION_GAP := 8.0
const ACTION_GROUP_HEIGHT := MINIMUM_TOUCH_TARGET * 2.0 + ACTION_GAP


static func action_rects(
	canvas_size: Vector2,
	display_size: Vector2,
	row_index: int,
	row_count: int,
) -> Dictionary:
	if (
		canvas_size.x <= 0.0
		or canvas_size.y <= 0.0
		or display_size.x <= 0.0
		or display_size.y <= 0.0
		or row_count <= 0
	):
		return {}
	var margin := 8.0
	var right_zone_left := ceilf(display_size.x * 0.53)
	var right := floorf(display_size.x - margin)
	var available_width := right - right_zone_left
	# The approved primary button theme has a wider intrinsic minimum than the
	# icon/text actions. Reserve that width in display pixels before placing the
	# delete/edit column so Godot's theme minimum cannot make the controls overlap.
	var primary_width := clampf(available_width * 0.4, 132.0, 160.0)
	var secondary_width := available_width - primary_width - ACTION_GAP
	if secondary_width < MINIMUM_TOUCH_TARGET:
		primary_width = maxf(
			MINIMUM_TOUCH_TARGET,
			primary_width - (MINIMUM_TOUCH_TARGET - secondary_width),
		)
		secondary_width = MINIMUM_TOUCH_TARGET
	var area_top := maxf(118.0, display_size.y * 0.23)
	var area_bottom := display_size.y - maxf(64.0, display_size.y * 0.12)
	var available_height := maxf(
		ACTION_GROUP_HEIGHT,
		area_bottom - area_top,
	)
	var row_step := ACTION_GROUP_HEIGHT
	if row_count > 1:
		row_step = clampf(
			(available_height - ACTION_GROUP_HEIGHT) / float(row_count - 1),
			ACTION_GROUP_HEIGHT,
			132.0,
		)
	var top := roundf(area_top + float(row_index) * row_step)
	var secondary_left := right_zone_left + primary_width + ACTION_GAP
	var display_rects := {
		"primary": Rect2(
			right_zone_left,
			top,
			primary_width,
			ACTION_GROUP_HEIGHT,
		),
		"delete": Rect2(
			secondary_left,
			top,
			secondary_width,
			MINIMUM_TOUCH_TARGET,
		),
		"edit": Rect2(
			secondary_left,
			top + MINIMUM_TOUCH_TARGET + ACTION_GAP,
			secondary_width,
			MINIMUM_TOUCH_TARGET,
		),
	}
	var to_canvas := canvas_size / display_size
	var result: Dictionary = {}
	for role: String in display_rects:
		var rect := display_rects[role] as Rect2
		result[role] = Rect2(
			rect.position * to_canvas,
			rect.size * to_canvas,
		)
	return result
