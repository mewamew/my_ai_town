class_name TownEntryLoadingOverlay
extends CanvasLayer


const BACKGROUND_TEXTURE_PATH := (
	"res://assets/ui/opening_flow/shared/loading/runtime/v1/components/"
	+ "loading_background_dimmed_v1.png"
)
const SHELL_TEXTURE_PATH := (
	"res://assets/ui/opening_flow/shared/loading/runtime/v1/components/"
	+ "loading_shell_exact_full_canvas_v1.png"
)
const PROGRESS_TRACK_PATH := (
	"res://assets/ui/opening_flow/shared/loading/runtime/v1/components/"
	+ "progress_track_empty_520x31_v1.png"
)
const PROGRESS_FILL_PATH := (
	"res://assets/ui/opening_flow/shared/loading/runtime/v1/components/"
	+ "progress_fill_source_226x25_v1.png"
)
const RUNTIME_MANIFEST_PATH := (
	"res://assets/ui/opening_flow/shared/loading/runtime/v1/"
	+ "town_entry_loading_runtime_v1_manifest.json"
)
const FONT_PATH := (
	"res://assets/ui/startup/fonts/noto_sans_cjk_sc_medium/"
	+ "NotoSansCJKsc-Medium.otf"
)
const REFERENCE_SIZE := Vector2(1672.0, 941.0)
const PANEL_RECT_REFERENCE := Rect2(515.0, 481.0, 641.0, 308.0)
const TITLE_RECT_REFERENCE := Rect2(570.0, 530.0, 530.0, 88.0)
const STATUS_RECT_REFERENCE := Rect2(570.0, 642.0, 530.0, 42.0)
const PROGRESS_RECT_REFERENCE := Rect2(577.0, 708.0, 520.0, 31.0)
const PROGRESS_INNER_OFFSET := Vector2(3.0, 3.0)
const PROGRESS_INNER_SIZE := Vector2(514.0, 25.0)
const INITIAL_PROGRESS := 0.08
const AUTO_PROGRESS_INTERVAL := 0.12
const AUTO_PROGRESS_CAP := 0.92
const AUTO_PROGRESS_STEPS: Array[float] = [
	0.009,
	0.014,
	0.007,
	0.012,
	0.006,
]

var _blocker: Control
var _visual_root: Control
var _background: TextureRect
var _shell: TextureRect
var _title: Label
var _status: Label
var _progress: Control
var _progress_track: TextureRect
var _progress_fill: NinePatchRect
var _active := false
var _route_kind := ""
var _progress_value := 0.0
var _auto_progress_elapsed := 0.0
var _auto_progress_step_index := 0
var _reference_scale := 1.0
var _reference_offset := Vector2.ZERO


func _ready() -> void:
	layer = 1000
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_nodes()
	get_viewport().size_changed.connect(_layout)
	_layout()
	dismiss()


func begin(route_kind: String) -> void:
	_ensure_nodes()
	_route_kind = route_kind.strip_edges()
	_progress_value = INITIAL_PROGRESS
	_auto_progress_elapsed = 0.0
	_auto_progress_step_index = 0
	_active = true
	_title.text = _route_title(_route_kind)
	_status.text = _initial_status(_route_kind)
	_sync_progress_visual()
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_blocker.show()
	_layout()


func _process(delta: float) -> void:
	if (
		not _active
		or _progress_value >= AUTO_PROGRESS_CAP
	):
		return
	_auto_progress_elapsed += maxf(0.0, delta)
	while (
		_auto_progress_elapsed >= AUTO_PROGRESS_INTERVAL
		and _progress_value < AUTO_PROGRESS_CAP
	):
		_auto_progress_elapsed -= AUTO_PROGRESS_INTERVAL
		var step := AUTO_PROGRESS_STEPS[
			_auto_progress_step_index % AUTO_PROGRESS_STEPS.size()
		]
		_auto_progress_step_index += 1
		_progress_value = minf(
			AUTO_PROGRESS_CAP,
			_progress_value + step,
		)
		_sync_progress_visual()


func advance(progress_value: float, status_text: String) -> void:
	if not _active:
		return
	_progress_value = maxf(
		_progress_value,
		clampf(progress_value, 0.0, 1.0),
	)
	_sync_progress_visual()
	var player_copy := status_text.strip_edges()
	if not player_copy.is_empty():
		_status.text = player_copy


func complete() -> void:
	advance(1.0, "小镇准备好了")


func dismiss() -> void:
	_active = false
	_route_kind = ""
	_progress_value = 0.0
	_auto_progress_elapsed = 0.0
	_auto_progress_step_index = 0
	if _blocker == null:
		return
	_sync_progress_visual()
	_blocker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blocker.hide()


func is_active() -> bool:
	return _active


func debug_snapshot() -> Dictionary:
	return {
			"active": _active,
			"routeKind": _route_kind,
			"progress": _progress_value,
		"automaticProgress": _active,
		"title": _title.text if _title != null else "",
		"status": _status.text if _status != null else "",
		"blocksInput": (
			_blocker != null
			and _blocker.mouse_filter == Control.MOUSE_FILTER_STOP
		),
		"blockerVisible": _blocker.visible if _blocker != null else false,
		"blockerRect": (
			Rect2(_blocker.position, _blocker.size)
			if _blocker != null
			else Rect2()
		),
		"panelRect": _scaled_reference_rect(PANEL_RECT_REFERENCE),
		"progressRect": (
			Rect2(_progress.position, _progress.size)
			if _progress != null
			else Rect2()
		),
		"progressFillWidth": (
			_progress_fill.size.x if _progress_fill != null else 0.0
		),
		"referenceScale": _reference_scale,
		"referenceOffset": _reference_offset,
		"backgroundRect": (
			Rect2(_background.position, _background.size)
			if _background != null
			else Rect2()
		),
		"backgroundCoversViewport": (
			_background != null
			and _background.position == Vector2.ZERO
			and _background.size == _blocker.size
		),
		"backgroundTexturePath": BACKGROUND_TEXTURE_PATH,
		"shellTexturePath": SHELL_TEXTURE_PATH,
		"progressTrackPath": PROGRESS_TRACK_PATH,
		"progressFillPath": PROGRESS_FILL_PATH,
		"runtimeManifestPath": RUNTIME_MANIFEST_PATH,
		"fontPath": FONT_PATH,
		"singleBackgroundOwner": _background != null,
	}


func debug_layout_for_viewport(viewport_size: Vector2) -> Dictionary:
	_layout_for_size(viewport_size)
	return debug_snapshot()


func _ensure_nodes() -> void:
	if _blocker != null:
		return
	_blocker = Control.new()
	_blocker.name = "TownEntryInputBlocker"
	_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_blocker)
	_background = _texture_rect("OpeningFlowLoadingBackground", BACKGROUND_TEXTURE_PATH)
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_blocker.add_child(_background)

	_visual_root = Control.new()
	_visual_root.name = "OpeningFlowLoadingVisual"
	_visual_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blocker.add_child(_visual_root)

	_shell = _texture_rect("OpeningFlowLoadingShell", SHELL_TEXTURE_PATH)
	_visual_root.add_child(_shell)

	_title = _label("TownEntryLoadingTitle", 34, Color("#3f2818"))
	_status = _label("TownEntryLoadingStatus", 24, Color("#50331f"))
	_blocker.add_child(_title)
	_blocker.add_child(_status)

	_progress = Control.new()
	_progress.name = "TownEntryProgress"
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blocker.add_child(_progress)

	_progress_track = _texture_rect(
		"TownEntryProgressTrack",
		PROGRESS_TRACK_PATH,
	)
	_progress.add_child(_progress_track)

	_progress_fill = NinePatchRect.new()
	_progress_fill.name = "TownEntryProgressFill"
	_progress_fill.texture = ResourceLoader.load(
		PROGRESS_FILL_PATH,
		"Texture2D",
	) as Texture2D
	_progress_fill.axis_stretch_horizontal = (
		NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	)
	_progress_fill.axis_stretch_vertical = (
		NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	)
	_progress_fill.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_progress_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress.add_child(_progress_fill)


func _texture_rect(node_name: String, texture_path: String) -> TextureRect:
	var rect := TextureRect.new()
	rect.name = node_name
	rect.texture = ResourceLoader.load(texture_path, "Texture2D") as Texture2D
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _label(node_name: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var font := ResourceLoader.load(FONT_PATH, "FontFile") as FontFile
	if font != null:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 0)
	return label


func _layout() -> void:
	if _blocker == null or _visual_root == null:
		return
	_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layout_for_size(get_viewport().get_visible_rect().size)


func _layout_for_size(viewport_size: Vector2) -> void:
	if _visual_root == null:
		return
	var safe_size := Vector2(
		maxf(1.0, viewport_size.x),
		maxf(1.0, viewport_size.y),
	)
	_reference_scale = minf(
		safe_size.x / REFERENCE_SIZE.x,
		safe_size.y / REFERENCE_SIZE.y,
	)
	var visual_size := Vector2(
		roundf(REFERENCE_SIZE.x * _reference_scale),
		roundf(REFERENCE_SIZE.y * _reference_scale),
	)
	_reference_offset = Vector2(
		roundf((safe_size.x - visual_size.x) * 0.5),
		roundf((safe_size.y - visual_size.y) * 0.5),
	)
	_visual_root.position = _reference_offset
	_visual_root.size = visual_size
	_background.position = Vector2.ZERO
	_background.size = safe_size
	_shell.position = Vector2.ZERO
	_shell.size = visual_size
	_apply_reference_rect(_title, TITLE_RECT_REFERENCE)
	_apply_reference_rect(_status, STATUS_RECT_REFERENCE)
	_apply_reference_rect(_progress, PROGRESS_RECT_REFERENCE)
	_title.add_theme_font_size_override(
		"font_size",
		maxi(20, roundi(34.0 * _reference_scale)),
	)
	_status.add_theme_font_size_override(
		"font_size",
		maxi(16, roundi(24.0 * _reference_scale)),
	)
	_progress_track.position = Vector2.ZERO
	_progress_track.size = _progress.size
	_progress_fill.position = Vector2(
		roundf(PROGRESS_INNER_OFFSET.x * _reference_scale),
		roundf(PROGRESS_INNER_OFFSET.y * _reference_scale),
	)
	var patch_margin := maxi(4, roundi(12.0 * _reference_scale))
	_progress_fill.patch_margin_left = patch_margin
	_progress_fill.patch_margin_right = patch_margin
	_progress_fill.patch_margin_top = maxi(1, roundi(3.0 * _reference_scale))
	_progress_fill.patch_margin_bottom = maxi(1, roundi(3.0 * _reference_scale))
	_sync_progress_visual()


func _apply_reference_rect(control: Control, reference_rect: Rect2) -> void:
	var scaled := _scaled_reference_rect(reference_rect)
	control.position = scaled.position
	control.size = scaled.size


func _scaled_reference_rect(reference_rect: Rect2) -> Rect2:
	return Rect2(
		_reference_offset + Vector2(
			roundf(reference_rect.position.x * _reference_scale),
			roundf(reference_rect.position.y * _reference_scale),
		),
		Vector2(
			roundf(reference_rect.size.x * _reference_scale),
			roundf(reference_rect.size.y * _reference_scale),
		),
	)


func _sync_progress_visual() -> void:
	if _progress_fill == null:
		return
	var inner_size := Vector2(
		roundf(PROGRESS_INNER_SIZE.x * _reference_scale),
		roundf(PROGRESS_INNER_SIZE.y * _reference_scale),
	)
	var fill_width := roundf(inner_size.x * _progress_value)
	_progress_fill.size = Vector2(fill_width, inner_size.y)
	_progress_fill.visible = fill_width > 0.0


func _initial_status(route_kind: String) -> String:
	match route_kind:
		"quit_game":
			return "正在整理离开前的事情…"
		"new_game":
			return "正在准备新的小镇…"
		"load_game":
			return "正在读取所选存档…"
	return "正在读取最近存档…"


func _route_title(route_kind: String) -> String:
	match route_kind:
		"quit_game":
			return "正在保存小镇"
		"new_game":
			return "正在创建小镇"
		"load_game":
			return "正在加载存档"
	return "正在继续游戏"
