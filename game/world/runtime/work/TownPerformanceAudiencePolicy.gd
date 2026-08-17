class_name TownPerformanceAudiencePolicy
extends RefCounted


static func audience_ids(
	performer_id: String,
	place_id: String,
	day_index: int,
	residents: Dictionary,
	resident_order: Array[String],
	present_resident_ids: Array[String],
) -> Array[String]:
	if day_index < 0:
		return []
	var performer := residents.get(performer_id, {}) as Dictionary
	var performer_position := performer.get("position", Vector2.ZERO) as Vector2
	var result: Array[String] = []
	for resident_id: String in resident_order:
		if resident_id == performer_id or not present_resident_ids.has(resident_id):
			continue
		var resident := residents.get(resident_id, {}) as Dictionary
		var action := resident.get("currentAction", {}) as Dictionary
		if (
			String(resident.get("currentPlace", "")) == place_id
			and String(action.get("type", "")) == "待着"
			and int(action.get("performanceDayIndex", -1)) == day_index
			and (resident.get("position", Vector2.ZERO) as Vector2).distance_to(
				performer_position,
			) <= 640.0
		):
			result.append(resident_id)
	result.sort()
	return result
