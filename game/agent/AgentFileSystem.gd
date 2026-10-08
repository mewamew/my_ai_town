extends RefCounted


# One-way, process-local opt-in for isolated tests. No environment switch and no
# production fallback after enrollment. Only descendants of owned/ may be moved.
static var _retention_root := ""
static var _retention_sequence := 0
static var _retention_incomplete: Dictionary = {}


static func configure_test_retention(root: String) -> Error:
	if not _retention_root.is_empty():
		return ERR_ALREADY_IN_USE
	if (
		not root.is_absolute_path() or root.contains("://")
		or root != root.simplify_path() or root.contains("\\")
		or not root.get_file().begins_with("gametest-retention-")
		or not _link_free(root)
	):
		return ERR_INVALID_PARAMETER
	var user_root := ProjectSettings.globalize_path("user://").trim_suffix("/").to_lower()
	var candidate := root.to_lower()
	if candidate == user_root or candidate.begins_with(user_root + "/"):
		return ERR_INVALID_PARAMETER
	for child: String in ["owned", "retained"]:
		if not DirAccess.dir_exists_absolute(root.path_join(child)):
			return ERR_DOES_NOT_EXIST
		if not _link_free(root.path_join(child)):
			return ERR_INVALID_PARAMETER
	var journal := root.path_join("retention.jsonl")
	if not FileAccess.file_exists(journal) or not _link_free(journal):
		return ERR_INVALID_PARAMETER
	var file := FileAccess.open(journal, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	if file.get_length() != 0:
		return ERR_ALREADY_IN_USE
	_retention_root = root
	return OK


static func test_retention_enabled() -> bool:
	return not _retention_root.is_empty()


static func test_retention_path_allowed(path: String) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	return (
		test_retention_enabled()
		and absolute == absolute.simplify_path() and not absolute.contains("\\")
		and absolute.begins_with(_retention_root.path_join("owned") + "/")
		and _link_free(absolute)
	)


static func _link_free(path: String) -> bool:
	var current := path
	while not current.is_empty() and current != current.get_base_dir():
		var parent := DirAccess.open(current.get_base_dir())
		if parent == null:
			if FileAccess.file_exists(current.get_base_dir()):
				return false
			current = current.get_base_dir()
			continue
		if parent.is_link(current):
			return false
		current = current.get_base_dir()
	return true


static func _inventory(path: String, entries: Dictionary, relative := ".", depth := 0) -> Error:
	if depth > 32 or entries.size() > 10000 or not _link_free(path):
		return ERR_INVALID_PARAMETER
	if FileAccess.file_exists(path):
		var digest := FileAccess.get_sha256(path)
		if digest.length() != 64:
			return ERR_FILE_CANT_READ
		entries[relative] = {"type": "file", "sha256": digest}
		return OK
	var directory := DirAccess.open(path)
	if directory == null:
		return DirAccess.get_open_error()
	entries[relative] = {"type": "directory"}
	directory.include_hidden = true
	var error := directory.list_dir_begin()
	if error != OK:
		return error
	var name := directory.get_next()
	while not name.is_empty():
		if name != "." and name != "..":
			error = _inventory(path.path_join(name), entries, relative.path_join(name), depth + 1)
			if error != OK:
				directory.list_dir_end()
				return error
		name = directory.get_next()
	directory.list_dir_end()
	return OK


static func _append_retention(record: Dictionary) -> Error:
	var journal := _retention_root.path_join("retention.jsonl")
	if not _link_free(journal) or not FileAccess.file_exists(journal):
		return ERR_FILE_CANT_WRITE
	var file := FileAccess.open(journal, FileAccess.READ_WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.seek_end()
	file.store_line(JSON.stringify(record))
	file.flush()
	return file.get_error()


static func retain_for_test(path: String) -> Error:
	if not test_retention_enabled():
		return ERR_UNCONFIGURED
	var absolute := ProjectSettings.globalize_path(path)
	if (
		not test_retention_path_allowed(path)
		or not _link_free(_retention_root.path_join("retained"))
	):
		return ERR_INVALID_PARAMETER
	if _retention_incomplete.has(absolute):
		return ERR_FILE_CANT_WRITE
	if not FileAccess.file_exists(absolute) and not DirAccess.dir_exists_absolute(absolute):
		return OK
	_retention_sequence += 1
	var target := _retention_root.path_join("retained/%08d" % _retention_sequence)
	if FileAccess.file_exists(target) or DirAccess.dir_exists_absolute(target):
		return ERR_ALREADY_EXISTS
	var entries := {}
	var error := _inventory(absolute, entries)
	if error != OK:
		return error
	var record := {"retentionId": _retention_sequence, "ownerPid": OS.get_process_id(),
		"source": absolute, "target": target, "entries": entries,
		"status": "prepared", "unixTime": Time.get_unix_time_from_system()}
	error = _append_retention(record)
	if error != OK:
		return error
	error = DirAccess.rename_absolute(absolute, target)
	record["moveError"] = int(error)
	if error != OK:
		record["status"] = "move_failed"
		_append_retention(record)
		return error
	# A failed post-move check must never turn into success on a subsequent call
	# merely because the original path has disappeared.
	_retention_incomplete[absolute] = target
	var retained := {}
	error = _inventory(target, retained)
	if error == OK and retained != entries:
		error = ERR_FILE_CORRUPT
	record["status"] = "retained" if error == OK else "verification_failed"
	record["verifyError"] = int(error)
	var journal_error := _append_retention(record)
	if error != OK or journal_error != OK:
		return error if error != OK else journal_error
	_retention_incomplete.erase(absolute)
	return OK


static func remove_tree(path: String) -> Error:
	if test_retention_enabled():
		return retain_for_test(path)
	var absolute_path := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute_path):
		return OK
	var directory := DirAccess.open(absolute_path)
	if directory == null:
		return DirAccess.get_open_error()
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		if name != "." and name != "..":
			var child_path := "%s/%s" % [path.trim_suffix("/"), name]
			var remove_error := OK
			if directory.current_is_dir():
				remove_error = remove_tree(child_path)
			else:
				remove_error = DirAccess.remove_absolute(
					ProjectSettings.globalize_path(child_path),
				)
			if remove_error != OK:
				directory.list_dir_end()
				return remove_error
		name = directory.get_next()
	directory.list_dir_end()
	# Windows can keep the directory locked until the DirAccess object itself is
	# released, even after list_dir_end() closes the enumeration.
	directory = null
	return DirAccess.remove_absolute(absolute_path)


static func remove_empty_directory(path: String) -> void:
	# Keep empty test parents too; callers may allocate another runtime under them.
	if test_retention_enabled():
		return
	var absolute_path := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute_path):
		return
	var directory := DirAccess.open(absolute_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var first_entry := directory.get_next()
	directory.list_dir_end()
	directory = null
	if first_entry.is_empty():
		DirAccess.remove_absolute(absolute_path)


static func is_safe_path_segment(value: String) -> bool:
	if value.is_empty() or value.length() > 128:
		return false
	for character in value:
		if not character.to_lower() in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			return false
	return true
