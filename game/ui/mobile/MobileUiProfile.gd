class_name MobileUiProfile
extends RefCounted


const PHONE_SHORT_SIDE_MAX := 720.0
const MINIMUM_TOUCH_TARGET := 48.0
const PHONE_LANDSCAPE := "phone_landscape"
const PHONE_PORTRAIT := "phone_portrait"
const DESKTOP_COMPACT := "desktop_compact"
const DESKTOP_WIDE := "desktop_wide"
const LANDSCAPE_4_3 := Vector2(2048.0, 1536.0)
const LANDSCAPE_3_2 := Vector2(2160.0, 1440.0)
const LANDSCAPE_16_10 := Vector2(2560.0, 1600.0)
const LANDSCAPE_16_9 := Vector2(2400.0, 1350.0)
const LANDSCAPE_21_9 := Vector2(2520.0, 1080.0)
const ADAPTIVE_LANDSCAPE_TEST_SIZES: Array[Vector2] = [
	LANDSCAPE_4_3,
	LANDSCAPE_3_2,
	LANDSCAPE_16_10,
	LANDSCAPE_16_9,
	LANDSCAPE_21_9,
]


static func is_mobile_runtime() -> bool:
	return OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"]


static func input_mode(_viewport_size: Vector2 = Vector2.ZERO) -> String:
	# Window proportions must never switch a desktop build into touch mode.
	return "touch" if is_mobile_runtime() else "keyboard_mouse"


static func is_phone_landscape(viewport_size: Vector2) -> bool:
	return (
		viewport_size.x >= viewport_size.y
		and minf(viewport_size.x, viewport_size.y) <= PHONE_SHORT_SIDE_MAX
	)


static func layout_profile(viewport_size: Vector2) -> String:
	if is_mobile_runtime():
		return PHONE_LANDSCAPE if viewport_size.x >= viewport_size.y else PHONE_PORTRAIT
	if viewport_size.x < 1440.0 or viewport_size.y < 810.0:
		return DESKTOP_COMPACT
	return DESKTOP_WIDE


static func window_width_class(viewport_size: Vector2, density := 1.0) -> String:
	var dp_width := viewport_size.x / maxf(0.1, density)
	if dp_width < 600.0:
		return "compact"
	if dp_width < 840.0:
		return "medium"
	return "expanded"


static func uniform_cover_scale(
	viewport_size: Vector2,
	content_size: Vector2,
	margin := 1.0,
) -> float:
	if (
		viewport_size.x <= 0.0
		or viewport_size.y <= 0.0
		or content_size.x <= 0.0
		or content_size.y <= 0.0
	):
		return 1.0
	return maxf(
		viewport_size.x / content_size.x,
		viewport_size.y / content_size.y,
	) * maxf(margin, 1.0)


static func safe_rect(viewport_size: Vector2, insets: Vector4) -> Rect2:
	return Rect2(
		Vector2(maxf(0.0, insets.x), maxf(0.0, insets.y)),
		Vector2(
			maxf(1.0, viewport_size.x - maxf(0.0, insets.x) - maxf(0.0, insets.z)),
			maxf(1.0, viewport_size.y - maxf(0.0, insets.y) - maxf(0.0, insets.w)),
		),
	)


static func centered_design_rect(
	viewport_size: Vector2,
	design_size: Vector2,
	insets: Vector4 = Vector4.ZERO,
) -> Rect2:
	var safe := safe_rect(viewport_size, insets)
	if design_size.x <= 0.0 or design_size.y <= 0.0:
		return Rect2()
	var scale_factor := minf(
		safe.size.x / design_size.x,
		safe.size.y / design_size.y,
	)
	var display_size := design_size * scale_factor
	return Rect2(
		safe.position + (safe.size - display_size) * 0.5,
		display_size,
	)


static func adaptive_landscape_band(viewport_size: Vector2) -> String:
	var aspect := viewport_size.x / maxf(1.0, viewport_size.y)
	if aspect < 1.42:
		return "tablet_4_3"
	if aspect < 1.70:
		return "foldable_or_tablet"
	if aspect < 2.08:
		return "standard_landscape"
	return "ultrawide_phone"


static func insets_vector(viewport_size: Vector2, window: Window) -> Vector4:
	var values := safe_insets(viewport_size, window)
	return Vector4(
		float(values.get("left", 0.0)),
		float(values.get("top", 0.0)),
		float(values.get("right", 0.0)),
		float(values.get("bottom", 0.0)),
	)


static func safe_insets(viewport_size: Vector2, window: Window) -> Dictionary:
	var result := {"top": 0.0, "right": 0.0, "bottom": 0.0, "left": 0.0}
	if window == null:
		return result
	var window_size := Vector2(window.size)
	var safe_area := DisplayServer.get_display_safe_area()
	if (
		window_size.x <= 0.0
		or window_size.y <= 0.0
		or safe_area.size.x <= 0
		or safe_area.size.y <= 0
		or safe_area.size.x > window_size.x
		or safe_area.size.y > window_size.y
	):
		return result
	var scale := viewport_size / window_size
	result["left"] = safe_area.position.x * scale.x
	result["top"] = safe_area.position.y * scale.y
	result["right"] = (window_size.x - safe_area.end.x) * scale.x
	result["bottom"] = (window_size.y - safe_area.end.y) * scale.y
	return result
