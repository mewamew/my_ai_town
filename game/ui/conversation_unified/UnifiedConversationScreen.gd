class_name UnifiedConversationScreen
extends Control

const MOBILE_UI_PROFILE := preload("res://ui/mobile/MobileUiProfile.gd")


signal intent_requested(intent: StringName, payload: Dictionary)
signal action_blocked(intent: StringName, reason: String)
signal close_requested

const UI_SIGNALS := preload(
	"res://ui/common/AiTownUiSignals.gd"
)
const UiViewModel = preload("res://ui/common/AiTownUiViewModel.gd")
const UiNodeRetirement = preload("res://ui/common/AiTownUiNodeRetirement.gd")
const Segmenter = preload(
	"res://ui/conversation_unified/ConversationSemanticSegmenter.gd"
)
const PageTheme = preload(
	"res://ui/conversation_unified/UnifiedConversationTheme.gd"
)
const FormalDialog = preload(
	"res://ui/common/formal_dialog/FormalConfirmationDialog.gd"
)

const SCOPE := &"conversation"
const BASE_SIZE := Vector2(765, 898)
const PLAYER_SHELL_PATH := (
	"res://assets/ui/conversation_unified/runtime/shells/"
	+ "unified_chat_player_shell_v1.png"
)
const SPECTATOR_SHELL_PATH := (
	"res://assets/ui/conversation_unified/runtime/shells/"
	+ "unified_chat_spectator_shell_v1.png"
)
const THINKING_HOURGLASS_PATH := (
	"res://assets/ui/conversation_unified/runtime/status/"
	+ "unified_chat_thinking_hourglass_v1_1x.png"
)
const PLAYER_SHELL_TEXTURE := preload(
	"res://assets/ui/conversation_unified/runtime/shells/"
	+ "unified_chat_player_shell_v1.png"
)
const SPECTATOR_SHELL_TEXTURE := preload(
	"res://assets/ui/conversation_unified/runtime/shells/"
	+ "unified_chat_spectator_shell_v1.png"
)
const THINKING_HOURGLASS_TEXTURE := preload(
	"res://assets/ui/conversation_unified/runtime/status/"
	+ "unified_chat_thinking_hourglass_v1_1x.png"
)
const MAX_DRAFT_CHARACTERS := 280
const MAX_DRAFT_LINES := 3
const STREAM_MIN_CHARACTERS_PER_SECOND := 52.0
const STREAM_MAX_DURATION_SECONDS := 1.6
const ENDED_AUTO_DISMISS_DELAY_SECONDS := 1.25
const THINKING_DOT_HOP_HEIGHT := 5.0
const THINKING_DOT_PHASE_SECONDS := 0.18
const BUBBLE_TAIL_OVERLAP := 8
const BUBBLE_MIN_TEXT_WIDTH := 220.0
const BUBBLE_MAX_TEXT_WIDTH := 468.0
const HISTORY_BOTTOM_TOLERANCE := 24.0
const PLAYER_HISTORY_HEIGHT := 580.0
const SPECTATOR_HISTORY_HEIGHT := 708.0
const PLAYER_PORTRAIT_SAFE_RECT := Rect2(55, 43, 88, 74)
const PLAYER_TITLE_SAFE_RECT := Rect2(166, 48, 300, 60)
const SPECTATOR_PORTRAIT_SAFE_RECT := Rect2(56, 43, 135, 74)
const SPECTATOR_TITLE_SAFE_RECT := Rect2(220, 48, 276, 60)
const HEADER_STATUS_SAFE_RECT := Rect2(515, 60, 86, 44)

@export_enum("auto", "player", "spectator") var forced_display_mode := "auto"

var _adapter: Object
var _view_model: Dictionary = {}
var _render_data: Dictionary = {}
var _last_confirmed_data: Dictionary = {}
var _current_revision := -1
var _mode := "player"
var _suppress_draft_change := false
var _selected_photo_ref := ""
var _selected_photo_mime_type := ""
var _selected_photo_owner_id := ""
var _selected_photo_texture: ImageTexture
var _photo_local_status := ""
var _photo_local_error_code := ""
var _thinking_elapsed := 0.0
var _thinking_dots: Array[Label] = []
var _stream_turn_key := ""
var _stream_visible_characters := 0.0
var _stream_total_characters := 0
var _rendered_message_signature := ""
var _stream_segments: Array[Dictionary] = []
var _stream_scroll_elapsed := 0.0
var _stream_characters_per_second := STREAM_MIN_CHARACTERS_PER_SECOND
var _scroll_request_generation := 0
var _history_auto_follow_latest := true
var _restore_draft_focus_after_wait := false
var _draft_limit_reached := false
var _conversation_photo_textures: Dictionary = {}
var _portrait_texture_cache: Dictionary = {}
var _ended_presentation_conversation_id := ""
var _ended_notice_revealed := false
var _ended_dismiss_requested := false
var _ended_dismiss_elapsed := -1.0

var _stage: Control
var _shell_skin: TextureRect
var _portrait_slot: Control
var _portrait_textures: Array[TextureRect] = []
var _portrait_initials: Array[Label] = []
var _title_label: Label
var _subtitle_label: Label
var _close_button: Button
var _history_scroll: ScrollContainer
var _message_list: VBoxContainer
var _composer_root: Control
var _photo_button: Button
var _draft_edit: TextEdit
var _draft_limit_label: Label
var _send_button: Button
var _file_dialog: FileDialog
var _close_confirmation: FormalDialog
var _end_notice_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	theme = PageTheme.create()
	_build_interface()
	get_viewport().size_changed.connect(_apply_layout)
	_apply_layout()
	if _adapter != null:
		_refresh_from_adapter()
	else:
		_render()


func _process(delta: float) -> void:
	if not _thinking_dots.is_empty():
		_thinking_elapsed += delta
		_update_thinking_dots()
	if not _stream_turn_key.is_empty() and _stream_total_characters > 0:
		_stream_visible_characters = minf(
			float(_stream_total_characters),
			_stream_visible_characters
				+ delta * _stream_characters_per_second
		)
		_apply_stream_progress()
		_stream_scroll_elapsed += delta
		if _stream_scroll_elapsed >= 0.12:
			_stream_scroll_elapsed = 0.0
			_scroll_to_latest()
	_update_ended_presentation(delta)


func _exit_tree() -> void:
	_clear_selected_photo(true)
	_conversation_photo_textures.clear()
	_disconnect_adapter()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if request_back():
		get_viewport().set_input_as_handled()


func request_back() -> bool:
	if is_instance_valid(_close_confirmation) and _close_confirmation.visible:
		return true
	if _mode == "spectator":
		_close_spectator()
	elif _conversation_ended():
		_dismiss_ended_conversation()
	else:
		_request_end_conversation()
	return true


func bind_town_ui_adapter(adapter: Object) -> void:
	if _adapter == adapter:
		return
	_clear_selected_photo(true)
	_disconnect_adapter()
	_adapter = adapter
	_view_model.clear()
	_render_data.clear()
	_last_confirmed_data.clear()
	_current_revision = -1
	_restore_draft_focus_after_wait = false
	_conversation_photo_textures.clear()
	_reset_history_auto_follow()
	_reset_ended_presentation()
	if _adapter != null and _adapter.has_signal("view_model_changed"):
		var callback := Callable(self, "_on_view_model_changed")
		if not _adapter.is_connected("view_model_changed", callback):
			_adapter.connect("view_model_changed", callback)
	if is_node_ready():
		_refresh_from_adapter()


func unbind_town_ui_adapter() -> void:
	_clear_selected_photo(true)
	_disconnect_adapter()
	_adapter = null
	_view_model.clear()
	_render_data.clear()
	_last_confirmed_data.clear()
	_current_revision = -1
	_restore_draft_focus_after_wait = false
	_conversation_photo_textures.clear()
	_reset_history_auto_follow()
	_reset_ended_presentation()
	if is_node_ready():
		_render()


func apply_view_model(view_model: Dictionary) -> bool:
	var issues := UiViewModel.validate(view_model, "统一聊天页")
	if not issues.is_empty():
		for issue: String in issues:
			push_error(issue)
		return false
	if UiViewModel.scope(view_model) != SCOPE:
		return false
	var previous_waiting := _resident_waiting()
	var previous_ended := _conversation_ended()
	var previous_latest_turn := _latest_message_turn_key()
	var previous_conversation_id := str(
		_render_data.get("conversationId", "")
	)
	var incoming_revision := UiViewModel.revision(view_model)
	if _current_revision >= 0 and incoming_revision < _current_revision:
		return false
	var incoming_data := UiViewModel.data(view_model)
	var operation_status := UiViewModel.operation_status(view_model)
	if operation_status != &"rejected" and not incoming_data.is_empty():
		_last_confirmed_data = incoming_data.duplicate(true)
	if operation_status == &"rejected" and not _last_confirmed_data.is_empty():
		_render_data = _last_confirmed_data.duplicate(true)
	else:
		_render_data = UiViewModel.data_for_render(
			view_model,
			_last_confirmed_data
		)
	if _render_data.is_empty():
		_render_data = _last_confirmed_data.duplicate(true)
	_view_model = view_model.duplicate(true)
	_current_revision = incoming_revision
	_mode = (
		forced_display_mode
		if forced_display_mode in ["player", "spectator"]
		else str(_render_data.get("displayMode", "player"))
	)
	if _mode not in ["player", "spectator"]:
		_mode = "player"
	var current_conversation_id := str(
		_render_data.get("conversationId", "")
	)
	if current_conversation_id != previous_conversation_id:
		_restore_draft_focus_after_wait = false
		_conversation_photo_textures.clear()
		_reset_history_auto_follow()
	var current_ended := _conversation_ended()
	if current_ended:
		if (
			_ended_presentation_conversation_id
			!= current_conversation_id
		):
			_reset_ended_presentation()
			_ended_presentation_conversation_id = current_conversation_id
	else:
		_reset_ended_presentation()
	if (
		not _selected_photo_ref.is_empty()
		and (
			_mode != "player"
			or not bool(_render_data.get("canAttachPhoto", false))
			or (
				not previous_conversation_id.is_empty()
				and current_conversation_id != previous_conversation_id
			)
		)
	):
		_clear_selected_photo(true)
	var current_waiting := _resident_waiting()
	var current_latest_turn := _latest_message_turn_key()
	if (
		(
			previous_waiting
			and not current_waiting
		)
		or (
			not previous_ended
			and current_ended
		)
	) and (
		not current_latest_turn.is_empty()
		and current_latest_turn != previous_latest_turn
	):
		_begin_stream(current_latest_turn)
	elif current_waiting:
		_cancel_stream()
	if is_node_ready():
		_render()
		if (
			_restore_draft_focus_after_wait
			and previous_waiting
			and not current_waiting
			and not current_ended
		):
			_restore_draft_focus_after_wait = false
			call_deferred(
				"_focus_draft_after_reply",
				current_conversation_id,
			)
	return true


func focus_default_control() -> bool:
	if (
		_mode == "player"
		and _draft_edit.visible
		and _draft_edit.editable
	):
		_draft_edit.grab_focus()
		return true
	_close_button.grab_focus()
	return true


func runtime_gate_snapshot() -> Dictionary:
	var source_turn_ids: Array = []
	for child: Node in _message_list.get_children():
		if child.has_meta("source_turn_id"):
			source_turn_ids.append(child.get_meta("source_turn_id"))
	var bubble_tails := find_children(
		"UniqueBubbleTail",
		"TextureRect",
		true,
		false,
	)
	var image_bubbles := find_children(
		"*ImageBubble*",
		"HBoxContainer",
		true,
		false,
	)
	var narration_only_turns := find_children(
		"ConversationNarrationOnlyTurn",
		"HBoxContainer",
		true,
		false,
	)
	var history_photo_previews := find_children(
		"ConversationPhotoPreview",
		"TextureRect",
		true,
		false,
	)
	var speaker_copies: Array[String] = []
	for speaker_label_value: Node in find_children(
		"ConversationSpeakerLabel",
		"Label",
		true,
		false,
	):
		speaker_copies.append((speaker_label_value as Label).text)
	var scroll_bar := _history_scroll.get_v_scroll_bar()
	var selected_spectator := _selected_spectator_conversation()
	var spectator_contract_available := not selected_spectator.is_empty()
	var can_attach_photo := bool(_render_data.get("canAttachPhoto", false))
	return {
		"pageId": "unified_conversation",
		"mode": _mode,
			"revision": _current_revision,
			"title": _title_label.text,
			"subtitle": _subtitle_label.text,
			"titleClipText": _title_label.clip_text,
			"subtitleClipText": _subtitle_label.clip_text,
		"sourceMode": "town_ui_adapter" if _adapter != null else "unbound",
		"source": str(_render_data.get("source", "")),
		"formalReady": bool(_render_data.get("formalReady", false)),
		"adapterInstanceId": (
			_adapter.get_instance_id()
			if is_instance_valid(_adapter)
			else 0
		),
		"contractAvailable": (
			spectator_contract_available
			if _mode == "spectator"
			else not str(_render_data.get("conversationId", "")).is_empty()
		),
		"contractFailureCode": (
			"SPECTATOR_INTERFACE_MISSING"
			if _mode == "spectator" and not spectator_contract_available
			else ""
		),
		"runtimeMockUsed": false,
		"referenceLockedWide": true,
		"composerVisible": _composer_root.visible,
		"composerRect": _rect_snapshot(
			Rect2(_composer_root.position, _composer_root.size)
		),
		"draftControlRect": _rect_snapshot(
			Rect2(
				_composer_root.position + _draft_edit.position,
				_draft_edit.size,
			)
		),
		"draftTextSafeRect": _rect_snapshot(
			Rect2(
				_composer_root.position
					+ _draft_edit.position
					+ Vector2(
						PageTheme.INPUT_CONTENT_MARGINS.x,
						PageTheme.INPUT_CONTENT_MARGINS.y,
					),
				_draft_edit.size
					- Vector2(
						PageTheme.INPUT_CONTENT_MARGINS.x
							+ PageTheme.INPUT_CONTENT_MARGINS.z,
						PageTheme.INPUT_CONTENT_MARGINS.y
							+ PageTheme.INPUT_CONTENT_MARGINS.w,
					),
			)
		),
		"draftFontSize": _draft_edit.get_theme_font_size(
			"font_size",
			"TextEdit",
		),
		"draftMaxLines": MAX_DRAFT_LINES,
		"draftLimitReached": _draft_limit_reached,
		"draftLimitCopy": (
			_draft_limit_label.text
			if is_instance_valid(_draft_limit_label)
			else ""
		),
		"draftLimitVisible": (
			_draft_limit_label.visible
			if is_instance_valid(_draft_limit_label)
			else false
		),
		"canAttachPhoto": can_attach_photo,
		"photoEnabled": not _photo_button.disabled,
		"photoButtonDisabled": _photo_button.disabled,
		"photoSelected": not _selected_photo_ref.is_empty(),
		"photoPreviewVisible": _photo_button.icon != null,
		"photoLocalErrorCode": _photo_local_error_code,
		"originalSendDisabled": _send_button.disabled,
		"messageSegmentCount": _message_list.get_child_count(),
		"imageBubbleCount": image_bubbles.size(),
		"bubbleTailCount": bubble_tails.size(),
		"narrationOnlyTurnCount": narration_only_turns.size(),
		"historyPhotoPreviewCount": history_photo_previews.size(),
		"speakerCopies": speaker_copies,
		"historyHeight": _history_scroll.size.y,
		"historyScrollVertical": _history_scroll.scroll_vertical,
		"historyScrollBottom": int(maxf(
			0.0,
			scroll_bar.max_value - scroll_bar.page,
		)),
		"historyAutoFollowLatest": _history_auto_follow_latest,
		"thinkingVisible": not _thinking_dots.is_empty(),
		"thinkingDotCount": _thinking_dots.size(),
		"conversationEnded": _conversation_ended(),
		"endedByName": str(_render_data.get("endedByName", "")),
		"endNotice": str(_render_data.get("endNotice", "")),
		"endNoticeVisible": (
			is_instance_valid(_end_notice_label)
			and _end_notice_label.visible
		),
		"endedDismissRequested": _ended_dismiss_requested,
		"streamActive": not _stream_turn_key.is_empty(),
		"streamTurnId": _stream_turn_key,
		"streamVisibleCharacters": int(floorf(_stream_visible_characters)),
		"streamTotalCharacters": _stream_total_characters,
		"streamCharactersPerSecond": _stream_characters_per_second,
		"sourceTurnIds": source_turn_ids,
		"shellPath": (
			SPECTATOR_SHELL_PATH
			if _mode == "spectator"
			else PLAYER_SHELL_PATH
		),
		"fontPath": PageTheme.MAIN_MENU_FONT_PATH,
		"fontMatchesMainMenu": true,
		"bubbleTailPolicy": "one_fixed_tail_per_message",
		"portraitSafeRect": _rect_snapshot(
			SPECTATOR_PORTRAIT_SAFE_RECT
			if _mode == "spectator"
			else PLAYER_PORTRAIT_SAFE_RECT
		),
		"titleSafeRect": _rect_snapshot(
			SPECTATOR_TITLE_SAFE_RECT
			if _mode == "spectator"
			else PLAYER_TITLE_SAFE_RECT
		),
		"statusSafeRect": _rect_snapshot(HEADER_STATUS_SAFE_RECT),
		"legacyReferenceLockedActive": false,
		"originalMessageDataPreserved": true,
	}


func _build_interface() -> void:
	_stage = Control.new()
	_stage.name = "UnifiedConversationStage"
	_stage.size = BASE_SIZE
	_stage.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_stage)

	_shell_skin = TextureRect.new()
	_shell_skin.name = "UnifiedConversationShell"
	_shell_skin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shell_skin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shell_skin.stretch_mode = TextureRect.STRETCH_SCALE
	_shell_skin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_shell_skin)

	_build_header()
	_build_history()
	_build_composer()
	_build_file_dialog()
	_build_close_confirmation()


func _build_header() -> void:
	_portrait_slot = Control.new()
	_portrait_slot.name = "HeaderPortraitSlot"
	_portrait_slot.position = PLAYER_PORTRAIT_SAFE_RECT.position
	_portrait_slot.size = PLAYER_PORTRAIT_SAFE_RECT.size
	_portrait_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_portrait_slot)
	for index: int in 2:
		var texture := TextureRect.new()
		texture.name = "HeaderPortrait%d" % (index + 1)
		texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_portrait_slot.add_child(texture)
		_portrait_textures.append(texture)
		var initial := Label.new()
		initial.name = "HeaderInitial%d" % (index + 1)
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initial.add_theme_font_size_override(
			"font_size",
			PageTheme.HEADER_TITLE_FONT_SIZE,
		)
		initial.add_theme_color_override("font_color", PageTheme.INK)
		initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_portrait_slot.add_child(initial)
		_portrait_initials.append(initial)

	_title_label = Label.new()
	_title_label.name = "ConversationTitle"
	_title_label.position = PLAYER_TITLE_SAFE_RECT.position
	_title_label.size = PLAYER_TITLE_SAFE_RECT.size
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.clip_text = true
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_label.add_theme_font_size_override(
		"font_size",
		PageTheme.HEADER_TITLE_FONT_SIZE,
	)
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.name = "ConversationSubtitle"
	_subtitle_label.position = HEADER_STATUS_SAFE_RECT.position
	_subtitle_label.size = HEADER_STATUS_SAFE_RECT.size
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_subtitle_label.clip_text = true
	_subtitle_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_subtitle_label.add_theme_font_size_override(
		"font_size",
		PageTheme.HEADER_STATUS_FONT_SIZE,
	)
	_subtitle_label.add_theme_color_override("font_color", PageTheme.MUTED)
	_subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_subtitle_label)

	_close_button = Button.new()
	_close_button.name = "CloseConversationButton"
	_close_button.position = Vector2(679, 35)
	_close_button.size = Vector2(66, 76)
	_close_button.focus_mode = Control.FOCUS_ALL
	_close_button.tooltip_text = "结束聊天"
	_close_button.pressed.connect(_on_close_pressed)
	_stage.add_child(_close_button)


func _build_history() -> void:
	_history_scroll = ScrollContainer.new()
	_history_scroll.name = "ConversationHistory"
	_history_scroll.position = Vector2(52, 138)
	_history_scroll.size = Vector2(646, PLAYER_HISTORY_HEIGHT)
	_history_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_history_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_history_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage.add_child(_history_scroll)
	_history_scroll.get_v_scroll_bar().value_changed.connect(
		_on_history_scroll_changed
	)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history_scroll.add_child(margin)

	_message_list = VBoxContainer.new()
	_message_list.name = "ConversationMessages"
	_message_list.add_theme_constant_override("separation", 12)
	_message_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_message_list)


func _build_composer() -> void:
	_composer_root = Control.new()
	_composer_root.name = "PlayerComposer"
	_composer_root.position = Vector2(48, 745)
	_composer_root.size = Vector2(660, 108)
	_stage.add_child(_composer_root)

	_photo_button = Button.new()
	_photo_button.name = "AttachPhotoButton"
	_photo_button.position = Vector2(4, 6)
	_photo_button.size = Vector2(82, 84)
	_photo_button.tooltip_text = "选择照片"
	_photo_button.expand_icon = true
	_photo_button.pressed.connect(_open_photo_dialog)
	_composer_root.add_child(_photo_button)

	_draft_edit = TextEdit.new()
	_draft_edit.name = "ConversationDraft"
	_draft_edit.position = Vector2(100, 12)
	_draft_edit.size = Vector2(430, 70)
	_draft_edit.placeholder_text = "输入消息…"
	_draft_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_draft_edit.scroll_fit_content_height = false
	_draft_edit.tooltip_text = "最多 280 字、3 行；Enter 发送，Shift+Enter 换行"
	_draft_edit.text_changed.connect(_on_draft_changed)
	_draft_edit.gui_input.connect(_on_draft_gui_input)
	_composer_root.add_child(_draft_edit)

	_draft_limit_label = _label(
		"",
		16,
		PageTheme.MUTED,
	)
	_draft_limit_label.name = "ConversationDraftLimit"
	_draft_limit_label.position = Vector2(100, -22)
	_draft_limit_label.size = Vector2(430, 20)
	_draft_limit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_composer_root.add_child(_draft_limit_label)

	_send_button = Button.new()
	_send_button.name = "SendConversationReply"
	_send_button.position = Vector2(544, 4)
	_send_button.size = Vector2(108, 90)
	_send_button.tooltip_text = "发送"
	_send_button.pressed.connect(_submit_reply)
	_composer_root.add_child(_send_button)


func _build_file_dialog() -> void:
	_file_dialog = FileDialog.new()
	_file_dialog.name = "ConversationPhotoFileDialog"
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	_file_dialog.add_filter(
		"*.png,*.PNG,*.jpg,*.JPG,*.jpeg,*.JPEG,*.webp,*.WEBP",
		"图片",
	)
	_file_dialog.file_selected.connect(_on_photo_selected)
	_file_dialog.canceled.connect(_on_photo_selection_canceled)
	add_child(_file_dialog)


func _build_close_confirmation() -> void:
	_close_confirmation = FormalDialog.new()
	_close_confirmation.name = "ConversationCloseConfirmation"
	_close_confirmation.title = "结束对话"
	_close_confirmation.dialog_text = "还有未发送的内容，确定结束对话吗？"
	_close_confirmation.ok_button_text = "结束对话"
	_close_confirmation.cancel_button_text = "继续聊天"
	_close_confirmation.confirmed.connect(_submit_end_conversation)
	add_child(_close_confirmation)


func _render() -> void:
	var spectator_mode := _mode == "spectator"
	var conversation_ended := _conversation_ended()
	_shell_skin.texture = (
		SPECTATOR_SHELL_TEXTURE
		if spectator_mode
		else PLAYER_SHELL_TEXTURE
	) as Texture2D
	_composer_root.visible = not spectator_mode and not conversation_ended
	_history_scroll.size.y = (
		SPECTATOR_HISTORY_HEIGHT
		if spectator_mode
		else PLAYER_HISTORY_HEIGHT
	)
	_render_header()
	_rebuild_messages()
	_render_composer()
	MOBILE_UI_PROFILE.apply_mobile_typography(self, 22, 3, 34)
	_apply_layout()


func _render_header() -> void:
	if _mode == "spectator":
		_apply_header_safe_rects(
			SPECTATOR_PORTRAIT_SAFE_RECT,
			SPECTATOR_TITLE_SAFE_RECT,
		)
		var selected := _selected_spectator_conversation()
		var participants := selected.get("participants", []) as Array
		var left := _participant(participants, 0)
		var right := _participant(participants, 1)
		var left_name := str(left.get("residentName", "居民"))
		var right_name := str(right.get("residentName", "居民"))
		_title_label.text = "%s × %s" % [left_name, right_name]
		_subtitle_label.text = "旁观中"
		_apply_header_portraits([left, right])
		_close_button.tooltip_text = "关闭旁观"
		return
	_apply_header_safe_rects(
		PLAYER_PORTRAIT_SAFE_RECT,
		PLAYER_TITLE_SAFE_RECT,
	)
	var resident_name := str(_render_data.get("residentName", "居民"))
	if resident_name.is_empty():
		resident_name = "居民"
	_title_label.text = resident_name
	_subtitle_label.text = (
		"对话结束"
		if _conversation_ended()
		else "聊天中"
	)
	_apply_header_portraits([{
		"residentName": resident_name,
		"portraitRef": str(_render_data.get("portraitRef", "")),
	}])
	_close_button.tooltip_text = (
		"关闭"
		if _conversation_ended()
		else "结束聊天"
	)


func _apply_header_portraits(participants: Array) -> void:
	var spectator_mode := participants.size() >= 2
	var slot_width := _portrait_slot.size.x
	var slot_height := _portrait_slot.size.y
	for index: int in 2:
		var texture_rect := _portrait_textures[index]
		var initial := _portrait_initials[index]
		var data: Dictionary = {}
		if index < participants.size() and participants[index] is Dictionary:
			data = (participants[index] as Dictionary).duplicate(true)
		var visible_slot := index == 0 or spectator_mode
		texture_rect.visible = visible_slot
		initial.visible = visible_slot
		var slot_rect := (
			Rect2(
				float(index) * slot_width * 0.5,
				0,
				slot_width * 0.5,
				slot_height,
			)
			if spectator_mode
			else Rect2(Vector2.ZERO, _portrait_slot.size)
		)
		texture_rect.position = slot_rect.position
		texture_rect.size = slot_rect.size
		initial.position = slot_rect.position
		initial.size = slot_rect.size
		var name := str(data.get("residentName", ""))
		initial.text = name.left(1) if not name.is_empty() else "？"
		var portrait_ref := str(data.get("portraitRef", ""))
		var portrait: Texture2D
		if portrait_ref.begins_with("res://"):
			if _portrait_texture_cache.has(portrait_ref):
				portrait = _portrait_texture_cache.get(portrait_ref) as Texture2D
			else:
				portrait = ResourceLoader.load(
					portrait_ref,
					"Texture2D",
				) as Texture2D
				if portrait != null:
					_portrait_texture_cache[portrait_ref] = portrait
		texture_rect.texture = portrait
		texture_rect.visible = visible_slot and portrait != null
		initial.visible = visible_slot and portrait == null


func _apply_header_safe_rects(
	portrait_rect: Rect2,
	title_rect: Rect2,
) -> void:
	_portrait_slot.position = portrait_rect.position
	_portrait_slot.size = portrait_rect.size
	_title_label.position = title_rect.position
	_title_label.size = title_rect.size
	_subtitle_label.position = HEADER_STATUS_SAFE_RECT.position
	_subtitle_label.size = HEADER_STATUS_SAFE_RECT.size


func _rect_snapshot(rect: Rect2) -> Dictionary:
	return {
		"x": rect.position.x,
		"y": rect.position.y,
		"width": rect.size.x,
		"height": rect.size.y,
	}


func _rebuild_messages() -> void:
	# 消息与尾部状态都没变时跳过整棵子树的销毁重建（视图模型的其他字段
	# 变化也会触发到这里）。流式进度由计时器驱动，不依赖本次重建。
	var render_signature := _message_render_signature()
	if render_signature == _rendered_message_signature:
		return
	_rendered_message_signature = render_signature
	UiNodeRetirement.retire_children(_message_list)
	_end_notice_label = null
	_thinking_dots.clear()
	_stream_segments.clear()
	_stream_total_characters = 0
	var error_value: Variant = _view_model.get("error", {})
	var error: Dictionary = (
		(error_value as Dictionary).duplicate(true)
		if error_value is Dictionary
		else {}
	)
	var messages := _render_messages()
	var showing_thinking_only := (
		messages.is_empty()
		and _resident_waiting()
		and error.is_empty()
	)
	if messages.is_empty() and not showing_thinking_only:
		_add_status_line("还没有已确认的对话。", false)
	else:
		for index: int in messages.size():
			var value: Variant = messages[index]
			if not value is Dictionary:
				continue
			var message := value as Dictionary
			var resident_side := _message_is_resident_side(message, index)
			if str(message.get("say", "")).strip_edges().is_empty():
				_add_narration_only_turn(message, resident_side)
				continue
			for segment: Dictionary in Segmenter.segment_message(message):
				_add_message_segment(segment, resident_side)
	if _resident_waiting() and error.is_empty():
		_add_thinking_bubble()
	if not error.is_empty():
		_add_status_line(_error_copy(error), true)
	if _conversation_ended():
		var end_notice := str(
			_render_data.get("endNotice", "对话已结束")
		).strip_edges()
		if end_notice.is_empty():
			end_notice = "对话已结束"
		_end_notice_label = _add_status_line(end_notice, false)
		_end_notice_label.name = "ConversationEndNotice"
		_end_notice_label.visible = (
			_ended_notice_revealed
			and _stream_turn_key.is_empty()
		)
	_refresh_stream_speed()
	_apply_stream_progress()
	if _conversation_ended() and _stream_turn_key.is_empty():
		_reveal_ended_notice()
	call_deferred("_scroll_to_latest")


func _add_narration_only_turn(
	message: Dictionary,
	resident_side: bool,
) -> void:
	var narration_copy := str(message.get("narration", "")).strip_edges()
	if narration_copy.is_empty():
		return
	var row := HBoxContainer.new()
	row.name = "ConversationNarrationOnlyTurn"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.set_meta("source_turn_id", int(message.get("turnId", 0)))
	_message_list.add_child(row)
	if not resident_side:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
	var narration := _label(
		"〔%s〕" % narration_copy,
		PageTheme.NARRATION_FONT_SIZE,
		PageTheme.MUTED,
	)
	narration.custom_minimum_size.x = 420
	narration.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(narration)
	if resident_side:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
	if (
		not _stream_turn_key.is_empty()
		and _turn_key(message) == _stream_turn_key
	):
		_stream_segments.append({
			"row": null,
			"body": null,
			"offset": _stream_total_characters,
			"length": 0,
			"narrationRow": row,
			"showNarration": true,
		})


func _add_message_segment(segment: Dictionary, resident_side: bool) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	row.set_meta("source_turn_id", int(segment.get("turnId", 0)))
	row.set_meta("segment_index", int(segment.get("segmentIndex", 0)))
	_message_list.add_child(row)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not resident_side:
		row.add_child(spacer)

	var speaker_copy := ""
	if bool(segment.get("showIdentity", false)):
		speaker_copy = (
			"你"
			if _mode == "player" and not resident_side
			else str(segment.get("speaker", ""))
		)
		if speaker_copy.is_empty():
			speaker_copy = "居民" if resident_side else "你"
	var bubble_parts := _create_image_bubble(
		resident_side,
		_bubble_width(str(segment.get("say", "")), speaker_copy),
		107.0 if resident_side else 79.0,
	)
	var bubble_cluster := bubble_parts.get("cluster") as HBoxContainer
	var bubble := bubble_parts.get("panel") as PanelContainer
	row.add_child(bubble_cluster)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	bubble.add_child(stack)
	if bool(segment.get("showIdentity", false)):
		var speaker_label := _label(
			speaker_copy,
			PageTheme.SPEAKER_FONT_SIZE,
			PageTheme.MUTED,
		)
		speaker_label.name = "ConversationSpeakerLabel"
		stack.add_child(speaker_label)
	var body_copy := str(segment.get("say", ""))
	var body := _label(
		body_copy,
		PageTheme.BODY_FONT_SIZE,
		PageTheme.INK,
	)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.max_lines_visible = -1
	stack.add_child(body)
	if bool(segment.get("showNarration", false)):
		_add_message_photos(
			stack,
			segment.get("photos", []) as Array,
		)

	var narration_row: HBoxContainer
	if resident_side:
		row.add_child(spacer)

	if (
		bool(segment.get("showNarration", false))
		and not str(segment.get("narration", "")).strip_edges().is_empty()
	):
		narration_row = HBoxContainer.new()
		narration_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		narration_row.set_meta(
			"source_turn_id",
			int(segment.get("turnId", 0))
		)
		_message_list.add_child(narration_row)
		if not resident_side:
			var narration_spacer := Control.new()
			narration_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			narration_row.add_child(narration_spacer)
		var narration := _label(
			"〔%s〕" % str(segment.get("narration", "")),
			PageTheme.NARRATION_FONT_SIZE,
			PageTheme.MUTED
		)
		narration.custom_minimum_size.x = 420
		narration.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		narration_row.add_child(narration)
	if (
		not _stream_turn_key.is_empty()
		and _turn_key(segment) == _stream_turn_key
	):
		var offset := _stream_total_characters
		_stream_total_characters += body_copy.length()
		_stream_segments.append({
			"row": row,
			"body": body,
			"offset": offset,
			"length": body_copy.length(),
			"narrationRow": narration_row,
			"showNarration": bool(segment.get("showNarration", false)),
		})


func _add_thinking_bubble() -> void:
	var row := HBoxContainer.new()
	row.name = "ConversationThinkingRow"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message_list.add_child(row)
	var bubble_parts := _create_image_bubble(true, 196.0, 107.0)
	var bubble_cluster := bubble_parts.get("cluster") as HBoxContainer
	bubble_cluster.name = "ResidentImageBubbleThinking"
	var bubble := bubble_parts.get("panel") as PanelContainer
	row.add_child(bubble_cluster)
	var content := HBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 14)
	bubble.add_child(content)
	var hourglass := TextureRect.new()
	hourglass.name = "ThinkingHourglass"
	hourglass.custom_minimum_size = Vector2(30, 48)
	hourglass.texture = THINKING_HOURGLASS_TEXTURE
	hourglass.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hourglass.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hourglass.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hourglass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(hourglass)
	var dots_root := Control.new()
	dots_root.name = "ThinkingDots"
	dots_root.custom_minimum_size = Vector2(74, 42)
	dots_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(dots_root)
	for index: int in 3:
		var dot := _label(".", 30, PageTheme.INK)
		dot.name = "ThinkingDot%d" % (index + 1)
		dot.position = Vector2(index * 22, 5)
		dot.size = Vector2(22, 34)
		dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		dots_root.add_child(dot)
		_thinking_dots.append(dot)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_thinking_elapsed = 0.0
	_update_thinking_dots()


func _update_thinking_dots() -> void:
	if _thinking_dots.is_empty():
		return
	var cycle := THINKING_DOT_PHASE_SECONDS * 4.0
	var cycle_time := fmod(_thinking_elapsed, cycle)
	for index: int in _thinking_dots.size():
		var local_time := cycle_time - float(index) * THINKING_DOT_PHASE_SECONDS
		if local_time < 0.0:
			local_time += cycle
		var hop_progress := clampf(
			local_time / THINKING_DOT_PHASE_SECONDS,
			0.0,
			1.0
		)
		var hop: float = (
			sin(hop_progress * PI) * THINKING_DOT_HOP_HEIGHT
			if local_time <= THINKING_DOT_PHASE_SECONDS
			else 0.0
		)
		_thinking_dots[index].position.y = 5.0 - hop


func _begin_stream(turn_key: String) -> void:
	_stream_turn_key = turn_key
	_stream_visible_characters = 0.0
	_stream_total_characters = 0
	_stream_scroll_elapsed = 0.0
	_stream_characters_per_second = STREAM_MIN_CHARACTERS_PER_SECOND
	_stream_segments.clear()


func _cancel_stream() -> void:
	_stream_turn_key = ""
	_stream_visible_characters = 0.0
	_stream_total_characters = 0
	_stream_scroll_elapsed = 0.0
	_stream_characters_per_second = STREAM_MIN_CHARACTERS_PER_SECOND
	_stream_segments.clear()


func _refresh_stream_speed() -> void:
	if _stream_turn_key.is_empty() or _stream_total_characters <= 0:
		_stream_characters_per_second = STREAM_MIN_CHARACTERS_PER_SECOND
		return
	_stream_characters_per_second = maxf(
		STREAM_MIN_CHARACTERS_PER_SECOND,
		float(_stream_total_characters) / STREAM_MAX_DURATION_SECONDS,
	)


func _conversation_ended() -> bool:
	return (
		_mode == "player"
		and bool(_render_data.get("conversationEnded", false))
	)


func _reset_ended_presentation() -> void:
	_ended_presentation_conversation_id = ""
	_ended_notice_revealed = false
	_ended_dismiss_requested = false
	_ended_dismiss_elapsed = -1.0
	_end_notice_label = null


func _reveal_ended_notice() -> void:
	if not _conversation_ended() or _ended_notice_revealed:
		return
	_ended_notice_revealed = true
	_ended_dismiss_elapsed = 0.0
	if is_instance_valid(_end_notice_label):
		_end_notice_label.visible = true
	_scroll_to_latest()


func _update_ended_presentation(delta: float) -> void:
	if not _conversation_ended():
		_ended_dismiss_elapsed = -1.0
		return
	if _ended_dismiss_requested:
		return
	if not _stream_turn_key.is_empty():
		_ended_dismiss_elapsed = -1.0
		if is_instance_valid(_end_notice_label):
			_end_notice_label.visible = false
		return
	if not _ended_notice_revealed:
		_reveal_ended_notice()
		return
	_ended_dismiss_elapsed += maxf(0.0, delta)
	if _ended_dismiss_elapsed >= ENDED_AUTO_DISMISS_DELAY_SECONDS:
		_dismiss_ended_conversation()


func _dismiss_ended_conversation() -> void:
	if _ended_dismiss_requested:
		return
	_ended_dismiss_requested = true
	if not _request_action("dismissEnded", {}):
		_ended_dismiss_requested = false


func _apply_stream_progress() -> void:
	if _stream_turn_key.is_empty() or _stream_segments.is_empty():
		return
	var visible_total := int(floorf(_stream_visible_characters))
	for record: Dictionary in _stream_segments:
		var row := record.get("row") as Control
		var body := record.get("body") as Label
		var offset := int(record.get("offset", 0))
		var length := int(record.get("length", 0))
		var visible_count := clampi(visible_total - offset, 0, length)
		if is_instance_valid(row):
			row.visible = visible_count > 0
		if is_instance_valid(body):
			body.visible_characters = visible_count
		var narration_row := record.get("narrationRow") as Control
		if is_instance_valid(narration_row):
			narration_row.visible = (
				bool(record.get("showNarration", false))
				and visible_total >= _stream_total_characters
			)
	if visible_total < _stream_total_characters:
		return
	_stream_turn_key = ""
	_stream_visible_characters = float(_stream_total_characters)


func _add_status_line(copy: String, error_tone: bool) -> Label:
	var label := _label(
		copy,
		22,
		PageTheme.ERROR if error_tone else PageTheme.MUTED
	)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message_list.add_child(label)
	if error_tone:
		var retry := UiViewModel.action(_view_model, "retry")
		if UiViewModel.action_enabled(retry):
			var button := Button.new()
			button.text = "重试"
			button.custom_minimum_size = Vector2(120, 56)
			button.pressed.connect(_request_action.bind("retry", {}))
			_message_list.add_child(button)
	return label


func _render_composer() -> void:
	if _mode != "player":
		return
	var reply := UiViewModel.action(_view_model, "reply")
	var can_reply := UiViewModel.action_enabled(reply)
	_draft_edit.editable = can_reply
	var has_photo := not _selected_photo_ref.is_empty()
	_send_button.disabled = (
		not can_reply
		or (
			_draft_edit.text.strip_edges().is_empty()
			and not has_photo
		)
	)
	var can_attach := bool(_render_data.get("canAttachPhoto", false))
	_photo_button.disabled = not can_attach or not can_reply
	_photo_button.icon = _selected_photo_texture
	_photo_button.tooltip_text = (
		"取消已选照片"
		if has_photo
		else (
			"选择照片"
			if can_attach
			else "当前居民的模型不支持照片"
		)
	)
	_draft_edit.placeholder_text = (
		_photo_local_status
		if not _photo_local_status.is_empty()
		else (
			"照片已选，可补充说明"
			if has_photo
			else "输入消息…"
		)
	)
	var draft_characters := _draft_edit.text.length()
	var draft_lines := _draft_edit.text.split("\n", true).size()
	if _draft_limit_reached:
		_draft_limit_label.visible = true
		_draft_limit_label.text = "已到上限：280 字 / 3 行"
		_draft_limit_label.add_theme_color_override(
			"font_color",
			PageTheme.ERROR,
		)
	elif draft_characters >= 240 or draft_lines >= MAX_DRAFT_LINES:
		_draft_limit_label.visible = true
		_draft_limit_label.text = "%d / 280 字 · %d / 3 行" % [
			draft_characters,
			draft_lines,
		]
		_draft_limit_label.add_theme_color_override(
			"font_color",
			PageTheme.INK,
		)
	else:
		_draft_limit_label.visible = false
		_draft_limit_label.text = ""
		_draft_limit_label.add_theme_color_override(
			"font_color",
			PageTheme.MUTED,
		)


func _submit_reply() -> void:
	var say := _draft_edit.text.strip_edges()
	var has_photo := not _selected_photo_ref.is_empty()
	if say.is_empty() and not has_photo:
		return
	var payload := {
		"say": (
			"给你看一张照片。"
			if say.is_empty() and has_photo
			else say
		),
		"narration": (
			"旅行者展示了一张照片"
			if has_photo
			else "旅行者继续交谈"
		),
	}
	if has_photo:
		payload["photoRef"] = _selected_photo_ref
		payload["photoMimeType"] = _selected_photo_mime_type
	if not _request_action("reply", payload):
		_photo_local_status = (
			"照片发送失败，请重试"
			if has_photo
			else ""
		)
		_render_composer()
		return
	_restore_draft_focus_after_wait = true
	_draft_limit_reached = false
	_suppress_draft_change = true
	_draft_edit.text = ""
	_suppress_draft_change = false
	_clear_selected_photo(false)
	_render_composer()


func _request_action(action_key: String, payload: Dictionary) -> bool:
	var action := UiViewModel.action(_view_model, action_key)
	var intent := StringName(action.get("intent", ""))
	if intent == &"":
		action_blocked.emit(&"", "ACTION_NOT_DECLARED")
		return false
	if not UiViewModel.action_enabled(action):
		action_blocked.emit(
			intent,
			str(action.get("disabledReason", "ACTION_DISABLED"))
		)
		return false
	intent_requested.emit(intent, payload.duplicate(true))
	if _adapter != null and _adapter.has_method("dispatch"):
		var result := _adapter.call(
			"dispatch",
			String(intent),
			payload.duplicate(true),
		) as Dictionary
		return bool(result.get("ok", false))
	return true


func _on_close_pressed() -> void:
	request_back()


func _request_end_conversation() -> void:
	if _has_unsent_content():
		_close_confirmation.popup_centered()
		return
	_submit_end_conversation()


func _submit_end_conversation() -> void:
	_restore_draft_focus_after_wait = false
	_request_action("end", {"narration": "旅行者结束交谈"})


func _has_unsent_content() -> bool:
	return (
		not _draft_edit.text.strip_edges().is_empty()
		or not _selected_photo_ref.is_empty()
	)


func _close_spectator() -> void:
	if _request_action("closeSpectator", {}):
		close_requested.emit()


func _open_photo_dialog() -> void:
	if _photo_button.disabled:
		return
	if not _selected_photo_ref.is_empty():
		_clear_selected_photo(true)
		_render_composer()
		return
	_photo_local_status = ""
	_photo_local_error_code = ""
	_render_composer()
	_file_dialog.popup_centered_ratio(0.72)


func _on_photo_selected(path: String) -> void:
	if (
		_adapter == null
		or not _adapter.has_method("prepare_conversation_photo")
	):
		_photo_local_error_code = "PHOTO_INTERFACE_MISSING"
		_photo_local_status = _photo_error_copy(_photo_local_error_code)
		_render_composer()
		return
	var result := _adapter.call(
		"prepare_conversation_photo",
		path,
	) as Dictionary
	if not bool(result.get("ok", false)):
		_photo_local_error_code = str(
			result.get("errorCode", "PHOTO_READ_FAILED")
		)
		_photo_local_status = _photo_error_copy(_photo_local_error_code)
		_render_composer()
		return
	var preview := result.get("previewImage") as Image
	if preview == null or preview.is_empty():
		_photo_local_error_code = "PHOTO_PREVIEW_FAILED"
		_photo_local_status = _photo_error_copy(_photo_local_error_code)
		var staged_ref := str(result.get("ref", ""))
		var staged_owner := str(result.get("residentId", ""))
		if (
			not staged_ref.is_empty()
			and not staged_owner.is_empty()
			and _adapter.has_method("discard_conversation_photo")
		):
			_adapter.call(
				"discard_conversation_photo",
				staged_ref,
				staged_owner,
			)
		_render_composer()
		return
	_selected_photo_ref = str(result.get("ref", ""))
	_selected_photo_mime_type = str(result.get("mimeType", ""))
	_selected_photo_owner_id = str(result.get("residentId", ""))
	_selected_photo_texture = ImageTexture.create_from_image(preview)
	_photo_local_status = ""
	_photo_local_error_code = ""
	_render_composer()


func _on_photo_selection_canceled() -> void:
	# Native picker cancellation intentionally preserves the existing draft and
	# any already staged photo.
	_render_composer()


func _clear_selected_photo(release_staged: bool) -> void:
	if (
		release_staged
		and not _selected_photo_ref.is_empty()
		and not _selected_photo_owner_id.is_empty()
		and _adapter != null
		and _adapter.has_method("discard_conversation_photo")
	):
		_adapter.call(
			"discard_conversation_photo",
			_selected_photo_ref,
			_selected_photo_owner_id,
		)
	_selected_photo_ref = ""
	_selected_photo_mime_type = ""
	_selected_photo_owner_id = ""
	_selected_photo_texture = null
	_photo_local_status = ""
	_photo_local_error_code = ""


func _photo_error_copy(error_code: String) -> String:
	match error_code:
		"PHOTO_PERMISSION_DENIED":
			return "需要照片权限，请授权后重选"
		"PHOTO_FILE_TOO_LARGE":
			return "照片过大，请选择 10MB 内图片"
		"PHOTO_FORMAT_UNSUPPORTED", "PHOTO_DECODE_FAILED":
			return "格式不支持，请选择 PNG/JPEG/WebP"
		"PHOTO_DIMENSIONS_UNSUPPORTED":
			return "照片尺寸过大，请换一张"
		"PHOTO_CAPABILITY_UNAVAILABLE":
			return "当前居民的模型不支持照片"
		"PHOTO_INTERFACE_MISSING":
			return "照片接口暂不可用"
		_:
			return "照片读取失败，请重新选择"


func _on_draft_changed() -> void:
	if _suppress_draft_change:
		return
	var raw_text := _draft_edit.text
	var normalized := raw_text.left(MAX_DRAFT_CHARACTERS)
	var lines := normalized.split("\n", true)
	_draft_limit_reached = (
		raw_text.length() > MAX_DRAFT_CHARACTERS
		or lines.size() > MAX_DRAFT_LINES
	)
	if lines.size() > MAX_DRAFT_LINES:
		normalized = "\n".join(lines.slice(0, MAX_DRAFT_LINES))
	if normalized != _draft_edit.text:
		var caret_line := _draft_edit.get_caret_line()
		var caret_column := _draft_edit.get_caret_column()
		_suppress_draft_change = true
		_draft_edit.text = normalized
		_draft_edit.set_caret_line(mini(caret_line, MAX_DRAFT_LINES - 1))
		_draft_edit.set_caret_column(
			mini(caret_column, _draft_edit.get_line(_draft_edit.get_caret_line()).length())
		)
		_suppress_draft_change = false
	_render_composer()


func _on_draft_gui_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if (
		not key_event.pressed
		or key_event.echo
		or key_event.shift_pressed
		or _draft_edit.has_ime_text()
		or (
			key_event.keycode != KEY_ENTER
			and key_event.keycode != KEY_KP_ENTER
		)
	):
		return
	_draft_edit.accept_event()
	_submit_reply()


func _focus_draft_after_reply(conversation_id: String) -> void:
	if (
		not is_inside_tree()
		or not is_visible_in_tree()
		or _mode != "player"
		or _conversation_ended()
		or _resident_waiting()
		or str(_render_data.get("conversationId", "")) != conversation_id
		or not _draft_edit.visible
		or not _draft_edit.editable
		or (
			is_instance_valid(_close_confirmation)
			and _close_confirmation.visible
		)
	):
		return
	_draft_edit.grab_focus()


func _refresh_from_adapter() -> void:
	if _adapter == null or not _adapter.has_method("get_view_model"):
		return
	var candidate: Variant = _adapter.call("get_view_model", String(SCOPE))
	if candidate is Dictionary:
		apply_view_model(candidate as Dictionary)


func _on_view_model_changed(scope: String, view_model: Dictionary) -> void:
	if scope == String(SCOPE):
		apply_view_model(view_model)


func _disconnect_adapter() -> void:
	UI_SIGNALS.disconnect_view_model(
		_adapter,
		Callable(self, "_on_view_model_changed"),
	)


func _apply_layout() -> void:
	if _stage == null:
		return
	var viewport := get_viewport_rect().size
	var scale_factor := minf(
		1.0,
		minf(
			maxf(0.01, (viewport.x - 32.0) / BASE_SIZE.x),
			maxf(0.01, (viewport.y - 32.0) / BASE_SIZE.y),
		),
	)
	_stage.scale = Vector2.ONE * scale_factor
	_stage.position = Vector2(
		floorf(viewport.x - BASE_SIZE.x * scale_factor - 16.0),
		floorf((viewport.y - BASE_SIZE.y * scale_factor) * 0.5),
	)


func _scroll_to_latest() -> void:
	if (
		not _history_auto_follow_latest
		or not is_instance_valid(_history_scroll)
	):
		return
	_scroll_request_generation += 1
	call_deferred(
		"_scroll_to_latest_after_layout",
		_scroll_request_generation
	)


func _scroll_to_latest_after_layout(generation: int) -> void:
	if (
		generation != _scroll_request_generation
		or not _history_auto_follow_latest
		or not is_instance_valid(_history_scroll)
	):
		return
	call_deferred("_scroll_to_latest_now", generation)


func _scroll_to_latest_now(generation: int) -> void:
	if (
		generation != _scroll_request_generation
		or not _history_auto_follow_latest
		or not is_instance_valid(_history_scroll)
	):
		return
	var bar := _history_scroll.get_v_scroll_bar()
	_history_scroll.scroll_vertical = int(maxf(
		0.0,
		bar.max_value - bar.page,
	))


func _on_history_scroll_changed(_value: float) -> void:
	var follow_latest := _history_is_near_bottom()
	if _history_auto_follow_latest and not follow_latest:
		_scroll_request_generation += 1
	_history_auto_follow_latest = follow_latest


func _history_is_near_bottom() -> bool:
	if not is_instance_valid(_history_scroll):
		return true
	var bar := _history_scroll.get_v_scroll_bar()
	var bottom := maxf(0.0, bar.max_value - bar.page)
	return (
		bottom - float(_history_scroll.scroll_vertical)
		<= HISTORY_BOTTOM_TOLERANCE
	)


func _reset_history_auto_follow() -> void:
	_history_auto_follow_latest = true
	_scroll_request_generation += 1


func _selected_spectator_conversation() -> Dictionary:
	var spectator := _render_data.get("spectator", {}) as Dictionary
	var selected: Variant = spectator.get("selectedConversation", {})
	return (selected as Dictionary).duplicate(true) if selected is Dictionary else {}


func _message_render_signature() -> String:
	var parts: Array[String] = []
	for value: Variant in _render_messages():
		if not value is Dictionary:
			continue
		var message := value as Dictionary
		parts.append("%s|%s|%s|%s" % [
			str(message.get("turnId", 0)),
			str(message.get("speaker", "")),
			str(message.get("say", "")),
			str(message.get("narration", "")),
		])
	var error_value: Variant = _view_model.get("error", {})
	parts.append("waiting=%s" % _resident_waiting())
	parts.append("error=%s" % str(error_value))
	parts.append("ended=%s" % _conversation_ended())
	parts.append("notice=%s" % str(_render_data.get("endNotice", "")))
	parts.append("mode=%s" % _mode)
	return "\n".join(parts)


func _render_messages() -> Array:
	var messages := _render_data.get("messages", []) as Array
	if _mode != "spectator":
		return messages
	var selected_messages := (
		_selected_spectator_conversation().get("messages", []) as Array
	)
	return selected_messages if not selected_messages.is_empty() else messages


func _latest_message_turn_key() -> String:
	var messages := _render_messages()
	for index: int in range(messages.size() - 1, -1, -1):
		var value: Variant = messages[index]
		if value is Dictionary:
			return _turn_key(value as Dictionary)
	return ""


func _turn_key(message: Dictionary) -> String:
	for field_name: String in ["turnId", "turn_id", "decisionId", "decision_id"]:
		if message.has(field_name):
			return str(message.get(field_name))
	return ""


func _participant(participants: Array, index: int) -> Dictionary:
	if index < participants.size() and participants[index] is Dictionary:
		return (participants[index] as Dictionary).duplicate(true)
	return {}


func _message_is_resident_side(message: Dictionary, index: int) -> bool:
	if _mode == "player":
		var resident_name := str(_render_data.get("residentName", ""))
		var resident_id := str(_render_data.get("residentId", ""))
		return (
			str(message.get("speaker", "")) == resident_name
			or (
				not resident_id.is_empty()
				and str(message.get("speakerId", "")) == resident_id
			)
		)
	var participants := _selected_spectator_conversation().get("participants", []) as Array
	var left := _participant(participants, 0)
	var left_id := str(left.get("residentId", ""))
	var left_name := str(left.get("residentName", ""))
	if not left_id.is_empty() and str(message.get("speakerId", "")) == left_id:
		return true
	if not left_name.is_empty() and str(message.get("speaker", "")) == left_name:
		return true
	return index % 2 == 0


func _resident_waiting() -> bool:
	var waiting := _render_data.get("waitingFor", []) as Array
	if _mode == "spectator":
		# Spectator mode is a read-only record of the residents' exchange.
		# It must not invent a player-facing "thinking" state between turns.
		return false
	var resident_name := str(_render_data.get("residentName", ""))
	var resident_id := str(_render_data.get("residentId", ""))
	return (
		waiting.has(resident_name)
		or (not resident_id.is_empty() and waiting.has(resident_id))
	)


func _add_message_photos(stack: VBoxContainer, photos: Array) -> void:
	for photo_value: Variant in photos:
		if not photo_value is Dictionary:
			continue
		var photo := photo_value as Dictionary
		var ref := str(photo.get("ref", "")).strip_edges()
		var mime_type := str(photo.get("mime_type", "")).strip_edges()
		if ref.is_empty() or mime_type.is_empty():
			continue
		var texture := _conversation_photo_texture(ref, mime_type)
		if texture == null:
			var unavailable := _label(
				"照片暂时无法显示",
				PageTheme.NARRATION_FONT_SIZE,
				PageTheme.MUTED,
			)
			unavailable.name = "ConversationPhotoUnavailable"
			stack.add_child(unavailable)
			continue
		var preview := TextureRect.new()
		preview.name = "ConversationPhotoPreview"
		preview.custom_minimum_size = Vector2(280, 180)
		preview.texture = texture
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(preview)


func _conversation_photo_texture(
	ref: String,
	mime_type: String,
) -> ImageTexture:
	var cache_key := "%s|%s" % [ref, mime_type]
	var cached: Variant = _conversation_photo_textures.get(cache_key)
	if cached is ImageTexture:
		return cached as ImageTexture
	if (
		_adapter == null
		or not _adapter.has_method("resolve_conversation_photo_preview")
	):
		return null
	var resolved := _adapter.call(
		"resolve_conversation_photo_preview",
		ref,
		mime_type,
	) as Dictionary
	if not bool(resolved.get("ok", false)):
		return null
	var image := resolved.get("previewImage") as Image
	if image == null or image.is_empty():
		return null
	var texture := ImageTexture.create_from_image(image)
	_conversation_photo_textures[cache_key] = texture
	return texture


func _create_image_bubble(
	resident_side: bool,
	minimum_width: float,
	minimum_height: float,
) -> Dictionary:
	var cluster := HBoxContainer.new()
	cluster.name = (
		"ResidentImageBubble"
		if resident_side
		else "PlayerImageBubble"
	)
	cluster.add_theme_constant_override("separation", -BUBBLE_TAIL_OVERLAP)
	cluster.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := PanelContainer.new()
	panel.theme_type_variation = (
		&"UnifiedResidentBubble"
		if resident_side
		else &"UnifiedPlayerBubble"
	)
	panel.custom_minimum_size = Vector2(
		maxf(1.0, minimum_width - 10.0),
		minimum_height,
	)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tail_center := CenterContainer.new()
	tail_center.name = "UniqueBubbleTailOwner"
	tail_center.custom_minimum_size.x = 18
	tail_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tail_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tail := TextureRect.new()
	tail.name = "UniqueBubbleTail"
	tail.add_to_group("unified_conversation_unique_bubble_tail")
	tail.texture = PageTheme.bubble_tail_texture(resident_side)
	tail.custom_minimum_size = (
		Vector2(18, 57)
		if resident_side
		else Vector2(18, 40)
	)
	tail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tail.stretch_mode = TextureRect.STRETCH_KEEP
	tail.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tail_center.add_child(tail)

	if resident_side:
		cluster.add_child(tail_center)
		cluster.add_child(panel)
	else:
		cluster.add_child(panel)
		cluster.add_child(tail_center)
	return {
		"cluster": cluster,
		"panel": panel,
		"tail": tail,
	}


func _bubble_width(copy: String, identity_copy: String = "") -> float:
	var conversation_font := PageTheme.conversation_font(theme)
	var copy_width := 0.0
	var identity_width := 0.0
	if conversation_font != null:
		copy_width = conversation_font.get_string_size(
			copy,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			PageTheme.BODY_FONT_SIZE,
		).x
		identity_width = conversation_font.get_string_size(
			identity_copy,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			PageTheme.SPEAKER_FONT_SIZE,
		).x
	else:
		copy_width = float(copy.length() * PageTheme.BODY_FONT_SIZE)
		identity_width = float(
			identity_copy.length() * PageTheme.SPEAKER_FONT_SIZE
		)
	# A line only slightly wider than the maximum used to wrap as “full line +
	# one character”. Use the width of evenly distributed wrapped lines so the
	# final visible line cannot collapse into a one-character tail.
	if copy_width > BUBBLE_MAX_TEXT_WIDTH:
		var wrapped_line_count := int(ceil(
			copy_width / BUBBLE_MAX_TEXT_WIDTH
		))
		copy_width = ceil(copy_width / float(wrapped_line_count))
	var measured_text_width := maxf(copy_width, identity_width)
	return clampf(
		measured_text_width + 52.0,
		BUBBLE_MIN_TEXT_WIDTH + 52.0,
		BUBBLE_MAX_TEXT_WIDTH + 52.0,
	)


func _label(copy: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = copy
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _error_copy(error: Dictionary) -> String:
	var code := str(error.get("code", "CONVERSATION_FAILED"))
	var retryable := bool(error.get("retryable", false))
	match code:
		"PROVIDER_API_KEY_REQUIRED", "AGENT_PROVIDER_NOT_CONFIGURED":
			return "这位居民还没有配置可用的聊天模型。"
		"AGENT_RESPONSE_TIMEOUT":
			return (
				"居民暂时没有回应，可以稍后重试。"
				if retryable
				else "居民暂时没有回应。"
			)
		"AGENT_DECISION_REQUEST_FAILED":
			return (
				"这位居民这次没有成功回应，可以重试。"
				if retryable
				else "这位居民这次没有成功回应。"
			)
		"PROVIDER_REQUEST_FAILED":
			return (
				"聊天连接暂时不稳定，可以重试。"
				if retryable
				else "聊天连接当前不可用。"
			)
		"PHOTO_CAPABILITY_UNAVAILABLE":
			return "这位居民当前无法查看照片。"
		"PHOTO_REF_NOT_STAGED", "PHOTO_PAYLOAD_INVALID":
			return "照片没有发送成功，请重新选择。"
		"TARGET_NOT_NEARBY":
			return "你离这位居民太远了，请靠近后再聊天。"
		"AGENT_NOT_CONNECTED":
			return "这位居民现在无法聊天，请稍后再试。"
		_:
			return (
				"聊天暂时没有成功，可以稍后重试。"
				if retryable
				else "聊天暂时没有成功。"
			)
