class_name TownSaveCompatibilityRegistry
extends RefCounted
## beta1 起的存档兼容账本。导入器只通过本模块查询迁移范围、识别结果和升级路径。

const SAVE_SCHEMA_REGISTRY := preload(
	"res://world/presentation/session/TownSaveSchemaRegistry.gd"
)
const AGENT_STATE_MIGRATION := preload(
	"res://agent/lifecycle/AgentResidentStateMigration.gd"
)

const POLICY_REQUIRED := "required"
const POLICY_BEST_EFFORT := "best_effort"
const POLICY_EXCLUDED := "excluded"

const STATUS_CURRENT := "current"
const STATUS_SUPPORTED := "supported"
const STATUS_READ_ONLY := "read_only"
const STATUS_UNSUPPORTED := "unsupported"
const STATUS_INVALID := "invalid"

const ERROR_TYPES := {
	"invalid_evidence": "SAVE_COMPATIBILITY_EVIDENCE_INVALID",
	"damaged_save": "SAVE_ARCHIVE_DAMAGED",
	"future_version": "SAVE_VERSION_NEWER_THAN_SUPPORTED",
	"unsupported_version": "SAVE_VERSION_NO_LONGER_SUPPORTED",
	"unknown_combination": "SAVE_VERSION_COMBINATION_UNKNOWN",
	"migration_path_missing": "SAVE_MIGRATION_PATH_MISSING",
}

const VERSION_RULES := {
	"world": {"current": 2, "supported": [1, 2], "requiredForDetection": true},
	"manifest": {
		"current": 3,
		"supported": [1, 2, 3],
		"requiredForDetection": true,
	},
	"profile": {"current": 2, "supported": [1, 2], "requiredForDetection": true},
	"agent": {"current": 3, "supported": [3], "requiredForDetection": true},
	"residentPayload": {
		"current": 2,
		"supported": [2],
		"requiredForDetection": true,
	},
	"residentRuntime": {
		"current": 6,
		"supported": [5, 6],
		"requiredForDetection": true,
	},
	"residentMemory": {
		"current": 6,
		"supported": [5, 6],
		"requiredForDetection": true,
	},
	"provider": {"current": 2, "supported": [1, 2], "requiredForDetection": false},
	"worldData": {
		"current": SAVE_SCHEMA_REGISTRY.WORLD_DATA_VERSION,
		"supported": [SAVE_SCHEMA_REGISTRY.WORLD_DATA_VERSION],
		"requiredForDetection": true,
	},
	"worldLog": {"current": 1, "supported": [1], "requiredForDetection": false},
	"customResidentLibrary": {
		"current": 1,
		"supported": [1],
		"requiredForDetection": false,
	},
	"playerSettings": {
		"current": 1,
		"supported": [1],
		"requiredForDetection": false,
	},
	"providerCredentials": {
		"current": 1,
		"supported": [1],
		"requiredForDetection": false,
	},
}
const BETA1_TO_BETA6_VERSION_COMBINATION := {
	"world": 2,
	"manifest": 3,
	"profile": 2,
	"agent": 3,
	"residentPayload": 2,
	"residentRuntime": 6,
	"residentMemory": 6,
	"worldData": 4,
}
# 尚未形成新发行版、且旧存档无法靠版本字段区分时，恢复链按内容守卫执行这些迁移。
const CURRENT_MIGRATIONS := [
	{
		"id": SAVE_SCHEMA_REGISTRY.PLACE_SERVICE_OWNER_BACKFILL_MIGRATION_ID,
		"module": "world_snapshot",
		"reason": "地点服务协调者的默认派生规则变化；仅在静态配置完全一致时补齐。",
	},
	{
		"id": AGENT_STATE_MIGRATION.SHOP_OWNER_DERIVATION_MIGRATION_ID,
		"module": "resident_payload",
		"reason": "铺面负责人改由当前职业岗位派生；旧初始化资料移除固定负责人。",
	},
]
const RELEASES := [
	{
		"id": "beta1",
		"worldSectionCount": 26,
		"activitySourceFingerprint": (
			SAVE_SCHEMA_REGISTRY
			.ACTIVITY_SOURCE_FINGERPRINT_AFTER_PUBLIC_DINING_SLOT_REWORK
		),
		"residentPathLayout": "raw",
		"nextEdge": {
			"id": "beta1-to-beta2",
			"kind": "no_change",
			"modules": [],
			"migrationIds": [],
			"reason": (
				"正式存档没有变化；运行时记忆工作副本重新生成，Provider 设置按尽力兼容处理。"
			),
		},
	},
	{
		"id": "beta2",
		"worldSectionCount": 26,
		"activitySourceFingerprint": (
			SAVE_SCHEMA_REGISTRY
			.ACTIVITY_SOURCE_FINGERPRINT_AFTER_PUBLIC_DINING_SLOT_REWORK
		),
		"residentPathLayout": "hashed",
		"nextEdge": {
			"id": "beta2-to-beta3",
			"kind": "migrate",
			"modules": ["world_snapshot"],
			"migrationIds": [
				"2026-08-12-public-dining-day-routine",
			],
			"reason": (
				"活动指纹更新；缺少的 travelerRelations 由当前恢复逻辑重建默认状态。"
			),
		},
	},
	{
		"id": "beta3",
		"worldSectionCount": 27,
		"activitySourceFingerprint": (
			SAVE_SCHEMA_REGISTRY
			.ACTIVITY_SOURCE_FINGERPRINT_AFTER_PUBLIC_DINING_DAY_REWORK
		),
		"residentPathLayout": "hashed",
		"nextEdge": {
			"id": "beta3-to-beta4",
			"kind": "no_change",
			"modules": [],
			"migrationIds": [],
			"reason": "已登记持久化契约没有变化。",
		},
	},
	{
		"id": "beta4",
		"worldSectionCount": 27,
		"activitySourceFingerprint": (
			SAVE_SCHEMA_REGISTRY
			.ACTIVITY_SOURCE_FINGERPRINT_AFTER_PUBLIC_DINING_DAY_REWORK
		),
		"residentPathLayout": "hashed",
		"nextEdge": {
			"id": "beta4-to-beta5",
			"kind": "no_change",
			"modules": [],
			"migrationIds": [],
			"reason": "World 代码拆分和 Web 设备标识不改变正式存档契约。",
		},
	},
	{
		"id": "beta5",
		"worldSectionCount": 27,
		"activitySourceFingerprint": (
			SAVE_SCHEMA_REGISTRY
			.ACTIVITY_SOURCE_FINGERPRINT_AFTER_PUBLIC_DINING_DAY_REWORK
		),
		"residentPathLayout": "hashed",
		"nextEdge": {
			"id": "beta5-to-beta6",
			"kind": "no_change",
			"modules": [],
			"migrationIds": [],
			"reason": "已登记持久化契约没有变化，升级后按 beta6 重新保存。",
		},
	},
	{
		"id": "beta6",
		"worldSectionCount": 27,
		"activitySourceFingerprint": (
			SAVE_SCHEMA_REGISTRY
			.ACTIVITY_SOURCE_FINGERPRINT_AFTER_UNSTAFFED_PUBLIC_PLACE_ACCESS
		),
		# beta6 样本在当前无人值守公共场所规则合入前生成；它已经带有
		# beta6 写入标记，仍应按当前发行版识别，再由恢复流水线重写当前指纹。
		"legacyActivitySourceFingerprints": [
			SAVE_SCHEMA_REGISTRY.ACTIVITY_SOURCE_FINGERPRINT_AFTER_PUBLIC_DINING_DAY_REWORK,
		],
		"residentPathLayout": "hashed",
		"nextEdge": {},
	},
]

const MODULES := [
	{
		"id": "startup_profile",
		"layer": "session",
		"policy": POLICY_REQUIRED,
		"versionKeys": ["profile"],
	},
	{
		"id": "session_manifest",
		"layer": "session",
		"policy": POLICY_REQUIRED,
		"versionKeys": ["manifest"],
	},
	{
		"id": "session_config",
		"layer": "session",
		"policy": POLICY_REQUIRED,
		"versionKeys": [],
	},
	{
		"id": "world_snapshot",
		"layer": "world",
		"policy": POLICY_REQUIRED,
		"versionKeys": ["world", "worldData"],
	},
	{
		"id": "world_log",
		"layer": "world",
		"policy": POLICY_REQUIRED,
		"versionKeys": ["worldLog"],
	},
	{
		"id": "agent_snapshot",
		"layer": "agent",
		"policy": POLICY_REQUIRED,
		"versionKeys": ["agent"],
	},
	{
		"id": "resident_payload",
		"layer": "agent",
		"policy": POLICY_REQUIRED,
		"versionKeys": ["residentPayload", "residentRuntime"],
	},
	{
		"id": "resident_memory",
		"layer": "agent",
		"policy": POLICY_REQUIRED,
		"versionKeys": ["residentMemory"],
	},
	{
		"id": "conversation_photos",
		"layer": "asset",
		"policy": POLICY_REQUIRED,
		"versionKeys": [],
	},
	{
		"id": "custom_resident_library",
		"layer": "asset",
		"policy": POLICY_REQUIRED,
		"versionKeys": ["customResidentLibrary"],
	},
	{
		"id": "provider_config",
		"layer": "local",
		"policy": POLICY_BEST_EFFORT,
		"versionKeys": ["provider"],
	},
	{
		"id": "player_settings",
		"layer": "local",
		"policy": POLICY_BEST_EFFORT,
		"versionKeys": ["playerSettings"],
	},
	{
		"id": "legacy_audio_settings",
		"layer": "local",
		"policy": POLICY_BEST_EFFORT,
		"versionKeys": [],
	},
	{
		"id": "provider_credentials",
		"layer": "local",
		"policy": POLICY_EXCLUDED,
		"versionKeys": ["providerCredentials"],
	},
	{
		"id": "device_and_transaction_state",
		"layer": "ephemeral",
		"policy": POLICY_EXCLUDED,
		"versionKeys": [],
	},
]


static func module_descriptors() -> Array:
	var descriptors: Array[Dictionary] = []
	for module_value: Variant in MODULES:
		var descriptor := (module_value as Dictionary).duplicate(true)
		var versions := {}
		for version_key_value: Variant in descriptor.get("versionKeys", []) as Array:
			var version_key := String(version_key_value)
			var rule := VERSION_RULES.get(version_key, {}) as Dictionary
			versions[version_key] = {
				"current": int(rule.get("current", 0)),
				"supported": (rule.get("supported", []) as Array).duplicate(),
			}
		descriptor.erase("versionKeys")
		descriptor["versions"] = versions
		descriptors.append(descriptor)
	return descriptors


static func detect_release(evidence: Dictionary) -> Dictionary:
	var versions_value: Variant = evidence.get("versions")
	if not versions_value is Dictionary:
		return _detection_error(
			"invalid_evidence",
			STATUS_INVALID,
			"version combination is missing",
		)
	var versions := versions_value as Dictionary
	var explicit_version_check := _detect_explicit_module_versions(versions)
	if explicit_version_check.get("ok") != true:
		return explicit_version_check
	for key_value: Variant in VERSION_RULES:
		var key := String(key_value)
		if not versions.has(key):
			if not bool((VERSION_RULES.get(key) as Dictionary).get(
				"requiredForDetection",
				false,
			)):
				continue
			return _detection_error(
				"invalid_evidence",
				STATUS_INVALID,
				"version is missing: %s" % key,
			)
	var recorded_release := String(evidence.get("recordedRelease", ""))
	if not recorded_release.is_empty() and not is_registered_release(recorded_release):
		if _release_number(recorded_release) > _release_number(_current_release()):
			return _detection_error(
				"future_version",
				STATUS_READ_ONLY,
				"recorded release is newer than supported",
			)
		return _detection_error(
			"unknown_combination",
			STATUS_INVALID,
			"recorded release is not registered",
		)
	var section_count_value: Variant = evidence.get("worldSectionCount")
	var fingerprint_value: Variant = evidence.get("activitySourceFingerprint")
	if (
		typeof(section_count_value) != TYPE_INT
		or not fingerprint_value is String
		or String(fingerprint_value).is_empty()
	):
		return _detection_error(
			"invalid_evidence",
			STATUS_INVALID,
			"release evidence is incomplete",
		)
	var path_layout := String(evidence.get("residentPathLayout", ""))
	var candidates: Array[String] = []
	for release_value: Variant in RELEASES:
		var release := release_value as Dictionary
		if not _release_version_combination_matches(versions, release):
			continue
		if int(release.get("worldSectionCount", 0)) != int(section_count_value):
			continue
		var release_fingerprint := String(release.get("activitySourceFingerprint", ""))
		var legacy_fingerprints := release.get(
			"legacyActivitySourceFingerprints",
			[],
		) as Array
		if (
			release_fingerprint != String(fingerprint_value)
			and not legacy_fingerprints.has(String(fingerprint_value))
		):
			continue
		if (
			not path_layout.is_empty()
			and String(release.get("residentPathLayout", "")) != path_layout
		):
			continue
		candidates.append(String(release.get("id", "")))
	if candidates.is_empty():
		return _detection_error(
			"unknown_combination",
			STATUS_INVALID,
			"release evidence does not match a supported contract",
		)
	if not recorded_release.is_empty():
		if not candidates.has(recorded_release):
			return _detection_error(
				"unknown_combination",
				STATUS_INVALID,
				"recorded release conflicts with save evidence",
			)
		candidates = [recorded_release]
	var exact := candidates.size() == 1
	var release := candidates[0] if exact else ""
	return {
		"ok": true,
		"supportStatus": (
			STATUS_CURRENT if release == _current_release() else STATUS_SUPPORTED
		),
		"release": release,
		"releaseRange": candidates,
		"migrationStartRelease": candidates[0],
		"exact": exact,
		"readOnly": false,
		"error": {},
	}


static func evidence_from_save(
	manifest: Dictionary,
	world_snapshot: Dictionary,
	session_config: Dictionary,
	resident_path_layout: String = "",
	module_versions: Dictionary = {},
) -> Dictionary:
	var versions := BETA1_TO_BETA6_VERSION_COMBINATION.duplicate(true)
	versions["world"] = int(world_snapshot.get("schemaVersion", 0))
	versions["manifest"] = int(manifest.get("schema_version", 0))
	versions["worldData"] = int(world_snapshot.get("worldDataVersion", 0))
	for key_value: Variant in module_versions:
		versions[String(key_value)] = module_versions.get(key_value)
	var state := world_snapshot.get("state", {}) as Dictionary
	var activity := state.get("activityRuntime", {}) as Dictionary
	var evidence := {
		"versions": versions,
		"worldSectionCount": state.size(),
		"activitySourceFingerprint": String(
			activity.get("sourceFingerprint", ""),
		),
		"residentPathLayout": resident_path_layout,
	}
	var recorded_release := String(
		session_config.get("saveRelease", ""),
	).strip_edges()
	if not recorded_release.is_empty():
		evidence["recordedRelease"] = recorded_release
	return evidence


static func migration_path(
	from_release: String,
	to_release: String = "",
) -> Dictionary:
	var release_order := _release_order()
	var resolved_to_release := to_release
	if resolved_to_release.is_empty():
		resolved_to_release = _current_release()
	var from_index := release_order.find(from_release)
	var to_index := release_order.find(resolved_to_release)
	if from_index < 0 or to_index < 0 or from_index > to_index:
		return {
			"ok": false,
			"from": from_release,
			"to": resolved_to_release,
			"edges": [],
			"error": {
				"type": "migration_path_missing",
				"code": String(ERROR_TYPES.get("migration_path_missing", "")),
				"reason": "release migration path is not registered",
			},
		}
	var registered_edges := _migration_edges()
	var edges: Array[Dictionary] = []
	for edge_index in range(from_index, to_index):
		edges.append(registered_edges[edge_index].duplicate(true))
	return {
		"ok": true,
		"from": from_release,
		"to": resolved_to_release,
		"edges": edges,
		"currentMigrationIds": _current_migration_ids(),
		"error": {},
	}


static func current_release() -> String:
	return _current_release()


static func is_registered_release(release_id: String) -> bool:
	return _release_order().has(release_id)


static func is_valid_release_marker(release_id: String) -> bool:
	var normalized := release_id.strip_edges()
	return (
		normalized == release_id
		and normalized.begins_with("beta")
		and _release_number(normalized) > 0
	)


static func restore_gate(detection: Dictionary) -> Dictionary:
	if (
		detection.get("ok") == true
		and String(detection.get("supportStatus", "")) in [
			STATUS_CURRENT,
			STATUS_SUPPORTED,
		]
	):
		return {"ok": true, "errorCode": "", "retryable": false}
	var error := detection.get("error", {}) as Dictionary
	return {
		"ok": false,
		"errorCode": String(
			error.get("code", "SAVE_VERSION_COMBINATION_UNKNOWN"),
		),
		"retryable": false,
		"readOnly": bool(detection.get("readOnly", true)),
		"supportStatus": String(detection.get("supportStatus", STATUS_INVALID)),
	}


static func _detect_explicit_module_versions(versions: Dictionary) -> Dictionary:
	var unknown_versions: Array[String] = []
	for key_value: Variant in versions:
		var key := String(key_value)
		if not VERSION_RULES.has(key):
			unknown_versions.append(key)
			continue
		var version_value: Variant = versions.get(key)
		if typeof(version_value) != TYPE_INT:
			return _detection_error(
				"invalid_evidence",
				STATUS_INVALID,
				"version must be an integer: %s" % key,
			)
		var rule := VERSION_RULES.get(key, {}) as Dictionary
		if int(version_value) > int(rule.get("current", 0)):
			return _detection_error(
				"future_version",
				STATUS_READ_ONLY,
				"one or more module versions are newer than supported",
				[key],
			)
		if not (rule.get("supported", []) as Array).has(version_value):
			return _detection_error(
				"unsupported_version",
				STATUS_UNSUPPORTED,
				"one or more module versions are no longer supported",
				[key],
			)
	unknown_versions.sort()
	if not unknown_versions.is_empty():
		return _detection_error(
			"future_version",
			STATUS_READ_ONLY,
			"one or more module versions are not registered",
			unknown_versions,
		)
	return {"ok": true}


static func validate_registry(releases: Array = RELEASES) -> Array[String]:
	var errors: Array[String] = []
	var error_codes := {}
	for error_type_value: Variant in ERROR_TYPES:
		var error_type := String(error_type_value)
		var error_code := String(ERROR_TYPES.get(error_type, ""))
		if error_code.is_empty() or error_codes.has(error_code):
			errors.append("error code is missing or duplicated: %s" % error_type)
		else:
			error_codes[error_code] = true
	var module_ids := {}
	for module_value: Variant in MODULES:
		if not module_value is Dictionary:
			errors.append("module descriptor must be a dictionary")
			continue
		var module := module_value as Dictionary
		var module_id := String(module.get("id", ""))
		if module_id.is_empty():
			errors.append("module id is required")
		elif module_ids.has(module_id):
			errors.append("duplicate module id: %s" % module_id)
		else:
			module_ids[module_id] = true
		if String(module.get("layer", "")).is_empty():
			errors.append("module layer is required: %s" % module_id)
		if not String(module.get("policy", "")) in [
			POLICY_REQUIRED,
			POLICY_BEST_EFFORT,
			POLICY_EXCLUDED,
		]:
			errors.append("module policy is invalid: %s" % module_id)
		for version_key_value: Variant in module.get("versionKeys", []) as Array:
			var version_key := String(version_key_value)
			if not VERSION_RULES.has(version_key):
				errors.append("module version key is not registered: %s" % version_key)
	var release_ids: Array[String] = []
	for release_value: Variant in releases:
		if not release_value is Dictionary:
			errors.append("release descriptor must be a dictionary")
			continue
		var release_id := String((release_value as Dictionary).get("id", ""))
		if release_id.is_empty() or release_ids.has(release_id):
			errors.append("release id is missing or duplicated: %s" % release_id)
		else:
			release_ids.append(release_id)
	var edge_ids := {}
	for edge_index in releases.size():
		var release := releases[edge_index] as Dictionary
		var edge := release.get("nextEdge", {}) as Dictionary
		if edge_index == releases.size() - 1:
			if not edge.is_empty():
				errors.append("current release cannot have a next edge")
			continue
		if edge.is_empty():
			errors.append(
				"release has no migration edge: %s" % String(release.get("id", ""))
			)
			continue
		var edge_id := String(edge.get("id", ""))
		if edge_id.is_empty() or edge_ids.has(edge_id):
			errors.append("migration edge id is missing or duplicated: %s" % edge_id)
		else:
			edge_ids[edge_id] = true
		var kind := String(edge.get("kind", ""))
		if not kind in ["migrate", "no_change"]:
			errors.append("migration edge kind is invalid: %s" % edge_id)
		var migration_ids := edge.get("migrationIds", []) as Array
		if kind == "migrate" and migration_ids.is_empty():
			errors.append("migration edge has no migration ids: %s" % edge_id)
		if kind == "no_change" and not migration_ids.is_empty():
			errors.append("no-change edge cannot contain migration ids: %s" % edge_id)
		if String(edge.get("reason", "")).is_empty():
			errors.append("migration edge reason is required: %s" % edge_id)
		for module_id_value: Variant in edge.get("modules", []) as Array:
			var module_id := String(module_id_value)
			if not module_ids.has(module_id):
				errors.append("migration edge references unknown module: %s" % module_id)
	var current_migration_ids := {}
	for migration_value: Variant in CURRENT_MIGRATIONS:
		if not migration_value is Dictionary:
			errors.append("current migration descriptor must be a dictionary")
			continue
		var current_migration := migration_value as Dictionary
		var migration_id := String(current_migration.get("id", ""))
		if migration_id.is_empty() or current_migration_ids.has(migration_id):
			errors.append("current migration id is missing or duplicated: %s" % migration_id)
		else:
			current_migration_ids[migration_id] = true
		if not module_ids.has(String(current_migration.get("module", ""))):
			errors.append("current migration references unknown module: %s" % migration_id)
		if String(current_migration.get("reason", "")).is_empty():
			errors.append("current migration reason is required: %s" % migration_id)
	return errors


static func _release_order() -> Array[String]:
	var release_order: Array[String] = []
	for release_value: Variant in RELEASES:
		release_order.append(String((release_value as Dictionary).get("id", "")))
	return release_order


static func _current_release() -> String:
	if RELEASES.is_empty():
		return ""
	return String((RELEASES.back() as Dictionary).get("id", ""))


static func _release_number(release_id: String) -> int:
	if not release_id.begins_with("beta"):
		return -1
	var number := release_id.trim_prefix("beta")
	if number.is_empty() or not number.is_valid_int():
		return -1
	return int(number)


static func _current_migration_ids() -> Array[String]:
	var migration_ids: Array[String] = []
	for migration_value: Variant in CURRENT_MIGRATIONS:
		migration_ids.append(String((migration_value as Dictionary).get("id", "")))
	return migration_ids


static func _migration_edges() -> Array[Dictionary]:
	var edges: Array[Dictionary] = []
	for edge_index in RELEASES.size() - 1:
		var release := RELEASES[edge_index] as Dictionary
		var next_release := RELEASES[edge_index + 1] as Dictionary
		var edge := (release.get("nextEdge", {}) as Dictionary).duplicate(true)
		edge["from"] = String(release.get("id", ""))
		edge["to"] = String(next_release.get("id", ""))
		edges.append(edge)
	return edges


static func _release_version_combination_matches(
	versions: Dictionary,
	release: Dictionary,
) -> bool:
	var expected := release.get(
		"versions",
		BETA1_TO_BETA6_VERSION_COMBINATION,
	) as Dictionary
	for key_value: Variant in expected:
		var key := String(key_value)
		if versions.get(key) != expected.get(key):
			return false
	return true


static func _detection_error(
	error_type: String,
	support_status: String,
	reason: String,
	modules: Array[String] = [],
) -> Dictionary:
	return {
		"ok": false,
		"supportStatus": support_status,
		"release": "",
		"releaseRange": [],
		"migrationStartRelease": "",
		"exact": false,
		"readOnly": true,
		"error": {
			"type": error_type,
			"code": String(ERROR_TYPES.get(error_type, "")),
			"reason": reason,
			"modules": modules,
		},
	}
