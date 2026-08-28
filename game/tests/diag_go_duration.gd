extends "res://tests/support/TownWorldTestCase.gd"
## diag_go_duration.gd — 实测「去」动作路线耗时
## 目的：唐小满 第2天 14:50 去中心广场，20:09 才到达（≈5h19m）；
## 乔一鸣 13:36 去公共食堂，18:40 才被感知已到达。验证 durationMinutes
## 是否被路线计算异常放大（连接 movementMinutes=1、速度144米/分钟，
## 正常应为几分钟）。

const ROUTE_QUERY := preload("res://world/data/town/TownWorldRouteQuery.gd")

func _initialize() -> void:
	print("===== 去动作路线耗时实测 =====")
	var data := _build_data()
	var speed := float(
		(data.get("movementRules", {}) as Dictionary).get(
			"outdoorDistancePerGameMinute", 0.0,
		)
	)
	print("outdoorDistancePerGameMinute = %s" % str(speed))
	var cases := [
		["西街三号住宅", "中心广场"],
		["西街三号住宅", "公共食堂"],
		["公共食堂", "中心广场"],
		["花房咖啡馆", "独立市集"],
		["独立市集", "公共食堂"],
		["码头的鱼摊", "公共食堂"],
	]
	for case_value in cases:
		var from_place := str(case_value[0])
		var to_place := str(case_value[1])
		var route := ROUTE_QUERY.find_route(data, from_place, to_place)
		_dump_route(from_place, to_place, route)
	_finish_suite("GO_DURATION_DIAG")


func _dump_route(from_place: String, to_place: String, route: Dictionary) -> void:
	if route.is_empty():
		print("[%s → %s] 无路线!" % [from_place, to_place])
		return
	var steps := route.get("segments", []) as Array
	print("--- %s → %s ---" % [from_place, to_place])
	print("  durationMinutes=%s costGameMinutes=%s connectionMinutes=%s routeDistance=%s" % [
		str(route.get("durationMinutes", 0)),
		str(route.get("costGameMinutes", 0.0)),
		str(route.get("connectionMinutes", 0)),
		str(route.get("routeDistance", 0.0)),
	])
	var indoor := 0.0
	var outdoor_m := 0.0
	var conn_min := 0
	for step_value in steps:
		var step := step_value as Dictionary
		var kind := String(step.get("kind", ""))
		var cost := float(step.get("costGameMinutes", 0.0))
		if kind == "route_edge":
			var length := float(step.get("length", 0.0))
			if String(step.get("fromSpaceId", "")) == "town_outdoor":
				outdoor_m += length
			else:
				indoor += length
			print("   edge from=%s to=%s space=%s→%s len=%s cost=%s" % [
				str(step.get("fromNodeId", "")),
				str(step.get("toNodeId", "")),
				str(step.get("fromSpaceId", "")),
				str(step.get("toSpaceId", "")),
				str(length),
				str(snappedf(cost, 0.001)),
			])
		else:
			conn_min += int(roundf(cost))
			print("   conn %s→%s cost=%s" % [
				str(step.get("fromNodeId", "")),
				str(step.get("toNodeId", "")),
				str(snappedf(cost, 0.001)),
			])
	print("   indoor_m=%s outdoor_m=%s conn_min=%s" % [
		str(snappedf(indoor, 0.001)),
		str(snappedf(outdoor_m, 0.001)),
		str(conn_min),
	])