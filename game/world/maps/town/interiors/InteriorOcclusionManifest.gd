class_name InteriorOcclusionManifest
extends RefCounted

const PATH_RESOLVER := preload(
	"res://world/maps/town/interiors/InteriorOcclusionManifestPathResolver.gd"
)

const SCHEMA_VERSION := 2
const MAX_SEGMENTS := 256
const MAX_POLYGON_POINTS := 4096
const MAX_POLYGONS_PER_SEGMENT := 64
const MAX_TOTAL_POLYGON_POINTS := 32768
const MAX_CANVAS_COMPONENT := 65536.0
const MAX_CANVAS_PIXELS := 16777216
const MAX_JSON_BYTES := 8388608
const MAX_ID_LENGTH := 128
const MAX_REVISION_LENGTH := 256
const MANIFEST_KEYS := [
	"canvas_size_px",
	"room_id",
	"schema_version",
	"segments",
	"source_geometry_revision",
	"source_geometry_sha256",
	"source_occlusion_revision",
	"source_occlusion_sha256",
	"source_shell_path",
	"source_shell_sha256",
]
const SEGMENT_KEYS := [
	"fade_distance_px",
	"foreground_canvas_origin_px",
	"foreground_texture_path",
	"foreground_texture_sha256",
	"foreground_texture_size_px",
	"id",
	"minimum_alpha",
	"reveal_polygons_canvas_px",
]

var _validation_active := false
var _pending_canvas_size := Vector2i.ZERO
var _pending_segment_values: Array = []
var _pending_segment_index := 0
var _pending_ids: Dictionary = {}
var _pending_polygon_points := 0
var _validated_segments: Array[Dictionary] = []
var _file_only_texture_validation := false


func set_file_only_texture_validation(enabled: bool) -> void:
	_file_only_texture_validation = enabled


func load_validated(
	geometry_value: Variant,
	geometry_path_value: Variant,
	occlusion_path_value: Variant,
	shell_path_value: Variant,
) -> Dictionary:
	var begun := begin_load_staged(
		geometry_value,
		geometry_path_value,
		occlusion_path_value,
		shell_path_value,
	)
	if begun.get("ok") != true:
		return begun
	while _validation_active:
		var step := validate_next_segment()
		if step.get("ok") != true:
			return step
	return {"ok": true, "segments": get_validated_segments()}


func begin_load_staged(
	geometry_value: Variant,
	geometry_path_value: Variant,
	occlusion_path_value: Variant,
	shell_path_value: Variant,
) -> Dictionary:
	if (
		geometry_value is not Dictionary
		or geometry_path_value is not String
		or occlusion_path_value is not String
		or shell_path_value is not String
	):
		return _failure("INVALID_INPUT", "manifest inputs have invalid types")
	var geometry := geometry_value as Dictionary
	var geometry_path := _resource_path(geometry_path_value)
	var occlusion_path := _resource_path(occlusion_path_value)
	var shell_path := _resource_path(shell_path_value)
	if geometry_path.is_empty() or occlusion_path.is_empty() or shell_path.is_empty():
		return _failure("INVALID_PATH", "manifest source paths are invalid")
	var manifest_path := occlusion_path.get_base_dir().path_join(
		"wall_occlusion_runtime.json",
	)
	var resolved_path := PATH_RESOLVER.resolve(manifest_path, occlusion_path) as Dictionary
	if resolved_path.get("ok") != true:
		return _failure(
			"PUBLISH_TRANSACTION_INVALID",
			String(resolved_path.get("error", "publish transaction is invalid")),
		)
	manifest_path = String(resolved_path.get("path", ""))
	var manifest := _load_data(manifest_path)
	if manifest.is_empty():
		return _failure("MANIFEST_MISSING", "generated manifest is missing")
	var authored_occlusion := _load_data(occlusion_path)
	if authored_occlusion.is_empty():
		return _failure("OCCLUSION_SOURCE_MISSING", "authored occlusion is missing")
	return begin_validation(
		manifest,
		geometry,
		authored_occlusion,
		geometry_path,
		occlusion_path,
		shell_path,
	)


func validate(
	data: Dictionary,
	geometry: Dictionary,
	authored_occlusion: Dictionary,
	geometry_path: String,
	occlusion_path: String,
	shell_path: String,
) -> Dictionary:
	var begun := begin_validation(
		data,
		geometry,
		authored_occlusion,
		geometry_path,
		occlusion_path,
		shell_path,
	)
	if begun.get("ok") != true:
		return begun
	while _validation_active:
		var step := validate_next_segment()
		if step.get("ok") != true:
			return step
	return {"ok": true, "segments": get_validated_segments()}


func begin_validation(
	data: Dictionary,
	geometry: Dictionary,
	authored_occlusion: Dictionary,
	geometry_path: String,
	occlusion_path: String,
	shell_path: String,
) -> Dictionary:
	_reset_staged_validation()
	if not _keys_equal(data, MANIFEST_KEYS):
		return _failure("MANIFEST_SHAPE_INVALID", "generated manifest keys are invalid")
	if not _exact_integer(data.get("schema_version"), SCHEMA_VERSION):
		return _failure("MANIFEST_VERSION_STALE", "generated manifest schema is stale")
	var canvas_size := _canvas_size(geometry.get("canvas_size_px"))
	var room_id := _canonical_id(geometry.get("room_id"), MAX_ID_LENGTH)
	var geometry_revision := _canonical_text_limited(
		geometry.get("source_revision"),
		MAX_REVISION_LENGTH,
	)
	var occlusion_revision := _canonical_text_limited(
		authored_occlusion.get("source_revision"),
		MAX_REVISION_LENGTH,
	)
	if canvas_size == Vector2i.ZERO or canvas_size.x * canvas_size.y > MAX_CANVAS_PIXELS:
		return _failure("CANVAS_INVALID", "room canvas is invalid")
	if room_id.is_empty() or _canonical_id(data.get("room_id"), MAX_ID_LENGTH) != room_id:
		return _failure("ROOM_ID_MISMATCH", "room identity does not match")
	if _canvas_size(data.get("canvas_size_px")) != canvas_size:
		return _failure("CANVAS_MISMATCH", "room canvas does not match")
	if geometry_revision.is_empty():
		return _failure("GEOMETRY_REVISION_MISSING", "geometry revision is required")
	if (
		_canonical_text_limited(
			data.get("source_geometry_revision"),
			MAX_REVISION_LENGTH,
		) != geometry_revision
	):
		return _failure("GEOMETRY_REVISION_STALE", "geometry revision is stale")
	if occlusion_revision.is_empty():
		return _failure("OCCLUSION_REVISION_MISSING", "occlusion revision is required")
	if (
		_canonical_text_limited(
			data.get("source_occlusion_revision"),
			MAX_REVISION_LENGTH,
		) != occlusion_revision
	):
		return _failure("OCCLUSION_REVISION_STALE", "occlusion revision is stale")
	if _resource_path(data.get("source_shell_path")) != shell_path:
		return _failure("SHELL_PATH_MISMATCH", "shell path does not match")
	if not _finite_pair(geometry.get("world_origin_px")):
		return _failure("WORLD_ORIGIN_INVALID", "room world origin is invalid")
	if not _source_matches(geometry_path, data.get("source_geometry_sha256")):
		return _failure("GEOMETRY_DIGEST_STALE", "geometry digest is stale")
	if not _source_matches(occlusion_path, data.get("source_occlusion_sha256")):
		return _failure("OCCLUSION_DIGEST_STALE", "occlusion digest is stale")
	if not _source_matches(shell_path, data.get("source_shell_sha256")):
		return _failure("SHELL_DIGEST_STALE", "shell digest is stale")
	var segment_values: Variant = data.get("segments")
	if (
		segment_values is not Array
		or (segment_values as Array).is_empty()
		or (segment_values as Array).size() > MAX_SEGMENTS
	):
		return _failure("SEGMENTS_INVALID", "generated segments are invalid")
	_pending_canvas_size = canvas_size
	_pending_segment_values = (segment_values as Array).duplicate(true)
	_validation_active = true
	return {"ok": true, "complete": false}


func validate_next_segment() -> Dictionary:
	if not _validation_active:
		return _failure("VALIDATION_NOT_ACTIVE", "staged validation is not active")
	if _pending_segment_index >= _pending_segment_values.size():
		_validation_active = false
		return {"ok": true, "complete": true}
	var value: Variant = _pending_segment_values[_pending_segment_index]
	if value is not Dictionary:
		return _abort_validation("SEGMENT_INVALID", "generated segment is not a dictionary")
	var segment := value as Dictionary
	if not _keys_equal(segment, SEGMENT_KEYS):
		return _abort_validation("SEGMENT_SHAPE_INVALID", "generated segment keys are invalid")
	var segment_id := _canonical_id(segment.get("id"), MAX_ID_LENGTH)
	var texture_path := _resource_path(segment.get("foreground_texture_path"))
	var texture_size := _canvas_size(segment.get("foreground_texture_size_px"))
	if segment_id.is_empty() or _pending_ids.has(segment_id):
		return _abort_validation("SEGMENT_ID_INVALID", "segment id is invalid or duplicated")
	if texture_path.is_empty() or texture_size == Vector2i.ZERO:
		return _abort_validation("TEXTURE_METADATA_INVALID", "segment texture metadata is invalid")
	if not _source_matches(texture_path, segment.get("foreground_texture_sha256")):
		return _abort_validation("TEXTURE_DIGEST_STALE", "segment texture digest is stale")
	if not _texture_matches_size(texture_path, texture_size):
		return _abort_validation("TEXTURE_SIZE_MISMATCH", "segment texture size does not match")
	if not _finite_pair(segment.get("foreground_canvas_origin_px")):
		return _abort_validation("TEXTURE_ORIGIN_INVALID", "segment texture origin is invalid")
	var origin := _pair(segment.get("foreground_canvas_origin_px"))
	if (
		origin.x < 0.0
		or origin.y < 0.0
		or origin.x + texture_size.x > _pending_canvas_size.x
		or origin.y + texture_size.y > _pending_canvas_size.y
	):
		return _abort_validation("TEXTURE_BOUNDS_INVALID", "segment texture exceeds the room canvas")
	_pending_ids[segment_id] = true
	var occlusion_fields := validate_segment_occlusion_fields(
		segment,
		_pending_canvas_size,
		_pending_polygon_points,
	)
	if occlusion_fields.get("ok") != true:
		return _abort_validation(
			String(occlusion_fields.get("code", "SEGMENT_INVALID")),
			String(occlusion_fields.get("error", "segment fields are invalid")),
		)
	_pending_polygon_points = int(occlusion_fields.get("polygon_points", 0))
	var validated_segment := segment.duplicate(true)
	_validated_segments.append(validated_segment)
	_pending_segment_index += 1
	var complete := _pending_segment_index >= _pending_segment_values.size()
	if complete:
		_validation_active = false
	return {
		"ok": true,
		"complete": complete,
		"segment": validated_segment,
	}


func get_validated_segments() -> Array[Dictionary]:
	return _validated_segments.duplicate(true)


func validate_segment_occlusion_fields(
	segment: Dictionary,
	canvas_size: Vector2i,
	accumulated_polygon_points: int = 0,
) -> Dictionary:
	if not _valid_fade(segment):
		return _failure("FADE_INVALID", "segment fade values are invalid")
	var reveal_values: Variant = segment.get("reveal_polygons_canvas_px")
	if (
		reveal_values is not Array
		or (reveal_values as Array).is_empty()
		or (reveal_values as Array).size() > MAX_POLYGONS_PER_SEGMENT
	):
		return _failure(
			"REVEAL_POLYGONS_INVALID",
			"segment reveal polygons are invalid",
		)
	var polygon_points := accumulated_polygon_points
	for polygon_value: Variant in reveal_values as Array:
		var polygon := _polygon(polygon_value, canvas_size)
		if not _valid_polygon(polygon):
			return _failure(
				"REVEAL_POLYGON_INVALID",
				"segment reveal polygon is invalid",
			)
		polygon_points += polygon.size()
		if polygon_points > MAX_TOTAL_POLYGON_POINTS:
			return _failure(
				"POLYGON_LIMIT_EXCEEDED",
				"generated polygons exceed the limit",
			)
	return {"ok": true, "polygon_points": polygon_points}


func _abort_validation(code: String, error: String) -> Dictionary:
	_validation_active = false
	return _failure(code, error)


func _reset_staged_validation() -> void:
	_validation_active = false
	_pending_canvas_size = Vector2i.ZERO
	_pending_segment_values.clear()
	_pending_segment_index = 0
	_pending_ids.clear()
	_pending_polygon_points = 0
	_validated_segments.clear()


func _valid_fade(segment: Dictionary) -> bool:
	return (
		_finite_number(segment.get("fade_distance_px"))
		and float(segment.get("fade_distance_px")) > 0.0
		and _finite_number(segment.get("minimum_alpha"))
		and float(segment.get("minimum_alpha")) >= 0.0
		and float(segment.get("minimum_alpha")) <= 1.0
	)


func _source_matches(path: String, expected_value: Variant) -> bool:
	var expected := _canonical_hash(expected_value)
	return (
		not expected.is_empty()
		and FileAccess.file_exists(path)
		and FileAccess.get_sha256(path) == expected
	)


func _texture_matches_size(path: String, expected_size: Vector2i) -> bool:
	if _file_only_texture_validation:
		if not FileAccess.file_exists(path):
			return false
		var image := Image.new()
		return (
			image.load(ProjectSettings.globalize_path(path)) == OK
			and image.get_size() == expected_size
		)
	var texture := _load_texture(path)
	return texture != null and Vector2i(texture.get_size()) == expected_size


func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path, "Texture2D"):
		var imported := ResourceLoader.load(path, "Texture2D") as Texture2D
		if imported != null:
			return imported
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(path)) != OK:
		return null
	return ImageTexture.create_from_image(image)


func _load_data(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() <= 0 or file.get_length() > MAX_JSON_BYTES:
		return {}
	var text := file.get_as_text()
	file.close()
	if text.to_utf8_buffer().size() > MAX_JSON_BYTES:
		return {}
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else {}


func _valid_polygon(polygon: PackedVector2Array) -> bool:
	if polygon.size() < 3 or polygon.size() > MAX_POLYGON_POINTS:
		return false
	var seen_points := {}
	for index in range(polygon.size()):
		var point := polygon[index]
		if seen_points.has(point) or point == polygon[(index + 1) % polygon.size()]:
			return false
		seen_points[point] = true
	return (
		absf(_signed_area(polygon)) > 0.0001
		and not Geometry2D.triangulate_polygon(polygon).is_empty()
	)


func _signed_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for index in range(polygon.size()):
		var current := polygon[index]
		var next := polygon[(index + 1) % polygon.size()]
		area += current.x * next.y - next.x * current.y
	return area * 0.5


func _polygon(value: Variant, canvas_size: Vector2i) -> PackedVector2Array:
	var points := PackedVector2Array()
	if value is not Array or (value as Array).size() > MAX_POLYGON_POINTS:
		return points
	for point_value: Variant in value as Array:
		if not _finite_pair(point_value):
			return PackedVector2Array()
		var point := _pair(point_value)
		if (
			point.x < 0.0
			or point.y < 0.0
			or point.x > canvas_size.x
			or point.y > canvas_size.y
		):
			return PackedVector2Array()
		points.append(point)
	return points


func _canvas_size(value: Variant) -> Vector2i:
	if value is not Array or (value as Array).size() != 2:
		return Vector2i.ZERO
	var pair := value as Array
	if not _positive_integer(pair[0]) or not _positive_integer(pair[1]):
		return Vector2i.ZERO
	return Vector2i(int(pair[0]), int(pair[1]))


func _pair(value: Variant) -> Vector2:
	var pair := value as Array
	return Vector2(float(pair[0]), float(pair[1]))


func _finite_pair(value: Variant) -> bool:
	return (
		value is Array
		and (value as Array).size() == 2
		and _finite_number((value as Array)[0])
		and _finite_number((value as Array)[1])
	)


func _finite_number(value: Variant) -> bool:
	return (
		(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		and is_finite(float(value))
		and absf(float(value)) <= MAX_CANVAS_COMPONENT
	)


func _positive_integer(value: Variant) -> bool:
	return (
		_finite_number(value)
		and float(value) == floor(float(value))
		and float(value) > 0.0
	)


func _exact_integer(value: Variant, expected: int) -> bool:
	return (
		_finite_number(value)
		and float(value) == floor(float(value))
		and int(value) == expected
	)


func _canonical_text(value: Variant) -> String:
	if value is not String:
		return ""
	var text := value as String
	return text if not text.is_empty() and text == text.strip_edges() else ""


func _canonical_id(value: Variant, max_length: int) -> String:
	var text := _canonical_text(value)
	return text if text.length() <= max_length and text.is_valid_identifier() else ""


func _canonical_text_limited(value: Variant, max_length: int) -> String:
	var text := _canonical_text(value)
	return text if text.length() <= max_length else ""


func _canonical_hash(value: Variant) -> String:
	var text := _canonical_text(value)
	if text.length() != 64 or text.to_lower() != text:
		return ""
	for character in text:
		if not character in "0123456789abcdef":
			return ""
	return text


func _resource_path(value: Variant) -> String:
	var path := _canonical_text(value)
	if not path.begins_with("res://") and not path.begins_with("user://"):
		return ""
	return path if path.simplify_path() == path else ""


func _keys_equal(value: Dictionary, expected: Array) -> bool:
	var actual: Array = value.keys()
	actual.sort()
	var sorted_expected := expected.duplicate()
	sorted_expected.sort()
	return actual == sorted_expected


func _failure(code: String, error: String) -> Dictionary:
	return {"ok": false, "code": code, "error": error}
