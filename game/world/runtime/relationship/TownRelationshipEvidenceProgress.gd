class_name TownRelationshipEvidenceProgress
extends RefCounted


static func build(
	resident_id: String,
	resident_names: Dictionary,
	conversations: Array,
	social_matters: Array,
	conflict_events: Array = [],
) -> Array[Dictionary]:
	var normalized_resident_id := resident_id.strip_edges()
	if (
		normalized_resident_id.is_empty()
		or not resident_names.has(normalized_resident_id)
	):
		return []
	var resident_ids_by_name := _resident_ids_by_name(resident_names)
	var progress_by_resident := {}
	for conversation_value: Variant in conversations:
		if typeof(conversation_value) != TYPE_DICTIONARY:
			continue
		var conversation := conversation_value as Dictionary
		if String(conversation.get("status", "")) != "ended":
			continue
		var participant_ids: Array[String] = []
		for participant_value: Variant in (
			conversation.get("participants", []) as Array
		):
			var participant_id := _resident_id_for_ref(
				String(participant_value),
				resident_names,
				resident_ids_by_name,
			)
			if (
				not participant_id.is_empty()
				and not participant_ids.has(participant_id)
			):
				participant_ids.append(participant_id)
		if (
			participant_ids.size() != 2
			or not participant_ids.has(normalized_resident_id)
		):
			continue
		var other_id := (
			participant_ids[1]
			if participant_ids[0] == normalized_resident_id
			else participant_ids[0]
		)
		var turn_count := _confirmed_turn_count(
			conversation.get("turns", []) as Array
		)
		if turn_count <= 0:
			continue
		var item := _item_for(
			progress_by_resident,
			other_id,
			resident_names,
		)
		item["conversationCount"] = int(
			item.get("conversationCount", 0)
		) + 1
		item["confirmedTurnCount"] = int(
			item.get("confirmedTurnCount", 0)
		) + turn_count
		item["lastInteractionAt"] = (
			conversation.get("endedAt", {}) as Dictionary
		).duplicate(true)
		_add_evidence_id(
			item,
			"conversation:%s" % String(
				conversation.get("conversationId", "")
			),
		)
		progress_by_resident[other_id] = item
	for matter_value: Variant in social_matters:
		if typeof(matter_value) != TYPE_DICTIONARY:
			continue
		_add_social_matter_evidence(
			progress_by_resident,
			normalized_resident_id,
			resident_names,
			resident_ids_by_name,
			matter_value as Dictionary,
		)
	for conflict_event_value: Variant in conflict_events:
		if typeof(conflict_event_value) != TYPE_DICTIONARY:
			continue
		_add_conflict_evidence(
			progress_by_resident,
			normalized_resident_id,
			resident_names,
			conflict_event_value as Dictionary,
		)
	var items: Array[Dictionary] = []
	var other_ids: Array[String] = []
	for other_id_value: Variant in progress_by_resident:
		other_ids.append(String(other_id_value))
	other_ids.sort()
	for other_id: String in other_ids:
		var item := (
			progress_by_resident[other_id] as Dictionary
		).duplicate(true)
		var conversation_count := int(
			item.get("conversationCount", 0)
		)
		var turn_count := int(item.get("confirmedTurnCount", 0))
		var shared_matter_count := int(
			item.get("sharedMatterCount", 0)
		)
		var conflict_evidence_count := int(
			item.get("conflictEvidenceCount", 0)
		)
		var evidence_count := (
			conversation_count
			+ turn_count / 4
			+ shared_matter_count
			+ conflict_evidence_count
		)
		var depth_level := mini(7, int(evidence_count))
		item["evidenceCount"] = evidence_count
		item["depth"] = {
			"available": true,
			"level": depth_level,
			"segmentCount": 7,
			"label": _depth_label(depth_level),
		}
		item.erase("_evidenceIds")
		items.append(item)
	return items


static func _add_conflict_evidence(
	progress_by_resident: Dictionary,
	resident_id: String,
	resident_names: Dictionary,
	conflict_event: Dictionary,
) -> void:
	var event_type := String(conflict_event.get("type", ""))
	if event_type not in [
		"conflict_challenged",
		"conflict_threatened",
		"conflict_apologized",
		"conflict_disengaged",
		"unilateral_hit_confirmed",
		"brawl_started",
	]:
		return
	var conflict_id := String(
		conflict_event.get(
			"rootConflictId",
			conflict_event.get("conflictId", ""),
		)
	).strip_edges()
	if conflict_id.is_empty():
		return
	var actor_ids: Array[String] = []
	for actor_value: Variant in conflict_event.get("actorIds", []) as Array:
		var actor_id := String(actor_value).strip_edges()
		if resident_names.has(actor_id) and not actor_ids.has(actor_id):
			actor_ids.append(actor_id)
	if not actor_ids.has(resident_id):
		return
	for other_id: String in actor_ids:
		if other_id == resident_id:
			continue
		var item := _item_for(progress_by_resident, other_id, resident_names)
		var evidence_id := "conflict:%s:%s" % [
			conflict_id,
			_pair_id(resident_id, other_id),
		]
		if _add_evidence_id(item, evidence_id):
			item["conflictEvidenceCount"] = int(
				item.get("conflictEvidenceCount", 0)
			) + 1
		progress_by_resident[other_id] = item


static func _confirmed_turn_count(turns: Array) -> int:
	var count := 0
	for turn_value: Variant in turns:
		if typeof(turn_value) != TYPE_DICTIONARY:
			continue
		var turn := turn_value as Dictionary
		var status := String(turn.get("status", "confirmed"))
		if status in ["confirmed", "completed", "accepted"]:
			count += 1
	return count


static func _add_social_matter_evidence(
	progress_by_resident: Dictionary,
	resident_id: String,
	resident_names: Dictionary,
	resident_ids_by_name: Dictionary,
	matter: Dictionary,
) -> void:
	var matter_id := String(matter.get("matter_id", "")).strip_edges()
	if matter_id.is_empty():
		return
	var completed_ids: Array[String] = []
	for participant_value: Variant in (
		matter.get("participants", {}) as Dictionary
	).values():
		if typeof(participant_value) != TYPE_DICTIONARY:
			continue
		var participant := participant_value as Dictionary
		if String(participant.get("status", "")) != "completed":
			continue
		var participant_id := _resident_id_for_ref(
			String(participant.get("resident_id", "")),
			resident_names,
			resident_ids_by_name,
		)
		if (
			resident_names.has(participant_id)
			and not completed_ids.has(participant_id)
		):
			completed_ids.append(participant_id)
	var related_ids := completed_ids.duplicate()
	var creator_id := _resident_id_for_ref(
		String(matter.get("creator_id", "")),
		resident_names,
		resident_ids_by_name,
	)
	if resident_names.has(creator_id) and not related_ids.has(creator_id):
		related_ids.append(creator_id)
	for subject_value: Variant in matter.get("subject_ids", []) as Array:
		var subject_id := _resident_id_for_ref(
			String(subject_value),
			resident_names,
			resident_ids_by_name,
		)
		if (
			resident_names.has(subject_id)
			and not related_ids.has(subject_id)
		):
			related_ids.append(subject_id)
	if not related_ids.has(resident_id):
		return
	for other_id: String in related_ids:
		if other_id == resident_id:
			continue
		# A creator/subject only becomes relationship evidence when the other
		# resident actually completed a formal participation in this matter.
		if (
			not completed_ids.has(resident_id)
			and not completed_ids.has(other_id)
		):
			continue
		var item := _item_for(
			progress_by_resident,
			other_id,
			resident_names,
		)
		var evidence_id := "matter:%s:%s" % [
			matter_id,
			_pair_id(resident_id, other_id),
		]
		if _add_evidence_id(item, evidence_id):
			item["sharedMatterCount"] = int(
				item.get("sharedMatterCount", 0)
			) + 1
		progress_by_resident[other_id] = item


static func _item_for(
	progress_by_resident: Dictionary,
	other_id: String,
	resident_names: Dictionary,
) -> Dictionary:
	return (
		progress_by_resident.get(other_id, {
			"residentId": other_id,
			"displayName": String(resident_names.get(other_id, "")),
			"conversationCount": 0,
			"confirmedTurnCount": 0,
			"sharedMatterCount": 0,
			"conflictEvidenceCount": 0,
			"lastInteractionAt": {},
			"_evidenceIds": [],
		}) as Dictionary
	).duplicate(true)


static func _add_evidence_id(item: Dictionary, evidence_id: String) -> bool:
	var normalized := evidence_id.strip_edges()
	if normalized.is_empty():
		return false
	var evidence_ids := item.get("_evidenceIds", []) as Array
	if evidence_ids.has(normalized):
		return false
	evidence_ids.append(normalized)
	item["_evidenceIds"] = evidence_ids
	return true


static func _pair_id(first_id: String, second_id: String) -> String:
	var ids := [first_id, second_id]
	ids.sort()
	return "%s+%s" % [ids[0], ids[1]]


static func _resident_ids_by_name(resident_names: Dictionary) -> Dictionary:
	var result := {}
	for resident_id_value: Variant in resident_names:
		var resident_id := String(resident_id_value).strip_edges()
		var resident_name := String(
			resident_names.get(resident_id_value, "")
		).strip_edges()
		if resident_id.is_empty() or resident_name.is_empty():
			continue
		if result.has(resident_name):
			# 重名不能安全地反查稳定身份，因此保持失败关闭。
			result[resident_name] = ""
			continue
		result[resident_name] = resident_id
	return result


static func _resident_id_for_ref(
	resident_ref: String,
	resident_names: Dictionary,
	resident_ids_by_name: Dictionary,
) -> String:
	var normalized := resident_ref.strip_edges()
	if normalized.is_empty():
		return ""
	if resident_names.has(normalized):
		return normalized
	return String(resident_ids_by_name.get(normalized, "")).strip_edges()


static func _depth_label(level: int) -> String:
	match clampi(level, 0, 7):
		0:
			return "尚未形成共同经历"
		1:
			return "刚有接触"
		2:
			return "逐渐熟悉"
		3:
			return "已有来往"
		4:
			return "关系深厚"
		5:
			return "心意相通"
		6:
			return "亲密无间"
		_:
			return "结为伴侣"
