extends SceneTree

const GENERATOR := preload(
	"res://tools/interiors/InteriorOcclusionAssetGenerator.gd"
)
const PUBLISH_TRANSACTION := preload(
	"res://tools/interiors/InteriorOcclusionPublishTransaction.gd"
)
const MANIFEST_PATH_RESOLVER := preload(
	"res://world/maps/town/interiors/InteriorOcclusionManifestPathResolver.gd"
)
const TEST_ROOT := "user://issue141_generator_atomic"
const ROOMS_ROOT := TEST_ROOT + "/rooms"
const ROOM_IDS: Array[String] = ["room_a", "room_b"]

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_remove_test_root()
	for room_id in ROOM_IDS:
		_create_room_fixture(room_id, "v1")
	var generator := GENERATOR.new()
	var first := generator.generate(ROOMS_ROOT, ROOM_IDS) as Dictionary
	_expect_equal(first.get("ok"), true, "two-room generation succeeds")
	_expect_equal(first.get("room_count"), 2, "both rooms publish together")
	_expect_equal(first.get("segment_count"), 2, "both segment textures publish together")
	var manifest_a_path := ROOMS_ROOT.path_join("room_a/wall_occlusion_runtime.json")
	var manifest_b_path := ROOMS_ROOT.path_join("room_b/wall_occlusion_runtime.json")
	var manifest_a := _read_json(manifest_a_path)
	var manifest_b := _read_json(manifest_b_path)
	_expect_equal(manifest_a.get("schema_version"), 2, "room A uses schema 2")
	_expect_equal(manifest_b.get("schema_version"), 2, "room B uses schema 2")
	var asset_a := (manifest_a.get("segments") as Array)[0] as Dictionary
	var texture_a_path := String(asset_a.get("foreground_texture_path"))
	_expect(
		texture_a_path.contains(String(asset_a.get("foreground_texture_sha256")).left(12)),
		"published texture name is content-addressed",
	)
	_expect_equal(
		asset_a.get("foreground_texture_sha256"),
		FileAccess.get_sha256(texture_a_path),
		"published texture digest matches the manifest",
	)
	var previous_manifest_text := FileAccess.get_file_as_string(manifest_a_path)
	var previous_texture_hash := FileAccess.get_sha256(texture_a_path)
	_create_room_fixture("room_a", "v2")
	_write_text(ROOMS_ROOT.path_join("room_b/wall_occlusion.json"), "{}\n")
	var failed := generator.generate(ROOMS_ROOT, ROOM_IDS) as Dictionary
	_expect_equal(failed.get("ok"), false, "a later room staging failure rejects the batch")
	_expect_equal(
		FileAccess.get_file_as_string(manifest_a_path),
		previous_manifest_text,
		"failed batch keeps room A's previous manifest byte-for-byte",
	)
	_expect_equal(
		FileAccess.get_sha256(texture_a_path),
		previous_texture_hash,
		"failed batch keeps room A's previous published texture",
	)
	_expect_equal(
		_read_json(manifest_a_path).get("source_occlusion_revision"),
		"v1",
		"failed batch cannot publish room A's staged v2 metadata",
	)
	_create_room_fixture("room_b", "v1")
	_create_room_fixture("room_a", "v2")
	var invalid_polygon := _read_json(
		ROOMS_ROOT.path_join("room_a/wall_occlusion.json"),
	)
	var invalid_polygon_segment := (
		(invalid_polygon.get("segments") as Array)[0] as Dictionary
	)
	invalid_polygon_segment["reveal_polygons_canvas_px"] = [[
		[0, 0], [16, 16], [0, 16], [16, 0],
	]]
	_write_json(
		ROOMS_ROOT.path_join("room_a/wall_occlusion.json"),
		invalid_polygon,
	)
	var invalid_polygon_result := generator.generate(ROOMS_ROOT, ROOM_IDS) as Dictionary
	_expect_equal(
		invalid_polygon_result.get("ok"),
		false,
		"an invalid reveal polygon is rejected before publication",
	)
	_expect_equal(
		FileAccess.get_file_as_string(manifest_a_path),
		previous_manifest_text,
		"an invalid reveal polygon keeps the previous manifest",
	)
	_create_room_fixture("room_a", "v2")
	var extreme_fade := _read_json(
		ROOMS_ROOT.path_join("room_a/wall_occlusion.json"),
	)
	var extreme_fade_segment := (
		(extreme_fade.get("segments") as Array)[0] as Dictionary
	)
	extreme_fade_segment["fade_distance_px"] = 70000
	_write_json(
		ROOMS_ROOT.path_join("room_a/wall_occlusion.json"),
		extreme_fade,
	)
	var extreme_fade_result := generator.generate(ROOMS_ROOT, ROOM_IDS) as Dictionary
	_expect_equal(
		extreme_fade_result.get("ok"),
		false,
		"an extreme fade value is rejected before publication",
	)
	_expect_equal(
		FileAccess.get_file_as_string(manifest_a_path),
		previous_manifest_text,
		"an extreme fade value keeps the previous manifest",
	)
	_create_room_fixture("room_a", "v2")
	_create_room_fixture("room_b", "v2")
	var staging_root := TEST_ROOT.path_join("publish_failure_staging")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(staging_root))
	var staged_b := generator.call(
		"_stage_room",
		ROOMS_ROOT,
		"room_b",
		staging_root,
	) as Dictionary
	var staged_b_asset := (staged_b.get("assets") as Array)[0] as Dictionary
	var collision_path := String(staged_b_asset.get("final_path"))
	_write_text(collision_path, "digest collision")
	var staged_a := generator.call(
		"_stage_room",
		ROOMS_ROOT,
		"room_a",
		staging_root,
	) as Dictionary
	var staged_a_asset := (staged_a.get("assets") as Array)[0] as Dictionary
	var new_a_texture_path := String(staged_a_asset.get("final_path"))
	var publish_failure := generator.generate(ROOMS_ROOT, ROOM_IDS) as Dictionary
	_expect_equal(
		publish_failure.get("ok"),
		false,
		"a content-address collision aborts publication",
	)
	_expect(
		not FileAccess.file_exists(new_a_texture_path),
		"publication rollback removes assets created by the failed run",
	)
	_expect_equal(
		FileAccess.get_file_as_string(manifest_a_path),
		previous_manifest_text,
		"publication failure keeps the previous manifest",
	)
	_test_second_manifest_commit_interruption()
	_test_backup_rename_interruption()
	_test_manifest_commit_interruption()
	_test_rollback_remove_failure()
	_test_backup_restore_failure()
	_test_committed_backup_delete_failure()
	_test_journal_record_failures()
	_test_duplicate_room_ids()
	_test_runtime_view_during_hard_interruption()
	_remove_test_root()
	await process_frame
	await process_frame
	_finish()


func _test_second_manifest_commit_interruption() -> void:
	_prepare_published_revision("v1")
	_create_room_fixture("room_a", "v2")
	_create_room_fixture("room_b", "v2")
	var interrupted := _faulted_generate("manifest_commit_rename", 2)
	_expect_equal(
		interrupted.get("ok"),
		false,
		"an interruption before the second manifest commit rejects the publish",
	)
	_expect_equal(
		_manifest_revision("room_a"),
		"v1",
		"a reported second-manifest interruption is rolled back before return",
	)
	_expect(
		FileAccess.file_exists(_manifest_path("room_b")),
		"a reported interruption restores the second previous manifest",
	)
	_expect_equal(
		interrupted.get("recovery_pending"),
		false,
		"a reported interruption leaves no recovery pending",
	)
	_expect_published_revision_is_consistent(
		"v1",
		"multi-manifest rollback leaves one complete previous version",
	)


func _test_backup_rename_interruption() -> void:
	_prepare_published_revision("v1")
	_create_room_fixture("room_a", "v2")
	_create_room_fixture("room_b", "v2")
	var interrupted := _faulted_generate("backup_rename_after")
	_expect_equal(
		interrupted.get("ok"),
		false,
		"an interruption immediately after backup rename rejects the publish",
	)
	_expect_equal(
		_manifest_revision("room_a"),
		"v1",
		"a reported backup interruption restores the previous manifest before return",
	)
	_expect_published_revision_is_consistent(
		"v1",
		"backup recovery leaves one complete previous version",
	)


func _test_manifest_commit_interruption() -> void:
	_prepare_published_revision("v1")
	_create_room_fixture("room_a", "v2")
	_create_room_fixture("room_b", "v2")
	var interrupted := _faulted_generate("manifest_commit_rename_after")
	_expect_equal(
		interrupted.get("ok"),
		false,
		"an interruption after final manifest rename rejects the publish",
	)
	_expect_equal(
		_manifest_revision("room_a"),
		"v1",
		"a reported final-rename interruption rolls back before return",
	)
	_expect_published_revision_is_consistent(
		"v1",
		"post-rename recovery leaves one complete previous version",
	)


func _test_rollback_remove_failure() -> void:
	_prepare_interrupted_manifest_commit()
	_write_text(ROOMS_ROOT.path_join("room_b/wall_occlusion.json"), "{}\n")
	var failed_recovery := _faulted_generate("rollback_remove")
	_expect_equal(
		failed_recovery.get("recovery_pending"),
		true,
		"a failed rollback remove keeps the recovery transaction pending",
	)
	_expect_equal(
		_recover_without_republishing(),
		"v1",
		"a later fresh generator can retry rollback remove",
	)
	_expect_published_revision_is_consistent(
		"v1",
		"retried rollback remove restores every manifest and texture",
	)


func _test_backup_restore_failure() -> void:
	_prepare_interrupted_manifest_commit()
	_write_text(ROOMS_ROOT.path_join("room_b/wall_occlusion.json"), "{}\n")
	var failed_recovery := _faulted_generate("backup_restore_rename")
	_expect_equal(
		failed_recovery.get("recovery_pending"),
		true,
		"a failed backup restore keeps the recovery transaction pending",
	)
	_expect_equal(
		_recover_without_republishing(),
		"v1",
		"a later fresh generator can retry backup restoration",
	)
	_expect_published_revision_is_consistent(
		"v1",
		"retried backup restoration restores every manifest and texture",
	)


func _test_committed_backup_delete_failure() -> void:
	_prepare_published_revision("v1")
	_create_room_fixture("room_a", "v2")
	_create_room_fixture("room_b", "v2")
	var interrupted := _interrupt_publish_direct("backup_delete")
	_expect_equal(
		interrupted.get("recovery_pending"),
		true,
		"a committed transaction remains recoverable when backup deletion fails",
	)
	_expect_equal(
		_manifest_revision("room_a"),
		"v2",
		"a cleanup failure does not roll a committed manifest back",
	)
	_write_text(ROOMS_ROOT.path_join("room_b/wall_occlusion.json"), "{}\n")
	var recovery_then_staging_failure := GENERATOR.new().generate(
		ROOMS_ROOT,
		ROOM_IDS,
	) as Dictionary
	_expect_equal(
		recovery_then_staging_failure.get("ok"),
		false,
		"a fresh generator completes committed cleanup before staging",
	)
	_expect_equal(
		_manifest_revision("room_a"),
		"v2",
		"roll-forward recovery preserves the committed manifest",
	)
	_expect_published_revision_is_consistent(
		"v2",
		"roll-forward recovery preserves one complete committed version",
	)


func _test_journal_record_failures() -> void:
	_prepare_published_revision("v1")
	_create_room_fixture("room_a", "v2")
	_create_room_fixture("room_b", "v2")
	var begin_failure := _faulted_generate("journal_record")
	_expect_equal(
		begin_failure.get("ok"),
		false,
		"a failed begin journal record rejects the publish",
	)
	_expect_equal(
		_manifest_revision("room_a"),
		"v1",
		"no manifest changes before the begin record is durable",
	)
	var commit_failure := _faulted_generate("journal_record", 2)
	_expect_equal(
		commit_failure.get("ok"),
		false,
		"a failed commit journal record leaves an incomplete transaction",
	)
	_expect_equal(
		commit_failure.get("recovery_pending"),
		false,
		"a failed commit record is rolled back before generate returns",
	)
	_expect_equal(
		_manifest_revision("room_a"),
		"v1",
		"commit-record failure restores the previous manifests",
	)
	_expect_published_revision_is_consistent(
		"v1",
		"commit-record recovery leaves one complete previous version",
	)
	_create_room_fixture("room_a", "v2")
	_create_room_fixture("room_b", "v2")
	var partial_commit := _faulted_generate("journal_commit_partial")
	_expect_equal(
		partial_commit.get("ok"),
		false,
		"a truncated commit record rejects the publish",
	)
	_expect_equal(
		partial_commit.get("recovery_pending"),
		false,
		"a truncated commit tail is treated as uncommitted and rolled back",
	)
	_expect_published_revision_is_consistent(
		"v1",
		"truncated commit recovery leaves one complete previous version",
	)


func _test_duplicate_room_ids() -> void:
	_prepare_published_revision("v1")
	var duplicate_ids: Array[String] = ["room_a", "room_a"]
	var duplicate_result := GENERATOR.new().generate(
		ROOMS_ROOT,
		duplicate_ids,
	) as Dictionary
	_expect_equal(
		duplicate_result.get("ok"),
		false,
		"duplicate room ids are rejected before a transaction starts",
	)
	_expect(
		not FileAccess.file_exists(
			ROOMS_ROOT.path_join(".wall_occlusion_publish.journal"),
		),
		"duplicate room ids cannot leave an unrecoverable journal",
	)


func _test_runtime_view_during_hard_interruption() -> void:
	_prepare_published_revision("v1")
	_create_room_fixture("room_a", "v2")
	_create_room_fixture("room_b", "v2")
	_interrupt_publish_direct("manifest_commit_rename", 2)
	var consistent_previous_view := true
	for room_id in ROOM_IDS:
		var manifest_path := _manifest_path(room_id)
		var occlusion_path := ROOMS_ROOT.path_join(
			room_id,
		).path_join("wall_occlusion.json")
		var resolved := MANIFEST_PATH_RESOLVER.resolve(
			manifest_path,
			occlusion_path,
		) as Dictionary
		var visible_manifest := _read_json(String(resolved.get("path", "")))
		consistent_previous_view = (
			consistent_previous_view
			and resolved.get("ok") == true
			and String(visible_manifest.get("source_occlusion_revision", "")) == "v1"
		)
	_expect(
		consistent_previous_view,
		"runtime resolves every room to the previous version during hard interruption",
	)
	_expect_equal(
		_recover_without_republishing(),
		"v1",
		"the next generator completes hard-interruption recovery",
	)
	_expect_published_revision_is_consistent(
		"v1",
		"hard-interruption recovery leaves one complete previous version",
	)


func _prepare_interrupted_manifest_commit() -> void:
	_prepare_published_revision("v1")
	_create_room_fixture("room_a", "v2")
	_create_room_fixture("room_b", "v2")
	_interrupt_publish_direct("manifest_commit_rename_after")


func _interrupt_publish_direct(point: String, occurrence: int = 1) -> Dictionary:
	var staging_root := TEST_ROOT.path_join(
		"hard_interrupt_%d" % Time.get_ticks_usec(),
	)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(staging_root))
	var generator := GENERATOR.new()
	var staged_rooms: Array[Dictionary] = []
	for room_id in ROOM_IDS:
		staged_rooms.append(
			generator.call("_stage_room", ROOMS_ROOT, room_id, staging_root) as Dictionary,
		)
	var transaction := PUBLISH_TRANSACTION.new()
	transaction.configure_fault(point, occurrence)
	return transaction.publish(
		ROOMS_ROOT,
		staged_rooms,
		"hard_interrupt_%d" % Time.get_ticks_usec(),
	) as Dictionary


func _prepare_published_revision(revision: String) -> void:
	_remove_test_root()
	for room_id in ROOM_IDS:
		_create_room_fixture(room_id, revision)
	GENERATOR.new().generate(ROOMS_ROOT, ROOM_IDS)


func _faulted_generate(point: String, occurrence: int = 1) -> Dictionary:
	var generator := GENERATOR.new()
	generator.configure_publish_fault(point, occurrence)
	return generator.generate(ROOMS_ROOT, ROOM_IDS) as Dictionary


func _recover_without_republishing() -> String:
	_write_text(ROOMS_ROOT.path_join("room_b/wall_occlusion.json"), "{}\n")
	var recovery_then_staging_failure := GENERATOR.new().generate(
		ROOMS_ROOT,
		ROOM_IDS,
	) as Dictionary
	_expect_equal(
		recovery_then_staging_failure.get("ok"),
		false,
		"recovery completes before deliberately invalid staging",
	)
	return _manifest_revision("room_a")


func _manifest_path(room_id: String) -> String:
	return ROOMS_ROOT.path_join(room_id).path_join("wall_occlusion_runtime.json")


func _manifest_revision(room_id: String) -> String:
	return String(_read_json(_manifest_path(room_id)).get("source_occlusion_revision", ""))


func _expect_published_revision_is_consistent(
	revision: String,
	message: String,
) -> void:
	var consistent := true
	for room_id in ROOM_IDS:
		var manifest := _read_json(_manifest_path(room_id))
		consistent = consistent and String(
			manifest.get("source_occlusion_revision", ""),
		) == revision
		var segments_value: Variant = manifest.get("segments")
		if segments_value is not Array or (segments_value as Array).is_empty():
			consistent = false
			continue
		for segment_value: Variant in segments_value as Array:
			var segment := segment_value as Dictionary
			var texture_path := String(segment.get("foreground_texture_path", ""))
			consistent = (
				consistent
				and FileAccess.file_exists(texture_path)
				and FileAccess.get_sha256(texture_path)
				== String(segment.get("foreground_texture_sha256", ""))
			)
	_expect(consistent, message)


func _create_room_fixture(room_id: String, revision: String) -> void:
	var room_root := ROOMS_ROOT.path_join(room_id)
	var shell_directory := room_root.path_join("assets/background")
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(shell_directory),
	)
	var shell_path := shell_directory.path_join("room_shell.png")
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(
		Color(0.7, 0.4, 0.2, 1.0)
		if revision == "v1"
		else Color(0.2, 0.5, 0.8, 1.0)
	)
	image.save_png(ProjectSettings.globalize_path(shell_path))
	_write_json(room_root.path_join("room_geometry.json"), {
		"room_id": room_id,
		"source_revision": revision,
		"background_sprite": "assets/background/room_shell.png",
		"canvas_size_px": [16, 16],
	})
	_write_json(room_root.path_join("wall_occlusion.json"), {
		"room_id": room_id,
		"source_revision": revision,
		"canvas_size_px": [16, 16],
		"segments": [{
			"id": "front_wall",
			"foreground_polygon_canvas_px": [
				[0, 0], [16, 0], [16, 8], [0, 8],
			],
			"foreground_cutout_polygons_canvas_px": [],
			"reveal_polygons_canvas_px": [[
				[0, 0], [16, 0], [16, 16], [0, 16],
			]],
			"fade_distance_px": 4,
			"minimum_alpha": 0.2,
		}],
	})


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
	var absolute := ProjectSettings.globalize_path(TEST_ROOT)
	_remove_tree_contents(absolute)
	if DirAccess.dir_exists_absolute(absolute):
		DirAccess.remove_absolute(absolute)


func _remove_tree_contents(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	var entries: Array[Dictionary] = []
	directory.include_hidden = true
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		entries.append({"name": entry, "directory": directory.current_is_dir()})
		entry = directory.get_next()
	directory.list_dir_end()
	for record in entries:
		var child := path.path_join(String(record.get("name", "")))
		if bool(record.get("directory")):
			_remove_tree_contents(child)
			DirAccess.remove_absolute(child)
		else:
			DirAccess.remove_absolute(child)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s: expected %s, got %s" % [message, expected, actual])


func _finish() -> void:
	_prepare_audio_shutdown()
	if _failures.is_empty():
		print("INTERIOR_OCCLUSION_ASSET_GENERATOR_PASS checks=%d" % _checks)
		call_deferred("_quit_after_cleanup", 0)
		return
	for failure in _failures:
		printerr("INTERIOR_OCCLUSION_ASSET_GENERATOR_FAIL: %s" % failure)
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
