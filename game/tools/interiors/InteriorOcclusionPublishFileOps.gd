extends RefCounted

var _fault_point := ""
var _fault_occurrence := 1
var _point_calls: Dictionary[String, int] = {}
var _fault_was_injected := false


func configure_fault(point: String, occurrence: int = 1) -> void:
	_fault_point = point
	_fault_occurrence = maxi(1, occurrence)
	_point_calls.clear()
	_fault_was_injected = false


func fault_was_injected() -> bool:
	return _fault_was_injected


func make_directory(path: String, point: String) -> bool:
	if _inject(point):
		return false
	return DirAccess.make_dir_recursive_absolute(_absolute(path)) == OK


func copy_file(source: String, destination: String, point: String) -> bool:
	if _inject(point):
		return false
	return DirAccess.copy_absolute(_absolute(source), _absolute(destination)) == OK


func rename_file(source: String, destination: String, point: String) -> bool:
	if _inject(point):
		return false
	if DirAccess.rename_absolute(_absolute(source), _absolute(destination)) != OK:
		return false
	return not _inject(point + "_after")


func remove_file(path: String, point: String) -> bool:
	if path.is_empty() or not FileAccess.file_exists(path):
		return true
	if _inject(point):
		return false
	return DirAccess.remove_absolute(_absolute(path)) == OK


func begin_journal(path: String, begin_record: Dictionary) -> bool:
	if _inject("journal_record"):
		return false
	var temp_path := path + ".begin.tmp"
	if not remove_file(temp_path, "journal_temp_remove"):
		return false
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_line(JSON.stringify(begin_record))
	file.flush()
	var stored := file.get_error() == OK
	file.close()
	if not stored:
		return false
	return rename_file(temp_path, path, "journal_begin_rename")


func append_journal(path: String, record: Dictionary) -> bool:
	if _inject("journal_record"):
		return false
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		return false
	file.seek_end()
	if _inject("journal_commit_partial"):
		file.store_string('{"event":')
		file.flush()
		file.close()
		return false
	file.store_line(JSON.stringify(record))
	file.flush()
	var stored := file.get_error() == OK
	file.close()
	return stored


func _inject(point: String) -> bool:
	var calls: int = int(_point_calls.get(point, 0)) + 1
	_point_calls[point] = calls
	if point != _fault_point or calls != _fault_occurrence:
		return false
	_fault_was_injected = true
	return true


func _absolute(path: String) -> String:
	return ProjectSettings.globalize_path(path)
