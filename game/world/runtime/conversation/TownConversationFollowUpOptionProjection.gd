class_name TownConversationFollowUpOptionProjection
extends RefCounted


static func legacy_options(context: Dictionary) -> Array[Dictionary]:
	var resident_id := String(context.get("residentId", ""))
	var partner_id := String(context.get("partnerId", ""))
	var partner_ref := String(context.get("partnerRef", ""))
	var partner_name := String(context.get("partnerName", ""))
	var current_place := String(context.get("currentPlace", ""))
	var requested_place_ids := context.get("requestedPlaceIds", []) as Array
	var options: Array[Dictionary] = []
	for place_value: Variant in context.get("destinations", []) as Array:
		var place_id := String(place_value)
		if not requested_place_ids.is_empty() and not requested_place_ids.has(place_id):
			continue
		options.append({
			"option_id": "go:%s" % place_id,
			"meaning": "对话结束后本人前往%s" % place_id,
			"capability_id": "world.go_to_place",
			"target_refs": {"place_id": place_id},
			"success_result_id": "conversation-destination-reached",
			"place_id": place_id,
		})
		if not partner_id.is_empty():
			options.append({
				"option_id": "escort:%s:%s" % [partner_id, place_id],
				"meaning": "对话结束后带%s前往%s；同行者掉队时等待或折返，双方到达才算完成" % [
					partner_name, place_id,
				],
				"capability_id": "world.escort_person_to_place",
				"target_refs": {
					"place_id": place_id,
					"person_id": partner_id,
				},
				"success_result_id": "conversation-escort-arrived",
				"place_id": place_id,
			})
	if requested_place_ids.is_empty() or requested_place_ids.has(current_place):
		for activity_value: Variant in context.get("activities", []) as Array:
			var activity := activity_value as Dictionary
			var activity_id := String(activity.get("activity_id", ""))
			var label := String(activity.get("label", ""))
			if activity_id.is_empty() or label.is_empty():
				continue
			options.append({
				"option_id": "activity:%s" % activity_id,
				"meaning": "对话结束后在%s实际进行“%s”" % [current_place, label],
				"capability_id": "world.perform_activity",
				"target_refs": {
					"place_id": current_place,
					"activity_id": activity_id,
				},
				"success_result_id": "conversation-activity-completed",
				"place_id": current_place,
			})
	if requested_place_ids.is_empty():
		for nearby_value: Variant in context.get("nearby", []) as Array:
			var nearby := nearby_value as Dictionary
			var nearby_id := String(nearby.get("residentId", ""))
			if nearby_id.is_empty() or nearby_id in [resident_id, partner_ref]:
				continue
			options.append({
				"option_id": "talk:%s" % nearby_id,
				"meaning": "对话结束后尝试与%s当面交谈" % String(
					nearby.get("displayName", ""),
				),
				"capability_id": "world.start_conversation",
				"target_refs": {"resident_id": nearby_id},
				"success_result_id": "conversation-follow-up-contacted",
				"place_id": current_place,
			})
	if bool(context.get("skipServiceOfferings", false)) or partner_id.is_empty():
		return options
	for offering_value: Variant in context.get("serviceOfferings", []) as Array:
		var offering := offering_value as Dictionary
		var service_place := String(offering.get("place_id", ""))
		if not requested_place_ids.is_empty() and not requested_place_ids.has(service_place):
			continue
		var service_activity := String(offering.get("activity_id", ""))
		var service_label := String(offering.get("service_label", ""))
		options.append({
			"option_id": "fetch-service:%s:%s:%s" % [
				partner_id, service_place, service_activity,
			],
			"meaning": "请%s等候，前往%s取得%s后返回对方身边" % [
				partner_name, service_place, service_label,
			],
			"capability_id": "world.fetch_service_for_person",
			"target_refs": {
				"person_id": partner_id,
				"service_place_id": service_place,
				"service_activity_id": service_activity,
				"service_label": service_label,
			},
			"success_result_id": "conversation-service-delivered",
			"place_id": service_place,
		})
	return options
