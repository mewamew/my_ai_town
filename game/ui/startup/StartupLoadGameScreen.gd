class_name StartupLoadGameScreen
extends Control


signal intent_requested(intent: StringName, payload: Dictionary)
signal action_blocked(intent: StringName, reason: String)


const BUTTON_THEME := preload("res://ui/startup/StartupButtonImageTheme.gd")
const UiViewModel := preload("res://ui/common/AiTownUiViewModel.gd")
const UiNodeRetirement := preload("res://ui/common/AiTownUiNodeRetirement.gd")
const LOAD_GAME_IMAGE_THEME := preload(
	"res://ui/startup/StartupLoadGameImageTheme.gd"
)
const REFERENCE_VIEWPORT := Vector2(1920.0, 1080.0)
const VISUAL_ATLAS_SIZE := Vector2(1672.0, 941.0)
const LOAD_MODE := "load"
const OVERWRITE_SELECTION_MODE := "overwrite_selection"
const BACK_INTENT := "startup.close_load_game"
const CONTINUE_SLOT_INTENT := "session.continue_slot"
const SELECT_OVERWRITE_SLOT_INTENT := "startup.select_overwrite_slot"
const REQUEST_DELETE_SLOT_INTENT := "save.request_delete_slot"
const VISUAL_STATE_HEALTHY := "healthy"
const VISUAL_STATE_RECOVERABLE := "recoverable"
const VISUAL_STATE_DISABLED := "disabled"
const HEALTHY_ACCENT_REGION := Rect2(446.0, 274.0, 51.0, 142.0)
const RECOVERABLE_ACCENT_REGION := Rect2(446.0, 433.0, 51.0, 142.0)
const DISABLED_ACCENT_REGION := Rect2(446.0, 592.0, 51.0, 142.0)
const VALID_SLOT_STATES: Array[String] = [
	"empty",
	"healthy",
	"recoverable",
	"incomplete",
	"corrupt",
	# Keep the old projection name readable while all callers migrate to
	# TownStartupSaveCatalog's `healthy` state.
	"complete",
]
const OLDER_REVISION_SELECTION_DISABLED_REASON := (
	"STARTUP_OLDER_REVISION_SELECTION_NOT_AVAILABLE"
)
const LOAD_GAME_VISUAL_ASSET_PATH := (
	"res://assets/ui/startup/final/load_game/"
	+ "load_game_open_paper_1672x941.png"
)

var _view_model: Dictionary = {}
var _revision := -1
var _slot_layer: Control
var _title: Label
var _subtitle: Label
var _feedback: Label
var _back_button: Button
var _visual_atlas_texture: Texture2D
var _delete_icon_texture: AtlasTexture


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = LOAD_GAME_IMAGE_THEME.create()
	_build_interface()
	if not _view_model.is_empty():
		_render()


func deactivate_modal_ownership() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_unhandled_input(false)
	hide()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed(&"ui_cancel") or (
		event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE
	):
		if request_back():
			get_viewport().set_input_as_handled()


func apply_view_model(view_model: Dictionary) -> bool:
	var issues := _validate_view_model(view_model)
	if not issues.is_empty():
		for issue: String in issues:
			push_error(issue)
		return false
	var incoming_revision := int(view_model.get("revision", -1))
	if _revision >= 0 and incoming_revision < _revision:
		return false
	_view_model = view_model.duplicate(true)
	_revision = incoming_revision
	if is_node_ready():
		_render()
	return true


func get_contract_snapshot() -> Dictionary:
	var data := _view_model.get("data", {}) as Dictionary
	return {
		"scope": String(_view_model.get("scope", "")),
		"revision": _revision,
		"mode": String(data.get("mode", "")),
		"providerIndependent": bool(data.get("providerIndependent", false)),
		"slotCount": (data.get("slots", []) as Array).size(),
		"buttonThemeRevision": LOAD_GAME_IMAGE_THEME.REVISION,
		"baseButtonThemeRevision": BUTTON_THEME.REVISION,
		"usesStartupGlobalFont": true,
		"globalFontPath": BUTTON_THEME.FONT_PATH,
		"usesImageButtonStates": true,
		"usesApprovedFullPageImageAtlas": true,
		"usesProgrammaticFrame": false,
		"slotVisualStateManagement": true,
		"slotVisualFamilies": {
			"healthy": VISUAL_STATE_HEALTHY,
			"recoverable": VISUAL_STATE_RECOVERABLE,
			"empty": VISUAL_STATE_DISABLED,
			"incomplete": VISUAL_STATE_DISABLED,
			"corrupt": VISUAL_STATE_DISABLED,
		},
		"olderRevisionSelectionEnabled": false,
		"olderRevisionSelectionDisabledReason": (
			OLDER_REVISION_SELECTION_DISABLED_REASON
		),
		"supportedModes": [LOAD_MODE, OVERWRITE_SELECTION_MODE],
		"allowedActions": {
			"back": BACK_INTENT,
			"continueSlot": CONTINUE_SLOT_INTENT,
			"selectOverwriteSlot": SELECT_OVERWRITE_SLOT_INTENT,
			"deleteSlot": REQUEST_DELETE_SLOT_INTENT,
		},
		"ownsOverwriteSelection": true,
		"ownsOverwriteConfirmation": false,
		"ownsRecoveryConfirmation": false,
		"ownsDeleteConfirmation": false,
		"recoveryHandoffIntent": "session.continue_slot",
		"functionalStatus": "functional_runtime_ready",
		"runtimeVisualRole": "formal_image_asset_runtime",
		"formalRuntimeVisualConnected": true,
		"hostMounted": true,
		"visualAssetPreviousStatus": "v1_runtime_user_feedback_received",
		"visualAssetStatus": "user_visual_approved",
		"runtimeVisualStatus": "user_visual_approved",
		"visualAssetPath": LOAD_GAME_VISUAL_ASSET_PATH,
		"visualApprovalStatus": "user_visual_approved",
	}


func debug_request_slot(slot_id: String) -> bool:
	for slot_value: Variant in (
		(_view_model.get("data", {}) as Dictionary).get("slots", []) as Array
	):
		if (
			slot_value is Dictionary
			and String((slot_value as Dictionary).get("slotId", "")) == slot_id
		):
			return _request_slot(slot_value as Dictionary)
	return _block(_slot_action_intent(), "STARTUP_SAVE_SLOT_ID_INVALID")


func debug_request_delete_slot(slot_id: String) -> bool:
	for slot_value: Variant in (
		(_view_model.get("data", {}) as Dictionary).get("slots", []) as Array
	):
		if (
			slot_value is Dictionary
			and String((slot_value as Dictionary).get("slotId", "")) == slot_id
		):
			return _request_delete_slot(slot_value as Dictionary)
	return _block(&"save.request_delete_slot", "STARTUP_SAVE_SLOT_ID_INVALID")


func _validate_view_model(view_model: Dictionary) -> PackedStringArray:
	var issues := PackedStringArray()
	if String(view_model.get("scope", "")) != "save":
		issues.append("加载游戏页 scope 必须为 save。")
	if int(view_model.get("revision", -1)) < 0:
		issues.append("加载游戏页 revision 无效。")
	var data := view_model.get("data", {}) as Dictionary
	var mode := String(data.get("mode", ""))
	if not mode in [LOAD_MODE, OVERWRITE_SELECTION_MODE]:
		issues.append("加载游戏页 mode 必须为 load 或 overwrite_selection。")
	if not bool(data.get("providerIndependent", false)):
		issues.append("加载游戏页必须声明 Provider 独立浏览。")
	if not data.get("slots", []) is Array:
		issues.append("加载游戏页 slots 必须为 Array。")
	else:
		var slot_ids: Array[String] = []
		for slot_value: Variant in data.get("slots", []) as Array:
			if not slot_value is Dictionary:
				issues.append("加载游戏页 slot 必须为 Dictionary。")
				continue
			var slot := slot_value as Dictionary
			var slot_id := String(slot.get("slotId", "")).strip_edges()
			var state := String(slot.get("state", ""))
			if slot_id.is_empty() or slot_ids.has(slot_id):
				issues.append("加载游戏页 slotId 缺失或重复。")
			else:
				slot_ids.append(slot_id)
			if not state in VALID_SLOT_STATES:
				issues.append("加载游戏页 slot state 无效：%s。" % state)
	var actions := view_model.get("actions", {}) as Dictionary
	var expected_intents := {"back": BACK_INTENT}
	if mode == OVERWRITE_SELECTION_MODE:
		expected_intents["selectOverwriteSlot"] = SELECT_OVERWRITE_SLOT_INTENT
	else:
		expected_intents["continueSlot"] = CONTINUE_SLOT_INTENT
		expected_intents["deleteSlot"] = REQUEST_DELETE_SLOT_INTENT
	for action_key: String in expected_intents:
		var action_value: Variant = actions.get(action_key)
		if not action_value is Dictionary:
			issues.append("加载游戏页 actions 缺少 %s。" % action_key)
			continue
		var action := action_value as Dictionary
		var expected_intent := String(expected_intents.get(action_key, ""))
		if String(action.get("intent", "")) != expected_intent:
			issues.append(
				"加载游戏页 action %s 的 intent 必须为 %s。" % [
					action_key,
					expected_intent,
				],
			)
	return issues


func _build_interface() -> void:
	_visual_atlas_texture = _load_texture(LOAD_GAME_VISUAL_ASSET_PATH)
	_delete_icon_texture = _cropped_texture(
		_load_texture(LOAD_GAME_IMAGE_THEME.DELETE_ICON_PATH),
		Rect2(32.0, 24.0, 64.0, 80.0),
	)
	var visual_atlas := TextureRect.new()
	visual_atlas.name = "LoadGameApprovedVisualAtlas"
	visual_atlas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visual_atlas.texture = _visual_atlas_texture
	visual_atlas.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	visual_atlas.stretch_mode = TextureRect.STRETCH_SCALE
	visual_atlas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visual_atlas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(visual_atlas)

	_title = _label(
		"LoadGameTitle",
		_source_rect(Rect2(485.0, 108.0, 700.0, 90.0)),
		&"StartupLoadTitle",
	)
	_title.add_theme_font_size_override(&"font_size", 54)
	_subtitle = _label(
		"LoadGameSubtitle",
		_source_rect(Rect2(470.0, 216.0, 735.0, 42.0)),
		&"StartupLoadSubtitle",
	)
	_subtitle.add_theme_font_size_override(&"font_size", 26)
	_subtitle.add_theme_color_override(&"font_color", Color("4e3826"))
	_back_button = _button(
		"LoadGameBackButton",
		"返回",
		_source_rect(LOAD_GAME_IMAGE_THEME.BACK_ACTION_REGION),
		&"StartupLoadBackAction",
		_request_back,
	)
	_slot_layer = Control.new()
	_slot_layer.name = "LoadGameSlots"
	_slot_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slot_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slot_layer)
	_feedback = _label(
		"LoadGameFeedback",
		_source_rect(Rect2(642.0, 770.0, 615.0, 72.0)),
		&"StartupLoadSubtitle",
	)
	_feedback.add_theme_font_size_override(&"font_size", 28)
	_feedback.add_theme_color_override(&"font_color", Color("4e3826"))


func _render() -> void:
	var focus_identity := _capture_focus_identity()
	var data := _view_model.get("data", {}) as Dictionary
	var overwrite_selection := _is_overwrite_selection_mode()
	var in_session := bool(data.get("inSession", false))
	_title.text = String(data.get(
		"pageTitle",
		"选择要覆盖的小镇" if overwrite_selection else "加载游戏",
	))
	_subtitle.text = (
		"选择一个已有存档；下一步仍需确认覆盖。"
		if overwrite_selection
		else "选择后会先保存当前小镇，再加载目标存档。"
		if in_session
		else "本地存档可直接浏览；进入小镇前会检查全部居民连接。"
	)
	var back_action := _action("back")
	_back_button.disabled = not bool(back_action.get("enabled", false))
	_back_button.tooltip_text = (
		"返回"
		if not _back_button.disabled
		else UiViewModel.player_reason(
			String(back_action.get("disabledReason", "ACTION_NOT_AVAILABLE"))
		)
	)
	UiNodeRetirement.retire_children(_slot_layer)
	var slots := data.get("slots", []) as Array
	for index in range(slots.size()):
		var value: Variant = slots[index]
		if value is Dictionary:
			_build_slot_card(index, value as Dictionary)
	var error: Variant = _view_model.get("error", null)
	_feedback.text = (
		String((error as Dictionary).get("message", "本地存档暂不可用。"))
		if error is Dictionary
		else (
			"选择后仍会再次确认，不会立即覆盖存档。"
			if overwrite_selection
			else "当前小镇保存成功后，才会切换到所选存档。"
			if in_session
			else "选择其他小镇不会改变当前存档。"
		)
	)
	_restore_focus_identity(focus_identity)


func _capture_focus_identity() -> String:
	if not is_inside_tree():
		return ""
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner == _back_button:
		return "back"
	if (
		is_instance_valid(focus_owner)
		and is_instance_valid(_slot_layer)
		and _slot_layer.is_ancestor_of(focus_owner)
	):
		return String(focus_owner.name)
	return ""


func _restore_focus_identity(focus_identity: String) -> void:
	if focus_identity == "back":
		_back_button.call_deferred("grab_focus")
		return
	if not focus_identity.is_empty():
		var target := _slot_layer.find_child(
			focus_identity,
			false,
			false,
		) as Button
		if target != null and not target.disabled:
			target.call_deferred("grab_focus")
			return
	_focus_first_available()


func _build_slot_card(index: int, slot: Dictionary) -> void:
	var source_y := 283.0 + float(index) * 159.0
	var slot_id := String(slot.get("slotId", ""))
	var display_name := String(slot.get("displayName", slot_id))
	var state := String(slot.get("state", "empty"))
	var visual_family := _slot_visual_family(slot)
	var accent := TextureRect.new()
	accent.name = "%sStateAccent" % slot_id
	_apply_reference_rect(
		accent,
		_source_rect(Rect2(446.0, 274.0 + float(index) * 159.0, 51.0, 142.0)),
	)
	accent.texture = _atlas_texture(_state_accent_region(visual_family))
	accent.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	accent.stretch_mode = TextureRect.STRETCH_SCALE
	accent.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	accent.set_meta("visual_state_family", visual_family)
	_slot_layer.add_child(accent)
	var title := _label(
		"%sTitle" % slot_id,
		_source_rect(Rect2(512.0, source_y, 492.0, 31.0)),
		&"StartupLoadSlotTitle",
		_slot_layer,
	)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.add_theme_font_size_override(&"font_size", 28)
	title.text = "%s · %s" % [display_name, _state_copy(state)]

	var body := _label(
		"%sBody" % slot_id,
		_source_rect(Rect2(512.0, source_y + 32.0, 492.0, 31.0)),
		&"StartupLoadSlotBody",
		_slot_layer,
	)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	body.add_theme_font_size_override(&"font_size", 22)
	body.add_theme_color_override(&"font_color", Color("4e3826"))
	body.text = _slot_body(slot)
	var recovery := _label(
		"%sRecovery" % slot_id,
		_source_rect(Rect2(512.0, source_y + 64.0, 492.0, 31.0)),
		&"StartupLoadSlotDamage",
		_slot_layer,
	)
	recovery.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	recovery.add_theme_font_size_override(&"font_size", 22)
	if state in ["healthy", "complete", "empty"]:
		recovery.add_theme_color_override(&"font_color", Color("4e3826"))
	recovery.text = _recovery_copy(slot)
	recovery.tooltip_text = _damage_detail_copy(slot)
	var detail := _label(
		"%sDetail" % slot_id,
		_source_rect(Rect2(512.0, source_y + 96.0, 492.0, 31.0)),
		&"StartupLoadSlotBody",
		_slot_layer,
	)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	detail.add_theme_font_size_override(&"font_size", 22)
	detail.add_theme_color_override(&"font_color", Color("4e3826"))
	detail.text = _slot_detail_copy(slot)
	detail.tooltip_text = _damage_detail_copy(slot)

	var action_key := (
		"selectOverwriteSlot"
		if _is_overwrite_selection_mode()
		else "continueSlot"
	)
	var action_contract := _action(action_key)
	var action_text := (
		"选择覆盖"
		if _is_overwrite_selection_mode()
		else _slot_action_copy(slot)
	)
	var action_variation := (
		&"StartupLoadRecoverableAction"
		if visual_family == VISUAL_STATE_RECOVERABLE
		else &"StartupLoadHealthyAction"
	)
	var primary_action_rect := (
		Rect2(1044.0, 311.0 + float(index) * 159.0, 162.0, 79.0)
		if not _is_overwrite_selection_mode()
		else Rect2(1044.0, 311.0 + float(index) * 159.0, 162.0, 79.0)
	)
	var action := _button(
		"%sAction" % slot_id,
		action_text,
		_source_rect(primary_action_rect),
		action_variation,
		_request_slot.bind(slot.duplicate(true)),
		_slot_layer,
	)
	action.set_meta("slot_id", slot_id)
	action.set_meta("visual_state_family", visual_family)
	action.disabled = (
		not bool(action_contract.get("enabled", false))
		or state == "empty"
		or (
			not bool(slot.get("continueAvailable", false))
			and not bool(slot.get("diagnosticAvailable", false))
		)
	)
	action.tooltip_text = (
		UiViewModel.player_reason(
			String(
				action_contract.get(
					"disabledReason",
					"ACTION_NOT_AVAILABLE",
				)
			)
		)
		if not bool(action_contract.get("enabled", false))
		else _damage_detail_copy(slot)
		if action.disabled or state == "recoverable"
		else action_text
	)
	if not _is_overwrite_selection_mode():
		var delete_contract := _action("deleteSlot")
		var delete_button := _button(
			"%sDeleteAction" % slot_id,
			"",
			_source_rect(Rect2(
				1228.0,
				322.0 + float(index) * 159.0,
				60.0,
				58.0,
			)),
			&"StartupLoadDeleteBadgeAction",
			_request_delete_slot.bind(slot.duplicate(true)),
			_slot_layer,
		)
		delete_button.icon = _delete_icon_texture
		delete_button.expand_icon = true
		delete_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		delete_button.set_meta("slot_id", slot_id)
		delete_button.set_meta("action_key", "deleteSlot")
		delete_button.disabled = (
			not bool(delete_contract.get("enabled", false))
			or state == "empty"
		)
		delete_button.tooltip_text = (
			"删除前会再次确认"
			if not delete_button.disabled
			else UiViewModel.player_reason(
				String(delete_contract.get(
					"disabledReason",
					"SESSION_SAVE_NO_PUBLISHED_REVISION",
				))
			)
		)


func _slot_body(slot: Dictionary) -> String:
	var state := String(slot.get("state", "empty"))
	if state == "empty":
		return "尚未创建小镇"
	if state == "incomplete" and not bool(slot.get("continueAvailable", false)):
		return "尚无可用的完整保存"
	if state == "corrupt" and not bool(slot.get("continueAvailable", false)):
		return "无法读取可进入的小镇存档"
	if state == "recoverable":
		var damage := slot.get("damageDetails", {}) as Dictionary
		return "完整修订 %d · %s · World %d" % [
			int(damage.get("fallbackSaveRevision", slot.get("saveRevision", 0))),
			_full_saved_at(String(
				damage.get("fallbackSavedAt", slot.get("savedAt", "")),
			)),
			int(damage.get("fallbackWorldRevision", slot.get("worldRevision", 0))),
		]
	return "%s · World %d" % [
		_full_saved_at(String(slot.get("savedAt", ""))),
		int(slot.get("worldRevision", 0)),
	]


func _recovery_copy(slot: Dictionary) -> String:
	var state := String(slot.get("state", "empty"))
	var recovery_state := String(slot.get("recoveryState", "none"))
	var damage := slot.get("damageDetails", {}) as Dictionary
	if state == "empty":
		return "没有可加载的存档"
	if state == "incomplete":
		return (
			"上次保存未完成；将使用最近完整存档"
			if bool(slot.get("continueAvailable", false))
			else "保存未完成，尚无可恢复版本"
		)
	if state == "recoverable" or recovery_state == "older_complete_revision_available":
		return "损坏修订 %d · %s · World %d" % [
			int(damage.get("damagedSaveRevision", 0)),
			_full_saved_at(String(damage.get("damagedSavedAt", ""))),
			int(damage.get("damagedWorldRevision", 0)),
		]
	if recovery_state == "restore_reconciliation_required":
		return "上次恢复未完成，需要先完成存档协调"
	if state == "corrupt" or recovery_state.begins_with("corrupt"):
		if not bool(slot.get("continueAvailable", false)):
			return "存档损坏，且没有可恢复的完整版本"
		return "存档损坏；将使用最近完整存档"
	if state in ["healthy", "complete"]:
		return "第 %d 天 · %d 位居民" % [
			int(slot.get("day", 0)),
			int(slot.get("residentCount", 0)),
		]
	return "存档状态无法识别"


func _slot_detail_copy(slot: Dictionary) -> String:
	var state := String(slot.get("state", "empty"))
	if state == "recoverable":
		var damage := slot.get("damageDetails", {}) as Dictionary
		return "恢复至第 %d 天 · %d 位居民" % [
			int(damage.get("fallbackDay", slot.get("day", 0))),
			int(slot.get("residentCount", 0)),
		]
	if state in ["healthy", "complete"]:
		return "完整存档"
	if state == "incomplete" and bool(slot.get("continueAvailable", false)):
		return "最近完整存档：第 %d 天 · %d 位居民" % [
			int(slot.get("day", 0)),
			int(slot.get("residentCount", 0)),
		]
	if state in ["empty", "incomplete", "corrupt"]:
		return "当前无法进入"
	return "请检查存档状态"


func _damage_detail_copy(slot: Dictionary) -> String:
	var state := String(slot.get("state", "empty"))
	if state != "recoverable":
		return _recovery_copy(slot)
	var damage := slot.get("damageDetails", {}) as Dictionary
	return (
		"损坏：修订 %d · %s · World %d；"
		+ "恢复：修订 %d · %s · World %d · 第 %d 天"
	) % [
		int(damage.get("damagedSaveRevision", 0)),
		_full_saved_at(String(damage.get("damagedSavedAt", ""))),
		int(damage.get("damagedWorldRevision", 0)),
		int(damage.get("fallbackSaveRevision", slot.get("saveRevision", 0))),
		_full_saved_at(String(
			damage.get("fallbackSavedAt", slot.get("savedAt", "")),
		)),
		int(damage.get("fallbackWorldRevision", slot.get("worldRevision", 0))),
		int(damage.get("fallbackDay", slot.get("day", 0))),
	]


func _slot_action_copy(slot: Dictionary) -> String:
	if bool(slot.get("diagnosticAvailable", false)):
		return "查看诊断"
	if bool(slot.get("requiresRecoveryConfirmation", false)):
		return "查看恢复详情"
	if String(slot.get("state", "")) == "recoverable":
		return "恢复并继续"
	return "进入小镇"


func _slot_visual_family(slot: Dictionary) -> String:
	var state := String(slot.get("state", "empty"))
	var continue_available := bool(slot.get("continueAvailable", false))
	if state in ["healthy", "complete"] and continue_available:
		return VISUAL_STATE_HEALTHY
	if state == "recoverable" and continue_available:
		return VISUAL_STATE_RECOVERABLE
	if state in ["incomplete", "corrupt"] and continue_available:
		return VISUAL_STATE_RECOVERABLE
	return VISUAL_STATE_DISABLED


func _state_accent_region(visual_family: String) -> Rect2:
	match visual_family:
		VISUAL_STATE_HEALTHY:
			return HEALTHY_ACCENT_REGION
		VISUAL_STATE_RECOVERABLE:
			return RECOVERABLE_ACCENT_REGION
	return DISABLED_ACCENT_REGION


func _state_copy(state: String) -> String:
	match state:
		"healthy", "complete":
			return "可继续"
		"recoverable":
			return "可恢复"
		"incomplete":
			return "保存未完成"
		"corrupt":
			return "存档损坏"
		"empty":
			return "空槽"
	return "状态未知"


func _full_saved_at(value: String) -> String:
	if value.is_empty():
		return "保存时间未知"
	var local := value.replace("T", " ")
	var plus_index := local.find("+", 10)
	if plus_index >= 0:
		local = local.left(plus_index)
	if local.ends_with("Z"):
		local = local.left(-1)
	return local


func _request_slot(slot: Dictionary) -> bool:
	var state := String(slot.get("state", "empty"))
	var overwrite_selection := _is_overwrite_selection_mode()
	var action_key := "selectOverwriteSlot" if overwrite_selection else "continueSlot"
	var action := _action(action_key)
	var intent := StringName(String(action.get("intent", "")))
	if not bool(action.get("enabled", false)):
		return _block(
			intent,
			String(action.get("disabledReason", "ACTION_NOT_AVAILABLE")),
		)
	if state == "empty":
		return _block(
			intent,
			"STARTUP_OVERWRITE_SLOT_EMPTY"
			if overwrite_selection
			else "SESSION_SAVE_NO_PUBLISHED_REVISION",
		)
	if (
		not bool(slot.get("continueAvailable", false))
		and not bool(slot.get("diagnosticAvailable", false))
	):
		var unavailable_reason := String(slot.get(
				"errorCode",
				"STARTUP_OVERWRITE_SLOT_CONFIRMATION_UNAVAILABLE"
				if overwrite_selection
				else "SESSION_SAVE_CORRUPT",
			)).strip_edges()
		if unavailable_reason.is_empty():
			unavailable_reason = (
				"STARTUP_OVERWRITE_SLOT_CONFIRMATION_UNAVAILABLE"
				if overwrite_selection
				else "SESSION_SAVE_CORRUPT"
			)
		return _block(intent, unavailable_reason)
	intent_requested.emit(intent, {
		"scope": "save",
		"actionKey": action_key,
		"revision": _revision,
		"routeOrigin": "startup_load_game",
		"slotId": String(slot.get("slotId", "")),
		"saveRevision": int(slot.get("saveRevision", 0)),
		"recoveryState": String(slot.get("recoveryState", "none")),
		"requiresRecoveryConfirmation": bool(
			slot.get("requiresRecoveryConfirmation", false)
		),
	})
	return true


func _request_delete_slot(slot: Dictionary) -> bool:
	var action := _action("deleteSlot")
	var intent := StringName(String(action.get("intent", "")))
	if _is_overwrite_selection_mode():
		return _block(intent, "ACTION_NOT_AVAILABLE_IN_MODE")
	if not bool(action.get("enabled", false)):
		return _block(
			intent,
			String(action.get("disabledReason", "ACTION_NOT_AVAILABLE")),
		)
	if String(slot.get("state", "empty")) == "empty":
		return _block(intent, "SESSION_SAVE_NO_PUBLISHED_REVISION")
	intent_requested.emit(intent, {
		"scope": "save",
		"actionKey": "deleteSlot",
		"revision": _revision,
		"routeOrigin": "startup_load_game",
		"slotId": String(slot.get("slotId", "")),
		"saveRevision": int(slot.get("saveRevision", 0)),
		"sessionId": String(slot.get("sessionId", "")),
		"state": String(slot.get("state", "")),
	})
	return true


func _request_back() -> bool:
	var action := _action("back")
	var intent := StringName(String(action.get("intent", "")))
	if not bool(action.get("enabled", false)):
		return _block(
			intent,
			String(action.get("disabledReason", "ACTION_NOT_AVAILABLE")),
		)
	intent_requested.emit(intent, {
		"scope": "save",
		"actionKey": "back",
		"revision": _revision,
		"routeOrigin": "startup_load_game",
	})
	return true


func request_back() -> bool:
	return _request_back()


func _block(intent: StringName, reason: String) -> bool:
	action_blocked.emit(intent, reason)
	if is_instance_valid(_feedback):
		_feedback.text = (
			"当前槽位不能作为覆盖目标。"
			if _is_overwrite_selection_mode()
			else "当前存档无法删除。"
			if intent == &"save.request_delete_slot"
			else "当前存档无法进入。"
		)
	return false


func _is_overwrite_selection_mode() -> bool:
	return String(
		(_view_model.get("data", {}) as Dictionary).get("mode", LOAD_MODE),
	) == OVERWRITE_SELECTION_MODE


func _slot_action_intent() -> StringName:
	var action_key := (
		"selectOverwriteSlot"
		if _is_overwrite_selection_mode()
		else "continueSlot"
	)
	return StringName(String(_action(action_key).get("intent", "")))


func _action(action_key: String) -> Dictionary:
	return (
		(_view_model.get("actions", {}) as Dictionary).get(action_key, {})
		as Dictionary
	)


func _focus_first_available() -> void:
	for child: Node in _slot_layer.get_children():
		if child is Button and not (child as Button).disabled:
			(child as Button).call_deferred("grab_focus")
			return
	_back_button.call_deferred("grab_focus")


func _label(
	node_name: String,
	reference_rect: Rect2,
	variation: StringName,
	parent: Node = self,
) -> Label:
	var label := Label.new()
	label.name = node_name
	label.theme_type_variation = variation
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_reference_rect(label, reference_rect)
	parent.add_child(label)
	return label


func _button(
	node_name: String,
	text: String,
	reference_rect: Rect2,
	variation: StringName,
	callback: Callable,
	parent: Node = self,
) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.tooltip_text = text
	button.theme_type_variation = variation
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_apply_reference_rect(button, reference_rect)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _apply_reference_rect(control: Control, reference_rect: Rect2) -> void:
	control.anchor_left = reference_rect.position.x / REFERENCE_VIEWPORT.x
	control.anchor_top = reference_rect.position.y / REFERENCE_VIEWPORT.y
	control.anchor_right = reference_rect.end.x / REFERENCE_VIEWPORT.x
	control.anchor_bottom = reference_rect.end.y / REFERENCE_VIEWPORT.y
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0


func _source_rect(source_rect: Rect2) -> Rect2:
	var scale := REFERENCE_VIEWPORT / VISUAL_ATLAS_SIZE
	return Rect2(source_rect.position * scale, source_rect.size * scale)


func _atlas_texture(region: Rect2) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = _visual_atlas_texture
	texture.region = region
	texture.filter_clip = true
	return texture


func _cropped_texture(source: Texture2D, region: Rect2) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = source
	texture.region = region
	texture.filter_clip = true
	return texture


func _load_texture(path: String) -> Texture2D:
	return ResourceLoader.load(path, "Texture2D") as Texture2D
