class_name TownAgentInitializationProjection
extends RefCounted


static func places(host) -> Array[Dictionary]:
	return host.place_presentation_query.agent_places(
		host.world_definition.world_data,
		host.world_definition.owners,
		host.resident_registry.name_by_id,
		host.player_avatar_id(),
		String(host.actor_presentation_state.player_avatar.get("name", "")),
	)


static func build(host, resident_id: String) -> Dictionary:
	var runtime := host.resident_registry.records[resident_id] as Dictionary
	var attributes := (runtime.get("attributes", {}) as Dictionary).duplicate(true)
	attributes.erase("appearance")
	var soul_profiles := host.world_definition.opening.get(
		"agentSoulProfiles",
		{},
	) as Dictionary
	var soul_profile := (
		(soul_profiles.get(resident_id, {}) as Dictionary).duplicate(true)
		if soul_profiles.get(resident_id, {}) is Dictionary
		else {}
	)
	var me := {
		"resident_id": resident_id,
		"attributes": attributes,
		"social_state": (
			runtime.get("socialState", {}) as Dictionary
		).duplicate(true),
	}
	if not soul_profile.is_empty():
		me["soul_profile"] = soul_profile
	var others: Array[Dictionary] = []
	for other_id in host.resident_registry.order:
		if other_id == resident_id:
			continue
		var other := host.resident_registry.records[other_id] as Dictionary
		var other_attributes := other.get("attributes", {}) as Dictionary
		var other_social := other.get("socialState", {}) as Dictionary
		others.append({
			"resident_id": other_id,
			"name": String(other_attributes.get("name", "")),
			"gender": String(other_attributes.get("gender", "")),
			"age": int(other_attributes.get("age", 0)),
			"job": String(other_social.get("job", "")),
			"home": String(other_social.get("home", "")),
			"workplace": String(other_social.get("workplace", "")),
			"lifecycle_status": String(
				(host._resident_lifecycle.get_resident_state(
					other_id,
				) as Dictionary).get("status", "alive"),
			),
		})
	return {
		"me": me,
		"residents": others,
		"places": places(host),
	}
