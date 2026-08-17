extends SceneTree

const WALL_OCCLUSION := preload(
	"res://world/maps/town/interiors/InteriorWallOcclusion.gd"
)
const WALL_Z_STEP := 4
const ROOMS := [
	"cafe",
	"clinic",
	"dining_hall",
	"dock_warehouse",
	"home_template_a",
	"home_template_b",
	"library",
	"market_shop",
	"town_hall",
	"workshop",
]
const ROOM_BASE := "res://world/maps/town/interiors/redesign_v2/rooms"
const VALID_PATH := "user://wall_occlusion_valid_test.json"
const INVALID_PATH := "user://wall_occlusion_invalid_test.json"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_synthetic_cutout_and_state_transitions()
	_test_formal_room_data()
	_cleanup()
	_finish()


func _test_synthetic_cutout_and_state_transitions() -> void:
	var valid_data := _synthetic_data()
	_write_json(VALID_PATH, valid_data)
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.8, 0.4, 0.2, 1.0))
	var shell := Sprite2D.new()
	shell.name = "Shell"
	shell.centered = false
	shell.texture = ImageTexture.create_from_image(image)
	root.add_child(shell)
	var occlusion := WALL_OCCLUSION.new()
	root.add_child(occlusion)
	var geometry := {
		"room_id": "cutout_test",
		"source_revision": "cutout_test",
		"world_origin_px": [0, 0],
		"canvas_size_px": [16, 16],
	}
	_expect(
		bool(occlusion.configure(shell, geometry, VALID_PATH)),
		"wall occlusion configures with a floor cutout",
	)
	var base_image := shell.texture.get_image()
	_expect(
		base_image.get_pixel(2, 2).a == 0.0,
		"wall pixels move out of the base shell",
	)
	_expect(
		base_image.get_pixel(8, 8).a == 1.0,
		"cut-out floor stays in the base shell",
	)
	var foreground := occlusion.get_node_or_null(
		"wall_with_floor_cutout"
	) as Sprite2D
	_expect(foreground != null, "foreground segment is extracted")
	if foreground != null:
		var foreground_image := foreground.texture.get_image()
		_expect(
			foreground_image.get_pixel(2, 2).a == 1.0,
			"wall pixel exists in the foreground segment",
		)
		_expect(
			foreground_image.get_pixel(8, 8).a == 0.0,
			"cut-out floor is absent from the foreground segment",
		)
	var stable_child_count := occlusion.get_child_count()
	var stable_base_bytes := shell.texture.get_image().get_data()
	_expect(
		bool(occlusion.configure(shell, geometry, VALID_PATH)),
		"repeated configuration succeeds",
	)
	_expect_equal(
		occlusion.get_child_count(),
		stable_child_count,
		"repeated configuration replaces instead of duplicating render nodes",
	)
	_expect_equal(
		shell.texture.get_image().get_data(),
		stable_base_bytes,
		"repeated configuration is pixel deterministic",
	)
	_test_failed_configuration_is_atomic(
		occlusion,
		shell,
		geometry,
		stable_child_count,
		stable_base_bytes,
		valid_data,
	)
	var first_subject := Node2D.new()
	first_subject.z_index = 10
	first_subject.position = Vector2(3, 3)
	root.add_child(first_subject)
	var second_subject := Node2D.new()
	second_subject.z_index = 20
	second_subject.position = Vector2(8, 8)
	root.add_child(second_subject)
	occlusion.update_for_subjects([first_subject, second_subject])
	foreground = occlusion.get_node_or_null(
		"wall_with_floor_cutout"
	) as Sprite2D
	_expect_equal(
		foreground.z_index if foreground != null else -1,
		6,
		"wall base stays behind all active subjects",
	)
	_expect_equal(
		_visible_subject_overlays(occlusion).size(),
		2,
		"multiple subjects receive independent wall foreground slices",
	)
	var before_invalid_update := (
		foreground.z_index if foreground != null else -1
	)
	occlusion.update_for_subjects([first_subject, true])
	_expect_equal(
		foreground.z_index if foreground != null else -1,
		before_invalid_update,
		"mixed invalid subject collections are ignored atomically",
	)
	first_subject.z_index = RenderingServer.CANVAS_ITEM_Z_MAX
	first_subject.position = Vector2(8, 8)
	occlusion.update_for_subjects([first_subject])
	_expect_equal(
		foreground.z_index if foreground != null else -1,
		RenderingServer.CANVAS_ITEM_Z_MAX - WALL_Z_STEP,
		"wall base z-index stays clamped behind the maximum-depth subject",
	)
	var overlays := _visible_subject_overlays(occlusion)
	_expect_equal(
		overlays.size(),
		1,
		"maximum-depth active subject keeps one independent wall slice",
	)
	_expect_equal(
		(occlusion.get("_subject_overlays") as Dictionary).size(),
		1,
		"inactive historical subjects release their cached wall slices",
	)
	if overlays.size() == 1:
		_expect_equal(
			overlays[0].z_index,
			RenderingServer.CANVAS_ITEM_Z_MAX,
			"active wall slice clamps to the CanvasItem maximum",
		)
	first_subject.z_index = RenderingServer.CANVAS_ITEM_Z_MIN
	first_subject.position = Vector2(32, 32)
	occlusion.update_for_subjects([first_subject])
	_expect_equal(
		foreground.z_index if foreground != null else -1,
		RenderingServer.CANVAS_ITEM_Z_MIN,
		"inactive foreground z-index clamps to the CanvasItem minimum",
	)
	first_subject.free()
	second_subject.free()
	occlusion.update_for_subjects([])
	_expect_equal(
		foreground.z_index if foreground != null else -1,
		999,
		"removing every subject restores the foreground default z-index",
	)
	_expect_equal(
		foreground.modulate.a if foreground != null else -1.0,
		1.0,
		"removing every subject restores full foreground opacity",
	)
	_expect_equal(
		_visible_subject_overlays(occlusion).size(),
		0,
		"removing every subject hides all wall foreground slices",
	)
	_expect_equal(
		(occlusion.get("_subject_overlays") as Dictionary).size(),
		0,
		"removing every subject frees all cached wall slices",
	)
	occlusion.set_debug_visible("true")
	_expect(
		not occlusion.is_debug_visible(),
		"non-boolean debug values cannot change state",
	)
	occlusion.set_debug_visible(true)
	_expect(occlusion.is_debug_visible(), "boolean debug values remain supported")
	root.remove_child(occlusion)
	root.add_child(occlusion)
	_expect_equal(
		shell.texture.get_image().get_data(),
		stable_base_bytes,
		"temporary tree removal does not duplicate foreground pixels",
	)
	occlusion.free()
	_expect_equal(
		shell.texture.get_image().get_data(),
		image.get_data(),
		"removing the occlusion runtime restores the original room shell",
	)
	shell.free()


func _test_failed_configuration_is_atomic(
	occlusion: Node2D,
	shell: Sprite2D,
	geometry: Dictionary,
	stable_child_count: int,
	stable_base_bytes: PackedByteArray,
	valid_data: Dictionary,
) -> void:
	var invalid_values: Array[Dictionary] = []
	var unknown_top_level := valid_data.duplicate(true)
	unknown_top_level["debug"] = true
	invalid_values.append(unknown_top_level)
	var duplicate_segments := valid_data.duplicate(true)
	duplicate_segments["segments"] = (
		duplicate_segments.get("segments") as Array
	).duplicate(true)
	(duplicate_segments.get("segments") as Array).append(
		(duplicate_segments.get("segments") as Array)[0].duplicate(true)
	)
	invalid_values.append(duplicate_segments)
	var malformed_segment := valid_data.duplicate(true)
	malformed_segment["segments"] = [true]
	invalid_values.append(malformed_segment)
	var crossing_polygon := valid_data.duplicate(true)
	(
		(crossing_polygon.get("segments") as Array)[0] as Dictionary
	)["foreground_polygon_canvas_px"] = [
		[0, 0], [16, 16], [0, 16], [16, 0],
	]
	invalid_values.append(crossing_polygon)
	var infinite_fade := valid_data.duplicate(true)
	(
		(infinite_fade.get("segments") as Array)[0] as Dictionary
	)["fade_distance_px"] = 1.0e300
	invalid_values.append(infinite_fade)
	var wrong_room := valid_data.duplicate(true)
	wrong_room["room_id"] = "other_room"
	invalid_values.append(wrong_room)
	var wrong_revision := valid_data.duplicate(true)
	wrong_revision["source_revision"] = " other_revision"
	invalid_values.append(wrong_revision)
	var no_reveal := valid_data.duplicate(true)
	((no_reveal.get("segments") as Array)[0] as Dictionary)[
		"reveal_polygons_canvas_px"
	] = []
	invalid_values.append(no_reveal)
	var repeated_vertex := valid_data.duplicate(true)
	((repeated_vertex.get("segments") as Array)[0] as Dictionary)[
		"foreground_polygon_canvas_px"
	] = [[0, 0], [16, 0], [0, 0], [0, 16]]
	invalid_values.append(repeated_vertex)
	var too_many_reveals := valid_data.duplicate(true)
	var reveal_template: Array = (
		((too_many_reveals.get("segments") as Array)[0] as Dictionary)[
			"reveal_polygons_canvas_px"
		] as Array
	)[0]
	var reveal_overflow := []
	for _index in range(65):
		reveal_overflow.append(reveal_template.duplicate(true))
	((too_many_reveals.get("segments") as Array)[0] as Dictionary)[
		"reveal_polygons_canvas_px"
	] = reveal_overflow
	invalid_values.append(too_many_reveals)
	for invalid_data in invalid_values:
		_write_json(INVALID_PATH, invalid_data)
		_expect(
			not bool(occlusion.configure(shell, geometry, INVALID_PATH)),
			"invalid occlusion data is rejected",
		)
		_expect_equal(
			occlusion.get_child_count(),
			stable_child_count,
			"failed configuration preserves the previous render nodes",
		)
		_expect_equal(
			shell.texture.get_image().get_data(),
			stable_base_bytes,
			"failed configuration preserves the previous shell pixels",
		)
	_write_text(INVALID_PATH, "{")
	_expect(
		not bool(occlusion.configure(shell, geometry, INVALID_PATH)),
		"malformed JSON is rejected",
	)
	for invalid_call: Array in [
		[null, geometry, VALID_PATH],
		[shell, [], VALID_PATH],
		[shell, geometry, []],
		[shell, {
			"room_id": "cutout_test",
			"source_revision": "cutout_test",
			"world_origin_px": [INF, 0],
			"canvas_size_px": [16, 16],
		}, VALID_PATH],
		[shell, {
			"room_id": "cutout_test",
			"source_revision": "cutout_test",
			"world_origin_px": [0, 0],
			"canvas_size_px": [1.0e300, 16],
		}, VALID_PATH],
	]:
		_expect(
			not bool(occlusion.callv("configure", invalid_call)),
			"wrong public input types and extreme geometry are rejected",
		)
	_expect_equal(
		occlusion.get_child_count(),
		stable_child_count,
		"invalid public calls preserve the previous render nodes",
	)
	_expect_equal(
		shell.texture.get_image().get_data(),
		stable_base_bytes,
		"invalid public calls preserve the previous shell pixels",
	)


func _test_formal_room_data() -> void:
	var configured_rooms := 0
	for room_id in ROOMS:
		var base := "%s/%s" % [ROOM_BASE, room_id]
		var geometry := _read_json(base.path_join("room_geometry.json"))
		var data := _read_json(base.path_join("wall_occlusion.json"))
		_expect(not geometry.is_empty(), "%s has room geometry" % room_id)
		_expect(not data.is_empty(), "%s has wall occlusion data" % room_id)
		if geometry.is_empty() or data.is_empty():
			continue
		var canvas := data.get("canvas_size_px") as Array
		_expect_equal(
			geometry.get("canvas_size_px"),
			canvas,
			"%s geometry and occlusion use one canvas" % room_id,
		)
		_expect_equal(
			geometry.get("room_id"),
			data.get("room_id"),
			"%s geometry and occlusion use one room identity" % room_id,
		)
		_expect(
			not String(data.get("source_revision", "")).is_empty(),
			"%s occlusion keeps its authored source revision" % room_id,
		)
		var canvas_size := Vector2i(int(canvas[0]), int(canvas[1]))
		var image := Image.create(
			canvas_size.x,
			canvas_size.y,
			false,
			Image.FORMAT_RGBA8,
		)
		image.fill(Color(0.48, 0.32, 0.2, 1.0))
		_expect_equal(
			Vector2i(image.get_width(), image.get_height()),
			canvas_size,
			"%s synthetic shell matches authored occlusion canvas" % room_id,
		)
		var original_bytes := image.get_data()
		var shell := Sprite2D.new()
		shell.centered = false
		shell.texture = ImageTexture.create_from_image(image)
		root.add_child(shell)
		var occlusion := WALL_OCCLUSION.new()
		root.add_child(occlusion)
		_expect(
			bool(occlusion.configure(
				shell,
				geometry,
				base.path_join("wall_occlusion.json"),
			)),
			"%s formal wall occlusion configures" % room_id,
		)
		var segments := data.get("segments") as Array
		_expect_equal(
			occlusion.get_child_count(),
			segments.size() + 1,
			"%s creates exactly one node per segment and one debug root"
			% room_id,
		)
		for segment_value: Variant in segments:
			var segment := segment_value as Dictionary
			_expect(
				occlusion.get_node_or_null(String(segment.get("id"))) != null,
				"%s exposes the stable segment %s"
				% [room_id, segment.get("id")],
			)
		occlusion.free()
		_expect_equal(
			shell.texture.get_image().get_data(),
			original_bytes,
			"%s restores the source shell after unload" % room_id,
		)
		shell.free()
		configured_rooms += 1
	_expect_equal(
		configured_rooms,
		ROOMS.size(),
		"every formal room geometry and wall data pair is exercised",
	)


func _synthetic_data() -> Dictionary:
	return {
		"schema_version": 1,
		"source_revision": "cutout_test",
		"room_id": "cutout_test",
		"canvas_size_px": [16, 16],
		"segments": [{
			"id": "wall_with_floor_cutout",
			"foreground_polygon_canvas_px": [
				[0, 0], [16, 0], [16, 16], [0, 16],
			],
			"foreground_cutout_polygons_canvas_px": [
				[[4, 4], [12, 4], [12, 12], [4, 12]],
			],
			"reveal_polygons_canvas_px": [
				[[0, 0], [16, 0], [16, 16], [0, 16]],
			],
			"fade_distance_px": 4,
			"minimum_alpha": 0.15,
		}],
	}


func _visible_subject_overlays(occlusion: Node2D) -> Array[Sprite2D]:
	var result: Array[Sprite2D] = []
	for child in occlusion.get_children():
		if child is Sprite2D and child.has_meta("subject_overlay") and child.visible:
			result.append(child as Sprite2D)
	return result


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


func _write_json(path: String, value: Dictionary) -> void:
	_write_text(path, JSON.stringify(value))


func _write_text(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value)
	file.close()


func _cleanup() -> void:
	for path in [VALID_PATH, INVALID_PATH]:
		var absolute := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(absolute)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_equal(
	actual: Variant,
	expected: Variant,
	message: String,
) -> void:
	if actual != expected:
		_failures.append(
			"%s: expected %s, got %s" % [message, expected, actual]
		)


func _finish() -> void:
	_prepare_audio_shutdown()
	if _failures.is_empty():
		print(
			"TOWN_INTERIOR_WALL_OCCLUSION_PASS: %d formal rooms"
			% ROOMS.size()
		)
		call_deferred("_quit_after_cleanup", 0)
		return
	for failure in _failures:
		printerr("TOWN_INTERIOR_WALL_OCCLUSION_FAIL: %s" % failure)
	call_deferred("_quit_after_cleanup", 1)


func _quit_after_cleanup(exit_code: int) -> void:
	await process_frame
	await process_frame
	quit(exit_code)


func _prepare_audio_shutdown() -> void:
	var audio := root.get_node_or_null("TownAudioController")
	if audio != null and audio.has_method("prepare_shutdown"):
		audio.call("prepare_shutdown")
