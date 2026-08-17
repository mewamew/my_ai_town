class_name TownPostalMessageRuntime
extends RefCounted


const WORLD_LOG_COMMIT_RUNTIME := preload(
	"res://world/runtime/log/TownWorldLogCommitRuntime.gd"
)


const CONTENT_CATALOG := preload(
	"res://world/data/town/TownWorkContentCatalog.gd"
)
const CREATE_COMMAND := preload(
	"res://world/runtime/social/TownPrivateMessageCreateCommand.gd"
)


static func create(
	host,
	sender_ref: String,
	recipient_ref: String,
	content: String,
	message_kind: String,
	announcement_id: String,
	expires_at_minute: int,
	source_ref: String,
) -> Dictionary:
	if not host._running:
		return host._command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var sender_id: String = host._resident_key(sender_ref)
	var recipient_id: String = host._resident_key(recipient_ref)
	if (
		not sender_id.is_empty()
		and not recipient_id.is_empty()
		and (
			not host._resident_is_alive(sender_id)
			or not host._resident_is_alive(recipient_id)
		)
	):
		return host._command_failure(
			"PRIVATE_MESSAGE_PARTICIPANT_DEAD",
			["死亡居民不能发送或接收新消息"],
		)
	var creation := CREATE_COMMAND.execute(
		host.private_message_runtime,
		host._work,
		sender_id,
		recipient_id,
		content,
		message_kind,
		announcement_id,
		expires_at_minute,
		source_ref,
		int(host._environment.get_absolute_minute()),
	) as Dictionary
	if creation.get("ok") != true:
		return host._decorate_command_result(creation)
	var message := creation.get("message", {}) as Dictionary
	var message_id := String(message.get("messageId", ""))
	var task_id := String(message.get("taskId", ""))
	var created_at := int(message.get("createdAtMinute", 0))
	var delivery_task := creation.get("task", {}) as Dictionary
	if bool(creation.get("senderDeliveryRequired", false)):
		host.PRIVATE_MESSAGE_DELIVERY_RUNTIME.enable_sender_delivery(host, message_id)
		message = host.private_message_runtime.message(message_id)
		delivery_task = host._work.tasks.task(task_id) as Dictionary
	else:
		ensure_sort_task(
			host._work,
			String(message.get("batchId", "")),
			created_at,
		)
	host._bump_world_revision()
	WORLD_LOG_COMMIT_RUNTIME.append_private_message(host, "消息创建", message, "waiting")
	for resident_id: String in host.resident_registry.order:
		if host.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.can_work_occupation(host,
			resident_id,
			"occupation_postal_worker",
		):
			host._schedule_decision(resident_id, true)
	return host._decorate_command_result({
		"ok": true,
		"changed": true,
		"message": host.private_message_runtime.public_message(
			message, host.resident_registry.name_by_id,
		),
		"task": delivery_task.duplicate(true),
	})


static func enable_sender_delivery(
	private_message_runtime,
	work_domain,
	message_id: String,
) -> String:
	var message := private_message_runtime.message(message_id) as Dictionary
	if (
		message.is_empty()
		or String(message.get("state", "")) != "pending"
		or String(message.get("messageKind", "private")) != "private"
	):
		return ""
	var task_id := String(message.get("taskId", ""))
	var task := work_domain.tasks.task(task_id) as Dictionary
	if task.is_empty():
		return ""
	var sender_id := String(message.get("senderResidentId", ""))
	var granted := work_domain.tasks.add_eligible_residents(
		task_id,
		[sender_id],
	) as Dictionary
	if granted.get("ok") != true:
		return ""
	task = granted.get("task", {}) as Dictionary
	if String(task.get("processStage", "")) != "out_for_delivery":
		var staged := work_domain.tasks.set_process_stage_from_world(
			task_id,
			int(task.get("revision", 0)),
			"out_for_delivery",
			{
				"batchId": "",
				"messageId": message_id,
				"nextActivityId": "__resident_delivery__",
				"fallbackMode": "sender_in_person",
			},
		) as Dictionary
		if staged.get("ok") != true:
			return ""
	message["batchId"] = ""
	private_message_runtime.set_message(message_id, message)
	return sender_id


static func ensure_sort_task(
	work_domain,
	batch_id: String,
	created_at: int,
) -> void:
	if batch_id.is_empty():
		return
	work_domain.ensure_production_task({
		"taskId": "postal-sort-task:%s" % batch_id,
		"capability": "message.sort",
		"sourceKind": "postal_batch",
		"sourceRef": batch_id,
		"targets": [{"kind": "route", "ref": "小镇道路"}],
		"requestedResultKind": "message_batch_sorted",
		"createdAtMinute": created_at,
		"priority": CONTENT_CATALOG.TASK_PRIORITY["postal_sort"],
	})


static func waiting_message_count(host) -> int:
	return host.private_message_runtime.waiting_message_count()


static func batch_message_count(host, batch_id: String) -> int:
	return host.private_message_runtime.postal_batch_message_count(batch_id)


static func set_batch_delivery_stage(
	host,
	batch_id: String,
	stage: String,
	next_activity_id: String,
	now: int,
) -> void:
	set_delivery_tasks_stage(
		host.private_message_runtime,
		host._work,
		batch_id,
		stage,
		next_activity_id,
		now,
	)


static func reserve_delivery_tasks(host, batch_id: String) -> void:
	for message: Dictionary in host.private_message_runtime.messages_in_batch(batch_id):
		var task := host._work.tasks.task(
			String(message.get("taskId", "")),
		) as Dictionary
		host.WORK_TASK_PUBLIC_RUNTIME.reserve(
			host,
			task,
			"occupation_postal_worker",
		)


static func set_delivery_tasks_stage(
	private_message_runtime,
	work_domain,
	batch_id: String,
	stage: String,
	next_activity_id: String,
	now: int,
) -> void:
	for message: Dictionary in private_message_runtime.messages_in_batch(
		batch_id,
	):
		var task_id := String(message.get("taskId", ""))
		var task := work_domain.tasks.task(task_id) as Dictionary
		if task.is_empty():
			continue
		work_domain.tasks.set_process_stage_from_world(
			task_id,
			int(task.get("revision", 0)),
			stage,
			{
				"batchId": batch_id,
				"messageId": String(message.get("messageId", "")),
				"stageUpdatedAtMinute": now,
				"nextActivityId": next_activity_id,
			},
		)


static func cancellation_context(
	private_message_runtime,
	work_domain,
	message_id: String,
) -> Dictionary:
	var message := private_message_runtime.message(message_id) as Dictionary
	if message.is_empty() or String(message.get("state", "")) != "pending":
		return {}
	var task := work_domain.tasks.task(
		String(message.get("taskId", "")),
	) as Dictionary
	return {
		"message": message,
		"task": task,
		"assignedResidentId": String(task.get("assignedResidentId", "")),
	}


static func finish_cancellation(
	private_message_runtime,
	work_domain,
	message_id: String,
	reason: String,
) -> Dictionary:
	var message := private_message_runtime.message(message_id) as Dictionary
	if message.is_empty() or String(message.get("state", "")) != "pending":
		return {}
	var task := work_domain.tasks.task(
		String(message.get("taskId", "")),
	) as Dictionary
	if not task.is_empty() and String(task.get("state", "")) not in [
		"completed", "failed", "cancelled",
	]:
		work_domain.tasks.cancel_task(String(task.get("taskId", "")), reason)
	var cancelled_message := message.duplicate(true)
	cancelled_message["state"] = "cancelled"
	cancelled_message["reason"] = reason
	private_message_runtime.remove(message_id)
	return cancelled_message


static func delivered_follow_up(
	message_id: String,
	message: Dictionary,
	delivered_at: int,
) -> Dictionary:
	if (
		String(message.get("state", "")) != "delivered"
		or String(message.get("messageKind", "private")) != "private"
		or String(message.get("messageId", "")) != message_id
	):
		return {}
	var source_ref := String(message.get("sourceRef", "")).strip_edges()
	var result := {
		"messageId": message_id,
		"senderId": String(message.get("senderResidentId", "")),
		"recipientId": String(message.get("recipientResidentId", "")),
		"deliveredAt": delivered_at,
		"expiresAt": int(message.get("expiresAtMinute", -1)),
	}
	if source_ref.begins_with("preorder:"):
		result["kind"] = "preorder_pickup"
		result["sourceId"] = source_ref.substr("preorder:".length())
		return result
	if source_ref.begins_with("repair-pickup:"):
		result["kind"] = "repair_pickup"
		result["sourceId"] = source_ref.substr("repair-pickup:".length())
		return result
	if source_ref.begins_with("performance-event:"):
		var day_text := source_ref.substr("performance-event:".length())
		if day_text.is_valid_int():
			result["kind"] = "performance_invitation"
			result["dayIndex"] = int(day_text)
			return result
	return {}


static func delivered_follow_up_request(
	work_domain,
	resident_names: Dictionary,
	follow_up: Dictionary,
) -> Dictionary:
	match String(follow_up.get("kind", "")):
		"preorder_pickup":
			return _preorder_pickup_request(work_domain, follow_up)
		"repair_pickup":
			return _repair_pickup_request(work_domain, follow_up)
		"performance_invitation":
			return _performance_invitation_request(
				work_domain,
				resident_names,
				follow_up,
			)
	return {}


static func _preorder_pickup_request(
	work_domain,
	follow_up: Dictionary,
) -> Dictionary:
	var request_id := String(follow_up.get("sourceId", ""))
	var request := work_domain.services.request(request_id) as Dictionary
	var context := request.get("context", {}) as Dictionary
	var message_id := String(follow_up.get("messageId", ""))
	var sender_id := String(follow_up.get("senderId", ""))
	var recipient_id := String(follow_up.get("recipientId", ""))
	var delivered_at := int(follow_up.get("deliveredAt", -1))
	if (
		String(request.get("state", "")) not in ["pending", "waiting"]
		or String(request.get("requesterResidentId", "")) != recipient_id
		or String(context.get("pickupMessageId", "")) != message_id
		or int(context.get("preorderReservedQuantity", 0)) <= 0
	):
		return {}
	var expires_at := int(
		context.get("preorderExpiresAtMinute", delivered_at + 1440),
	)
	if expires_at <= delivered_at:
		return {}
	return {
		"request_id": "preorder-pickup:%s" % request_id,
		"source_revision": 1,
		"requester_id": sender_id,
		"submitted": true,
		"active": true,
		"reason_summary": "预订商品已经到店，可以回来领取",
		"subject_ids": [sender_id, recipient_id],
		"place_id": String(request.get("placeId", "")),
		"capability_id": "world.go_to_place",
		"target_refs": {"place_id": String(request.get("placeId", ""))},
		"success_result_id": "preorder-customer-arrived",
		"expires_at": expires_at,
		"capacity": 1,
		"source_event_ids": [request_id],
	}


static func _repair_pickup_request(
	work_domain,
	follow_up: Dictionary,
) -> Dictionary:
	var request_id := String(follow_up.get("sourceId", ""))
	var request := work_domain.services.request(request_id) as Dictionary
	var context := request.get("context", {}) as Dictionary
	var outcome := request.get("outcome", {}) as Dictionary
	var message_id := String(follow_up.get("messageId", ""))
	var sender_id := String(follow_up.get("senderId", ""))
	var recipient_id := String(follow_up.get("recipientId", ""))
	var delivered_at := int(follow_up.get("deliveredAt", -1))
	var expires_at := int(follow_up.get("expiresAt", -1))
	if (
		String(request.get("kind", "")) != "repair"
		or String(request.get("state", "")) not in ["pending", "waiting"]
		or String(request.get("requesterResidentId", "")) != recipient_id
		or String(context.get("pickupMessageId", "")) != message_id
		or String(outcome.get("status", "")) != "ready_for_pickup"
		or expires_at <= delivered_at
	):
		return {}
	return {
		"request_id": "repair-pickup:%s" % request_id,
		"source_revision": 1,
		"requester_id": sender_id,
		"submitted": true,
		"active": true,
		"reason_summary": "修理件已经完成，可以到工作坊领取",
		"subject_ids": [sender_id, recipient_id],
		"place_id": CONTENT_CATALOG.PLACE_WORKSHOP,
		"capability_id": "world.go_to_place",
		"target_refs": {"place_id": CONTENT_CATALOG.PLACE_WORKSHOP},
		"success_result_id": "repair-item-picked-up",
		"expires_at": expires_at,
		"capacity": 1,
		"source_event_ids": [request_id],
	}


static func _performance_invitation_request(
	work_domain,
	resident_names: Dictionary,
	follow_up: Dictionary,
) -> Dictionary:
	var day_index := int(follow_up.get("dayIndex", -1))
	var sender_id := String(follow_up.get("senderId", ""))
	var recipient_id := String(follow_up.get("recipientId", ""))
	var delivered_at := int(follow_up.get("deliveredAt", -1))
	var expires_at := int(follow_up.get("expiresAt", -1))
	if expires_at <= delivered_at:
		return {}
	var performance_active := false
	for request_value: Variant in (
		work_domain.services.snapshot() as Dictionary
	).get("requests", []) as Array:
		var request := request_value as Dictionary
		var context := request.get("context", {}) as Dictionary
		if (
			String(request.get("kind", "")) == "performance"
			and String(request.get("state", "")) in ["pending", "waiting"]
			and String(request.get("requesterResidentId", "")) == sender_id
			and int(context.get("dayIndex", -1)) == day_index
		):
			performance_active = true
			break
	if not performance_active:
		return {}
	return {
		"request_id": "performance-invitation:%d:%s" % [
			day_index,
			recipient_id,
		],
		"source_revision": 1,
		"requester_id": sender_id,
		"submitted": true,
		"active": true,
		"reason_summary": "%s邀请居民到中心广场听演奏" % String(
			resident_names.get(sender_id, ""),
		),
		"subject_ids": [sender_id, recipient_id],
		"place_id": CONTENT_CATALOG.PLACE_PLAZA,
		"capability_id": "world.go_to_place",
		"target_refs": {
			"place_id": CONTENT_CATALOG.PLACE_PLAZA,
			"resident_id": sender_id,
		},
		"success_result_id": "performance-audience-arrived",
		"expires_at": expires_at,
		"capacity": 1,
		"source_event_ids": ["performance-event:%d" % day_index],
	}


static func ordinary_recipients(
	private_message_runtime,
	resident_id: String,
	resident_order: Array[String],
	present_resident_ids: Dictionary,
	resident_names: Dictionary,
) -> Array[Dictionary]:
	var recipients: Array[Dictionary] = []
	if (
		resident_id.is_empty()
		or private_message_runtime.pending_count_from_sender(resident_id) >= 2
	):
		return recipients
	for other_id: String in resident_order:
		if other_id == resident_id:
			continue
		if not present_resident_ids.has(other_id):
			continue
		recipients.append({
			"resident_id": other_id,
			"name": String(resident_names.get(other_id, "")),
		})
	return recipients
