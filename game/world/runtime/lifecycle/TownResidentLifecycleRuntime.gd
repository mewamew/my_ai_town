class_name TownResidentLifecycleRuntime
extends RefCounted


const SCHEMA_VERSION := 1
const STATUS_ALIVE := "alive"
const STATUS_DEAD := "dead"
const EVENT_TYPE_DEATH := "居民死亡"
const VALID_STATUSES := [STATUS_ALIVE, STATUS_DEAD]
const HOME_ANCHOR_KEYS := [
	"spaceId",
	"regionId",
	"placeName",
	"position",
]
const DEATH_EVENT_KEYS := [
	"event_id",
	"type",
	"time",
	"deceased_resident_id",
	"deceased_resident_name",
	"reason",
	"location",
	"attacker_resident_id",
]
const RESIDENT_STATE_KEYS := [
	"residentId",
	"residentName",
	"status",
	"revision",
	"homeAnchor",
	"deathEvent",
	"recipientResidentIds",
	"deliveredResidentIds",
]

var _residents: Dictionary = {}


func initialize_resident(
	resident_id: String,
	resident_name: String,
	home_anchor: Dictionary,
) -> Dictionary:
	var normalized_id := resident_id.strip_edges()
	var normalized_name := resident_name.strip_edges()
	var errors: Array[String] = []
	if normalized_id.is_empty():
		errors.append("居民生命周期必须使用稳定 residentId")
	if normalized_name.is_empty():
		errors.append("居民生命周期必须包含居民姓名")
	errors.append_array(_home_anchor_errors(home_anchor))
	if not errors.is_empty():
		return _failure("RESIDENT_LIFECYCLE_INVALID", errors)
	if _residents.has(normalized_id):
		var existing := _residents[normalized_id] as Dictionary
		if (
			String(existing.get("residentName", "")) != normalized_name
			or existing.get("homeAnchor") != home_anchor
		):
			return _failure(
				"RESIDENT_LIFECYCLE_IDENTITY_MISMATCH",
				["同一 residentId 不能对应不同姓名或住处"],
			)
		return {
			"ok": true,
			"changed": false,
			"state": existing.duplicate(true),
		}
	var state := {
		"residentId": normalized_id,
		"residentName": normalized_name,
		"status": STATUS_ALIVE,
		"revision": 1,
		"homeAnchor": home_anchor.duplicate(true),
		"deathEvent": {},
		"recipientResidentIds": [],
		"deliveredResidentIds": [],
	}
	_residents[normalized_id] = state
	return {
		"ok": true,
		"changed": true,
		"state": state.duplicate(true),
	}


func replace_deceased_resident(
	resident_id: String,
	resident_name: String,
	home_anchor: Dictionary,
) -> Dictionary:
	var normalized_id := resident_id.strip_edges()
	if (
		not _residents.has(normalized_id)
		or String((_residents[normalized_id] as Dictionary).get("status", ""))
		!= STATUS_DEAD
	):
		return _failure(
			"RESIDENT_REPLACEMENT_LIFECYCLE_INVALID",
			["只有已经死亡的居民席位可以迎接新居民"],
		)
	_residents.erase(normalized_id)
	return initialize_resident(normalized_id, resident_name, home_anchor)


func confirm_death(
	resident_id: String,
	reason: String,
	event_id: String,
	world_time: Dictionary,
	death_location: Dictionary,
	queue_direct_death_events: bool,
	attacker_resident_id: String = "",
	witness_resident_ids: Array = [],
) -> Dictionary:
	var normalized_id := resident_id.strip_edges()
	if not _residents.has(normalized_id):
		return _failure(
			"RESIDENT_NOT_FOUND",
			["找不到要确认死亡的居民"],
		)
	var state := _residents[normalized_id] as Dictionary
	if String(state.get("status", "")) == STATUS_DEAD:
		return {
			"ok": true,
			"changed": false,
			"state": state.duplicate(true),
			"event": (
				state.get("deathEvent", {}) as Dictionary
			).duplicate(true),
		}
	var normalized_reason := reason.strip_edges()
	var normalized_event_id := event_id.strip_edges()
	var errors: Array[String] = []
	if normalized_reason.is_empty():
		errors.append("死亡确认必须包含 World 已确认的原因")
	if normalized_event_id.is_empty():
		errors.append("死亡确认必须包含稳定事件编号")
	elif not _resident_id_for_death_event(normalized_event_id).is_empty():
		errors.append("死亡确认事件编号已经被其他居民使用")
	if not _valid_world_time(world_time):
		errors.append("死亡确认必须包含世界时间")
	var confirmed_location := (
		death_location
		if not death_location.is_empty()
		else state.get("homeAnchor", {}) as Dictionary
	)
	errors.append_array(_location_errors(confirmed_location))
	if not errors.is_empty():
		return _failure("RESIDENT_DEATH_INVALID", errors)
	var recipients: Array[String] = []
	if queue_direct_death_events:
		for other_id_value: Variant in _residents:
			var other_id := String(other_id_value)
			if other_id == normalized_id:
				continue
			var other := _residents[other_id] as Dictionary
			if String(other.get("status", "")) == STATUS_ALIVE:
				recipients.append(other_id)
	recipients.sort()
	var event := {
		"event_id": normalized_event_id,
		"type": EVENT_TYPE_DEATH,
		"time": world_time.duplicate(true),
		"deceased_resident_id": normalized_id,
		"deceased_resident_name": String(
			state.get("residentName", ""),
		),
		"reason": normalized_reason,
		"location": confirmed_location.duplicate(true),
		"attacker_resident_id": attacker_resident_id.strip_edges(),
	}
	var normalized_witnesses := _unique_string_array(
		witness_resident_ids,
	)
	if not normalized_witnesses.is_empty():
		event["witness_resident_ids"] = normalized_witnesses
	state["status"] = STATUS_DEAD
	state["revision"] = int(state.get("revision", 1)) + 1
	state["deathEvent"] = event.duplicate(true)
	state["recipientResidentIds"] = recipients.duplicate()
	state["deliveredResidentIds"] = []
	return {
		"ok": true,
		"changed": true,
		"state": state.duplicate(true),
		"event": event.duplicate(true),
		"recipientResidentIds": recipients.duplicate(),
	}


func mark_death_event_delivered(
	event_id: String,
	recipient_resident_id: String,
) -> Dictionary:
	var owner_id := _resident_id_for_death_event(event_id.strip_edges())
	if owner_id.is_empty():
		return _failure(
			"RESIDENT_DEATH_EVENT_NOT_FOUND",
			["找不到要交付的死亡事件"],
		)
	var state := _residents[owner_id] as Dictionary
	var recipient_id := recipient_resident_id.strip_edges()
	var recipients := state.get("recipientResidentIds", []) as Array
	if not recipients.has(recipient_id) or not is_alive(recipient_id):
		return _failure(
			"RESIDENT_DEATH_EVENT_RECIPIENT_INVALID",
			["该居民不是这次死亡事件的合法接收者"],
		)
	var delivered := state.get("deliveredResidentIds", []) as Array
	if delivered.has(recipient_id):
		return {
			"ok": true,
			"changed": false,
			"state": state.duplicate(true),
		}
	delivered.append(recipient_id)
	delivered.sort()
	state["revision"] = int(state.get("revision", 1)) + 1
	return {
		"ok": true,
		"changed": true,
		"state": state.duplicate(true),
	}


func get_pending_death_deliveries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for resident_id in _sorted_resident_ids():
		var state := _residents[resident_id] as Dictionary
		if String(state.get("status", "")) != STATUS_DEAD:
			continue
		var event := state.get("deathEvent", {}) as Dictionary
		var delivered := state.get("deliveredResidentIds", []) as Array
		for recipient_value: Variant in state.get(
			"recipientResidentIds",
			[],
		) as Array:
			var recipient_id := String(recipient_value)
			if delivered.has(recipient_id):
				continue
			if not is_alive(recipient_id):
				continue
			result.append({
				"event": event.duplicate(true),
				"recipientResidentId": recipient_id,
			})
	return result


func get_public_death_events() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for resident_id in _sorted_resident_ids():
		var state := _residents[resident_id] as Dictionary
		if String(state.get("status", "")) != STATUS_DEAD:
			continue
		var event := state.get("deathEvent", {}) as Dictionary
		if not event.is_empty():
			result.append(event.duplicate(true))
	result.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return String(left.get("event_id", "")) < String(
				right.get("event_id", ""),
			)
	)
	return result


func is_alive(resident_id: String) -> bool:
	var normalized_id := resident_id.strip_edges()
	return (
		_residents.has(normalized_id)
		and String(
			(_residents[normalized_id] as Dictionary).get("status", ""),
		) == STATUS_ALIVE
	)


func get_resident_state(resident_id: String) -> Dictionary:
	var normalized_id := resident_id.strip_edges()
	if not _residents.has(normalized_id):
		return {}
	return (_residents[normalized_id] as Dictionary).duplicate(true)


func create_save_snapshot() -> Dictionary:
	var residents: Array[Dictionary] = []
	for resident_id in _sorted_resident_ids():
		residents.append(
			(_residents[resident_id] as Dictionary).duplicate(true),
		)
	return {
		"schemaVersion": SCHEMA_VERSION,
		"residents": residents,
	}


func restore_save_snapshot(snapshot: Dictionary) -> Dictionary:
	var prepared := _prepare_snapshot(snapshot)
	if prepared.get("ok") != true:
		return prepared
	_residents = (
		prepared.get("residents", {}) as Dictionary
	).duplicate(true)
	return {
		"ok": true,
		"residentCount": _residents.size(),
	}


func _prepare_snapshot(snapshot: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if not _has_exact_keys(snapshot, ["schemaVersion", "residents"]):
		errors.append("居民生命周期存档字段不完整或包含未知字段")
	if snapshot.get("schemaVersion") != SCHEMA_VERSION:
		errors.append("居民生命周期存档版本不受支持")
	var residents_value: Variant = snapshot.get("residents")
	if not residents_value is Array:
		errors.append("居民生命周期存档 residents 必须是数组")
		return _failure("RESIDENT_LIFECYCLE_SAVE_INVALID", errors)
	var restored := {}
	var event_ids := {}
	for index in (residents_value as Array).size():
		var value: Variant = (residents_value as Array)[index]
		if not value is Dictionary:
			errors.append("居民生命周期存档 residents[%d] 必须是对象" % index)
			continue
		var state := value as Dictionary
		errors.append_array(_resident_state_errors(state, index, event_ids))
		var resident_id := String(state.get("residentId", ""))
		if not resident_id.is_empty():
			if restored.has(resident_id):
				errors.append("居民生命周期存档 residentId 重复：%s" % resident_id)
			else:
				restored[resident_id] = state.duplicate(true)
	if errors.is_empty() and not _residents.is_empty():
		var expected_ids := _sorted_resident_ids()
		var restored_ids: Array[String] = []
		for resident_id_value: Variant in restored:
			restored_ids.append(String(resident_id_value))
		restored_ids.sort()
		if restored_ids != expected_ids:
			errors.append("居民生命周期存档居民集合与当前开局配置不一致")
		else:
			for resident_id in expected_ids:
				var restored_state := restored[resident_id] as Dictionary
				var current_state := _residents[resident_id] as Dictionary
				if String(
					restored_state.get(
						"residentName",
						"",
					),
				) != String(
					current_state.get(
						"residentName",
						"",
					),
				):
					errors.append("居民生命周期存档姓名与当前开局配置不一致")
				if restored_state.get("homeAnchor") != current_state.get("homeAnchor"):
					errors.append("居民生命周期存档住处与当前开局配置不一致")
	if errors.is_empty():
		for owner_id_value: Variant in restored:
			var owner_id := String(owner_id_value)
			var owner_state := restored[owner_id] as Dictionary
			for recipient_value: Variant in owner_state.get(
				"recipientResidentIds",
				[],
			) as Array:
				var recipient_id := String(recipient_value)
				if recipient_id == owner_id or not restored.has(recipient_id):
					errors.append("居民生命周期存档包含未知或自指的死亡事件接收者")
	if not errors.is_empty():
		return _failure("RESIDENT_LIFECYCLE_SAVE_INVALID", errors)
	return {
		"ok": true,
		"residents": restored,
	}


func _resident_state_errors(
	state: Dictionary,
	index: int,
	event_ids: Dictionary,
) -> Array[String]:
	var errors: Array[String] = []
	var label := "居民生命周期存档 residents[%d]" % index
	if not _has_exact_keys(state, RESIDENT_STATE_KEYS):
		errors.append("%s 字段不完整或包含未知字段" % label)
	var resident_id := String(state.get("residentId", ""))
	var resident_name := String(state.get("residentName", ""))
	var status := String(state.get("status", ""))
	if resident_id.strip_edges().is_empty():
		errors.append("%s residentId 无效" % label)
	if resident_name.strip_edges().is_empty():
		errors.append("%s residentName 无效" % label)
	if status not in VALID_STATUSES:
		errors.append("%s status 无效" % label)
	if typeof(state.get("revision")) != TYPE_INT or int(state.get("revision", 0)) < 1:
		errors.append("%s revision 无效" % label)
	var home_anchor_value: Variant = state.get("homeAnchor")
	if not home_anchor_value is Dictionary:
		errors.append("%s homeAnchor 必须是对象" % label)
	else:
		errors.append_array(_home_anchor_errors(home_anchor_value as Dictionary))
	var death_event_value: Variant = state.get("deathEvent")
	var death_event: Dictionary = {}
	var recipient_value: Variant = state.get("recipientResidentIds")
	var delivered_value: Variant = state.get("deliveredResidentIds")
	if not death_event_value is Dictionary:
		errors.append("%s deathEvent 必须是对象" % label)
	else:
		death_event = (death_event_value as Dictionary).duplicate(true)
	if not recipient_value is Array or not delivered_value is Array:
		errors.append("%s 的死亡事件接收记录必须是数组" % label)
		return errors
	var recipients := _unique_string_array(recipient_value as Array)
	var delivered := _unique_string_array(delivered_value as Array)
	if recipients.size() != (recipient_value as Array).size():
		errors.append("%s 的死亡事件接收者无效或重复" % label)
	if delivered.size() != (delivered_value as Array).size():
		errors.append("%s 的死亡事件已交付居民无效或重复" % label)
	for delivered_id in delivered:
		if not recipients.has(delivered_id):
			errors.append("%s 包含不属于本次事件的已交付居民" % label)
	if status == STATUS_ALIVE:
		if not death_event.is_empty():
			errors.append("%s 活着时不能保留死亡事件" % label)
		if not recipients.is_empty() or not delivered.is_empty():
			errors.append("%s 活着时不能保留死亡事件交付记录" % label)
	else:
		var event := death_event
		errors.append_array(_death_event_errors(event, resident_id, resident_name))
		var event_id := String(event.get("event_id", ""))
		if not event_id.is_empty():
			if event_ids.has(event_id):
				errors.append("居民生命周期存档死亡事件编号重复：%s" % event_id)
			else:
				event_ids[event_id] = true
	return errors


func _death_event_errors(
	event: Dictionary,
	resident_id: String,
	resident_name: String,
) -> Array[String]:
	var errors: Array[String] = []
	if not _has_exact_keys(event, DEATH_EVENT_KEYS):
		errors.append("死亡事件字段不完整或包含未知字段")
	if String(event.get("event_id", "")).strip_edges().is_empty():
		errors.append("死亡事件缺少稳定事件编号")
	if String(event.get("type", "")) != EVENT_TYPE_DEATH:
		errors.append("死亡事件类型无效")
	if not event.get("time") is Dictionary or not _valid_world_time(
		event.get("time") as Dictionary,
	):
		errors.append("死亡事件缺少世界时间")
	if String(event.get("deceased_resident_id", "")) != resident_id:
		errors.append("死亡事件居民编号与生命周期状态不一致")
	if String(event.get("deceased_resident_name", "")) != resident_name:
		errors.append("死亡事件居民姓名与生命周期状态不一致")
	if String(event.get("reason", "")).strip_edges().is_empty():
		errors.append("死亡事件缺少 World 已确认的原因")
	var location_value: Variant = event.get("location")
	if location_value is not Dictionary:
		errors.append("死亡事件缺少 World 已确认的发生地点")
	else:
		errors.append_array(_location_errors(location_value as Dictionary))
	return errors


func _location_errors(location: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not _has_exact_keys(location, HOME_ANCHOR_KEYS):
		errors.append("死亡发生地点字段不完整或包含未知字段")
		return errors
	for key in ["spaceId", "regionId", "placeName"]:
		if String(location.get(key, "")).strip_edges().is_empty():
			errors.append("死亡发生地点 %s 无效" % key)
	if location.get("position") is not Vector2:
		errors.append("死亡发生地点 position 必须是 Vector2")
	return errors


func _home_anchor_errors(home_anchor: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not _has_exact_keys(home_anchor, HOME_ANCHOR_KEYS):
		errors.append("居民住处锚点字段不完整或包含未知字段")
		return errors
	for key in ["spaceId", "regionId", "placeName"]:
		if String(home_anchor.get(key, "")).strip_edges().is_empty():
			errors.append("居民住处锚点 %s 无效" % key)
	if not home_anchor.get("position") is Vector2:
		errors.append("居民住处锚点 position 必须是 Vector2")
	return errors


func _valid_world_time(world_time: Dictionary) -> bool:
	if typeof(world_time.get("day")) != TYPE_INT or int(world_time.get("day", 0)) < 1:
		return false
	var clock := String(world_time.get("clock", ""))
	var parts := clock.split(":", false)
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return false
	var hour := int(parts[0])
	var minute := int(parts[1])
	if hour < 0 or hour > 23 or minute < 0 or minute > 59:
		return false
	return not String(world_time.get("period", "")).strip_edges().is_empty()


func _resident_id_for_death_event(event_id: String) -> String:
	if event_id.is_empty():
		return ""
	for resident_id in _sorted_resident_ids():
		var event := (
			(_residents[resident_id] as Dictionary).get(
				"deathEvent",
				{},
			) as Dictionary
		)
		if String(event.get("event_id", "")) == event_id:
			return resident_id
	return ""


func _sorted_resident_ids() -> Array[String]:
	var result: Array[String] = []
	for resident_id_value: Variant in _residents:
		result.append(String(resident_id_value))
	result.sort()
	return result


func _unique_string_array(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		if not value is String:
			continue
		var normalized := String(value).strip_edges()
		if normalized.is_empty() or result.has(normalized):
			continue
		result.append(normalized)
	result.sort()
	return result


func _has_exact_keys(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size():
		return false
	for key: Variant in keys:
		if not value.has(key):
			return false
	return true


func _failure(error_code: String, errors: Array[String]) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"errors": errors.duplicate(),
	}
