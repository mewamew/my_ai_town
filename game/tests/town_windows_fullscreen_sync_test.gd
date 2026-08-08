extends SceneTree


const SERVICE := preload(
	"res://world/presentation/ui/TownAudioDisplaySettingsService.gd"
)
const SETTINGS_PATH := "user://town_windows_fullscreen_sync_test.json"


class FakeWindowsDisplayBackend:
	extends RefCounted

	var mode := DisplayServer.WINDOW_MODE_WINDOWED
	var server_name := "Windows"
	var size := Vector2i(1600, 900)
	var position := Vector2i(160, 90)
	var screen := 0
	var usable_rect := Rect2i(0, 0, 1920, 1040)

	func get_name() -> String:
		return server_name

	func window_get_mode() -> int:
		return mode

	func window_set_mode(value: int) -> void:
		mode = value

	func window_get_size() -> Vector2i:
		return size

	func window_set_size(value: Vector2i) -> void:
		size = value

	func window_get_position() -> Vector2i:
		return position

	func window_set_position(value: Vector2i) -> void:
		position = value

	func window_get_current_screen() -> int:
		return screen

	func screen_get_usable_rect(_screen: int) -> Rect2i:
		return usable_rect


var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_remove_settings_file()
	var backend := FakeWindowsDisplayBackend.new()
	var service := SERVICE.new()
	service.settings_path = SETTINGS_PATH
	var configured := service.call(
		"configure_display_backend_for_tests",
		backend,
	) as Dictionary
	_expect(bool(configured.get("ok", false)), "fake Windows display backend is accepted")
	root.add_child(service)
	await process_frame
	await process_frame
	_expect_global_shortcuts()

	_expect(
		bool(service.call("toggle_fullscreen_from_global_shortcut")),
		"F11 request is accepted globally on Windows",
	)
	_expect_equal(
		backend.mode,
		DisplayServer.WINDOW_MODE_FULLSCREEN,
		"F11 enters Godot borderless fullscreen instead of enlarging a window",
	)
	var fullscreen_vm := service.call("get_view_model") as Dictionary
	_expect_equal(
		(
			(fullscreen_vm.get("data", {}) as Dictionary).get(
				"display", {},
			) as Dictionary
		).get("windowModeId"),
		"borderless_fullscreen",
		"settings state follows the global fullscreen shortcut",
	)

	_expect(
		bool(service.call("toggle_fullscreen_from_global_shortcut")),
		"a second F11 request is accepted",
	)
	_expect_equal(
		backend.mode,
		DisplayServer.WINDOW_MODE_WINDOWED,
		"a second F11 returns to the saved window mode",
	)

	backend.mode = DisplayServer.WINDOW_MODE_MAXIMIZED
	backend.position = Vector2i.ZERO
	backend.size = backend.usable_rect.size
	service.set("_external_fullscreen_exit_grace_until_msec", 0)
	service.call("_process", 0.0)
	_expect_equal(
		backend.mode,
		DisplayServer.WINDOW_MODE_FULLSCREEN,
		"maximize button, title double-click, and Win+Up promote to fullscreen",
	)

	_expect(
		bool(service.call("toggle_fullscreen_from_global_shortcut")),
		"fullscreen promoted from maximize can return to windowed mode",
	)
	backend.position = Vector2i(200, 100)
	backend.size = Vector2i(1500, 850)
	service.set("_external_fullscreen_exit_grace_until_msec", 0)
	service.call("_process", 0.0)
	_expect_equal(
		backend.mode,
		DisplayServer.WINDOW_MODE_WINDOWED,
		"a partial window is not promoted to fullscreen",
	)
	backend.usable_rect = Rect2i(0, 0, 1600, 900)
	backend.position = Vector2i.ZERO
	backend.size = Vector2i(1600, 900)
	service.set("_external_fullscreen_exit_grace_until_msec", 0)
	service.call("_process", 0.0)
	_expect_equal(
		backend.mode,
		DisplayServer.WINDOW_MODE_WINDOWED,
		"a deliberately managed screen-sized window remains windowed",
	)

	backend.usable_rect = Rect2i(0, 0, 1920, 1040)
	backend.position = Vector2i(-8, -8)
	backend.size = Vector2i(1936, 1096)
	service.call("_process", 0.0)
	_expect_equal(
		backend.mode,
		DisplayServer.WINDOW_MODE_FULLSCREEN,
		"an external tool covering the current screen is promoted to fullscreen",
	)

	backend.mode = DisplayServer.WINDOW_MODE_WINDOWED
	backend.position = Vector2i(160, 90)
	backend.size = Vector2i(1600, 900)
	service.call("_process", 0.0)
	var exited_vm := service.call("get_view_model") as Dictionary
	_expect_equal(
		(
			(exited_vm.get("data", {}) as Dictionary).get(
				"display", {},
			) as Dictionary
		).get("windowModeId"),
		"windowed",
		"externally leaving fullscreen restores windowed settings state",
	)
	service.call("_process", 0.0)
	_expect_equal(
		backend.mode,
		DisplayServer.WINDOW_MODE_WINDOWED,
		"fullscreen exit grace prevents immediate accidental re-entry",
	)

	backend.screen = 1
	backend.usable_rect = Rect2i(1920, 0, 2560, 1400)
	backend.position = Vector2i(1920, 0)
	backend.size = Vector2i(2560, 1440)
	service.set("_external_fullscreen_exit_grace_until_msec", 0)
	service.call("_process", 0.0)
	_expect_equal(
		backend.mode,
		DisplayServer.WINDOW_MODE_FULLSCREEN,
		"screen coverage detection uses the active monitor coordinates",
	)
	_expect(
		bool(service.call("toggle_fullscreen_from_global_shortcut")),
		"multi-monitor fullscreen can return to windowed mode",
	)
	backend.position = Vector2i.ZERO
	backend.size = Vector2i(2560, 1440)
	service.set("_external_fullscreen_exit_grace_until_msec", 0)
	service.call("_process", 0.0)
	_expect_equal(
		backend.mode,
		DisplayServer.WINDOW_MODE_WINDOWED,
		"screen-sized geometry on a different monitor is not promoted",
	)

	backend.mode = DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	service.call("_process", 0.0)
	var exclusive_vm := service.call("get_view_model") as Dictionary
	_expect_equal(
		(
			(exclusive_vm.get("data", {}) as Dictionary).get(
				"display", {},
			) as Dictionary
		).get("windowModeId"),
		"exclusive_fullscreen",
		"externally requested exclusive fullscreen is adopted globally",
	)

	backend.server_name = "macOS"
	backend.mode = DisplayServer.WINDOW_MODE_MAXIMIZED
	service.set("_external_fullscreen_exit_grace_until_msec", 0)
	service.call("_process", 0.0)
	_expect_equal(
		backend.mode,
		DisplayServer.WINDOW_MODE_MAXIMIZED,
		"Windows normalization does not change other desktop platforms",
	)

	service.queue_free()
	await process_frame
	_remove_settings_file()
	var audio_controller := root.get_node_or_null("TownAudioController")
	if audio_controller != null and audio_controller.has_method("prepare_shutdown"):
		audio_controller.call("prepare_shutdown")
		await process_frame
		await create_timer(0.2).timeout
	_finish()


func _expect_global_shortcuts() -> void:
	var flow_host := root.get_node_or_null("GameFlowHost")
	_expect(flow_host != null, "global GameFlowHost exists")
	if flow_host == null:
		return
	var f11 := InputEventKey.new()
	f11.keycode = KEY_F11
	_expect(
		bool(flow_host.call("_is_fullscreen_toggle_shortcut", f11)),
		"F11 is recognized as a global fullscreen shortcut",
	)
	var alt_enter := InputEventKey.new()
	alt_enter.keycode = KEY_ENTER
	alt_enter.alt_pressed = true
	_expect(
		bool(flow_host.call("_is_fullscreen_toggle_shortcut", alt_enter)),
		"Alt+Enter is recognized as a global fullscreen shortcut",
	)
	var alt_keypad_enter := InputEventKey.new()
	alt_keypad_enter.keycode = KEY_KP_ENTER
	alt_keypad_enter.alt_pressed = true
	_expect(
		bool(
			flow_host.call(
				"_is_fullscreen_toggle_shortcut",
				alt_keypad_enter,
			)
		),
		"Alt+keypad Enter is recognized as a global fullscreen shortcut",
	)
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	_expect(
		not bool(flow_host.call("_is_fullscreen_toggle_shortcut", enter)),
		"plain Enter remains gameplay input",
	)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s: expected=%s actual=%s" % [
		message,
		expected,
		actual,
	])


func _remove_settings_file() -> void:
	var absolute := ProjectSettings.globalize_path(SETTINGS_PATH)
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(absolute)


func _finish() -> void:
	if _failures.is_empty():
		print("TOWN_WINDOWS_FULLSCREEN_SYNC_PASS")
		quit(0)
		return
	print("TOWN_WINDOWS_FULLSCREEN_SYNC_FAIL: %s" % str(_failures))
	quit(1)
