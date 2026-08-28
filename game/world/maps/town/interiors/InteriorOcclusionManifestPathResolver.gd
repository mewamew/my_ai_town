class_name InteriorOcclusionManifestPathResolver
extends RefCounted

const JOURNAL_NAME := ".wall_occlusion_publish.journal"


static func resolve(manifest_path: String, occlusion_path: String) -> Dictionary:
	var rooms_root := occlusion_path.get_base_dir().get_base_dir()
	var journal_path := rooms_root.path_join(JOURNAL_NAME)
	if not FileAccess.file_exists(journal_path):
		return {"ok": true, "path": manifest_path, "transaction": false}
	var lines := FileAccess.get_file_as_string(journal_path).split("\n", false)
	if lines.is_empty():
		return _failure("publish journal is empty")
	var begin_value: Variant = _parse_record(lines[0])
	if begin_value is not Dictionary:
		return _failure("publish journal begin record is invalid")
	var begin := begin_value as Dictionary
	var plan_value: Variant = begin.get("plan")
	if begin.get("event") != "begin" or plan_value is not Dictionary:
		return _failure("publish journal begin record is invalid")
	var plan := plan_value as Dictionary
	if String(plan.get("rooms_root", "")) != rooms_root:
		return _failure("publish journal root does not match the room")
	var manifest_record := _manifest_record(plan, manifest_path)
	if manifest_record.is_empty():
		return _failure("publish journal does not contain the room manifest")
	var committed := _has_complete_commit(lines)
	if committed:
		return _verified_path(
			String(manifest_record.get("final", "")),
			String(manifest_record.get("new_sha256", "")),
			true,
		)
	if not bool(manifest_record.get("had_previous")):
		return _failure("no previous manifest exists during an incomplete publish")
	var previous_hash := String(manifest_record.get("previous_sha256", ""))
	var backup_path := String(manifest_record.get("backup", ""))
	if _path_matches(backup_path, previous_hash):
		return {"ok": true, "path": backup_path, "transaction": true}
	return _verified_path(
		String(manifest_record.get("final", "")),
		previous_hash,
		true,
	)


static func _manifest_record(plan: Dictionary, manifest_path: String) -> Dictionary:
	var matches := 0
	var found: Dictionary = {}
	var values: Variant = plan.get("manifests")
	if values is not Array:
		return found
	for value: Variant in values as Array:
		if value is not Dictionary:
			return {}
		var record := value as Dictionary
		if String(record.get("final", "")) == manifest_path:
			matches += 1
			found = record
	return found if matches == 1 else {}


static func _has_complete_commit(lines: PackedStringArray) -> bool:
	for index in range(1, lines.size()):
		var value: Variant = _parse_record(lines[index])
		if value is Dictionary and (value as Dictionary).get("event") == "commit":
			return true
		# A truncated tail is uncommitted and must use the previous version.
		if index == lines.size() - 1:
			return false
		return false
	return false


static func _verified_path(path: String, digest: String, transaction: bool) -> Dictionary:
	if not _path_matches(path, digest):
		return _failure("transaction manifest is missing or has the wrong digest")
	return {"ok": true, "path": path, "transaction": transaction}


static func _path_matches(path: String, digest: String) -> bool:
	return (
		not path.is_empty()
		and digest.length() == 64
		and FileAccess.file_exists(path)
		and FileAccess.get_sha256(path) == digest
	)


static func _parse_record(text: String) -> Variant:
	var parser := JSON.new()
	return parser.data if parser.parse(text) == OK else null


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
