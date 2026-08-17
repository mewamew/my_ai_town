class_name TownAnimalFactRuntime
extends RefCounted


var _facts: Dictionary = {}


func reset() -> void:
	_facts.clear()


func restore_prepared(prepared: Dictionary) -> void:
	_facts = prepared.duplicate(true)


func save_snapshot() -> Dictionary:
	return _facts.duplicate(true)


func fact(animal_id: String) -> Dictionary:
	return (_facts.get(animal_id, {}) as Dictionary).duplicate(true)


func set_fact(animal_id: String, value: Dictionary) -> void:
	_facts[animal_id] = value.duplicate(true)


func prepare_upsert(
	state: Dictionary,
	absolute_minute: int,
	membership_for_position: Callable,
) -> Dictionary:
	for field: String in [
		"animal_id",
		"display_name",
		"species",
		"exists",
		"position",
		"generation",
	]:
		if not state.has(field):
			return _failure(
				"ANIMAL_FACT_INVALID",
				"动物存在事实缺少字段：%s" % field,
			)
	var animal_id := String(state.get("animal_id", "")).strip_edges()
	var display_name := String(state.get("display_name", "")).strip_edges()
	var species := String(state.get("species", "")).strip_edges()
	var position_value: Variant = state.get("position")
	if (
		animal_id.is_empty()
		or display_name.is_empty()
		or species.is_empty()
		or state.get("exists") is not bool
		or position_value is not Vector2
		or not (position_value as Vector2).is_finite()
		or state.get("generation") is not int
		or int(state.get("generation", -1)) < 0
	):
		return _failure("ANIMAL_FACT_INVALID", "动物存在事实字段无效")
	var exists := bool(state.get("exists"))
	var position := position_value as Vector2
	var previous := fact(animal_id)
	if not exists and previous.is_empty():
		return {
			"ok": true,
			"alreadyAbsent": true,
			"changed": false,
			"animal": {},
		}
	var place_id := String(previous.get("place_id", ""))
	if exists:
		place_id = String(membership_for_position.call(position))
		if place_id.is_empty():
			return _failure(
				"ANIMAL_FACT_OUTSIDE_WORLD",
				"动物位置不属于当前小镇",
			)
	var public_attention := bool(previous.get("public_attention", false))
	var source_revision := int(previous.get("source_revision", 0))
	var meaningful_change := (
		previous.is_empty()
		or bool(previous.get("exists", false)) != exists
		or String(previous.get("place_id", "")) != place_id
		or int(previous.get("generation", -1)) != int(state.get("generation"))
	)
	var attention_fact_changed := (
		not previous.is_empty()
		and public_attention
		and (not exists or String(previous.get("place_id", "")) != place_id)
	)
	if attention_fact_changed:
		source_revision += 1
		if not exists:
			public_attention = false
	var prepared_fact := {
		"animal_id": animal_id,
		"display_name": display_name,
		"species": species,
		"exists": exists,
		"place_id": place_id,
		"position": position,
		"generation": int(state.get("generation")),
		"public_attention": public_attention,
		"source_revision": source_revision,
		"expires_at": int(previous.get("expires_at", -1)),
		"source_event_ids": (
			previous.get("source_event_ids", []) as Array
		).duplicate(),
		"updated_at": absolute_minute,
	}
	set_fact(animal_id, prepared_fact)
	return {
		"ok": true,
		"alreadyAbsent": false,
		"changed": meaningful_change,
		"attentionFactChanged": attention_fact_changed,
		"previous": previous,
		"animal": prepared_fact.duplicate(true),
	}


func prepare_public_attention(
	animal_id: String,
	active: bool,
	expires_at: int,
	source_event_ids: Array,
	absolute_minute: int,
) -> Dictionary:
	var normalized_id := animal_id.strip_edges()
	var current := fact(normalized_id)
	if current.is_empty() or not bool(current.get("exists", false)):
		return _failure(
			"ANIMAL_FACT_UNKNOWN",
			"只能让当前确实存在的动物成为公共关注",
		)
	if active and expires_at <= absolute_minute:
		return _failure(
			"ANIMAL_FACT_INVALID",
			"动物公共关注期限必须晚于当前时间",
		)
	var normalized_event_ids: Array[String] = []
	for event_value: Variant in source_event_ids:
		if event_value is not String:
			return _failure(
				"ANIMAL_FACT_INVALID",
				"动物关注来源事件编号必须是文本",
			)
		var event_id := String(event_value).strip_edges()
		if not event_id.is_empty() and not normalized_event_ids.has(event_id):
			normalized_event_ids.append(event_id)
	normalized_event_ids.sort()
	var unchanged: bool = (
		bool(current.get("public_attention", false)) == active
		and int(current.get("expires_at", -1)) == expires_at
		and current.get("source_event_ids", []) == normalized_event_ids
	)
	if unchanged:
		return {"ok": true, "changed": false, "animal": current}
	current["public_attention"] = active
	current["expires_at"] = expires_at
	current["source_event_ids"] = normalized_event_ids
	current["source_revision"] = int(current.get("source_revision", 0)) + 1
	current["updated_at"] = absolute_minute
	set_fact(normalized_id, current)
	return {"ok": true, "changed": true, "animal": current}


func public_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var animal_ids: Array[String] = []
	for animal_id_value: Variant in _facts:
		animal_ids.append(String(animal_id_value))
	animal_ids.sort()
	for animal_id: String in animal_ids:
		result.append(fact(animal_id))
	return result


func expire_public_attention(absolute_minute: int) -> bool:
	var changed := false
	for animal_id_value: Variant in _facts:
		var animal_id := String(animal_id_value)
		var current := fact(animal_id)
		if (
			not bool(current.get("public_attention", false))
			or int(current.get("expires_at", -1)) > absolute_minute
		):
			continue
		current["public_attention"] = false
		current["source_revision"] = int(current.get("source_revision", 0)) + 1
		current["updated_at"] = absolute_minute
		set_fact(animal_id, current)
		changed = true
	return changed


func attention_sync_payload(value: Dictionary) -> Dictionary:
	return {
		"animal_id": String(value.get("animal_id", "")),
		"source_revision": int(value.get("source_revision", 0)),
		"exists": bool(value.get("exists", false)),
		"public_attention": bool(value.get("public_attention", false)),
		"place_id": String(value.get("place_id", "")),
		"expires_at": int(value.get("expires_at", -1)),
		"source_event_ids": (
			value.get("source_event_ids", []) as Array
		).duplicate(),
	}


func clear_public_attention(animal_id: String, absolute_minute: int) -> Dictionary:
	var current := fact(animal_id)
	if current.is_empty() or not bool(current.get("public_attention", false)):
		return {}
	current["public_attention"] = false
	current["source_revision"] = int(current.get("source_revision", 0)) + 1
	current["updated_at"] = absolute_minute
	set_fact(animal_id, current)
	return current


func pet_attention_request(
	resident_id: String,
	action: Dictionary,
	absolute_minute: int,
) -> Dictionary:
	if String(action.get("verb", "")) != "摸摸":
		return {}
	var prop_id := String(action.get("dynamicPropId", ""))
	var prefix := "dynamic_animal_"
	if not prop_id.begins_with(prefix):
		return {}
	var animal_id := prop_id.trim_prefix(prefix)
	var current := fact(animal_id)
	if current.is_empty() or not bool(current.get("exists", false)):
		return {}
	var event_ids := (current.get("source_event_ids", []) as Array).duplicate()
	var event_id := "animal-pet:%s:%s" % [
		resident_id,
		String(action.get("action_id", "")),
	]
	if not event_ids.has(event_id):
		event_ids.append(event_id)
	return {
		"animalId": animal_id,
		"animal": current,
		"expiresAt": maxi(
			int(current.get("expires_at", -1)),
			absolute_minute + 60,
		),
		"sourceEventIds": event_ids,
	}


func _failure(error_code: String, error: String) -> Dictionary:
	return {"ok": false, "errorCode": error_code, "errors": [error]}
