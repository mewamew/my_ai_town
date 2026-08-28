class_name InteriorOcclusionController
extends Node

var _active_room: InteriorRoom
var _player_subject: Node2D
var _resident_subjects_by_id: Dictionary = {}
var _resident_presentation: Node
var _pending_upserts: Dictionary = {}
var _pending_removals: Dictionary = {}


func _ready() -> void:
	set_process(true)


func _process(_delta: float) -> void:
	process_pending()


func bind_player(subject: Node2D) -> void:
	if is_instance_valid(_player_subject) and _player_subject != subject:
		_queue_subject_removal(_player_subject.get_instance_id())
	_player_subject = subject
	_queue_subject_upsert(subject)


func bind_resident_presentation(presentation: Node) -> bool:
	_disconnect_resident_presentation()
	if (
		not is_instance_valid(presentation)
		or not presentation.has_signal("occlusion_subjects_changed")
		or not presentation.has_signal("occlusion_subject_added")
		or not presentation.has_signal("occlusion_subject_removed")
		or not presentation.has_signal("occlusion_subject_state_changed")
		or not presentation.has_method("get_active_occlusion_subjects")
	):
		return false
	_resident_presentation = presentation
	presentation.connect(
		"occlusion_subjects_changed",
		_on_resident_subjects_changed,
	)
	presentation.connect("occlusion_subject_added", _on_resident_subject_added)
	presentation.connect("occlusion_subject_removed", _on_resident_subject_removed)
	presentation.connect(
		"occlusion_subject_state_changed",
		mark_subject_dirty,
	)
	_on_resident_subjects_changed(
		presentation.get_active_occlusion_subjects() as Array[Node2D],
	)
	return true


func set_active_room(room: InteriorRoom) -> void:
	if _active_room == room:
		return
	if is_instance_valid(_active_room):
		_active_room.clear_wall_occlusion_subjects()
	_active_room = room
	_pending_upserts.clear()
	_pending_removals.clear()
	_queue_subject_upsert(_player_subject)
	for subject_value: Variant in _resident_subjects_by_id.values():
		_queue_subject_upsert(subject_value as Node2D)


func mark_subject_dirty(subject: Node2D) -> void:
	if not is_instance_valid(subject):
		return
	var subject_id := subject.get_instance_id()
	if subject == _player_subject or _resident_subjects_by_id.has(subject_id):
		_queue_subject_upsert(subject)


func process_pending() -> bool:
	if _pending_upserts.is_empty() and _pending_removals.is_empty():
		return false
	if not is_instance_valid(_active_room) or not _active_room.visible:
		_pending_upserts.clear()
		_pending_removals.clear()
		return false
	var removals := _pending_removals.keys()
	var upserts := _pending_upserts.values()
	_pending_removals.clear()
	_pending_upserts.clear()
	for subject_id_value: Variant in removals:
		_active_room.remove_wall_occlusion_subject(int(subject_id_value))
	for subject_value: Variant in upserts:
		var subject := subject_value as Node2D
		if is_instance_valid(subject):
			_active_room.upsert_wall_occlusion_subject(subject)
	return true


func has_pending_refresh() -> bool:
	return not _pending_upserts.is_empty() or not _pending_removals.is_empty()


func _on_resident_subjects_changed(subjects: Array[Node2D]) -> void:
	var next_subjects_by_id: Dictionary = {}
	for subject in subjects:
		if not is_instance_valid(subject):
			continue
		var subject_id := subject.get_instance_id()
		next_subjects_by_id[subject_id] = subject
		if not _resident_subjects_by_id.has(subject_id):
			_queue_subject_upsert(subject)
	for subject_id_value: Variant in _resident_subjects_by_id.keys():
		var subject_id := int(subject_id_value)
		if not next_subjects_by_id.has(subject_id):
			_queue_subject_removal(subject_id)
	_resident_subjects_by_id = next_subjects_by_id


func _on_resident_subject_added(subject: Node2D) -> void:
	if not is_instance_valid(subject):
		return
	var subject_id := subject.get_instance_id()
	_resident_subjects_by_id[subject_id] = subject
	_queue_subject_upsert(subject)


func _on_resident_subject_removed(subject_id: int) -> void:
	_resident_subjects_by_id.erase(subject_id)
	_queue_subject_removal(subject_id)


func _queue_subject_upsert(subject: Node2D) -> void:
	if not is_instance_valid(subject):
		return
	var subject_id := subject.get_instance_id()
	_pending_removals.erase(subject_id)
	_pending_upserts[subject_id] = subject


func _queue_subject_removal(subject_id: int) -> void:
	_pending_upserts.erase(subject_id)
	_pending_removals[subject_id] = true


func _disconnect_resident_presentation() -> void:
	if not is_instance_valid(_resident_presentation):
		_resident_presentation = null
		for subject_id_value: Variant in _resident_subjects_by_id.keys():
			_queue_subject_removal(int(subject_id_value))
		_resident_subjects_by_id.clear()
		return
	for signal_name: StringName in [
		&"occlusion_subjects_changed",
		&"occlusion_subject_added",
		&"occlusion_subject_removed",
		&"occlusion_subject_state_changed",
	]:
		var callable: Callable = mark_subject_dirty
		match signal_name:
			&"occlusion_subjects_changed":
				callable = _on_resident_subjects_changed
			&"occlusion_subject_added":
				callable = _on_resident_subject_added
			&"occlusion_subject_removed":
				callable = _on_resident_subject_removed
		if _resident_presentation.is_connected(signal_name, callable):
			_resident_presentation.disconnect(signal_name, callable)
	_resident_presentation = null
	for subject_id_value: Variant in _resident_subjects_by_id.keys():
		_queue_subject_removal(int(subject_id_value))
	_resident_subjects_by_id.clear()
