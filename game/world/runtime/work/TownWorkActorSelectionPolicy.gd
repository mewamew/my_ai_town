class_name TownWorkActorSelectionPolicy
extends RefCounted


## 工作来源只从真实在场、当前可工作的对应居民中选择执行者。
## 轮换依据来自业务来源，而不是固定使用居民表里的第一人。


static func choose_qualified_actor(
	world,
	occupation_id: String,
	selection_key: String,
	preferred_resident_id := "",
) -> String:
	var preferred_id := preferred_resident_id.strip_edges()
	if _is_available_qualified_resident(world, preferred_id, occupation_id):
		return preferred_id
	var candidates := qualified_actor_ids(world, occupation_id)
	if candidates.is_empty():
		return ""
	return choose_from_candidates(candidates, _stable_selection_index(selection_key))


static func qualified_actor_ids(world, occupation_id: String) -> Array[String]:
	var result: Array[String] = []
	var normalized_occupation_id := occupation_id.strip_edges()
	if normalized_occupation_id.is_empty():
		return result
	for resident_id: String in world.resident_registry.order:
		if _is_available_qualified_resident(
			world,
			resident_id,
			normalized_occupation_id,
		):
			result.append(resident_id)
	return result


static func choose_from_candidates(
	candidates: Array[String],
	selection_index: int,
) -> String:
	if candidates.is_empty():
		return ""
	return candidates[posmod(selection_index, candidates.size())]


static func _is_available_qualified_resident(
	world,
	resident_id: String,
	occupation_id: String,
) -> bool:
	if resident_id.is_empty() or not world.resident_registry.records.has(resident_id):
		return false
	if not world.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.can_work_occupation(world, resident_id, occupation_id):
		return false
	return world.OCCUPATION_RESIDENT_CONTEXT_RUNTIME.available_for_work(world,
		world.resident_registry.records.get(resident_id, {}) as Dictionary,
	)


static func _stable_selection_index(selection_key: String) -> int:
	var hash_value := 0
	for character: String in selection_key:
		hash_value = posmod(
			hash_value * 31 + character.unicode_at(0),
			2147483647,
		)
	return hash_value
