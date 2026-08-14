class_name TownOutdoorSurfaceMask
extends RefCounted


const WALKABILITY_MASK_PATH := (
	"res://world/presentation/environment/assets/town_dry_walkability_mask.bin"
)
# Generated losslessly from the former surface-mask plus town-map formula by
# tools/build_town_auxiliary_masks.py. Runtime movement only needs this binary
# answer and must not retain either full RGBA authoring image.
const SEGMENT_SAMPLE_STEP_PX := 3
const MOVEMENT_CLEARANCE := preload(
	"res://world/data/town/TownOutdoorMovementClearance.gd"
)

const WALKABILITY_MAGIC := "ATWM"
const WALKABILITY_VERSION := 1
const WALKABILITY_HEADER_SIZE := 16

static var _cached_bits := PackedByteArray()


static func data() -> PackedByteArray:
	if not _cached_bits.is_empty():
		return _cached_bits
	var file := FileAccess.open(WALKABILITY_MASK_PATH, FileAccess.READ)
	if file == null or file.get_length() < WALKABILITY_HEADER_SIZE:
		return PackedByteArray()
	if file.get_buffer(4).get_string_from_ascii() != WALKABILITY_MAGIC:
		return PackedByteArray()
	if file.get_32() != WALKABILITY_VERSION:
		return PackedByteArray()
	var map_size := Vector2i(MOVEMENT_CLEARANCE.MAP_SIZE)
	if file.get_32() != map_size.x or file.get_32() != map_size.y:
		return PackedByteArray()
	var expected_size := ceili(float(map_size.x * map_size.y) / 8.0)
	if file.get_length() != WALKABILITY_HEADER_SIZE + expected_size:
		return PackedByteArray()
	var loaded_bits := file.get_buffer(expected_size)
	if loaded_bits.size() != expected_size:
		return PackedByteArray()
	_cached_bits = loaded_bits
	return _cached_bits


static func reset_cache() -> void:
	_cached_bits = PackedByteArray()


static func body_origin_is_dry(
	body_origin: Vector2,
	walkability_bits: PackedByteArray = PackedByteArray(),
) -> bool:
	if not body_origin.is_finite():
		return false
	var bits := walkability_bits if not walkability_bits.is_empty() else data()
	if bits.is_empty():
		return false
	var feet_center := body_origin + MOVEMENT_CLEARANCE.FEET_CENTER_OFFSET
	var pixel := Vector2i(roundi(feet_center.x), roundi(feet_center.y))
	if (
		pixel.x < 0
		or pixel.y < 0
		or pixel.x >= MOVEMENT_CLEARANCE.MAP_SIZE.x
		or pixel.y >= MOVEMENT_CLEARANCE.MAP_SIZE.y
	):
		return false
	var index := pixel.y * int(MOVEMENT_CLEARANCE.MAP_SIZE.x) + pixel.x
	return (bits[index >> 3] & (1 << (index & 7))) != 0


static func body_segment_is_dry(
	from_body_origin: Vector2,
	to_body_origin: Vector2,
	walkability_bits: PackedByteArray = PackedByteArray(),
) -> bool:
	if not from_body_origin.is_finite() or not to_body_origin.is_finite():
		return false
	var bits := walkability_bits if not walkability_bits.is_empty() else data()
	if bits.is_empty():
		return false
	var distance := from_body_origin.distance_to(to_body_origin)
	var samples := maxi(1, ceili(distance / float(SEGMENT_SAMPLE_STEP_PX)))
	for index: int in range(samples + 1):
		if not body_origin_is_dry(
			from_body_origin.lerp(
				to_body_origin,
				float(index) / float(samples),
			),
			bits,
		):
			return false
	return true
