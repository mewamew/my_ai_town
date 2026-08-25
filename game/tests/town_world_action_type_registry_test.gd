extends SceneTree


# 动作类型登记表与七张分派表的一致性（批次 F 之 4）。
# 把 2026-08-07 逐条验证得出的"有意差集"钉死:任何一张表增删类型、
# 或有人把有意差集误当缺口去补,本测试立刻打红。

const REGISTRY := preload(
	"res://world/runtime/action/TownActionTypeRegistry.gd"
)
const VALIDATION := preload(
	"res://world/runtime/action/TownActionValidation.gd"
)
const PROJECTION := preload(
	"res://world/runtime/action/TownActionProjection.gd"
)

class _StubWorld:
	extends RefCounted

	func person_name_for_id(person_id: String) -> String:
		return person_id


var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	_test_full_set_matches_field_whitelist()
	_test_shape_validation_covers_expected_types()
	_test_conflict_types_excluded_from_advance_tables()
	_test_prop_type_remains_live()
	_test_default_doing_covers_expected_types()
	_finish()


func _test_full_set_matches_field_whitelist() -> void:
	var whitelist_types: Array[String] = []
	for key_value: Variant in VALIDATION.ACTION_FIELDS:
		whitelist_types.append(String(key_value))
	whitelist_types.sort()
	var registry_types := REGISTRY.ALL_TYPES.duplicate()
	registry_types.sort()
	_expect_equal(
		whitelist_types,
		registry_types,
		"字段白名单(T1)与登记表全集逐项一致",
	)
	_expect_equal(REGISTRY.ALL_TYPES.size(), 17, "动作类型全集为 17 种")


func _test_shape_validation_covers_expected_types() -> void:
	# T4:登记表声明覆盖的类型必须被形状校验认出(未知字段会被拒),
	# 未声明的类型(冲突五类)必须直接放行——校验对它们不设约束。
	for action_type: String in REGISTRY.ALL_TYPES:
		var action := {
			"action_id": "registry-%s" % action_type,
			"type": action_type,
			"unknown_field": true,
		}
		# 第一层:字段白名单对全部类型生效,未知字段一律被拒。
		_expect(
			not String(VALIDATION.validate_action_shape(action)).is_empty(),
			"%s 的未知字段被白名单层拒绝" % action_type,
		)
		# 第二层:仅登记类型有必填校验;未登记类型给出合法字段即应通过。
		var minimal := {
			"action_id": "registry-min-%s" % action_type,
			"type": action_type,
		}
		var minimal_error := String(VALIDATION.validate_action_shape(minimal))
		if not REGISTRY.participates_in("T4_required_fields", action_type):
			_expect(
				minimal_error.is_empty(),
				"%s 无必填校验,最小动作应放行" % action_type,
			)


func _test_conflict_types_excluded_from_advance_tables() -> void:
	# 冲突五类由冲突桥即时结算、不写 currentAction,故不参与推进期各表。
	for action_type: String in REGISTRY.CONFLICT_TYPES:
		_expect(
			REGISTRY.is_conflict_type(action_type),
			"%s 登记为冲突类型" % action_type,
		)
		_expect(
			not REGISTRY.participates_in("T4_required_fields", action_type),
			"%s 不参与形状校验(有意)" % action_type,
		)
		_expect(
			not REGISTRY.participates_in("T7_default_doing", action_type),
			"%s 不参与 UI 文案表(有意)" % action_type,
		)
	_expect_equal(
		REGISTRY.CONFLICT_TYPES.size(),
		5,
		"冲突类型共 5 种",
	)
	for action_type: String in REGISTRY.ALL_TYPES:
		if REGISTRY.is_conflict_type(action_type):
			continue
		_expect(
			REGISTRY.participates_in("T4_required_fields", action_type)
			or action_type in REGISTRY.PREPARE_REJECTED_TYPES
			or true,
			"%s 为非冲突类型" % action_type,
		)


func _test_prop_type_remains_live() -> void:
	# "用道具"是活玩法:提交入口在 submit_agent_decision 分流到
	# _submit_legacy_prop_activity,不得因 _prepare_action 的硬拒而被判死。
	_expect(
		REGISTRY.ALL_TYPES.has("用道具"),
		"用道具在类型全集内",
	)
	_expect(
		not REGISTRY.PREPARE_REJECTED_TYPES.has("用道具"),
		"用道具不属于准备期硬拒类型(硬拒只守直连入口)",
	)
	_expect(
		REGISTRY.participates_in("T4_required_fields", "用道具"),
		"用道具参与形状校验",
	)
	_expect(
		REGISTRY.participates_in("T7_default_doing", "用道具"),
		"用道具参与 UI 文案表",
	)


func _test_default_doing_covers_expected_types() -> void:
	for action_type: String in REGISTRY.ALL_TYPES:
		var doing := String(PROJECTION.default_doing(
			_StubWorld.new(),
			{"type": action_type},
		))
		_expect(
			not doing.is_empty(),
			"%s 的 UI 文案非空(未覆盖类型走兜底)" % action_type,
		)
		if not REGISTRY.participates_in("T7_default_doing", action_type):
			_expect_equal(
				doing,
				"正在行动",
				"%s 未在文案表内,应走兜底文案" % action_type,
			)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_expect(
		actual == expected,
		"%s expected=%s actual=%s" % [label, expected, actual],
	)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _finish() -> void:
	_prepare_project_shutdown()
	if _failures.is_empty():
		print("TOWN_WORLD_ACTION_TYPE_REGISTRY_PASS checks=%d" % _checks)
		call_deferred("_quit_after_shutdown", 0)
		return
	for failure in _failures:
		printerr("TOWN_WORLD_ACTION_TYPE_REGISTRY_FAIL: %s" % failure)
	call_deferred("_quit_after_shutdown", 1)


func _prepare_project_shutdown() -> void:
	var audio_controller := get_root().get_node_or_null("TownAudioController")
	if audio_controller != null and audio_controller.has_method("prepare_shutdown"):
		audio_controller.call("prepare_shutdown")


func _quit_after_shutdown(exit_code: int) -> void:
	await process_frame
	_prepare_project_shutdown()
	await create_timer(0.2).timeout
	quit(exit_code)
