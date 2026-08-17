class_name TownPrivateMessageRuntime
extends RefCounted


const RESTORE_WORK := preload(
	"res://world/runtime/persistence/TownWorldRestoreWork.gd"
)
const MAX_DELIVERED_MESSAGES := 64

var _messages: Dictionary = {}
var _sequence := 0
var _archive_summary: Dictionary = {}
var _reserved_message_id := ""


func _init() -> void:
	reset()


func reset() -> void:
	_messages.clear()
	_sequence = 0
	_archive_summary = RESTORE_WORK.empty_private_message_archive_summary()
	_reserved_message_id = ""


func restore_prepared(prepared: Dictionary) -> void:
	_messages = (
		prepared.get("messagesById", {}) as Dictionary
	).duplicate(true)
	_sequence = int(prepared.get("sequence", 0))
	_archive_summary = (
		prepared.get(
			"archiveSummary",
			RESTORE_WORK.empty_private_message_archive_summary(),
		) as Dictionary
	).duplicate(true)
	_reserved_message_id = ""


func prepare_create(
	sender_id: String,
	recipient_id: String,
	content: String,
	message_kind: String,
	announcement_id: String,
	expires_at_minute: int,
	source_ref: String,
	created_at: int,
	work_tasks: RefCounted,
) -> Dictionary:
	var normalized_content := content.strip_edges()
	var normalized_kind := message_kind.strip_edges()
	var normalized_announcement_id := announcement_id.strip_edges()
	if sender_id.is_empty() or recipient_id.is_empty() or sender_id == recipient_id:
		return _failure(
			"PRIVATE_MESSAGE_PARTICIPANT_INVALID",
			"私人消息必须有两个不同的真实居民",
		)
	if (
		normalized_kind not in ["private", "announcement_notice"]
		or (
			normalized_kind == "announcement_notice"
			and normalized_announcement_id.is_empty()
		)
		or (
			normalized_kind == "private"
			and not normalized_announcement_id.is_empty()
		)
	):
		return _failure(
			"PRIVATE_MESSAGE_KIND_INVALID",
			"正式通知必须携带唯一公告编号",
		)
	if normalized_content.is_empty() or normalized_content.length() > 240:
		return _failure(
			"PRIVATE_MESSAGE_CONTENT_INVALID",
			"私人消息必须是 1 到 240 个字符的文字",
		)
	if expires_at_minute >= 0 and expires_at_minute <= created_at:
		return _failure(
			"PRIVATE_MESSAGE_EXPIRY_INVALID",
			"有时效的消息必须在创建之后到期",
		)
	_sequence += 1
	var message_id := "private-message-%d" % _sequence
	var batch_id := active_unsorted_postal_batch_id(work_tasks)
	if batch_id.is_empty():
		batch_id = "postal-batch-%d-%d" % [created_at / 1440, _sequence]
	_reserved_message_id = message_id
	return {
		"ok": true,
		"errorCode": "",
		"message": {
			"messageId": message_id,
			"senderResidentId": sender_id,
			"recipientResidentId": recipient_id,
			"content": normalized_content,
			"state": "pending",
			"createdAtMinute": created_at,
			"deliveredAtMinute": -1,
			"deliveredByResidentId": "",
			"taskId": "private-message-task:%s" % message_id,
			"batchId": batch_id,
			"messageKind": normalized_kind,
			"announcementId": normalized_announcement_id,
			"expiresAtMinute": expires_at_minute,
			"sourceRef": source_ref.strip_edges(),
		},
	}


func rollback_create(message_id: String) -> void:
	if message_id != _reserved_message_id:
		return
	if message_id == "private-message-%d" % _sequence:
		_sequence = maxi(0, _sequence - 1)
	_reserved_message_id = ""


func commit_created(message: Dictionary) -> void:
	var message_id := String(message.get("messageId", ""))
	if message_id.is_empty():
		return
	_messages[message_id] = message.duplicate(true)
	if message_id == _reserved_message_id:
		_reserved_message_id = ""


func set_message(message_id: String, message: Dictionary) -> void:
	if message_id.is_empty():
		return
	_messages[message_id] = message.duplicate(true)


func remove(message_id: String) -> bool:
	return _messages.erase(message_id)


func has(message_id: String) -> bool:
	return _messages.has(message_id)


func message(message_id: String) -> Dictionary:
	return (
		_messages.get(message_id, {}) as Dictionary
	).duplicate(true)


func sorted_message_ids() -> Array[String]:
	var result: Array[String] = []
	for message_id_value: Variant in _messages:
		result.append(String(message_id_value))
	result.sort()
	return result


func values_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for message_id: String in sorted_message_ids():
		result.append(message(message_id))
	return result


func create_save_snapshot(work_tasks: RefCounted) -> Dictionary:
	compact_delivered(work_tasks)
	return {
		"schemaVersion": 4,
		"sequence": _sequence,
		"messages": values_snapshot(),
		"archiveSummary": _archive_summary.duplicate(true),
	}


func distribution_token(
	source_ref: String,
	context_hint: String,
	absolute_minute: int,
) -> String:
	return "%s|%d|%d|%s" % [
		source_ref.strip_edges(),
		absolute_minute,
		_sequence + 1,
		context_hint.strip_edges(),
	]


func public_message(
	value: Dictionary,
	resident_names_by_id: Dictionary,
) -> Dictionary:
	var sender_id := String(value.get("senderResidentId", ""))
	var recipient_id := String(value.get("recipientResidentId", ""))
	return {
		"message_id": String(value.get("messageId", "")),
		"sender_resident_id": sender_id,
		"sender_name": String(resident_names_by_id.get(sender_id, "")),
		"recipient_resident_id": recipient_id,
		"recipient_name": String(resident_names_by_id.get(recipient_id, "")),
		"content": String(value.get("content", "")),
		"message_kind": String(value.get("messageKind", "private")),
		"announcement_id": String(value.get("announcementId", "")),
		"expires_at_minute": int(value.get("expiresAtMinute", -1)),
		"source_ref": String(value.get("sourceRef", "")),
		"state": String(value.get("state", "")),
		"created_at_minute": int(value.get("createdAtMinute", 0)),
		"delivered_at_minute": int(value.get("deliveredAtMinute", -1)),
		"delivered_by_resident_id": String(
			value.get("deliveredByResidentId", ""),
		),
		"task_id": String(value.get("taskId", "")),
		"batch_id": String(value.get("batchId", "")),
	}


func messages_for_resident(
	resident_id: String,
	resident_names_by_id: Dictionary,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for message_id: String in sorted_message_ids():
		var value := message(message_id)
		if resident_id in [
			String(value.get("senderResidentId", "")),
			String(value.get("recipientResidentId", "")),
			String(value.get("deliveredByResidentId", "")),
		]:
			result.append(public_message(value, resident_names_by_id))
	return result


func find_existing_pending(
	sender_id: String,
	recipient_id: String,
	content: String,
	source_ref: String,
) -> Dictionary:
	for message_id: String in sorted_message_ids():
		var value := message(message_id)
		if String(value.get("senderResidentId", "")).strip_edges() != sender_id:
			continue
		if String(value.get("recipientResidentId", "")).strip_edges() != recipient_id:
			continue
		if String(value.get("content", "")).strip_edges() != content:
			continue
		if String(value.get("state", "")) != "pending":
			continue
		if (
			not source_ref.is_empty()
			and String(value.get("sourceRef", "")).strip_edges() != source_ref
		):
			continue
		return value
	return {}


func active_unsorted_postal_batch_id(work_tasks: RefCounted) -> String:
	for message_id: String in sorted_message_ids():
		var value := message(message_id)
		if String(value.get("state", "")) != "pending":
			continue
		var task := work_tasks.task(String(value.get("taskId", ""))) as Dictionary
		if String(task.get("processStage", "")) == "awaiting_sort":
			return String(value.get("batchId", ""))
	return ""


func messages_in_batch(batch_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Dictionary in values_snapshot():
		if (
			String(value.get("batchId", "")) == batch_id
			and String(value.get("state", "")) == "pending"
		):
			result.append(value)
	return result


func postal_batch_message_count(batch_id: String) -> int:
	return messages_in_batch(batch_id).size()


func pending_expired_ids(absolute_minute: int) -> Array[String]:
	var result: Array[String] = []
	for message_id: String in sorted_message_ids():
		var value := message(message_id)
		if (
			String(value.get("state", "")) == "pending"
			and int(value.get("expiresAtMinute", -1)) >= 0
			and absolute_minute >= int(value.get("expiresAtMinute", -1))
		):
			result.append(message_id)
	return result


func pending_ids_for_source(source_ref: String) -> Array[String]:
	var normalized_source := source_ref.strip_edges()
	var result: Array[String] = []
	if normalized_source.is_empty():
		return result
	for message_id: String in sorted_message_ids():
		var value := message(message_id)
		if (
			String(value.get("state", "")) == "pending"
			and String(value.get("sourceRef", "")) == normalized_source
		):
			result.append(message_id)
	return result


func pending_count_from_sender(sender_id: String) -> int:
	var result := 0
	for value: Dictionary in values_snapshot():
		if (
			String(value.get("senderResidentId", "")) == sender_id
			and String(value.get("state", "")) == "pending"
		):
			result += 1
	return result


func delivery_task_for_talk(
	postal_resident_id: String,
	recipient_id: String,
	spoken_content: String,
	work_tasks: RefCounted,
	resident_can_accept_work_task: Callable,
) -> Dictionary:
	var candidates := _delivery_tasks_for_talk(
		postal_resident_id,
		recipient_id,
		spoken_content,
		work_tasks,
		resident_can_accept_work_task,
	)
	return candidates[0] if not candidates.is_empty() else {}


func complete_delivery(
	postal_resident_id: String,
	recipient_id: String,
	spoken_content: String,
	delivered_at: int,
	work_tasks: RefCounted,
	resident_can_accept_work_task: Callable,
	task_acceptance_occupation_id: Callable,
) -> Dictionary:
	for candidate: Dictionary in _delivery_tasks_for_talk(
		postal_resident_id,
		recipient_id,
		spoken_content,
		work_tasks,
		resident_can_accept_work_task,
	):
		var message_id := String(candidate.get("messageId", ""))
		var value := candidate.get("message", {}) as Dictionary
		var task := candidate.get("task", {}) as Dictionary
		var task_id := String(task.get("taskId", ""))
		if String(task.get("state", "")) in ["open", "waiting"]:
			var acceptance_occupation_id := String(
				task_acceptance_occupation_id.call(
					postal_resident_id,
					task,
				),
			)
			var accepted := work_tasks.accept_task(
				task_id,
				postal_resident_id,
				acceptance_occupation_id,
				int(task.get("revision", 0)),
			) as Dictionary
			if accepted.get("ok") != true:
				continue
			task = accepted.get("task", {}) as Dictionary
		if String(task.get("state", "")) == "accepted":
			var started := work_tasks.start_task(
				task_id,
				postal_resident_id,
				int(task.get("revision", 0)),
			) as Dictionary
			if started.get("ok") != true:
				continue
			task = started.get("task", {}) as Dictionary
		if (
			String(task.get("state", "")) != "in_progress"
			or String(task.get("assignedResidentId", ""))
			!= postal_resident_id
		):
			continue
		var completed := work_tasks.complete_task(
			task_id,
			postal_resident_id,
			int(task.get("revision", 0)),
			"message_delivery",
			{
				"resultRef": "message-delivery:%s" % message_id,
				"facts": {
					"messageId": message_id,
					"senderResidentId": String(
						value.get("senderResidentId", ""),
					),
					"recipientResidentId": recipient_id,
					"deliveredByResidentId": postal_resident_id,
					"deliveredAtMinute": delivered_at,
					"originalContentDelivered": true,
				},
			},
		) as Dictionary
		if completed.get("ok") != true:
			continue
		value = mark_delivered(
			message_id,
			delivered_at,
			postal_resident_id,
		)
		return {
			"ok": true,
			"messageId": message_id,
			"message": value,
		}
	return {"ok": false}


func _delivery_tasks_for_talk(
	postal_resident_id: String,
	recipient_id: String,
	spoken_content: String,
	work_tasks: RefCounted,
	resident_can_accept_work_task: Callable,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var normalized_content := spoken_content.strip_edges()
	if normalized_content.is_empty():
		return result
	for message_id: String in sorted_message_ids():
		var value := message(message_id)
		if (
			String(value.get("state", "")) != "pending"
			or String(value.get("recipientResidentId", "")) != recipient_id
			or String(value.get("content", "")).strip_edges()
			!= normalized_content
		):
			continue
		var task := work_tasks.task(String(value.get("taskId", ""))) as Dictionary
		var assigned_resident_id := String(task.get("assignedResidentId", ""))
		if (
			task.is_empty()
			or not bool(
				resident_can_accept_work_task.call(
					postal_resident_id,
					task,
				)
			)
			or String(task.get("processStage", "")) != "out_for_delivery"
			or String(task.get("state", "")) in [
				"completed",
				"failed",
				"cancelled",
			]
			or (
				not assigned_resident_id.is_empty()
				and assigned_resident_id != postal_resident_id
			)
		):
			continue
		result.append({
			"messageId": message_id,
			"message": value,
			"task": task.duplicate(true),
		})
	return result


func waiting_message_count() -> int:
	var result := 0
	for value: Dictionary in values_snapshot():
		if String(value.get("state", "")) in ["pending", "sorted", "prepared"]:
			result += 1
	return result


func mark_delivered(
	message_id: String,
	delivered_at: int,
	delivered_by_resident_id: String,
) -> Dictionary:
	var value := message(message_id)
	if value.is_empty():
		return {}
	value["state"] = "delivered"
	value["deliveredAtMinute"] = delivered_at
	value["deliveredByResidentId"] = delivered_by_resident_id
	set_message(message_id, value)
	return value


func compact_delivered(work_tasks: RefCounted) -> void:
	var delivered: Array[Dictionary] = []
	for value: Dictionary in values_snapshot():
		if String(value.get("state", "")) == "delivered":
			delivered.append(value)
	delivered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("deliveredAtMinute", -1)) != int(b.get("deliveredAtMinute", -1)):
			return int(a.get("deliveredAtMinute", -1)) > int(b.get("deliveredAtMinute", -1))
		return String(a.get("messageId", "")) > String(b.get("messageId", ""))
	)
	for index in delivered.size():
		var value := delivered[index]
		var task := work_tasks.task(String(value.get("taskId", ""))) as Dictionary
		if (
			index < MAX_DELIVERED_MESSAGES
			and not task.is_empty()
			and String(task.get("state", "")) == "completed"
		):
			continue
		_archive_summary = RESTORE_WORK.archive_private_message_in_summary(
			_archive_summary,
			value,
		)
		_messages.erase(String(value.get("messageId", "")))


func _failure(error_code: String, error: String) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"errors": [error],
	}
