class_name TownPerceptionRuntime
extends RefCounted


# 感知刷新与空间网格索引(自 TownWorldRuntime 下沉,docs/性能优化方案.md 点名的
# 热路径)。world 为世界运行时实例;函数内把反复访问的 world 字段提升为局部
# 变量,避免逐次动态查找。

class SpatialState:
	var last_spatial_state: Array = []
	var initialized := false
	var full_scan_count := 0
	var grid_cells_by_space: Dictionary = {}
	var grid_cell_size_by_space: Dictionary = {}

	func reset() -> void:
		last_spatial_state.clear()
		initialized = false
		full_scan_count = 0


static func _refresh_perception(world, emit_events: bool) -> void:
	var spatial_state := _perception_spatial_state(world)
	if (
		emit_events
		and world.perception_spatial.initialized
		and spatial_state == world.perception_spatial.last_spatial_state
	):
		return
	world.perception_spatial.last_spatial_state = spatial_state
	world.perception_spatial.initialized = true
	world.perception_spatial.full_scan_count += 1
	# Freeze the stable world views once for this refresh. Re-entering dynamic
	# accessors inside every bucket/pair comparison was a large part of the
	# once-per-game-minute main-thread spike, while all of these collections are
	# intentionally updated only after the pair scan completes.
	var resident_order: Array = world.resident_order()
	var residents: Dictionary = world.residents()
	var player_avatar: Dictionary = world.player_avatar()
	var player_present: bool = world.player_avatar_present()
	var perception_range := float(world.world_data().get("perceptionRange", 0.0))
	var next_by_resident := {}
	var previous_player := (
		player_avatar.get("nearby", []) as Array
	).duplicate()
	for resident_name in resident_order:
		next_by_resident[resident_name] = []
	# Residents only need to be compared with people in the same or adjacent
	# spatial buckets. The bucket width includes the exit hysteresis, so a pair
	# that can still be nearby cannot skip over an adjacent bucket.
	var bucket_size := maxf(
		perception_range + world.PERCEPTION_EXIT_HYSTERESIS_PX,
		1.0,
	)
	var resident_buckets: Dictionary = {}
	var resident_bucket_info: Dictionary = {}
	var resident_index_by_name: Dictionary = {}
	var resident_present: Dictionary = {}
	for resident_index in resident_order.size():
		var resident_name: Variant = resident_order[resident_index]
		resident_index_by_name[resident_name] = resident_index
		var resident := residents[resident_name] as Dictionary
		var is_present: bool = world.resident_is_present(resident)
		resident_present[resident_name] = is_present
		if not is_present:
			continue
		var space_id := String(resident.get("spaceId", ""))
		var region_id := String(resident.get("regionId", ""))
		if space_id.is_empty() or region_id.is_empty():
			continue
		var position := resident.get("position", Vector2.ZERO) as Vector2
		var cell := Vector2i(
			floori(position.x / bucket_size),
			floori(position.y / bucket_size),
		)
		var bucket_key := "%s|%s|%d|%d" % [
			space_id,
			region_id,
			cell.x,
			cell.y,
		]
		var bucket := resident_buckets.get(bucket_key, []) as Array
		bucket.append(resident_name)
		resident_buckets[bucket_key] = bucket
		resident_bucket_info[resident_name] = {
			"spaceId": space_id,
			"regionId": region_id,
			"cell": cell,
		}
	for left_index in resident_order.size():
		var left_name : Variant = resident_order[left_index]
		var left := residents[left_name] as Dictionary
		var left_info := resident_bucket_info.get(left_name, {}) as Dictionary
		if not bool(resident_present.get(left_name, false)) or left_info.is_empty():
			continue
		var left_cell := left_info.get("cell", Vector2i.ZERO) as Vector2i
		for cell_x in range(left_cell.x - 1, left_cell.x + 2):
			for cell_y in range(left_cell.y - 1, left_cell.y + 2):
				var bucket_key := "%s|%s|%d|%d" % [
					String(left_info.get("spaceId", "")),
					String(left_info.get("regionId", "")),
					cell_x,
					cell_y,
				]
				for right_value: Variant in resident_buckets.get(bucket_key, []) as Array:
					var right_name := String(right_value)
					var right_index := int(resident_index_by_name.get(right_name, -1))
					if right_index <= left_index:
						continue
					var right := residents[right_name] as Dictionary
					var was_nearby := (
						(left.get("nearby", []) as Array).has(right_name)
						or (right.get("nearby", []) as Array).has(left_name)
					)
					var range_limit: float = (
						perception_range + world.PERCEPTION_EXIT_HYSTERESIS_PX
						if was_nearby
						else perception_range
					)
					if (
						(left.get("position", Vector2.ZERO) as Vector2).distance_squared_to(
							right.get("position", Vector2.ZERO) as Vector2,
						) <= range_limit * range_limit
					):
						(next_by_resident[left_name] as Array).append(right_name)
						(next_by_resident[right_name] as Array).append(left_name)
	var next_by_player: Array[String] = []
	if player_present:
		for resident_name in resident_order:
			var resident := residents[resident_name] as Dictionary
			if not bool(resident_present.get(resident_name, false)):
				continue
			var was_nearby := (
				(resident.get("nearby", []) as Array).has(world.player_avatar_id())
				or previous_player.has(resident_name)
			)
			var range_limit: float = (
				perception_range + world.PERCEPTION_EXIT_HYSTERESIS_PX
				if was_nearby
				else perception_range
			)
			if (
				String(resident.get("spaceId", ""))
					== String(player_avatar.get("spaceId", ""))
				and String(resident.get("regionId", ""))
					== String(player_avatar.get("regionId", ""))
				and (resident.get("position", Vector2.ZERO) as Vector2).distance_squared_to(
					player_avatar.get("position", Vector2.ZERO) as Vector2,
				) <= range_limit * range_limit
			):
				(next_by_resident[resident_name] as Array).append(
					world.player_avatar_id(),
				)
				next_by_player.append(resident_name)
	for resident_name in resident_order:
		var resident := residents[resident_name] as Dictionary
		var previous := (resident.get("nearby", []) as Array).duplicate()
		var current := next_by_resident[resident_name] as Array
		current.sort()
		resident["nearby"] = current
		if not emit_events or not bool(resident_present.get(resident_name, false)):
			continue
		if previous != current:
			var added: Array = []
			var removed: Array = []
			for other_name: Variant in current:
				if not previous.has(other_name):
					added.append(other_name)
			for other_name: Variant in previous:
				if not current.has(other_name):
					removed.append(other_name)
			world.resident_perception_changed.emit(world.resident_display_name(resident_name), {
				"residentId": resident_name,
				"added": added,
				"removed": removed,
				"nearby": current.duplicate(),
				"time": world.get_time(),
			})
		for other_name: Variant in current:
			if not previous.has(other_name):
				world.queue_world_event(resident_name, {
					"type": "有人来了",
					"who_resident_id": world.person_id_for_name(String(other_name)),
					"who": world.person_name_for_id(world.person_id_for_name(String(other_name))),
				})
		for other_name: Variant in previous:
			if not current.has(other_name):
				world.queue_world_event(resident_name, {
					"type": "有人走了",
					"who_resident_id": world.person_id_for_name(String(other_name)),
					"who": world.person_name_for_id(world.person_id_for_name(String(other_name))),
				})
	next_by_player.sort()
	player_avatar["nearby"] = next_by_player
	if emit_events and previous_player != next_by_player:
		var player_added: Array[String] = []
		var player_removed: Array[String] = []
		for resident_name in next_by_player:
			if not previous_player.has(resident_name):
				player_added.append(world.resident_display_name(resident_name))
		for resident_name_value: Variant in previous_player:
			var resident_name := String(resident_name_value)
			if not next_by_player.has(resident_name):
				player_removed.append(world.resident_display_name(resident_name))
		var nearby_names: Array[String] = []
		for resident_id in next_by_player:
			nearby_names.append(world.resident_display_name(resident_id))
		world.player_avatar_perception_changed.emit({
			"source": "world_perception_refresh",
			"added": player_added,
			"removed": player_removed,
			"nearbyResidentIds": next_by_player.duplicate(),
			"nearby": nearby_names,
			"time": world.get_time(),
		})
		world.player_avatar_state_changed.emit(world.get_player_avatar_state())
	if emit_events:
		world.CONVERSATION_RUNTIME._end_conversations_out_of_range(world)


static func _refresh_player_avatar_perception(
	world,
	emit_events: bool,
	bump_revision_on_change: bool,
	semantic_state_changed := false,
	avatar_position_changed := false,
) -> bool:
	var player_id : Variant = world.player_avatar_id()
	var previous_player := (
		world.player_avatar().get("nearby", []) as Array
	).duplicate()
	var next_by_player: Array[String] = []
	var resident_deltas: Array[Dictionary] = []
	for resident_name in world.resident_order():
		var resident := world.residents()[resident_name] as Dictionary
		var previous := (resident.get("nearby", []) as Array).duplicate()
		var current := previous.duplicate()
		current.erase(player_id)
		if world.player_avatar_present() and world.resident_is_present(resident):
			var was_nearby := (
				previous.has(player_id)
				or previous_player.has(resident_name)
			)
			if _are_nearby_with_hysteresis(world, 
				resident,
				world.player_avatar(),
				was_nearby,
			):
				current.append(player_id)
				next_by_player.append(resident_name)
		current.sort()
		resident["nearby"] = current
		if previous != current:
			resident_deltas.append({
				"residentId": resident_name,
				"previous": previous,
				"current": current,
			})
	next_by_player.sort()
	world.player_avatar()["nearby"] = next_by_player
	_cache_player_avatar_perception_spatial_state(world)
	var player_nearby_changed := previous_player != next_by_player
	var perception_changed := (
		player_nearby_changed or not resident_deltas.is_empty()
	)
	if perception_changed and bump_revision_on_change:
		world.bump_world_revision(false)
	if emit_events:
		for delta in resident_deltas:
			var resident_name := String(delta.get("residentId", ""))
			var previous := delta.get("previous", []) as Array
			var current := delta.get("current", []) as Array
			var added: Array = []
			var removed: Array = []
			for other_name: Variant in current:
				if not previous.has(other_name):
					added.append(other_name)
			for other_name: Variant in previous:
				if not current.has(other_name):
					removed.append(other_name)
			world.resident_perception_changed.emit(
				world.resident_display_name(resident_name),
				{
					"residentId": resident_name,
					"added": added,
					"removed": removed,
					"nearby": current.duplicate(),
					"time": world.get_time(),
				},
			)
			for other_name: Variant in added:
				world.queue_world_event(resident_name, {
					"type": "有人来了",
					"who_resident_id": world.person_id_for_name(String(other_name)),
					"who": world.person_name_for_id(world.person_id_for_name(String(other_name))),
				})
			for other_name: Variant in removed:
				world.queue_world_event(resident_name, {
					"type": "有人走了",
					"who_resident_id": world.person_id_for_name(String(other_name)),
					"who": world.person_name_for_id(world.person_id_for_name(String(other_name))),
				})
		if player_nearby_changed or avatar_position_changed or semantic_state_changed:
			var player_added: Array[String] = []
			var player_removed: Array[String] = []
			for resident_name in next_by_player:
				if not previous_player.has(resident_name):
					player_added.append(world.resident_display_name(resident_name))
			for resident_name_value: Variant in previous_player:
				var resident_name := String(resident_name_value)
				if not next_by_player.has(resident_name):
					player_removed.append(world.resident_display_name(resident_name))
			var nearby_names: Array[String] = []
			for resident_id in next_by_player:
				nearby_names.append(world.resident_display_name(resident_id))
			world.player_avatar_perception_changed.emit({
				"source": "avatar_position",
				"semanticStateChanged": semantic_state_changed,
				"positionChanged": avatar_position_changed,
				"added": player_added,
				"removed": player_removed,
				"nearbyResidentIds": next_by_player.duplicate(),
				"nearby": nearby_names,
				"time": world.get_time(),
			})
		world.CONVERSATION_RUNTIME._end_conversations_out_of_range(world)
	return perception_changed


static func _cache_player_avatar_perception_spatial_state(world) -> void:
	if (
		not world.perception_spatial.initialized
		or world.perception_spatial.last_spatial_state.is_empty()
	):
		return
	var player_index : Variant = world.perception_spatial.last_spatial_state.size() - 1
	var cached_player := (
		world.perception_spatial.last_spatial_state[player_index] as Array
	)
	if cached_player.is_empty() or String(cached_player[0]) != "__player__":
		return
	world.perception_spatial.last_spatial_state[player_index] = [
		"__player__",
		world.player_avatar_present(),
		String(world.player_avatar().get("spaceId", "")),
		String(world.player_avatar().get("regionId", "")),
		world.player_avatar().get("position", Vector2.ZERO) as Vector2,
	]


static func _perception_spatial_state(world) -> Array:
	var result: Array = []
	for resident_id: String in world.resident_order():
		var resident := world.residents().get(resident_id, {}) as Dictionary
		result.append([
			resident_id,
			world.resident_is_present(resident),
			String(resident.get("spaceId", "")),
			String(resident.get("regionId", "")),
			resident.get("position", Vector2.ZERO) as Vector2,
		])
	result.append([
		"__player__",
		world.player_avatar_present(),
		String(world.player_avatar().get("spaceId", "")),
		String(world.player_avatar().get("regionId", "")),
		world.player_avatar().get("position", Vector2.ZERO) as Vector2,
	])
	return result


static func _are_nearby(world, left: Dictionary, right: Dictionary) -> bool:
	return _are_nearby_with_limit(world, 
		left,
		right,
		float(world.world_data().get("perceptionRange", 0.0)),
	)


static func _are_nearby_with_hysteresis(
	world,
	left: Dictionary,
	right: Dictionary,
	was_nearby: bool,
) -> bool:
	var range_limit := float(world.world_data().get("perceptionRange", 0.0))
	if was_nearby:
		range_limit += world.PERCEPTION_EXIT_HYSTERESIS_PX
	return _are_nearby_with_limit(world, left, right, range_limit)


static func _are_nearby_with_limit(
	world,
	left: Dictionary,
	right: Dictionary,
	range_limit: float,
) -> bool:
	if (
		not world.resident_is_present(left)
		or (
			right.has("arrivalState")
			and not world.resident_is_present(right)
		)
	):
		return false
	var left_space := String(left.get("spaceId", ""))
	var right_space := String(right.get("spaceId", ""))
	var left_region := String(left.get("regionId", ""))
	var right_region := String(right.get("regionId", ""))
	return (
		not left_space.is_empty()
		and not left_region.is_empty()
		and left_space == right_space
		and left_region == right_region
		and (
			left.get("position", Vector2.ZERO) as Vector2
		).distance_to(
			right.get("position", Vector2.ZERO) as Vector2
		) <= range_limit
	)


static func _are_currently_perceived(
	world,
	left_id: String,
	left: Dictionary,
	right_id: String,
	right: Dictionary,
) -> bool:
	return (
		(left.get("nearby", []) as Array).has(right_id)
		and (right.get("nearby", []) as Array).has(left_id)
	)


static func _membership(world, space_id: String, position: Vector2) -> Dictionary:
	var grid_cell_size := int(
		world.perception_spatial.grid_cell_size_by_space.get(space_id, 0)
	)
	if grid_cell_size > 0:
		var cell := Vector2i(
			floori(position.x / float(grid_cell_size)),
			floori(position.y / float(grid_cell_size)),
		)
		var cells := (
			world.perception_spatial.grid_cells_by_space.get(space_id, {}) as Dictionary
		)
		var indexed_membership := cells.get(cell, {}) as Dictionary
		if not indexed_membership.is_empty():
			return indexed_membership.duplicate()
	for value: Variant in world.world_data().get("perceptionRegions", []) as Array:
		var region := value as Dictionary
		if String(region.get("spaceId", "")) != space_id:
			continue
		if (
			grid_cell_size > 0
			and String((region.get("shape", {}) as Dictionary).get("type", ""))
				== "grid_cells"
		):
			continue
		if _position_in_shape(world, position, region.get("shape", {}) as Dictionary):
			return {"regionId": String(region.get("id", "")), "placeName": String(region.get("placeName", ""))}
	return {}


static func _rebuild_membership_grid_lookup(world) -> void:
	world.perception_spatial.grid_cells_by_space.clear()
	world.perception_spatial.grid_cell_size_by_space.clear()
	for value: Variant in world.world_data().get("perceptionRegions", []) as Array:
		var region := value as Dictionary
		var shape := region.get("shape", {}) as Dictionary
		if String(shape.get("type", "")) != "grid_cells":
			continue
		var space_id := String(region.get("spaceId", ""))
		var cell_size := int(shape.get("cellSize", 0))
		if space_id.is_empty() or cell_size <= 0:
			continue
		var known_cell_size := int(
			world.perception_spatial.grid_cell_size_by_space.get(space_id, cell_size)
		)
		if known_cell_size != cell_size:
			world.perception_spatial.grid_cell_size_by_space[space_id] = -1
			world.perception_spatial.grid_cells_by_space.erase(space_id)
			continue
		if known_cell_size < 0:
			continue
		world.perception_spatial.grid_cell_size_by_space[space_id] = cell_size
		if not world.perception_spatial.grid_cells_by_space.has(space_id):
			world.perception_spatial.grid_cells_by_space[space_id] = {}
		var cells := world.perception_spatial.grid_cells_by_space[space_id] as Dictionary
		var membership := {
			"regionId": String(region.get("id", "")),
			"placeName": String(region.get("placeName", "")),
		}
		for cell_value: Variant in shape.get("cells", []) as Array:
			var pair := cell_value as Array
			if pair.size() != 2:
				continue
			var cell := Vector2i(int(pair[0]), int(pair[1]))
			if not cells.has(cell):
				cells[cell] = membership


static func _nearest_outdoor_membership(world, position: Vector2) -> Dictionary:
	var nearest_distance := INF
	var nearest: Dictionary = {}
	for value: Variant in world.world_data().get("perceptionRegions", []) as Array:
		var region := value as Dictionary
		if String(region.get("spaceId", "")) != "town_outdoor":
			continue
		var shape := region.get("shape", {}) as Dictionary
		var shape_type := String(shape.get("type", ""))
		if shape_type == "grid_cells":
			var cell_size := float(shape.get("cellSize", 0.0))
			if cell_size <= 0.0:
				continue
			for cell_value: Variant in shape.get("cells", []) as Array:
				var cell := cell_value as Array
				if cell.size() != 2:
					continue
				var center := Vector2(
					(float(cell[0]) + 0.5) * cell_size,
					(float(cell[1]) + 0.5) * cell_size,
				)
				var distance := position.distance_squared_to(center)
				if distance < nearest_distance:
					nearest_distance = distance
					nearest = {
						"regionId": String(region.get("id", "")),
						"placeName": String(region.get("placeName", "")),
					}
		elif shape_type == "rect":
			var rect := Rect2(
				float(shape.get("x", 0.0)),
				float(shape.get("y", 0.0)),
				float(shape.get("width", 0.0)),
				float(shape.get("height", 0.0)),
			)
			var closest := Vector2(
				clampf(position.x, rect.position.x, rect.end.x),
				clampf(position.y, rect.position.y, rect.end.y),
			)
			var distance := position.distance_squared_to(closest)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest = {
					"regionId": String(region.get("id", "")),
					"placeName": String(region.get("placeName", "")),
				}
	return nearest if nearest_distance <= 480.0 * 480.0 else {}


static func _position_in_shape(world, position: Vector2, shape: Dictionary) -> bool:
	if String(shape.get("type", "")) == "grid_cells":
		var cell_size := int(shape.get("cellSize", 0))
		if cell_size <= 0:
			return false
		var expected := Vector2i(floori(position.x / float(cell_size)), floori(position.y / float(cell_size)))
		for value: Variant in shape.get("cells", []) as Array:
			var pair := value as Array
			if Vector2i(int(pair[0]), int(pair[1])) == expected:
				return true
		return false
	if String(shape.get("type", "")) == "rect":
		return Rect2(float(shape.get("x", 0.0)), float(shape.get("y", 0.0)), float(shape.get("width", 0.0)), float(shape.get("height", 0.0))).has_point(position)
	return false
