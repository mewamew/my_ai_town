class_name TownSocialSourceReferenceValidator
extends RefCounted


const RESTORE_LAYOUT := preload(
	"res://world/runtime/persistence/TownWorldRestoreLayout.gd"
)


static func errors(
	method: String,
	source_state: Dictionary,
	world_data: Dictionary,
	residents: Dictionary,
	resident_id_by_name: Dictionary,
	conversations: Dictionary,
	announcement_ids: Array[String],
) -> Array[String]:
	var result: Array[String] = []
	match method:
		"sync_place_service_pressure":
			_validate_place(source_state.get("place_id"), "地点服务压力 place_id", world_data, result)
			_validate_resident(source_state.get("owner_id"), "地点服务压力 owner_id", residents, resident_id_by_name, result)
			var activity_id := _text(source_state.get("helper_activity_id"))
			var place_id := _text(source_state.get("place_id"))
			if (
				not activity_id.is_empty()
				and not place_id.is_empty()
				and not RESTORE_LAYOUT.world_data_has_activity_at_place(
					world_data,
					activity_id,
					place_id,
				)
			):
				result.append("地点服务压力引用的帮助活动不属于该地点")
		"sync_resident_request":
			_validate_resident(source_state.get("requester_id"), "居民请求 requester_id", residents, resident_id_by_name, result)
			var recipients: Variant = source_state.get("recipient_ids", [])
			if recipients is not Array:
				result.append("居民请求 recipient_ids 必须是数组")
			else:
				for recipient: Variant in recipients as Array:
					_validate_resident(recipient, "居民请求 recipient_ids", residents, resident_id_by_name, result)
			var place_id := _text(source_state.get("place_id"))
			if not place_id.is_empty():
				_validate_place(place_id, "居民请求 place_id", world_data, result)
			_validate_capability(
				_text(source_state.get("capability_id")),
				source_state.get("target_refs", {}) as Dictionary
					if source_state.get("target_refs") is Dictionary
					else {},
				world_data,
				residents,
				resident_id_by_name,
				conversations,
				announcement_ids,
				result,
			)
		"sync_animal_attention":
			_validate_place(source_state.get("place_id"), "动物关注 place_id", world_data, result)
		"sync_job_vacancy":
			_validate_place(source_state.get("primary_place_id"), "岗位空缺 primary_place_id", world_data, result)
			var occupation_id := _text(source_state.get("occupation_id"))
			if not _occupation_exists(world_data, occupation_id):
				result.append("岗位空缺引用不存在的职业：%s" % occupation_id)
			for candidate: Variant in source_state.get("candidate_resident_ids", []) as Array:
				_validate_resident(candidate, "岗位空缺 candidate_resident_ids", residents, resident_id_by_name, result)
	return result


static func _validate_capability(
	capability_id: String,
	target_refs: Dictionary,
	world_data: Dictionary,
	residents: Dictionary,
	resident_id_by_name: Dictionary,
	conversations: Dictionary,
	announcement_ids: Array[String],
	errors_out: Array[String],
) -> void:
	var target_place := _text(target_refs.get("place_id"))
	if not target_place.is_empty():
		_validate_place(target_place, "行动目标 place_id", world_data, errors_out)
	var target_resident := _text(target_refs.get("resident_id"))
	if not target_resident.is_empty():
		_validate_resident(target_resident, "行动目标 resident_id", residents, resident_id_by_name, errors_out)
	if capability_id == "world.perform_activity":
		var activity_id := _text(target_refs.get("activity_id"))
		if (
			not activity_id.is_empty()
			and not target_place.is_empty()
			and not RESTORE_LAYOUT.world_data_has_activity_at_place(
				world_data,
				activity_id,
				target_place,
			)
		):
			errors_out.append("行动目标活动不属于目标地点")
	elif capability_id == "world.reply_conversation":
		var conversation_id := _text(target_refs.get("conversation_id"))
		if not conversation_id.is_empty() and not conversations.has(conversation_id):
			errors_out.append("行动目标引用的对话不存在")
	elif capability_id == "bulletin.read":
		var announcement_id := _text(target_refs.get("announcement_id"))
		if not announcement_id.is_empty() and not announcement_ids.has(announcement_id):
			errors_out.append("行动目标引用的公告不存在")
	elif capability_id == "staffing.apply_assignment":
		var occupation_id := _text(target_refs.get("occupation_id"))
		if not _occupation_exists(world_data, occupation_id):
			errors_out.append("行动目标引用的职业不存在")


static func _validate_place(
	value: Variant,
	label: String,
	world_data: Dictionary,
	errors_out: Array[String],
) -> void:
	var place_id := _text(value)
	if not place_id.is_empty() and not _place_exists(world_data, place_id):
		errors_out.append("%s 引用不存在的地点：%s" % [label, place_id])


static func _validate_resident(
	value: Variant,
	label: String,
	residents: Dictionary,
	resident_id_by_name: Dictionary,
	errors_out: Array[String],
) -> void:
	var resident_ref := _text(value)
	if (
		not resident_ref.is_empty()
		and not residents.has(resident_ref)
		and not resident_id_by_name.has(resident_ref)
	):
		errors_out.append("%s 引用不存在的居民：%s" % [label, resident_ref])


static func _place_exists(world_data: Dictionary, place_id: String) -> bool:
	for value: Variant in world_data.get("places", []) as Array:
		if value is Dictionary and String((value as Dictionary).get("name", "")) == place_id:
			return true
	return false


static func _occupation_exists(world_data: Dictionary, occupation_id: String) -> bool:
	for value: Variant in world_data.get("occupations", []) as Array:
		if value is Dictionary and String((value as Dictionary).get("occupationId", "")) == occupation_id:
			return true
	return false


static func _text(value: Variant) -> String:
	return String(value).strip_edges() if value is String else ""
