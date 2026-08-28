class_name TownSessionSaveManifest
extends RefCounted


const SCHEMA := "town-session-save-manifest"
const SCHEMA_VERSION := TownSaveSchemaRegistry.MANIFEST_SCHEMA_VERSION
const LEGACY_SCHEMA_VERSION := TownSaveSchemaRegistry.MANIFEST_LEGACY_SCHEMA_VERSION
const PREVIOUS_SCHEMA_VERSION := TownSaveSchemaRegistry.MANIFEST_PREVIOUS_SCHEMA_VERSION
const WORLD_SCHEMA := "town-world-save"
const WORLD_SCHEMA_VERSIONS: Array[int] = [1, 2]
const WORLD_LOG_SCHEMA := "town-world-log-snapshot"
const MAX_SAFE_INTEGER := 9007199254740991
const CONTEXT_FIELDS: Array[String] = ["slot_id", "session_id", "save_revision"]
const LEGACY_MANIFEST_FIELDS: Array[String] = [
	"schema",
	"schema_version",
	"state",
	"slot_id",
	"session_id",
	"save_revision",
	"saved_at",
	"session_config_ref",
	"session_config_sha256",
	"resident_ids",
	"components",
]
const MANIFEST_FIELDS: Array[String] = LEGACY_MANIFEST_FIELDS + [
	"resident_messages",
]
const RESIDENT_MESSAGE_FIELDS: Array[String] = [
	"message_id",
	"resident_id",
	"resident_name",
	"content",
]
const MAX_RESIDENT_MESSAGES := 2
const MAX_RESIDENT_MESSAGE_NAME_LENGTH := 64
const MAX_RESIDENT_MESSAGE_LENGTH := 96
const WORLD_FIELDS: Array[String] = [
	"snapshot_ref",
	"snapshot_sha256",
	"world_revision",
	"schema",
	"schema_version",
	"world_data_version",
	"day",
	"transaction_status",
]
const WORLD_BUILD_FIELDS: Array[String] = [
	"snapshotRef",
	"worldRevision",
	"schema",
	"schemaVersion",
	"worldDataVersion",
]
const WORLD_BUILD_FIELDS_WITH_DAY: Array[String] = [
	"snapshotRef",
	"worldRevision",
	"schema",
	"schemaVersion",
	"worldDataVersion",
	"day",
]
const AGENT_FIELDS: Array[String] = ["context", "transaction_status"]
const WORLD_LOG_BUILD_FIELDS: Array[String] = [
	"snapshotRef",
	"snapshotSha256",
	"schema",
	"schemaVersion",
	"timelineId",
	"maxSequence",
	"worldRevision",
]
const WORLD_LOG_FIELDS: Array[String] = [
	"snapshot_ref",
	"snapshot_sha256",
	"schema",
	"schema_version",
	"timeline_id",
	"max_sequence",
	"world_revision",
	"transaction_status",
]


static func validate_context(value: Variant) -> Dictionary:
	var errors: Array[Dictionary] = []
	if not (value is Dictionary):
		return _failure("SESSION_SAVE_CONTEXT_INVALID", [{
			"path": "context",
			"code": "SESSION_SAVE_CONTEXT_INVALID",
		}])
	var context := value as Dictionary
	_reject_unknown_fields(context, CONTEXT_FIELDS, "context", errors)
	var slot_id := _string_or_empty(context.get("slot_id")).strip_edges()
	var session_id := _string_or_empty(context.get("session_id")).strip_edges()
	if (
		not _safe_identifier(slot_id)
		or _string_or_empty(context.get("slot_id")) != slot_id
	):
		errors.append(_error("context.slot_id", "SESSION_SAVE_CONTEXT_INVALID"))
	if (
		not _safe_identifier(session_id)
		or _string_or_empty(context.get("session_id")) != session_id
	):
		errors.append(_error("context.session_id", "SESSION_SAVE_CONTEXT_INVALID"))
	if not _is_non_negative_integer_number(
		context.get("save_revision"),
	):
		errors.append(_error("context.save_revision", "SESSION_SAVE_CONTEXT_INVALID"))
	if not errors.is_empty():
		return _failure("SESSION_SAVE_CONTEXT_INVALID", errors)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"context": {
			"slot_id": slot_id,
			"session_id": session_id,
			"save_revision": int(context.get("save_revision", 0)),
		},
	}


static func validate_slot_id(value: Variant) -> Dictionary:
	var slot_id := _string_or_empty(value).strip_edges()
	if not _safe_identifier(slot_id) or _string_or_empty(value) != slot_id:
		return _failure("SESSION_SAVE_CONTEXT_INVALID", [
			_error("context.slot_id", "SESSION_SAVE_CONTEXT_INVALID"),
		])
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"slotId": slot_id,
	}


static func validate_slot_session(
	slot_value: Variant,
	session_value: Variant,
) -> Dictionary:
	var errors: Array[Dictionary] = []
	var slot_id := _string_or_empty(slot_value).strip_edges()
	var session_id := _string_or_empty(session_value).strip_edges()
	if not _safe_identifier(slot_id) or _string_or_empty(slot_value) != slot_id:
		errors.append(_error("context.slot_id", "SESSION_SAVE_CONTEXT_INVALID"))
	if (
		not _safe_identifier(session_id)
		or _string_or_empty(session_value) != session_id
	):
		errors.append(_error("context.session_id", "SESSION_SAVE_CONTEXT_INVALID"))
	if not errors.is_empty():
		return _failure("SESSION_SAVE_CONTEXT_INVALID", errors)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"slotId": slot_id,
		"sessionId": session_id,
	}


static func resident_ids(value: Variant) -> Dictionary:
	var errors: Array[Dictionary] = []
	var ids: Array[String] = []
	if not (value is Array):
		return _failure("SESSION_SAVE_CONTEXT_INVALID", [{
			"path": "residentIdentities",
			"code": "SESSION_SAVE_CONTEXT_INVALID",
		}])
	for index in (value as Array).size():
		var identity_value: Variant = (value as Array)[index]
		if not (identity_value is Dictionary):
			errors.append(_error(
				"residentIdentities[%d]" % index,
				"SESSION_SAVE_CONTEXT_INVALID",
			))
			continue
		var identity := identity_value as Dictionary
		_reject_unknown_fields(
			identity,
			["residentId", "residentName"],
			"residentIdentities[%d]" % index,
			errors,
		)
		var resident_id_value: Variant = identity.get("residentId")
		var resident_name_value: Variant = identity.get("residentName")
		var resident_id := _string_or_empty(
			resident_id_value
		).strip_edges()
		var resident_name := _string_or_empty(
			resident_name_value
		).strip_edges()
		if (
			not resident_id_value is String
			or not resident_name_value is String
			or resident_id != resident_id_value
			or resident_name != resident_name_value
			or not _safe_resident_identifier(resident_id)
			or resident_name.is_empty()
			or ids.has(resident_id)
		):
			errors.append(_error(
				"residentIdentities[%d]" % index,
				"SESSION_SAVE_CONTEXT_INVALID",
			))
			continue
		ids.append(resident_id)
	ids.sort()
	if ids.is_empty():
		errors.append(_error(
			"residentIdentities",
			"SESSION_SAVE_CONTEXT_INVALID",
		))
	if not errors.is_empty():
		return _failure("SESSION_SAVE_CONTEXT_INVALID", errors)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"residentIds": ids,
	}


static func build(
	context_value: Variant,
	saved_at_value: Variant,
	session_config_ref_value: Variant,
	session_config_sha256_value: Variant,
	resident_id_values: Variant,
	world_component_value: Variant,
	snapshot_sha256_value: Variant,
	resident_message_values: Array = [],
	world_log_component: Dictionary = {},
) -> Dictionary:
	if (
		not context_value is Dictionary
		or not saved_at_value is String
		or not session_config_ref_value is String
		or not session_config_sha256_value is String
		or not resident_id_values is Array
		or not world_component_value is Dictionary
		or not snapshot_sha256_value is String
	):
		return {}
	if (
		not _has_exact_fields(
			world_component_value as Dictionary,
			WORLD_BUILD_FIELDS,
		)
		and not _has_exact_fields(
			world_component_value as Dictionary,
			WORLD_BUILD_FIELDS_WITH_DAY,
		)
	):
		return {}
	if (
		not world_log_component.is_empty()
		and not _has_exact_fields(
			world_log_component,
			WORLD_LOG_BUILD_FIELDS,
		)
	):
		return {}
	var normalized_context := validate_context(context_value)
	if normalized_context.get("ok") != true:
		return {}
	var resident_ids_result := _validate_resident_id_array(resident_id_values)
	if resident_ids_result.get("ok") != true:
		return {}
	var resident_messages_result := validate_resident_messages(
		resident_message_values,
		resident_ids_result.get("residentIds", []) as Array,
	)
	if resident_messages_result.get("ok") != true:
		return {}
	var saved_at := saved_at_value as String
	var session_config_ref := session_config_ref_value as String
	var session_config_sha256 := session_config_sha256_value as String
	var world_component := world_component_value as Dictionary
	var snapshot_sha256 := snapshot_sha256_value as String
	var normalized_world := {
		"snapshot_ref": _string_or_empty(
			world_component.get("snapshotRef")
		),
		"snapshot_sha256": snapshot_sha256,
		"world_revision": _positive_integer_or_zero(
			world_component.get("worldRevision")
		),
		"schema": _string_or_empty(
			world_component.get("schema")
		),
		"schema_version": _positive_integer_or_zero(
			world_component.get("schemaVersion")
		),
		"world_data_version": _positive_integer_or_zero(
			world_component.get("worldDataVersion")
		),
		"day": _positive_integer_or_zero(
			world_component.get("day")
		),
		"transaction_status": "committed",
	}
	var normalized := normalized_context.get("context", {}) as Dictionary
	var has_world_log := not world_log_component.is_empty()
	var normalized_world_log := {
		"snapshot_ref": _string_or_empty(
			world_log_component.get("snapshotRef"),
		),
		"snapshot_sha256": _string_or_empty(
			world_log_component.get("snapshotSha256"),
		),
		"schema": _string_or_empty(world_log_component.get("schema")),
		"schema_version": _positive_integer_or_zero(
			world_log_component.get("schemaVersion"),
		),
		"timeline_id": _string_or_empty(
			world_log_component.get("timelineId"),
		),
		"max_sequence": _positive_integer_or_zero(
			world_log_component.get("maxSequence"),
		),
		"world_revision": _positive_integer_or_zero(
			world_log_component.get("worldRevision"),
		),
		"transaction_status": "committed",
	}
	var components := {
		"world": normalized_world,
		"agent": {
			"context": normalized.duplicate(true),
			"transaction_status": "committed",
		},
	}
	if has_world_log:
		components["world_log"] = normalized_world_log
	var manifest := {
		"schema": SCHEMA,
		"schema_version": (
			SCHEMA_VERSION if has_world_log else PREVIOUS_SCHEMA_VERSION
		),
		"state": "published",
		"slot_id": String(normalized.get("slot_id", "")),
		"session_id": String(normalized.get("session_id", "")),
		"save_revision": int(normalized.get("save_revision", 0)),
		"saved_at": saved_at,
		"session_config_ref": session_config_ref,
		"session_config_sha256": session_config_sha256,
		"resident_ids": (
			resident_ids_result.get("residentIds", []) as Array
		).duplicate(),
		"resident_messages": (
			resident_messages_result.get("residentMessages", []) as Array
		).duplicate(true),
		"components": components,
	}
	return manifest if validate(manifest).get("ok") == true else {}


static func validate(value: Variant) -> Dictionary:
	var errors: Array[Dictionary] = []
	if not (value is Dictionary):
		return _failure("SESSION_SAVE_MANIFEST_INVALID", [{
			"path": "manifest",
			"code": "SESSION_SAVE_MANIFEST_INVALID",
		}])
	var manifest := value as Dictionary
	var schema_version := (
		int(manifest.get("schema_version"))
		if _is_non_negative_integer_number(manifest.get("schema_version"))
		else -1
	)
	var allowed_fields: Array = (
		LEGACY_MANIFEST_FIELDS
		if schema_version == LEGACY_SCHEMA_VERSION
		else MANIFEST_FIELDS
	)
	_reject_unknown_fields(manifest, allowed_fields, "manifest", errors)
	if _string_or_empty(manifest.get("schema")) != SCHEMA:
		errors.append(_error("manifest.schema", "SESSION_SAVE_MANIFEST_INVALID"))
	if (
		schema_version != LEGACY_SCHEMA_VERSION
		and schema_version != PREVIOUS_SCHEMA_VERSION
		and schema_version != SCHEMA_VERSION
	):
		errors.append(_error(
			"manifest.schema_version",
			"SESSION_SAVE_MANIFEST_INVALID",
		))
	if _string_or_empty(manifest.get("state")) != "published":
		errors.append(_error("manifest.state", "SESSION_SAVE_MANIFEST_INVALID"))
	var context_result := validate_context({
		"slot_id": manifest.get("slot_id"),
		"session_id": manifest.get("session_id"),
		"save_revision": manifest.get("save_revision"),
	})
	var normalized_context := (
		context_result.get("context", {}) as Dictionary
	)
	if (
		context_result.get("ok") != true
		or int(normalized_context.get("save_revision", 0)) < 1
	):
		errors.append(_error("manifest.context", "SESSION_SAVE_MANIFEST_INVALID"))
	if not TownSaveScalars.is_saved_at_value(manifest.get("saved_at")):
		errors.append(_error("manifest.saved_at", "SESSION_SAVE_MANIFEST_INVALID"))
	var session_config_ref_value: Variant = manifest.get("session_config_ref")
	if not _reference_matches_context(
		session_config_ref_value,
		normalized_context,
		"session_config.json",
	):
		errors.append(_error(
			"manifest.session_config_ref",
			"SESSION_SAVE_MANIFEST_INVALID",
		))
	if not _is_sha256(manifest.get("session_config_sha256")):
		errors.append(_error(
			"manifest.session_config_sha256",
			"SESSION_SAVE_MANIFEST_INVALID",
		))
	var resident_result := _validate_resident_id_array(
		manifest.get("resident_ids", []),
	)
	if resident_result.get("ok") != true:
		errors.append(_error(
			"manifest.resident_ids",
			"SESSION_SAVE_MANIFEST_INVALID",
		))
	if schema_version in [PREVIOUS_SCHEMA_VERSION, SCHEMA_VERSION]:
		var message_result := validate_resident_messages(
			manifest.get("resident_messages"),
			resident_result.get("residentIds", []) as Array,
		)
		if message_result.get("ok") != true:
			errors.append(_error(
				"manifest.resident_messages",
				"SESSION_SAVE_MANIFEST_INVALID",
			))
	var components_value: Variant = manifest.get("components")
	if not (components_value is Dictionary):
		errors.append(_error("manifest.components", "SESSION_SAVE_MANIFEST_INVALID"))
	else:
		var components := components_value as Dictionary
		var component_fields := (
			["world", "agent", "world_log"]
			if schema_version == SCHEMA_VERSION
			else ["world", "agent"]
		)
		_reject_unknown_fields(
			components,
			component_fields,
			"manifest.components",
			errors,
		)
		_validate_world_component(
			components.get("world"),
			normalized_context,
			errors,
		)
		_validate_agent_component(
			components.get("agent"),
			context_result.get("context", {}) as Dictionary,
			errors,
		)
		if schema_version == SCHEMA_VERSION:
			_validate_world_log_component(
				components.get("world_log"),
				normalized_context,
				errors,
			)
	if not errors.is_empty():
		return _failure("SESSION_SAVE_MANIFEST_INVALID", errors)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"manifest": manifest.duplicate(true),
	}


static func unsupported_version_evidence(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var manifest := value as Dictionary
	var versions := {}
	var manifest_version: Variant = manifest.get("schema_version")
	if (
		_is_non_negative_integer_number(manifest_version)
		and int(manifest_version) not in [
			LEGACY_SCHEMA_VERSION,
			PREVIOUS_SCHEMA_VERSION,
			SCHEMA_VERSION,
		]
	):
		versions["manifest"] = int(manifest_version)
	var components_value: Variant = manifest.get("components")
	if not components_value is Dictionary:
		return versions
	var world_value: Variant = (components_value as Dictionary).get("world")
	if not world_value is Dictionary:
		return versions
	var world := world_value as Dictionary
	var world_version: Variant = world.get("schema_version")
	if (
		_is_non_negative_integer_number(world_version)
		and int(world_version) not in WORLD_SCHEMA_VERSIONS
	):
		versions["world"] = int(world_version)
	var world_data_version: Variant = world.get("world_data_version")
	if (
		_is_non_negative_integer_number(world_data_version)
		and int(world_data_version) != TownSaveSchemaRegistry.WORLD_DATA_VERSION
	):
		versions["worldData"] = int(world_data_version)
	return versions


static func validate_resident_messages(
	value: Variant,
	resident_id_values: Array,
) -> Dictionary:
	if not value is Array:
		return _failure("SESSION_SAVE_RESIDENT_MESSAGES_INVALID")
	var resident_ids: Dictionary = {}
	for resident_id_value: Variant in resident_id_values:
		if not resident_id_value is String:
			return _failure("SESSION_SAVE_RESIDENT_MESSAGES_INVALID")
		resident_ids[resident_id_value as String] = true
	var messages := value as Array
	if messages.size() > MAX_RESIDENT_MESSAGES:
		return _failure("SESSION_SAVE_RESIDENT_MESSAGES_INVALID")
	var normalized: Array[Dictionary] = []
	var message_ids: Dictionary = {}
	var message_resident_ids: Dictionary = {}
	for index in messages.size():
		var item_value: Variant = messages[index]
		if not item_value is Dictionary:
			return _failure("SESSION_SAVE_RESIDENT_MESSAGES_INVALID")
		var item := item_value as Dictionary
		var item_errors: Array[Dictionary] = []
		_reject_unknown_fields(
			item,
			RESIDENT_MESSAGE_FIELDS,
			"residentMessages[%d]" % index,
			item_errors,
		)
		if not item_errors.is_empty():
			return _failure("SESSION_SAVE_RESIDENT_MESSAGES_INVALID", item_errors)
		var message_id_value: Variant = item.get("message_id")
		var resident_id_value: Variant = item.get("resident_id")
		var resident_name_value: Variant = item.get("resident_name")
		var content_value: Variant = item.get("content")
		var message_id := _string_or_empty(message_id_value).strip_edges()
		var resident_id := _string_or_empty(resident_id_value).strip_edges()
		var resident_name := _string_or_empty(resident_name_value).strip_edges()
		var content := _string_or_empty(content_value).strip_edges()
		if (
			not message_id_value is String
			or not resident_id_value is String
			or not resident_name_value is String
			or not content_value is String
			or message_id != message_id_value
			or resident_id != resident_id_value
			or resident_name != resident_name_value
			or content != content_value
			or not _safe_identifier(message_id)
			or message_ids.has(message_id)
			or not resident_ids.has(resident_id)
			or message_resident_ids.has(resident_id)
			or resident_name.is_empty()
			or resident_name.length() > MAX_RESIDENT_MESSAGE_NAME_LENGTH
			or resident_name.contains("\n")
			or resident_name.contains("\r")
			or content.is_empty()
			or content.length() > MAX_RESIDENT_MESSAGE_LENGTH
			or content.contains("\n")
			or content.contains("\r")
		):
			return _failure("SESSION_SAVE_RESIDENT_MESSAGES_INVALID")
		message_ids[message_id] = true
		message_resident_ids[resident_id] = true
		normalized.append({
			"message_id": message_id,
			"resident_id": resident_id,
			"resident_name": resident_name,
			"content": content,
		})
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"residentMessages": normalized,
	}


static func resident_messages(manifest: Dictionary) -> Array:
	if validate(manifest).get("ok") != true:
		return []
	if int(manifest.get("schema_version", 0)) == LEGACY_SCHEMA_VERSION:
		return []
	return (
		manifest.get("resident_messages", []) as Array
	).duplicate(true)


static func summary(manifest_value: Variant) -> Dictionary:
	if not manifest_value is Dictionary:
		return {}
	var manifest := manifest_value as Dictionary
	if validate(manifest).get("ok") != true:
		return {}
	var components := manifest.get("components", {}) as Dictionary
	var world := components.get("world", {}) as Dictionary
	return {
		"slotId": String(manifest.get("slot_id", "")),
		"sessionId": String(manifest.get("session_id", "")),
		"saveRevision": int(manifest.get("save_revision", 0)),
		"savedAt": String(manifest.get("saved_at", "")),
		"residentCount": (manifest.get("resident_ids", []) as Array).size(),
		"worldRevision": int(world.get("world_revision", 0)),
		"day": int(world.get("day", 0)),
	}


static func _validate_world_component(
	value: Variant,
	expected_context: Dictionary,
	errors: Array[Dictionary],
) -> void:
	if not (value is Dictionary):
		errors.append(_error(
			"manifest.components.world",
			"SESSION_SAVE_MANIFEST_INVALID",
		))
		return
	var world := value as Dictionary
	_reject_unknown_fields(
		world,
		WORLD_FIELDS,
		"manifest.components.world",
		errors,
	)
	if not _reference_matches_context(
		world.get("snapshot_ref"),
		expected_context,
		"world_snapshot.json",
	):
		errors.append(_error(
			"manifest.components.world.snapshot_ref",
			"SESSION_SAVE_MANIFEST_INVALID",
		))
	if not _is_sha256(world.get("snapshot_sha256")):
		errors.append(_error(
			"manifest.components.world.snapshot_sha256",
			"SESSION_SAVE_MANIFEST_INVALID",
		))
	if _string_or_empty(world.get("schema")) != WORLD_SCHEMA:
		errors.append(_error(
			"manifest.components.world.schema",
			"SESSION_SAVE_MANIFEST_INVALID",
		))
	if (
		not _is_non_negative_integer_number(world.get("schema_version"))
		or int(world.get("schema_version")) not in WORLD_SCHEMA_VERSIONS
	):
		errors.append(_error(
			"manifest.components.world.schema_version",
			"SESSION_SAVE_MANIFEST_INVALID",
		))
	for field_name in ["world_revision", "world_data_version"]:
		if (
			not _is_non_negative_integer_number(world.get(field_name))
			or int(world.get(field_name)) < 1
		):
			errors.append(_error(
				"manifest.components.world.%s" % field_name,
				"SESSION_SAVE_MANIFEST_INVALID",
			))
	if world.has("day") and not _is_non_negative_integer_number(world.get("day")):
		errors.append(_error(
			"manifest.components.world.day",
			"SESSION_SAVE_MANIFEST_INVALID",
		))
	if _string_or_empty(world.get("transaction_status")) != "committed":
		errors.append(_error(
			"manifest.components.world.transaction_status",
			"SESSION_SAVE_MANIFEST_INVALID",
		))


static func _validate_agent_component(
	value: Variant,
	expected_context: Dictionary,
	errors: Array[Dictionary],
) -> void:
	if not (value is Dictionary):
		errors.append(_error(
			"manifest.components.agent",
			"SESSION_SAVE_MANIFEST_INVALID",
		))
		return
	var agent := value as Dictionary
	_reject_unknown_fields(
		agent,
		AGENT_FIELDS,
		"manifest.components.agent",
		errors,
	)
	var context_result := validate_context(agent.get("context"))
	if (
		context_result.get("ok") != true
		or (context_result.get("context", {}) as Dictionary) != expected_context
	):
		errors.append(_error(
			"manifest.components.agent.context",
			"SESSION_SAVE_MANIFEST_INVALID",
		))
	if _string_or_empty(agent.get("transaction_status")) != "committed":
		errors.append(_error(
			"manifest.components.agent.transaction_status",
			"SESSION_SAVE_MANIFEST_INVALID",
		))


static func _validate_world_log_component(
	value: Variant,
	expected_context: Dictionary,
	errors: Array[Dictionary],
) -> void:
	if not value is Dictionary:
		errors.append(_error(
			"manifest.components.world_log",
			"SESSION_SAVE_MANIFEST_INVALID",
		))
		return
	var world_log := value as Dictionary
	_reject_unknown_fields(
		world_log,
		WORLD_LOG_FIELDS,
		"manifest.components.world_log",
		errors,
	)
	if not _reference_matches_context(
		world_log.get("snapshot_ref"),
		expected_context,
		"world_log_snapshot.json",
	):
		errors.append(_error(
			"manifest.components.world_log.snapshot_ref",
			"SESSION_SAVE_MANIFEST_INVALID",
		))
	if not _is_sha256(world_log.get("snapshot_sha256")):
		errors.append(_error(
			"manifest.components.world_log.snapshot_sha256",
			"SESSION_SAVE_MANIFEST_INVALID",
		))
	if _string_or_empty(world_log.get("schema")) != WORLD_LOG_SCHEMA:
		errors.append(_error(
			"manifest.components.world_log.schema",
			"SESSION_SAVE_MANIFEST_INVALID",
		))
	if (
		not _is_non_negative_integer_number(world_log.get("schema_version"))
		or int(world_log.get("schema_version")) != 1
	):
		errors.append(_error(
			"manifest.components.world_log.schema_version",
			"SESSION_SAVE_MANIFEST_INVALID",
		))
	if not _safe_identifier(_string_or_empty(world_log.get("timeline_id"))):
		errors.append(_error(
			"manifest.components.world_log.timeline_id",
			"SESSION_SAVE_MANIFEST_INVALID",
		))
	if not _is_non_negative_integer_number(world_log.get("max_sequence")):
		errors.append(_error(
			"manifest.components.world_log.max_sequence",
			"SESSION_SAVE_MANIFEST_INVALID",
		))
	if (
		not _is_non_negative_integer_number(world_log.get("world_revision"))
		or int(world_log.get("world_revision")) < 1
	):
		errors.append(_error(
			"manifest.components.world_log.world_revision",
			"SESSION_SAVE_MANIFEST_INVALID",
		))
	if _string_or_empty(world_log.get("transaction_status")) != "committed":
		errors.append(_error(
			"manifest.components.world_log.transaction_status",
			"SESSION_SAVE_MANIFEST_INVALID",
		))


static func _validate_resident_id_array(value: Variant) -> Dictionary:
	var ids: Array[String] = []
	if not (value is Array):
		return _failure("SESSION_SAVE_MANIFEST_INVALID")
	for item: Variant in value as Array:
		if not item is String:
			return _failure("SESSION_SAVE_MANIFEST_INVALID")
		var resident_id := item as String
		if not _safe_resident_identifier(resident_id) or ids.has(resident_id):
			return _failure("SESSION_SAVE_MANIFEST_INVALID")
		ids.append(resident_id)
	var original: Array = (value as Array).duplicate()
	ids.sort()
	if ids.is_empty() or ids != original:
		return _failure("SESSION_SAVE_MANIFEST_INVALID")
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"residentIds": ids,
	}


static func _reject_unknown_fields(
	value: Dictionary,
	allowed: Array,
	path: String,
	errors: Array[Dictionary],
) -> void:
	for key_value: Variant in value:
		var key := key_value as String if key_value is String else str(key_value)
		if not key_value is String or not allowed.has(key):
			errors.append(_error(
				"%s.%s" % [path, key],
				"SESSION_SAVE_PRIVATE_PAYLOAD_FORBIDDEN",
			))


static func _has_exact_fields(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key: Variant in value:
		if not key is String or not expected.has(key):
			return false
	return true


static func _safe_identifier(value: String) -> bool:
	if (
		value.is_empty()
		or value.length() > 128
		or value == "."
		or value == ".."
	):
		return false
	for character in value:
		var code := character.unicode_at(0)
		var allowed := (
			(code >= 48 and code <= 57)
			or (code >= 65 and code <= 90)
			or (code >= 97 and code <= 122)
			or character == "_"
			or character == "-"
		)
		if not allowed:
			return false
	return true


static func _safe_resident_identifier(value: String) -> bool:
	return _safe_identifier(value) and value == value.to_lower()


static func _is_sha256(value: Variant) -> bool:
	if not value is String or (value as String).length() != 64:
		return false
	for character in value as String:
		var code := character.unicode_at(0)
		if not (
			(code >= 48 and code <= 57)
			or (code >= 97 and code <= 102)
		):
			return false
	return true


static func _reference_matches_context(
	value: Variant,
	context: Dictionary,
	file_name: String,
) -> bool:
	if not value is String:
		return false
	var reference := value as String
	if (
		reference.is_empty()
		or reference != reference.strip_edges()
		or reference.begins_with("/")
		or reference.contains("\\")
		or reference.contains("//")
	):
		return false
	for segment in reference.split("/"):
		if segment.is_empty() or segment == "." or segment == "..":
			return false
	return reference == TownSaveContext.revision_reference(context, file_name)


static func _is_non_negative_integer_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return value >= 0 and value <= MAX_SAFE_INTEGER
	if typeof(value) != TYPE_FLOAT:
		return false
	var numeric := float(value)
	return (
		is_finite(numeric)
		and numeric >= 0.0
		and numeric <= float(MAX_SAFE_INTEGER)
		and numeric == floor(numeric)
	)


static func _positive_integer_or_zero(value: Variant) -> int:
	if not _is_non_negative_integer_number(value):
		return 0
	var normalized := int(value)
	return normalized if normalized > 0 else 0


static func _string_or_empty(value: Variant) -> String:
	return value as String if value is String else ""


static func _error(path: String, code: String) -> Dictionary:
	return {"path": path, "code": code}


static func _failure(
	error_code: String,
	errors: Array = [],
) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"retryable": false,
		"errors": errors.duplicate(true),
	}
