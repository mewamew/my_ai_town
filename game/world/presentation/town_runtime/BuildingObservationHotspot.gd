extends Area2D

const POINTER_INPUT := preload("res://ui/mobile/PointerInput.gd")


signal activated(place_name: String)


const INPUT_COLLISION_LAYER := 1 << 15
const FOCUS_LIGHT_TEXTURE_SIZE := 256
const FOCUS_LIGHT_DIAMETER_MULTIPLIER := 1.15
const FOCUS_LIGHT_ENERGY := 0.42
const MAX_PLACE_NAME_LENGTH := 128
const MAX_CANVAS_COMPONENT := 1_000_000.0

var _place_name := ""
var _world_position := Vector2.ZERO
var _available := false
var _focused := false
var _input_shape: CollisionShape2D
var _focus_light: PointLight2D


func _init() -> void:
	z_index = 170
	z_as_relative = false
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = false
	input_pickable = false


func _enter_tree() -> void:
	if not _place_name.is_empty():
		global_position = _world_position


func configure(
	place_name_value: Variant,
	world_position_value: Variant,
	hit_size_value: Variant,
) -> bool:
	var place_name := _canonical_place_name(place_name_value)
	if (
		place_name.is_empty()
		or not world_position_value is Vector2
		or not hit_size_value is Vector2
	):
		return false
	var world_position := world_position_value as Vector2
	var hit_size := hit_size_value as Vector2
	if not _valid_position(world_position) or not _valid_hit_size(hit_size):
		return false

	var rectangle := RectangleShape2D.new()
	rectangle.size = hit_size
	var next_input_shape := CollisionShape2D.new()
	next_input_shape.name = "InputShape"
	next_input_shape.shape = rectangle

	var next_focus_light := PointLight2D.new()
	next_focus_light.name = "BuildingFocusLight"
	next_focus_light.texture = _building_focus_texture()
	next_focus_light.texture_scale = (
		maxf(hit_size.x, hit_size.y)
		* FOCUS_LIGHT_DIAMETER_MULTIPLIER
		/ float(FOCUS_LIGHT_TEXTURE_SIZE)
	)
	next_focus_light.color = Color(1.0, 0.78, 0.38)
	next_focus_light.energy = FOCUS_LIGHT_ENERGY
	next_focus_light.shadow_enabled = false
	next_focus_light.visible = _focused and _available

	_release_owned_node(_input_shape)
	_release_owned_node(_focus_light)
	_input_shape = next_input_shape
	_focus_light = next_focus_light
	add_child(_input_shape)
	add_child(_focus_light)

	_place_name = place_name
	_world_position = world_position
	if is_inside_tree():
		global_position = _world_position
	else:
		position = _world_position
	collision_layer = INPUT_COLLISION_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = false
	input_pickable = _available
	return true


func set_available(value: Variant) -> bool:
	if not value is bool:
		return false
	var requested := value as bool
	if requested and _place_name.is_empty():
		return false
	_available = requested
	input_pickable = _available
	if not _available:
		_set_focused_unchecked(false)
	return true


func set_focused(value: Variant) -> bool:
	if not value is bool:
		return false
	var requested := value as bool
	if requested and not _available:
		return false
	_set_focused_unchecked(requested)
	return true


func is_available() -> bool:
	return _available


func is_focused() -> bool:
	return _focused


func configured_place_name() -> String:
	return _place_name


func _set_focused_unchecked(value: bool) -> void:
	_focused = value
	if is_instance_valid(_focus_light):
		_focus_light.visible = _focused


func _building_focus_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.52, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 0.90, 0.58, 0.40),
		Color(1.0, 0.72, 0.28, 0.16),
		Color(1.0, 0.62, 0.16, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.width = FOCUS_LIGHT_TEXTURE_SIZE
	texture.height = FOCUS_LIGHT_TEXTURE_SIZE
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture


func _input_event(
	viewport: Viewport,
	event: InputEvent,
	_shape_index: int,
) -> void:
	_activate_from_pointer(viewport, event)


func activate_from_overlapping_marker(
	viewport: Viewport,
	event: InputEvent,
) -> void:
	# Physics input can report a child roof Area2D before its parent building
	# Area2D. The marker delegates non-resident-cell clicks here so the house
	# still owns the whole building footprint deterministically.
	_activate_from_pointer(viewport, event)


func _activate_from_pointer(viewport: Viewport, event: InputEvent) -> void:
	if (
		not _available
		or not POINTER_INPUT.is_primary_press(event)
	):
		return
	viewport.set_input_as_handled()
	activated.emit(_place_name)


func _release_owned_node(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node.get_parent() == self:
		remove_child(node)
	node.free()


func _canonical_place_name(value: Variant) -> String:
	if not value is String:
		return ""
	var text := value as String
	if (
		text.is_empty()
		or text != text.strip_edges()
		or text.length() > MAX_PLACE_NAME_LENGTH
	):
		return ""
	for index in range(text.length()):
		var codepoint := text.unicode_at(index)
		if (
			codepoint < 32
			or (codepoint >= 127 and codepoint <= 159)
			or _is_unicode_whitespace(codepoint)
			or _is_invisible_format_codepoint(codepoint)
			or _is_visual_blank_codepoint(codepoint)
			or _is_unicode_noncharacter(codepoint)
		):
			return ""
	return text


func _is_unicode_whitespace(codepoint: int) -> bool:
	return (
		codepoint == 0x00A0
		or codepoint == 0x1680
		or (codepoint >= 0x2000 and codepoint <= 0x200A)
		or codepoint == 0x2028
		or codepoint == 0x2029
		or codepoint == 0x202F
		or codepoint == 0x205F
		or codepoint == 0x3000
	)


func _is_invisible_format_codepoint(codepoint: int) -> bool:
	return (
		codepoint == 0x00AD
		or codepoint == 0x034F
		or (codepoint >= 0x0600 and codepoint <= 0x0605)
		or codepoint == 0x061C
		or codepoint == 0x06DD
		or codepoint == 0x070F
		or (codepoint >= 0x0890 and codepoint <= 0x0891)
		or codepoint == 0x08E2
		or (codepoint >= 0x115F and codepoint <= 0x1160)
		or (codepoint >= 0x17B4 and codepoint <= 0x17B5)
		or (codepoint >= 0x180B and codepoint <= 0x180F)
		or (codepoint >= 0x200B and codepoint <= 0x200F)
		or (codepoint >= 0x202A and codepoint <= 0x202E)
		or (codepoint >= 0x2060 and codepoint <= 0x206F)
		or codepoint == 0x3164
		or (codepoint >= 0xFE00 and codepoint <= 0xFE0F)
		or codepoint == 0xFEFF
		or codepoint == 0xFFA0
		or (codepoint >= 0xFFF0 and codepoint <= 0xFFFB)
		or codepoint == 0x110BD
		or codepoint == 0x110CD
		or (codepoint >= 0x13430 and codepoint <= 0x1343F)
		or (codepoint >= 0x1BCA0 and codepoint <= 0x1BCA3)
		or (codepoint >= 0x1D173 and codepoint <= 0x1D17A)
		or (codepoint >= 0xE0000 and codepoint <= 0xE0FFF)
	)


func _is_visual_blank_codepoint(codepoint: int) -> bool:
	return codepoint == 0x2800


func _is_unicode_noncharacter(codepoint: int) -> bool:
	return (
		(codepoint >= 0xFDD0 and codepoint <= 0xFDEF)
		or (
			codepoint <= 0x10FFFF
			and codepoint % 0x10000 >= 0xFFFE
		)
	)


func _valid_position(value: Vector2) -> bool:
	return (
		is_finite(value.x)
		and is_finite(value.y)
		and absf(value.x) <= MAX_CANVAS_COMPONENT
		and absf(value.y) <= MAX_CANVAS_COMPONENT
	)


func _valid_hit_size(value: Vector2) -> bool:
	return (
		_valid_position(value)
		and value.x > 0.0
		and value.y > 0.0
	)
