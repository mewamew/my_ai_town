extends "res://tests/support/TownWorldTestCase.gd"
## 冲突运行时与化身攻击表现的聚焦契约测试。


const CONFLICT_RUNTIME := preload(
	"res://world/runtime/conflict/TownConflictRuntime.gd"
)
const WORLD_RUNTIME := preload("res://world/runtime/TownWorldRuntime.gd")
const CONFLICT_PRESENTATION := preload(
	"res://world/presentation/conflict/TownConflictPresentation.gd"
)


class FakeCharacterSprite:
	extends Node2D

	var direction_name := "right"

	func get_direction_name() -> String:
		return direction_name


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_runtime_metadata_and_follow_up()
	await _test_attacker_direction_and_flip()
	_test_post_injury_reaction_gate()
	_finish_suite("town_conflict_contract")


func _test_runtime_metadata_and_follow_up() -> void:
	var runtime := CONFLICT_RUNTIME.new()
	var configure_result := runtime.configure({
		"heavyTreatmentMinutes": 120,
	}) as Dictionary
	_expect_equal(
		configure_result.get("ok"),
		true,
		"conflict runtime configures for focused contract test",
	)

	var first := runtime.record_avatar_area_cast({
		"requestId": "attack-1",
		"attackerId": "avatar",
		"attackKind": "avatar_rasengan",
		"sourceKind": "avatar_intent",
		"sourceRef": "avatar-input-1",
		"hitTargetIds": ["resident-b", "resident-c"],
		"placeId": "社区花园",
		"spaceId": "town_outdoor",
		"occurredAtMinute": 10,
		"worldRevision": 4,
	}) as Dictionary
	_expect_equal(first.get("ok"), true, "area cast is accepted")
	var cast_event := _event_of_type(
		first.get("events", []) as Array,
		"avatar_area_attack_cast",
	)
	_expect_equal(
		cast_event.get("attackKind"),
		"avatar_rasengan",
		"cast event preserves attackKind",
	)
	_expect_equal(
		cast_event.get("hitTargetIds"),
		["resident-b", "resident-c"],
		"cast event preserves hitTargetIds",
	)
	_expect_equal(
		cast_event.get("sourceKind"),
		"avatar_intent",
		"cast event preserves sourceKind",
	)
	var first_projection := runtime.get_public_projection() as Dictionary
	_expect(
		not (first_projection.get("events", []) as Array).is_empty(),
		"public conflict projection keeps event history",
	)
	_expect_equal(
		(runtime.get_public_projection(false) as Dictionary).get("events"),
		[],
		"agent conflict projection omits historical events",
	)
	var first_injury := _injury_of_actor(
		first_projection.get("injuries", []) as Array,
		"resident-b",
	)
	_expect_equal(
		first_injury.get("sourceKind"),
		"avatar_intent",
		"injury projection preserves sourceKind",
	)
	_expect_equal(
		first_injury.get("sourceRef"),
		"avatar-input-1",
		"injury projection preserves sourceRef",
	)
	_expect_equal(
		first_injury.get("treatmentStatus"),
		"not_required",
		"light injury keeps treatment status",
	)

	var second := runtime.record_avatar_area_cast({
		"requestId": "attack-2",
		"attackerId": "avatar",
		"attackKind": "unarmed",
		"sourceKind": "avatar_intent",
		"sourceRef": "avatar-input-2",
		"hitTargetIds": ["resident-b"],
		"placeId": "社区花园",
		"spaceId": "town_outdoor",
		"occurredAtMinute": 11,
		"worldRevision": 5,
	}) as Dictionary
	_expect_equal(second.get("ok"), true, "second area cast is accepted")
	var heavy_follow_up := runtime.get_follow_up("resident-b") as Dictionary
	_expect_equal(
		heavy_follow_up.get("required"),
		true,
		"heavy injury still requires follow-up",
	)
	_expect_equal(
		heavy_follow_up.get("kind"),
		"go_to_clinic",
		"heavy injury follow-up goes to clinic",
	)
	_expect_equal(
		heavy_follow_up.get("treatmentStatus"),
		"required",
		"follow-up exposes treatment status",
	)
	_expect_equal(
		heavy_follow_up.get("treatmentPlaceId"),
		"",
		"follow-up exposes treatment place metadata",
	)
	_expect_equal(
		heavy_follow_up.get("treatmentDueAtMinute"),
		-1,
		"untreated injury has no treatment due minute",
	)
	var heavy_event := _event_of_type(
		second.get("events", []) as Array,
		"injury_applied",
	)
	_expect_equal(
		heavy_event.get("sourceKind"),
		"avatar_intent",
		"injury event preserves sourceKind",
	)
	_expect_equal(
		heavy_event.get("treatmentStatus"),
		"required",
		"injury event preserves treatment status",
	)


func _test_attacker_direction_and_flip() -> void:
	var presentation := CONFLICT_PRESENTATION.new()
	get_root().add_child(presentation)
	var configure_result := presentation.configure({
		"avatarAttackDurationSeconds": 3.0,
	}) as Dictionary
	_expect_equal(
		configure_result.get("ok"),
		true,
		"conflict presentation configures for focused contract test",
	)

	var attacker := Node2D.new()
	attacker.name = "AttackerAuthority"
	attacker.position = Vector2.ZERO
	get_root().add_child(attacker)
	var attacker_visual := Node2D.new()
	attacker_visual.name = "AttackerVisual"
	attacker.add_child(attacker_visual)
	var character_sprite := FakeCharacterSprite.new()
	character_sprite.name = "CharacterSprite"
	character_sprite.direction_name = "left"
	attacker_visual.add_child(character_sprite)
	var target := Node2D.new()
	target.name = "TargetAuthority"
	target.position = Vector2(200.0, 0.0)
	get_root().add_child(target)
	presentation.register_actor("avatar", attacker, attacker_visual, "avatar")
	presentation.register_actor("resident-b", target, target, "resident")

	var left_result := presentation.apply_public_projection({
		"revision": 1,
		"activeConflicts": [],
		"injuries": [],
		"events": [{
			"eventId": "avatar-attack-left",
			"type": "avatar_area_attack_cast",
			"conflictId": "cast-left",
			"actorIds": ["avatar", "resident-b"],
			"sourceActorId": "avatar",
			"attackKind": "unarmed",
			"hitTargetIds": ["resident-b"],
			"sourceKind": "avatar_intent",
		}],
	}) as Dictionary
	_expect_equal(left_result.get("ok"), true, "left-facing cast is presented")
	var left_attack := _avatar_attack_of(
		presentation.debug_snapshot().get("avatarAttacks", []) as Array,
		"cast-left",
	)
	_expect_equal(
		left_attack.get("direction"),
		-1.0,
		"left-facing attacker drives effect direction",
	)
	_expect_equal(
		left_attack.get("flipH"),
		true,
		"left-facing attacker flips effect horizontally",
	)

	presentation.advance_presentation(3.1)
	await process_frame
	character_sprite.direction_name = "right"
	target.position = Vector2(-200.0, 0.0)
	var right_result := presentation.apply_public_projection({
		"revision": 2,
		"activeConflicts": [],
		"injuries": [],
		"events": [{
			"eventId": "avatar-attack-right",
			"type": "avatar_area_attack_cast",
			"conflictId": "cast-right",
			"actorIds": ["avatar", "resident-b"],
			"sourceActorId": "avatar",
			"attackKind": "unarmed",
			"hitTargetIds": ["resident-b"],
			"sourceKind": "avatar_intent",
		}],
	}) as Dictionary
	_expect_equal(right_result.get("ok"), true, "right-facing cast is presented")
	var right_attack := _avatar_attack_of(
		presentation.debug_snapshot().get("avatarAttacks", []) as Array,
		"cast-right",
	)
	_expect_equal(
		right_attack.get("direction"),
		1.0,
		"right-facing attacker drives effect direction",
	)
	_expect_equal(
		right_attack.get("flipH"),
		false,
		"right-facing attacker keeps effect unflipped",
	)

	presentation.queue_free()
	attacker.queue_free()
	target.queue_free()
	await process_frame


func _test_post_injury_reaction_gate() -> void:
	var runtime := WORLD_RUNTIME.new()
	var reaction := runtime.call(
		"_post_injury_reaction_for_events",
		"resident-b",
		[{
			"type": "冲突见闻",
			"knowledge_kind": "participant",
			"conflict_event_type": "injury_applied",
			"actor_ids": ["resident-a", "resident-b"],
			"source_actor_id": "resident-a",
			"subject_id": "resident-b",
			"conflict_id": "conflict-test",
			"severity": "heavy",
			"event_id": "injury-event-1",
		}],
	) as Dictionary
	_expect_equal(
		reaction.is_empty(),
		false,
		"injury event exposes post-injury reaction",
	)
	_expect_equal(
		reaction.get("attacker_resident_id"),
		"resident-a",
		"explicit attacker is kept in post-injury reaction",
	)
	var attacker_reaction := runtime.call(
		"_post_injury_reaction_for_events",
		"resident-a",
		[{
			"type": "冲突见闻",
			"knowledge_kind": "participant",
			"conflict_event_type": "injury_applied",
			"actor_ids": ["resident-a", "resident-b"],
			"source_actor_id": "resident-a",
			"subject_id": "resident-b",
			"conflict_id": "conflict-test",
			"severity": "heavy",
			"event_id": "injury-event-1",
		}],
	) as Dictionary
	_expect_equal(
		attacker_reaction.is_empty(),
		true,
		"attacker is not mistaken for the injured participant",
	)

	var invalid_reply := runtime.call(
		"_post_injury_reaction_action_error",
		{"currentPlace": "广场"},
		{
			"handling": "replace_current",
			"action": {"action_id": "wait-1", "type": "待着"},
		},
		reaction,
	) as String
	_expect_equal(
		invalid_reply,
		"刚刚受伤时只能先当面质问攻击者，或直接去诊所",
		"post-injury reaction rejects waiting outside clinic",
	)

	var stay_error_free := runtime.call(
		"_post_injury_reaction_action_error",
		{"currentPlace": "诊所"},
		{
			"handling": "replace_current",
			"action": {"action_id": "wait-1", "type": "待着"},
		},
		reaction,
	) as String
	_expect_equal(
		stay_error_free,
		"",
		"post-injury reaction allows waiting in clinic",
	)

	var talk_wrong_target_error := runtime.call(
		"_post_injury_reaction_action_error",
		{"currentPlace": "广场"},
		{
			"handling": "replace_current",
			"action": {
				"action_id": "talk-1",
				"type": "搭话",
				"target_resident_id": "resident-c",
			},
		},
		reaction,
	) as String
	_expect_equal(
		talk_wrong_target_error,
		"刚刚受伤时只能先当面质问攻击者，不能先和其他人搭话",
		"post-injury reaction only allows talking to attacker",
	)

	var talk_attacker_ok := runtime.call(
		"_post_injury_reaction_action_error",
		{"currentPlace": "广场"},
		{
			"handling": "replace_current",
			"action": {
				"action_id": "talk-2",
				"type": "搭话",
				"target_resident_id": "resident-a",
			},
		},
		reaction,
	) as String
	_expect_equal(
		talk_attacker_ok,
		"",
		"post-injury reaction allows direct talk to attacker",
	)

	var go_error := runtime.call(
		"_post_injury_reaction_action_error",
		{"currentPlace": "广场"},
		{
			"handling": "replace_current",
			"action": {"action_id": "go-1", "type": "去", "place": "商店"},
		},
		reaction,
	) as String
	_expect_equal(
		go_error,
		"刚刚受伤时只能直接去诊所；去诊所本身就是离开冲突现场",
		"post-injury reaction only allows go clinic",
	)

	var go_clinic_ok := runtime.call(
		"_post_injury_reaction_action_error",
		{"currentPlace": "广场"},
		{
			"handling": "replace_current",
			"action": {"action_id": "go-2", "type": "去", "place": "诊所"},
		},
		reaction,
	) as String
	_expect_equal(
		go_clinic_ok,
		"",
		"post-injury reaction allows go clinic",
	)

	var continue_non_replace_error := runtime.call(
		"_post_injury_reaction_action_error",
		{"currentPlace": "广场"},
		{
			"handling": "continue_current",
			"action": {"action_id": "talk-3", "type": "搭话"},
		},
		reaction,
	) as String
	_expect_equal(
		continue_non_replace_error,
		"刚刚受伤，必须先当面质问攻击者，或直接去诊所",
		"post-injury reaction requires replace_current handling",
	)


func _event_of_type(events: Array, event_type: String) -> Dictionary:
	for value: Variant in events:
		if (
			value is Dictionary
			and String((value as Dictionary).get("type", "")) == event_type
		):
			return value as Dictionary
	return {}


func _injury_of_actor(injuries: Array, actor_id: String) -> Dictionary:
	for value: Variant in injuries:
		if (
			value is Dictionary
			and String((value as Dictionary).get("actorId", "")) == actor_id
		):
			return value as Dictionary
	return {}


func _avatar_attack_of(attacks: Array, conflict_id: String) -> Dictionary:
	for value: Variant in attacks:
		if (
			value is Dictionary
			and String((value as Dictionary).get("conflictId", "")) == conflict_id
		):
			return value as Dictionary
	return {}
