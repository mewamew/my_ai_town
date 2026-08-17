class_name TownPrivateMessageCreateCommand
extends RefCounted


const CONTENT_CATALOG := preload(
	"res://world/data/town/TownWorkContentCatalog.gd"
)


static func execute(
	private_message_runtime,
	work_domain,
	sender_id: String,
	recipient_id: String,
	content: String,
	message_kind: String,
	announcement_id: String,
	expires_at_minute: int,
	source_ref: String,
	created_at: int,
) -> Dictionary:
	var prepared := private_message_runtime.prepare_create(
		sender_id,
		recipient_id,
		content,
		message_kind,
		announcement_id,
		expires_at_minute,
		source_ref,
		created_at,
		work_domain.tasks,
	) as Dictionary
	if prepared.get("ok") != true:
		return prepared
	var message := prepared.get("message", {}) as Dictionary
	var message_id := String(message.get("messageId", ""))
	var task_id := String(message.get("taskId", ""))
	var task_result := work_domain.tasks.create_task_for_occupations(
		{
			"taskId": task_id,
			"capability": "message.deliver",
			"sourceKind": (
				"formal_notice"
				if String(message.get("messageKind", "")) == "announcement_notice"
				else "resident_message"
			),
			"sourceRef": message_id,
			"targets": [{"kind": "resident", "ref": recipient_id}],
			"requestedResultKind": "message_delivery",
			"createdAtMinute": created_at,
			"priority": CONTENT_CATALOG.TASK_PRIORITY["private_message_delivery"],
		},
		["occupation_postal_worker"],
	) as Dictionary
	if task_result.get("ok") != true:
		private_message_runtime.rollback_create(message_id)
		return task_result
	var delivery_task := task_result.get("task", {}) as Dictionary
	var configured_process := work_domain.tasks.configure_initial_process(
		task_id,
		int(delivery_task.get("revision", 0)),
		"awaiting_sort",
		{
			"batchId": String(message.get("batchId", "")),
			"messageId": message_id,
			"nextActivityId": "__awaiting_postal_batch__",
		},
	) as Dictionary
	if configured_process.get("ok") != true:
		work_domain.tasks.cancel_task(task_id, "消息投递阶段初始化失败")
		private_message_runtime.rollback_create(message_id)
		return configured_process
	private_message_runtime.commit_created(message)
	return {
		"ok": true,
		"message": message,
		"task": configured_process.get("task", {}) as Dictionary,
		"senderDeliveryRequired": (
			String(message.get("messageKind", "private")) == "private"
			and work_domain.occupation_post_is_vacant(
				"occupation_postal_worker",
			)
		),
	}
