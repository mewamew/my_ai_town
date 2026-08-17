extends RefCounted

# 居民状态投影(docs/帧预算与节拍解耦方案.md A2):完整投影与 town_hud 轻量
# 投影共享同一套字段派生逻辑,靠字段集合参数按需计算、不生成其余字段。
# 语义合同:轻量结果恒等于对完整投影输出做键裁剪(差分用例断言),不得新增
# 或改变任何字段语义——特别地,完整投影不含 isMoving,轻量投影也不得出现。

const ACTION_PRESENTATION := preload(
	"res://world/runtime/presentation/TownActionPresentationSemantics.gd"
)
const RESIDENT_LIFECYCLE_PROJECTION := preload(
	"res://world/presentation/lifecycle/TownResidentLifecycleProjection.gd"
)

# town_hud 构建路径实际读取的键(TownUiAdapter town_hud 调用树逐处枚举,
# 证据清单见方案落地记录;position 只经 avatar scope 间接读取,不在其列)。
const HUD_KEYS := {
	"residentId": true,
	"name": true,
	"spaceId": true,
	"currentPlace": true,
	"doing": true,
	"body": true,
	"currentAction": true,
	"actionPhase": true,
	"activityCue": true,
	"actionPresentation": true,
}

# resident_state_changed 表现通知合同的载荷键(docs/居民状态通知链减负方案.md
# C2):唯一订阅者 ResidentCharacterPresentation 实际消费的 7 键。空间字段由
# 订阅者自拉移动快照覆写,不在其列。
const EMIT_KEYS := {
	"residentId": true,
	"name": true,
	"appearance": true,
	"lifecycle": true,
	"currentAction": true,
	"actionPhase": true,
	"activityCue": true,
}


static func project(world, resident: Dictionary) -> Dictionary:
	return project_fields(world, resident, {})


static func project_hud(world, resident: Dictionary) -> Dictionary:
	return project_fields(world, resident, HUD_KEYS)


static func project_emit(world, resident: Dictionary) -> Dictionary:
	return project_fields(world, resident, EMIT_KEYS)


static func project_player_avatar(
	avatar: Dictionary,
	present: bool,
	resident_display_name: Callable,
) -> Dictionary:
	var state := avatar.duplicate(true)
	state["present"] = present
	var nearby_ids := (avatar.get("nearby", []) as Array).duplicate()
	var nearby_names: Array[String] = []
	for resident_id_value: Variant in nearby_ids:
		nearby_names.append(
			String(resident_display_name.call(String(resident_id_value))),
		)
	state["nearbyResidentIds"] = nearby_ids
	state["nearby"] = nearby_names
	return state


static func avatar_runtime(record: Dictionary, default_avatar_id: String) -> Dictionary:
	var state := record.get("worldState", {}) as Dictionary
	var pair := state.get("position", []) as Array
	return {
		"residentId": String(record.get("residentId", default_avatar_id)),
		"name": String(record.get("name", "")),
		"position": Vector2(float(pair[0]), float(pair[1])),
		"spaceId": String(state.get("spaceId", "")),
		"regionId": String(state.get("regionId", "")),
		"currentPlace": String(state.get("place", "")),
		"doing": String(state.get("doing", "")),
		"nearby": [],
		"conversationId": "",
		"conversation": null,
	}


# keys 为空表示全字段。字段的派生逻辑只写这一遍,轻量路径靠跳过不生成;
# 字段写入顺序与拆分前的完整投影一致。
static func project_fields(
	world,
	resident: Dictionary,
	keys: Dictionary,
) -> Dictionary:
	var all_fields := keys.is_empty()
	var attributes := resident.get("attributes", {}) as Dictionary
	var resident_id := String(resident.get("residentId", ""))
	var projection := {}
	if all_fields or keys.has("residentId"):
		projection["residentId"] = resident_id
	if all_fields or keys.has("movementRevision"):
		projection["movementRevision"] = int(resident.get("movementRevision", 1))
	if all_fields or keys.has("worldRevision"):
		projection["worldRevision"] = world._world_revision
	if all_fields or keys.has("isPresent"):
		projection["isPresent"] = world.resident_is_present(resident)
	if all_fields or keys.has("arrivalState"):
		projection["arrivalState"] = (
			resident.get(
				"arrivalState",
				{
					"status": "arrived",
					"scheduledAbsoluteMinute": -1,
					"arrivedAbsoluteMinute": -1,
				},
			) as Dictionary
		).duplicate(true)
	if all_fields or keys.has("name"):
		projection["name"] = String(attributes.get("name", ""))
	if all_fields or keys.has("appearance"):
		projection["appearance"] = String(attributes.get("appearance", ""))
	if all_fields or keys.has("position"):
		projection["position"] = resident.get("position", Vector2.ZERO) as Vector2
	if all_fields or keys.has("spaceId"):
		projection["spaceId"] = String(resident.get("spaceId", ""))
	if all_fields or keys.has("regionId"):
		projection["regionId"] = String(resident.get("regionId", ""))
	if all_fields or keys.has("currentPlace"):
		projection["currentPlace"] = String(resident.get("currentPlace", ""))
	if all_fields or keys.has("doing"):
		projection["doing"] = String(resident.get("doing", ""))
	if all_fields or keys.has("body"):
		projection["body"] = (resident.get("body", {}) as Dictionary).duplicate(true)
	if all_fields or keys.has("activityNeeds"):
		projection["activityNeeds"] = (
			resident.get(
				"activityState",
				world.ACTIVITY_SCALARS.empty_activity_state(),
			) as Dictionary
		).duplicate(true)
	if all_fields or keys.has("conditions"):
		projection["conditions"] = world._resident_conditions.get_conditions(resident_id,) as Array
	if all_fields or keys.has("activeNeeds"):
		projection["activeNeeds"] = world._resident_conditions.get_active_needs(resident_id,) as Array
	if all_fields or keys.has("nearbyResidentIds") or keys.has("nearby"):
		var nearby_ids: Array[String] = []
		var nearby_names: Array[String] = []
		for person_ref_value: Variant in resident.get("nearby", []) as Array:
			var person_id := String(
				world.person_id_for_name(String(person_ref_value)),
			)
			nearby_ids.append(person_id)
			nearby_names.append(String(world.person_name_for_id(person_id)))
		if all_fields or keys.has("nearbyResidentIds"):
			projection["nearbyResidentIds"] = nearby_ids
		if all_fields or keys.has("nearby"):
			projection["nearby"] = nearby_names
	if all_fields or keys.has("currentAction"):
		projection["currentAction"] = ACTION_PRESENTATION._resident_public_current_action(
			world,
			resident,
		)
	if all_fields or keys.has("actionPhase"):
		projection["actionPhase"] = ACTION_PRESENTATION._resident_action_phase_projection(
			world,
			resident,
		)
	if all_fields or keys.has("conversation"):
		projection["conversation"] = world.ACTIVITY_SCALARS.duplicate_optional_dictionary(
			resident.get("conversation"),
		)
	if all_fields or keys.has("lifecycle"):
		projection["lifecycle"] = RESIDENT_LIFECYCLE_PROJECTION.project(
			world._resident_lifecycle.get_resident_state(resident_id) as Dictionary,
		)
	if all_fields or keys.has("activityCue") or keys.has("actionPresentation"):
		var activity_cue: Variant = ACTION_PRESENTATION._resident_activity_cue(
			world,
			resident,
		)
		if (all_fields or keys.has("activityCue")) and activity_cue is Dictionary:
			projection["activityCue"] = (activity_cue as Dictionary).duplicate(true)
		if all_fields or keys.has("actionPresentation"):
			var action_presentation: Variant = ACTION_PRESENTATION._resident_action_presentation(
				world,
				resident,
				activity_cue,
			)
			if action_presentation is Dictionary:
				projection["actionPresentation"] = (
					action_presentation as Dictionary
				).duplicate(true)
	return projection
