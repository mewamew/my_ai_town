extends SceneTree
## 智能节流器(方案 A)可测部分验证。
## 引擎限制: --script 模式(无主场景)下 root Window 不在场景树内, 无法触发
## is_inside_tree() 分支(预算限速/对话绕过/树内 429 节流态)。该分支已由
## 游戏实战日志验证(090835 局可见 0.8/s 预算放行节奏 1-2s 间隔)。
## 本测试覆盖可测部分:
##   1. _refill_dispatch_budget 纯算术(首调/正常 0.5s 速率/节流态 0.35s/cap 3.0)
##   2. 非树内 _select_dispatchable_requests 容量投影(MAX=3, 对话优先)
##   3. 非树内 429 退化为立即重发(假 world 断言 redispatch 调用)
##   4. 非树内 429 不设置节流态(树内才设)
##   5. 投票快速通道(方案C): 投票请求绕过普通 2 槽占满 MAX=3;
##      有投票 pending 时普通请求全部让路; 玩家对话仍优先
## 运行: Godot --headless --path game --script res://tests/diag_throttle.gd

const GATEWAY_SCRIPT := preload("res://world/integration/TownWorldAgentGateway.gd")

var _checks := 0
var _failures := 0


class FakeWorld:
	extends RefCounted

	var redispatch_called := 0

	func redispatch_decision_request_by_id(
		_resident_id: String,
		_decision_id: String,
	) -> Dictionary:
		redispatch_called += 1
		return {"ok": true}


func _initialize() -> void:
	print("===== 智能节流器(可测部分)验证 =====\n")
	var gateway: Node = GATEWAY_SCRIPT.new()

	# 1a. 首次 _refill 只记录起始时间, 不补充预算
	gateway._dispatch_budget = 3.0
	gateway._last_budget_refill_ms = 0
	var now_ms := Time.get_ticks_msec()
	gateway._refill_dispatch_budget(now_ms)
	_expect(
		absf(gateway._dispatch_budget - 3.0) < 0.001,
		"首调不补充预算 (%.2f)" % gateway._dispatch_budget,
	)
	_expect(
		gateway._last_budget_refill_ms == now_ms,
		"首调记录起始时间",
	)

	# 1b. 正常态 2.1s × 0.5/s = 1.05 补充
	gateway._dispatch_budget = 1.0
	gateway._refill_dispatch_budget(now_ms + 2100)
	_expect(
		absf(gateway._dispatch_budget - 2.05) < 0.01,
		"正常态 2100ms 补充 1.05 (%.2f)" % gateway._dispatch_budget,
	)

	# 1c. 节流态 2s × 0.35/s = 0.7 补充
	gateway._throttle_until_ms = now_ms + 30000
	gateway._dispatch_budget = 1.0
	gateway._last_budget_refill_ms = now_ms
	gateway._refill_dispatch_budget(now_ms + 2000)
	_expect(
		absf(gateway._dispatch_budget - 1.7) < 0.01,
		"节流态 2000ms 补充 0.7 (%.2f)" % gateway._dispatch_budget,
	)

	# 1d. 预算上限 cap 3.0
	gateway._throttle_until_ms = 0
	gateway._dispatch_budget = 2.9
	gateway._last_budget_refill_ms = now_ms
	gateway._refill_dispatch_budget(now_ms + 100000)
	_expect(
		absf(gateway._dispatch_budget - 3.0) < 0.001,
		"预算封顶 3.0 (%.2f)" % gateway._dispatch_budget,
	)

	# 2. 非树内容量投影: 无对话时普通居民受 MAX-RESERVED=2 槽位限制
	#    (留 1 槽给可能的玩家对话), 10 普通请求 → 2 selected / 8 overflow
	var avatar_id: String = String(gateway._avatar_person_id)
	var requests := _make_requests(10, avatar_id, false)
	var selection: Dictionary = gateway._select_dispatchable_requests(
		requests, 10, false, false,
	)
	_expect_equal(
		(selection["selected"] as Array).size(),
		2,
		"无对话时普通居民 2 槽位(MAX-RESERVED)",
	)
	_expect_equal(
		(selection["overflow"] as Array).size(),
		8,
		"其余 8 个进 overflow",
	)

	# 3. 有对话时普通居民可用全部 MAX=3 槽(has_pending=true 放开 RESERVED)
	selection = gateway._select_dispatchable_requests(
		requests, 10, true, false,
	)
	_expect_equal(
		(selection["selected"] as Array).size(),
		3,
		"有对话时普通居民 3 槽位(MAX)",
	)
	_expect_equal(
		(selection["overflow"] as Array).size(),
		7,
		"其余 7 个进 overflow",
	)

	# 4. 对话请求优先(非树内容量同样适用)
	var conversation_requests := _make_requests(3, avatar_id, true)
	selection = gateway._select_dispatchable_requests(
		conversation_requests, 3, true, false,
	)
	_expect_equal(
		(selection["selected"] as Array).size(),
		3,
		"对话请求 3 个全放行",
	)
	_expect_equal(
		(selection["overflow"] as Array).size(),
		0,
		"对话请求无 overflow",
	)

	# 5. 投票快速通道(方案C): 投票请求绕过普通 2 槽限制占满 MAX=3
	var vote_requests := _make_requests(10, avatar_id, false, true)
	selection = gateway._select_dispatchable_requests(
		vote_requests, 10, false, true,
	)
	_expect_equal(
		(selection["selected"] as Array).size(),
		3,
		"投票请求占满 MAX=3(绕过普通 2 槽)",
	)
	_expect_equal(
		(selection["overflow"] as Array).size(),
		7,
		"其余 7 个投票请求进 overflow",
	)
	# 5b. 有投票 pending 时普通生活请求全部让路
	selection = gateway._select_dispatchable_requests(
		requests, 10, false, true,
	)
	_expect_equal(
		(selection["selected"] as Array).size(),
		0,
		"有投票请求时普通请求 0 放行",
	)
	_expect_equal(
		(selection["overflow"] as Array).size(),
		10,
		"普通请求全部进 overflow 让路",
	)
	# 5c. 混合: 玩家对话仍优先, 投票次之, 不互相挤占
	var mixed_requests: Array[Dictionary] = []
	mixed_requests.append_array(conversation_requests)
	mixed_requests.append_array(vote_requests)
	selection = gateway._select_dispatchable_requests(
		mixed_requests, 10, true, true,
	)
	_expect_equal(
		(selection["selected"] as Array).size(),
		3,
		"对话优先占满 MAX=3",
	)
	_expect_equal(
		(selection["overflow"] as Array).size(),
		10,
		"投票请求排队等槽",
	)

	# 4. 非树内 429 → 立即重发(退化路径), 假 world 收到 redispatch
	var fake_world := FakeWorld.new()
	gateway._world = fake_world
	gateway._session_active = true
	gateway._throttle_until_ms = 0
	gateway._schedule_rate_limit_redispatch("resident_0", "decision_0", 1)
	_expect_equal(
		fake_world.redispatch_called,
		1,
		"非树内 429 立即重发一次",
	)
	_expect_equal(
		gateway._throttle_until_ms,
		0,
		"非树内 429 不设置节流态(树内才设)",
	)

	print(
		"\n===== 节流器验证完成 checks=%d failures=%d ====="
		% [_checks, _failures],
	)
	if _failures == 0:
		print("THROTTLE_PASS checks=%d" % _checks)
	quit(_failures if _failures > 0 else 0)


func _make_requests(
	count: int,
	avatar_id: String,
	conversation: bool,
	vote: bool = false,
) -> Array[Dictionary]:
	var requests: Array[Dictionary] = []
	for i in count:
		var wake: Dictionary = {
			"decision_id": "decision_%d_%d" % [Time.get_ticks_usec(), i],
		}
		if conversation:
			wake["events"] = [{
				"type": "对话",
				"participant_resident_ids": [avatar_id],
			}]
		if vote:
			wake["snapshot"] = {
				"exile_vote": {
					"forced": true,
					"candidate_names": ["林岚"],
				},
			}
		requests.append({
			"residentId": "resident_%d" % i,
			"wakePacket": wake,
		})
	return requests


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  ✓ %s" % label)
	else:
		_failures += 1
		print("  ✗ FAIL: %s" % label)


func _expect_equal(actual: int, expected: int, label: String) -> void:
	_expect(actual == expected, "%s (got %d, want %d)" % [label, actual, expected])
