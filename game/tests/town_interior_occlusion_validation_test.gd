extends SceneTree

const WALL_OCCLUSION := preload(
	"res://world/maps/town/interiors/InteriorWallOcclusion.gd"
)
const MANIFEST_VALIDATOR := preload(
	"res://world/maps/town/interiors/InteriorOcclusionManifest.gd"
)
const SOURCE_ROOT := (
	"res://world/maps/town/interiors/redesign_v2/rooms/cafe"
)
const TEST_ROOT := "user://issue141_manifest_validation/cafe"

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_remove_test_root()
	_expect(
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(TEST_ROOT),
		) == OK,
		"validation fixture directory is created",
	)
	var geometry_path := TEST_ROOT.path_join("room_geometry.json")
	var occlusion_path := TEST_ROOT.path_join("wall_occlusion.json")
	var shell_path := TEST_ROOT.path_join("cafe.png")
	_expect(_copy_source("room_geometry.json", geometry_path), "geometry fixture copies")
	_expect(_copy_source("wall_occlusion.json", occlusion_path), "occlusion fixture copies")
	_expect(
		_copy_source("assets/background/room_shell.png", shell_path),
		"shell fixture copies",
	)
	var geometry := _read_json(geometry_path)
	var authored := _read_json(occlusion_path)
	var manifest := _read_json(SOURCE_ROOT.path_join("wall_occlusion_runtime.json"))
	manifest["source_geometry_sha256"] = FileAccess.get_sha256(geometry_path)
	manifest["source_occlusion_sha256"] = FileAccess.get_sha256(occlusion_path)
	manifest["source_shell_path"] = shell_path
	manifest["source_shell_sha256"] = FileAccess.get_sha256(shell_path)
	var manifest_path := TEST_ROOT.path_join("wall_occlusion_runtime.json")
	_write_json(manifest_path, manifest)
	var validator := MANIFEST_VALIDATOR.new()
	_expect_equal(
		_validation_code(validator, manifest, geometry, authored, geometry_path, occlusion_path, shell_path),
		"OK",
		"valid generated data passes the standalone manifest boundary",
	)
	_test_negative_manifest_cases(
		validator,
		manifest,
		geometry,
		authored,
		geometry_path,
		occlusion_path,
		shell_path,
	)
	_test_malformed_json(
		validator,
		manifest,
		geometry,
		geometry_path,
		occlusion_path,
		shell_path,
		manifest_path,
	)
	await _test_failed_configuration_is_atomic(
		manifest,
		geometry,
		geometry_path,
		occlusion_path,
		shell_path,
		manifest_path,
	)
	_remove_test_root()
	await process_frame
	await process_frame
	_finish()


func _test_negative_manifest_cases(
	validator: RefCounted,
	manifest: Dictionary,
	geometry: Dictionary,
	authored: Dictionary,
	geometry_path: String,
	occlusion_path: String,
	shell_path: String,
) -> void:
	var cases: Array[Dictionary] = []
	var unknown_key := manifest.duplicate(true)
	unknown_key["debug"] = true
	cases.append({"data": unknown_key, "code": "MANIFEST_SHAPE_INVALID"})
	var wrong_schema := manifest.duplicate(true)
	wrong_schema["schema_version"] = 1
	cases.append({"data": wrong_schema, "code": "MANIFEST_VERSION_STALE"})
	var wrong_geometry_revision := manifest.duplicate(true)
	wrong_geometry_revision["source_geometry_revision"] = "stale"
	cases.append({"data": wrong_geometry_revision, "code": "GEOMETRY_REVISION_STALE"})
	var wrong_occlusion_revision := manifest.duplicate(true)
	wrong_occlusion_revision["source_occlusion_revision"] = "stale"
	cases.append({"data": wrong_occlusion_revision, "code": "OCCLUSION_REVISION_STALE"})
	var wrong_geometry_digest := manifest.duplicate(true)
	wrong_geometry_digest["source_geometry_sha256"] = "0".repeat(64)
	cases.append({"data": wrong_geometry_digest, "code": "GEOMETRY_DIGEST_STALE"})
	var wrong_occlusion_digest := manifest.duplicate(true)
	wrong_occlusion_digest["source_occlusion_sha256"] = "0".repeat(64)
	cases.append({"data": wrong_occlusion_digest, "code": "OCCLUSION_DIGEST_STALE"})
	var wrong_shell_digest := manifest.duplicate(true)
	wrong_shell_digest["source_shell_sha256"] = "0".repeat(64)
	cases.append({"data": wrong_shell_digest, "code": "SHELL_DIGEST_STALE"})
	var duplicate_segment := manifest.duplicate(true)
	(duplicate_segment.get("segments") as Array).append(
		(duplicate_segment.get("segments") as Array)[0].duplicate(true),
	)
	cases.append({"data": duplicate_segment, "code": "SEGMENT_ID_INVALID"})
	var malformed_segment := manifest.duplicate(true)
	malformed_segment["segments"] = [true]
	cases.append({"data": malformed_segment, "code": "SEGMENT_INVALID"})
	var crossing_polygon := manifest.duplicate(true)
	((crossing_polygon.get("segments") as Array)[0] as Dictionary)[
		"reveal_polygons_canvas_px"
	] = [[[0, 0], [16, 16], [0, 16], [16, 0]]]
	cases.append({"data": crossing_polygon, "code": "REVEAL_POLYGON_INVALID"})
	var repeated_vertex := manifest.duplicate(true)
	((repeated_vertex.get("segments") as Array)[0] as Dictionary)[
		"reveal_polygons_canvas_px"
	] = [[[0, 0], [16, 0], [0, 0], [0, 16]]]
	cases.append({"data": repeated_vertex, "code": "REVEAL_POLYGON_INVALID"})
	var extreme_fade := manifest.duplicate(true)
	((extreme_fade.get("segments") as Array)[0] as Dictionary)[
		"fade_distance_px"
	] = 1.0e300
	cases.append({"data": extreme_fade, "code": "FADE_INVALID"})
	var wrong_texture_digest := manifest.duplicate(true)
	((wrong_texture_digest.get("segments") as Array)[0] as Dictionary)[
		"foreground_texture_sha256"
	] = "0".repeat(64)
	cases.append({"data": wrong_texture_digest, "code": "TEXTURE_DIGEST_STALE"})
	var extreme_origin := manifest.duplicate(true)
	((extreme_origin.get("segments") as Array)[0] as Dictionary)[
		"foreground_canvas_origin_px"
	] = [1.0e300, 0]
	cases.append({"data": extreme_origin, "code": "TEXTURE_ORIGIN_INVALID"})
	for case in cases:
		_expect_equal(
			_validation_code(
				validator,
				case.get("data") as Dictionary,
				geometry,
				authored,
				geometry_path,
				occlusion_path,
				shell_path,
			),
			String(case.get("code")),
			"invalid manifest case is rejected by its stable code",
		)
	var missing_geometry_revision := geometry.duplicate(true)
	missing_geometry_revision["source_revision"] = ""
	_expect_equal(
		_validation_code(
			validator,
			manifest,
			missing_geometry_revision,
			authored,
			geometry_path,
			occlusion_path,
			shell_path,
		),
		"GEOMETRY_REVISION_MISSING",
		"empty geometry revision is rejected before digest acceptance",
	)
	var missing_occlusion_revision := authored.duplicate(true)
	missing_occlusion_revision["source_revision"] = ""
	_expect_equal(
		_validation_code(
			validator,
			manifest,
			geometry,
			missing_occlusion_revision,
			geometry_path,
			occlusion_path,
			shell_path,
		),
		"OCCLUSION_REVISION_MISSING",
		"empty occlusion revision is rejected before digest acceptance",
	)
	_expect_equal(
		String(validator.load_validated([], [], [], []).get("code")),
		"INVALID_INPUT",
		"wrong public input types are rejected",
	)


func _test_malformed_json(
	validator: RefCounted,
	manifest: Dictionary,
	geometry: Dictionary,
	geometry_path: String,
	occlusion_path: String,
	shell_path: String,
	manifest_path: String,
) -> void:
	_write_text(manifest_path, "{")
	_expect_equal(
		String(validator.begin_load_staged(
			geometry,
			geometry_path,
			occlusion_path,
			shell_path,
		).get("code")),
		"MANIFEST_MISSING",
		"malformed manifest JSON is rejected",
	)
	_write_json(manifest_path, manifest)
	var authored_text := FileAccess.get_file_as_string(occlusion_path)
	_write_text(occlusion_path, "{")
	_expect_equal(
		String(validator.begin_load_staged(
			geometry,
			geometry_path,
			occlusion_path,
			shell_path,
		).get("code")),
		"OCCLUSION_SOURCE_MISSING",
		"malformed authored occlusion JSON is rejected",
	)
	_write_text(occlusion_path, authored_text)


func _test_failed_configuration_is_atomic(
	manifest: Dictionary,
	geometry: Dictionary,
	geometry_path: String,
	occlusion_path: String,
	shell_path: String,
	manifest_path: String,
) -> void:
	var shell_image := Image.new()
	_expect_equal(
		shell_image.load(ProjectSettings.globalize_path(shell_path)),
		OK,
		"atomic configuration fixture shell loads",
	)
	var shell := Sprite2D.new()
	shell.texture = ImageTexture.create_from_image(shell_image)
	root.add_child(shell)
	var occlusion := WALL_OCCLUSION.new()
	root.add_child(occlusion)
	_expect(
		bool(occlusion.configure(
			shell,
			geometry,
			geometry_path,
			occlusion_path,
			shell_path,
		)),
		"valid configuration establishes the old render state",
	)
	var child_ids: Array[int] = []
	for child in occlusion.get_children():
		child_ids.append(child.get_instance_id())
	var stale := manifest.duplicate(true)
	stale["schema_version"] = 1
	_write_json(manifest_path, stale)
	var rejected := not bool(occlusion.configure(
		shell,
		geometry,
		geometry_path,
		occlusion_path,
		shell_path,
	))
	_expect(rejected, "stale replacement configuration is rejected")
	var after_ids: Array[int] = []
	for child in occlusion.get_children():
		after_ids.append(child.get_instance_id())
	_expect_equal(
		after_ids,
		child_ids,
		"failed replacement keeps every previous render node",
	)
	_write_text(manifest_path, "{")
	rejected = not bool(occlusion.configure(
		shell,
		geometry,
		geometry_path,
		occlusion_path,
		shell_path,
	))
	_expect(rejected, "malformed replacement configuration is rejected")
	_expect_equal(
		occlusion.get_child_count(),
		child_ids.size(),
		"malformed replacement also keeps the previous render state",
	)
	_write_json(manifest_path, manifest)
	occlusion.free()
	shell.free()
	await process_frame


func _validation_code(
	validator: RefCounted,
	manifest: Dictionary,
	geometry: Dictionary,
	authored: Dictionary,
	geometry_path: String,
	occlusion_path: String,
	shell_path: String,
) -> String:
	var result := validator.call(
		"validate",
		manifest,
		geometry,
		authored,
		geometry_path,
		occlusion_path,
		shell_path,
	) as Dictionary
	return "OK" if result.get("ok") == true else String(result.get("code"))


func _copy_source(file_name: String, destination: String) -> bool:
	return DirAccess.copy_absolute(
		ProjectSettings.globalize_path(SOURCE_ROOT.path_join(file_name)),
		ProjectSettings.globalize_path(destination),
	) == OK


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


func _write_json(path: String, value: Dictionary) -> void:
	_write_text(path, JSON.stringify(value, "  ") + "\n")


func _write_text(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value)
	file.close()


func _remove_test_root() -> void:
	var absolute := ProjectSettings.globalize_path("user://issue141_manifest_validation")
	_remove_tree_contents(absolute)
	if DirAccess.dir_exists_absolute(absolute):
		DirAccess.remove_absolute(absolute)


func _remove_tree_contents(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		var child := path.path_join(entry)
		if directory.current_is_dir():
			_remove_tree_contents(child)
			DirAccess.remove_absolute(child)
		else:
			DirAccess.remove_absolute(child)
		entry = directory.get_next()
	directory.list_dir_end()


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s: expected %s, got %s" % [message, expected, actual])


func _finish() -> void:
	_prepare_audio_shutdown()
	if _failures.is_empty():
		print("TOWN_INTERIOR_OCCLUSION_VALIDATION_PASS checks=%d" % _checks)
		call_deferred("_quit_after_cleanup", 0)
		return
	for failure in _failures:
		printerr("TOWN_INTERIOR_OCCLUSION_VALIDATION_FAIL: %s" % failure)
	call_deferred("_quit_after_cleanup", 1)


func _quit_after_cleanup(exit_code: int) -> void:
	await process_frame
	await process_frame
	await create_timer(0.2).timeout
	quit(exit_code)


func _prepare_audio_shutdown() -> void:
	var audio := root.get_node_or_null("TownAudioController")
	if audio != null and audio.has_method("prepare_shutdown"):
		audio.call("prepare_shutdown")
