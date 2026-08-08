class_name TownConflictKnowledgeProjector
extends RefCounted


const RESULT_SHAPES := preload(
	"res://world/contract/TownWorldResultShapes.gd"
)
const DIRECT_KNOWLEDGE_KINDS: Array[String] = [
	"participant",
	"witness",
]
const KNOWLEDGE_KINDS: Array[String] = [
	"participant",
	"witness",
	"hearsay",
]
const PUBLIC_EVENT_TYPES: Array[String] = [
	"conflict_challenged",
	"conflict_threatened",
	"conflict_apologized",
	"conflict_disengaged",
	"avatar_area_attack_cast",
	"unilateral_hit_confirmed",
	"injury_applied",
	"brawl_started",
	"conflict_intervened",
	"conflict_joined",
	"conflict_left",
	"conflict_ended",
	"treatment_started",
	"treatment_completed",
	"injury_recovered",
]


static func project(
	conflict_event: Dictionary,
	knowledge_kind: String,
	actor_names: Dictionary,
	source_resident_id := "",
) -> Dictionary:
	var source_type := String(
		conflict_event.get("type", ""),
	).strip_edges()
	if source_type not in PUBLIC_EVENT_TYPES:
		return _failure("CONFLICT_KNOWLEDGE_EVENT_NOT_PUBLIC")
	var normalized_kind := knowledge_kind.strip_edges()
	if normalized_kind not in KNOWLEDGE_KINDS:
		return _failure("CONFLICT_KNOWLEDGE_KIND_INVALID")
	var relay_source := String(source_resident_id).strip_edges()
	if normalized_kind == "hearsay" and relay_source.is_empty():
		return _failure("CONFLICT_KNOWLEDGE_SOURCE_REQUIRED")
	if normalized_kind in DIRECT_KNOWLEDGE_KINDS and not relay_source.is_empty():
		return _failure("CONFLICT_DIRECT_KNOWLEDGE_SOURCE_INVALID")
	var conflict_id := String(
		conflict_event.get(
			"rootConflictId",
			conflict_event.get("conflictId", ""),
		),
	).strip_edges()
	var conflict_event_id := String(
		conflict_event.get("eventId", ""),
	).strip_edges()
	if conflict_id.is_empty() or conflict_event_id.is_empty():
		return _failure("CONFLICT_KNOWLEDGE_SOURCE_INVALID")
	var actor_ids := _actor_ids(conflict_event)
	if actor_ids.is_empty():
		return _failure("CONFLICT_KNOWLEDGE_ACTORS_REQUIRED")
	var summary := _summary(conflict_event, actor_names)
	if summary.is_empty():
		return _failure("CONFLICT_KNOWLEDGE_SUMMARY_UNAVAILABLE")
	return {
		"ok": true,
		"errorCode": "",
		"event": {
			"type": "冲突见闻",
			"conflict_id": conflict_id,
			"conflict_event_id": conflict_event_id,
			"conflict_event_type": source_type,
			"knowledge_kind": normalized_kind,
			"source_resident_id": relay_source,
			"source_actor_id": String(
				conflict_event.get("sourceActorId", ""),
			).strip_edges(),
			"subject_id": String(
				conflict_event.get("subjectId", ""),
			).strip_edges(),
			"actor_ids": actor_ids,
			"place_id": String(
				conflict_event.get("placeId", ""),
			).strip_edges(),
			"severity": String(
				conflict_event.get("severity", ""),
			).strip_edges(),
			"summary": summary,
		},
	}


static func is_injury_subject(
	event: Dictionary,
	resident_id: String,
) -> bool:
	if (
		String(event.get("type", "")) != "冲突见闻"
		or String(event.get("knowledge_kind", "")) != "participant"
		or String(event.get("conflict_event_type", "")) != "injury_applied"
	):
		return false
	var subject_id := String(event.get("subject_id", "")).strip_edges()
	if not subject_id.is_empty():
		return subject_id == resident_id
	# 兼容旧存档：参与者中只有非攻击方可以被视为伤者。
	return (
		(event.get("actor_ids", []) as Array).has(resident_id)
		and String(event.get("source_actor_id", "")).strip_edges()
		!= resident_id
	)


static func _actor_ids(event: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in event.get("actorIds", []) as Array:
		var actor_id := String(value).strip_edges()
		if not actor_id.is_empty() and not result.has(actor_id):
			result.append(actor_id)
	for value: Variant in [
		event.get("sourceActorId", ""),
		event.get("subjectId", ""),
	]:
		var actor_id := String(value).strip_edges()
		if not actor_id.is_empty() and not result.has(actor_id):
			result.append(actor_id)
	return result


static func _summary(event: Dictionary, actor_names: Dictionary) -> String:
	var source_type := String(event.get("type", ""))
	var source_id := String(event.get("sourceActorId", ""))
	var subject_id := String(event.get("subjectId", ""))
	var source_name := _actor_name(source_id, actor_names)
	var subject_name := _actor_name(subject_id, actor_names)
	var actor_ids := _actor_ids(event)
	var participants := _actor_names(actor_ids, actor_names)
	match source_type:
		"conflict_challenged":
			return "%s当面质问了%s：%s" % [
				source_name,
				subject_name,
				String(event.get("reason", "")).strip_edges(),
			]
		"conflict_threatened":
			return "%s在争执中威胁了%s：%s" % [
				source_name,
				subject_name,
				String(event.get("reason", "")).strip_edges(),
			]
		"conflict_apologized":
			return "%s向%s道歉，争执没有继续升级。" % [
				source_name,
				subject_name,
			]
		"conflict_disengaged":
			return "%s离开了与%s的争执。" % [source_name, subject_name]
		"avatar_area_attack_cast":
			if actor_ids.size() <= 1:
				return ""
			var targets := actor_ids.duplicate()
			targets.erase(source_id)
			return "%s攻击了%s。" % [
				source_name,
				_joined_people(_actor_names(targets, actor_names)),
			]
		"unilateral_hit_confirmed":
			return "%s攻击了%s。" % [source_name, subject_name]
		"injury_applied":
			var injury_severity := "重伤" if String(event.get("severity", "")) == "heavy" else "轻伤"
			if String(event.get("sourceKind", "")) == "avatar_intent" and not source_id.is_empty():
				return "%s攻击了%s，造成%s。" % [source_name, subject_name, injury_severity]
			return "%s受了%s。" % [subject_name, injury_severity]
		"brawl_started":
			return "%s打了起来。" % _joined_people(participants)
		"conflict_intervened":
			return "%s出面调停了这场冲突。" % source_name
		"conflict_joined":
			return "%s加入了这场冲突。" % source_name
		"conflict_left":
			return "%s离开了这场冲突。" % source_name
		"conflict_ended":
			return "%s的冲突已经结束。" % _joined_people(participants)
		"treatment_started":
			return "%s开始接受治疗。" % subject_name
		"treatment_completed":
			return "%s的重伤经过治疗已经减轻。" % subject_name
		"injury_recovered":
			return "%s的伤势已经恢复。" % subject_name
	return ""


static func _actor_names(
	actor_ids: Array[String],
	actor_names: Dictionary,
) -> Array[String]:
	var result: Array[String] = []
	for actor_id: String in actor_ids:
		var actor_name := _actor_name(actor_id, actor_names)
		if not result.has(actor_name):
			result.append(actor_name)
	return result


static func _actor_name(actor_id: String, actor_names: Dictionary) -> String:
	var actor_name := String(actor_names.get(actor_id, "")).strip_edges()
	return actor_name if not actor_name.is_empty() else "一位居民"


static func _joined_people(names: Array[String]) -> String:
	if names.is_empty():
		return "几位居民"
	if names.size() == 1:
		return names[0]
	if names.size() == 2:
		return "%s和%s" % [names[0], names[1]]
	return "%s等%d人" % [names[0], names.size()]


static func _failure(error_code: String) -> Dictionary:
	return RESULT_SHAPES.failure(error_code)
