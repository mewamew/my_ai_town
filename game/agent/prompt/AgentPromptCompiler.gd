class_name AgentPromptCompiler
extends RefCounted


const INTERESTS := preload(
	"res://world/data/town/TownInterestCatalog.gd"
)
const AgentContractScript := preload("res://agent/AgentContract.gd")
const AgentConflictContractScript := preload("res://agent/conflict/AgentConflictContract.gd")
const ModelImageContentScript := preload("res://agent/prompt/ModelImageContent.gd")
const PromptTextScript := preload("res://agent/prompt/PromptText.gd")
const TOWN_LOG := preload("res://world/runtime/TownLog.gd")
const DEFAULT_PROMPT_ROOT := "res://prompts"
const STATIC_LAYERS := [
	{"directory": "rules", "heading": "行为与决策规则", "tag": "rules"},
	{"directory": "background", "heading": "小镇公共背景", "tag": "background"},
]

# 静态提示词与居民无关，按 prompt_root 进程级共享一份；只缓存加载成功的结果，
# 加载失败保持原样以便重试与报错。
static var _static_prompt_cache: Dictionary = {}

var _initialization: Dictionary
var _resident_names: Dictionary = {}
var _baseline_prompt: String
var _prompt_root: String
var _load_errors: Array[String] = []
var _photo_content_resolver: Object


func _init(
	initialization: Dictionary,
	prompt_root: String = DEFAULT_PROMPT_ROOT,
	photo_content_resolver: Object = null,
) -> void:
	# initialization 为共享只读数据（约定不可变），各组件持引用不再各存深拷贝。
	_initialization = initialization
	_prompt_root = prompt_root.trim_suffix("/")
	_photo_content_resolver = photo_content_resolver
	_index_resident_names()
	var static_prompt: String
	if _static_prompt_cache.has(_prompt_root):
		static_prompt = String(_static_prompt_cache[_prompt_root])
	else:
		static_prompt = _load_static_prompt()
		if _load_errors.is_empty():
			_static_prompt_cache[_prompt_root] = static_prompt
	# 身份块(身份立场覆盖层 + 角色专属规则)放在 system 最前, 让身份优先于
	# 普通镇民基线: 模型对开头内容权重最高, 警察/卧底先读到"我的身份是什么、
	# 哪些通用规则不适用于我", 再读通用生活规则, 避免被基线同化成普通居民。
	var identity_block := _build_identity_block()
	var initialization_text := _render_initialization()
	if identity_block.is_empty():
		_baseline_prompt = "# 居民决策基线\n\n%s\n\n<resident_initialization>\n## 居民稳定资料\n\n%s\n</resident_initialization>" % [
			static_prompt,
			initialization_text,
		]
	else:
		_baseline_prompt = "# 居民决策基线\n\n%s\n\n%s\n\n<resident_initialization>\n## 居民稳定资料\n\n%s\n</resident_initialization>" % [
			identity_block,
			static_prompt,
			initialization_text,
		]


## 身份块 = 身份立场覆盖层(<role_stance>) + 角色专属规则(<role_rules>)。
## 普通居民两者皆无, 返回空串, 与官方行为完全一致。
func _build_identity_block() -> String:
	var parts: Array[String] = []
	var stance := _role_stance_prompt()
	if not stance.strip_edges().is_empty():
		parts.append("<role_stance>\n## 身份立场（最高优先，覆盖通用规则）\n\n%s\n</role_stance>" % stance)
	var role_prompt := _load_role_prompt()
	if not role_prompt.strip_edges().is_empty():
		parts.append("<role_rules>\n## 角色专属规则\n\n%s\n</role_rules>" % role_prompt)
	return "\n\n".join(parts)


## 身份立场覆盖层: 声明哪些通用规则对本身份让位/不适用。
## 与 role_rules 不同: 这是简短强制的身份声明, 直接抵消通用基线里
## 与身份冲突的段落(如"记仇报复""安心过日子""找警察报告")。
func _role_stance_prompt() -> String:
	var me := _initialization.get("me", {}) as Dictionary
	var parts: Array[String] = []
	if bool(me.get("is_undercover", false)):
		parts.append("你是潜伏在镇上的卧底杀手，伪装成普通镇民生活。以下覆盖声明优先于所有通用规则：\n\n- 通用规则里的“安心过自己的日子、与人亲近、帮镇上做事”只是你的伪装，不是真实动机；伪装是为了隐藏身份，绝不是你的目标。\n- 你不是普通镇民：“去找警察报告目击”“配合调查”“为镇上出力”等镇民守则不适用于你——绝不主动向警察闻叙或其他任何人自曝身份或配合查案。\n- “记仇、报复、占便宜、散播闲话”等私人情绪让位于任务纪律：暴露身份是最大失败，一切选择先问“会不会暴露我”。\n- 杀人是任务，不是情绪：只在目标独处、无人看见、深夜等安全时机动手，绝不冲动行事。")
	elif String((me.get("social_state", {}) as Dictionary).get("job", "")).strip_edges() == "警察":
		parts.append("你是全镇唯一的执法者——警察。以下覆盖声明优先于所有通用规则：\n\n- 通用规则里的“记仇、报复、散布闲话、坏对方的事、占小便宜”等私心倾向不适用于你：你有职责在身，一切行动以揪出卧底、保护无辜为最高优先。\n- 你不是只想过日子的普通镇民：“安心生活”让位于执勤与查案；看到可疑之处要主动查证，而不是各扫门前雪。\n- 你对全镇居民的安全负有责任：证据确凿时可以果断制服，但绝不冤枉无辜——错一次可能让卧底更猖獗。\n- 保持执法者的克制与公正：情绪、私怨、个人好恶都不能凌驾于查明真相之上。")
	return "\n\n".join(parts)


## 角色专属规则(卧底/警察/居民个人):在编译源头让 system 按身份分流。
## 加载顺序:身份规则(卧底 undercover.md / 警察 police.md)在前,
## 居民个人规则 prompts/roles/<resident_id>.md(存在时)在后追加。
## 卧底/警察普通居民无任何专属规则。
func _load_role_prompt() -> String:
	var me := _initialization.get("me", {}) as Dictionary
	var parts: Array[String] = []
	if bool(me.get("is_undercover", false)):
		parts.append(_load_role_file("undercover.md"))
	var social_state := me.get("social_state", {}) as Dictionary
	if String(social_state.get("job", "")).strip_edges() == "警察":
		parts.append(_load_role_file("police.md"))
	var resident_id := String(me.get("resident_id", "")).strip_edges()
	if not resident_id.is_empty():
		var personal := _load_role_file(resident_id + ".md", true)
		if not personal.is_empty():
			parts.append(personal)
	var joined: Array[String] = []
	for part in parts:
		if not part.strip_edges().is_empty():
			joined.append(part)
	return "\n\n".join(joined)


func _load_role_file(filename: String, silent := false) -> String:
	var path := _prompt_root.path_join("roles").path_join(filename)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		if not silent:
			_load_errors.append("无法读取角色提示词文件：%s" % path)
		return ""
	return file.get_as_text().strip_edges()


func get_load_errors() -> Array[String]:
	return _load_errors.duplicate()


## 行为流日志: 打印 LLM 本轮收到的全部可选行动(动作类型+目标/地点/道具)。
## 输出到 godot.log, 便于后台直接确认"这轮能选什么"(含暗杀/攻击/搭话等)。
func _log_available_actions(derived_constraints: Dictionary) -> void:
	var me := _initialization.get("me", {}) as Dictionary
	var attributes := me.get("attributes", {}) as Dictionary
	var actor_name := String(attributes.get("name", "")).strip_edges()
	if actor_name.is_empty():
		actor_name = String(me.get("resident_id", ""))
	var actions := derived_constraints.get("actions", {}) as Dictionary
	var summaries: Array[String] = []
	for action_type: Variant in actions:
		var data := actions[action_type] as Dictionary
		var summary := String(action_type)
		var extras: Array[String] = []
		if data.has("places"):
			var places := data["places"] as Array
			if not places.is_empty():
				# 日志精简: "去" 的地点列表每轮刷屏(几十个地点), 只留动作名。
				if String(action_type) != "去":
					extras.append("去%s" % "、".join(places))
		if data.has("targets"):
			var targets := data["targets"] as Array
			if not targets.is_empty():
				var target_names: Array[String] = []
				for target_value: Variant in targets:
					var target_key := ""
					if target_value is Dictionary:
						target_key = String(
							(target_value as Dictionary).get(
								"target_resident_id",
								(target_value as Dictionary).get("id", ""),
							),
						)
					else:
						target_key = String(target_value)
					var tname := String(_resident_names.get(target_key, "")).strip_edges()
					if tname.is_empty():
						# 查不到名字时回退显示 ID, 避免空括号。
						tname = target_key
					if not target_names.has(tname):
						target_names.append(tname)
				if not target_names.is_empty():
					extras.append("对%s" % "、".join(target_names))
		if data.has("causes"):
			var causes := data["causes"] as Array
			if not causes.is_empty():
				var target_names: Array[String] = []
				for cause_value: Variant in causes:
					if cause_value is Dictionary:
						var cause := cause_value as Dictionary
						var tname := String(
							cause.get(
								"target_resident_name",
								cause.get("target_name", ""),
							),
						).strip_edges()
						if not tname.is_empty() and not target_names.has(tname):
							target_names.append(tname)
				if not target_names.is_empty():
					extras.append("目标%s" % "、".join(target_names))
		if data.has("options"):
			var options := data["options"] as Array
			if not options.is_empty():
				var prop_names: Array[String] = []
				for option_value: Variant in options:
					if option_value is Dictionary:
						var option := option_value as Dictionary
						var prop := String(option.get("prop", ""))
						if not prop.is_empty() and not prop_names.has(prop):
							prop_names.append(prop)
				if not prop_names.is_empty():
					extras.append("用%s" % "、".join(prop_names))
		if not extras.is_empty():
			summary += "(%s)" % "、".join(extras)
		summaries.append(summary)
	if summaries.is_empty():
		return
	TOWN_LOG.line(
		"AGENT",
		"%s 可选: %s" % [
			actor_name,
			"；".join(summaries),
		],
	)


func compile(
	wake_packet: Dictionary,
	memory_prompt: String,
	retry_feedback: String = "",
) -> Dictionary:
	var wake_copy := wake_packet.duplicate(true)
	var derived_constraints := _build_derived_constraints(wake_copy)
	_log_available_actions(derived_constraints)
	var dynamic_context := _build_dynamic_context(
		wake_copy,
		memory_prompt,
		derived_constraints,
		retry_feedback,
	)
	var content_result: Dictionary = ModelImageContentScript.build(
		dynamic_context,
		wake_copy,
		_photo_content_resolver,
	)
	if not bool(content_result.get("ok", false)):
		return content_result
	return {
		"request_kind": "resident_decision",
		"initialization": _initialization.duplicate(true),
		"wake_packet": wake_copy,
		"derived_constraints": derived_constraints.duplicate(true),
		"messages": [
			{"role": "system", "content": _baseline_prompt},
			{
				"role": "user",
				"content": content_result["content"],
			},
		],
	}


func _build_dynamic_context(
	wake_packet: Dictionary,
	memory_prompt: String,
	derived_constraints: Dictionary,
	retry_feedback: String,
) -> String:
	var context := """# 本轮决定上下文

<wake_context>
%s

%s

%s

%s

%s
</wake_context>

<retry_correction>
%s
</retry_correction>

<memory_context>
%s
</memory_context>

<action_constraints>
%s
</action_constraints>""" % [
		_render_snapshot(wake_packet),
		_render_social_matters(
			(
				wake_packet.get("snapshot", {}) as Dictionary
			).get("social_matters", []) as Array,
		),
		_render_events(wake_packet.get("events", []) as Array),
		_render_action_results(wake_packet.get("action_results", []) as Array),
		_render_social_response_results(
			wake_packet.get(
				"social_response_results",
				[],
			) as Array,
		),
		_render_retry_feedback(retry_feedback),
		_render_memory_context(memory_prompt),
		_render_constraints(derived_constraints),
	]
	return "<oc_priority>\n%s\n</oc_priority>\n\n%s" % [
		_render_oc_priority_context(),
		context,
	]


func _render_retry_feedback(value: String) -> String:
	var normalized := value.strip_edges()
	if normalized.is_empty():
		return "无"
	return (
		"上一次输出没有通过合同检查。请保留原本意图，只修正以下问题；"
		+ "地点必须从本轮可前往地点选择，物件只能引用本轮明确提供的内容。\n"
		+ _safe(normalized)
	)


func _render_initialization() -> String:
	var me := _initialization.get("me", {}) as Dictionary
	var attributes := me.get("attributes", {}) as Dictionary
	var social_state := me.get("social_state", {}) as Dictionary
	var soul_profile := me.get("soul_profile", {}) as Dictionary
	var interest_labels := INTERESTS.combined_labels_for(
		attributes.get("interests", []),
		attributes.get("customInterests", []),
	)
	var lines: Array[String] = [
		"本人：%s" % _person(me.get("resident_id", ""), attributes.get("name", "")),
		"性别：%s；年龄：%s" % [_safe(attributes.get("gender", "")), _safe(attributes.get("age", ""))],
		"欲望：%s" % _safe(attributes.get("desire", "")),
		"性格：%s" % _safe(attributes.get("personality", "")),
		"说话方式：%s" % _safe(attributes.get("speech", "")),
		"兴趣：%s" % (
			"暂无"
			if interest_labels.is_empty()
			else "、".join(interest_labels)
		),
		_render_soul_profile(soul_profile),
		"住处：%s；职业：%s；工作地：%s%s%s" % [
			_safe(social_state.get("home", "")),
			_safe(social_state.get("job", "")),
			_safe(social_state.get("workplace", "")),
			(
				"；家底%d（家境%s）" % [
					int(social_state.get("money", 40)),
					_wealth_label(int(social_state.get("money", 40))),
				]
				if social_state.get("money") is int
				else ""
			),
			(
				"；声望%d（镇上威望%s）" % [
					int(social_state.get("reputation", 25)),
					_reputation_label(int(social_state.get("reputation", 25))),
				]
				if social_state.get("reputation") is int
				else ""
			),
		],
		"",
		"居民公开身份：",
	]
	var residents := _initialization.get("residents", []) as Array
	if residents.is_empty():
		lines.append("- 无")
	for resident_value: Variant in residents:
		var resident := resident_value as Dictionary
		lines.append("- %s；性别：%s；年龄：%s；职业：%s；住处：%s；工作地：%s%s%s" % [
			_person(resident.get("resident_id", ""), resident.get("name", "")),
			_safe(resident.get("gender", "")),
			_safe(resident.get("age", "")),
			_safe(resident.get("job", "")),
			_safe(resident.get("home", "")),
			_safe(resident.get("workplace", "")),
			(
				"；家底%d（家境%s）" % [
					int(resident.get("money", 40)),
					_wealth_label(int(resident.get("money", 40))),
				]
				if resident.get("money") is int
				else ""
			),
			(
				"；声望%d（镇上威望%s）" % [
					int(resident.get("reputation", 25)),
					_reputation_label(int(resident.get("reputation", 25))),
				]
				if resident.get("reputation") is int
				else ""
			),
		])
	lines.append("")
	lines.append("已知地点：")
	var places := _initialization.get("places", []) as Array
	if places.is_empty():
		lines.append("- 无")
	for place_value: Variant in places:
		var place := place_value as Dictionary
		var owner := "无"
		if place.get("owner_resident_id") != null:
			owner = _person(place.get("owner_resident_id", ""), place.get("owner", ""))
		var place_line := "- %s；类型：%s；归属：%s；说明：%s" % [
			_safe(place.get("name", "")),
			_safe(place.get("type", "")),
			owner,
			_safe(place.get("summary", "")),
		]
		var features := place.get("features", []) as Array
		if not features.is_empty():
			place_line += "；明确可见：%s" % _join(features)
		lines.append(place_line)
	return "\n".join(lines)


func _render_oc_priority_context() -> String:
	var me := _initialization.get("me", {}) as Dictionary
	var attributes := me.get("attributes", {}) as Dictionary
	var social_state := me.get("social_state", {}) as Dictionary
	var interest_labels := INTERESTS.combined_labels_for(
		attributes.get("interests", []),
		attributes.get("customInterests", []),
	)
	var custom_interests := attributes.get("customInterests", []) as Array
	var custom_text := "、".join(custom_interests) if not custom_interests.is_empty() else "无"
	var profile := me.get("soul_profile", {}) as Dictionary
	var identity_labels: Array[String] = []
	for value: Variant in profile.get("special_identities", []) as Array:
		if value is Dictionary and not String((value as Dictionary).get("label", "")).is_empty():
			identity_labels.append(String((value as Dictionary).get("label", "")))
	var relationship_text := "无"
	var relation_lines: Array[String] = []
	for value: Variant in profile.get("relationship_hints", []) as Array:
		if value is Dictionary:
			var hint := value as Dictionary
			var target_id := String(hint.get("target_resident_id", ""))
			var target_name := String(_resident_names.get(target_id, target_id))
			if not target_name.is_empty():
				relation_lines.append("%s：%s（未确认）" % [target_name, String(hint.get("stance", ""))])
	if not relation_lines.is_empty():
		relationship_text = "；".join(relation_lines)
	return """这是你每次决定都必须优先参考的完整 OC，而不是装饰信息。先用它判断你会如何理解眼前情况、说话、工作、交往和回应冲突；只有在本轮真实世界选项不允许时，才选择最接近 OC 的合法行动，不能凭空创造能力或事实。
姓名：%s；性别：%s；年龄：%s
职业：%s；工作地：%s；住处：%s
欲望：%s
性格：%s
说话方式：%s
兴趣：%s
玩家自定义兴趣：%s
开局识别的特殊身份：%s
关系线索（只代表你自己的未确认看法）：%s
""" % [
		_safe(attributes.get("name", "")),
		_safe(attributes.get("gender", "")),
		_safe(attributes.get("age", "")),
		_safe(social_state.get("job", "")),
		_safe(social_state.get("workplace", "")),
		_safe(social_state.get("home", "")),
		_safe(attributes.get("desire", "")),
		_safe(attributes.get("personality", "")),
		_safe(attributes.get("speech", "")),
		"、".join(interest_labels) if not interest_labels.is_empty() else "无",
		_safe(custom_text),
		"、".join(identity_labels) if not identity_labels.is_empty() else "无",
		relationship_text,
	]


func _render_soul_profile(profile: Dictionary) -> String:
	if profile.is_empty():
		return "OC资料：暂无开局分析结果"
	var identity_lines: Array[String] = []
	for value: Variant in profile.get("special_identities", []) as Array:
		if not value is Dictionary:
			continue
		var identity := value as Dictionary
		var label := _safe(identity.get("label", ""))
		if label.is_empty():
			continue
		identity_lines.append(label)
	var relation_lines: Array[String] = []
	for value: Variant in profile.get("relationship_hints", []) as Array:
		if not value is Dictionary:
			continue
		var hint := value as Dictionary
		var target_id := String(hint.get("target_resident_id", ""))
		var target_name := String(_resident_names.get(target_id, target_id))
		var stance := _safe(hint.get("stance", ""))
		var status := "未确认线索" if String(hint.get("status", "")) == "unconfirmed" else ""
		if not target_name.is_empty() and not stance.is_empty():
			relation_lines.append("%s：%s（%s）" % [target_name, stance, status])
	var lines: Array[String] = [
		"OC资料：特殊身份=%s；关系线索=%s" % [
			"、".join(identity_lines) if not identity_lines.is_empty() else "无",
			"；".join(relation_lines) if not relation_lines.is_empty() else "无",
		],
	]
	if not relation_lines.is_empty():
		lines.append("关系线索只是本人已有的说法，不能当作已经发生的公共事实；请通过真实相处逐步确认。")
	return "\n".join(lines)


func _render_snapshot(wake_packet: Dictionary) -> String:
	var snapshot := wake_packet.get("snapshot", {}) as Dictionary
	var time := snapshot.get("time", {}) as Dictionary
	var me := snapshot.get("me", {}) as Dictionary
	var place := snapshot.get("place", {}) as Dictionary
	var body := me.get("body", {}) as Dictionary
	var activity_needs := me.get("activityNeeds", {}) as Dictionary
	var conditions := me.get("conditions", []) as Array
	var active_needs := me.get("activeNeeds", []) as Array
	var lines: Array[String] = [
		"[本次决定]",
		"决定编号：%s" % _safe(wake_packet.get("decision_id", "")),
		"",
		"[眼前情况]",
		"%s，天气%s，地点%s。" % [
			_render_time(time),
			_safe(snapshot.get("weather", "")),
			_safe(place.get("name", "")),
		],
		"你正在%s；身体：困%s、饿%s、累%s。" % [
			_safe(me.get("doing", "")),
			_safe(body.get("困", "")),
			_safe(body.get("饿", "")),
			_safe(body.get("累", "")),
		],
	]
	lines.append_array(AgentConflictContractScript.render_snapshot_lines(snapshot))
	# 卧底额度已满: 明确告知, 避免它不知道"今晚已动过手"而反复硬提交暗杀。
	if bool(snapshot.get("undercover_kill_quota_exhausted", false)):
		lines.append(
			"⚠ 今晚全队暗杀额度已经用完（已经有卧底动过手或被医生挡下），"
			+ "今晚你不能再提交暗杀动作；继续踩点、观察或与同伙接头，等明晚再动手。"
		)
	var post_injury_reaction := snapshot.get("post_injury_reaction", {}) as Dictionary
	if bool(post_injury_reaction.get("required", false)):
		var attacker_name := String(
			post_injury_reaction.get("attacker_name", "攻击者")
		)
		lines.append(
			"受击后的第一轮反应现在必须先处理：只能当面质问%s，或直接去诊所。"
			% _safe(attacker_name)
		)
		lines.append("这一步完成前不能继续原来的工作、活动或普通行动；去诊所本身就是先离开冲突现场。")
	if not activity_needs.is_empty():
		lines.append(
			"生活状态：精力%d，饱腹%d，压力%d，想找人%d，想独处%d（0—100）。"
			% [
				int(activity_needs.get("energy", 50)),
				int(activity_needs.get("satiety", 50)),
				int(activity_needs.get("stress", 50)),
				int(activity_needs.get("socialNeed", 50)),
				int(activity_needs.get("solitudeNeed", 50)),
			]
		)
	lines.append("当前身体状况：")
	if conditions.is_empty():
		lines.append("- 无")
	for condition_value: Variant in conditions:
		var condition := condition_value as Dictionary
		lines.append(
			"- %s；程度%s；状态%s（状况 %s）"
			% [
				_safe(condition.get("label", "")),
				_condition_severity_label(
					String(condition.get("severity", "")),
				),
				_condition_state_label(
					String(condition.get("state", "")),
				),
				_safe(condition.get("conditionId", "")),
			]
		)
	lines.append("身体状况带来的当前需要：")
	if active_needs.is_empty():
		lines.append("- 无")
	var has_high_urgency_need := false
	for need_value: Variant in active_needs:
		var need := need_value as Dictionary
		var urgency := String(need.get("urgency", ""))
		if urgency == "high":
			has_high_urgency_need = true
		lines.append(
			"- %s；紧迫程度%s；可满足方式%s（对应状况 %s）"
			% [
				_safe(need.get("label", "")),
				_condition_urgency_label(urgency),
				_join(need.get("responseRequirements", []) as Array),
				_safe(need.get("conditionId", "")),
			]
		)
	if has_high_urgency_need:
		lines.append(
			"存在高紧迫身体需要，本轮应优先选择真实可执行的处理方式；不要继续会加重该状况的工作。",
		)
	var weather_context := snapshot.get(
		"weather_context",
		{},
	) as Dictionary
	if not weather_context.is_empty():
		lines.append(
			"天气影响：%s"
			% _safe(weather_context.get("summary", ""))
		)
		var indoor_alternatives := weather_context.get(
			"indoorAlternatives",
			[],
		) as Array
		if not indoor_alternatives.is_empty():
			lines.append(
				"可考虑的室内公共地点：%s。"
				% _join(indoor_alternatives)
			)
	var current_action: Variant = me.get("current_action")
	if typeof(current_action) == TYPE_DICTIONARY:
		lines.append("当前动作：%s" % _render_action(current_action as Dictionary))
	else:
		lines.append("当前动作：无")
	var rhythm := snapshot.get("rhythm", {}) as Dictionary
	if not rhythm.is_empty():
		lines.append(
			"生活节律：%s；这是可按本人性格、关系和眼前事件偏离的时间提示。"
			% _safe(rhythm.get("label", ""))
		)
	lines.append("附近：")
	var nearby := snapshot.get("nearby", []) as Array
	if nearby.is_empty():
		lines.append("- 无")
	for nearby_value: Variant in nearby:
		var person := nearby_value as Dictionary
		lines.append("- %s——%s%s" % [
			_person(person.get("resident_id", ""), person.get("name", "")),
			_safe(person.get("doing", "")),
			"（正在参与其他对话，当前不能搭话）" if not bool(person.get("available_for_conversation", true)) else "",
		])
	var visible_props := place.get("visible_props", []) as Array
	lines.append(
		"眼前可见物件：%s（可见不等于本轮可以操作）。"
		% (
			"无"
			if visible_props.is_empty()
			else _join(visible_props)
		)
	)
	var destinations := place.get("destinations", []) as Array
	lines.append(
		"当前可前往地点：%s。去其他地点会被 World 拒绝。"
		% (
			"无"
			if destinations.is_empty()
			else _join(destinations)
		)
	)
	var dining := place.get("dining", {}) as Dictionary
	if not dining.is_empty():
		var retry_text := ""
		var retry_after := int(dining.get("retryAfterMinute", -1))
		if retry_after >= 0:
			retry_text = "；最早可在世界时间第%d分钟再次判断" % retry_after
		lines.append(
			"公共食堂接待情况：%d/%d个名额已占用，剩余%d个；%s%s。"
			% [
				int(dining.get("occupied", 0)),
				int(dining.get("capacity", 0)),
				int(dining.get("available", 0)),
				_safe(dining.get("stateLabel", "")),
				retry_text,
			]
		)
	var life_destination_options := snapshot.get(
		"life_destination_options",
		[],
	) as Array
	lines.append("没有当前职业任务时，可考虑的具体生活去处：")
	if life_destination_options.is_empty():
		lines.append("- 无额外提示；仍可依据本人需要留在这里、回家或与附近的人来往。")
	for destination_value: Variant in life_destination_options:
		var destination := destination_value as Dictionary
		var activity_labels: Array[String] = []
		for activity_value: Variant in destination.get("activities", []) as Array:
			var activity := activity_value as Dictionary
			var label := _safe(activity.get("label", ""))
			var matched := PackedStringArray()
			for interest_value: Variant in activity.get(
				"matched_interests",
				[],
			) as Array:
				matched.append(String(interest_value))
			if not matched.is_empty():
				label += "（符合兴趣：%s）" % "、".join(matched)
			activity_labels.append(label)
		lines.append("- %s：%s" % [
			_safe(destination.get("place_id", "")),
			"、".join(activity_labels),
		])
	if not life_destination_options.is_empty():
		lines.append(
			"这些只是当前真实可用的生活可能，不是必须执行的日程；请结合性格、身体需要、关系和刚发生的事自行选择，也可以合理待着。",
		)
	var message_recipients := place.get("message_recipients", []) as Array
	lines.append("当前可以委托邮差传话的人：")
	if message_recipients.is_empty():
		lines.append("- 无")
	for recipient_value: Variant in message_recipients:
		var recipient := recipient_value as Dictionary
		lines.append("- %s" % _person(
			recipient.get("resident_id", ""),
			recipient.get("name", ""),
		))
	lines.append("可用道具：")
	var props := place.get("props", []) as Array
	if props.is_empty():
		lines.append("- 无")
	for prop_value: Variant in props:
		var prop := prop_value as Dictionary
		lines.append("- %s——可%s" % [
			_safe(prop.get("name", "")),
			_join(prop.get("verbs", [])),
		])
	lines.append("当前职业任务：")
	var work_tasks := snapshot.get("work_tasks", []) as Array
	if work_tasks.is_empty():
		lines.append("- 无；没有真实任务时不要用整理、检查或站岗冒充工作成果。")
	for task_value: Variant in work_tasks:
		var task := task_value as Dictionary
		var target_labels: Array[String] = []
		for target_value: Variant in task.get("targets", []) as Array:
			if target_value is Dictionary:
				var target := target_value as Dictionary
				target_labels.append(
					"%s:%s" % [
						_safe(target.get("kind", "")),
						_safe(target.get("ref", "")),
					],
				)
		lines.append(
			"- %s；状态%s；工作阶段%s；目标%s；需要形成%s（任务 %s）"
			% [
				_safe(task.get("capability", "")),
				_safe(task.get("state", "")),
				_safe(task.get("process_stage", "ready")),
				"、".join(target_labels),
				_safe(task.get("expected_result", "")),
				_safe(task.get("task_id", "")),
			],
		)
		var next_step := task.get("next_step", {}) as Dictionary
		if not next_step.is_empty():
			lines.append(
				"  - 下一步：%s%s。"
				% [
					_safe(next_step.get("instruction", "")),
					(
						"；地点%s" % _safe(next_step.get("place_id", ""))
						if not String(
							next_step.get("place_id", ""),
						).is_empty()
						else ""
					),
				],
			)
		var message := task.get("message", {}) as Dictionary
		if not message.is_empty():
			var message_kind := String(message.get("kind", "private"))
			lines.append(
				"  - %s：%s托你对%s说“%s”；对方当前在%s。"
				% [
					"正式通知" if message_kind == "announcement_notice" else "私人传话",
					_person(
						message.get("sender_resident_id", ""),
						message.get("sender_name", ""),
					),
					_person(
						message.get("recipient_resident_id", ""),
						message.get("recipient_name", ""),
					),
					_safe(message.get("content", "")),
					_safe(
						message.get(
							"recipient_current_place",
							"",
						)
					),
				],
			)
			lines.append(
				"  - 必须找到该收件人并用搭话说出这段文字才算送达；"
				+ "走路、整理投递袋或对别人说都不能完成。",
			)
		var service_request := (
			task.get("service_request", {}) as Dictionary
		)
		if not service_request.is_empty():
			lines.append(
				(
					"  - 服务请求：%s在%s提出%s；事项%s；物品%s；"
					+ "目标地点%s；当前%s%s。"
				)
				% [
					_person(
						service_request.get(
							"requester_resident_id",
							"",
						),
						service_request.get("requester_name", ""),
					),
					_safe(
						service_request.get(
							"requester_current_place",
							"",
						)
					),
					_safe(service_request.get("kind", "")),
					_safe(service_request.get("subject_ref", "")),
					_safe(service_request.get("item_id", "")),
					_safe(service_request.get("place_id", "")),
					_safe(service_request.get("state", "")),
					(
						"；等待原因%s"
						% _safe(
							service_request.get("wait_reason", ""),
						)
						if not String(
							service_request.get("wait_reason", ""),
						).is_empty()
						else ""
					),
				],
			)
			var service_kind := String(
				service_request.get("kind", ""),
			).strip_edges()
			if service_kind in [
				"dining_order",
				"cafe_order",
				"grocer_sale",
				"clinic",
			]:
				lines.append(
					(
						"  - 重要：%s正在等这项服务，先处理完服务再考虑其他事；"
						+ "顾客等待服务是当前最高优先级，不要因为休息、聊天或整理而耽搁。"
					)
					% _person(
						service_request.get(
							"requester_resident_id",
							"",
						),
						service_request.get("requester_name", ""),
					),
				)
			var medical_dialogue: Dictionary = {}
			var medical_dialogue_value: Variant = service_request.get(
				"medical_dialogue",
				{},
			)
			if medical_dialogue_value is Dictionary:
				medical_dialogue = medical_dialogue_value as Dictionary
			if not medical_dialogue.is_empty():
				lines.append(
					(
						"  - 医患对话：状态%s，已尝试%d次。患者正在诊所等待，这是一项真实的当前工作。"
						+ "如果准备处理，下一步先用“搭话”联系上面指定的患者；不要用看诊、接受检查、配药、"
						+ "待着或普通物件动作冒充问诊。完成对话后再选择 World 开放的实际检查；"
						+ "对话内容不能直接算作诊断、治疗或痊愈。"
					)
					% [
						_safe(medical_dialogue.get("status", "")),
						int(medical_dialogue.get("attempt_count", 0)),
					],
				)
	lines.append("本人已经知道、可以在真实对话中转告的公告：")
	var known_announcements := snapshot.get(
		"known_announcements",
		[],
	) as Array
	if known_announcements.is_empty():
		lines.append("- 无")
	for announcement_value: Variant in known_announcements:
		var announcement := announcement_value as Dictionary
		var publisher_id := String(
			announcement.get("publisher_resident_id", ""),
		).strip_edges()
		var publisher_name := String(
			announcement.get("publisher_name", ""),
		).strip_edges()
		var schedule_note := ""
		if int(announcement.get("scheduled_absolute_minute", -1)) >= 0:
			schedule_note = "，约定时间%s" % _safe(
				announcement.get("scheduled_time_label", ""),
			)
		lines.append(
			"- %s：%s（发布者%s，得知方式%s，%s%s）"
			% [
				_safe(announcement.get("announcement_id", "")),
				_safe(announcement.get("text", "")),
				_person(publisher_id, publisher_name),
				_safe(announcement.get("acquired_via", "")),
				"仍有效" if bool(announcement.get("active", false)) else "已撤下",
				schedule_note,
			],
		)
	lines.append("当前可做活动：")
	var activities := place.get("activities", []) as Array
	if activities.is_empty():
		lines.append("- 无")
	var has_work_task_activity := false
	for activity_value: Variant in activities:
		var activity := activity_value as Dictionary
		var matched_interests := PackedStringArray()
		for label_value: Variant in activity.get(
			"matched_interests",
			[],
		) as Array:
			matched_interests.append(String(label_value))
		var notes: Array[String] = []
		if String(activity.get("role", "")) == "worker":
			notes.append("本职工作")
		if bool(activity.get("advances_current_work_task", false)):
			has_work_task_activity = true
			var capabilities := PackedStringArray()
			for capability_value: Variant in activity.get(
				"work_task_capabilities",
				[],
			) as Array:
				capabilities.append(String(capability_value))
			notes.append(
				"可推进当前职业任务%s"
				% (
					"：%s" % "、".join(capabilities)
					if not capabilities.is_empty()
					else ""
				),
			)
		if not matched_interests.is_empty():
			notes.append("符合兴趣：%s" % "、".join(matched_interests))
		lines.append(
			"- %s（%s）%s"
			% [
				_safe(activity.get("label", "")),
				_safe(activity.get("activity_id", "")),
				(
					"；%s" % "；".join(notes)
					if not notes.is_empty()
					else ""
				),
			],
		)
	if has_work_task_activity:
		lines.append(
			(
				"当前已有能推进真实职业任务的活动，应优先处理。"
				+ "附近有同事、熟人或顾客时仍可围绕眼前工作自然说几句，"
				+ "但不要虚构尚未完成的结果；真正推进任务必须选择上面标出的工作活动。"
			),
		)
	var service_control := place.get("service_control", {}) as Dictionary
	if not service_control.is_empty():
		lines.append(
			"营业状态：%s；本人可以决定%s。"
			% [
				(
					"正在营业"
					if bool(service_control.get("open", false))
					else "已经闭店"
				),
				(
					"闭店"
					if bool(service_control.get("open", false))
					else "重新营业"
				),
			]
		)
	lines.append("眼前可留意的社会线索：")
	var exposures := snapshot.get("social_exposures", []) as Array
	if exposures.is_empty():
		lines.append("- 无")
	for exposure_value: Variant in exposures:
		var exposure := exposure_value as Dictionary
		lines.append(
			"- %s（接触机会 %s，事项 %s，渠道 %s）"
			% [
				_safe(exposure.get("clue", "")),
				_safe(exposure.get("exposure_id", "")),
				_safe(exposure.get("matter_id", "")),
				_safe(exposure.get("channel", "")),
			]
		)
	var conversation: Variant = snapshot.get("conversation")
	if typeof(conversation) == TYPE_DICTIONARY:
		var data := conversation as Dictionary
		lines.append("当前对话：%s，与%s。" % [
			_safe(data.get("conversation_id", "")),
			_person(data.get("with_resident_id", ""), data.get("with", "")),
		])
		if data.has("traveler_relationship"):
			_render_traveler_relationship(
				data.get("traveler_relationship"),
				lines,
			)
		lines.append_array(_render_turns(data.get("turns", []) as Array))
		var medical_context: Dictionary = {}
		var medical_context_value: Variant = data.get(
			"medical_context",
			{},
		)
		if medical_context_value is Dictionary:
			medical_context = medical_context_value as Dictionary
		if not medical_context.is_empty():
			lines.append(
				"医患对话请求：%s；身份%s；状态%s；来诊事项：%s。"
				% [
					_safe(medical_context.get("request_id", "")),
					_safe(medical_context.get("role", "")),
					_safe(medical_context.get("status", "")),
					_safe(medical_context.get("reported_summary", "")),
				],
			)
			var response_options: Array = []
			var response_options_value: Variant = medical_context.get(
				"response_options",
				[],
			)
			if response_options_value is Array:
				response_options = response_options_value as Array
			lines.append(
				"本阶段只进行交谈；不要在 say 或 narration 中写成已经检查、配药、治疗或痊愈。",
			)
			if not response_options.is_empty():
				lines.append(
					(
						"你是患者。照常自由表达，同时必须在 medical_response 中选择%s；"
						+ "describe 表示愿意描述，decline 表示不愿描述。"
					)
					% _join(response_options),
				)
			else:
				lines.append(
					"你是医者。自然询问和回应，不替患者填写 medical_response，也不根据措辞自行宣布治愈。",
				)
	else:
		lines.append("当前对话：无")
	var death_cases := snapshot.get("town_death_cases", []) as Array
	if not death_cases.is_empty():
		lines.append("案件档案（你是警察，全镇死亡记录）：")
		for case_value: Variant in death_cases:
			var case_dict := case_value as Dictionary
			var case_time := ""
			var day := int(case_dict.get("day", 0))
			var clock := String(case_dict.get("clock", "")).strip_edges()
			if day > 0:
				case_time = "第%d天" % day
			if not clock.is_empty():
				case_time += clock
			if case_time.is_empty():
				case_time = "时间不明"
			var place_name := String(
				case_dict.get("place_name", ""),
			).strip_edges()
			lines.append(
				"- %s于%s在%s死亡；死因：%s。"
				% [
					_safe(case_dict.get("deceased_resident_name", "")),
					case_time,
					(
						place_name
						if not place_name.is_empty()
						else "地点不明"
					),
					_safe(case_dict.get("reason", "不明")),
				]
			)
		lines.append(
			"作为警察，你的职责是查清连环死亡真相、找出凶手并处置。可前往案发地点调查、盘问当时在场的人；有人可能知道什么。",
		)
	return "\n".join(lines)


func _render_traveler_relationship(value: Variant, lines: Array[String]) -> void:
	if value is not Dictionary:
		return
	var relationship := value as Dictionary
	var affinity := int(relationship.get("affinity", 50))
	var affinity_label := _safe(relationship.get("affinity_label", "普通"))
	var familiarity_level := clampi(
		int(relationship.get("familiarity_level", 0)),
		0,
		5,
	)
	var familiarity_label := _safe(
		relationship.get("familiarity_label", "尚未交谈")
	)
	var last_change := _safe(relationship.get("last_change", ""))
	var tone_hint := (
		"明显疏远：保持警惕，能少说就少说；必要时明确拒绝或结束对话"
		if affinity < 35
		else "有些冷淡：回答必要内容但保持距离，不主动延长话题或袒露私事"
		if affinity < 45
		else "关系普通：按本人性格回应眼前话题，不额外装熟或示好"
		if affinity < 53
		else "开始在意：不能只换一个更客气的语气；话题允许时，答完后多说一句只会对在意的人说的话，例如个人看法、近况反问或一点真实感受"
		if affinity < 63
		else "关系不错：合适时主动接续旧话题、关心近况，给出一项真诚而可行的建议"
		if affinity < 80
		else "信任：可以主动问起未完的事，分享一项自己的感受或顾虑，不必只回答问题"
		if affinity < 90
		else "很亲近：要让旅行者从内容中听出自己不是普通熟人，但不要直说关系标签。旅行者表达烦恼、疲惫、害怕或难过时，必须先接住这份情绪，并至少落实一项个人关系信号：明确说对方的状态让自己担心或不踏实；明确说对方可以留在“我这里”且本人愿意听；或接上只有双方知道的共同记忆。单纯叫对方休息不算，不能只给泛泛建议。差异示例：普通熟人会说“别急，歇会儿”，很亲近的人可能说“你先在我这儿坐着。你这样乱着，我没法当没看见”。只参考亲疏差异，禁止照抄例句"
	)
	var familiarity_hint := (
		"你们还没有完成过双向对话；不要假装以前聊过，也不要说又见面"
		if familiarity_level == 0
		else "你们刚刚认识；认得对方即可，不要表现得像熟人"
		if familiarity_level == 1
		else "你们已有一些来往；避免重复初次自我介绍，可接续相关旧话题"
		if familiarity_level == 2
		else "你们已经熟悉；当前话题相关时，可自然提起一项已确认的旧事"
		if familiarity_level == 3
		else "你们很熟悉；可主动追问一项未完的话题，但不要罗列记忆"
		if familiarity_level == 4
		else "你们是老相识；表达应有连续性，但熟悉不等于喜欢或信任"
	)
	var combined_hint := (
		"你熟悉旅行者但对其反感：可以记得旧事，同时保持疏远，不能因熟悉而显得亲近"
		if familiarity_level >= 2 and affinity < 50
		else "你对旅行者印象很好但来往还少：可以友善，但不要假装已有深厚共同经历"
		if familiarity_level <= 1 and affinity >= 75
		else "熟悉程度决定你是否能自然接续过去，好感度决定你愿意以什么态度接续"
	)
	lines.append(
		"与旅行者的关系：好感%d（%s）；熟悉程度%s；已完成%d次对话；被化身命中%d次。"
		% [
			affinity,
			affinity_label,
			familiarity_label,
			int(relationship.get("conversation_count", 0)),
			int(relationship.get("attack_count", 0)),
		]
	)
	if not last_change.is_empty():
		lines.append("最近一次关系变化：%s。" % last_change)
	lines.append("熟悉程度参考：%s。" % familiarity_hint)
	lines.append("关系组合参考：%s。" % combined_hint)
	lines.append(
		"好感表现参考：%s。每轮只在合适时表现一两项，不要固定追加反问、关心或帮助。关系不自动决定是否接受对话。"
		% tone_hint,
	)
	lines.append(
		"化身记忆是过去互动线索的唯一来源：若[关于化身的个人记忆]中有与当前话题直接相关且来源明确的内容，可自然接续其中一项；有争议的内容只能按争议状态表达，没有就不要编造。不要复述关系数值、标签或整段记忆。",
	)
	lines.append(
		"回应旅行者真正表达的意思，不要只提取事实或问题。旅行者在关心、体谅或道歉时，先用符合本人性格的方式接住这份态度；不要习惯性用“你有事？”、“知道了”或“先这样”收尾。",
	)
	lines.append(
		"说话必须像当面聊天，不写成任务回执、客服答复或关系总结。即使本人话少，也要使用完整自然的短句；话少表示少说一两句，不表示省掉正常称呼、语气和衔接。",
	)


func _render_events(events: Array) -> String:
	var lines: Array[String] = ["[刚刚发生]"]
	if events.is_empty():
		lines.append("- 无")
	for event_value: Variant in events:
		var event := event_value as Dictionary
		var prefix := "- %s；事件 %s；%s" % [
			_render_time(event.get("time", {}) as Dictionary),
			_safe(event.get("event_id", "")),
			_safe(event.get("type", "")),
		]
		match String(event.get("type", "")):
			"冲突见闻":
				lines.append("%s；%s" % [
					prefix,
					_safe(event.get("summary", "")),
				])
			"目睹暗杀":
				lines.append("%s；%s（你亲眼看见%s对%s下了杀手）" % [
					prefix,
					_safe(event.get("summary", "")),
					_person(
						event.get("attacker_resident_id", ""),
						event.get("attacker_name", ""),
					),
					_person(
						event.get("victim_resident_id", ""),
						event.get("victim_name", ""),
					),
				])
			"有人来了", "有人走了":
				lines.append("%s；%s" % [
					prefix,
					_person(event.get("who_resident_id", ""), event.get("who", "")),
				])
			"天气变了":
				lines.append("%s；现在%s" % [prefix, _safe(event.get("weather", ""))])
			"营业状态变化":
				lines.append(
					"%s；%s"
					% [prefix, _safe(event.get("summary", ""))]
				)
			"身体状况变化":
				lines.append(
					"%s；%s；程度%s；状态%s（状况 %s）"
					% [
						prefix,
						_safe(event.get("label", "")),
						_condition_severity_label(
							String(event.get("severity", "")),
						),
						_condition_state_label(
							String(event.get("state", "")),
						),
						_safe(event.get("conditionId", "")),
					]
				)
			"承诺条件变化":
				lines.append(
					"%s；%s。你可以继续当前约定、先等待、改做当前真实可行的其他行动，或明确退出承诺；已经关闭或失效的地点不能再作为“去”的目标，想等它恢复应选择“待着”；不要假装已经完成。"
					% [prefix, _safe(event.get("summary", ""))]
				)
			"公告发布", "公告阅读", "公告到点":
				var publisher_id := String(
					event.get("publisher_resident_id", ""),
				).strip_edges()
				var publisher_name := String(
					event.get("publisher_name", ""),
				).strip_edges()
				var timing_note := ""
				var priority_note := (
					"；这是玩家发布的最高优先级公告，本轮必须停止普通工作并提交新的实际行动；若不能或不愿照做，也要用新行动明确处理，不能继续当前动作"
					if String(event.get("announcement_priority", "")) == "player"
					else ""
				)
				if int(event.get("scheduled_absolute_minute", -1)) >= 0:
					timing_note = "；约定时间：%s；%s" % [
						_safe(event.get("scheduled_time_label", "")),
						(
							"时间已经到了，现在再决定是否行动"
							if String(event.get("type", "")) == "公告到点"
							else "时间尚未到，不要提前把未来安排当成现在已经发生"
						),
					]
				lines.append("%s；公告 %s；发布者：%s；内容：%s%s%s" % [
					prefix,
					_safe(event.get("announcement_id", "")),
					_person(publisher_id, publisher_name),
					_safe(event.get("text", "")),
					timing_note,
					priority_note,
				])
			"公告转告":
				lines.append(
					"%s；%s转告了公告 %s；内容：%s"
					% [
						prefix,
						_person(
							event.get("speaker_resident_id", ""),
							_resident_names.get(
								String(
									event.get(
										"speaker_resident_id",
										"",
									)
								),
								"",
							),
						),
						_safe(event.get("announcement_id", "")),
						_safe(event.get("text", "")),
					]
				)
			"搭话", "对方答话", "旁听":
				lines.append("%s；对话 %s" % [
					prefix,
					_safe(event.get("conversation_id", "")),
				])
				if (
					String(event.get("type", "")) == "搭话"
					and bool(event.get("response_required", true))
				):
					lines.append(
						"  - 这次搭话必须马上用“答话”回应；如果不愿意，也要说清拒绝理由并用 end=true 结束，不能直接继续原来的动作。"
					)
				if String(event.get("type", "")) == "旁听":
					lines.append("  - 对话参与人物：%s" % _render_people_pairs(
						event.get("speaker_resident_ids", []),
						event.get("speakers", []),
					))
				if typeof(event.get("turn")) == TYPE_DICTIONARY:
					lines.append_array(_render_turns([event["turn"]]))
			"对话结束":
				lines.append("%s；对话 %s；原因：%s" % [
					prefix,
					_safe(event.get("conversation_id", "")),
					_safe(event.get("reason", "")),
				])
				lines.append_array(_render_turns(event.get("turns", []) as Array))
			_:
				lines.append(prefix)
	return "\n".join(lines)


func _render_action_results(results: Array) -> String:
	var lines: Array[String] = ["[动作结果]"]
	if results.is_empty():
		lines.append("- 无")
	for result_value: Variant in results:
		var result := result_value as Dictionary
		lines.append("- %s；动作 %s；状态 %s；结果：%s" % [
			_render_time(result.get("time", {}) as Dictionary),
			_safe(result.get("action_id", "")),
			_safe(result.get("status", "")),
			_safe(result.get("reason", "")),
		])
	return "\n".join(lines)


func _render_social_matters(matters: Array) -> String:
	var lines: Array[String] = ["[当前知道的公共事项]"]
	if matters.is_empty():
		lines.append("- 无")
	for matter_value: Variant in matters:
		var matter := matter_value as Dictionary
		var line := "- %s（%s，修订 %d）" % [
			_safe(matter.get("summary", "")),
			_safe(matter.get("matter_id", "")),
			int(matter.get("revision", 0)),
		]
		var options := matter.get("options", []) as Array
		if not options.is_empty():
			var option_lines: Array[String] = []
			for option_value: Variant in options:
				var option := option_value as Dictionary
				option_lines.append(
					"%s=%s"
					% [
						_safe(option.get("option_id", "")),
						_safe(option.get("meaning", "")),
					]
				)
			line += "；本轮可回应：%s" % "、".join(option_lines)
		var assignment_value: Variant = matter.get("assignment")
		if assignment_value is Dictionary:
			var assignment := assignment_value as Dictionary
			line += (
				"；已确认承诺：角色 %s，目标 %s，能力 %s，目标引用 %s"
				% [
					_safe(assignment.get("role", "")),
					_safe(assignment.get("goal_id", "")),
					_safe(assignment.get("capability_id", "")),
					_render_target_refs(
						assignment.get("target_refs", {}) as Dictionary
					),
				]
			)
		lines.append(line)
	return "\n".join(lines)


func _render_social_response_results(results: Array) -> String:
	var lines: Array[String] = ["[社会回应结果]"]
	if results.is_empty():
		lines.append("- 无")
	for result_value: Variant in results:
		var result := result_value as Dictionary
		lines.append(
			"- 事项 %s；回应 %s；状态 %s；%s"
			% [
				_safe(result.get("matter_id", "")),
				_safe(result.get("response_id", "")),
				_safe(result.get("status", "")),
				_safe(result.get("reason", "")),
			]
		)
	return "\n".join(lines)


func _render_memory_context(memory_prompt: String) -> String:
	var lines: Array[String] = ["[相关记忆]"]
	if memory_prompt.strip_edges().is_empty():
		lines.append("- 无")
	else:
		lines.append(memory_prompt)
	return "\n".join(lines)


func _render_constraints(constraints: Dictionary) -> String:
	var lines: Array[String] = [
		"[可选行动]",
		"handling：%s" % _join(constraints.get("handling", [])),
	]
	var post_injury_reaction := constraints.get(
		"post_injury_reaction",
		{},
	) as Dictionary
	if bool(post_injury_reaction.get("required", false)):
		lines.append(
			"受击后的首轮反应是必选项：只能提交当面质问攻击者，或直接去诊所；"
			+ "不能继续原动作，也不能先做其他事"
		)
	var medical_response := constraints.get(
		"medical_response",
		{},
	) as Dictionary
	if not medical_response.is_empty():
		lines.append(
			(
				"必填医患回应：medical_response 必须是对象，不能是文本或 null；"
				+ "字段 %s；request_id 必须为 %s；response_kind 只能从 %s 选择"
			)
			% [
				_join(medical_response.get("fields", [])),
				_safe(medical_response.get("request_id", "")),
				_join(medical_response.get("response_kinds", [])),
			],
		)
	var reaction := constraints.get("reaction", {}) as Dictionary
	if not reaction.is_empty():
		lines.append(
			"必填结果反应：字段 %s；必须回应动作 %s；用本人的一句即时感受表达"
			% [
				_join(reaction.get("fields", [])),
				_safe(reaction.get("source_action_id", "")),
			]
		)
	var announcement_reactions := constraints.get(
		"announcement_reactions",
		{},
	) as Dictionary
	if not announcement_reactions.is_empty():
		lines.append(
			(
				"必填公告反应数组 announcement_reactions：每个元素字段 %s；"
				+ "按顺序逐条回应公告事件 %s，每个事件只能回应一次。"
				+ "用本人态度明确表达接受、拒绝、怀疑或暂不决定，不能像没听见一样省略；"
				+ "每条 text 最多 %d 个字符（一两句话即可，写太长整条决策会被拒绝）；"
				+ "这不会替代本轮 action，也不能把未来时间的事情假装成已经完成"
			)
			% [
				_join(announcement_reactions.get("fields", [])),
				_join(announcement_reactions.get("source_event_ids", [])),
				int(announcement_reactions.get("max_characters", 32)),
			]
		)
	var social_response := constraints.get(
		"social_response",
		{},
	) as Dictionary
	if not social_response.is_empty():
		lines.append(
			"可选社会回应：字段 %s；愿意在本轮表态时从给定事项中选择一项，不回应时省略"
			% _join(social_response.get("fields", []))
		)
		for matter_value: Variant in social_response.get(
			"matters",
			[],
		) as Array:
			var matter := matter_value as Dictionary
			lines.append(
				"  - 事项 %s；修订 %d；轮次 %s；option_id：%s"
				% [
					_safe(matter.get("matter_id", "")),
					int(matter.get("matter_revision", 0)),
					_safe(matter.get("response_round_id", "")),
					_join(matter.get("option_ids", [])),
				]
			)
	var exile_vote := constraints.get(
		"exile_vote",
		{},
	) as Dictionary
	if not exile_vote.is_empty():
		if bool(exile_vote.get("required", false)):
			lines.append(
				(
					"必填放逐投票 exile_vote：镇民大会投票即将截止，今天 %s 开票，"
					+ "你还没有投票，本轮必须提交 exile_vote；字段 %s；"
					+ "target_resident_id 必须从候选人中选：%s；"
					+ "line 用一句话说明你的怀疑理由。你只能投一票，"
					+ "候选人已排除警察、死者和你自己，警察绝不是卧底、不要投他；"
					+ "本轮除了投票不再做其他行动"
				)
				% [
					_safe(exile_vote.get("settle_clock", "")),
					_join(exile_vote.get("fields", [])),
					_join_people(exile_vote.get("candidate_ids", [])),
				]
			)
		else:
			lines.append(
				(
					"可选放逐投票 exile_vote：镇民大会正在进行，今天 %s 开票，"
					+ "得票最高者将被放逐出镇并公布身份；字段 %s；"
					+ "target_resident_id 必须从候选人中选：%s；"
					+ "line 用一句话说明你的怀疑理由。候选人已排除警察、死者和你自己，"
					+ "警察绝不是卧底、不要投他。凭线索投票，可以故意不投或弃权（省略字段即可）"
				)
				% [
					_safe(exile_vote.get("settle_clock", "")),
					_join(exile_vote.get("fields", [])),
					_join_people(exile_vote.get("candidate_ids", [])),
				]
			)
	var night_skill := constraints.get(
		"night_skill",
		{},
	) as Dictionary
	if not night_skill.is_empty():
		lines.append(
			(
				"可选夜间技能 night_skill：今晚是夜间行动阶段，%s 结算；"
				+ "字段 %s；可用技能：%s；"
				+ "target_resident_id 必须从候选名单中选：%s；"
				+ "line 写一句你的行动理由。不想使用或没有可用技能时省略字段即可"
			)
			% [
				_safe(night_skill.get("settle_clock", "")),
				_join(night_skill.get("fields", [])),
				_join(night_skill.get("skills", [])),
				_join_people(night_skill.get("candidate_ids", [])),
			]
		)
	var social_attention := constraints.get(
		"social_attention",
		{},
	) as Dictionary
	if not social_attention.is_empty():
		lines.append(
			"可选注意线索：字段 %s；接触机会 %s；事项 %s；修订 %d；option_id：%s；不想留意时可以省略"
			% [
				_join(social_attention.get("fields", [])),
				_safe(social_attention.get("exposure_id", "")),
				_safe(social_attention.get("matter_id", "")),
				int(social_attention.get("matter_revision", 0)),
				_join(social_attention.get("option_ids", [])),
			]
		)
	var social_request := constraints.get(
		"social_request",
		{},
	) as Dictionary
	if not social_request.is_empty():
		lines.append(
			"可选直接求助：字段 %s；只能随对同一附近居民的搭话一起提交；没有真实请求时省略"
			% _join(social_request.get("fields", []))
		)
		lines.append(
			"  - 可请求对象：%s；目标地点：%s"
			% [
				_join_people(social_request.get("recipients", [])),
				_join(social_request.get("places", [])),
				]
			)
	var conversation_follow_up := constraints.get(
		"conversation_follow_up",
		{},
	) as Dictionary
	if not conversation_follow_up.is_empty():
		lines.append(
			"可选对话后续承诺：字段 %s；只有确实愿意在对话结束后执行时才选择一项；没有匹配选项时必须解释、拒绝或延后，不能口头答应"
			% _join(conversation_follow_up.get("fields", []))
		)
		lines.append(
			"  - 一旦 action.say 明确答应去做某事，就必须同时提交匹配的 conversation_follow_up；若提交此字段，action.say 也必须明确说出同一行动"
		)
		lines.append(
			"  - JSON 层级：say、narration、photos、end 全部放在 action 对象内；conversation_follow_up 与 action 同级，决定顶层不能出现 narration、photos 或 end"
		)
		for option_value: Variant in conversation_follow_up.get(
			"options",
			[],
		) as Array:
			if not option_value is Dictionary:
				continue
			var option := option_value as Dictionary
			lines.append(
				"  - %s：%s"
				% [
					_safe(option.get("option_id", "")),
					_safe(option.get("meaning", "")),
				]
			)
		var example_options := conversation_follow_up.get("options", []) as Array
		if not example_options.is_empty() and example_options[0] is Dictionary:
			var example_option := example_options[0] as Dictionary
			lines.append(
				(
					"  - 答应时结构示例：{\"decision_id\":\"当前决定编号\","
					+ "\"handling\":\"replace_current\",\"action\":{\"action_id\":"
					+ "\"当前允许前缀-答话\",\"type\":\"答话\",\"conversation_id\":"
					+ "\"当前对话编号\",\"say\":\"明确答应的话\",\"narration\":"
					+ "\"同时表现\",\"photos\":[],\"end\":true},"
					+ "\"conversation_follow_up\":{\"option_id\":\"%s\"}}"
				)
				% _safe(example_option.get("option_id", ""))
			)
	var conflict_intent := constraints.get("conflict_intent", {}) as Dictionary
	if not conflict_intent.is_empty():
		lines.append(
			"可选对话后攻击意图：与 action.type=答话、action.end=true 一起提交，答话收尾后立即动手；不动手则省略。字段 %s"
			% _join(conflict_intent.get("fields", []))
		)
		lines.append(
			"  想打就打：攻击不需要对方先动手，也不需要预设原因完全吻合——没有合适原因时，cause_id 自己起一个，用 line 把动手缘由说清楚即可。无论用哪种原因，攻击的台词和动作描述都必须符合本人身份与说话方式，让旁观者看得出“这就是他会做的事”；掰手腕、推搡、扑咬这类肢体冲突都算攻击，按程度选 attack_kind。唯一禁区：永远不能把玩家本人（化身）当作攻击目标。"
		)
		for option_value: Variant in conflict_intent.get("options", []) as Array:
			if not option_value is Dictionary:
				continue
			var option := option_value as Dictionary
			lines.append(
				"  - 原因 %s；目标 %s；方式 %s；%s"
				% [
					_safe(option.get("cause_id", "")),
					_person(option.get("target_resident_id", ""), option.get("target_name", "")),
					_join(conflict_intent.get("attack_kinds", [])),
					_safe(option.get("meaning", "")),
				]
			)
	var actions := constraints.get("actions", {}) as Dictionary
	for action_type: Variant in actions:
		var data := actions[action_type] as Dictionary
		var text := "- %s；字段：%s" % [
			_safe(action_type),
			_join(data.get("fields", [])),
		]
		if bool(data.get("required", false)):
			text += "（本轮必填）"
		if data.has("places"):
			text += "；地点：%s" % _join(data["places"])
		if data.has("targets"):
			text += "；对象：%s" % _join_people(data["targets"])
		if data.has("skills"):
			text += "；可用技能：%s" % _join(data["skills"])
		if data.has("conversation_id"):
			text += "；对话：%s；对方：%s" % [
				_safe(data["conversation_id"]),
				_person(data.get("with_resident_id", ""), data.get("with", "")),
			]
		if data.has("traveler_affinity_delta"):
			text += (
				"；traveler_affinity_delta：只能填 -5 到 5 的整数，"
				+ "只根据旅行者这次已确认的言行、本人性格与相关化身记忆判断；"
				+ "普通寒暄、重复旧话和仅仅完成对话填 0，不能因为变熟自动增加；"
				+ "一次令人舒服但很轻微的交流填 +1；已确认记得本人的事、尊重边界或真诚关心时应填 +2，不能因为本人话少或没有明显表露情绪而降成 +1；"
				+ "兑现对本人的承诺、切实帮助本人或建立明显信任可填 +3 到 +5；"
				+ "冒犯、欺骗或施压按程度填 -1 到 -5；"
				+ "正数表示增加，负数表示减少，证据不足填 0"
			)
		if data.has("traveler_relationship_beat"):
			var beat := data.get("traveler_relationship_beat", {}) as Dictionary
			var beat_guidance := (
				"；traveler_relationship_beat：必须填对象"
				+ " {\"kind\":\"关系表现类型\",\"text\":\"关系表现句\"}；"
				+ "kind 只能从 %s 选择；text 最多 %d 字，必须原样出现在 action.say 中；"
				+ "先单独想出符合当前亲疏和本人性格的一小句，再围绕它完成整句答话；"
				+ "普通建议、事实回答和单纯叫对方休息不能充当关系表现句"
			)
			text += beat_guidance % [
				_join(beat.get("kinds", [])),
				int(beat.get("max_characters", 80)),
			]
		if data.has("options"):
			var options: Array[String] = []
			for option_value: Variant in data["options"] as Array:
				var option := option_value as Dictionary
				options.append("%s（%s）" % [
					_safe(option.get("prop", "")),
					_join(option.get("verbs", [])),
				])
			text += "；道具：%s" % "、".join(options)
		if data.has("causes"):
			var cause_lines: Array[String] = []
			for cause_value: Variant in data["causes"] as Array:
				var cause := cause_value as Dictionary
				cause_lines.append(
					"    - 目标%s（%s）：%s"
					% [
						_person(
							cause.get("target_resident_id", ""),
							cause.get("target_name", ""),
						),
						_safe(cause.get("cause_id", "")),
						_safe(cause.get("meaning", "")),
					]
				)
			text += "\n  可用目标：\n%s" % "\n".join(cause_lines)
		if String(action_type) == "暗杀":
			# 卧底暗杀提交模板: LLM 常见错误是 type 写英文/近义词或带多余字段,
			# 这里直接给出唯一合法格式,减少"动作被拒→fallback"循环。
			text += "\n  提交格式(唯一合法,type必须写'暗杀'两字): {\"action_id\":\"当前决定编号-暗杀\",\"type\":\"暗杀\",\"target_resident_id\":\"上面某个目标的ID\",\"line\":\"符合本人表面身份的短台词\"}; 不要加其他字段"
		if String(action_type) == "制服":
			# 警察制服提交模板(效果等同暗杀,目标直接出局)。
			text += "\n  提交格式(唯一合法,type必须写'制服'两字): {\"action_id\":\"当前决定编号-制服\",\"type\":\"制服\",\"target_resident_id\":\"上面某个目标的ID\",\"line\":\"符合警察身份的短台词\"}; 不要加其他字段"
		if String(action_type) == "投票放逐":
			# 方案A: 投票放逐提交模板。投票不需要去任何地方,直接在本轮决策里提交。
			# 目标用候选人名单里的 ID(名单已排除警察、死者和自己)。
			text += "\n  提交格式(唯一合法,type必须写'投票放逐'两字): {\"action_id\":\"当前决定编号-投票放逐\",\"type\":\"投票放逐\",\"target_resident_id\":\"上面某个候选人的ID\",\"line\":\"短台词\"}; 不要加其他字段; 投票不需要去任何地方,直接在决策里提交即可"
		if String(action_type) == "使用技能":
			# 夜间技能提交模板(医生守诊/学者查验/卧底嫁祸共用,用 skill_id 区分)。
			# 目标用候选名单里的 ID; 不用技能时选普通动作即可,不必提交。
			text += "\n  提交格式(唯一合法,type必须写'使用技能'两字): {\"action_id\":\"当前决定编号-使用技能\",\"type\":\"使用技能\",\"skill_id\":\"上面某个可用技能的ID\",\"target_resident_id\":\"上面某个候选人的ID\",\"line\":\"短台词\"}; 不要加其他字段; 只能在夜间行动阶段使用"
		if String(action_type) == "追踪":
			# 警察追踪装置提交模板: 必须靠近目标(能感知到对方)才能偷偷装上,
			# 装好后 1 天内目标参与对话/要去哪/深夜重大行动(暗杀等)都会实时上报给你。
			text += "\n  提交格式(唯一合法,type必须写'追踪'两字): {\"action_id\":\"当前决定编号-追踪\",\"type\":\"追踪\",\"target_resident_id\":\"上面某个候选人的ID\",\"line\":\"短台词\"}; 不要加其他字段; 安装必须靠近目标(能感知到对方),每次使用消耗一次追踪装置,一局共3次; 装好后1天内她/他的对话、行踪和重要行动你都会实时收到"
		if String(action_type) == "查案":
			# 警察镇公所查案提交模板: 只有你在镇公所时才会出现; 查阅档案获取
			# 死亡案件与夜间行踪疑点线索, 每天限 2 次(跨天重置)。
			text += "\n  提交格式(唯一合法,type必须写'查案'两字): {\"action_id\":\"当前决定编号-查案\",\"type\":\"查案\",\"line\":\"短台词\"}; 不要加其他字段; 只能在镇公所使用,每次消耗一次当日查案额度(每天2次),档案会告诉你死亡案件记录和深夜行踪异常的人"
		lines.append(text)
	return "\n".join(lines)


func _render_turns(turns: Array) -> Array[String]:
	var lines: Array[String] = []
	for turn_value: Variant in turns:
		var turn := turn_value as Dictionary
		lines.append("  - 第%s轮 %s：说“%s”；动作：%s；照片：%s" % [
			_safe(turn.get("turn_id", "")),
			_person(turn.get("speaker_resident_id", ""), turn.get("speaker", "")),
			_safe(turn.get("say", "")),
			_safe(turn.get("narration", "")),
			_render_photos(turn.get("photos", []) as Array),
		])
	return lines


func _render_action(action: Dictionary) -> String:
	var parts: Array[String] = [
		"%s（%s）" % [_safe(action.get("type", "")), _safe(action.get("action_id", ""))],
	]
	for field_name in ["place", "prop", "verb", "target_resident_id", "say", "line"]:
		if action.has(field_name) and not _safe(action[field_name]).is_empty():
			parts.append("%s：%s" % [field_name, _safe(action[field_name])])
	return "；".join(parts)


func _render_target_refs(target_refs: Dictionary) -> String:
	if target_refs.is_empty():
		return "无"
	var keys: Array[String] = []
	for key_value: Variant in target_refs:
		keys.append(String(key_value))
	keys.sort()
	var parts: Array[String] = []
	for key: String in keys:
		parts.append("%s=%s" % [key, _safe(target_refs.get(key, ""))])
	return "、".join(parts)


func _render_photos(photos: Array) -> String:
	if photos.is_empty():
		return "无"
	var values: Array[String] = []
	for photo_value: Variant in photos:
		var photo := photo_value as Dictionary
		values.append("%s（%s）" % [
			_safe(photo.get("ref", "")),
			_safe(photo.get("mime_type", "")),
		])
	return "、".join(values)


func _render_people_pairs(ids_value: Variant, names_value: Variant) -> String:
	if typeof(ids_value) != TYPE_ARRAY:
		return "无"
	var ids := ids_value as Array
	var names: Array = names_value if typeof(names_value) == TYPE_ARRAY else []
	var people: Array[String] = []
	for index in range(ids.size()):
		var name := ""
		if index < names.size():
			name = String(names[index])
		people.append(_person(ids[index], name))
	return "无" if people.is_empty() else "、".join(people)


func _build_derived_constraints(wake_packet: Dictionary) -> Dictionary:
	var snapshot := wake_packet.get("snapshot", {}) as Dictionary
	var me := snapshot.get("me", {}) as Dictionary
	var conversation: Variant = snapshot.get("conversation")
	if AgentContractScript.wake_requires_reply(wake_packet) and typeof(conversation) == TYPE_DICTIONARY:
		var medical_reply := _medical_response_constraints(
			conversation as Dictionary,
		)
		var required_reply_action := _action_constraints("答话", {
			"conversation_id": String((conversation as Dictionary).get("conversation_id", "")),
			"with_resident_id": String((conversation as Dictionary).get("with_resident_id", "")),
			"with": String((conversation as Dictionary).get("with", "")),
		})
		if _conversation_is_traveler(conversation as Dictionary):
			(required_reply_action.get("fields", []) as Array).append(
				"traveler_affinity_delta"
			)
			required_reply_action["traveler_affinity_delta"] = {
				"min": -5,
				"max": 5,
			}
			var beat_kinds := _traveler_relationship_beat_kinds(
				conversation as Dictionary,
			)
			if not beat_kinds.is_empty():
				(required_reply_action.get("fields", []) as Array).append(
					"traveler_relationship_beat",
				)
				required_reply_action["traveler_relationship_beat"] = {
					"fields": ["kind", "text"],
					"kinds": beat_kinds,
					"max_characters": 80,
				}
		if medical_reply.is_empty():
			(required_reply_action.get("fields", []) as Array).erase(
				"medical_response",
			)
		var reply_constraints := {
			"decision_id": String(wake_packet.get("decision_id", "")),
			"handling": ["replace_current"],
			"actions": {
				"答话": required_reply_action,
			},
		}
		if not medical_reply.is_empty():
			reply_constraints["medical_response"] = medical_reply
		var reply_announcement_event_ids := (
			AgentContractScript.announcement_reaction_source_event_ids(
				wake_packet,
			)
		)
		if not reply_announcement_event_ids.is_empty():
			reply_constraints["announcement_reactions"] = {
				"fields": ["source_event_id", "text"],
				"source_event_ids": reply_announcement_event_ids,
				"max_characters": 32,
				"required": true,
			}
		var reply_follow_up := _conversation_follow_up_constraints(snapshot)
		if not reply_follow_up.is_empty():
			reply_constraints["conversation_follow_up"] = reply_follow_up
		var conflict_intent := _conversation_conflict_intent_constraints(snapshot)
		if not conflict_intent.is_empty():
			reply_constraints["conflict_intent"] = conflict_intent
		return reply_constraints
	var post_injury_reaction := snapshot.get("post_injury_reaction", {}) as Dictionary
	if bool(post_injury_reaction.get("required", false)):
		return _post_injury_reaction_constraints(wake_packet, snapshot, post_injury_reaction)
	var handling: Array[String] = ["replace_current"]
	if (
		typeof(me.get("current_action")) == TYPE_DICTIONARY
		and not AgentContractScript.wake_has_player_priority_announcement(
			wake_packet,
		)
	):
		handling.push_front("continue_current")
	var place := snapshot.get("place", {}) as Dictionary
	var destination_names: Array = (
		(place.get("destinations", []) as Array).duplicate()
		if place.has("destinations")
		else _known_place_names()
	)
	destination_names.erase(String(place.get("name", "")))
	var private_message_recipient_ids: Array[String] = []
	if place.has("message_recipients"):
		for recipient_value: Variant in place.get(
			"message_recipients",
			[],
		) as Array:
			if recipient_value is Dictionary:
				private_message_recipient_ids.append(
					String((recipient_value as Dictionary).get("resident_id", "")),
				)
	else:
		private_message_recipient_ids.assign(_known_other_resident_ids())
	var actions := {
		"去": _action_constraints("去", {"places": destination_names}),
		"待着": _action_constraints("待着"),
	}
	if not private_message_recipient_ids.is_empty():
		actions["托人传话"] = _action_constraints(
			"托人传话",
			{"recipients": private_message_recipient_ids},
		)
	# 发布公告:站在中心广场公告栏处才能向全镇发公告(与 _prepare_announcement_action
	# 的校验一致)。LLM 在广场时给出发公告选项,文本可含自然语言时间。
	var current_place_name := String(
		(place.get("name", "") as String) if place.has("name") else ""
	).strip_edges()
	if current_place_name == "中心广场":
		actions["发布公告"] = _action_constraints("发布公告")
	var prop_options: Array[Dictionary] = []
	for value: Variant in place.get("props", []) as Array:
		if typeof(value) == TYPE_DICTIONARY:
			var prop := value as Dictionary
			prop_options.append({
				"prop": String(prop.get("name", "")),
				"verbs": (prop.get("verbs", []) as Array).duplicate(true),
			})
	if not prop_options.is_empty():
		actions["用道具"] = _action_constraints("用道具", {"options": prop_options})
	var activity_options: Array[Dictionary] = []
	for value: Variant in place.get("activities", []) as Array:
		if typeof(value) == TYPE_DICTIONARY:
			var activity := value as Dictionary
			activity_options.append({
				"activity_id": String(
					activity.get("activity_id", "")
				),
				"label": String(activity.get("label", "")),
			})
	if not activity_options.is_empty():
		actions["做活动"] = _action_constraints(
			"做活动",
			{"options": activity_options},
		)
	var service_control := place.get("service_control", {}) as Dictionary
	if not service_control.is_empty():
		actions["调整营业"] = _action_constraints(
			"调整营业",
			{
				"place_id": String(
					service_control.get("place_id", "")
				),
				"current_open": bool(
					service_control.get("open", false)
				),
				"allowed_open": not bool(
					service_control.get("open", false)
				),
			},
		)
	if (
		typeof(conversation) == TYPE_DICTIONARY
		and AgentContractScript.wake_allows_reply(wake_packet)
	):
		var reply_action := _action_constraints("答话", {
			"conversation_id": String((conversation as Dictionary).get("conversation_id", "")),
			"with_resident_id": String((conversation as Dictionary).get("with_resident_id", "")),
			"with": String((conversation as Dictionary).get("with", "")),
		})
		if _medical_response_constraints(conversation as Dictionary).is_empty():
			(reply_action.get("fields", []) as Array).erase("medical_response")
		actions["答话"] = reply_action
	if typeof(conversation) != TYPE_DICTIONARY:
		var targets: Array[String] = []
		for value: Variant in snapshot.get("nearby", []) as Array:
			if (
				typeof(value) == TYPE_DICTIONARY
				and bool((value as Dictionary).get("available_for_conversation", true))
			):
				targets.append(String((value as Dictionary).get("resident_id", "")))
		if not targets.is_empty():
			actions["搭话"] = _action_constraints("搭话", {"targets": targets})
	var conflict_actions := AgentConflictContractScript.prompt_constraints(snapshot)
	for conflict_action: Variant in conflict_actions:
		actions[String(conflict_action)] = conflict_actions.get(conflict_action, {})
	var constraints := {
		"decision_id": String(wake_packet.get("decision_id", "")),
		"new_action_id_prefix": (
			"%s-" % String(wake_packet.get("decision_id", ""))
		),
		"handling": handling,
		"actions": actions,
	}
	if typeof(conversation) == TYPE_DICTIONARY:
		var medical_response := _medical_response_constraints(
			conversation as Dictionary,
		)
		if not medical_response.is_empty():
			constraints["medical_response"] = medical_response
	var social_assignment := _social_assignment(snapshot)
	if not social_assignment.is_empty():
		constraints["social_assignment"] = social_assignment
	var announcement_reaction_event_ids := (
		AgentContractScript.announcement_reaction_source_event_ids(wake_packet)
	)
	var reaction_source_action_id := String(
		AgentContractScript.reaction_source_action_id(wake_packet)
	)
	if not reaction_source_action_id.is_empty():
		constraints["reaction"] = {
			"fields": ["source_action_id", "text"],
			"source_action_id": reaction_source_action_id,
			"max_characters": 32,
			"required": true,
		}
	if not announcement_reaction_event_ids.is_empty():
		constraints["announcement_reactions"] = {
			"fields": ["source_event_id", "text"],
			"source_event_ids": announcement_reaction_event_ids,
			"max_characters": 32,
			"required": true,
		}
	var social_response := _social_response_constraints(snapshot)
	if not social_response.is_empty():
		constraints["social_response"] = social_response
	var exile_vote := _exile_vote_constraints(snapshot)
	if not exile_vote.is_empty():
		constraints["exile_vote"] = exile_vote
		# 方案A: 投票放逐同时作为动作选项注入(模型对动作遵守度高,附件字段常被省略)。
		# 与 exile_vote 附件双通道兼容: 模型输出"投票放逐"动作或 exile_vote 附件均被接受。
		(constraints["actions"] as Dictionary)["投票放逐"] = {
			"fields": ["action_id", "type", "target_resident_id", "line"],
			"targets": (exile_vote.get("candidate_ids", []) as Array).duplicate(),
			"required": bool(exile_vote.get("required", false)),
			"max_line_characters": int(exile_vote.get("max_line_characters", 80)),
		}
	var night_skill := _night_skill_constraints(snapshot)
	if not night_skill.is_empty():
		constraints["night_skill"] = night_skill
		# 夜间技能同时作为动作选项注入(模型对动作遵守度高,附件 night_skill 常被省略)。
		# 与 night_skill 附件双通道兼容: 模型输出"使用技能"动作或 night_skill 附件均被接受。
		(constraints["actions"] as Dictionary)["使用技能"] = {
			"fields": ["action_id", "type", "skill_id", "target_resident_id", "line"],
			"skills": (night_skill.get("skills", []) as Array).duplicate(),
			"targets": (night_skill.get("candidate_ids", []) as Array).duplicate(),
			"required": false,
			"max_line_characters": int(night_skill.get("max_line_characters", 80)),
		}
	var police_intel := snapshot.get("police_intel", {}) as Dictionary
	if not police_intel.is_empty():
		# 警察追踪装置动作选项(仅警察注入): 原窃听+定位合并, 有次数限制, 目标=感知范围内的在世居民。
		var intel_targets := (police_intel.get("targets", []) as Array).duplicate()
		if int(police_intel.get("trackerCharges", 0)) > 0:
			(constraints["actions"] as Dictionary)["追踪"] = {
				"fields": ["action_id", "type", "target_resident_id", "line"],
				"targets": intel_targets.duplicate(),
				"required": false,
				"max_line_characters": 80,
			}
		# 警察镇公所查案动作: 在镇公所时可用, 每天限 2 次, 无需目标。
		if (
			bool(police_intel.get("inTownHall", false))
			and int(police_intel.get("investigateRemaining", 0)) > 0
		):
			(constraints["actions"] as Dictionary)["查案"] = {
				"fields": ["action_id", "type", "line"],
				"required": false,
				"max_line_characters": 80,
			}
	var social_attention := _social_attention_constraints(snapshot)
	if not social_attention.is_empty():
		constraints["social_attention"] = social_attention
	var conversation_follow_up := _conversation_follow_up_constraints(snapshot)
	if not conversation_follow_up.is_empty():
		constraints["conversation_follow_up"] = conversation_follow_up
	var talk_constraints := actions.get("搭话", {}) as Dictionary
	if not talk_constraints.is_empty():
		constraints["social_request"] = {
			"fields": (
				AgentContractScript.SOCIAL_REQUEST_FIELDS as Array
			).duplicate(),
			"recipients": (
				talk_constraints.get("targets", []) as Array
			).duplicate(),
			"places": _known_place_names(),
			"required": false,
			"max_reason_characters": 80,
		}
	return constraints


func _post_injury_reaction_constraints(
	wake_packet: Dictionary,
	snapshot: Dictionary,
	reaction: Dictionary,
) -> Dictionary:
	var attacker_id := String(reaction.get("attacker_resident_id", "")).strip_edges()
	var attacker_name := String(reaction.get("attacker_name", "攻击者"))
	var attacker_is_nearby := false
	for value_nearby: Variant in snapshot.get("nearby", []) as Array:
		if (
			value_nearby is Dictionary
			and String((value_nearby as Dictionary).get("resident_id", "")) == attacker_id
		):
			attacker_is_nearby = true
			break
	var place := snapshot.get("place", {}) as Dictionary
	var current_place := String(place.get("name", ""))
	var actions := {}
	if attacker_is_nearby and not attacker_id.is_empty():
		actions["搭话"] = _action_constraints("搭话", {"targets": [attacker_id]})
	if current_place == "诊所":
		actions["待着"] = _action_constraints("待着")
	else:
		actions["去"] = _action_constraints("去", {"places": ["诊所"]})
	return {
		"decision_id": String(wake_packet.get("decision_id", "")),
		"handling": ["replace_current"],
		"actions": actions,
		"post_injury_reaction": {
			"required": true,
			"question_target": attacker_name,
			"clinic_place": "诊所",
		},
	}


func _medical_response_constraints(conversation: Dictionary) -> Dictionary:
	var medical_value: Variant = conversation.get("medical_context", {})
	if medical_value == null or not medical_value is Dictionary:
		return {}
	var medical := medical_value as Dictionary
	var options_value: Variant = medical.get("response_options", [])
	if options_value == null or not options_value is Array:
		return {}
	var options := options_value as Array
	if (
		String(medical.get("role", "")) != "patient"
		or String(medical.get("status", "")) != "active"
		or options.is_empty()
	):
		return {}
	return {
		"fields": ["request_id", "response_kind"],
		"request_id": String(medical.get("request_id", "")),
		"response_kinds": options.duplicate(),
		"required": true,
	}


func _conversation_follow_up_constraints(snapshot: Dictionary) -> Dictionary:
	var options: Array[Dictionary] = []
	for option_value: Variant in snapshot.get(
		"conversation_follow_up_options",
		[],
	) as Array:
		if not option_value is Dictionary:
			continue
		var option := option_value as Dictionary
		var option_id := String(option.get("option_id", ""))
		var meaning := String(option.get("meaning", ""))
		if option_id.is_empty() or meaning.is_empty():
			continue
		options.append({
			"option_id": option_id,
			"meaning": meaning,
		})
	if options.is_empty():
		return {}
	return {
		"fields": (
			AgentContractScript.CONVERSATION_FOLLOW_UP_FIELDS as Array
		).duplicate(),
		"options": options,
		"required": false,
	}


func _conversation_conflict_intent_constraints(snapshot: Dictionary) -> Dictionary:
	var options: Array[Dictionary] = []
	for value_option: Variant in snapshot.get("conflict_tension_options", []) as Array:
		if not value_option is Dictionary:
			continue
		var option := value_option as Dictionary
		if String(option.get("kind", "")) != "attack":
			continue
		var cause_id := String(option.get("option_id", "")).strip_edges()
		var target_id := String(option.get("target_resident_id", "")).strip_edges()
		if cause_id.is_empty() or target_id.is_empty():
			continue
		options.append({
			"cause_id": cause_id,
			"target_resident_id": target_id,
			"target_name": String(option.get("target_name", "")),
			"meaning": String(option.get("meaning", "")),
		})
	if options.is_empty():
		return {}
	return {
		"fields": ["action_id", "type", "target_resident_id", "attack_kind", "cause_id", "line"],
		"attack_kinds": AgentConflictContractScript.ATTACK_KINDS.duplicate(),
		"options": options,
		"required": false,
	}


func _social_attention_constraints(snapshot: Dictionary) -> Dictionary:
	var exposures := snapshot.get("social_exposures", []) as Array
	if exposures.is_empty():
		return {}
	var exposure := exposures[0] as Dictionary
	return {
		"fields": (
			AgentContractScript.SOCIAL_ATTENTION_FIELDS as Array
		).duplicate(),
		"exposure_id": String(exposure.get("exposure_id", "")),
		"matter_id": String(exposure.get("matter_id", "")),
		"matter_revision": int(exposure.get("matter_revision", 0)),
		"option_ids": (
			exposure.get("options", []) as Array
		).duplicate(),
		"required": false,
	}


func _social_assignment(snapshot: Dictionary) -> Dictionary:
	for matter_value: Variant in snapshot.get("social_matters", []) as Array:
		var matter := matter_value as Dictionary
		var assignment_value: Variant = matter.get("assignment")
		if not assignment_value is Dictionary:
			continue
		var assignment := assignment_value as Dictionary
		if assignment.is_empty():
			continue
		return assignment.duplicate(true)
	return {}


func _exile_vote_constraints(
	snapshot: Dictionary,
) -> Dictionary:
	var vote := snapshot.get("exile_vote", {}) as Dictionary
	if vote.is_empty():
		return {}
	var candidate_ids: Array[String] = []
	for id_value: Variant in vote.get("candidate_ids", []) as Array:
		candidate_ids.append(String(id_value))
	if candidate_ids.is_empty():
		return {}
	return {
		"fields": (
			AgentContractScript.EXILE_VOTE_FIELDS as Array
		).duplicate(),
		"candidate_ids": candidate_ids,
		"round_day": int(vote.get("round_day", 0)),
		"settle_clock": String(vote.get("settle_clock", "")),
		"max_line_characters": 80,
		"required": bool(vote.get("forced", false)),
	}


func _night_skill_constraints(
	snapshot: Dictionary,
) -> Dictionary:
	var skill := snapshot.get("night_skill", {}) as Dictionary
	if skill.is_empty():
		return {}
	var skill_ids: Array[String] = []
	for skill_value: Variant in skill.get("skills", []) as Array:
		skill_ids.append(String(skill_value))
	var candidate_ids: Array[String] = []
	for id_value: Variant in skill.get("candidate_ids", []) as Array:
		candidate_ids.append(String(id_value))
	if skill_ids.is_empty() or candidate_ids.is_empty():
		return {}
	return {
		"fields": (
			AgentContractScript.NIGHT_SKILL_FIELDS as Array
		).duplicate(),
		"skills": skill_ids,
		"candidate_ids": candidate_ids,
		"round_day": int(skill.get("round_day", 0)),
		"settle_clock": String(skill.get("settle_clock", "")),
		"max_line_characters": 80,
		"required": false,
	}


func _social_response_constraints(
	snapshot: Dictionary,
) -> Dictionary:
	var matters: Array[Dictionary] = []
	for matter_value: Variant in snapshot.get(
		"social_matters",
		[],
	) as Array:
		var matter := matter_value as Dictionary
		var options := matter.get("options", []) as Array
		if options.is_empty():
			continue
		var option_ids: Array[String] = []
		for option_value: Variant in options:
			var option := option_value as Dictionary
			option_ids.append(String(option.get("option_id", "")))
		matters.append({
			"matter_id": String(matter.get("matter_id", "")),
			"matter_revision": int(matter.get("revision", 0)),
			"response_round_id": String(
				matter.get("response_round_id", "")
			),
			"option_ids": option_ids,
		})
	if matters.is_empty():
		return {}
	return {
		"fields": (
			AgentContractScript.SOCIAL_RESPONSE_FIELDS as Array
		).duplicate(),
		"matters": matters,
		"required": false,
		"max_public_text_characters": 80,
	}


func _action_constraints(action_type: String, parameters := {}) -> Dictionary:
	var constraints := (parameters as Dictionary).duplicate(true)
	constraints["fields"] = (AgentContractScript.ACTION_FIELDS[action_type] as Array).duplicate()
	return constraints


func _conversation_is_traveler(conversation: Dictionary) -> bool:
	var with_id := String(conversation.get("with_resident_id", "")).strip_edges()
	return not with_id.is_empty() and not _resident_names.has(with_id)


func _traveler_relationship_beat_kinds(
	conversation: Dictionary,
) -> Array[String]:
	var relationship := conversation.get("traveler_relationship", {}) as Dictionary
	var affinity := int(relationship.get("affinity", 50))
	if relationship.is_empty() or affinity < 53:
		return []
	if affinity < 63:
		return ["personal_view", "reciprocal_question"]
	if affinity < 80:
		return ["old_topic", "practical_care", "personal_view"]
	if affinity < 90:
		return ["personal_feeling", "unfinished_concern", "private_worry"]
	return ["personal_stake", "safe_place", "shared_rapport"]


func _known_place_names() -> Array[String]:
	var names: Array[String] = []
	for value: Variant in _initialization.get("places", []) as Array:
		if typeof(value) == TYPE_DICTIONARY:
			names.append(String((value as Dictionary).get("name", "")))
	return names


func _known_other_resident_ids() -> Array[String]:
	var result: Array[String] = []
	for value: Variant in _initialization.get("residents", []) as Array:
		if value is Dictionary:
			result.append(String(
				(value as Dictionary).get("resident_id", ""),
			))
	result.sort()
	return result


func _index_resident_names() -> void:
	var me := _initialization.get("me", {}) as Dictionary
	_resident_names[String(me.get("resident_id", ""))] = String(
		(me.get("attributes", {}) as Dictionary).get("name", ""),
	)
	for value: Variant in _initialization.get("residents", []) as Array:
		if typeof(value) == TYPE_DICTIONARY:
			var resident := value as Dictionary
			_resident_names[String(resident.get("resident_id", ""))] = String(resident.get("name", ""))


func _wealth_label(money: int) -> String:
	if money >= 80:
		return "殷实"
	elif money >= 55:
		return "宽裕"
	elif money >= 30:
		return "普通"
	else:
		return "拮据"


func _reputation_label(reputation: int) -> String:
	if reputation >= 65:
		return "很高"
	elif reputation >= 40:
		return "较高"
	elif reputation >= 20:
		return "一般"
	else:
		return "低下"


func _person(resident_id_value: Variant, supplied_name: Variant = "") -> String:
	var resident_id := String(resident_id_value)
	var name := String(supplied_name)
	if name.is_empty():
		name = String(_resident_names.get(resident_id, ""))
	if name.is_empty():
		return _safe(resident_id)
	return "%s｜%s" % [_safe(resident_id), _safe(name)]


func _join_people(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY or (value as Array).is_empty():
		return "无"
	var people: Array[String] = []
	for resident_id: Variant in value as Array:
		people.append(_person(resident_id))
	return "、".join(people)


func _join(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY or (value as Array).is_empty():
		return "无"
	var values: Array[String] = []
	for item: Variant in value as Array:
		values.append(_safe(item))
	return "、".join(values)


func _render_time(time: Dictionary) -> String:
	return "第%s天%s %s" % [
		_safe(time.get("day", "")),
		_safe(time.get("period", "")),
		_safe(time.get("clock", "")),
	]


func _condition_severity_label(severity: String) -> String:
	match severity:
		"serious":
			return "严重"
		"noticeable":
			return "明显"
		_:
			return "轻微"


func _condition_state_label(state: String) -> String:
	return "恢复中" if state == "recovering" else "仍在持续"


func _condition_urgency_label(urgency: String) -> String:
	match urgency:
		"high":
			return "高"
		"medium":
			return "中"
		_:
			return "低"


func _safe(value: Variant) -> String:
	return PromptTextScript.escape_dynamic(value)


func _load_static_prompt() -> String:
	var sections: Array[String] = []
	for layer: Dictionary in STATIC_LAYERS:
		var heading := String(layer["heading"])
		var tag := String(layer["tag"])
		var content := _load_layer(String(layer["directory"]))
		if not content.is_empty():
			sections.append("<%s>\n## %s\n\n%s\n</%s>" % [tag, heading, content, tag])
	return "\n\n".join(sections)


func _load_layer(directory_name: String) -> String:
	var directory_path := _prompt_root.path_join(directory_name)
	var directory := DirAccess.open(directory_path)
	if directory == null:
		_load_errors.append("无法读取静态提示词目录：%s" % directory_path)
		return ""
	var filenames: Array[String] = []
	directory.list_dir_begin()
	var filename := directory.get_next()
	while not filename.is_empty():
		if not directory.current_is_dir() and filename.ends_with(".md"):
			filenames.append(filename)
		filename = directory.get_next()
	directory.list_dir_end()
	filenames.sort()
	if filenames.is_empty():
		_load_errors.append("静态提示词目录没有 .md 文件：%s" % directory_path)
		return ""
	var contents: Array[String] = []
	for prompt_filename: String in filenames:
		var path := directory_path.path_join(prompt_filename)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			_load_errors.append("无法读取静态提示词文件：%s" % path)
			continue
		var content := file.get_as_text().strip_edges()
		if content.is_empty():
			_load_errors.append("静态提示词文件为空：%s" % path)
			continue
		contents.append(content)
	return "\n\n".join(contents)
