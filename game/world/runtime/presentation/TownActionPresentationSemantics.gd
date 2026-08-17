class_name TownActionPresentationSemantics
extends RefCounted


static func public_action(host, action: Dictionary) -> Dictionary:
	var result := {
		"action_id": String(action.get("action_id", "")),
		"type": String(action.get("type", "")),
		"line": String(action.get("line", host.ACTION_PROJECTION_MODULE.default_doing(host, action))),
		"startedAt": host.get_time(),
	}
	for key in [
		"target_resident_id",
		"recipient_resident_id",
		"content",
		"conversation_id",
		"say",
		"narration",
		"photos",
		"end",
		"prop",
		"verb",
		"dynamicPropId",
	]:
		if action.has(key):
			var value: Variant = action[key]
			result[key] = (
				value.duplicate(true)
				if value is Array or value is Dictionary
				else value
			)
	return result

# Stable World-owned semantic keys. UI assets are resolved separately by key.
const ACTIVITY_ICON_KEYS := {
	"activity_baker_bake_bread": "bake_bread",
	"activity_baker_prepare_dough": "prepare_dough",
	"activity_botanist_observe_plants": "observe_plants",
	"activity_botanist_record_plants": "record_plants",
	"activity_botanist_verify_sources": "verify_plant_sources",
	"activity_bulletin_publish": "publish_bulletin",
	"activity_bulletin_read": "read_bulletin",
	"activity_cafe_brew_coffee": "cafe_brew_coffee",
	"activity_cafe_eat_pastry": "eat_pastry",
	"activity_cafe_order": "place_order",
	"activity_cafe_receive_guests": "counter_service",
	"activity_cafe_rest": "cafe_rest",
	"activity_cafe_tidy_tables": "cafe_tidy_tables",
	"activity_clinic_consult": "clinic_consult",
	"activity_clinic_examination": "clinic_examination",
	"activity_clinic_prepare_medicine": "clinic_medicine",
	"activity_clinic_receive_patient": "clinic_consult",
	"activity_clinic_wait": "clinic_wait",
	"activity_dining_collect_meal": "collect_meal",
	"activity_dining_eat_meal": "eat_meal",
	"activity_dining_prepare_meal": "prepare_meal",
	"activity_dining_return_dishes": "return_dishes",
	"activity_dining_serve_meal": "counter_service",
	"activity_dining_wash_dishes": "wash_dishes",
	"activity_farm_tidy_tools": "tidy_garden_tools",
	"activity_farm_water_beds": "water_beds",
	"activity_fisher_catch_in_region": "catch_fish",
	"activity_fisher_count_catch": "count_catch",
	"activity_fisher_organize_gear": "organize_fishing_gear",
	"activity_flower_arrange_bouquets": "arrange_bouquets",
	"activity_flower_watch_stall": "counter_service",
	"activity_garden_bench_rest": "rest_outdoor_bench",
	"activity_garden_harvest_region": "harvest_garden",
	"activity_grocer_count_goods": "count_goods",
	"activity_grocer_tidy_stall": "counter_service",
	"activity_home_sleep": "sleep",
	"activity_library_checkout": "library_checkout",
	"activity_library_read": "read_book",
	"activity_library_research": "research",
	"activity_library_shelve_returns": "shelve_books",
	"activity_library_staff_checkout": "loan_records",
	"activity_library_write": "write",
	"activity_market_buy_fish": "buy_fish",
	"activity_market_buy_flowers": "buy_flowers",
	"activity_market_buy_general_goods": "buy_general_goods",
	"activity_musician_perform": "perform_music",
	"activity_musician_rehearse": "rehearse_music",
	"activity_postal_collect_outgoing_mail": "prepare_mailbag",
	"activity_postal_prepare_mailbag": "prepare_mailbag",
	"activity_postal_sort_mail": "sort_mail",
	"activity_river_bench_rest": "rest_outdoor_bench",
	"activity_town_hall_civic_service": "civic_service",
	"activity_town_hall_fill_form": "fill_form",
	"activity_town_hall_manage_records": "manage_archives",
	"activity_town_hall_meeting": "meeting",
	"activity_town_hall_process_paperwork": "paperwork",
	"activity_warehouse_check_cargo": "inspect_cargo",
	"activity_warehouse_check_manifest": "check_manifest",
	"activity_warehouse_move_cargo": "move_cargo",
	"activity_warehouse_organize_shelves": "organize_shelves",
	"activity_workshop_assemble_item": "assemble_item",
	"activity_workshop_craft_item": "craft_item",
	"activity_workshop_grind_parts": "grind_parts",
	"activity_workshop_handoff_repair": "handoff_repair",
	"activity_workshop_inspect_finished": "inspect_finished",
	"activity_workshop_take_lumber": "take_lumber",
}

const VERB_ICON_KEYS := {
	"书写示范": "calligraphy_demonstrate",
	"交接修理件": "handoff_repair",
	"借还书": "library_checkout",
	"做饭": "prepare_meal",
	"写作": "write",
	"整理笔记": "write",
	"自由书写": "write",
	"冲咖啡": "cafe_brew_coffee",
	"准备面团": "prepare_dough",
	"分拣信件": "sort_mail",
	"制作器物": "craft_item",
	"办事": "civic_service",
	"取用木料": "take_lumber",
	"取药": "clinic_medicine",
	"取餐": "collect_meal",
	"递餐": "collect_meal",
	"叫卖报纸": "sell_newspapers",
	"吃点心": "eat_pastry",
	"吃饭": "eat_meal",
	"填表": "fill_form",
	"处理文书": "paperwork",
	"张贴公告": "publish_bulletin",
	"归还书籍": "shelve_books",
	"归还餐具": "return_dishes",
	"打磨零件": "grind_parts",
	"接受检查": "clinic_examination",
	"接待客人": "counter_service",
	"接诊": "clinic_consult",
	"搬运货物": "move_cargo",
	"摸摸": "pet_animal",
	"整理借还": "loan_records",
	"整理园具": "tidy_garden_tools",
	"整理字帖": "tidy_copybooks",
	"整理投递袋": "prepare_mailbag",
	"整理报纸": "tidy_newspapers",
	"整理摊位": "tidy_stall",
	"整理桌椅": "cafe_tidy_tables",
	"整理渔具": "organize_fishing_gear",
	"整理渔网": "tidy_fishing_nets",
	"整理花束": "arrange_bouquets",
	"整理货架": "organize_shelves",
	"查档案": "manage_archives",
	"查看成品": "inspect_finished",
	"查资料": "research",
	"核对货单": "check_manifest",
	"检查货物": "inspect_cargo",
	"洗餐具": "wash_dishes",
	"浇灌花圃": "water_beds",
	"清点渔获": "count_catch",
	"清点货品": "count_goods",
	"演奏": "perform_music",
	"点单": "place_order",
	"烘烤面包": "bake_bread",
	"看诊": "clinic_consult",
	"看顾花摊": "counter_service",
	"睡觉": "sleep",
	"练习曲目": "rehearse_music",
	"组装器物": "assemble_item",
	"观察植物": "observe_plants",
	"议事": "meeting",
	"记录植物": "record_plants",
	"购买日用品": "buy_general_goods",
	"购买花束": "buy_flowers",
	"购买鲜鱼": "buy_fish",
	"阅读": "read_book",
	"阅读公告": "read_bulletin",
}

const SYSTEM_ICON_KEYS := {
	"去": "walk",
	"待着": "idle",
	"托人传话": "relay_message",
}


static func activity_icon_key(activity_id: String) -> String:
	return String(ACTIVITY_ICON_KEYS.get(activity_id.strip_edges(), ""))


static func verb_icon_key(
	verb: String,
	place_name := "",
	prop_name := "",
) -> String:
	var normalized_verb := verb.strip_edges()
	if normalized_verb == "歇着":
		var context := "%s %s" % [place_name, prop_name]
		if "诊所" in context or "候诊" in context:
			return "clinic_wait"
		if "咖啡" in context:
			return "cafe_rest"
		return "rest_outdoor_bench"
	return String(VERB_ICON_KEYS.get(normalized_verb, ""))


static func system_icon_key(action_type: String, action: Dictionary = {}) -> String:
	var normalized_type := action_type.strip_edges()
	if normalized_type == "调整营业":
		return "business_open" if bool(action.get("open", false)) else "business_close"
	return String(SYSTEM_ICON_KEYS.get(normalized_type, ""))


static func system_label(action_type: String, action: Dictionary = {}) -> String:
	match action_type.strip_edges():
		"去":
			var place := String(action.get("place", "")).strip_edges()
			return "前往%s" % place if not place.is_empty() else "前往目的地"
		"待着":
			var line := String(action.get("line", "")).strip_edges()
			return line if not line.is_empty() else "在这里歇一会儿"
		"托人传话":
			return "托人传话"
		"调整营业":
			return "开门营业" if bool(action.get("open", false)) else "停止营业"
	return ""


# ---- 以下为居民动作/活动的表现投影(自 TownWorldRuntime 下沉) ----
# UI 文案与提示计算属于表现层;world 为世界运行时实例,活动执行态与
# 环境时间经 world 访问，提示缓存由地点表现查询组件持有。

static func _resident_public_current_action(world, resident: Dictionary) -> Variant:
	if world.CONVERSATION_RUNTIME._resident_has_suspended_conversation(world, resident):
		var conversation : Variant = world.CONVERSATION_RUNTIME._active_conversation_for_person(world,
			String(resident.get("residentId", "")),
		)
		var conversation_action_prefix := (
			"player-conversation"
			if world.CONVERSATION_RUNTIME._is_player_initiated_conversation(world, conversation)
			else "conversation"
		)
		return {
			"action_id": "%s:%s" % [conversation_action_prefix, String(
				conversation.get("conversationId", ""),
			)],
			"type": "答话",
		}
	return world.ACTION_PROJECTION_MODULE.public_current_action(
		resident.get("currentAction", {}) as Dictionary,
	)


static func _agent_current_action(world, action: Dictionary) -> Variant:
	if bool(action.get("decisionBridge", false)):
		return null
	var projected: Variant = world.ACTION_PROJECTION_MODULE.public_current_action(action)
	if (
		projected is Dictionary
		and String((projected as Dictionary).get("type", ""))
		== "activity.perform"
	):
		return null
	return projected


static func _cached_presentation_cue(
	world,
	place_name: String,
	prop_name: String,
	verb: String,
) -> Dictionary:
	return world.place_presentation_query.presentation_cue(
		world.PROP_ACTION_PREPARER.query_data(world),
		place_name,
		prop_name,
		verb,
	)


static func _resident_activity_cue(world, resident: Dictionary) -> Variant:
	if world.CONVERSATION_RUNTIME._resident_has_suspended_conversation(world, resident):
		return _resident_conversation_activity_cue(world,
			resident,
			"答话",
		)
	var action := resident.get("currentAction", {}) as Dictionary
	var action_type := String(action.get("type", ""))
	if action_type in ["搭话", "答话"]:
		return _resident_conversation_activity_cue(world,
			resident,
			action_type,
		)
	if action_type != "用道具":
		return null
	var execution := world._activity_runtime.execution_for_action(
		String(resident.get("residentId", "")),
		String(action.get("action_id", "")),
	) as Dictionary
	if not execution.is_empty():
		var activity_absolute_minute := int(
			world._environment.get_absolute_minute()
		)
		var activity_elapsed := maxi(
			0,
			activity_absolute_minute - int(
				action.get(
					"startedAbsoluteMinute",
					activity_absolute_minute,
				)
			),
		)
		var activity_cue := _cached_presentation_cue(world,
			String(execution.get("placeId", "")),
			String(execution.get("targetPropName", "")),
			String(execution.get("targetActionVerb", "")),
		)
		activity_cue["kind"] = "activity"
		activity_cue["label"] = String(
			execution.get("activityLabel", "")
		)
		var activity_semantic := world._activity_runtime.presentation_semantic_for_activity(
			String(execution.get("activityId", "")),
		) as Dictionary
		for field in [
			"activityKind",
			"poseFamily",
			"semanticIconType",
			"baseIconKey",
		]:
			if activity_semantic.has(field):
				activity_cue[field] = activity_semantic[field]
		activity_cue["sourceActivityId"] = String(
			execution.get("activityId", "")
		)
		activity_cue["phase"] = (
			"performing"
				if activity_elapsed
				>= world.ACTION_SUPPORT.prop_approach_duration_minutes(world, action)
				else "approaching"
		)
		return activity_cue
	var cue := _cached_presentation_cue(world,
		String(action.get("sourcePlace", resident.get("currentPlace", ""))),
		String(action.get("prop", "")),
		String(action.get("verb", "")),
	)
	if cue.is_empty():
		return null
	cue["baseIconKey"] = world.ACTION_PRESENTATION.verb_icon_key(
		String(action.get("verb", "")),
		String(action.get("sourcePlace", resident.get("currentPlace", ""))),
		String(action.get("prop", "")),
	)
	cue["label"] = String(action.get("verb", "")).strip_edges()
	var absolute_minute := int(world._environment.get_absolute_minute())
	var elapsed := maxi(
		0,
		absolute_minute - int(action.get("startedAbsoluteMinute", absolute_minute)),
	)
	cue["phase"] = (
		"performing"
		if elapsed >= world.ACTION_SUPPORT.prop_approach_duration_minutes(world, action)
		else "approaching"
	)
	return cue


static func _resident_action_presentation(
	world,
	resident: Dictionary,
	activity_cue_value: Variant,
) -> Variant:
	if world.CONVERSATION_RUNTIME._resident_has_suspended_conversation(world, resident):
		return null
	var action := resident.get("currentAction", {}) as Dictionary
	var action_type := String(action.get("type", "")).strip_edges()
	if action_type in ["搭话", "答话"]:
		return null
	var cue := (
		activity_cue_value as Dictionary
		if activity_cue_value is Dictionary
		else {}
	)
	var base_icon_key := String(cue.get("baseIconKey", "")).strip_edges()
	var phase := String(cue.get("phase", "")).strip_edges()
	var label := String(cue.get("label", cue.get("verb", ""))).strip_edges()
	var wait_reason := ""
	if base_icon_key.is_empty() and not action.is_empty():
		base_icon_key = world.ACTION_PRESENTATION.system_icon_key(action_type, action)
		label = world.ACTION_PRESENTATION.system_label(action_type, action)
		match action_type:
			"去":
				phase = "approaching"
			"待着":
				phase = "waiting"
				wait_reason = "idle"
			_:
				phase = "performing"
	if base_icon_key.is_empty() or phase.is_empty():
		return null
	var source_action_id := String(
		action.get("sourceActionId", action.get("action_id", ""))
	).strip_edges()
	return {
		"baseIconKey": base_icon_key,
		"phase": phase,
		"label": label,
		"publicThought": _public_surface_thought(world, action),
		"waitReason": wait_reason,
		"sourceActionId": source_action_id,
		"sourceActivityId": String(
			cue.get("sourceActivityId", action.get("activityId", ""))
		).strip_edges(),
		"visibleSpaceId": String(resident.get("spaceId", "")),
		"confirmedRevision": world._world_revision,
	}


static func _resident_conversation_activity_cue(
	world,
	resident: Dictionary,
	action_type: String,
) -> Variant:
	var conversation_value: Variant = resident.get("conversation")
	if conversation_value is not Dictionary:
		return null
	var conversation := conversation_value as Dictionary
	var other_id := String(
		conversation.get("with_resident_id", "")
	)
	var other : Variant = world._person_state(other_id)
	if other.is_empty():
		return null
	var offset := (
		other.get("position", Vector2.ZERO) as Vector2
		- resident.get("position", Vector2.ZERO) as Vector2
	)
	var facing := ""
	if offset.length_squared() > 0.001:
		if absf(offset.x) > absf(offset.y):
			facing = "right" if offset.x > 0.0 else "left"
		else:
			facing = "down" if offset.y > 0.0 else "up"
	var resident_id := String(resident.get("residentId", ""))
	var turns := conversation.get("turns", []) as Array
	var last_speaker_id := ""
	if not turns.is_empty():
		last_speaker_id = String(
			(turns[-1] as Dictionary).get("speaker_resident_id", "")
		)
	return {
		"actionType": action_type,
		"phase": "performing",
		"actorFacing": facing,
		"socialRole": (
			"speaking"
			if last_speaker_id == resident_id
			else "listening"
		),
		"withResidentId": other_id,
	}


static func _resident_action_phase_projection(world, resident: Dictionary) -> Dictionary:
	var resident_id := String(resident.get("residentId", ""))
	var current_action := resident.get("currentAction", {}) as Dictionary
	var preview := resident.get("confirmedActionPreview", {}) as Dictionary
	var result := {
		"residentId": resident_id,
		"phase": "idle",
		"previewId": "",
		"decisionId": "",
		"actionId": "",
		"summary": "",
		"publicThought": "",
		"baseIconKey": "",
		"label": "",
		"sourceActivityId": "",
		"waitReason": "",
		"visibleSpaceId": String(resident.get("spaceId", "")),
		"confirmedRevision": 0,
		"confirmedAt": null,
		"displaySeconds": 0.0,
		"holdSeconds": 0.0,
		"remainingSeconds": 0.0,
		"worldRevision": world._world_revision,
	}
	if world.CONVERSATION_RUNTIME._resident_has_suspended_conversation(world, resident):
		var conversation : Variant = world.CONVERSATION_RUNTIME._active_conversation_for_person(world, resident_id)
		result["phase"] = "executing"
		var conversation_action_prefix := (
			"player-conversation"
			if world.CONVERSATION_RUNTIME._is_player_initiated_conversation(world, conversation)
			else "conversation"
		)
		result["actionId"] = "%s:%s" % [conversation_action_prefix, String(
			conversation.get("conversationId", ""),
		)]
		return result
	if bool(resident.get("decisionPending", false)):
		# Agent latency is not exposed as a waiting presentation. A confirmed action
		# keeps executing; otherwise the resident gets a local ambient presentation.
		result["phase"] = "executing"
		result["decisionId"] = String(resident.get("validDecisionId", ""))
		result["actionId"] = String(
			current_action.get(
				"action_id",
				"ambient-decision:%s" % String(resident.get("validDecisionId", "")),
			)
		)
		if current_action.is_empty():
			result["baseIconKey"] = "idle"
			result["label"] = _pending_decision_label(resident)
			result["publicThought"] = _pending_decision_thought(resident)
		return result
	if not preview.is_empty():
		result["phase"] = "executing_preview"
		result["previewId"] = String(preview.get("previewId", ""))
		result["decisionId"] = String(preview.get("decisionId", ""))
		result["actionId"] = String(preview.get("actionId", ""))
		result["summary"] = String(preview.get("summary", ""))
		result["publicThought"] = String(
			preview.get(
				"publicThought",
				_public_surface_thought(world,
					preview.get("action", {}) as Dictionary
				),
			)
		).strip_edges()
		result["confirmedRevision"] = int(preview.get("confirmedRevision", 0))
		result["confirmedAt"] = (
			preview.get("confirmedAt", {}) as Dictionary
		).duplicate(true)
		result["holdSeconds"] = float(
			preview.get("holdSeconds", world.CONFIRMED_ACTION_PREVIEW_SECONDS),
		)
		result["displaySeconds"] = float(
			preview.get(
				"displaySeconds",
				preview.get(
					"holdSeconds",
					world.CONFIRMED_ACTION_PREVIEW_SECONDS,
				),
			),
		)
		result["remainingSeconds"] = maxf(
			0.0,
			float(preview.get("remainingSeconds", 0.0)),
		)
		var preview_presentation := _preview_action_presentation(world,
			resident,
			preview,
		)
		for field: String in [
			"baseIconKey",
			"label",
			"sourceActivityId",
			"waitReason",
			"visibleSpaceId",
		]:
			if preview_presentation.has(field):
				result[field] = preview_presentation[field]
		return result
	if not current_action.is_empty():
		result["phase"] = "executing"
		result["actionId"] = String(current_action.get("action_id", ""))
	return result


static func _pending_decision_label(resident: Dictionary) -> String:
	var doing := String(resident.get("doing", "")).strip_edges()
	if doing.contains("对方已经答话"):
		return "想想怎么回应"
	if doing.contains("对话"):
		return "整理一下话头"
	var place := String(resident.get("currentPlace", "")).strip_edges()
	if not place.is_empty():
		return "在%s看看周围" % place
	return "在这里缓一缓"


static func _pending_decision_thought(resident: Dictionary) -> String:
	var doing := String(resident.get("doing", "")).strip_edges()
	if doing.contains("对方已经答话"):
		return "琢磨一下该怎么接话。"
	if doing.contains("对话"):
		return "把刚才的话在心里过一遍。"
	return "先看看周围，再决定接下来做什么。"


static func _preview_action_presentation(
	world,
	resident: Dictionary,
	preview: Dictionary,
) -> Dictionary:
	var action := preview.get("action", {}) as Dictionary
	var action_type := String(action.get("type", "")).strip_edges()
	var base_icon_key := ""
	var label := ""
	var source_activity_id := ""
	if action_type == "做活动":
		source_activity_id = String(
			action.get("activity_id", action.get("activityId", ""))
		).strip_edges()
		var semantic := world._activity_runtime.presentation_semantic_for_activity(
			source_activity_id,
		) as Dictionary
		base_icon_key = String(semantic.get("baseIconKey", "")).strip_edges()
		label = String(semantic.get("label", "")).strip_edges()
	elif action_type == "用道具":
		label = String(action.get("verb", "")).strip_edges()
		base_icon_key = world.ACTION_PRESENTATION.verb_icon_key(
			label,
			String(resident.get("currentPlace", "")),
			String(action.get("prop", "")),
		)
	else:
		base_icon_key = world.ACTION_PRESENTATION.system_icon_key(action_type, action)
		label = world.ACTION_PRESENTATION.system_label(action_type, action)
	if base_icon_key.is_empty():
		return {}
	return {
		"baseIconKey": base_icon_key,
		"label": label,
		"publicThought": _public_surface_thought(world, action),
		"sourceActivityId": source_activity_id,
		"waitReason": "",
		"visibleSpaceId": String(resident.get("spaceId", "")),
	}


static func _action_preview_summary(world, action: Dictionary, continuing: bool) -> String:
	var summary : Variant = world.ACTION_PROJECTION_MODULE.default_doing(world, action)
	if continuing:
		summary = "继续%s" % summary
	if summary.length() > 48:
		summary = "%s…" % summary.substr(0, 47)
	return summary


static func _public_surface_thought(world, action: Dictionary) -> String:
	if String(action.get("type", "")) in ["搭话", "答话"]:
		return ""
	var thought := String(action.get("line", "")).strip_edges()
	for separator in ["\r", "\n", "\t"]:
		thought = thought.replace(separator, " ")
	while thought.contains("  "):
		thought = thought.replace("  ", " ")
	if thought.length() > world.PUBLIC_THOUGHT_MAX_LENGTH:
		thought = thought.substr(0, world.PUBLIC_THOUGHT_MAX_LENGTH)
	return thought


static func _conversation_doing(world, action: Dictionary) -> String:
	var narration := String(action.get("narration", "")).strip_edges()
	if not narration.is_empty():
		return narration
	var say := String(action.get("say", "")).strip_edges()
	return say if not say.is_empty() else "正在交谈"
