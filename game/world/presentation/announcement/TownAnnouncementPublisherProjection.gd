class_name TownAnnouncementPublisherProjection
extends RefCounted


static func project(
	world,
	announcements: Array[Dictionary],
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Dictionary in announcements:
		var announcement := value.duplicate(true)
		var publisher := _publisher(world, String(announcement.get("publisher_id", "")))
		announcement["publisher_name"] = String(publisher.get("name", ""))
		announcement["publisher_role"] = String(publisher.get("role", ""))
		announcement["publisher_type"] = String(publisher.get("type", ""))
		result.append(announcement)
	return result


static func _publisher(world, publisher_id: String) -> Dictionary:
	var normalized := publisher_id.strip_edges()
	if normalized == world.player_avatar_id():
		return {
			"name": String(world.actor_presentation_state.player_avatar.get("name", "旅行者")),
			"role": "旅行者",
			"type": "traveler",
		}
	if world.resident_registry.records.has(normalized):
		return {
			"name": world.resident_display_name(normalized),
			"role": "居民",
			"type": "resident",
		}
	if normalized == "world":
		return {
			"name": "小镇系统",
			"role": "系统",
			"type": "system",
		}
	if normalized == "legacy-player":
		return {
			"name": "早期玩家",
			"role": "历史发布者",
			"type": "legacy",
		}
	return {
		"name": "未知发布者",
		"role": "未知身份",
		"type": "unknown",
	}
