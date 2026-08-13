class_name TownOutdoorSurfaceMask
extends RefCounted


const SURFACE_MASK_PATH := (
	"res://world/presentation/environment/assets/town_surface_masks.png"
)
const TOWN_MAP_PATH := "res://world/maps/town/assets/runtime/town_4k.png"
const WATER_THRESHOLD := 0.01
const GROUND_THRESHOLD := 0.01
const SEGMENT_SAMPLE_STEP_PX := 3
const MOVEMENT_CLEARANCE := preload(
	"res://world/data/town/TownOutdoorMovementClearance.gd"
)

static var _cached_image: Image
static var _cached_town_image: Image


static func image() -> Image:
	if _cached_image != null and not _cached_image.is_empty():
		return _cached_image
	var texture := load(SURFACE_MASK_PATH) as Texture2D
	if texture == null:
		return null
	var loaded_image := texture.get_image()
	if (
		loaded_image == null
		or loaded_image.is_empty()
		or loaded_image.get_size() != Vector2i(MOVEMENT_CLEARANCE.MAP_SIZE)
	):
		return null
	_cached_image = loaded_image
	return _cached_image


static func reset_cache() -> void:
	_cached_image = null
	_cached_town_image = null


static func body_origin_is_dry(
	body_origin: Vector2,
	surface_image: Image = null,
) -> bool:
	if not body_origin.is_finite():
		return false
	var mask := surface_image if surface_image != null else image()
	if mask == null or mask.is_empty():
		return false
	var feet_center := body_origin + MOVEMENT_CLEARANCE.FEET_CENTER_OFFSET
	var pixel := Vector2i(roundi(feet_center.x), roundi(feet_center.y))
	if (
		pixel.x < 0
		or pixel.y < 0
		or pixel.x >= mask.get_width()
		or pixel.y >= mask.get_height()
	):
		return false
	var surface := mask.get_pixelv(pixel)
	if surface.r > WATER_THRESHOLD:
		return false
	if surface.g > GROUND_THRESHOLD:
		return true
	var town := _town_image()
	return town != null and not _looks_like_water(_town_color_at_map_pixel(town, pixel))


static func body_segment_is_dry(
	from_body_origin: Vector2,
	to_body_origin: Vector2,
	surface_image: Image = null,
) -> bool:
	if not from_body_origin.is_finite() or not to_body_origin.is_finite():
		return false
	var mask := surface_image if surface_image != null else image()
	if mask == null or mask.is_empty():
		return false
	var distance := from_body_origin.distance_to(to_body_origin)
	var samples := maxi(1, ceili(distance / float(SEGMENT_SAMPLE_STEP_PX)))
	for index: int in range(samples + 1):
		if not body_origin_is_dry(
			from_body_origin.lerp(
				to_body_origin,
				float(index) / float(samples),
			),
			mask,
		):
			return false
	return true


static func _town_image() -> Image:
	if _cached_town_image != null and not _cached_town_image.is_empty():
		return _cached_town_image
	var texture := load(TOWN_MAP_PATH) as Texture2D
	if texture == null:
		return null
	var loaded_image := texture.get_image()
	if loaded_image == null or loaded_image.is_empty():
		return null
	_cached_town_image = loaded_image
	return _cached_town_image


static func _town_color_at_map_pixel(town: Image, map_pixel: Vector2i) -> Color:
	var map_size := Vector2i(MOVEMENT_CLEARANCE.MAP_SIZE)
	var image_size := town.get_size()
	if image_size == map_size:
		return town.get_pixelv(map_pixel)
	var image_pixel := Vector2i(
		roundi(float(map_pixel.x) * float(image_size.x - 1) / float(map_size.x - 1)),
		roundi(float(map_pixel.y) * float(image_size.y - 1) / float(map_size.y - 1)),
	)
	return town.get_pixelv(image_pixel)


static func _looks_like_water(color: Color) -> bool:
	var blue_bias := color.b - maxf(color.r, color.g * 0.82)
	var cyan_bias := minf(color.g, color.b) - color.r * 1.12
	var brightness := maxf(color.r, maxf(color.g, color.b))
	return blue_bias > 0.035 and cyan_bias > 0.02 and brightness > 0.40
