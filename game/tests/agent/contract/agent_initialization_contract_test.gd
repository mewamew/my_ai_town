extends "res://tests/agent/support/AgentTestCase.gd"


const AgentContractScript := preload("res://agent/AgentContract.gd")
const AgentDebugScenariosScript := preload("res://agent/debug/AgentDebugScenarios.gd")
const ResidentStateMigrationScript := preload(
	"res://agent/lifecycle/AgentResidentStateMigration.gd"
)


func _initialize() -> void:
	var scenarios: RefCounted = AgentDebugScenariosScript.new()
	var valid: Dictionary = scenarios.call("initialization")
	_expect_equal(
		AgentContractScript.validate_initialization(valid),
		[],
		"标准居民初始化资料通过 JSON 契约",
	)
	var shop_without_owner := valid.duplicate(true)
	(shop_without_owner.get("places", []) as Array).append({
		"name": "无固定负责人的工作坊",
		"type": "铺面",
		"owner": null,
		"owner_resident_id": null,
		"summary": "由当前职业岗位中的居民提供服务",
		"features": ["工作台"],
	})
	_expect_equal(
		AgentContractScript.validate_initialization(shop_without_owner),
		[],
		"铺面可以不绑定固定居民负责人",
	)
	var homes := valid.duplicate(true)
	(homes.get("places", []) as Array).append_array([{
		"name": "林岚家",
		"type": "住家",
		"owner": "林岚",
		"owner_resident_id": "resident-lin-lan",
		"summary": "林岚已经入住的住宅",
	}, {
		"name": "空置住宅",
		"type": "住家",
		"owner": null,
		"owner_resident_id": null,
		"summary": "本局暂时无人入住的住宅",
	}])
	_expect_equal(
		AgentContractScript.validate_initialization(homes),
		[],
		"居民初始化允许住宅保持空置",
	)
	var incomplete_home_owner := homes.duplicate(true)
	var incomplete_home := (
		(incomplete_home_owner.get("places", []) as Array)[-1]
		as Dictionary
	)
	incomplete_home["owner"] = "幽灵居民"
	_expect_error_contains(
		{
			"ok": false,
			"errors": AgentContractScript.validate_initialization(
				incomplete_home_owner,
			),
		},
		"住家主人姓名与居民 ID 必须同时为空或同时存在",
		"空置住宅不能只残留主人姓名",
	)
	var legacy_state := {"initialization": shop_without_owner.duplicate(true)}
	var legacy_shop := (
		(legacy_state.get("initialization") as Dictionary).get("places") as Array
	).back() as Dictionary
	legacy_shop["owner"] = "唐小满"
	legacy_shop["owner_resident_id"] = "resident-tang-xiao-man"
	var migrated := ResidentStateMigrationScript.migrate(legacy_state)
	_expect_equal(
		migrated.get("applied"),
		[ResidentStateMigrationScript.SHOP_OWNER_DERIVATION_MIGRATION_ID],
		"旧铺面负责人迁移有稳定编号",
	)
	var migrated_initialization := (
		(migrated.get("state") as Dictionary).get("initialization") as Dictionary
	)
	_expect_equal(
		AgentContractScript.validate_initialization(migrated_initialization),
		[],
		"旧铺面负责人迁移后符合当前契约",
	)
	_expect_equal(
		ResidentStateMigrationScript.migrate(migrated.get("state")).get("applied"),
		[],
		"旧铺面负责人迁移可重复执行",
	)
	var damaged_state := legacy_state.duplicate(true)
	var damaged_shop := (
		(damaged_state.get("initialization") as Dictionary).get("places") as Array
	).back() as Dictionary
	damaged_shop["owner_resident_id"] = "resident-not-found"
	_expect_equal(
		ResidentStateMigrationScript.migrate(damaged_state).get("applied"),
		[],
		"虚构的铺面负责人引用不会被迁移掩盖",
	)
	var cases: Array[Dictionary] = [
		{"id": "not_object", "value": [], "error": "初始化资料必须是对象"},
		{"id": "unknown_field", "value": _with_field(valid, "unknown", true), "error": "initialization.unknown"},
		{"id": "missing_me", "value": _without(valid, ["me"]), "error": "me 缺失"},
		{"id": "missing_speech", "value": _without(valid, ["me", "attributes", "speech"]), "error": "me.attributes.speech 缺失"},
		{"id": "nested_unknown_field", "value": _with(valid, ["me", "attributes", "api_key"], "secret"), "error": "me.attributes.api_key 不是允许字段"},
		{"id": "unsafe_resident_id", "value": _with_me_id(valid, "../resident"), "error": "me.resident_id 只能包含"},
		{"id": "uppercase_resident_id", "value": _with_me_id(valid, "Resident-Lin-Lan"), "error": "me.resident_id 只能包含"},
		{"id": "duplicate_resident_id", "value": _with_duplicate_id(valid), "error": "resident_id 必须在本局居民中唯一"},
		{"id": "invalid_place_type", "value": _with_place_type(valid, "未知地点"), "error": "places[0].type"},
	]
	for case: Dictionary in cases:
		_set_assertion_context({"case_id": case["id"], "expected_error": case["error"]})
		var errors: Array[String] = AgentContractScript.validate_initialization(case["value"])
		_expect_error_contains(
			{"ok": false, "errors": errors},
			String(case["error"]),
			"非法初始化资料必须由对应契约分支拒绝",
		)
	_clear_assertion_context()
	_finish_suite("AGENT_INITIALIZATION_CONTRACT_PASS")


func _with_field(source: Dictionary, field: String, value: Variant) -> Dictionary:
	var result := source.duplicate(true)
	result[field] = value
	return result


func _without(source: Dictionary, path: Array[String]) -> Dictionary:
	var result := source.duplicate(true)
	var target := result
	for index in path.size() - 1:
		target = target[path[index]] as Dictionary
	target.erase(path[-1])
	return result


func _with(source: Dictionary, path: Array[String], value: Variant) -> Dictionary:
	var result := source.duplicate(true)
	var target := result
	for index in path.size() - 1:
		target = target[path[index]] as Dictionary
	target[path[-1]] = value
	return result


func _with_me_id(source: Dictionary, resident_id: String) -> Dictionary:
	var result := source.duplicate(true)
	result["me"]["resident_id"] = resident_id
	return result


func _with_duplicate_id(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	result["residents"][0]["resident_id"] = result["me"]["resident_id"]
	return result


func _with_place_type(source: Dictionary, place_type: String) -> Dictionary:
	var result := source.duplicate(true)
	result["places"][0]["type"] = place_type
	return result
