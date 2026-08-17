class_name TownConversationConflictBridge
extends RefCounted


static func prepare_intent(
	world: Object,
	resident: Dictionary,
	intent: Dictionary,
	wake_snapshot: Dictionary,
	allow_reserved_action_id := false,
) -> Dictionary:
	if intent.is_empty():
		return {"ok": false, "errors": ["对话后的冲突意图为空"]}
	var prepared := world.ACTION_PREPARATION_RUNTIME.prepare(world,
		resident,
		intent,
		allow_reserved_action_id,
		wake_snapshot,
	) as Dictionary
	if prepared.get("ok") != true:
		return prepared
	return {
		"ok": true,
		"action": (prepared.get("action", {}) as Dictionary).duplicate(true),
	}


static func activate_after_reply(
	world: Object,
	resident_id: String,
	resident: Dictionary,
	intent: Dictionary,
	wake_snapshot: Dictionary,
	story_provenance: Dictionary,
) -> Dictionary:
	var prepared := prepare_intent(world, resident, intent, wake_snapshot, true)
	if prepared.get("ok") != true:
		return prepared
	world.CONFIRMED_ACTION_ACTIVATION_RUNTIME.activate_conflict(world,
		resident_id,
		resident,
		prepared.get("action", {}) as Dictionary,
		{"storyProvenance": story_provenance.duplicate(true)},
		"",
		{},
	)
	return {"ok": true, "action": prepared.get("action", {}).duplicate(true)}
