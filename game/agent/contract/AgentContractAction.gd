class_name AgentContractAction
extends RefCounted
## AgentContract 拆分模块(批次C之4,纯搬运+跨模块调用改类前缀)。


static func _validate_action(
	action: Dictionary,
	initialization: Dictionary,
	wake_packet: Dictionary,
	used_action_ids: Dictionary,
	errors: Array[String],
) -> void:
	var action_id := AgentContract._require_non_empty_string(action, "action_id", "action.action_id", errors)
	if not action_id.is_empty() and used_action_ids.has(action_id):
		errors.append("action.action_id 必须在本 Agent 范围内唯一")
	if not action_id.is_empty() and action_id == AgentContractWake._current_action_id(wake_packet):
		errors.append("action.action_id 不能与当前动作编号重复")
	var action_type := AgentContract._require_non_empty_string(action, "type", "action.type", errors)
	if AgentContract.CONFLICT_CONTRACT.ACTION_TYPES.has(action_type):
		AgentContract.CONFLICT_CONTRACT.validate_action(action, wake_packet, errors)
	if AgentContract.ACTION_FIELDS.has(action_type):
		var allowed_fields: Array = (AgentContract.ACTION_FIELDS[action_type] as Array).duplicate()
		allowed_fields.append_array(
			AgentContract.OPTIONAL_ACTION_FIELDS.get(action_type, []) as Array
		)
		allowed_fields.append_array(
			AgentContract.MODEL_ONLY_ACTION_FIELDS.get(action_type, []) as Array
		)
		# 模型有时会把对话的 end 带到普通动作里；它不会参与执行，规范化时会丢弃。
		if action_type != "答话":
			allowed_fields.append("end")
		AgentContractIdentity._validate_allowed_fields(action, allowed_fields, "action", errors)
	if action_type == "去":
		var place := AgentContract._require_non_empty_string(action, "place", "action.place", errors)
		AgentContract._require_non_empty_string(action, "line", "action.line", errors)
		if not place.is_empty() and not AgentContractWake._initialization_has_place(initialization, place):
			errors.append("action.place 必须来自 Agent 当前的地点资料")
		var snapshot_place := (
			(wake_packet.get("snapshot", {}) as Dictionary).get(
				"place",
				{},
			) as Dictionary
		)
		var current_place := String(
			snapshot_place.get("name", ""),
		)
		# 提交"当前地点"视为原地停留: 不拒绝、不检查 destinations。
		# 夜间可去地点极少, 蹲守/留守的居民(如卧底跟踪)想留在原地时容易
		# 误把当前地点填进"去", 拒绝会让居民反复提交同一失败动作而卡死循环。
		if not place.is_empty() and place != current_place:
			if (
				snapshot_place.has("destinations")
				and not (
					snapshot_place.get("destinations", []) as Array
				).has(place)
			):
				errors.append(
					(
						"action.place 当前不可前往，必须来自 snapshot.place.destinations；"
						+ "已关闭或已失效的地点不能继续作为去的目标，想留在原地等候必须改用待着"
					)
				)
	elif action_type == "用道具":
		var prop := AgentContract._require_non_empty_string(action, "prop", "action.prop", errors)
		var verb := AgentContract._require_non_empty_string(action, "verb", "action.verb", errors)
		AgentContract._require_non_empty_string(action, "line", "action.line", errors)
		if not prop.is_empty() and not verb.is_empty() and not AgentContractWake._wake_has_prop_verb(wake_packet, prop, verb):
			errors.append("action.prop 和 action.verb 必须来自当前地点可用道具")
	elif action_type == "做活动":
		var activity_id := AgentContract._require_non_empty_string(
			action,
			"activity_id",
			"action.activity_id",
			errors,
		)
		AgentContract._require_non_empty_string(action, "line", "action.line", errors)
		if (
			not activity_id.is_empty()
			and not AgentContractWake._wake_has_activity(wake_packet, activity_id)
		):
			errors.append(
				"action.activity_id 必须来自当前地点可做活动"
			)
	elif action_type == "调整营业":
		var place_id := AgentContract._require_non_empty_string(
			action,
			"place_id",
			"action.place_id",
			errors,
		)
		if typeof(action.get("open")) != TYPE_BOOL:
			errors.append("action.open 必须是布尔值")
		AgentContract._require_non_empty_string(action, "line", "action.line", errors)
		var control := (
			(
				wake_packet.get("snapshot", {}) as Dictionary
			).get("place", {}) as Dictionary
		).get("service_control", {}) as Dictionary
		if (
			control.is_empty()
			or String(control.get("place_id", "")) != place_id
			or bool(control.get("open", false))
			== bool(action.get("open", false))
		):
			errors.append(
				"调整营业必须引用本人当前可控制的地点并改变现有状态"
			)
	elif action_type == "托人传话":
		var recipient_id := AgentContractIdentity._validate_resident_id(
			action,
			"recipient_resident_id",
			"action.recipient_resident_id",
			errors,
		)
		var content := AgentContract._require_non_empty_string(
			action,
			"content",
			"action.content",
			errors,
		)
		AgentContract._require_non_empty_string(action, "line", "action.line", errors)
		var me_id := String(
			(initialization.get("me", {}) as Dictionary).get(
				"resident_id",
				"",
			),
		)
		if recipient_id == me_id:
			errors.append("action.recipient_resident_id 不能是本人")
		elif (
			not recipient_id.is_empty()
			and not AgentContractWake._initialization_has_resident(
				initialization,
				recipient_id,
			)
		):
			errors.append(
				"action.recipient_resident_id 必须来自初始化居民表"
			)
		if (
			content.length() > 240
			or content.contains("\n")
			or content.contains("\r")
			or content.contains("\t")
		):
			errors.append("action.content 必须是最多 240 字的单行文字")
	elif action_type == "待着":
		AgentContract._require_non_empty_string(action, "line", "action.line", errors)
	elif action_type == "向警察汇报":
		# 审讯会汇报期动作: kind 必填; wake 带有汇报类型清单时必须取自其中
		# (与 TownWerewolfRuntime.ASSEMBLY_REPORT_KINDS 的世界侧校验一致)。
		var report_kind := AgentContract._require_non_empty_string(action, "kind", "action.kind", errors)
		var assembly_value: Variant = (
			(wake_packet.get("snapshot", {}) as Dictionary).get("assembly", {})
		)
		if (
			not report_kind.is_empty()
			and assembly_value is Dictionary
		):
			var report_kinds := (assembly_value as Dictionary).get("kinds", []) as Array
			if not report_kinds.is_empty() and not report_kinds.has(report_kind):
				errors.append("action.kind 必须来自当前汇报类型")
	elif action_type == "搭话":
		var target_resident_id := AgentContractIdentity._validate_resident_id(
			action,
			"target_resident_id",
			"action.target_resident_id",
			errors,
		)
		_validate_say_and_narration(action, "action", errors)
		_validate_photos(action, "action", AgentContractWake._available_photo_refs(wake_packet), errors, true)
		if (
			not target_resident_id.is_empty()
			and not AgentContractWake._wake_has_nearby_person(wake_packet, target_resident_id)
			and not _wake_has_interrogation_target(wake_packet, target_resident_id)
		):
			errors.append("action.target_resident_id 必须来自 snapshot.nearby")
	elif action_type == "答话":
		var conversation_id := AgentContract._require_non_empty_string(
			action,
			"conversation_id",
			"action.conversation_id",
			errors,
		)
		_validate_say_and_narration(action, "action", errors)
		_validate_photos(action, "action", AgentContractWake._available_photo_refs(wake_packet), errors, true)
		if not action.has("end"):
			errors.append("action.end 缺失")
		elif typeof(action["end"]) != TYPE_BOOL:
			errors.append("action.end 必须是布尔值")
		elif bool(action["end"]) and String(action.get("narration", "")).strip_edges().is_empty():
			errors.append("结束对话时 action.narration 必须说明结束行为")
		elif (
			bool(action["end"])
			and AgentContract.wake_requires_initial_invitation_reply(wake_packet)
			and String(action.get("say", "")).strip_edges().is_empty()
		):
			errors.append("拒绝搭话时 action.say 必须说明理由")
		if not conversation_id.is_empty() and conversation_id != AgentContractWake._current_conversation_id(wake_packet):
			errors.append("action.conversation_id 必须是当前对话编号")
		if action.has("traveler_affinity_delta"):
			var affinity_delta: Variant = action.get("traveler_affinity_delta")
			if typeof(affinity_delta) != TYPE_INT:
				errors.append("action.traveler_affinity_delta 必须是整数")
			elif int(affinity_delta) < -5 or int(affinity_delta) > 5:
				errors.append("action.traveler_affinity_delta 必须在 -5 到 5 之间")
		_validate_traveler_relationship_beat(action, wake_packet, errors)
		AgentContractMedical._validate_medical_response(action, wake_packet, errors)
	elif not action_type.is_empty() and not AgentContract.ACTION_TYPES.has(action_type):
		errors.append("action.type 不是合法动作类型")
	if AgentContract.ACTION_TYPES.has(action_type):
		_validate_action_environment_references(
			action,
			initialization,
			wake_packet,
			errors,
		)


static func _validate_traveler_relationship_beat(
	action: Dictionary,
	wake_packet: Dictionary,
	errors: Array[String],
) -> void:
	var snapshot_value: Variant = wake_packet.get("snapshot")
	if not snapshot_value is Dictionary:
		return
	var conversation_value: Variant = (snapshot_value as Dictionary).get("conversation")
	if not conversation_value is Dictionary:
		return
	var conversation := conversation_value as Dictionary
	var relationship_value: Variant = conversation.get("traveler_relationship")
	if not relationship_value is Dictionary:
		return
	var relationship := relationship_value as Dictionary
	var affinity := int(relationship.get("affinity", 50))
	if relationship.is_empty() or affinity < 53:
		return
	if not action.get("traveler_relationship_beat") is Dictionary:
		errors.append(
			"action.traveler_relationship_beat 缺失；正向关系答话必须标出关系表现句",
		)
		return
	var beat := action.get("traveler_relationship_beat") as Dictionary
	AgentContractIdentity._validate_allowed_fields(
		beat,
		["kind", "text"],
		"action.traveler_relationship_beat",
		errors,
	)
	var kind := AgentContract._require_non_empty_string(
		beat,
		"kind",
		"action.traveler_relationship_beat.kind",
		errors,
	)
	var beat_text := AgentContract._require_non_empty_string(
		beat,
		"text",
		"action.traveler_relationship_beat.text",
		errors,
	)
	if not kind.is_empty() and not _traveler_relationship_beat_kinds(affinity).has(kind):
		errors.append(
			"action.traveler_relationship_beat.kind 必须来自当前好感阶段允许值",
		)
	if beat_text.length() > 80:
		errors.append("action.traveler_relationship_beat.text 最多 80 字")
	elif not beat_text.is_empty() and not String(action.get("say", "")).contains(beat_text):
		errors.append(
			"action.traveler_relationship_beat.text 必须原样出现在 action.say 中",
		)


static func _traveler_relationship_beat_kinds(affinity: int) -> Array[String]:
	if affinity < 63:
		return ["personal_view", "reciprocal_question"]
	if affinity < 80:
		return ["old_topic", "practical_care", "personal_view"]
	if affinity < 90:
		return ["personal_feeling", "unfinished_concern", "private_worry"]
	return ["personal_stake", "safe_place", "shared_rapport"]


static func _validate_say_and_narration(
	data: Dictionary,
	path: String,
	errors: Array[String],
) -> void:
	var say := AgentContract._require_string(data, "say", "%s.say" % path, errors)
	var narration := AgentContract._require_string(data, "narration", "%s.narration" % path, errors)
	if say.strip_edges().is_empty() and narration.strip_edges().is_empty():
		errors.append("%s.say 和 %s.narration 至少一项必须是非空文本" % [path, path])


static func _validate_photos(
	data: Dictionary,
	path: String,
	available_refs: Dictionary,
	errors: Array[String],
	restrict_refs: bool,
) -> void:
	var photos := AgentContract._require_array(data, "photos", "%s.photos" % path, errors)
	for index in photos.size():
		var photo_path := "%s.photos[%d]" % [path, index]
		var value: Variant = photos[index]
		if typeof(value) != TYPE_DICTIONARY:
			errors.append("%s 必须是对象" % photo_path)
			continue
		var photo := value as Dictionary
		AgentContractIdentity._validate_allowed_fields(photo, ["ref", "mime_type"], photo_path, errors)
		var ref := AgentContract._require_non_empty_string(photo, "ref", "%s.ref" % photo_path, errors)
		AgentContract._require_non_empty_string(photo, "mime_type", "%s.mime_type" % photo_path, errors)
		if not ref.is_empty() and restrict_refs and not available_refs.has(ref):
			errors.append("%s.ref 不是本次输入中的有效照片引用" % photo_path)


## 审讯期警察远程提审: 搭话目标允许来自 wake 的 assembly.targets(可审候选),
## 不受 snapshot.nearby 感知范围限制(世界侧 prepare_talk_action 的
## interrogation_allowed 已豁免, 契约侧必须同步, 否则远程提审全被拒)。
static func _wake_has_interrogation_target(wake_packet: Dictionary, target_resident_id: String) -> bool:
	var assembly_value: Variant = (
		(wake_packet.get("snapshot", {}) as Dictionary).get("assembly", {})
	)
	if not assembly_value is Dictionary:
		return false
	var assembly := assembly_value as Dictionary
	if (
		String(assembly.get("phase", "")) != "interrogation"
		or String(assembly.get("role", "")) != "police"
	):
		return false
	for target_value: Variant in assembly.get("targets", []) as Array:
		if (
			target_value is Dictionary
			and String((target_value as Dictionary).get("resident_id", "")) == target_resident_id
		):
			return true
	return false


static func _validate_action_environment_references(
	action: Dictionary,
	initialization: Dictionary,
	wake_packet: Dictionary,
	errors: Array[String],
) -> void:
	var known_terms := _known_visible_feature_terms(initialization)
	if known_terms.is_empty():
		return
	var text_fields: Array[String] = []
	if action.has("line"):
		text_fields.append("line")
	if action.has("narration"):
		text_fields.append("narration")
	var action_type := String(action.get("type", ""))
	var snapshot := wake_packet.get("snapshot", {}) as Dictionary
	var current_place := (
		snapshot.get("place", {}) as Dictionary
	)
	var allowed_features := _features_for_place(
		initialization,
		String(current_place.get("name", "")),
	)
	for feature_value: Variant in allowed_features.keys():
		_allow_object_families_for_name(
			String(feature_value),
			known_terms,
			allowed_features,
		)
	for prop_value: Variant in current_place.get("props", []) as Array:
		if prop_value is Dictionary:
			var prop := prop_value as Dictionary
			_allow_object_families_for_name(
				String(prop.get("name", "")),
				known_terms,
				allowed_features,
			)
			if (
				action_type == "用道具"
				and String(prop.get("name", ""))
				== String(action.get("prop", ""))
			):
				for verb_value: Variant in prop.get("verbs", []) as Array:
					var verb := String(verb_value)
					if verb == String(action.get("verb", "")):
						_allow_object_families_for_name(
							verb,
							known_terms,
							allowed_features,
						)
						break
	for prop_value: Variant in current_place.get(
		"visible_props",
		[],
	) as Array:
		_allow_object_families_for_name(
			String(prop_value),
			known_terms,
			allowed_features,
		)
	if action_type == "去":
		_allow_work_task_target_families(
			snapshot.get("work_tasks", []) as Array,
			known_terms,
			allowed_features,
		)
	if action_type == "去":
		for feature: Variant in _features_for_place(
			initialization,
			String(action.get("place", "")),
		):
			allowed_features[String(feature)] = true
			_allow_object_families_for_name(
				String(feature),
				known_terms,
				allowed_features,
			)
	elif action_type == "用道具":
		_allow_object_families_for_name(
			String(action.get("prop", "")),
			known_terms,
			allowed_features,
		)
	elif action_type == "做活动":
		for activity_value: Variant in current_place.get(
			"activities",
			[],
		) as Array:
			if not activity_value is Dictionary:
				continue
			var activity := activity_value as Dictionary
			if (
				String(activity.get("activity_id", ""))
				!= String(action.get("activity_id", ""))
			):
				continue
			_allow_object_families_for_name(
				String(activity.get("label", "")),
				known_terms,
				allowed_features,
			)
			break
	for field_name in text_fields:
		var text := str(action.get(field_name, "")).strip_edges()
		if text.is_empty():
			continue
		for feature: Variant in known_terms:
			var feature_name := String(feature)
			if allowed_features.has(feature_name):
				continue
			for term_value: Variant in known_terms[feature] as Array:
				var term := String(term_value)
				if not term.is_empty() and text.contains(term):
					errors.append(
						"action.%s 提到了本轮动作不能使用的场景物件：%s"
						% [field_name, term]
					)
					break


static func _known_visible_feature_terms(
	initialization: Dictionary,
) -> Dictionary:
	var result := {}
	for place_value: Variant in initialization.get("places", []) as Array:
		if typeof(place_value) != TYPE_DICTIONARY:
			continue
		for feature_value: Variant in (
			(place_value as Dictionary).get("features", []) as Array
		):
			var feature := String(feature_value).strip_edges()
			if feature.is_empty():
				continue
			var terms: Array = [feature]
			for alias_value: Variant in (
				AgentContract.VISIBLE_FEATURE_ALIASES.get(feature, []) as Array
			):
				var alias := String(alias_value).strip_edges()
				if not alias.is_empty() and not terms.has(alias):
					terms.append(alias)
			result[feature] = terms
	for family_value: Variant in AgentContract.ENVIRONMENT_OBJECT_FAMILIES:
		var family := String(family_value)
		var terms := (
			AgentContract.ENVIRONMENT_OBJECT_FAMILIES[family_value] as Array
		).duplicate()
		result[family] = terms
	return result


static func _allow_object_families_for_name(
	name: String,
	known_terms: Dictionary,
	allowed: Dictionary,
) -> void:
	for feature_value: Variant in known_terms:
		var feature := String(feature_value)
		if name.contains(feature):
			allowed[feature] = true
			continue
		for term_value: Variant in known_terms[feature_value] as Array:
			var term := String(term_value)
			if not term.is_empty() and name.contains(term):
				allowed[feature] = true
				break


static func _allow_work_task_target_families(
	work_tasks: Array,
	known_terms: Dictionary,
	allowed: Dictionary,
) -> void:
	for task_value: Variant in work_tasks:
		if not task_value is Dictionary:
			continue
		for target_value: Variant in (task_value as Dictionary).get("targets", []) as Array:
			if not target_value is Dictionary:
				continue
			var target := target_value as Dictionary
			if String(target.get("kind", "")) != "prop":
				continue
			var target_ref := String(target.get("ref", "")).strip_edges()
			if target_ref.is_empty():
				continue
			for feature_value: Variant in known_terms:
				var feature := String(feature_value)
				if target_ref.contains(feature):
					allowed[feature] = true
					continue
				for term_value: Variant in known_terms[feature_value] as Array:
					if target_ref.contains(String(term_value)):
						allowed[feature] = true
						break


static func _features_for_place(
	initialization: Dictionary,
	place_name: String,
) -> Dictionary:
	var result := {}
	for place_value: Variant in initialization.get("places", []) as Array:
		if typeof(place_value) != TYPE_DICTIONARY:
			continue
		var place := place_value as Dictionary
		if String(place.get("name", "")) != place_name:
			continue
		for feature_value: Variant in place.get("features", []) as Array:
			var feature := String(feature_value).strip_edges()
			if not feature.is_empty():
				result[feature] = true
		break
	return result
