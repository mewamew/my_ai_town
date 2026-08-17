class_name TownStaffingMatterProjection
extends RefCounted


static func plan(
	snapshot: Dictionary,
	resident_order: Array[String],
	primary_occupation_by_resident: Dictionary,
	available_resident_ids: Array[String],
	max_candidates: int,
	source_revision: int,
	absolute_minute: int,
) -> Dictionary:
	var available := {}
	for resident_id: String in available_resident_ids:
		available[resident_id] = true
	var sources: Array[Dictionary] = []
	var signature: Array = []
	for post_value: Variant in snapshot.get("posts", []) as Array:
		if post_value is not Dictionary:
			continue
		var post := post_value as Dictionary
		var occupation_id := String(post.get("occupationId", ""))
		var vacant := String(post.get("status", "")) == "vacant"
		var candidate_ids: Array[String] = []
		if vacant:
			candidate_ids = candidate_resident_ids(
				snapshot,
				occupation_id,
				resident_order,
				primary_occupation_by_resident,
				available,
				max_candidates,
			)
		signature.append([
			occupation_id,
			String(post.get("label", "")),
			String(post.get("primaryWorkplacePlace", "")),
			vacant,
			String(post.get("vacancyEffect", "")),
			String(post.get("staffingEntryRule", "")),
			candidate_ids,
		])
		sources.append({
			"vacancy_id": "job-vacancy:%s" % occupation_id,
			"source_revision": source_revision,
			"occupation_id": occupation_id,
			"occupation_label": String(post.get("label", "")),
			"primary_place_id": String(post.get("primaryWorkplacePlace", "")),
			"vacant": vacant,
			"temporary_absence": not (
				post.get("temporarilyAbsentResidentIds", []) as Array
			).is_empty(),
			"vacancy_effect": String(post.get("vacancyEffect", "")),
			"staffing_entry_rule": String(post.get("staffingEntryRule", "")),
			"candidate_resident_ids": candidate_ids,
			"expires_at": absolute_minute + 10080,
			"source_event_ids": [],
		})
	signature.sort_custom(
		func(left: Array, right: Array) -> bool:
			return String(left[0]) < String(right[0])
	)
	return {"signature": signature, "sources": sources}


static func candidate_resident_ids(
	snapshot: Dictionary,
	target_occupation_id: String,
	resident_order: Array[String],
	primary_occupation_by_resident: Dictionary,
	available_residents: Dictionary,
	max_candidates: int,
) -> Array[String]:
	var seen := {}
	var result: Array[String] = []
	for post_value: Variant in snapshot.get("posts", []) as Array:
		if post_value is not Dictionary:
			continue
		var post := post_value as Dictionary
		if String(post.get("status", "")) != "duplicate":
			continue
		for resident_value: Variant in post.get("assignedResidentIds", []) as Array:
			var resident_id := String(resident_value)
			if not seen.has(resident_id):
				seen[resident_id] = true
				result.append(resident_id)
	for resident_value: Variant in snapshot.get("unassignedResidentIds", []) as Array:
		var resident_id := String(resident_value)
		if not seen.has(resident_id) and available_residents.has(resident_id):
			seen[resident_id] = true
			result.append(resident_id)
	for resident_id: String in resident_order:
		if (
			seen.has(resident_id)
			or not available_residents.has(resident_id)
			or String(primary_occupation_by_resident.get(resident_id, ""))
			== target_occupation_id
		):
			continue
		seen[resident_id] = true
		result.append(resident_id)
	if result.size() > max_candidates:
		result.resize(max_candidates)
	return result
