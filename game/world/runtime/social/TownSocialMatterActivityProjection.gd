class_name TownSocialMatterActivityProjection
extends RefCounted


const ACTION_PRESENTATION := preload(
	"res://world/runtime/presentation/TownActionPresentationSemantics.gd"
)
const SOCIAL_JUDGMENTS := preload(
	"res://world/runtime/social/TownSocialJudgments.gd"
)
const PUBLIC_PROJECTION := preload(
	"res://world/runtime/social/TownSocialMatterPublicProjection.gd"
)


static func build(host) -> Dictionary:
	if not host._running:
		return {
			"revision": maxi(host._world_revision, 0),
			"items": [],
			"history": [],
		}
	if host.social_coordination_state.has_public_activity_cache(host._world_revision):
		return host.social_coordination_state.public_activity_cache_snapshot()
	var active_activities := {}
	var bulletin_matter_ids := {}
	for resident_id: String in host.resident_registry.order:
		var resident := host.resident_registry.records.get(resident_id, {}) as Dictionary
		var action := resident.get("currentAction", {}) as Dictionary
		if action.is_empty():
			continue
		active_activities[resident_id] = {
			"actionId": String(action.get("action_id", "")),
			"actionType": String(action.get("type", "")),
			"activityId": "",
			"phase": "",
		}
		var execution := host._activity_runtime.execution_for_action(
			resident_id,
			String(action.get("action_id", "")),
		) as Dictionary
		if execution.is_empty():
			continue
		var cue_value: Variant = ACTION_PRESENTATION._resident_activity_cue(
			host,
			resident,
		)
		var cue := cue_value as Dictionary if cue_value is Dictionary else {}
		active_activities[resident_id] = {
			"actionId": String(action.get("action_id", "")),
			"actionType": String(action.get("type", "")),
			"activityId": String(execution.get("activityId", "")),
			"phase": String(cue.get("phase", "")),
		}
		if String(execution.get("activityId", "")) != SOCIAL_JUDGMENTS.BULLETIN_READ_ACTIVITY_ID:
			continue
		var announcement_id := first_unread_announcement_id(host, resident_id)
		var matter_id := community_announcement_matter_id(host, announcement_id)
		if not matter_id.is_empty():
			bulletin_matter_ids[resident_id] = matter_id
	var projection := PUBLIC_PROJECTION.build(
		host._social_matters.list_matters(true) as Array,
		host.resident_registry.name_by_id,
		active_activities,
		bulletin_matter_ids,
		host._world_revision,
		int(host._environment.get_absolute_minute()),
	)
	return host.social_coordination_state.store_public_activity_cache(
		projection,
		host._world_revision,
	)


static func first_unread_announcement_id(host, resident_id: String) -> String:
	var known_ids := {}
	for knowledge_value: Variant in host._community_bulletin.knowledge_for(
		resident_id,
	) as Array:
		var knowledge := knowledge_value as Dictionary
		known_ids[String(knowledge.get("announcement_id", ""))] = true
	for announcement: Dictionary in host._community_bulletin.get_announcements(
		false,
	) as Array[Dictionary]:
		var announcement_id := String(announcement.get("announcement_id", ""))
		if not known_ids.has(announcement_id):
			return announcement_id
	return ""


static func community_announcement_matter_id(
	host,
	announcement_id: String,
) -> String:
	var normalized := announcement_id.strip_edges()
	if normalized.is_empty():
		return ""
	for announcement: Dictionary in host._community_bulletin.get_announcements(
		true,
	) as Array[Dictionary]:
		if String(announcement.get("announcement_id", "")) == normalized:
			return String(announcement.get("matter_id", ""))
	return ""
