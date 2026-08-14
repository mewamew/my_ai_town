# 室内前景墙遮挡：只用人物脚点判定，墙面在脚点进入对应区域后
# 升到人物前方并按距离平滑淡出。
class_name InteriorWallOcclusion
extends Node2D

const SUBJECT_GROUP: StringName = &"map_occlusion_subject"
const Z_STEP := 4
const DEFAULT_FOREGROUND_Z := 999
const MAX_SEGMENTS := 256
const MAX_POLYGON_POINTS := 4096
const MAX_POLYGONS_PER_SEGMENT := 64
const MAX_TOTAL_POLYGON_POINTS := 32768
const MAX_CANVAS_COMPONENT := 65536.0
const MAX_CANVAS_PIXELS := 16777216
const MAX_TOTAL_EXTRACTED_PIXELS := 33554432
const MAX_JSON_BYTES := 8388608
const MAX_ID_LENGTH := 128
const MAX_REVISION_LENGTH := 256
const TOP_LEVEL_KEYS := [
	"canvas_size_px",
	"room_id",
	"schema_version",
	"segments",
	"source_revision",
]
const SEGMENT_REQUIRED_KEYS := [
	"fade_distance_px",
	"foreground_polygon_canvas_px",
	"id",
	"minimum_alpha",
	"reveal_polygons_canvas_px",
]
const SEGMENT_OPTIONAL_KEYS := [
	"foreground_cutout_polygons_canvas_px",
]

var _segments: Array[Dictionary] = []
var _subject_overlays: Dictionary = {}
var _debug_root: Node2D
var _configured_shell: Sprite2D
var _original_shell_image: Image


func configure(
	shell_value: Variant,
	geometry_value: Variant,
	occlusion_path_value: Variant,
) -> bool:
	if not shell_value is Sprite2D or not geometry_value is Dictionary:
		return false
	if not occlusion_path_value is String:
		return false
	var shell := shell_value as Sprite2D
	var geometry := geometry_value as Dictionary
	var occlusion_path := _canonical_text(occlusion_path_value)
	if occlusion_path.is_empty() or shell.texture == null:
		return false
	var data := _load_data(occlusion_path)
	if data.is_empty():
		return false
	var canvas_size := _canvas_size(geometry.get("canvas_size_px"))
	var data_canvas_size := _canvas_size(data.get("canvas_size_px"))
	var room_id := _canonical_id(geometry.get("room_id"), MAX_ID_LENGTH)
	var source_revision := _canonical_text_limited(
		geometry.get("source_revision"),
		MAX_REVISION_LENGTH,
	)
	if (
		canvas_size == Vector2i.ZERO
		or canvas_size.x * canvas_size.y > MAX_CANVAS_PIXELS
		or data_canvas_size != canvas_size
		or room_id.is_empty()
		or source_revision.is_empty()
		or not _finite_pair(geometry.get("world_origin_px"))
	):
		return false
	var original_image := _source_image_for(shell)
	if (
		original_image == null
		or original_image.is_empty()
		or original_image.get_width() != canvas_size.x
		or original_image.get_height() != canvas_size.y
	):
		return false
	var validated := _validate_data(
		data,
		canvas_size,
		room_id,
	)
	if validated.is_empty():
		return false
	var base_image := original_image.duplicate() as Image
	base_image.convert(Image.FORMAT_RGBA8)
	var world_origin := _pair(geometry.get("world_origin_px"))
	var new_segments: Array[Dictionary] = []
	var new_debug_root := Node2D.new()
	new_debug_root.name = "WallOcclusionDebug"
	new_debug_root.visible = false
	for segment_data in validated.get("segments", []) as Array[Dictionary]:
		var canvas_polygon := _polygon(
			segment_data.get("foreground_polygon_canvas_px"),
			canvas_size,
		)
		var cutout_polygons: Array[PackedVector2Array] = []
		for cutout_value: Variant in (
			segment_data.get("foreground_cutout_polygons_canvas_px", []) as Array
		):
			cutout_polygons.append(_polygon(cutout_value, canvas_size))
		var extracted := _extract_foreground_image(
			base_image,
			canvas_polygon,
			cutout_polygons,
		)
		var foreground_image := extracted.get("image") as Image
		if foreground_image == null or foreground_image.is_empty():
			_release_build(new_segments, new_debug_root)
			return false
		var foreground := Sprite2D.new()
		foreground.name = String(segment_data.get("id"))
		foreground.centered = false
		foreground.position = (
			extracted.get("canvas_origin", Vector2.ZERO) as Vector2
		) - world_origin
		foreground.texture = ImageTexture.create_from_image(foreground_image)
		foreground.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		foreground.z_as_relative = false
		foreground.z_index = DEFAULT_FOREGROUND_Z
		var reveal_polygons: Array[PackedVector2Array] = []
		for polygon_value: Variant in (
			segment_data.get("reveal_polygons_canvas_px") as Array
		):
			var reveal_local := _offset_polygon(
				_polygon(polygon_value, canvas_size),
				-world_origin,
			)
			reveal_polygons.append(reveal_local)
			var debug_polygon := Polygon2D.new()
			debug_polygon.name = "Debug_%s_%02d" % [
				String(segment_data.get("id")),
				reveal_polygons.size(),
			]
			debug_polygon.polygon = reveal_local
			debug_polygon.color = Color(0.545, 0.361, 0.965, 0.34)
			debug_polygon.z_index = 1200
			new_debug_root.add_child(debug_polygon)
		new_segments.append({
			"id": String(segment_data.get("id")),
			"foreground": foreground,
			"reveal_polygons": reveal_polygons,
			"fade_distance_px": float(segment_data.get("fade_distance_px")),
			"minimum_alpha": float(segment_data.get("minimum_alpha")),
			"default_z_index": DEFAULT_FOREGROUND_Z,
		})
	if new_segments.is_empty():
		_release_build(new_segments, new_debug_root)
		return false
	_commit_build(
		shell,
		original_image,
		base_image,
		new_segments,
		new_debug_root,
	)
	return true


func set_debug_visible(value: Variant) -> void:
	if value is bool and is_instance_valid(_debug_root):
		_debug_root.visible = value


func is_debug_visible() -> bool:
	return is_instance_valid(_debug_root) and _debug_root.visible


func update_for_subject(subject_value: Variant) -> void:
	if subject_value is Node2D:
		update_for_subjects([subject_value])


func update_for_subjects(subject_values: Variant) -> void:
	if not subject_values is Array:
		return
	var subjects: Array[Node2D] = []
	for value: Variant in subject_values as Array:
		if not value is Node2D:
			return
		subjects.append(value as Node2D)
	_prune_subject_overlays(subjects)
	_hide_subject_overlays()
	var has_valid_subject := false
	var behind_z := DEFAULT_FOREGROUND_Z
	for subject in subjects:
		if (
			not is_instance_valid(subject)
			or not subject.is_inside_tree()
			or not subject.is_visible_in_tree()
		):
			continue
		var subject_behind_z := _z_index_with_offset(
			subject.z_index,
			-Z_STEP,
		)
		if not has_valid_subject:
			behind_z = subject_behind_z
			has_valid_subject = true
		else:
			behind_z = mini(behind_z, subject_behind_z)
	for segment in _segments:
		var foreground := segment.get("foreground") as CanvasItem
		if not is_instance_valid(foreground):
			continue
		if not has_valid_subject:
			_reset_foreground(segment)
			continue
		# The full wall face remains behind all subjects. Only the portion around
		# the subject that triggered this reveal is promoted above that subject.
		foreground.z_index = behind_z
		foreground.modulate.a = 1.0
		for subject in subjects:
			if (
				not is_instance_valid(subject)
				or not subject.is_inside_tree()
				or not subject.is_visible_in_tree()
			):
				continue
			var local_foot := to_local(subject.global_position)
			var active_polygon := _active_polygon_for(segment, local_foot)
			if active_polygon.is_empty():
				continue
			var subject_alpha := _alpha_for_active_foot(
				local_foot,
				active_polygon,
				segment,
			)
			var overlay := _subject_overlay_for(segment, subject, local_foot)
			if not is_instance_valid(overlay):
				continue
			overlay.visible = true
			overlay.z_index = _z_index_with_offset(subject.z_index, Z_STEP)
			overlay.modulate = Color(1.0, 1.0, 1.0, subject_alpha)


func _z_index_with_offset(z_index: int, offset: int) -> int:
	return clampi(
		z_index + offset,
		RenderingServer.CANVAS_ITEM_Z_MIN,
		RenderingServer.CANVAS_ITEM_Z_MAX,
	)


func _subject_overlay_for(
	segment: Dictionary,
	subject: Node2D,
	local_foot: Vector2,
) -> Sprite2D:
	var foreground := segment.get("foreground") as Sprite2D
	if not is_instance_valid(foreground) or foreground.texture == null:
		return null
	var segment_id := String(segment.get("id", "segment"))
	var key := "%s:%d" % [segment_id, subject.get_instance_id()]
	var overlay := _subject_overlays.get(key) as Sprite2D
	if not is_instance_valid(overlay):
		overlay = Sprite2D.new()
		overlay.name = "%sSubjectOverlay_%d" % [segment_id, subject.get_instance_id()]
		overlay.centered = false
		overlay.texture_filter = foreground.texture_filter
		overlay.z_as_relative = false
		overlay.set_meta("subject_overlay", true)
		add_child(overlay)
		_subject_overlays[key] = overlay
	var source_rect := Rect2(Vector2.ZERO, foreground.texture.get_size())
	var source_foot := local_foot - foreground.position
	var slice := _subject_slice_rect(source_rect, source_foot)
	if not slice.has_area():
		overlay.visible = false
		return overlay
	var atlas: AtlasTexture = (
		overlay.get_meta("atlas_texture") as AtlasTexture
		if overlay.has_meta("atlas_texture")
		else null
	)
	if not is_instance_valid(atlas):
		atlas = AtlasTexture.new()
		overlay.set_meta("atlas_texture", atlas)
	atlas.atlas = foreground.texture
	atlas.region = slice
	overlay.texture = atlas
	overlay.position = foreground.position + slice.position
	return overlay


func _subject_slice_rect(source_rect: Rect2, source_foot: Vector2) -> Rect2:
	if not source_rect.has_area():
		return Rect2()
	# A reveal polygon can extend through a doorway between two extracted wall
	# faces. Clamp the slice to the nearest edge so both faces still get an
	# independent subject overlay when the foot point is just outside either
	# extracted texture.
	const HALF_EXTENT := 96.0
	var slice := source_rect
	if source_rect.size.x >= source_rect.size.y:
		var center_x := clampf(
			source_foot.x,
			source_rect.position.x,
			source_rect.end.x,
		)
		slice.position.x = center_x - HALF_EXTENT
		slice.size.x = HALF_EXTENT * 2.0
	else:
		var center_y := clampf(
			source_foot.y,
			source_rect.position.y,
			source_rect.end.y,
		)
		slice.position.y = center_y - HALF_EXTENT
		slice.size.y = HALF_EXTENT * 2.0
	return _intersection_rect(source_rect, slice)


func _intersection_rect(first: Rect2, second: Rect2) -> Rect2:
	var left := maxf(first.position.x, second.position.x)
	var top := maxf(first.position.y, second.position.y)
	var right := minf(first.end.x, second.end.x)
	var bottom := minf(first.end.y, second.end.y)
	return Rect2(left, top, right - left, bottom - top) if right > left and bottom > top else Rect2()


func _hide_subject_overlays() -> void:
	for overlay_value: Variant in _subject_overlays.values():
		var overlay := overlay_value as Sprite2D
		if is_instance_valid(overlay):
			overlay.visible = false


func _prune_subject_overlays(subjects: Array[Node2D]) -> void:
	# Residents can be represented by a new Node2D after an indoor/outdoor or
	# identity transition. Do not retain one wall Sprite2D/AtlasTexture for each
	# historical instance ID; only subjects in the current visible set are
	# allowed to keep a cached slice.
	var active_subject_ids := {}
	for subject in subjects:
		if (
			is_instance_valid(subject)
			and subject.is_inside_tree()
			and subject.is_visible_in_tree()
		):
			active_subject_ids[subject.get_instance_id()] = true
	for key_value: Variant in _subject_overlays.keys():
		var key := String(key_value)
		var separator := key.rfind(":")
		var overlay := _subject_overlays.get(key_value) as Sprite2D
		var subject_id := -1
		if separator >= 0:
			subject_id = int(key.substr(separator + 1))
		if (
			separator < 0
			or not active_subject_ids.has(subject_id)
			or not is_instance_valid(overlay)
		):
			if is_instance_valid(overlay):
				overlay.free()
			_subject_overlays.erase(key_value)


func _process(_delta: float) -> void:
	if not visible or get_parent() == null:
		return
	var parent_canvas := get_parent() as CanvasItem
	if parent_canvas != null and not parent_canvas.visible:
		return
	var subjects := _find_subjects()
	update_for_subjects(subjects)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_restore_configured_shell()


func _commit_build(
	shell: Sprite2D,
	original_image: Image,
	base_image: Image,
	new_segments: Array[Dictionary],
	new_debug_root: Node2D,
) -> void:
	if _configured_shell != shell:
		_restore_configured_shell()
	_clear_render_nodes()
	_original_shell_image = original_image.duplicate() as Image
	_configured_shell = shell
	shell.texture = ImageTexture.create_from_image(base_image)
	for segment in new_segments:
		add_child(segment.get("foreground") as Sprite2D)
	add_child(new_debug_root)
	_segments = new_segments
	_debug_root = new_debug_root
	name = "WallOcclusion"
	set_process(true)


func _source_image_for(shell: Sprite2D) -> Image:
	if (
		_configured_shell == shell
		and _original_shell_image != null
		and not _original_shell_image.is_empty()
	):
		return _original_shell_image.duplicate() as Image
	var image := shell.texture.get_image()
	return image.duplicate() as Image if image != null else null


func _restore_configured_shell() -> void:
	if (
		is_instance_valid(_configured_shell)
		and _original_shell_image != null
		and not _original_shell_image.is_empty()
	):
		_configured_shell.texture = ImageTexture.create_from_image(
			_original_shell_image.duplicate() as Image
		)


func _clear_render_nodes() -> void:
	_subject_overlays.clear()
	for child in get_children():
		remove_child(child)
		child.free()
	_segments.clear()
	_debug_root = null
	set_process(false)


func _release_build(
	segments: Array[Dictionary],
	debug_root: Node2D,
) -> void:
	for segment in segments:
		var foreground := segment.get("foreground") as Node
		if is_instance_valid(foreground):
			foreground.free()
	if is_instance_valid(debug_root):
		debug_root.free()


func _find_subjects() -> Array[Node2D]:
	var subjects: Array[Node2D] = []
	for candidate in get_tree().get_nodes_in_group(SUBJECT_GROUP):
		if candidate is Node2D and candidate.is_visible_in_tree():
			subjects.append(candidate as Node2D)
	return subjects


func _active_polygon_for(
	segment: Dictionary,
	local_foot: Vector2,
) -> PackedVector2Array:
	for reveal_polygon in segment.get("reveal_polygons") as Array[PackedVector2Array]:
		if Geometry2D.is_point_in_polygon(local_foot, reveal_polygon):
			return reveal_polygon
	return PackedVector2Array()


func _alpha_for_active_foot(
	local_foot: Vector2,
	active_polygon: PackedVector2Array,
	segment: Dictionary,
) -> float:
	var boundary_distance := _distance_to_polygon_boundary(
		local_foot,
		active_polygon,
	)
	var fade_distance := maxf(float(segment.get("fade_distance_px")), 1.0)
	var fade_weight := smoothstep(0.0, fade_distance, boundary_distance)
	return lerpf(
		1.0,
		float(segment.get("minimum_alpha")),
		fade_weight,
	)


func _reset_foreground(segment: Dictionary) -> void:
	var foreground := segment.get("foreground") as CanvasItem
	if not is_instance_valid(foreground):
		return
	foreground.z_index = int(
		segment.get("default_z_index", DEFAULT_FOREGROUND_Z)
	)
	foreground.modulate.a = 1.0


func _distance_to_polygon_boundary(
	point: Vector2,
	polygon: PackedVector2Array,
) -> float:
	if polygon.size() < 2:
		return 0.0
	var nearest := INF
	for index in range(polygon.size()):
		var closest := Geometry2D.get_closest_point_to_segment(
			point,
			polygon[index],
			polygon[(index + 1) % polygon.size()],
		)
		nearest = minf(nearest, point.distance_to(closest))
	return nearest


func _extract_foreground_image(
	image: Image,
	polygon: PackedVector2Array,
	cutout_polygons: Array[PackedVector2Array],
) -> Dictionary:
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		bounds = bounds.expand(point)
	var min_x := maxi(0, floori(bounds.position.x))
	var min_y := maxi(0, floori(bounds.position.y))
	var max_x := mini(image.get_width(), ceili(bounds.end.x))
	var max_y := mini(image.get_height(), ceili(bounds.end.y))
	if max_x <= min_x or max_y <= min_y:
		return {}
	var result := Image.create(
		max_x - min_x,
		max_y - min_y,
		false,
		Image.FORMAT_RGBA8,
	)
	result.fill(Color.TRANSPARENT)
	for y in range(min_y, max_y):
		for x in range(min_x, max_x):
			var pixel_center := Vector2(x + 0.5, y + 0.5)
			if not Geometry2D.is_point_in_polygon(pixel_center, polygon):
				continue
			var is_cutout := false
			for cutout in cutout_polygons:
				if Geometry2D.is_point_in_polygon(pixel_center, cutout):
					is_cutout = true
					break
			if is_cutout:
				continue
			var color := image.get_pixel(x, y)
			result.set_pixel(x - min_x, y - min_y, color)
			color.a = 0.0
			image.set_pixel(x, y, color)
	return {
		"image": result,
		"canvas_origin": Vector2(min_x, min_y),
	}


func _load_data(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() <= 0:
		return {}
	if file.get_length() > MAX_JSON_BYTES:
		file.close()
		return {}
	var text := file.get_as_text()
	file.close()
	if text.to_utf8_buffer().size() > MAX_JSON_BYTES:
		return {}
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {}
	var parsed: Variant = parser.data
	return parsed as Dictionary if parsed is Dictionary else {}


func _validate_data(
	data: Dictionary,
	canvas_size: Vector2i,
	expected_room_id: String,
) -> Dictionary:
	if not _keys_equal(data, TOP_LEVEL_KEYS):
		return {}
	if not _exact_integer(data.get("schema_version"), 1):
		return {}
	if (
		_canonical_id(data.get("room_id"), MAX_ID_LENGTH) != expected_room_id
		or _canonical_text_limited(
			data.get("source_revision"),
			MAX_REVISION_LENGTH,
		).is_empty()
		or _canvas_size(data.get("canvas_size_px")) != canvas_size
	):
		return {}
	var segments_value: Variant = data.get("segments")
	if not segments_value is Array:
		return {}
	var values := segments_value as Array
	if values.is_empty() or values.size() > MAX_SEGMENTS:
		return {}
	var segment_ids := {}
	var segments: Array[Dictionary] = []
	var total_polygon_points := 0
	var total_extracted_pixels := 0
	for value: Variant in values:
		if not value is Dictionary:
			return {}
		var segment := value as Dictionary
		if not _segment_keys_valid(segment):
			return {}
		var segment_id := _canonical_id(segment.get("id"), MAX_ID_LENGTH)
		if segment_id.is_empty() or segment_ids.has(segment_id):
			return {}
		segment_ids[segment_id] = true
		var foreground := _polygon(
			segment.get("foreground_polygon_canvas_px"),
			canvas_size,
		)
		if not _valid_polygon(foreground):
			return {}
		total_polygon_points += foreground.size()
		total_extracted_pixels += _polygon_pixel_area(foreground)
		if (
			total_polygon_points > MAX_TOTAL_POLYGON_POINTS
			or total_extracted_pixels > MAX_TOTAL_EXTRACTED_PIXELS
		):
			return {}
		var reveal_values: Variant = segment.get("reveal_polygons_canvas_px")
		if not reveal_values is Array:
			return {}
		if (
			(reveal_values as Array).is_empty()
			or (reveal_values as Array).size() > MAX_POLYGONS_PER_SEGMENT
		):
			return {}
		for polygon_value: Variant in reveal_values as Array:
			var reveal := _polygon(polygon_value, canvas_size)
			if not _valid_polygon(reveal):
				return {}
			total_polygon_points += reveal.size()
		var cutout_values: Variant = segment.get(
			"foreground_cutout_polygons_canvas_px",
			[],
		)
		if not cutout_values is Array:
			return {}
		if (cutout_values as Array).size() > MAX_POLYGONS_PER_SEGMENT:
			return {}
		for cutout_value: Variant in cutout_values as Array:
			var cutout := _polygon(cutout_value, canvas_size)
			if (
				not _valid_polygon(cutout)
				or not _polygon_strictly_inside(cutout, foreground)
			):
				return {}
			total_polygon_points += cutout.size()
		if total_polygon_points > MAX_TOTAL_POLYGON_POINTS:
			return {}
		if (
			not _finite_number(segment.get("fade_distance_px"))
			or float(segment.get("fade_distance_px")) <= 0.0
			or float(segment.get("fade_distance_px")) > MAX_CANVAS_COMPONENT
			or not _finite_number(segment.get("minimum_alpha"))
			or float(segment.get("minimum_alpha")) < 0.0
			or float(segment.get("minimum_alpha")) > 1.0
		):
			return {}
		segments.append(segment.duplicate(true))
	return {"segments": segments}


func _segment_keys_valid(segment: Dictionary) -> bool:
	for key_value: Variant in segment:
		var key := String(key_value)
		if (
			not SEGMENT_REQUIRED_KEYS.has(key)
			and not SEGMENT_OPTIONAL_KEYS.has(key)
		):
			return false
	for key in SEGMENT_REQUIRED_KEYS:
		if not segment.has(key):
			return false
	return true


func _valid_polygon(polygon: PackedVector2Array) -> bool:
	if polygon.size() < 3 or polygon.size() > MAX_POLYGON_POINTS:
		return false
	var seen_points := {}
	for index in range(polygon.size()):
		var point := polygon[index]
		if (
			seen_points.has(point)
			or point == polygon[(index + 1) % polygon.size()]
		):
			return false
		seen_points[point] = true
	return (
		absf(_signed_area(polygon)) > 0.0001
		and not Geometry2D.triangulate_polygon(polygon).is_empty()
	)


func _polygon_strictly_inside(
	inner: PackedVector2Array,
	outer: PackedVector2Array,
) -> bool:
	for point in inner:
		if not Geometry2D.is_point_in_polygon(point, outer):
			return false
	for inner_index in range(inner.size()):
		var inner_start := inner[inner_index]
		var inner_end := inner[(inner_index + 1) % inner.size()]
		for outer_index in range(outer.size()):
			var intersection: Variant = Geometry2D.segment_intersects_segment(
				inner_start,
				inner_end,
				outer[outer_index],
				outer[(outer_index + 1) % outer.size()],
			)
			if intersection != null:
				return false
	return true


func _polygon_pixel_area(polygon: PackedVector2Array) -> int:
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		bounds = bounds.expand(point)
	return (
		maxi(0, ceili(bounds.end.x) - floori(bounds.position.x))
		* maxi(0, ceili(bounds.end.y) - floori(bounds.position.y))
	)


func _signed_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for index in range(polygon.size()):
		var current := polygon[index]
		var next := polygon[(index + 1) % polygon.size()]
		area += current.x * next.y - next.x * current.y
	return area * 0.5


func _polygon(
	value: Variant,
	canvas_size: Vector2i,
) -> PackedVector2Array:
	var points := PackedVector2Array()
	if not value is Array:
		return points
	var values := value as Array
	if values.size() > MAX_POLYGON_POINTS:
		return points
	for point_value: Variant in values:
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
	if not value is Array or (value as Array).size() != 2:
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
	if not value is String:
		return ""
	var text := value as String
	return text if not text.is_empty() and text == text.strip_edges() else ""


func _canonical_id(value: Variant, max_length: int) -> String:
	var text := _canonical_text(value)
	return (
		text
		if text.length() <= max_length and text.is_valid_identifier()
		else ""
	)


func _canonical_text_limited(value: Variant, max_length: int) -> String:
	var text := _canonical_text(value)
	return text if text.length() <= max_length else ""


func _keys_equal(value: Dictionary, expected: Array) -> bool:
	var actual: Array = value.keys()
	actual.sort()
	var sorted_expected := expected.duplicate()
	sorted_expected.sort()
	return actual == sorted_expected


func _offset_polygon(
	polygon: PackedVector2Array,
	offset: Vector2,
) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in polygon:
		result.append(point + offset)
	return result
