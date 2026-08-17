extends "res://tests/support/TownWorldTestCase.gd"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var data := _build_data()
	var opening := _load_opening(data)
	var identities: Array[Dictionary] = []
	for resident_value: Variant in opening.get("residents", []) as Array:
		var resident := resident_value as Dictionary
		identities.append({
			"residentId": String(resident.get("residentId", "")),
			"residentName": String(
				(resident.get("attributes", {}) as Dictionary).get("name", "")
			),
		})
	var world := WORLD.new()
	var started := world.start(data, opening, identities) as Dictionary
	_expect(bool(started.get("ok", false)), "死亡确认验收世界可以启动")
	var resident_id := String(identities[0].get("residentId", ""))
	var before := world.get_resident_lifecycle_state(resident_id) as Dictionary
	var confirmed := world.confirm_resident_death(
		resident_id,
		"架构迁移回归测试",
		int(before.get("revision", -1)),
		str(world.get_instance_id()),
	) as Dictionary
	_expect(bool(confirmed.get("ok", false)), "死亡确认成功")
	_expect(bool(confirmed.get("changed", false)), "首次死亡确认会改变状态")
	_expect(
		not String((confirmed.get("event", {}) as Dictionary).get("event_id", "")).is_empty(),
		"死亡确认生成稳定事件编号",
	)
	_expect_equal(
		(world.get_resident_lifecycle_state(resident_id) as Dictionary).get("status"),
		"dead",
		"居民生命周期进入死亡状态",
	)
	var repeated := world.confirm_resident_death(
		resident_id,
		"架构迁移回归测试",
	) as Dictionary
	_expect(bool(repeated.get("ok", false)), "重复死亡确认保持幂等成功")
	_expect(not bool(repeated.get("changed", true)), "重复死亡确认不再次改变状态")
	_expect_equal(world.get_public_death_events().size(), 1, "死亡事件只记录一次")
	world.stop()
	_finish_suite("RESIDENT_DEATH_CONFIRMATION_ARCHITECTURE_PASS")
