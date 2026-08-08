extends SceneTree


const MARKER := preload(
	"res://world/presentation/town_runtime/BuildingResidentMarker.gd"
)
const ENTRY_CONFIRM := preload(
	"res://world/presentation/town_runtime/BuildingEntryConfirm.gd"
)
const HOTSPOT := preload(
	"res://world/presentation/town_runtime/BuildingObservationHotspot.gd"
)
const RESIDENT_BODY := preload(
	"res://world/presentation/residents/ResidentCharacterBody.gd"
)
const PORTRAIT_PATH := (
	"res://assets/characters/resident_2d_rig_v1/wardrobe_v1/"
	+ "classic_sets/runtime_portraits/lin_lan_front.png"
)

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fixture := Node2D.new()
	root.add_child(fixture)
	await _test_first_frame_and_zoom(fixture)
	await _test_entry_strip_click_area(fixture)
	await _test_hidden_resident_input_boundary(fixture)
	await _test_overlapping_building_click(fixture)
	fixture.queue_free()
	await process_frame
	_finish()


func _test_first_frame_and_zoom(fixture: Node2D) -> void:
	var marker := MARKER.new() as Node2D
	marker.configure("首帧房屋", Vector2(180.0, 180.0))
	marker.set_residents([_resident_entry("resident-first", "林岚")])
	marker.set_available(true)
	# Populate before entering the tree: _ready must rebuild the visible shell
	# instead of waiting for a later resident-place refresh.
	fixture.add_child(marker)
	await process_frame
	_expect_equal(marker.call("resident_count"), 1, "首帧保留恢复的居民名单")
	_expect(
		marker.get_node_or_null("MarkerContents/GlassShell") != null,
		"首帧已经建立屋顶标记图片外壳",
	)
	_expect(
		marker.get_node_or_null("MarkerContents/Portrait_林岚") != null,
		"首帧已经建立居民头像",
	)
	var native_size := marker.call("marker_size") as Vector2
	_expect_equal(
		native_size,
		Vector2(56.0, 62.0),
		"单居民屋顶标记保持原生尺寸",
	)
	marker.call("set_camera_zoom", Vector2(0.5, 0.5))
	var content_scale: Vector2 = marker.get_node("MarkerContents").scale
	var hit_area := marker.get_node("MarkerHitArea") as Area2D
	_expect_equal(content_scale, Vector2(2.0, 2.0), "远景头像保持最小可读屏幕尺寸")
	_expect_equal(hit_area.scale, content_scale, "头像点击区与显示内容同步缩放")
	_expect_equal(
		marker.call("display_size"),
		native_size * 2.0,
		"远景屋顶标记显示尺寸按最小屏幕尺寸放大",
	)
	var hit_shape := hit_area.get_node("MarkerHitShape") as CollisionShape2D
	var rectangle := hit_shape.shape as RectangleShape2D
	_expect(rectangle != null, "屋顶标记拥有矩形点击区")
	if rectangle != null:
		_expect_equal(
			rectangle.size,
			native_size,
		"屋顶标记点击区覆盖完整原生面板",
		)
	marker.queue_free()


func _test_entry_strip_click_area(fixture: Node2D) -> void:
	var entry := ENTRY_CONFIRM.new() as Node2D
	entry.configure("进入测试房屋", [], Vector2(320.0, 180.0))
	fixture.add_child(entry)
	await process_frame
	entry.call("set_camera_zoom", Vector2(0.5, 0.5))
	var button := entry.get_node("EnterInteriorButton") as Button
	_expect_equal(
		button.position,
		Vector2(-107.0, -22.0),
		"进入条点击区从完整图片条左上角开始",
	)
	_expect_equal(
		button.size,
		Vector2(214.0, 44.0),
		"进入条整张 214x44 图片区域都可点击",
	)
	var snapshot := entry.call("debug_asset_snapshot") as Dictionary
	_expect(
		bool(snapshot.get("fullStripClickable", false)),
		"进入条公开状态确认整条可点击",
	)
	_expect_equal(
		entry.scale,
		Vector2(2.0, 2.0),
		"远景进入条保持最小可读屏幕尺寸",
	)
	entry.queue_free()


func _test_hidden_resident_input_boundary(fixture: Node2D) -> void:
	var body := RESIDENT_BODY.new() as Node2D
	fixture.add_child(body)
	await process_frame
	body.call("set_space_active", false)
	var hit_area := body.get_node_or_null("ResidentHitArea") as Area2D
	_expect(
		not bool(body.call("can_receive_pointer_input")),
		"隐藏室外居民不能接收点击",
	)
	_expect(
		hit_area != null and not hit_area.input_pickable,
		"隐藏居民点击区同步关闭",
	)
	_expect(
		hit_area != null and hit_area.collision_layer == 0,
		"隐藏居民点击碰撞层同步关闭",
	)
	body.call("set_space_active", true)
	_expect(
		bool(body.call("can_receive_pointer_input")),
		"恢复当前空间后居民点击能力恢复",
	)
	body.queue_free()


func _test_overlapping_building_click(fixture: Node2D) -> void:
	var hotspot := HOTSPOT.new() as Area2D
	hotspot.configure("重叠房屋", Vector2(520.0, 280.0), Vector2(140.0, 120.0))
	hotspot.set_available(true)
	fixture.add_child(hotspot)
	var marker := MARKER.new() as Node2D
	marker.configure("重叠房屋", Vector2.ZERO)
	marker.set_residents([_resident_entry("resident-overlap", "顾川")])
	marker.set_available(true)
	hotspot.add_child(marker)
	await process_frame
	_expect(
		hotspot.z_index > marker.z_index,
		"重叠时建筑热点层级高于屋顶标记",
	)
	var activation := {"count": 0}
	var resident_activation := {"count": 0}
	hotspot.activated.connect(func(_place_name: String) -> void:
		activation["count"] = int(activation["count"]) + 1
	)
	marker.resident_activated.connect(func(_resident_id: String, _resident_name: String) -> void:
		resident_activation["count"] = int(resident_activation["count"]) + 1
	)
	# Put the marker's center 28px above the current pointer. The panel ends
	# at +31px, while the resident cell ends at +23px, so this is a valid
	# building-area click outside every resident cell.
	var pointer_global := marker.get_global_mouse_position()
	marker.global_position = pointer_global - Vector2(0.0, 28.0)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = marker.get_viewport().get_mouse_position()
	marker.call("_on_hit_area_input", marker.get_viewport(), click, 0)
	_expect_equal(
		activation["count"],
		1,
		"屋顶标记空白重叠区域转交建筑热点处理",
	)
	_expect_equal(
		resident_activation["count"],
		0,
		"点击房屋重叠区域不会打开居民五项菜单",
	)
	hotspot.queue_free()


func _resident_entry(resident_id: String, resident_name: String) -> Dictionary:
	return {
		"residentId": resident_id,
		"name": resident_name,
		"portraitPath": PORTRAIT_PATH,
	}


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(
		actual == expected,
		"%s; expected=%s actual=%s" % [message, expected, actual],
	)


func _finish() -> void:
	if _failures.is_empty():
		print("TOWN_BUILDING_RESIDENT_MARKER_RUNTIME_PASS checks=%d" % _checks)
		quit(0)
		return
	for failure in _failures:
		push_error("TOWN_BUILDING_RESIDENT_MARKER_RUNTIME_FAIL: %s" % failure)
	print("TOWN_BUILDING_RESIDENT_MARKER_RUNTIME_FAIL checks=%d" % _checks)
	quit(1)
