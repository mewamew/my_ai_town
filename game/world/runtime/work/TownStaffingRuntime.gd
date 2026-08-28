class_name TownStaffingRuntime
extends RefCounted


const RESULT_SHAPES := preload("res://world/contract/TownWorldResultShapes.gd")
const CHAIN_CATALOG := preload(
	"res://world/data/town/TownWorkChainCatalog.gd"
)
const MAX_TERMINAL_ARRANGEMENTS := 128


var _world_data: Dictionary = {}
var _chains_by_occupation: Dictionary = {}
var _snapshot: Dictionary = {}
var _configured := false
var _qualifications_by_resident: Dictionary = {}
var _arrangements: Dictionary = {}
var _arrangement_sequence := 0
var _last_rebuild_projection: Dictionary = {}


func configure(world_data: Dictionary) -> Dictionary:
	if _configured:
		return _failure("STAFFING_RUNTIME_ALREADY_CONFIGURED")
	if (
		not world_data.get("occupations") is Array
		or (world_data.get("occupations", []) as Array).is_empty()
		or not world_data.get("activityDefinitions") is Array
		or not world_data.get("activitySlots") is Array
	):
		return _failure("STAFFING_WORLD_DATA_INVALID")
	var chains := CHAIN_CATALOG.load_catalog()
	if chains.is_empty():
		return _failure("STAFFING_WORK_CHAIN_CATALOG_INVALID")
	for value: Variant in chains.get("chains", []) as Array:
		if value is Dictionary:
			var chain := value as Dictionary
			_chains_by_occupation[String(
				chain.get("occupationId", ""),
			)] = chain.duplicate(true)
	_world_data = world_data.duplicate(true)
	_configured = true
	_snapshot = _empty_snapshot()
	return {
		"ok": true,
		"errorCode": "",
		"postCount": (
			_world_data.get("occupations", []) as Array
		).size(),
	}


func rebuild(
	residents: Dictionary,
	absolute_minute := 0,
) -> Dictionary:
	if not _configured:
		return _failure("STAFFING_RUNTIME_NOT_CONFIGURED")
	var assigned_by_occupation: Dictionary = {}
	var unassigned_resident_ids: Array[String] = []
	var absent_by_occupation: Dictionary = {}
	var temporarily_absent_resident_ids: Array[String] = []
	var resident_ids: Array[String] = []
	for resident_id_value: Variant in residents:
		resident_ids.append(String(resident_id_value))
	resident_ids.sort()
	for resident_id: String in resident_ids:
		var resident := residents.get(resident_id, {}) as Dictionary
		var occupation_id := _occupation_id_for_resident(resident)
		if occupation_id.is_empty():
			unassigned_resident_ids.append(resident_id)
			continue
		_record_qualification(resident_id, occupation_id)
		if _resident_temporarily_absent(resident, absolute_minute):
			var absent_ids := (
				absent_by_occupation.get(occupation_id, []) as Array
			).duplicate()
			absent_ids.append(resident_id)
			absent_by_occupation[occupation_id] = absent_ids
			temporarily_absent_resident_ids.append(resident_id)
			continue
		var assigned := (
			assigned_by_occupation.get(
				occupation_id,
				[],
			) as Array
		).duplicate()
		assigned.append(resident_id)
		assigned_by_occupation[occupation_id] = assigned
	var support_by_occupation: Dictionary = {}
	var trials_by_occupation: Dictionary = {}
	for arrangement_value: Variant in _arrangements.values():
		var arrangement := arrangement_value as Dictionary
		if String(arrangement.get("status", "")) != "active":
			continue
		var occupation_id := String(
			arrangement.get("occupationId", ""),
		)
		var resident_id := String(
			arrangement.get("residentId", ""),
		)
		if not residents.has(resident_id):
			continue
		if String(arrangement.get("mode", "")) == "trial":
			var trials := (
				trials_by_occupation.get(occupation_id, []) as Array
			).duplicate()
			if not trials.has(resident_id):
				trials.append(resident_id)
			trials_by_occupation[occupation_id] = trials
			continue
		if not _arrangement_active_at(
			arrangement,
			absolute_minute,
		):
			continue
		var support := (
			support_by_occupation.get(occupation_id, []) as Array
		).duplicate()
		if not support.has(resident_id):
			support.append(resident_id)
		support_by_occupation[occupation_id] = support

	var posts: Array[Dictionary] = []
	var vacant_post_ids: Array[String] = []
	var duplicate_post_ids: Array[String] = []
	var capacity_conflict_post_ids: Array[String] = []
	for occupation_value: Variant in _world_data.get(
		"occupations",
		[],
	) as Array:
		if not occupation_value is Dictionary:
			continue
		var occupation := occupation_value as Dictionary
		var occupation_id := String(
			occupation.get("occupationId", ""),
		)
		var post_id := "post:%s" % occupation_id
		var assigned_resident_ids := (
			assigned_by_occupation.get(
				occupation_id,
				[],
			) as Array
		).duplicate()
		assigned_resident_ids.sort()
		var supporting_resident_ids := (
			support_by_occupation.get(
				occupation_id,
				[],
			) as Array
		).duplicate()
		supporting_resident_ids.sort()
		var trial_resident_ids := (
			trials_by_occupation.get(
				occupation_id,
				[],
			) as Array
		).duplicate()
		trial_resident_ids.sort()
		var temporarily_absent_ids := (
			absent_by_occupation.get(occupation_id, []) as Array
		).duplicate()
		temporarily_absent_ids.sort()
		var covering_support_ids: Array[String] = []
		for arrangement_value: Variant in _arrangements.values():
			var arrangement := arrangement_value as Dictionary
			var arrangement_resident_id := String(
				arrangement.get("residentId", ""),
			)
			if (
				String(arrangement.get("occupationId", ""))
				== occupation_id
				and bool(arrangement.get("coversPost", false))
				and supporting_resident_ids.has(
					arrangement_resident_id,
				)
				and not covering_support_ids.has(
					arrangement_resident_id,
				)
			):
				covering_support_ids.append(
					arrangement_resident_id,
				)
		covering_support_ids.sort()
		var physical_capacity := _physical_capacity(occupation)
		var status := "covered"
		if (
			assigned_resident_ids.is_empty()
			and covering_support_ids.is_empty()
		):
			status = "vacant"
			vacant_post_ids.append(post_id)
		elif assigned_resident_ids.is_empty():
			status = "covered_by_arrangement"
		elif (
			assigned_resident_ids.size()
			+ covering_support_ids.size()
			> 1
		):
			status = "duplicate"
			duplicate_post_ids.append(post_id)
		var responsible_resident_ids := (
			assigned_resident_ids.duplicate()
		)
		for resident_id: String in covering_support_ids:
			if not responsible_resident_ids.has(resident_id):
				responsible_resident_ids.append(resident_id)
		responsible_resident_ids.sort()
		if responsible_resident_ids.size() > physical_capacity:
			capacity_conflict_post_ids.append(post_id)
		var chain := _chains_by_occupation.get(
			occupation_id,
			{},
		) as Dictionary
		posts.append({
			"postId": post_id,
			"occupationId": occupation_id,
			"label": String(occupation.get("label", "")),
			"primaryWorkplacePlace": String(
				occupation.get("primaryWorkplacePlace", ""),
			),
			"relatedWorkplacePlaces": (
				occupation.get(
					"relatedWorkplacePlaces",
					[],
				) as Array
			).duplicate(),
			"dynamicWorkTargetRules": (
				occupation.get(
					"dynamicWorkTargetRules",
					[],
				) as Array
			).duplicate(),
			"fixedWorkAreaIds": (
				occupation.get(
					"fixedWorkAreaIds",
					[],
				) as Array
			).duplicate(),
			"requiredHeadcount": 1,
			"physicalCapacity": physical_capacity,
			"assignedResidentIds": assigned_resident_ids,
			"supportingResidentIds": supporting_resident_ids,
			"trialResidentIds": trial_resident_ids,
			"temporarilyAbsentResidentIds": temporarily_absent_ids,
			"responsibleResidentIds": responsible_resident_ids,
			"status": status,
			"capacityConflict": (
				responsible_resident_ids.size() > physical_capacity
			),
			"vacancyEffect": String(
				chain.get("vacancyEffect", ""),
			),
			"staffingEntryRule": String(
				chain.get("staffingEntryRule", ""),
			),
		})
	posts.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.get("occupationId", "")) < String(
			right.get("occupationId", ""),
		)
	)
	_snapshot = {
		"schemaVersion": 1,
		"posts": posts,
		"vacantPostIds": vacant_post_ids,
		"duplicatePostIds": duplicate_post_ids,
		"capacityConflictPostIds": capacity_conflict_post_ids,
		"unassignedResidentIds": unassigned_resident_ids,
		"temporarilyAbsentResidentIds": temporarily_absent_resident_ids,
		"qualificationsByResident": (
			_qualifications_by_resident.duplicate(true)
		),
		"arrangements": _arrangement_snapshots(),
		"arrangementSequence": _arrangement_sequence,
		"absoluteMinute": absolute_minute,
	}
	_last_rebuild_projection = _dependency_projection(
		residents,
		absolute_minute,
	)
	return {
		"ok": true,
		"errorCode": "",
		"snapshot": _snapshot.duplicate(true),
	}


# 周期维护专用:依赖投影与上次 rebuild 逐字段相等时跳过重建。
# 事件 / 命令触发的调用点仍走 rebuild(),不加门。
func rebuild_if_dependencies_changed(
	residents: Dictionary,
	absolute_minute := 0,
) -> Dictionary:
	if not _configured:
		return _failure("STAFFING_RUNTIME_NOT_CONFIGURED")
	if not _last_rebuild_projection.is_empty():
		var projection := _dependency_projection(
			residents,
			absolute_minute,
		)
		if projection == _last_rebuild_projection:
			# 其余输入未变 ⇒ rebuild 输出与上次逐字段一致,仅时间戳不同;
			# absoluteMinute 有真实消费者,补写为当前维护分钟。
			_snapshot["absoluteMinute"] = absolute_minute
			return {
				"ok": true,
				"errorCode": "",
				"skipped": true,
				"snapshot": _snapshot.duplicate(true),
			}
	return rebuild(residents, absolute_minute)


# 3c 依赖投影:与 rebuild 共享同一输入提取(_occupation_id_for_resident /
# _resident_temporarily_absent / _arrangement_active_at)。时间输入只以
# 分钟级派生生效布尔进投影,恰在影响 rebuild 输出的分钟边界翻转;绝对
# 分钟本身不进投影。集合按稳定主键排序,不受 Dictionary 遍历顺序影响。
func _dependency_projection(
	residents: Dictionary,
	absolute_minute: int,
) -> Dictionary:
	var resident_rows: Array[Dictionary] = []
	var resident_ids: Array[String] = []
	for resident_id_value: Variant in residents:
		resident_ids.append(String(resident_id_value))
	resident_ids.sort()
	for resident_id: String in resident_ids:
		var resident := residents.get(resident_id, {}) as Dictionary
		var occupation_id := _occupation_id_for_resident(resident)
		resident_rows.append({
			"residentId": resident_id,
			"occupationId": occupation_id,
			"temporarilyAbsent": (
				not occupation_id.is_empty()
				and _resident_temporarily_absent(
					resident,
					absolute_minute,
				)
			),
		})
	var arrangement_rows: Array[Dictionary] = []
	for arrangement: Dictionary in _arrangement_snapshots():
		arrangement["activeNow"] = (
			String(arrangement.get("status", "")) == "active"
			and (
				String(arrangement.get("mode", "")) == "trial"
				or _arrangement_active_at(
					arrangement,
					absolute_minute,
				)
			)
		)
		arrangement_rows.append(arrangement)
	return {
		"residents": resident_rows,
		"arrangements": arrangement_rows,
		"arrangementSequence": _arrangement_sequence,
		"qualificationsByResident": (
			_qualifications_by_resident.duplicate(true)
		),
	}


func snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func post_for_occupation(occupation_id: String) -> Dictionary:
	for value: Variant in _snapshot.get("posts", []) as Array:
		if (
			value is Dictionary
			and String((value as Dictionary).get(
				"occupationId",
				"",
			)) == occupation_id
		):
			return (value as Dictionary).duplicate(true)
	return {}


func is_qualified(
	resident_id: String,
	occupation_id: String,
) -> bool:
	return (
		_qualifications_by_resident.get(
			resident_id.strip_edges(),
			[],
		) as Array
	).has(occupation_id.strip_edges())


func allowed_assignment_modes(
	resident_id: String,
	occupation_id: String,
) -> Array[String]:
	var post := post_for_occupation(occupation_id)
	if post.is_empty():
		return []
	var entry_rule := String(post.get("staffingEntryRule", ""))
	var qualified := is_qualified(resident_id, occupation_id)
	match entry_rule:
		"direct":
			return ["transfer", "part_time", "shift"]
		"helper_only":
			return ["part_time"]
		"qualification_required":
			return (
				["transfer", "part_time", "shift"]
				if qualified
				else ["part_time"]
			)
		"performance_required":
			return (
				["transfer", "part_time", "shift"]
				if qualified
				else ["trial"]
			)
	return []


func create_arrangement(
	resident_id: String,
	occupation_id: String,
	mode: String,
	absolute_minute: int,
	shift_start_minute := 0,
	shift_end_minute := 1440,
) -> Dictionary:
	var normalized_resident := resident_id.strip_edges()
	var normalized_occupation := occupation_id.strip_edges()
	var normalized_mode := mode.strip_edges()
	var allowed_modes: Array = allowed_assignment_modes(
		normalized_resident,
		normalized_occupation,
	)
	if (
		normalized_resident.is_empty()
		or normalized_occupation.is_empty()
		or normalized_mode not in ["part_time", "shift", "trial"]
		or normalized_mode not in allowed_modes
		or absolute_minute < 0
		or shift_start_minute < 0
		or shift_start_minute >= 1440
		or shift_end_minute <= 0
		or shift_end_minute > 1440
		or shift_start_minute >= shift_end_minute
	):
		return _failure("STAFFING_ARRANGEMENT_INVALID")
	for value: Variant in _arrangements.values():
		var existing := value as Dictionary
		if (
			String(existing.get("residentId", ""))
			== normalized_resident
			and String(existing.get("occupationId", ""))
			== normalized_occupation
			and String(existing.get("status", "")) == "active"
		):
			return _failure("STAFFING_ARRANGEMENT_CONFLICT")
	var post := post_for_occupation(normalized_occupation)
	var entry_rule := String(post.get("staffingEntryRule", ""))
	var chain := _chains_by_occupation.get(normalized_occupation, {}) as Dictionary
	var authorized_capabilities := _authorized_capabilities_for_chain(chain)
	_arrangement_sequence += 1
	var arrangement_id := "staffing-arrangement-%06d" % (
		_arrangement_sequence
	)
	var arrangement := {
		"arrangementId": arrangement_id,
		"residentId": normalized_resident,
		"occupationId": normalized_occupation,
		"mode": normalized_mode,
		"status": "active",
		"coversPost": (
			normalized_mode in ["part_time", "shift"]
			and entry_rule != "helper_only"
			and (
				entry_rule == "direct"
				or is_qualified(
					normalized_resident,
					normalized_occupation,
				)
			)
		),
		"authorizesWork": not authorized_capabilities.is_empty() and (
			(
				normalized_mode in ["part_time", "shift"]
				and (
					entry_rule in ["direct", "helper_only"]
					or is_qualified(
						normalized_resident,
						normalized_occupation,
					)
				)
			)
			or (
				normalized_mode == "trial"
				and entry_rule == "performance_required"
			)
		),
		"authorizedCapabilities": authorized_capabilities,
		"createdAtMinute": absolute_minute,
		"shiftStartMinute": shift_start_minute,
		"shiftEndMinute": shift_end_minute,
		"completedAtMinute": -1,
		"trialResult": {},
	}
	_arrangements[arrangement_id] = arrangement
	return {
		"ok": true,
		"errorCode": "",
		"arrangement": arrangement.duplicate(true),
	}


func record_trial_result(
	arrangement_id: String,
	success: bool,
	evidence: Dictionary,
	absolute_minute: int,
) -> Dictionary:
	var arrangement := (
		_arrangements.get(
			arrangement_id.strip_edges(),
			{},
		) as Dictionary
	).duplicate(true)
	if (
		arrangement.is_empty()
		or String(arrangement.get("mode", "")) != "trial"
		or String(arrangement.get("status", "")) != "active"
		or evidence.is_empty()
		or absolute_minute
		< int(arrangement.get("createdAtMinute", 0))
	):
		return _failure("STAFFING_TRIAL_RESULT_INVALID")
	arrangement["status"] = "completed" if success else "failed"
	arrangement["completedAtMinute"] = absolute_minute
	arrangement["trialResult"] = evidence.duplicate(true)
	_arrangements[String(
		arrangement.get("arrangementId", ""),
	)] = arrangement
	if success:
		_record_qualification(
			String(arrangement.get("residentId", "")),
			String(arrangement.get("occupationId", "")),
		)
	_compact_terminal_arrangements()
	return {
		"ok": true,
		"errorCode": "",
		"arrangement": arrangement.duplicate(true),
		"qualificationGranted": success,
	}


func active_trial_for(
	resident_id: String,
	occupation_id: String,
) -> Dictionary:
	for value: Variant in _arrangements.values():
		var arrangement := value as Dictionary
		if (
			String(arrangement.get("residentId", ""))
			== resident_id
			and String(arrangement.get("occupationId", ""))
			== occupation_id
			and String(arrangement.get("mode", "")) == "trial"
			and String(arrangement.get("status", "")) == "active"
		):
			return arrangement.duplicate(true)
	return {}


func active_assignment_occupation_ids(
	resident_id: String,
	absolute_minute: int,
) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in _arrangements.values():
		var arrangement := value as Dictionary
		if (
			String(arrangement.get("residentId", ""))
			!= resident_id
			or String(arrangement.get("status", "")) != "active"
			or not bool(arrangement.get("authorizesWork", false))
		):
			continue
		if (
			String(arrangement.get("mode", "")) != "trial"
			and not _arrangement_active_at(
				arrangement,
				absolute_minute,
			)
		):
			continue
		var occupation_id := String(
			arrangement.get("occupationId", ""),
		)
		if not result.has(occupation_id):
			result.append(occupation_id)
	result.sort()
	return result


func active_assignment_capabilities(
	resident_id: String,
	absolute_minute: int,
	occupation_id := "",
) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in _arrangements.values():
		var arrangement := value as Dictionary
		if (
			String(arrangement.get("residentId", "")) != resident_id
			or String(arrangement.get("status", "")) != "active"
			or not bool(arrangement.get("authorizesWork", false))
			or (
				not occupation_id.is_empty()
				and String(arrangement.get("occupationId", "")) != occupation_id
			)
		):
			continue
		if (
			String(arrangement.get("mode", "")) != "trial"
			and not _arrangement_active_at(arrangement, absolute_minute)
		):
			continue
		for capability_value: Variant in arrangement.get(
			"authorizedCapabilities",
			[],
		) as Array:
			var capability := String(capability_value)
			if not capability.is_empty() and not result.has(capability):
				result.append(capability)
	result.sort()
	return result


func active_assignment_allows_capability(
	resident_id: String,
	occupation_id: String,
	capability: String,
	absolute_minute: int,
) -> bool:
	return active_assignment_capabilities(
		resident_id,
		absolute_minute,
		occupation_id,
	).has(capability)


func end_active_arrangements_for_occupation(
	occupation_id: String,
	absolute_minute: int,
	reason: String,
	created_not_before := -1,
) -> Dictionary:
	var normalized_occupation := occupation_id.strip_edges()
	var normalized_reason := reason.strip_edges()
	if (
		normalized_occupation.is_empty()
		or not _chains_by_occupation.has(normalized_occupation)
		or absolute_minute < 0
		or normalized_reason.is_empty()
	):
		return _failure("STAFFING_ARRANGEMENT_END_INVALID")
	var ended_ids: Array[String] = []
	for arrangement_id_value: Variant in _arrangements:
		var arrangement_id := String(arrangement_id_value)
		var arrangement := _arrangements.get(
			arrangement_id,
			{},
		) as Dictionary
		if (
			String(arrangement.get("occupationId", ""))
			!= normalized_occupation
			or String(arrangement.get("status", "")) != "active"
			or (
				created_not_before >= 0
				and int(arrangement.get("createdAtMinute", -1))
				< created_not_before
			)
		):
			continue
		arrangement["status"] = "ended"
		arrangement["completedAtMinute"] = absolute_minute
		arrangement["endReason"] = normalized_reason
		_arrangements[arrangement_id] = arrangement
		ended_ids.append(arrangement_id)
	ended_ids.sort()
	_compact_terminal_arrangements()
	return {
		"ok": true,
		"errorCode": "",
		"endedArrangementIds": ended_ids,
	}


func persistent_snapshot() -> Dictionary:
	return {
		"schemaVersion": 1,
		"qualificationsByResident": (
			_qualifications_by_resident.duplicate(true)
		),
		"arrangements": _arrangement_snapshots(),
		"arrangementSequence": _arrangement_sequence,
	}


func restore_persistent_snapshot(
	value: Dictionary,
	residents: Dictionary,
	absolute_minute: int,
) -> Dictionary:
	if (
		not _configured
		or int(value.get("schemaVersion", 0)) != 1
		or not value.get("qualificationsByResident") is Dictionary
		or not value.get("arrangements") is Array
		or typeof(value.get("arrangementSequence")) != TYPE_INT
	):
		return _failure("STAFFING_SAVE_INVALID")
	var qualifications: Dictionary = {}
	for resident_id_value: Variant in (
		value.get("qualificationsByResident", {}) as Dictionary
	):
		var resident_id := String(resident_id_value)
		var list_value: Variant = (
			value.get("qualificationsByResident", {}) as Dictionary
		).get(resident_id_value)
		if not residents.has(resident_id) or not list_value is Array:
			return _failure("STAFFING_SAVE_INVALID")
		var normalized: Array[String] = []
		for occupation_value: Variant in list_value as Array:
			var occupation_id := String(occupation_value)
			if (
				not _chains_by_occupation.has(occupation_id)
				or normalized.has(occupation_id)
			):
				return _failure("STAFFING_SAVE_INVALID")
			normalized.append(occupation_id)
		normalized.sort()
		qualifications[resident_id] = normalized
	var arrangements: Dictionary = {}
	for arrangement_value: Variant in value.get(
		"arrangements",
		[],
	) as Array:
		if not arrangement_value is Dictionary:
			return _failure("STAFFING_SAVE_INVALID")
		var arrangement := (
			arrangement_value as Dictionary
		).duplicate(true)
		var arrangement_occupation_id := String(
			arrangement.get("occupationId", ""),
		)
		var chain := _chains_by_occupation.get(
			arrangement_occupation_id,
			{},
		) as Dictionary
		var expected_capabilities := _authorized_capabilities_for_chain(chain)
		if not arrangement.has("authorizedCapabilities"):
			arrangement["authorizedCapabilities"] = expected_capabilities
			if (
				String(chain.get("staffingEntryRule", "")) == "helper_only"
				and String(arrangement.get("mode", "")) == "part_time"
				and String(arrangement.get("status", "")) == "active"
			):
				arrangement["authorizesWork"] = true
		var saved_capabilities_value: Variant = arrangement.get(
			"authorizedCapabilities",
		)
		if not saved_capabilities_value is Array:
			return _failure("STAFFING_SAVE_INVALID")
		var saved_capabilities: Array[String] = []
		for capability_value: Variant in saved_capabilities_value as Array:
			var capability := String(capability_value).strip_edges()
			if capability.is_empty() or saved_capabilities.has(capability):
				return _failure("STAFFING_SAVE_INVALID")
			saved_capabilities.append(capability)
		if saved_capabilities != expected_capabilities:
			return _failure("STAFFING_SAVE_INVALID")
		var arrangement_id := String(
			arrangement.get("arrangementId", ""),
		)
		if (
			arrangement_id.is_empty()
			or arrangements.has(arrangement_id)
			or not residents.has(String(
				arrangement.get("residentId", ""),
			))
			or not _chains_by_occupation.has(arrangement_occupation_id)
			or String(arrangement.get("mode", ""))
			not in ["part_time", "shift", "trial"]
			or String(arrangement.get("status", ""))
			not in ["active", "completed", "failed", "ended"]
		):
			return _failure("STAFFING_SAVE_INVALID")
		arrangements[arrangement_id] = arrangement
	_qualifications_by_resident = qualifications
	_arrangements = arrangements
	_arrangement_sequence = int(
		value.get("arrangementSequence", 0),
	)
	_compact_terminal_arrangements()
	return rebuild(residents, absolute_minute)


func _occupation_id_for_resident(resident: Dictionary) -> String:
	var social_state := resident.get("socialState", {}) as Dictionary
	var job := String(social_state.get("job", ""))
	for value: Variant in _world_data.get("occupations", []) as Array:
		if not value is Dictionary:
			continue
		var occupation := value as Dictionary
		if (
			String(occupation.get("label", "")) == job
			or (occupation.get("aliases", []) as Array).has(job)
		):
			return String(occupation.get("occupationId", ""))
	return ""


func _authorized_capabilities_for_chain(chain: Dictionary) -> Array:
	return (
		(chain.get("helperTaskCapabilities", []) as Array).duplicate()
		if String(chain.get("staffingEntryRule", "")) == "helper_only"
		else (chain.get("taskCapabilities", []) as Array).duplicate()
	)


func _physical_capacity(occupation: Dictionary) -> int:
	var fixed_work_area_ids := occupation.get(
		"fixedWorkAreaIds",
		[],
	) as Array
	if not fixed_work_area_ids.is_empty():
		return fixed_work_area_ids.size()
	var allowed_tags := occupation.get(
		"allowedActivityTags",
		[],
	) as Array
	var primary_workplace := String(
		occupation.get("primaryWorkplacePlace", ""),
	)
	var activities_by_id: Dictionary = {}
	for value: Variant in _world_data.get(
		"activityDefinitions",
		[],
	) as Array:
		if value is Dictionary:
			var activity := value as Dictionary
			activities_by_id[String(
				activity.get("activityId", ""),
			)] = activity
	var positions: Dictionary = {}
	for value: Variant in _world_data.get(
		"activitySlots",
		[],
	) as Array:
		if not value is Dictionary:
			continue
		var slot := value as Dictionary
		var activity := activities_by_id.get(
			String(slot.get("activityId", "")),
			{},
		) as Dictionary
		if (
			String(slot.get("role", "")) != "worker"
			or String(slot.get("placeName", "")) != primary_workplace
			or not _arrays_intersect(
				activity.get("tags", []) as Array,
				allowed_tags,
			)
		):
			continue
		for member_value: Variant in slot.get(
			"memberAnchors",
			[],
		) as Array:
			if not member_value is Dictionary:
				continue
			var position := (
				(member_value as Dictionary).get(
					"position",
					[],
				) as Array
			)
			if position.size() == 2:
				positions["%s,%s" % [position[0], position[1]]] = true
	return maxi(positions.size(), 1)


func _arrays_intersect(left: Array, right: Array) -> bool:
	for value: Variant in left:
		if right.has(value):
			return true
	return false


func _empty_snapshot() -> Dictionary:
	return {
		"schemaVersion": 1,
		"posts": [],
		"vacantPostIds": [],
		"duplicatePostIds": [],
		"capacityConflictPostIds": [],
		"unassignedResidentIds": [],
		"temporarilyAbsentResidentIds": [],
		"qualificationsByResident": {},
		"arrangements": [],
		"arrangementSequence": 0,
		"absoluteMinute": 0,
	}


func _resident_temporarily_absent(
	resident: Dictionary,
	absolute_minute: int,
) -> bool:
	var attendance := resident.get("attendanceState", {}) as Dictionary
	return (
		String(attendance.get("status", "available")) == "on_leave"
		and int(attendance.get("untilMinute", -1)) > absolute_minute
	)


func _record_qualification(
	resident_id: String,
	occupation_id: String,
) -> void:
	if resident_id.is_empty() or occupation_id.is_empty():
		return
	var qualifications := (
		_qualifications_by_resident.get(resident_id, []) as Array
	).duplicate()
	if not qualifications.has(occupation_id):
		qualifications.append(occupation_id)
		qualifications.sort()
	_qualifications_by_resident[resident_id] = qualifications


func _arrangement_snapshots() -> Array[Dictionary]:
	var ids: Array[String] = []
	for arrangement_id_value: Variant in _arrangements:
		ids.append(String(arrangement_id_value))
	ids.sort()
	var result: Array[Dictionary] = []
	for arrangement_id: String in ids:
		result.append(
			(
				_arrangements.get(
					arrangement_id,
					{},
				) as Dictionary
			).duplicate(true),
		)
	return result


func _compact_terminal_arrangements() -> void:
	var terminal: Array[Dictionary] = []
	for value: Variant in _arrangements.values():
		var arrangement := value as Dictionary
		if String(arrangement.get("status", "")) != "active":
			terminal.append(arrangement)
	if terminal.size() <= MAX_TERMINAL_ARRANGEMENTS:
		return
	terminal.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_minute := int(left.get(
			"completedAtMinute",
			left.get("createdAtMinute", 0),
		))
		var right_minute := int(right.get(
			"completedAtMinute",
			right.get("createdAtMinute", 0),
		))
		if left_minute != right_minute:
			return left_minute < right_minute
		return String(left.get("arrangementId", "")) < String(
			right.get("arrangementId", ""),
		)
	)
	var remove_count := terminal.size() - MAX_TERMINAL_ARRANGEMENTS
	for index in remove_count:
		_arrangements.erase(String(
			terminal[index].get("arrangementId", ""),
		))


func _arrangement_active_at(
	arrangement: Dictionary,
	absolute_minute: int,
) -> bool:
	if String(arrangement.get("mode", "")) == "part_time":
		return true
	if String(arrangement.get("mode", "")) != "shift":
		return false
	var minute_of_day := posmod(absolute_minute, 1440)
	return (
		minute_of_day
		>= int(arrangement.get("shiftStartMinute", 0))
		and minute_of_day
		< int(arrangement.get("shiftEndMinute", 1440))
	)


func _failure(error_code: String) -> Dictionary:
	return RESULT_SHAPES.failure_minimal(error_code)
