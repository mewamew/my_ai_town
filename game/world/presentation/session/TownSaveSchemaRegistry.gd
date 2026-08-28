class_name TownSaveSchemaRegistry
extends RefCounted
## 存档链路版本常量与已发布迁移规则的唯一事实源(批次E之3)。各文件原常量改为引用本表,
## 数值逐字保留。目标:回答"v1 存档今天还能不能开"时只查一处。
## agent 层的 PERSISTENT_STATE/MEMORY_STATE 版本归 agent 域(tim),不入本表。

const WORLD_SCHEMA_VERSION := 2
const WORLD_SUPPORTED_SCHEMA_VERSIONS := [1, 2]
const WORLD_DATA_VERSION := 4
const MANIFEST_SCHEMA_VERSION := 3
const MANIFEST_LEGACY_SCHEMA_VERSION := 1
const MANIFEST_PREVIOUS_SCHEMA_VERSION := 2
const PROFILE_SCHEMA_VERSION := 2
const PROFILE_LEGACY_SCHEMA_VERSION := 1
const AGENT_SAVE_FORMAT_VERSION := 3
const NEW_GAME_DRAFT_SCHEMA_VERSION := 1
const CUSTOM_RESIDENT_LIBRARY_SCHEMA_VERSION := 1

# 活动运行时的 sourceFingerprint 只描述编译数据整体版本，不能替代逐字段迁移。
# 每次发布会改变已保存引用含义的活动/位置/道具/锚点时，必须在下方登记一条
# 从旧 sourceFingerprint 到下一版本的、可重复执行的字段迁移。旧规则一旦随版本
# 发布就不能删除，否则跳过多个版本的存档会失去升级路径。
const ACTIVITY_SAVE_MIGRATION_VERSION := 2
const WORLD_SAVE_MIGRATION_VERSION := 2
const PLACE_SERVICE_OWNER_BACKFILL_MIGRATION_ID := (
	"2026-08-24-place-service-owner-backfill"
)
const PLACE_SERVICE_CONFIG_FIELDS: Array[String] = [
	"pressure_id",
	"place_id",
	"service_occupation_id",
	"service_capacity",
	"helper_activity_id",
	"request_activity_ids",
]
const ACTIVITY_SOURCE_FINGERPRINT_BEFORE_PUBLIC_DINING_SLOT_REWORK := (
	"bf870f16f18fde30f8512bdd6c1fbbaa62989f38970af10d1630d4ab87947dff"
)
const ACTIVITY_SOURCE_FINGERPRINT_AFTER_PUBLIC_DINING_SLOT_REWORK := (
	"584ba4b89019f92378131a56bc380e0c2dec5e460d977d7050484996a9c57a9f"
)
const ACTIVITY_SOURCE_FINGERPRINT_AFTER_PUBLIC_DINING_DAY_REWORK := (
	"bc3442e119eeccd05687f4f1bc73bb3f857c8747f651d5291b6f53cce09c3490"
)
const ACTIVITY_SOURCE_FINGERPRINT_AFTER_COMMUNAL_SIMPLE_MEAL := (
	"744cc6609bd100be9ead3a35199155e5fe6206f7c34c245e230a9f449bb79b72"
)
const ACTIVITY_SOURCE_FINGERPRINT_AFTER_CLINIC_SELF_CARE := (
	"75d01b68ad3727ff7327b828ca6c8d13846aac5699228db74cb749251044b479"
)
const ACTIVITY_SOURCE_FINGERPRINT_AFTER_UNSTAFFED_PUBLIC_PLACE_ACCESS := (
	"44815398b66700e89ebd014692af12d17c754bac2746d026f6796b35872b0cfd"
)
# 本地 fork：world/data/town/source/occupation_catalog.json 新增 occupation_police（警察职业）
# 后的世界数据聚合指纹（TownWorldDataBuild 重建产物）。
const ACTIVITY_SOURCE_FINGERPRINT_AFTER_LOCAL_POLICE_OCCUPATION := (
	"bf242f42dae623b44ec47902d4defea29314286de0be16a619683a5b61ad298f"
)
const ACTIVITY_SAVE_MIGRATIONS := [
	{
		"id": "2026-08-10-public-dining-prepare-dough-target",
		"fromSourceFingerprint": (
			ACTIVITY_SOURCE_FINGERPRINT_BEFORE_PUBLIC_DINING_SLOT_REWORK
		),
		"toSourceFingerprint": (
			ACTIVITY_SOURCE_FINGERPRINT_AFTER_PUBLIC_DINING_SLOT_REWORK
		),
		"executionRewrites": [
			{
				"activityId": "activity_baker_prepare_dough",
				"slotId": "slot_baker_prepare_dough_01",
				"targetType": "prop",
				"targetActionVerb": "准备面团",
				"field": "targetPropName",
				"from": "公共食堂备餐柜",
				"to": "公共食堂面团操作台",
			},
			{
				"activityId": "activity_dining_serve_meal",
				"slotId": "slot_dining_serve_meal_01",
				"targetType": "prop",
				"targetActionVerb": "取餐",
				"field": "targetPropName",
				"from": "公共食堂备餐柜",
				"to": "公共食堂递餐口",
			},
			{
				"activityId": "activity_dining_serve_meal",
				"slotId": "slot_dining_serve_meal_01",
				"targetType": "prop",
				"targetActionVerb": "取餐",
				"field": "targetActionVerb",
				"from": "取餐",
				"to": "递餐",
			},
		],
		"placeServiceStateRewrites": [
			{
				"placeId": "公共食堂",
				"field": "service_capacity",
				"from": 2,
				"to": 4,
			},
		],
		"refreshResidentActionRoutes": true,
	},
	{
		"id": "2026-08-12-public-dining-day-routine",
		"fromSourceFingerprint": (
			ACTIVITY_SOURCE_FINGERPRINT_AFTER_PUBLIC_DINING_SLOT_REWORK
		),
		"toSourceFingerprint": (
			ACTIVITY_SOURCE_FINGERPRINT_AFTER_PUBLIC_DINING_DAY_REWORK
		),
		# beta.2 之后调整了备餐时长、全天餐次窗口并增加可用活动位。
		# 已保存的执行引用没有被删除或改名，按原进度继续即可；登记这条
		# 兼容节点是为了让跨多个发行版跳跃的存档仍能走完整迁移链。
		"executionRewrites": [],
		"placeServiceStateRewrites": [],
	},
	{
		"id": "2026-08-24-communal-simple-meal",
		"fromSourceFingerprint": (
			ACTIVITY_SOURCE_FINGERPRINT_AFTER_PUBLIC_DINING_DAY_REWORK
		),
		"toSourceFingerprint": (
			ACTIVITY_SOURCE_FINGERPRINT_AFTER_COMMUNAL_SIMPLE_MEAL
		),
		# 新增自助简餐活动位，没有删除或改名既有执行引用；旧活动可按原进度继续。
		"executionRewrites": [],
		"placeServiceStateRewrites": [],
	},
	{
		"id": "2026-08-24-clinic-self-care",
		"fromSourceFingerprint": (
			ACTIVITY_SOURCE_FINGERPRINT_AFTER_COMMUNAL_SIMPLE_MEAL
		),
		"toSourceFingerprint": (
			ACTIVITY_SOURCE_FINGERPRINT_AFTER_CLINIC_SELF_CARE
		),
		# 新增基础自我处理活动位，没有删除或改名既有执行引用。
		"executionRewrites": [],
		"placeServiceStateRewrites": [],
	},
	{
		"id": "2026-08-24-unstaffed-public-place-access",
		"fromSourceFingerprint": (
			ACTIVITY_SOURCE_FINGERPRINT_AFTER_CLINIC_SELF_CARE
		),
		"toSourceFingerprint": (
			ACTIVITY_SOURCE_FINGERPRINT_AFTER_UNSTAFFED_PUBLIC_PLACE_ACCESS
		),
		# 只增加从静态地点配置推导的无人值守访问规则，不改写已保存活动引用。
		"executionRewrites": [],
		"placeServiceStateRewrites": [],
	},
	{
		"id": "2026-08-27-local-police-occupation-catalog",
		"fromSourceFingerprint": (
			ACTIVITY_SOURCE_FINGERPRINT_AFTER_UNSTAFFED_PUBLIC_PLACE_ACCESS
		),
		"toSourceFingerprint": (
			ACTIVITY_SOURCE_FINGERPRINT_AFTER_LOCAL_POLICE_OCCUPATION
		),
		# 本地 fork 在 occupation_catalog 增加警察职业，世界数据聚合指纹随之改变；
		# 只推进指纹节点，不改写已保存活动执行引用。
		"executionRewrites": [],
		"placeServiceStateRewrites": [],
	},
]


static func migrate_activity_runtime_state(
	value: Dictionary,
	current_source_fingerprint: String,
) -> Dictionary:
	var state := value.duplicate(true)
	var source := String(state.get("sourceFingerprint", ""))
	var applied: Array[String] = []
	var refresh_resident_action_routes := false
	var visited := {}
	while (
		not source.is_empty()
		and source != current_source_fingerprint
		and not visited.has(source)
	):
		visited[source] = true
		var migration := _activity_migration_from(source)
		if migration.is_empty():
			break
		_apply_activity_migration(state, migration)
		var migration_id := String(migration.get("id", ""))
		if not migration_id.is_empty():
			applied.append(migration_id)
		refresh_resident_action_routes = (
			refresh_resident_action_routes
			or bool(migration.get("refreshResidentActionRoutes", false))
		)
		var next_source := String(migration.get("toSourceFingerprint", ""))
		if next_source.is_empty() or next_source == source:
			break
		source = next_source
		state["sourceFingerprint"] = source
	return {
		"ok": true,
		"state": state,
		"applied": applied,
		"refreshResidentActionRoutes": refresh_resident_action_routes,
		"migrationVersion": ACTIVITY_SAVE_MIGRATION_VERSION,
	}


static func migrate_world_state(
	value: Dictionary,
	current_activity_source_fingerprint: String,
) -> Dictionary:
	var state := value.duplicate(true)
	var activity_state_value: Variant = state.get("activityRuntime", {})
	var source := (
		String((activity_state_value as Dictionary).get("sourceFingerprint", ""))
		if activity_state_value is Dictionary
		else ""
	)
	var applied: Array[String] = []
	var refresh_resident_action_routes := false
	var visited := {}
	while (
		not source.is_empty()
		and source != current_activity_source_fingerprint
		and not visited.has(source)
	):
		visited[source] = true
		var migration := _activity_migration_from(source)
		if migration.is_empty():
			break
		var activity_state := activity_state_value as Dictionary
		_apply_resident_action_migration(state, activity_state, migration)
		_apply_activity_migration(activity_state, migration)
		_apply_place_service_state_migration(state, migration)
		activity_state["sourceFingerprint"] = String(
			migration.get("toSourceFingerprint", "")
		)
		state["activityRuntime"] = activity_state
		activity_state_value = activity_state
		var migration_id := String(migration.get("id", ""))
		if not migration_id.is_empty():
			applied.append(migration_id)
		refresh_resident_action_routes = (
			refresh_resident_action_routes
			or bool(migration.get("refreshResidentActionRoutes", false))
		)
		var next_source := String(migration.get("toSourceFingerprint", ""))
		if next_source.is_empty() or next_source == source:
			break
		source = next_source
	return {
		"ok": true,
		"state": state,
		"applied": applied,
		"refreshResidentActionRoutes": refresh_resident_action_routes,
		"migrationVersion": WORLD_SAVE_MIGRATION_VERSION,
	}


static func migrate_place_service_owners(
	value: Variant,
	current_defaults: Dictionary,
) -> Dictionary:
	if not value is Dictionary:
		return {
			"ok": true,
			"state": value,
			"applied": [],
			"migrationVersion": WORLD_SAVE_MIGRATION_VERSION,
		}
	var states := (value as Dictionary).duplicate(true)
	var changed := false
	for place_id_value: Variant in states:
		var place_id := String(place_id_value)
		var state_value: Variant = states.get(place_id_value)
		var expected_value: Variant = current_defaults.get(place_id)
		if not state_value is Dictionary or not expected_value is Dictionary:
			continue
		var state := state_value as Dictionary
		var expected := expected_value as Dictionary
		if not _can_backfill_place_service_owner(state, expected):
			continue
		state["owner_id"] = expected.get("owner_id")
		if _place_service_state_is_untouched(state):
			state["open"] = expected.get("open")
		states[place_id_value] = state
		changed = true
	return {
		"ok": true,
		"state": states,
		"applied": (
			[PLACE_SERVICE_OWNER_BACKFILL_MIGRATION_ID]
			if changed
			else []
		),
		"migrationVersion": WORLD_SAVE_MIGRATION_VERSION,
	}


static func place_service_config_matches(
	state: Dictionary,
	expected: Dictionary,
) -> bool:
	for field_name: String in PLACE_SERVICE_CONFIG_FIELDS:
		if not state.has(field_name) or state.get(field_name) != expected.get(field_name):
			return false
	return true


static func _activity_migration_from(source_fingerprint: String) -> Dictionary:
	for value: Variant in ACTIVITY_SAVE_MIGRATIONS:
		var migration := value as Dictionary
		if String(migration.get("fromSourceFingerprint", "")) == source_fingerprint:
			return migration
	return {}


static func _can_backfill_place_service_owner(
	state: Dictionary,
	expected: Dictionary,
) -> bool:
	if (
		not state.get("owner_id") is String
		or not expected.get("owner_id") is String
		or not (state.get("owner_id") as String).is_empty()
		or (expected.get("owner_id") as String).is_empty()
		or not state.get("open") is bool
		or not expected.get("open") is bool
	):
		return false
	return place_service_config_matches(state, expected)


static func _place_service_state_is_untouched(state: Dictionary) -> bool:
	return (
		state.get("source_revision") is int
		and int(state.get("source_revision")) == 0
		and state.get("updated_at") is int
		and int(state.get("updated_at")) == -1
		and state.get("expires_at") is int
		and int(state.get("expires_at")) == -1
		and state.get("pending_request_ids") is Array
		and (state.get("pending_request_ids") as Array).is_empty()
	)


static func _apply_activity_migration(
	state: Dictionary,
	migration: Dictionary,
) -> int:
	var rewrite_count := 0
	for execution_value: Variant in state.get("executions", []) as Array:
		if not execution_value is Dictionary:
			continue
		var execution := execution_value as Dictionary
		for rewrite_value: Variant in migration.get("executionRewrites", []) as Array:
			if not rewrite_value is Dictionary:
				continue
			var rewrite := rewrite_value as Dictionary
			if not _execution_matches_rewrite(execution, rewrite):
				continue
			var field := String(rewrite.get("field", ""))
			if (
				field.is_empty()
				or String(execution.get(field, ""))
				!= String(rewrite.get("from", ""))
			):
				continue
			execution[field] = rewrite.get("to", "")
			rewrite_count += 1
	return rewrite_count


static func _apply_resident_action_migration(
	state: Dictionary,
	activity_state: Dictionary,
	migration: Dictionary,
) -> int:
	var residents_value: Variant = state.get("residents", [])
	if not residents_value is Array:
		return 0
	var rewrite_count := 0
	for execution_value: Variant in activity_state.get("executions", []) as Array:
		if not execution_value is Dictionary:
			continue
		var execution := execution_value as Dictionary
		if String(execution.get("status", "")) != "executing":
			continue
		var resident_id := String(execution.get("residentId", ""))
		if resident_id.is_empty():
			continue
		var resident: Dictionary = {}
		for resident_value: Variant in residents_value as Array:
			if not resident_value is Dictionary:
				continue
			var candidate := resident_value as Dictionary
			if String(candidate.get("id", candidate.get("residentId", ""))) == resident_id:
				resident = candidate
				break
		if resident.is_empty():
			continue
		var action_value: Variant = resident.get("currentAction", {})
		if not action_value is Dictionary:
			continue
		var action := action_value as Dictionary
		if not _resident_action_matches_execution(action, execution):
			continue
		for rewrite_value: Variant in migration.get("executionRewrites", []) as Array:
			if not rewrite_value is Dictionary:
				continue
			var rewrite := rewrite_value as Dictionary
			if not _execution_matches_rewrite(execution, rewrite):
				continue
			var action_field := _resident_action_field(
				String(rewrite.get("field", ""))
			)
			if action_field.is_empty():
				continue
			if String(action.get(action_field, "")) != String(rewrite.get("from", "")):
				continue
			action[action_field] = rewrite.get("to", "")
			rewrite_count += 1
		resident["currentAction"] = action
	return rewrite_count


static func _execution_matches_rewrite(
	execution: Dictionary,
	rewrite: Dictionary,
) -> bool:
	for match_field in [
		"activityId",
		"slotId",
		"targetType",
		"targetActionVerb",
	]:
		if String(execution.get(match_field, "")) != String(
			rewrite.get(match_field, "")
		):
			return false
	return true


static func _resident_action_matches_execution(
	action: Dictionary,
	execution: Dictionary,
) -> bool:
	var action_id := String(action.get("action_id", action.get("actionId", "")))
	var execution_action_id := String(execution.get("actionId", ""))
	var action_source_id := String(action.get("sourceActionId", ""))
	var execution_source_id := String(execution.get("sourceActionId", ""))
	return (
		not action_id.is_empty()
		and action_id == execution_action_id
		and String(action.get("sourceContract", ""))
			== String(execution.get("sourceContract", ""))
		and action_source_id == execution_source_id
	)


static func _resident_action_field(execution_field: String) -> String:
	return {
		"targetPropName": "prop",
		"targetActionVerb": "verb",
	}.get(execution_field, "")


static func _apply_place_service_state_migration(
	state: Dictionary,
	migration: Dictionary,
) -> int:
	var states_value: Variant = state.get("placeServiceStates", {})
	if not states_value is Dictionary:
		return 0
	var states := states_value as Dictionary
	var rewrite_count := 0
	for rewrite_value: Variant in migration.get(
		"placeServiceStateRewrites",
		[],
	) as Array:
		if not rewrite_value is Dictionary:
			continue
		var rewrite := rewrite_value as Dictionary
		var place_id := String(rewrite.get("placeId", ""))
		var place_state_value: Variant = states.get(place_id, {})
		if not place_state_value is Dictionary:
			continue
		var place_state := place_state_value as Dictionary
		var field := String(rewrite.get("field", ""))
		if (
			field.is_empty()
			or not place_state.has(field)
			or place_state.get(field) != rewrite.get("from")
		):
			continue
		place_state[field] = rewrite.get("to")
		rewrite_count += 1
	return rewrite_count
