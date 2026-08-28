extends RefCounted

const OCCLUSION_MANIFEST := preload(
	"res://world/maps/town/interiors/InteriorOcclusionManifest.gd"
)
const PUBLISH_TRANSACTION := preload(
	"res://tools/interiors/InteriorOcclusionPublishTransaction.gd"
)
const SCHEMA_VERSION := 2
const RUNTIME_DIRECTORY := "wall_occlusion_runtime"
const MANIFEST_NAME := "wall_occlusion_runtime.json"
const MAX_CANVAS_PIXELS := 16777216

var _publish_fault_point := ""
var _publish_fault_occurrence := 1


func configure_publish_fault(point: String, occurrence: int = 1) -> void:
	_publish_fault_point = point
	_publish_fault_occurrence = maxi(1, occurrence)


func generate(rooms_root: String, room_ids: Array[String]) -> Dictionary:
	if not _valid_resource_path(rooms_root) or room_ids.is_empty():
		return _failure("rooms root and room ids are required")
	var seen_room_ids := {}
	for room_id in room_ids:
		if room_id.is_empty() or not room_id.is_valid_identifier():
			return _failure("invalid room id: %s" % room_id)
		if seen_room_ids.has(room_id):
			return _failure("duplicate room id: %s" % room_id)
		seen_room_ids[room_id] = true
	var transaction := PUBLISH_TRANSACTION.new()
	transaction.configure_fault(_publish_fault_point, _publish_fault_occurrence)
	var recovery := transaction.recover_pending(rooms_root) as Dictionary
	if recovery.get("ok") != true:
		return recovery
	var run_id := "%d_%d" % [Time.get_ticks_usec(), randi()]
	var staging_root := "user://interior_occlusion_staging/%s" % run_id
	if DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(staging_root),
	) != OK:
		return _failure("staging directory could not be created")
	var staged_rooms: Array[Dictionary] = []
	for room_id in room_ids:
		var staged := _stage_room(rooms_root, room_id, staging_root)
		if staged.get("ok") != true:
			if not _remove_staging_tree(staging_root):
				staged["staging_cleanup_failed"] = true
				staged["error"] = "%s; staging cleanup failed" % staged.get(
					"error",
					"generation failed",
				)
			return staged
		staged_rooms.append(staged)
	var published := transaction.publish(rooms_root, staged_rooms, run_id) as Dictionary
	var staging_cleaned := _remove_staging_tree(staging_root)
	if published.get("ok") != true:
		# 可报告的 I/O 失败与故障注入都必须在 generate() 返回前恢复。
		# 真正的进程中断则由下一次 generate() 开头的 recover_pending() 接管。
		var rollback := PUBLISH_TRANSACTION.new().recover_pending(rooms_root) as Dictionary
		if rollback.get("ok") != true:
			rollback["publish_error"] = published.get("error", "")
			rollback["staging_cleanup_failed"] = not staging_cleaned
			return rollback
		published["recovery_pending"] = false
		if not staging_cleaned:
			published["staging_cleanup_failed"] = true
			published["error"] = "%s; staging cleanup failed" % published.get(
				"error",
				"publication failed",
			)
		return published
	if not staging_cleaned:
		return _failure("publication committed but staging cleanup failed")
	return {
		"ok": true,
		"room_count": staged_rooms.size(),
		"segment_count": int(published.get("segment_count", 0)),
	}


func _stage_room(
	rooms_root: String,
	room_id: String,
	staging_root: String,
) -> Dictionary:
	if room_id.is_empty() or not room_id.is_valid_identifier():
		return _failure("invalid room id: %s" % room_id)
	var room_root := rooms_root.path_join(room_id)
	var geometry_path := room_root.path_join("room_geometry.json")
	var occlusion_path := room_root.path_join("wall_occlusion.json")
	var geometry := _read_json(geometry_path)
	var occlusion := _read_json(occlusion_path)
	if geometry.is_empty() or occlusion.is_empty():
		return _failure("%s geometry or occlusion JSON is missing" % room_id)
	if (
		String(geometry.get("room_id", "")) != room_id
		or String(occlusion.get("room_id", "")) != room_id
		or geometry.get("canvas_size_px") != occlusion.get("canvas_size_px")
		or String(geometry.get("source_revision", "")).strip_edges().is_empty()
		or String(occlusion.get("source_revision", "")).strip_edges().is_empty()
	):
		return _failure("%s geometry and occlusion metadata do not match" % room_id)
	var canvas := _canvas_size(geometry.get("canvas_size_px"))
	if canvas == Vector2i.ZERO or canvas.x * canvas.y > MAX_CANVAS_PIXELS:
		return _failure("%s canvas size is invalid" % room_id)
	var shell_relative_path := String(geometry.get("background_sprite", ""))
	var shell_path := room_root.path_join(shell_relative_path).simplify_path()
	var shell_image := Image.new()
	if (
		shell_relative_path.is_empty()
		or shell_image.load(ProjectSettings.globalize_path(shell_path)) != OK
	):
		return _failure("%s shell image could not be loaded" % room_id)
	shell_image.convert(Image.FORMAT_RGBA8)
	if shell_image.get_size() != canvas:
		return _failure("%s shell size does not match its geometry" % room_id)
	var segment_values: Variant = occlusion.get("segments")
	if segment_values is not Array or (segment_values as Array).is_empty():
		return _failure("%s has no occlusion segments" % room_id)
	var room_stage := staging_root.path_join(room_id)
	if DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(room_stage),
	) != OK:
		return _failure("%s staging directory could not be created" % room_id)
	var generated_segments: Array[Dictionary] = []
	var staged_assets: Array[Dictionary] = []
	var ids := {}
	var manifest_validator := OCCLUSION_MANIFEST.new() as InteriorOcclusionManifest
	var reveal_polygon_points := 0
	for segment_value: Variant in segment_values as Array:
		if segment_value is not Dictionary:
			return _failure("%s contains an invalid segment" % room_id)
		var segment := segment_value as Dictionary
		var segment_id := String(segment.get("id", "")).strip_edges()
		if (
			segment_id.is_empty()
			or not segment_id.is_valid_identifier()
			or ids.has(segment_id)
		):
			return _failure("%s contains an invalid or duplicate segment" % room_id)
		ids[segment_id] = true
		var occlusion_fields := manifest_validator.validate_segment_occlusion_fields(
			segment,
			canvas,
			reveal_polygon_points,
		)
		if occlusion_fields.get("ok") != true:
			return _failure(
				"%s segment %s fields are invalid (%s)"
				% [room_id, segment_id, String(occlusion_fields.get("code", ""))],
			)
		reveal_polygon_points = int(occlusion_fields.get("polygon_points", 0))
		var foreground := _polygon(
			segment.get("foreground_polygon_canvas_px"),
			canvas,
		)
		if not _valid_polygon(foreground):
			return _failure("%s segment %s polygon is invalid" % [room_id, segment_id])
		var cutouts: Array[PackedVector2Array] = []
		var cutout_values: Variant = segment.get(
			"foreground_cutout_polygons_canvas_px",
			[],
		)
		if cutout_values is not Array:
			return _failure("%s segment %s cutouts are invalid" % [room_id, segment_id])
		for cutout_value: Variant in cutout_values as Array:
			var cutout := _polygon(cutout_value, canvas)
			if not _valid_polygon(cutout):
				return _failure(
					"%s segment %s cutout is invalid" % [room_id, segment_id],
				)
			cutouts.append(cutout)
		var extracted := _extract_foreground(shell_image, foreground, cutouts)
		var image := extracted.get("image") as Image
		if image == null or image.is_empty():
			return _failure("%s segment %s could not be extracted" % [room_id, segment_id])
		var staged_texture_path := room_stage.path_join("%s.png" % segment_id)
		if image.save_png(
			ProjectSettings.globalize_path(staged_texture_path),
		) != OK:
			return _failure("%s segment %s could not be staged" % [room_id, segment_id])
		var texture_sha256 := FileAccess.get_sha256(staged_texture_path)
		if texture_sha256.length() != 64:
			return _failure("%s segment %s digest failed" % [room_id, segment_id])
		var final_texture_path := room_root.path_join(
			RUNTIME_DIRECTORY,
		).path_join("%s-%s.png" % [segment_id, texture_sha256.left(12)])
		staged_assets.append({
			"staged_path": staged_texture_path,
			"final_path": final_texture_path,
			"sha256": texture_sha256,
		})
		generated_segments.append({
			"id": segment_id,
			"foreground_texture_path": final_texture_path,
			"foreground_texture_sha256": texture_sha256,
			"foreground_canvas_origin_px": extracted.get("canvas_origin"),
			"foreground_texture_size_px": [image.get_width(), image.get_height()],
			"reveal_polygons_canvas_px": segment.get(
				"reveal_polygons_canvas_px",
				[],
			),
			"fade_distance_px": segment.get("fade_distance_px"),
			"minimum_alpha": segment.get("minimum_alpha"),
		})
	var manifest := {
		"schema_version": SCHEMA_VERSION,
		"source_occlusion_revision": String(occlusion.get("source_revision")),
		"source_occlusion_sha256": FileAccess.get_sha256(occlusion_path),
		"source_geometry_revision": String(geometry.get("source_revision")),
		"source_geometry_sha256": FileAccess.get_sha256(geometry_path),
		"source_shell_path": shell_path,
		"source_shell_sha256": FileAccess.get_sha256(shell_path),
		"room_id": room_id,
		"canvas_size_px": occlusion.get("canvas_size_px"),
		"segments": generated_segments,
	}
	var staged_manifest_path := room_stage.path_join(MANIFEST_NAME)
	if not _write_json(staged_manifest_path, manifest):
		return _failure("%s manifest could not be staged" % room_id)
	return {
		"ok": true,
		"room_id": room_id,
		"room_root": room_root,
		"staged_manifest_path": staged_manifest_path,
		"final_manifest_path": room_root.path_join(MANIFEST_NAME),
		"assets": staged_assets,
		"manifest": manifest,
	}


func _extract_foreground(
	image: Image,
	polygon: PackedVector2Array,
	cutouts: Array[PackedVector2Array],
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
			var cut_out := false
			for cutout in cutouts:
				if Geometry2D.is_point_in_polygon(pixel_center, cutout):
					cut_out = true
					break
			if not cut_out:
				result.set_pixel(x - min_x, y - min_y, image.get_pixel(x, y))
	return {
		"image": result,
		"canvas_origin": [min_x, min_y],
	}


func _polygon(value: Variant, canvas: Vector2i) -> PackedVector2Array:
	var result := PackedVector2Array()
	if value is not Array or (value as Array).size() > 4096:
		return result
	for point_value: Variant in value as Array:
		if point_value is not Array or (point_value as Array).size() != 2:
			return PackedVector2Array()
		var pair := point_value as Array
		if not _finite_number(pair[0]) or not _finite_number(pair[1]):
			return PackedVector2Array()
		var point := Vector2(float(pair[0]), float(pair[1]))
		if point.x < 0.0 or point.y < 0.0 or point.x > canvas.x or point.y > canvas.y:
			return PackedVector2Array()
		result.append(point)
	return result


func _valid_polygon(polygon: PackedVector2Array) -> bool:
	if polygon.size() < 3:
		return false
	var seen := {}
	for index in polygon.size():
		if seen.has(polygon[index]) or polygon[index] == polygon[(index + 1) % polygon.size()]:
			return false
		seen[polygon[index]] = true
	return not Geometry2D.triangulate_polygon(polygon).is_empty()


func _canvas_size(value: Variant) -> Vector2i:
	if value is not Array or (value as Array).size() != 2:
		return Vector2i.ZERO
	var pair := value as Array
	if not _positive_integer(pair[0]) or not _positive_integer(pair[1]):
		return Vector2i.ZERO
	return Vector2i(int(pair[0]), int(pair[1]))


func _positive_integer(value: Variant) -> bool:
	return _finite_number(value) and float(value) == floorf(float(value)) and float(value) > 0.0


func _finite_number(value: Variant) -> bool:
	return (
		(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		and is_finite(float(value))
	)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


func _write_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "  ") + "\n")
	file.close()
	return true


func _remove_staging_tree(path: String) -> bool:
	if not path.begins_with("user://interior_occlusion_staging/"):
		return false
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return true
	return (
		_remove_directory_contents(absolute)
		and DirAccess.remove_absolute(absolute) == OK
	)


func _remove_directory_contents(absolute_path: String) -> bool:
	var directory := DirAccess.open(absolute_path)
	if directory == null:
		return false
	var entries: Array[Dictionary] = []
	directory.include_hidden = true
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		entries.append({"name": entry, "directory": directory.current_is_dir()})
		entry = directory.get_next()
	directory.list_dir_end()
	for record in entries:
		var child := absolute_path.path_join(String(record.get("name", "")))
		if bool(record.get("directory")):
			if (
				not _remove_directory_contents(child)
				or DirAccess.remove_absolute(child) != OK
			):
				return false
		else:
			if DirAccess.remove_absolute(child) != OK:
				return false
	return true


func _valid_resource_path(path: String) -> bool:
	return (
		(path.begins_with("res://") or path.begins_with("user://"))
		and path == path.simplify_path()
	)


func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
