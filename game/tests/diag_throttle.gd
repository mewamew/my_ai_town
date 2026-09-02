extends SceneTree
## 网关派发容量投影 + 投票快速通道可测部分验证。
## 本地自定义限流(令牌桶预算/429 退避/节流态)已整体删除, 只保留官方限流
## (MAX_CONCURRENT_MODEL_REQUESTS=6 / RESERVED_AVATAR=1 / LOCAL 并发常量)。
## 引擎限制: --script 模式(无主场景)下 root Window 不在场景树内, 无法触发
## is_inside_tree() 分支(逐帧 pump_frame_budgeted 等)。本测试覆盖可测部分:
##   1. 非树内 _select_dispatchable_requests 容量投影(MAX=6, 对话预留 1 槽)
##   2. 对话请求优先(有对话时普通居民可用全部 MAX=6 槽)
##   3. 投票快速通道: 投票请求不受普通槽位限制, 占满 MAX=6;
##      有投票 pending 时普通请求全部让路; 玩家对话仍优先
## 运行: Godot --headless --path game --script res://tests/diag_throttle.gd

const GATEWAY_SCRIPT := preload("res://world/integration/TownWorldAgentGateway.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	print("===== 网关容量投影 + 投票快速通道(可测部分)验证 =====\n")
	var gateway: Node = GATEWAY_SCRIPT.new()

	# 1. 非树内容量投影: 无对话时普通居民受 MAX-RESERVED=5 槽位限制
	#    (留 1 槽给可能的玩家对话), 10 普通请求 → 5 selected / 5 overflow
	var avatar_id: String = String(gateway._avatar_person_id)
	var requests := _make_requests(10, avatar_id, false)
	var selection: Dictionary = gateway._select_dispatchable_requests(
		requests, 10, false, false,
	)
	_expect_equal(
		(selection["selected"] as Array).size(),
		5,
		"无对话时普通居民 5 槽位(MAX-RESERVED)",
	)
	_expect_equal(
		(selection["overflow"] as Array).size(),
		5,
		"其余 5 个进 overflow",
	)

	# 2. 有对话时普通居民可用全部 MAX=6 槽(has_pending=true 放开 RESERVED)
	selection = gateway._select_dispatchable_requests(
		requests, 10, true, false,
	)
	_expect_equal(
		(selection["selected"] as Array).size(),
		6,
		"有对话时普通居民 6 槽位(MAX)",
	)
	_expect_equal(
		(selection["overflow"] as Array).size(),
		4,
		"其余 4 个进 overflow",
	)

	# 3. 对话请求优先(非树内容量同样适用)
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

	# 4. 投票快速通道: 投票请求绕过普通槽位限制占满 MAX=6
	var vote_requests := _make_requests(10, avatar_id, false, true)
	selection = gateway._select_dispatchable_requests(
		vote_requests, 10, false, true,
	)
	_expect_equal(
		(selection["selected"] as Array).size(),
		6,
		"投票请求占满 MAX=6(绕过普通 5 槽)",
	)
	_expect_equal(
		(selection["overflow"] as Array).size(),
		4,
		"其余 4 个投票请求进 overflow",
	)
	# 4b. 有投票 pending 时普通生活请求全部让路
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
	# 4c. 混合: 玩家对话仍优先, 投票次之, 不互相挤占
	var mixed_requests: Array[Dictionary] = []
	mixed_requests.append_array(conversation_requests)
	mixed_requests.append_array(vote_requests)
	selection = gateway._select_dispatchable_requests(
		mixed_requests, 10, true, true,
	)
	_expect_equal(
		(selection["selected"] as Array).size(),
		6,
		"对话+投票占满 MAX=6",
	)
	_expect_equal(
		(selection["overflow"] as Array).size(),
		7,
		"其余投票请求排队等槽",
	)

	print(
		"\n===== 容量投影验证完成 checks=%d failures=%d ====="
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
					"candidate_ids": ["resident_lin_lan_01"],
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