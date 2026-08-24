class_name TownSaveSchemaRegistry
extends RefCounted
## 存档链路版本常量与已发布迁移规则的唯一事实源(批次E之3)。各文件原常量改为引用本表,
## 数值逐字保留。目标:回答"v1 存档今天还能不能开"时只查一处。
## agent 层的 PERSISTENT_STATE/MEMORY_STATE 版本归 agent 域(tim),不入本表。

const WORLD_SCHEMA_VERSION := 2
const WORLD_SUPPORTED_SCHEMA_VERSIONS := [1, 2]
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
const ACTIVITY_SAVE_MIGRATION_VERSION := 1
const ACTIVITY_SOURCE_FINGERPRINT_BEFORE_PUBLIC_DINING_SLOT_REWORK := (
	"bf870f16f18fde30f8512bdd6c1fbbaa62989f38970af10d1630d4ab87947dff"
)
const ACTIVITY_SOURCE_FINGERPRINT_AFTER_PUBLIC_DINING_SLOT_REWORK := (
	"584ba4b89019f92378131a56bc380e0c2dec5e460d977d7050484996a9c57a9f"
)
const ACTIVITY_SOURCE_FINGERPRINT_AFTER_PUBLIC_DINING_DAY_REWORK := (
	"bc3442e119eeccd05687f4f1bc73bb3f857c8747f651d5291b6f53cce09c3490"
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
		"migrationVersion": ACTIVITY_SAVE_MIGRATION_VERSION,
	}


static func _activity_migration_from(source_fingerprint: String) -> Dictionary:
	for value: Variant in ACTIVITY_SAVE_MIGRATIONS:
		var migration := value as Dictionary
		if String(migration.get("fromSourceFingerprint", "")) == source_fingerprint:
			return migration
	return {}


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
