class_name TownServiceReadyNotificationRuntime
extends RefCounted


const SERVICE_DEFINITION := preload(
	"res://world/runtime/work/TownOccupationServiceDefinition.gd"
)
const RESIDENT_MESSAGE_POLICY := preload(
	"res://world/runtime/social/TownResidentMessagePolicy.gd"
)
const RESIDENT_MESSAGE_CONTENT := preload(
	"res://world/runtime/social/TownResidentMessageContent.gd"
)


static func maybe_notify_preorder(
	host,
	request: Dictionary,
	absolute_minute: int,
) -> void:
	var context := request.get("context", {}) as Dictionary
	if int(context.get("customerNotifiedAtMinute", -1)) >= 0:
		return
	var item_id := String(request.get("itemId", ""))
	var place_id := String(request.get("placeId", ""))
	if host._work.unreserved_preorder_inventory_quantity(place_id, item_id) <= 0:
		return
	var definition: Dictionary = SERVICE_DEFINITION.definition(
		String(request.get("kind", "")),
	)
	var request_id := String(request.get("requestId", ""))
	var source_ref := "preorder:%s" % request_id
	var sender_id := RESIDENT_MESSAGE_POLICY.sender_for_source(
		host,
		String(definition.get("occupationId", "")),
		source_ref,
		String(request.get("requesterResidentId", "")),
		host.PRIVATE_MESSAGE_QUERY_RUNTIME.distribution_token(
			host, source_ref, "preorder",
		),
	)
	var requester_id := String(request.get("requesterResidentId", ""))
	if sender_id.is_empty() or requester_id.is_empty():
		return
	var message_result := RESIDENT_MESSAGE_POLICY.send(
		host,
		RESIDENT_MESSAGE_CONTENT.preorder_ready(
			sender_id,
			requester_id,
			place_id,
			request_id,
			int(context.get("preorderExpiresAtMinute", absolute_minute + 1440)),
		),
	) as Dictionary
	if message_result.get("ok") != true:
		return
	var message := message_result.get("message", {}) as Dictionary
	var message_id := String(message.get("message_id", ""))
	var merged := host._work.services.merge_request_context(
		request_id,
		{
			"customerNotifiedAtMinute": absolute_minute,
			"preorderReservedQuantity": 1,
			"pickupMessageId": message_id,
		},
	) as Dictionary
	if merged.get("ok") != true:
		host.PRIVATE_MESSAGE_DELIVERY_RUNTIME.cancel_pending(host, message_id, "预订商品占货失败")


static func notify_repair(
	host,
	request: Dictionary,
	worker_resident_id: String,
	absolute_minute: int,
) -> void:
	var context := request.get("context", {}) as Dictionary
	if int(context.get("pickupNotifiedAtMinute", -1)) >= 0:
		return
	var request_id := String(request.get("requestId", ""))
	var requester_id := String(request.get("requesterResidentId", ""))
	var message_result := RESIDENT_MESSAGE_POLICY.send(
		host,
		RESIDENT_MESSAGE_CONTENT.repair_ready(
			worker_resident_id,
			requester_id,
			request_id,
			absolute_minute + 10080,
		),
	) as Dictionary
	if message_result.get("ok") != true:
		return
	host._work.services.merge_request_context(
		request_id,
		{
			"pickupNotifiedAtMinute": absolute_minute,
			"pickupMessageId": String(
				(message_result.get("message", {}) as Dictionary).get(
					"message_id",
					"",
				),
			),
		},
	)
