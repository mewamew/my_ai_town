class_name TownWorkChainCatalog
extends RefCounted


const WORLD_SCALARS := preload("res://world/data/town/TownWorldScalars.gd")
const CATALOG_PATH := "res://world/data/town/work_chain_catalog.json"
const OCCUPATION_PATH := (
	"res://world/data/town/source/occupation_catalog.json"
)
const REQUIRED_CHAIN_FIELDS: Array[String] = [
	"occupationId",
	"taskCapabilities",
	"taskSources",
	"targetKinds",
	"resultKinds",
	"upstreamOccupationIds",
	"downstreamOccupationIds",
	"noTaskFallback",
	"staffingEntryRule",
	"vacancyEffect",
]
const STAFFING_ENTRY_RULES := [
	"direct",
	"helper_only",
	"qualification_required",
	"performance_required",
]


static func load_catalog() -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(CATALOG_PATH),
	)
	if not parsed is Dictionary:
		return {}
	var catalog := (parsed as Dictionary).duplicate(true)
	return catalog if validate(catalog).is_empty() else {}


static func validate(catalog: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if not _exact_keys(
		catalog,
		[
			"schemaVersion",
			"worldId",
			"taskStates",
			"targetKinds",
			"itemKinds",
			"baseSupplyItems",
			"baseServiceItems",
			"specialtyCargoItems",
			"openingInputs",
			"activityBindings",
			"serviceBindings",
			"chains",
		],
	):
		errors.append("工作链目录字段无效")
	if int(catalog.get("schemaVersion", 0)) != 1:
		errors.append("工作链目录 schemaVersion 无效")
	if String(catalog.get("worldId", "")) != "town":
		errors.append("工作链目录 worldId 无效")
	var task_states := _string_array(
		catalog.get("taskStates"),
		"taskStates",
		errors,
	)
	for required_state: String in [
		"open",
		"accepted",
		"in_progress",
		"waiting",
		"completed",
		"failed",
		"cancelled",
	]:
		if not task_states.has(required_state):
			errors.append("工作链缺少任务状态：%s" % required_state)
	var allowed_target_kinds := _string_array(
		catalog.get("targetKinds"),
		"targetKinds",
		errors,
	)
	for required_kind: String in [
		"prop",
		"region",
		"route",
		"resident",
		"cargo_lot",
		"service_request",
	]:
		if not allowed_target_kinds.has(required_kind):
			errors.append("工作链缺少目标类型：%s" % required_kind)
	var item_kinds := _string_array(
		catalog.get("itemKinds"),
		"itemKinds",
		errors,
	)
	if item_kinds.is_empty():
		errors.append("工作链缺少物品种类")
	var base_supply_items := _string_array(
		catalog.get("baseSupplyItems"),
		"baseSupplyItems",
		errors,
	)
	var base_service_items := _string_array(
		catalog.get("baseServiceItems"),
		"baseServiceItems",
		errors,
	)
	var specialty_cargo_items := _string_array(
		catalog.get("specialtyCargoItems"),
		"specialtyCargoItems",
		errors,
	)
	var classified_items: Dictionary = {}
	for classification: Array[String] in [
		base_supply_items,
		base_service_items,
		specialty_cargo_items,
	]:
		for item_id: String in classification:
			if not item_kinds.has(item_id):
				errors.append("工作链物品分类引用未知物品：%s" % item_id)
			elif classified_items.has(item_id):
				errors.append("工作链物品分类重复：%s" % item_id)
			classified_items[item_id] = true
	for item_id: String in item_kinds:
		if not classified_items.has(item_id):
			errors.append("工作链物品没有供给分类：%s" % item_id)
	var opening_inputs: Variant = catalog.get("openingInputs")
	if (
		not opening_inputs is Dictionary
		or not bool((opening_inputs as Dictionary).get(
			"openingStockInitializedOnce",
			false,
		))
		or String((opening_inputs as Dictionary).get(
			"baseSupplyMode",
			"",
		)) != "always_available"
		or String((opening_inputs as Dictionary).get(
			"externalSupplyPlaceId",
			"",
		)) != "南入口"
		or not bool((opening_inputs as Dictionary).get(
			"externalSupplyDemandDriven",
			false,
		))
		or (
			(opening_inputs as Dictionary).get(
				"externalSupplyItems",
				[],
			) as Array
		).is_empty()
	):
		errors.append("工作链供给边界无效")
	elif not (opening_inputs as Dictionary).get(
		"openingInventoryByPlace",
	) is Dictionary:
		errors.append("工作链开局库存必须是地点对象")
	else:
		var opening_inventory := (
			(opening_inputs as Dictionary).get(
				"openingInventoryByPlace",
				{},
			) as Dictionary
		)
		if not opening_inventory.is_empty():
			errors.append("基础供给不能通过开局库存初始化")
		for item_value: Variant in (
			(opening_inputs as Dictionary).get(
				"externalSupplyItems",
				[],
			) as Array
		):
			if not specialty_cargo_items.has(String(item_value)):
				errors.append(
					"外来货批只能使用特色物品：%s" % str(item_value),
				)

	var occupation_document := _read_json(OCCUPATION_PATH)
	var occupation_by_id: Dictionary = {}
	for value: Variant in (
		occupation_document.get("occupations", []) as Array
	):
		if value is Dictionary:
			occupation_by_id[String(
				(value as Dictionary).get("occupationId", ""),
			)] = value
	var chains_value: Variant = catalog.get("chains")
	if not chains_value is Array:
		errors.append("工作链目录 chains 必须是数组")
		return errors
	var chain_ids: Dictionary = {}
	var all_capabilities: Dictionary = {}
	var chains_by_capability: Dictionary = {}
	for value: Variant in chains_value as Array:
		if not value is Dictionary:
			errors.append("工作链条目必须是对象")
			continue
		var chain := value as Dictionary
		var expected_chain_fields := REQUIRED_CHAIN_FIELDS.duplicate()
		if chain.has("helperTaskCapabilities"):
			expected_chain_fields.append("helperTaskCapabilities")
		if not _exact_keys(chain, expected_chain_fields):
			errors.append("工作链条目字段无效")
		var occupation_id := String(
			chain.get("occupationId", ""),
		).strip_edges()
		if (
			occupation_id.is_empty()
			or chain_ids.has(occupation_id)
			or not occupation_by_id.has(occupation_id)
		):
			errors.append("工作链职业无效：%s" % occupation_id)
			continue
		chain_ids[occupation_id] = true
		var capabilities := _string_array(
			chain.get("taskCapabilities"),
			"%s.taskCapabilities" % occupation_id,
			errors,
		)
		var occupation := occupation_by_id.get(
			occupation_id,
			{},
		) as Dictionary
		var expected_capabilities := _normalized_strings(
			occupation.get("taskCapabilities", []),
		)
		for capability: String in expected_capabilities:
			all_capabilities[capability] = true
			var capability_chains := (
				chains_by_capability.get(capability, []) as Array
			).duplicate()
			capability_chains.append(chain.duplicate(true))
			chains_by_capability[capability] = capability_chains
		if capabilities != expected_capabilities:
			errors.append("工作链能力与职业目录不一致：%s" % occupation_id)
		var helper_capabilities := _string_array(
			chain.get("helperTaskCapabilities", []),
			"%s.helperTaskCapabilities" % occupation_id,
			errors,
			true,
		)
		var entry_rule := String(chain.get("staffingEntryRule", ""))
		if entry_rule == "helper_only" and helper_capabilities.is_empty():
			errors.append("帮工岗位缺少明确辅助能力：%s" % occupation_id)
		elif entry_rule != "helper_only" and not helper_capabilities.is_empty():
			errors.append("非帮工岗位不能声明辅助能力：%s" % occupation_id)
		for capability: String in helper_capabilities:
			if not capabilities.has(capability):
				errors.append(
					"帮工能力不属于正式工作链：%s.%s"
					% [occupation_id, capability],
				)
		if _string_array(
			chain.get("taskSources"),
			"%s.taskSources" % occupation_id,
			errors,
		).is_empty():
			errors.append("工作链没有真实任务来源：%s" % occupation_id)
		var target_kinds := _string_array(
			chain.get("targetKinds"),
			"%s.targetKinds" % occupation_id,
			errors,
		)
		for target_kind: String in target_kinds:
			if not allowed_target_kinds.has(target_kind):
				errors.append(
					"工作链使用未知目标类型：%s.%s"
					% [occupation_id, target_kind],
				)
		if _string_array(
			chain.get("resultKinds"),
			"%s.resultKinds" % occupation_id,
			errors,
		).is_empty():
			errors.append("工作链没有最小结果：%s" % occupation_id)
		for dependency_field: String in [
			"upstreamOccupationIds",
			"downstreamOccupationIds",
		]:
			var dependencies := _string_array(
				chain.get(dependency_field),
				"%s.%s" % [occupation_id, dependency_field],
				errors,
				true,
			)
			if dependencies.has(occupation_id):
				errors.append("工作链不能依赖自身：%s" % occupation_id)
		for text_field: String in ["noTaskFallback", "vacancyEffect"]:
			if String(chain.get(text_field, "")).strip_edges().is_empty():
				errors.append(
					"工作链缺少 %s：%s" % [text_field, occupation_id],
				)
		if entry_rule not in (
			STAFFING_ENTRY_RULES
		):
			errors.append("工作链转岗条件无效：%s" % occupation_id)
	for occupation_id: String in occupation_by_id:
		if not chain_ids.has(occupation_id):
			errors.append("正式职业缺少工作链：%s" % occupation_id)
	for value: Variant in chains_value as Array:
		if not value is Dictionary:
			continue
		var chain := value as Dictionary
		for dependency_field: String in [
			"upstreamOccupationIds",
			"downstreamOccupationIds",
		]:
			for dependency_id: String in _normalized_strings(
				chain.get(dependency_field, []),
			):
				if not chain_ids.has(dependency_id):
					errors.append(
						"工作链引用未知职业：%s"
						% dependency_id,
					)
	var activity_bindings_value: Variant = catalog.get(
		"activityBindings",
	)
	if not activity_bindings_value is Dictionary:
		errors.append("工作链 activityBindings 必须是对象")
	else:
		var activity_document := _read_json(
			"res://world/data/town/source/activity_definitions.json",
		)
		var slot_document := _read_json(
			"res://world/data/town/source/activity_slots.json",
		)
		var activity_ids: Dictionary = {}
		for activity_value: Variant in (
			activity_document.get("activities", []) as Array
		):
			if activity_value is Dictionary:
				activity_ids[String(
					(activity_value as Dictionary).get("activityId", ""),
				)] = true
		for activity_id_value: Variant in (
			activity_bindings_value as Dictionary
		):
			var activity_id := String(activity_id_value)
			if not activity_ids.has(activity_id):
				errors.append(
					"工作链绑定未知活动：%s" % activity_id,
				)
			var bound_capabilities := _string_array(
				(activity_bindings_value as Dictionary).get(
					activity_id_value,
				),
				"activityBindings.%s" % activity_id,
				errors,
			)
			for capability: String in bound_capabilities:
				if not all_capabilities.has(capability):
					errors.append(
						"工作链活动绑定未知能力：%s.%s"
						% [activity_id, capability],
					)
		var worker_activity_ids: Dictionary = {}
		for slot_value: Variant in (
			slot_document.get("slots", []) as Array
		):
			if (
				slot_value is Dictionary
				and String(
					(slot_value as Dictionary).get("role", ""),
				) == "worker"
			):
				worker_activity_ids[String(
					(slot_value as Dictionary).get("activityId", ""),
				)] = true
		for activity_id: String in worker_activity_ids:
			if not (activity_bindings_value as Dictionary).has(
				activity_id,
			):
				errors.append(
					"职业活动没有真实任务绑定：%s"
					% activity_id,
				)
	var service_bindings_value: Variant = catalog.get("serviceBindings")
	if not service_bindings_value is Dictionary:
		errors.append("工作链 serviceBindings 必须是对象")
	else:
		for place_id_value: Variant in service_bindings_value:
			var place_id := String(place_id_value).strip_edges()
			var binding_value: Variant = (
				service_bindings_value as Dictionary
			).get(place_id_value)
			if not binding_value is Dictionary:
				errors.append("地点服务任务绑定必须是对象：%s" % place_id)
				continue
			var binding := binding_value as Dictionary
			if not _exact_keys(
				binding,
				[
					"helperActivityId",
					"capability",
					"sourceKind",
					"resultKind",
				],
			):
				errors.append("地点服务任务绑定字段无效：%s" % place_id)
				continue
			var helper_activity_id := String(
				binding.get("helperActivityId", ""),
			).strip_edges()
			var capability := String(
				binding.get("capability", ""),
			).strip_edges()
			var source_kind := String(
				binding.get("sourceKind", ""),
			).strip_edges()
			var result_kind := String(
				binding.get("resultKind", ""),
			).strip_edges()
			if (
				place_id.is_empty()
				or helper_activity_id.is_empty()
				or capability.is_empty()
				or source_kind.is_empty()
				or result_kind.is_empty()
			):
				errors.append("地点服务任务绑定内容为空：%s" % place_id)
				continue
			if not (
				_normalized_strings(
					(activity_bindings_value as Dictionary).get(
						helper_activity_id,
						[],
					),
				)
			).has(capability):
				errors.append(
					"地点服务任务能力与帮助活动不匹配：%s"
					% place_id,
				)
				continue
			var compatible_chain := false
			for chain_value: Variant in (
				chains_by_capability.get(capability, []) as Array
			):
				var chain := chain_value as Dictionary
				if (
					(chain.get("taskSources", []) as Array).has(
						source_kind,
					)
					and (chain.get("resultKinds", []) as Array).has(
						result_kind,
					)
					and (chain.get("targetKinds", []) as Array).has(
						"service_request",
					)
				):
					compatible_chain = true
					break
			if not compatible_chain:
				errors.append(
					"地点服务任务来源、目标或结果与职业链不匹配：%s"
					% place_id,
				)
	return errors


static func chain_for(
	catalog: Dictionary,
	occupation_id: String,
) -> Dictionary:
	for value: Variant in catalog.get("chains", []) as Array:
		if (
			value is Dictionary
			and String((value as Dictionary).get("occupationId", ""))
			== occupation_id
		):
			return (value as Dictionary).duplicate(true)
	return {}


static func capabilities_for_activity(
	catalog: Dictionary,
	activity_id: String,
) -> Array[String]:
	return _normalized_strings(
		(
			catalog.get("activityBindings", {}) as Dictionary
		).get(activity_id, []),
	)


static func service_binding_for(
	catalog: Dictionary,
	place_id: String,
) -> Dictionary:
	var value: Variant = (
		catalog.get("serviceBindings", {}) as Dictionary
	).get(place_id)
	return (
		(value as Dictionary).duplicate(true)
		if value is Dictionary
		else {}
	)


static func _string_array(
	value: Variant,
	path: String,
	errors: PackedStringArray,
	allow_empty := false,
) -> Array[String]:
	if not value is Array:
		errors.append("%s 必须是数组" % path)
		return []
	var result := _normalized_strings(value)
	if result.size() != (value as Array).size():
		errors.append("%s 包含空值或重复值" % path)
	if result.is_empty() and not allow_empty:
		errors.append("%s 不能为空" % path)
	return result


static func _normalized_strings(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		return result
	for item: Variant in value as Array:
		var text := String(item).strip_edges()
		if not text.is_empty() and not result.has(text):
			result.append(text)
	return result


static func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(path),
	)
	return (
		(parsed as Dictionary).duplicate(true)
		if parsed is Dictionary
		else {}
	)


static func _exact_keys(
	value: Dictionary,
	expected: Array,
) -> bool:
	return WORLD_SCALARS.exact_keys_sorted(value, expected)
