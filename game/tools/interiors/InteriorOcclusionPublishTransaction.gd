extends RefCounted

const FILE_OPS_SCRIPT := preload(
	"res://tools/interiors/InteriorOcclusionPublishFileOps.gd"
)
const JOURNAL_VERSION := 1
const RUNTIME_DIRECTORY := "wall_occlusion_runtime"

var _files := FILE_OPS_SCRIPT.new()


func configure_fault(point: String, occurrence: int = 1) -> void:
	_files.configure_fault(point, occurrence)


func recover_pending(rooms_root: String) -> Dictionary:
	var journal_path := _journal_path(rooms_root)
	if not FileAccess.file_exists(journal_path):
		return {"ok": true, "recovered": false}
	var journal := _read_journal(journal_path, rooms_root)
	if journal.get("ok") != true:
		return _pending_failure(String(journal.get("error", "journal is invalid")))
	var plan := journal.get("plan") as Dictionary
	var recovered := (
		_roll_forward(plan, journal_path)
		if bool(journal.get("committed"))
		else _roll_back(plan, journal_path)
	)
	if recovered.get("ok") != true:
		return _pending_failure(String(recovered.get("error", "recovery failed")))
	recovered["recovered"] = true
	return recovered


func publish(
	rooms_root: String,
	staged_rooms: Array[Dictionary],
	run_id: String,
) -> Dictionary:
	var plan_result := _create_plan(rooms_root, staged_rooms, run_id)
	if plan_result.get("ok") != true:
		return plan_result
	var plan := plan_result.get("plan") as Dictionary
	var journal_path := _journal_path(rooms_root)
	if FileAccess.file_exists(journal_path):
		return _pending_failure("a previous publish transaction is pending")
	if not _files.begin_journal(journal_path, {
		"event": "begin",
		"version": JOURNAL_VERSION,
		"plan": plan,
	}):
		var failure := _operation_failure("publish journal could not be created")
		failure["recovery_pending"] = FileAccess.file_exists(journal_path)
		return failure
	var assets_result := _publish_assets(plan)
	if assets_result.get("ok") != true:
		return assets_result
	var manifests_result := _publish_manifests(plan)
	if manifests_result.get("ok") != true:
		return manifests_result
	if not _files.append_journal(journal_path, {"event": "commit"}):
		return _operation_failure("publish commit could not be recorded")
	var cleanup := _roll_forward(plan, journal_path)
	if cleanup.get("ok") != true:
		return _pending_failure(String(cleanup.get("error", "commit cleanup failed")))
	return {
		"ok": true,
		"segment_count": (plan.get("assets") as Array).size(),
	}


func _create_plan(
	rooms_root: String,
	staged_rooms: Array[Dictionary],
	run_id: String,
) -> Dictionary:
	var manifests: Array[Dictionary] = []
	var assets: Array[Dictionary] = []
	var rooms: Array[Dictionary] = []
	var unique_targets := {}
	for room in staged_rooms:
		var room_root := String(room.get("room_root", ""))
		var final_manifest := String(room.get("final_manifest_path", ""))
		var staged_manifest := String(room.get("staged_manifest_path", ""))
		if (
			not _path_belongs_to(final_manifest, rooms_root)
			or unique_targets.has(final_manifest)
		):
			return _failure("manifest target is invalid or duplicated")
		unique_targets[final_manifest] = true
		var manifest_hash := FileAccess.get_sha256(staged_manifest)
		if manifest_hash.length() != 64:
			return _failure("staged manifest digest could not be read")
		var had_previous := FileAccess.file_exists(final_manifest)
		var previous_hash := (
			FileAccess.get_sha256(final_manifest) if had_previous else ""
		)
		if had_previous and previous_hash.length() != 64:
			return _failure("previous manifest digest could not be read")
		manifests.append({
			"final": final_manifest,
			"temp": "%s.%s.tmp" % [final_manifest, run_id],
			"backup": "%s.%s.backup" % [final_manifest, run_id],
			"staged": staged_manifest,
			"new_sha256": manifest_hash,
			"had_previous": had_previous,
			"previous_sha256": previous_hash,
		})
		var referenced_assets: Array[String] = []
		for asset_value: Variant in room.get("assets", []) as Array:
			var asset := asset_value as Dictionary
			var final_asset := String(asset.get("final_path", ""))
			var expected_hash := String(asset.get("sha256", ""))
			if (
				not _path_belongs_to(final_asset, room_root)
				or expected_hash.length() != 64
				or unique_targets.has(final_asset)
			):
				return _failure("generated texture target is invalid")
			unique_targets[final_asset] = true
			assets.append({
				"final": final_asset,
				"temp": "%s.%s.tmp" % [final_asset, run_id],
				"staged": String(asset.get("staged_path", "")),
				"sha256": expected_hash,
				"created": not FileAccess.file_exists(final_asset),
			})
			referenced_assets.append(final_asset)
		rooms.append({
			"runtime_root": room_root.path_join(RUNTIME_DIRECTORY),
			"referenced_assets": referenced_assets,
		})
	return {
		"ok": true,
		"plan": {
			"rooms_root": rooms_root,
			"manifests": manifests,
			"assets": assets,
			"rooms": rooms,
		},
	}


func _publish_assets(plan: Dictionary) -> Dictionary:
	for room_value: Variant in plan.get("rooms", []) as Array:
		var room := room_value as Dictionary
		if not _files.make_directory(
			String(room.get("runtime_root", "")),
			"runtime_directory_create",
		):
			return _operation_failure("runtime output directory could not be created")
	for asset_value: Variant in plan.get("assets", []) as Array:
		var asset := asset_value as Dictionary
		var final_path := String(asset.get("final", ""))
		var expected_hash := String(asset.get("sha256", ""))
		if FileAccess.file_exists(final_path):
			if FileAccess.get_sha256(final_path) != expected_hash:
				return _operation_failure("content-addressed texture digest collision")
			continue
		var temp_path := String(asset.get("temp", ""))
		if not _files.copy_file(
			String(asset.get("staged", "")),
			temp_path,
			"asset_copy",
		):
			return _operation_failure("generated texture could not be prepared")
		if FileAccess.get_sha256(temp_path) != expected_hash:
			return _operation_failure("prepared texture digest does not match")
		if not _files.rename_file(temp_path, final_path, "asset_commit_rename"):
			return _operation_failure("generated texture could not be committed")
	return {"ok": true}


func _publish_manifests(plan: Dictionary) -> Dictionary:
	for manifest_value: Variant in plan.get("manifests", []) as Array:
		var manifest := manifest_value as Dictionary
		if not _files.copy_file(
			String(manifest.get("staged", "")),
			String(manifest.get("temp", "")),
			"manifest_copy",
		):
			return _operation_failure("generated manifest could not be prepared")
		if FileAccess.get_sha256(String(manifest.get("temp", ""))) != String(
			manifest.get("new_sha256", ""),
		):
			return _operation_failure("prepared manifest digest does not match")
	for manifest_value: Variant in plan.get("manifests", []) as Array:
		var manifest := manifest_value as Dictionary
		if bool(manifest.get("had_previous")) and not _files.rename_file(
			String(manifest.get("final", "")),
			String(manifest.get("backup", "")),
			"backup_rename",
		):
			return _operation_failure("previous manifest could not be backed up")
		if not _files.rename_file(
			String(manifest.get("temp", "")),
			String(manifest.get("final", "")),
			"manifest_commit_rename",
		):
			return _operation_failure("generated manifest could not be committed")
	return {"ok": true}


func _roll_back(plan: Dictionary, journal_path: String) -> Dictionary:
	var manifests := plan.get("manifests", []) as Array
	for index in range(manifests.size() - 1, -1, -1):
		var restored := _restore_manifest(manifests[index] as Dictionary)
		if restored.get("ok") != true:
			return restored
	if not _verify_previous_manifests(manifests):
		return _failure("restored manifests do not match the previous version")
	for asset_value: Variant in plan.get("assets", []) as Array:
		var asset := asset_value as Dictionary
		if not _files.remove_file(String(asset.get("temp", "")), "asset_temp_remove"):
			return _operation_failure("prepared texture could not be removed")
		if bool(asset.get("created")):
			var final_path := String(asset.get("final", ""))
			if not _files.remove_file(final_path, "created_asset_remove"):
				return _operation_failure("uncommitted texture could not be removed")
			if not _files.remove_file(final_path + ".import", "created_import_remove"):
				return _operation_failure("uncommitted texture import could not be removed")
	if not _files.remove_file(journal_path, "journal_delete"):
		return _operation_failure("completed rollback journal could not be removed")
	return {"ok": true, "committed": false}


func _restore_manifest(manifest: Dictionary) -> Dictionary:
	var final_path := String(manifest.get("final", ""))
	var backup_path := String(manifest.get("backup", ""))
	var temp_path := String(manifest.get("temp", ""))
	var had_previous := bool(manifest.get("had_previous"))
	if FileAccess.file_exists(backup_path):
		if FileAccess.get_sha256(backup_path) != String(
			manifest.get("previous_sha256", ""),
		):
			return _failure("manifest backup digest does not match")
		if not _files.remove_file(final_path, "rollback_remove"):
			return _operation_failure("new manifest could not be removed during rollback")
		if not _files.rename_file(
			backup_path,
			final_path,
			"backup_restore_rename",
		):
			return _operation_failure("previous manifest could not be restored")
	elif had_previous:
		if (
			not FileAccess.file_exists(final_path)
			or FileAccess.get_sha256(final_path)
			!= String(manifest.get("previous_sha256", ""))
		):
			return _failure("previous manifest and its backup are both unavailable")
	elif FileAccess.file_exists(final_path):
		if FileAccess.get_sha256(final_path) != String(manifest.get("new_sha256", "")):
			return _failure("unexpected manifest blocks rollback")
		if not _files.remove_file(final_path, "rollback_remove"):
			return _operation_failure("new manifest could not be removed during rollback")
	if not _files.remove_file(temp_path, "manifest_temp_remove"):
		return _operation_failure("prepared manifest could not be removed")
	return {"ok": true}


func _roll_forward(plan: Dictionary, journal_path: String) -> Dictionary:
	if not _verify_committed_files(plan):
		return _failure("committed manifests or textures failed digest verification")
	for manifest_value: Variant in plan.get("manifests", []) as Array:
		var manifest := manifest_value as Dictionary
		if not _files.remove_file(
			String(manifest.get("temp", "")),
			"manifest_temp_remove",
		):
			return _operation_failure("prepared manifest could not be removed")
		if not _files.remove_file(
			String(manifest.get("backup", "")),
			"backup_delete",
		):
			return _operation_failure("committed manifest backup could not be removed")
	for room_value: Variant in plan.get("rooms", []) as Array:
		var cleanup := _remove_unreferenced_resources(room_value as Dictionary)
		if cleanup.get("ok") != true:
			return cleanup
	if not _files.remove_file(journal_path, "journal_delete"):
		return _operation_failure("completed commit journal could not be removed")
	return {"ok": true, "committed": true}


func _verify_previous_manifests(manifests: Array) -> bool:
	for manifest_value: Variant in manifests:
		var manifest := manifest_value as Dictionary
		var final_path := String(manifest.get("final", ""))
		if bool(manifest.get("had_previous")):
			if (
				not FileAccess.file_exists(final_path)
				or FileAccess.get_sha256(final_path)
				!= String(manifest.get("previous_sha256", ""))
			):
				return false
			if not _manifest_textures_are_valid(final_path):
				return false
		elif FileAccess.file_exists(final_path):
			return false
	return true


func _verify_committed_files(plan: Dictionary) -> bool:
	var expected_assets := {}
	for asset_value: Variant in plan.get("assets", []) as Array:
		var asset := asset_value as Dictionary
		var asset_path := String(asset.get("final", ""))
		expected_assets[asset_path] = String(asset.get("sha256", ""))
	var manifest_assets := {}
	for manifest_value: Variant in plan.get("manifests", []) as Array:
		var manifest := manifest_value as Dictionary
		var final_path := String(manifest.get("final", ""))
		if (
			not FileAccess.file_exists(final_path)
			or FileAccess.get_sha256(final_path)
			!= String(manifest.get("new_sha256", ""))
		):
			return false
		var manifest_asset_result := _manifest_assets(final_path)
		if manifest_asset_result.get("ok") != true:
			return false
		for asset_value: Variant in manifest_asset_result.get("assets", []) as Array:
			var asset := asset_value as Dictionary
			var asset_path := String(asset.get("path", ""))
			var asset_hash := String(asset.get("sha256", ""))
			if expected_assets.get(asset_path) != asset_hash:
				return false
			manifest_assets[asset_path] = asset_hash
	for asset_value: Variant in plan.get("assets", []) as Array:
		var asset := asset_value as Dictionary
		var final_path := String(asset.get("final", ""))
		if (
			not FileAccess.file_exists(final_path)
			or FileAccess.get_sha256(final_path) != String(asset.get("sha256", ""))
		):
			return false
	return manifest_assets == expected_assets


func _manifest_textures_are_valid(path: String) -> bool:
	return _manifest_assets(path).get("ok") == true


func _manifest_assets(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is not Dictionary:
		return {"ok": false}
	var segments_value: Variant = (parsed as Dictionary).get("segments")
	if segments_value is not Array or (segments_value as Array).is_empty():
		return {"ok": false}
	var assets: Array[Dictionary] = []
	for segment_value: Variant in segments_value as Array:
		if segment_value is not Dictionary:
			return {"ok": false}
		var segment := segment_value as Dictionary
		var texture_path := String(segment.get("foreground_texture_path", ""))
		var texture_hash := String(segment.get("foreground_texture_sha256", ""))
		if (
			texture_path.is_empty()
			or not _valid_sha256(texture_hash)
			or not FileAccess.file_exists(texture_path)
			or FileAccess.get_sha256(texture_path) != texture_hash
		):
			return {"ok": false}
		assets.append({"path": texture_path, "sha256": texture_hash})
	return {"ok": true, "assets": assets}


func _remove_unreferenced_resources(room: Dictionary) -> Dictionary:
	var referenced := {}
	for path_value: Variant in room.get("referenced_assets", []) as Array:
		referenced[String(path_value)] = true
	var runtime_root := String(room.get("runtime_root", ""))
	var directory := DirAccess.open(runtime_root)
	if directory == null:
		return _failure("runtime output directory could not be opened")
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir():
			var path := runtime_root.path_join(file_name)
			var png_path := path.trim_suffix(".import")
			if (
				(file_name.ends_with(".png") or file_name.ends_with(".png.import"))
				and not referenced.has(png_path)
				and not _files.remove_file(path, "unreferenced_asset_remove")
			):
				directory.list_dir_end()
				return _operation_failure("unreferenced texture could not be removed")
		file_name = directory.get_next()
	directory.list_dir_end()
	return {"ok": true}


func _read_journal(path: String, expected_rooms_root: String) -> Dictionary:
	var lines := FileAccess.get_file_as_string(path).split("\n", false)
	if lines.is_empty():
		return _failure("publish journal is empty")
	var begin_value: Variant = _parse_journal_record(lines[0])
	if begin_value is not Dictionary:
		return _failure("publish journal begin record is invalid")
	var begin := begin_value as Dictionary
	if begin.get("event") != "begin" or int(begin.get("version", 0)) != JOURNAL_VERSION:
		return _failure("publish journal version is invalid")
	var plan_value: Variant = begin.get("plan")
	if plan_value is not Dictionary:
		return _failure("publish journal plan is invalid")
	var plan := plan_value as Dictionary
	if not _valid_recovery_plan(plan, expected_rooms_root):
		return _failure("publish journal contains unsafe paths or digests")
	var committed := false
	for index in range(1, lines.size()):
		var event_value: Variant = _parse_journal_record(lines[index])
		if event_value is not Dictionary:
			# begin 记录通过临时文件重命名发布；只有追加的 commit 尾行可能
			# 在进程中断时半写。把截断尾行视为未提交即可安全回滚。
			if index == lines.size() - 1 and not committed:
				break
			return _failure("publish journal record is invalid")
		if (event_value as Dictionary).get("event") == "commit":
			committed = true
		else:
			return _failure("publish journal event is invalid")
	return {"ok": true, "plan": plan, "committed": committed}


func _parse_journal_record(text: String) -> Variant:
	var parser := JSON.new()
	return parser.data if parser.parse(text) == OK else null


func _valid_recovery_plan(plan: Dictionary, rooms_root: String) -> bool:
	if String(plan.get("rooms_root", "")) != rooms_root:
		return false
	var manifests_value: Variant = plan.get("manifests")
	var assets_value: Variant = plan.get("assets")
	var rooms_value: Variant = plan.get("rooms")
	if (
		manifests_value is not Array
		or (manifests_value as Array).is_empty()
		or assets_value is not Array
		or (assets_value as Array).is_empty()
		or rooms_value is not Array
		or (rooms_value as Array).is_empty()
	):
		return false
	var unique_paths := {}
	for manifest_value: Variant in manifests_value as Array:
		if manifest_value is not Dictionary:
			return false
		var manifest := manifest_value as Dictionary
		var final_path := String(manifest.get("final", ""))
		var temp_path := String(manifest.get("temp", ""))
		var backup_path := String(manifest.get("backup", ""))
		if (
			not _valid_manifest_target(final_path, rooms_root)
			or not temp_path.begins_with(final_path + ".")
			or not temp_path.ends_with(".tmp")
			or not backup_path.begins_with(final_path + ".")
			or not backup_path.ends_with(".backup")
			or not _safe_path(temp_path)
			or not _safe_path(backup_path)
			or not _valid_sha256(String(manifest.get("new_sha256", "")))
			or (
				bool(manifest.get("had_previous"))
				and not _valid_sha256(String(manifest.get("previous_sha256", "")))
			)
			or unique_paths.has(final_path)
		):
			return false
		unique_paths[final_path] = true
	for asset_value: Variant in assets_value as Array:
		if asset_value is not Dictionary:
			return false
		var asset := asset_value as Dictionary
		var final_path := String(asset.get("final", ""))
		var temp_path := String(asset.get("temp", ""))
		if (
			not _valid_asset_target(final_path, rooms_root)
			or not temp_path.begins_with(final_path + ".")
			or not temp_path.ends_with(".tmp")
			or not _safe_path(temp_path)
			or not _valid_sha256(String(asset.get("sha256", "")))
			or unique_paths.has(final_path)
		):
			return false
		unique_paths[final_path] = true
	for room_value: Variant in rooms_value as Array:
		if room_value is not Dictionary:
			return false
		var room := room_value as Dictionary
		var runtime_root := String(room.get("runtime_root", ""))
		var referenced_value: Variant = room.get("referenced_assets")
		if (
			not _valid_runtime_root(runtime_root, rooms_root)
			or runtime_root.get_file() != RUNTIME_DIRECTORY
			or referenced_value is not Array
		):
			return false
		for path_value: Variant in referenced_value as Array:
			if not _valid_asset_target(String(path_value), rooms_root):
				return false
	return true


func _valid_manifest_target(path: String, rooms_root: String) -> bool:
	return (
		_safe_path(path)
		and path.get_file() == "wall_occlusion_runtime.json"
		and path.get_base_dir().get_base_dir() == rooms_root
	)


func _valid_asset_target(path: String, rooms_root: String) -> bool:
	return (
		_safe_path(path)
		and path.ends_with(".png")
		and _valid_runtime_root(path.get_base_dir(), rooms_root)
	)


func _valid_runtime_root(path: String, rooms_root: String) -> bool:
	return (
		_safe_path(path)
		and path.get_file() == RUNTIME_DIRECTORY
		and path.get_base_dir().get_base_dir() == rooms_root
	)


func _safe_path(path: String) -> bool:
	return not path.is_empty() and path == path.simplify_path()


func _valid_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for character in value:
		if character not in "0123456789abcdef":
			return false
	return true


func _journal_path(rooms_root: String) -> String:
	return rooms_root.path_join(".wall_occlusion_publish.journal")


func _path_belongs_to(path: String, root: String) -> bool:
	return not path.is_empty() and path.begins_with(root.trim_suffix("/") + "/")


func _operation_failure(message: String) -> Dictionary:
	var result := _failure(message)
	result["interrupted"] = _files.fault_was_injected()
	result["recovery_pending"] = true
	return result


func _pending_failure(message: String) -> Dictionary:
	var result := _failure(message)
	result["recovery_pending"] = true
	result["interrupted"] = _files.fault_was_injected()
	return result


func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
