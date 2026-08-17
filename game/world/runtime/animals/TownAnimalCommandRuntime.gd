class_name TownAnimalCommandRuntime
extends RefCounted


const WORLD_LOG_COMMIT_RUNTIME := preload(
	"res://world/runtime/log/TownWorldLogCommitRuntime.gd"
)


static func upsert_presence(
	host,
	state: Dictionary,
	place_for_position: Callable,
) -> Dictionary:
	if not host._running:
		return host._command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var prepared: Dictionary = host._animal_fact_runtime.prepare_upsert(
		state,
		int(host._environment.get_absolute_minute()),
		place_for_position,
	)
	if prepared.get("ok") != true:
		return host._command_failure(
			String(prepared.get("errorCode", "ANIMAL_FACT_INVALID")),
			prepared.get("errors", []) as Array,
		)
	if bool(prepared.get("alreadyAbsent", false)):
		return host._decorate_command_result({
			"ok": true,
			"changed": false,
			"status": "already_absent",
			"animal": {},
		})
	var fact := prepared.get("animal", {}) as Dictionary
	var previous := prepared.get("previous", {}) as Dictionary
	var meaningful_change := bool(prepared.get("changed", false))
	if bool(prepared.get("attentionFactChanged", false)):
		var synced := sync_attention_fact(host, fact)
		if synced.get("ok") != true:
			return synced
	if meaningful_change:
		host._bump_world_revision()
		var animal_event_type := "动物状态更新"
		if previous.is_empty() and bool(fact.get("exists", false)):
			animal_event_type = "动物出现"
		elif bool(previous.get("exists", false)) and not bool(fact.get("exists", false)):
			animal_event_type = "动物离开"
		elif String(previous.get("place_id", "")) != String(fact.get("place_id", "")):
			animal_event_type = "动物地点变化"
		WORLD_LOG_COMMIT_RUNTIME.append_animal(host, animal_event_type, fact)
	return host._decorate_command_result({
		"ok": true,
		"changed": meaningful_change,
		"status": "updated" if meaningful_change else "position_synced",
		"animal": fact.duplicate(true),
	})


static func set_public_attention(
	host,
	animal_id: String,
	active: bool,
	expires_at: int,
	source_event_ids: Array = [],
) -> Dictionary:
	if not host._running:
		return host._command_failure("WORLD_NOT_RUNNING", ["世界尚未运行"])
	var prepared: Dictionary = host._animal_fact_runtime.prepare_public_attention(
		animal_id,
		active,
		expires_at,
		source_event_ids,
		int(host._environment.get_absolute_minute()),
	)
	if prepared.get("ok") != true:
		return host._command_failure(
			String(prepared.get("errorCode", "ANIMAL_FACT_INVALID")),
			prepared.get("errors", []) as Array,
		)
	var fact := prepared.get("animal", {}) as Dictionary
	if prepared.get("changed") != true:
		return host._decorate_command_result({
			"ok": true,
			"changed": false,
			"animal": fact,
		})
	var synced := sync_attention_fact(host, fact)
	if synced.get("ok") != true:
		return synced
	WORLD_LOG_COMMIT_RUNTIME.append_animal(
		host,
		"动物成为公共关注" if active else "动物不再受关注",
		fact,
	)
	return host._decorate_command_result({
		"ok": true,
		"changed": true,
		"animal": fact.duplicate(true),
		"matter": (
			synced.get("matter", {}) as Dictionary
		).duplicate(true),
	})


static func sync_attention_fact(host, fact: Dictionary) -> Dictionary:
	return host.sync_animal_attention(
		host._animal_fact_runtime.attention_sync_payload(fact),
	)
