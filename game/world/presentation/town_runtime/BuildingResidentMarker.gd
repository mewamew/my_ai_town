class_name BuildingResidentMarker
extends Node2D

const POINTER_INPUT := preload("res://ui/mobile/PointerInput.gd")


signal resident_activated(resident_id: String, resident_name: String)
signal expanded_changed(place_name: String, expanded: bool)


const INPUT_COLLISION_LAYER := 1 << 15
const COLLAPSED_LIMIT := 3
const MAX_RESIDENT_COUNT := 15
const STANDARD_GRID_COLUMNS := 4
const MAX_GRID_COLUMNS := 5
const CELL_WIDTH := 48.0
const CELL_HEIGHT := 54.0
const PANEL_PADDING := 4.0
const PORTRAIT_SIZE := 34.0
const PORTRAIT_CROP := Rect2(166.0, 45.0, 180.0, 180.0)
const NAME_FONT_SIZE := 13
const OVERFLOW_CHIP_SIZE := Vector2(32.0, 32.0)
const OVERFLOW_CHIP_OPTICAL_OFFSET := Vector2(0.0, 1.0)
const OVERFLOW_TEXT_OPTICAL_OFFSET := Vector2(0.0, -1.0)
const ONE_RESIDENT_TEXTURE := preload(
	"res://assets/ui/world_resident_marker/final/resident_roof_one_v4.svg"
)
const TWO_RESIDENT_TEXTURE := preload(
	"res://assets/ui/world_resident_marker/final/resident_roof_two_v4.svg"
)
const THREE_RESIDENT_TEXTURE := preload(
	"res://assets/ui/world_resident_marker/final/resident_roof_three_v4.svg"
)
const ONE_ROW_TEXTURE := preload(
	"res://assets/ui/world_resident_marker/final/resident_roof_overflow_v4.svg"
)
const TWO_ROW_TEXTURE := preload(
	"res://assets/ui/world_resident_marker/final/resident_roof_two_rows_v4.svg"
)
const THREE_ROW_TEXTURE := preload(
	"res://assets/ui/world_resident_marker/final/resident_roof_three_rows_v4.svg"
)
const FIFTEEN_RESIDENT_TEXTURE := preload(
	"res://assets/ui/world_resident_marker/final/resident_roof_fifteen_v4.svg"
)
const OVERFLOW_CHIP_TEXTURE := preload(
	"res://assets/ui/world_resident_marker/final/resident_overflow_chip_v4.svg"
)
const NAME_FONT := preload(
	"res://assets/fonts/zheng_ge_dian_hei_16/"
	+ "ZhengGeDianHei-16.ttf"
)

var _place_name := ""
var _available := false
var _expanded := false
var _resident_entries: Array[Dictionary] = []
var _marker_size := Vector2.ZERO
var _content_offset_y := 0.0
var _resident_cells: Array[Rect2] = []
var _overflow_cell := Rect2()
var _active_shell_texture: Texture2D
var _layout_rows := 0
var _layout_columns := 0
var _hit_area: Area2D
var _content_root: Node2D
var _camera_zoom := Vector2.ONE
var _touch_scale_multiplier := 1.0


func _ready() -> void:
	z_index = 160
	z_as_relative = false
	_build_content_root()
	_build_hit_area()
	if not _resident_entries.is_empty():
		# TownRuntime can populate the marker in the same frame it adds it to the
		# hotspot. Rebuild once the runtime nodes exist so the first frame already
		# contains the restored roof marker.
		_rebuild_contents()
	set_camera_zoom(_camera_zoom)
	_apply_visibility()


func configure(place_name: String, local_anchor: Vector2) -> bool:
	var normalized := place_name.strip_edges()
	if normalized.is_empty() or local_anchor != local_anchor:
		return false
	_place_name = normalized
	position = local_anchor
	name = "ResidentMarker_%s" % normalized
	return true


func set_available(available: bool) -> void:
	_available = available
	if not available:
		collapse()
	_apply_visibility()


func set_residents(entries: Array) -> void:
	var next_entries: Array[Dictionary] = []
	for value: Variant in entries:
		if next_entries.size() >= MAX_RESIDENT_COUNT:
			break
		if not value is Dictionary:
			continue
		var entry := (value as Dictionary).duplicate(true)
		var resident_name := String(entry.get("name", "")).strip_edges()
		var portrait_path := String(entry.get("portraitPath", "")).strip_edges()
		if (
			resident_name.is_empty()
			or portrait_path.is_empty()
			or not ResourceLoader.exists(portrait_path)
		):
			continue
		entry["name"] = resident_name
		entry["portraitPath"] = portrait_path
		next_entries.append(entry)
	# 任一居民换地点会触发全部标牌刷新；名单没变的标牌不必销毁重建。
	if next_entries == _resident_entries:
		return
	_resident_entries = next_entries
	if _resident_entries.size() <= COLLAPSED_LIMIT:
		_expanded = false
	_rebuild_contents()
	_apply_visibility()


func resident_count() -> int:
	return _resident_entries.size()


func resident_entries() -> Array[Dictionary]:
	return _resident_entries.duplicate(true)


func contains_resident(resident_ref: String) -> bool:
	return _resident_index(resident_ref) >= 0


func is_expanded() -> bool:
	return _expanded


func displayed_resident_count() -> int:
	return _resident_entries.size() if _expanded else mini(
		_resident_entries.size(),
		COLLAPSED_LIMIT,
	)


func overflow_count() -> int:
	return maxi(_resident_entries.size() - COLLAPSED_LIMIT, 0)


func expand() -> void:
	if _expanded or overflow_count() <= 0:
		return
	_expanded = true
	_rebuild_contents()
	expanded_changed.emit(_place_name, true)


func collapse() -> void:
	if not _expanded:
		return
	_expanded = false
	_rebuild_contents()
	expanded_changed.emit(_place_name, false)


func menu_anchor_for_resident(resident_ref: String) -> Vector2:
	var index := _resident_index(resident_ref)
	if index < 0 or index >= _resident_cells.size():
		return Vector2.ZERO
	var cell := _resident_cells[index]
	return Vector2(
		cell.get_center().x,
		_content_offset_y - _marker_size.y * 0.5,
	)


func marker_size() -> Vector2:
	return _marker_size


func display_size() -> Vector2:
	return _marker_size * (
		_content_root.scale if _content_root != null else Vector2.ONE
	)


func set_camera_zoom(camera_zoom: Vector2) -> void:
	var normalized_zoom := Vector2(
		maxf(absf(camera_zoom.x), 0.001),
		maxf(absf(camera_zoom.y), 0.001),
	)
	if camera_zoom.x != camera_zoom.x or camera_zoom.y != camera_zoom.y:
		normalized_zoom = Vector2.ONE
	_camera_zoom = normalized_zoom
	var minimum_zoom := minf(normalized_zoom.x, normalized_zoom.y)
	var screen_scale := Vector2.ONE * maxf(1.0, 1.0 / minimum_zoom) * _touch_scale_multiplier
	if _content_root != null:
		_content_root.scale = screen_scale
	if _hit_area != null:
		_hit_area.scale = screen_scale


func set_touch_scale_multiplier(multiplier: float) -> void:
	_touch_scale_multiplier = maxf(multiplier, 1.0)
	set_camera_zoom(_camera_zoom)


func debug_asset_snapshot() -> Dictionary:
	return {
		"placeName": _place_name,
		"worldAnchored": true,
		"screenProjectionTracking": false,
		"shellTexturePath": (
			_active_shell_texture.resource_path
			if _active_shell_texture != null
			else ""
		),
		"nativeTextureSize": (
			_active_shell_texture.get_size()
			if _active_shell_texture != null
			else Vector2.ZERO
		),
		"markerSize": _marker_size,
		"runtimeTextureScaled": false,
		"minimumScreenSizeLocked": true,
		"cameraZoom": _camera_zoom,
		"contentScreenScale": (
			_content_root.scale if _content_root != null else Vector2.ONE
		),
		"hitAreaScreenScale": (
			_hit_area.scale if _hit_area != null else Vector2.ONE
		),
		"portraitRimTexturePath": "",
		"usesPortraitFrame": false,
		"overflowFrameTexturePath": OVERFLOW_CHIP_TEXTURE.resource_path,
		"overflowFramed": overflow_count() > 0 and not _expanded,
		"dividerKind": "image_asset_blurred",
		"visibleSurfaceKind": "image_asset",
		"programmaticFrameCount": 0,
		"residentCount": resident_count(),
		"maxResidentCount": MAX_RESIDENT_COUNT,
		"displayedResidentCount": displayed_resident_count(),
		"overflowCount": overflow_count(),
		"expanded": _expanded,
		"layoutRows": _layout_rows,
		"layoutColumns": _layout_columns,
	}


func _build_content_root() -> void:
	_content_root = Node2D.new()
	_content_root.name = "MarkerContents"
	add_child(_content_root)


func _build_hit_area() -> void:
	_hit_area = Area2D.new()
	_hit_area.name = "MarkerHitArea"
	_hit_area.collision_layer = INPUT_COLLISION_LAYER
	_hit_area.collision_mask = 0
	_hit_area.monitoring = false
	_hit_area.monitorable = false
	_hit_area.input_pickable = false
	_hit_area.input_event.connect(_on_hit_area_input)
	add_child(_hit_area)
	var shape_node := CollisionShape2D.new()
	shape_node.name = "MarkerHitShape"
	shape_node.shape = RectangleShape2D.new()
	_hit_area.add_child(shape_node)


func _rebuild_contents() -> void:
	if _content_root == null:
		return
	for child in _content_root.get_children():
		child.free()
	_resident_cells.clear()
	_overflow_cell = Rect2()
	_active_shell_texture = null
	_layout_rows = 0
	_layout_columns = 0
	var shown_count := displayed_resident_count()
	if shown_count <= 0:
		_marker_size = Vector2.ZERO
		_content_offset_y = 0.0
		_content_root.position = Vector2.ZERO
		_hit_area.position = Vector2.ZERO
		_update_hit_shape()
		return
	var has_overflow := not _expanded and overflow_count() > 0
	_layout_columns = shown_count
	if _expanded:
		_layout_columns = (
			MAX_GRID_COLUMNS
			if shown_count > 12
			else STANDARD_GRID_COLUMNS
		)
	elif has_overflow:
		_layout_columns = STANDARD_GRID_COLUMNS
	_layout_rows = maxi(
		1,
		ceili(float(shown_count) / float(_layout_columns)),
	)
	_marker_size = Vector2(
		PANEL_PADDING * 2.0 + CELL_WIDTH * float(_layout_columns),
		PANEL_PADDING * 2.0 + CELL_HEIGHT * float(_layout_rows),
	)
	_content_offset_y = (
		-(_marker_size.y - (PANEL_PADDING * 2.0 + CELL_HEIGHT)) * 0.5
		if _expanded
		else 0.0
	)
	_content_root.position = Vector2(0.0, _content_offset_y)
	_hit_area.position = Vector2(0.0, _content_offset_y)
	_update_hit_shape()
	_build_glass_asset(has_overflow)
	for index in range(shown_count):
		var cell := _cell_rect(index)
		_resident_cells.append(cell)
		_build_resident_cell(_resident_entries[index], cell)
	if has_overflow:
		_build_overflow_cell()


func _cell_rect(index: int) -> Rect2:
	var column := index % _layout_columns
	var row := index / _layout_columns
	return Rect2(
		Vector2(
			-_marker_size.x * 0.5 + PANEL_PADDING + float(column) * CELL_WIDTH,
			-_marker_size.y * 0.5 + PANEL_PADDING + float(row) * CELL_HEIGHT,
		),
		Vector2(CELL_WIDTH, CELL_HEIGHT),
	)


func _build_glass_asset(has_overflow: bool) -> void:
	_active_shell_texture = _shell_texture(has_overflow)
	var shell := Sprite2D.new()
	shell.name = "GlassShell"
	shell.texture = _active_shell_texture
	shell.centered = true
	shell.position = Vector2.ZERO
	shell.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_content_root.add_child(shell)


func _shell_texture(has_overflow: bool) -> Texture2D:
	if _expanded:
		if _layout_columns == MAX_GRID_COLUMNS:
			return FIFTEEN_RESIDENT_TEXTURE
		match _layout_rows:
			1:
				return ONE_ROW_TEXTURE
			2:
				return TWO_ROW_TEXTURE
			3:
				return THREE_ROW_TEXTURE
			_:
				return THREE_ROW_TEXTURE
	if has_overflow:
		return ONE_ROW_TEXTURE
	match _layout_columns:
		1:
			return ONE_RESIDENT_TEXTURE
		2:
			return TWO_RESIDENT_TEXTURE
		_:
			return THREE_RESIDENT_TEXTURE


func _build_resident_cell(entry: Dictionary, cell: Rect2) -> void:
	var source := load(String(entry.get("portraitPath", ""))) as Texture2D
	if source == null:
		return
	var crop := AtlasTexture.new()
	crop.atlas = source
	crop.region = PORTRAIT_CROP
	var portrait := TextureRect.new()
	portrait.name = "Portrait_%s" % String(entry.get("name", ""))
	portrait.position = Vector2(
		cell.get_center().x - PORTRAIT_SIZE * 0.5,
		cell.position.y + 1.0,
	)
	portrait.size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	portrait.texture = crop
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_root.add_child(portrait)
	_build_name(entry, cell)


func _build_name(entry: Dictionary, cell: Rect2) -> void:
	var label := Label.new()
	label.name = "Name_%s" % String(entry.get("name", ""))
	label.position = Vector2(cell.position.x, cell.position.y + 34.0)
	label.size = Vector2(CELL_WIDTH, 18.0)
	label.text = String(entry.get("name", ""))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_apply_label_font(label, NAME_FONT_SIZE)
	_content_root.add_child(label)


func _build_overflow_cell() -> void:
	_overflow_cell = _cell_rect(COLLAPSED_LIMIT)
	var chip_center := (
		_overflow_cell.get_center()
		+ OVERFLOW_CHIP_OPTICAL_OFFSET
	)
	var chip := Sprite2D.new()
	chip.name = "ResidentOverflowImageFrame"
	chip.texture = OVERFLOW_CHIP_TEXTURE
	chip.centered = true
	chip.position = chip_center
	chip.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_content_root.add_child(chip)
	var count_label := Label.new()
	count_label.name = "ResidentOverflowCount"
	count_label.position = (
		chip_center
		- OVERFLOW_CHIP_SIZE * 0.5
		+ OVERFLOW_TEXT_OPTICAL_OFFSET
	)
	count_label.size = OVERFLOW_CHIP_SIZE
	count_label.text = "+%d" % overflow_count()
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_label_font(count_label, 12)
	_content_root.add_child(count_label)


func _apply_label_font(label: Label, font_size: int) -> void:
	var font := FontVariation.new()
	font.base_font = NAME_FONT
	font.variation_embolden = 0.16
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.247, 0.157, 0.094, 1.0))
	label.add_theme_color_override("font_outline_color", Color(1.0, 0.973, 0.902, 0.96))
	label.add_theme_constant_override("outline_size", 1)
	label.add_theme_constant_override("spacing_glyph", 1)


func _update_hit_shape() -> void:
	if _hit_area == null:
		return
	var shape_node := _hit_area.get_node_or_null("MarkerHitShape") as CollisionShape2D
	if shape_node == null or not shape_node.shape is RectangleShape2D:
		return
	(shape_node.shape as RectangleShape2D).size = Vector2(
		maxf(_marker_size.x, 1.0),
		maxf(_marker_size.y, 1.0),
	)


func _apply_visibility() -> void:
	var shown := _available and not _resident_entries.is_empty()
	visible = shown
	if _hit_area != null:
		_hit_area.input_pickable = shown
		_hit_area.collision_layer = INPUT_COLLISION_LAYER if shown else 0


func _on_hit_area_input(
	viewport: Viewport,
	event: InputEvent,
	_shape_index: int,
) -> void:
	if (
		not _available
		or not POINTER_INPUT.is_primary_press(event)
	):
		return
	if _hit_area == null or not _hit_area.input_pickable:
		return
	var local_position := _hit_area.to_local(POINTER_INPUT.position(event))
	if _overflow_cell.has_area() and _overflow_cell.has_point(local_position):
		viewport.set_input_as_handled()
		expand()
		return
	for index in range(_resident_cells.size()):
		if _resident_cell_hit_area_for(_resident_cells[index]).has_point(local_position):
			viewport.set_input_as_handled()
			_activate_resident(index)
			return
	var hotspot := get_parent() as Node
	if hotspot != null and hotspot.has_method("activate_from_overlapping_marker"):
		hotspot.call("activate_from_overlapping_marker", viewport, event)


func _activate_resident(index: int) -> void:
	if index < 0 or index >= _resident_entries.size():
		return
	var entry := _resident_entries[index]
	resident_activated.emit(
		String(entry.get("residentId", "")),
		String(entry.get("name", "")),
	)


func _resident_index(resident_ref: String) -> int:
	var normalized := resident_ref.strip_edges()
	if normalized.is_empty():
		return -1
	for index in range(_resident_entries.size()):
		var entry := _resident_entries[index]
		if (
			String(entry.get("residentId", "")) == normalized
			or String(entry.get("name", "")) == normalized
		):
			return index
	return -1


func _resident_cell_hit_area_for(cell: Rect2) -> Rect2:
	var portrait_region := Rect2(
		cell.position
			+ Vector2(
				(CELL_WIDTH - PORTRAIT_SIZE) * 0.5,
				1.0,
			),
		Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE),
	)
	var name_region := Rect2(
		cell.position + Vector2(0.0, 34.0),
		Vector2(CELL_WIDTH, 18.0),
	)
	var union_left := minf(portrait_region.position.x, name_region.position.x)
	var union_top := minf(portrait_region.position.y, name_region.position.y)
	var union_right := maxf(
		portrait_region.position.x + portrait_region.size.x,
		name_region.position.x + name_region.size.x,
	)
	var union_bottom := maxf(
		portrait_region.position.y + portrait_region.size.y,
		name_region.position.y + name_region.size.y,
	)
	return Rect2(
		Vector2(union_left, union_top),
		Vector2(
			union_right - union_left,
			union_bottom - union_top,
		),
	)
