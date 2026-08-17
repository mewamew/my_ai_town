class_name TownPrivateMessageDeliveryRuntime
extends RefCounted


const WORLD_LOG_COMMIT_RUNTIME := preload(
	"res://world/runtime/log/TownWorldLogCommitRuntime.gd"
)


const POSTAL_MESSAGE_RUNTIME := preload(
	"res://world/runtime/social/TownPostalMessageRuntime.gd"
)
const ANNOUNCEMENT_COMMAND_RUNTIME := preload(
	"res://world/runtime/social/TownAnnouncementCommandRuntime.gd"
)


static func finish_sender_action(
	host,
	resident_id: String,
	action: Dictionary,
) -> void:
	var created: Dictionary = host.create_private_message(
		resident_id,
		String(action.get("recipient_resident_id", "")),
		String(action.get("content", "")),
	)
	if created.get("ok") != true:
		host.ACTION_SETTLEMENT_RUNTIME.interrupt(host,
			resident_id,
			String((created.get(
				"errors",
				["口信没有进入投递流程"],
			) as Array)[0]),
		)
		return
	host.ACTION_SETTLEMENT_RUNTIME.finish(host,
		resident_id,
		"已把口信交给投递流程，等待邮差送达",
	)


static func complete_delivery(
	host,
	initiator_ref: String,
	target_ref: String,
	turn: Dictionary,
	can_accept_task: Callable,
	acceptance_occupation_id: Callable,
) -> void:
	var postal_resident_id: String = host._resident_key(initiator_ref)
	var recipient_id: String = host._resident_key(target_ref)
	if postal_resident_id.is_empty() or recipient_id.is_empty():
		return
	var delivered_at := int(host._environment.get_absolute_minute())
	var settlement: Dictionary = host.private_message_runtime.complete_delivery(
		postal_resident_id,
		recipient_id,
		String(turn.get("say", "")),
		delivered_at,
		host._work.tasks,
		can_accept_task,
		acceptance_occupation_id,
	)
	if settlement.get("ok") != true:
		return
	var message_id := String(settlement.get("messageId", ""))
	var message := settlement.get("message", {}) as Dictionary
	activate_follow_up(host, message_id, message, delivered_at)
	compact_delivered(host)
	ANNOUNCEMENT_COMMAND_RUNTIME.apply_delivered_notice(
		host,
		message_id,
		message,
		postal_resident_id,
		recipient_id,
		delivered_at,
	)
	host._bump_world_revision()
	WORLD_LOG_COMMIT_RUNTIME.append_private_message(host,
		"消息送达",
		message,
		"completed",
		postal_resident_id,
	)
	var sender_id := String(message.get("senderResidentId", ""))
	if host.resident_registry.records.has(sender_id):
		host._schedule_decision(sender_id, true)


static func compact_delivered(host) -> void:
	host.private_message_runtime.compact_delivered(host._work.tasks)


static func enable_sender_delivery(host, message_id: String) -> void:
	var sender_id := POSTAL_MESSAGE_RUNTIME.enable_sender_delivery(
		host.private_message_runtime,
		host._work,
		message_id,
	)
	if not sender_id.is_empty():
		host._schedule_decision(sender_id, true)


static func expire_time_sensitive(host, absolute_minute: int) -> void:
	for message_id: String in (
		host.private_message_runtime.pending_expired_ids(absolute_minute)
	):
		cancel_pending(host, message_id, "消息对应的事情已经过期")


static func cancel_for_source(
	host,
	source_ref: String,
	reason: String,
) -> void:
	for message_id: String in (
		host.private_message_runtime.pending_ids_for_source(source_ref)
	):
		cancel_pending(host, message_id, reason)


static func cancel_pending(
	host,
	message_id: String,
	reason: String,
) -> void:
	var cancellation := POSTAL_MESSAGE_RUNTIME.cancellation_context(
		host.private_message_runtime,
		host._work,
		message_id,
	)
	if cancellation.is_empty():
		return
	var message := cancellation.get("message", {}) as Dictionary
	var assigned_id := String(cancellation.get("assignedResidentId", ""))
	if not assigned_id.is_empty():
		var resident := host.resident_registry.records.get(assigned_id, {}) as Dictionary
		var action := resident.get("currentAction", {}) as Dictionary
		if (
			String(action.get("type", "")) == "搭话"
			and String(action.get("say", "")).strip_edges()
			== String(message.get("content", "")).strip_edges()
		):
			host.ACTION_SETTLEMENT_RUNTIME.interrupt(host, assigned_id, reason)
	var cancelled_message := POSTAL_MESSAGE_RUNTIME.finish_cancellation(
		host.private_message_runtime,
		host._work,
		message_id,
		reason,
	)
	if cancelled_message.is_empty():
		return
	WORLD_LOG_COMMIT_RUNTIME.append_private_message(host,
		"消息取消",
		cancelled_message,
		"cancelled",
	)
	host._bump_world_revision(false)


static func activate_follow_up(
	host,
	message_id: String,
	message: Dictionary,
	delivered_at: int,
) -> void:
	var follow_up := POSTAL_MESSAGE_RUNTIME.delivered_follow_up(
		message_id,
		message,
		delivered_at,
	)
	if follow_up.is_empty():
		return
	var request := POSTAL_MESSAGE_RUNTIME.delivered_follow_up_request(
		host._work,
		host.resident_registry.name_by_id,
		follow_up,
	)
	if not request.is_empty():
		host.sync_resident_request(request)


static func ordinary_recipients(
	host,
	resident_ref: String,
) -> Array[Dictionary]:
	var resident_id: String = host._resident_key(resident_ref)
	var present_resident_ids := {}
	for other_id: String in host.resident_registry.order:
		if host.resident_is_present(
			host.resident_registry.records.get(other_id, {}) as Dictionary,
		):
			present_resident_ids[other_id] = true
	return POSTAL_MESSAGE_RUNTIME.ordinary_recipients(
		host.private_message_runtime,
		resident_id,
		host.resident_registry.order,
		present_resident_ids,
		host.resident_registry.name_by_id,
	)
