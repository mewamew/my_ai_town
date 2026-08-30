# AGENT_HANDOFF — 给未来 agent 的交接包（2026-08-12）

> **这是你（新 agent）接手本项目的第一站。** 复制下面的"初始提示词"给新会话，
> 读完它你就能接续猫鼠玩法的开发。工作目录 `F:\my_ai_town`（真实开发），
> C 盘镜像 `C:\Users\Administrator\.openclaw\workspace\2026-08-11-05-14-53\my_ai_town\`。

---

## 一、初始提示词（直接粘贴给新会话）

```
你接手的是 my_ai_town（AI 小镇）项目——Godot 4.7 + 纯 GDScript 的 LLM 驱动生活模拟游戏。
F:\my_ai_town 是真实开发目录。开工前按顺序读以下文件（都是中文，读完再动手）：

1. F:\my_ai_town\PROJECT_GUIDE.md        —— 项目总览 + 14 项本地改造清单
2. F:\my_ai_town\docs\学习笔记\猫鼠玩法实战总结_20260812.md  —— 猫鼠全链路（暗杀/制服/公告/目击者）怎么实现的、修过哪些 bug、还有哪些坑
3. F:\my_ai_town\docs\学习笔记\加新动作全链路检查清单_20260812.md —— 加任何新东西先查这个（动作10关/事件4处/数据纯JSON 分级表）
4. F:\my_ai_town\docs\学习笔记\卧底暗杀全链路_20260812.md     —— 暗杀动作的完整实现细节
5. F:\my_ai_town\game\prompts\roles\undercover.md + police.md  —— 卧底/警察的提示词规则（改玩法先看这里）
6. F:\my_ai_town\docs\学习笔记\动作活动全览与资产体系_20260812.md —— 16种动作/66种活动清单 + 提示词结构 + 资产体系与"加家具→坐标→新活动"方法论 + 已做个性化改造汇总

已知未解决的坑（接手后优先处理，见猫鼠总结第六章）：
- 对话卡死：搭话后 CONVERSATION_REPLY_REQUIRED 循环（闻叙被周既明搭话卡死）
- 白天目击者太宽松：卧底白天连杀多次"无人察觉"
- 警察 subdue 注入过宽：对所有人注入制服选项，易误伤平民
- 卧底节奏过快：花子 1 天 7 杀，考虑暗杀冷却

验证方式：游戏跑起来看 %APPDATA%\Godot\app_userdata\我的ai小镇\logs\ 里的
[AGENT] 行为日志和 [CATMOUSE] 猫鼠事件日志；改动后先跑 tests/ 里对应 diag_* 诊断脚本，
再真实运行验证（fixture 直调不走契约校验，漏验证必出白名单 bug）。
```

---

## 二、项目速览

| 项 | 值 |
|---|---|
| 真实开发目录 | `F:\my_ai_town` |
| Godot 引擎 | `F:\tools\godot\Godot_v4.7.1-stable_win64_console.exe`（无头测试）/ 同目录 `_win64.exe`（开窗口） |
| 游戏数据目录 | `%APPDATA%\Godot\app_userdata\我的ai小镇\`（存档/日志/LLM请求） |
| 行为日志 | `...\我的ai小镇\logs\godot.log`（[AGENT]/[CATMOUSE] 前缀） |
| 玩法 | 猫鼠：3 卧底（暗杀）+ 1 警察（制服查案），平民官方人格 |

## 三、关键文件地图（改什么看什么）

### 玩法提示词（改"人设/规则"先看这里）
```
game/prompts/roles/undercover.md        —— 卧底规则（覆盖条款/夜间流程/暗杀提交模板）
game/prompts/roles/police.md            —— 警察规则（查案方法/制服参数/公告引导）
game/prompts/background/10_town_common_knowledge.md —— 小镇常识（敲门规则已改：白天访客才敲）
game/world/data/town/resident_catalog.json —— 16 居民数据（卧底3+警察1+平民12官方人格）
```

### 动作/校验链（改"动作"看这里，配合 10 关清单）
```
game/agent/AgentContract.gd                    —— ACTION_TYPES + ACTION_FIELDS 白名单
game/world/runtime/action/TownActionTypeRegistry.gd —— ALL_TYPES/T4/T7 注册表
game/world/runtime/action/TownActionValidation.gd    —— 字段白名单（双份）
game/agent/conflict/AgentConflictContract.gd   —— TENSION_KINDS + normalize 别名 + prompt_constraints
game/agent/prompt/AgentPromptCompiler.gd       —— 提示词编译（actions 选项生成=第10关）
game/world/runtime/TownWorldRuntime.gd         —— _prepare/_activate 分派 + 注入 + 公告 + 案件档案
```

### 猫鼠机制（核心函数，都在 TownWorldRuntime.gd）
```
_prepare_assassination_action    卧底暗杀判定（身份/空间/距离）
_activate_assassination_action   暗杀即时结算（confirm_resident_death）
_collect_assassination_witnesses 目击者判定
_death_announcement_text         公告三态（暗杀/制服卧底/制服平民）
_police_death_cases              警察案件档案
_prepare_subdue_action           ／制服判定（警察身份）
_activate_subdue_action          ／制服结算
_decorate_conflict_tension_options 卧底/警察选项注入
_poll_resident_replacement       禁用：新居民入镇机制（直接 return）
```

### 测试（改完必跑）
```
game/tests/diag_assassinate.gd            —— 暗杀全链路 12 项
game/tests/diag_assassinate_witness.gd    —— 目击者 12 项
game/tests/diag_assassinate_range.gd      —— 距离 9 项
game/tests/diag_subdue.gd                 —— 制服全链路 7 项
game/tests/diag_subdue_announcement.gd    —— 制服公告三态 5 项
game/tests/town_world_action_type_registry_test.gd —— 注册表 79 项（数量=16 种动作）
game/tests/town_conflict_contract_test.gd —— 冲突契约 35 项
game/tests/diag_werewolf_vote.gd         —— 审讯会投票语义 72 项
game/tests/diag_assembly_state_machine.gd —— 审讯会状态机+契约一致性 161 项
game/tests/diag_assembly_live.gd         —— 审讯会实机验收（真实LLM ~5分钟，开新档自动快进到第2天08:00；用法见 docs/审讯会实机测试指南-20260829.md）
运行：<godot> --headless --path F:/my_ai_town/game --script res://tests/<文件名>
```

---

## 四、当前状态（2026-08-12 定格）

### 已完成
- 卧底暗杀全链路 ✅（选项注入/判定/结算/目击者/公告）
- 警察制服动作 ✅（按 10 关清单一次通过，公告揭露卧底身份）
- 发布公告动作 ✅（修复"注册了但 LLM 看不到"，广场才可选）
- 死亡公告三态 ✅（暗杀不说凶手/制服卧底揭露/制服平民说误伤）
- 平民人格恢复官方 ✅（只留卧底3人+警察改造人格）
- 禁用新居民入镇 ✅（死人不补位）
- 角色提示词分流 ✅（undercover.md/police.md 编译源注入 system）
- **居民个人角色规则 ✅**（2026-08-12 晚，方案A：`prompts/roles/<resident_id>.md` 按 ID 加载，现有林岚/唐小满/罗远/许照 4 份；加规则=建文件无需改代码。详见动作活动全览笔记第四章）
- **UI"旅行者"旁白→动态化身名 ✅**（2026-08-12 晚：TownUiAdapter/UnifiedConversationScreen/TownUiRuntimeHost 共 9 处硬编码改为 `_player_avatar_name()`；注意居民旧记忆里的"旅行者"条目不会自动迁移）

### 已知特性（2026-08-12 确认）
- **游戏内编辑居民资料不影响 Agent prompt**：同局改欲望/性格，LLM 决策的 system 不变（只改 world 侧数据）；存档读档后才生效。改人格+个人规则文件会脱节

### 已验证的实战结果
- 第1天：花子7杀（含同伙乔一鸣+灭口目击者白芷）、谢眠2杀、闻叙制服谢眠
- 第2天：闻叙主动锁定花子→花房咖啡馆制服→公告揭露 → **警察完胜 3 卧底全清除**

### 待办（按优先级）
1. **对话卡死**：CONVERSATION_REPLY_REQUIRED 循环（最影响体验）
2. **白天目击者太宽松**：卧底白天连杀无人察觉
3. **subdue 注入过宽**：警察对所有人有制服选项，易误伤平民（建议改为"有嫌疑的"才注入）
4. **卧底节奏过快**：考虑暗杀冷却（如每日上限）
5. 目标临死前见过的人不算目击者（信息缺口，可选）

### 2026-08-16 狼人杀化 MVP 已落地
- 夜间(20:00-08:00)暗杀死亡延迟到次日 08:00 统一公布（`TownWerewolfRuntime.gd`）
- 每天 18:00 镇民大会 → LLM 决策附件 `exile_vote` 投票 → 19:30 开票放逐最高票并公布身份（平票流会）
- 胜负判定：卧底全灭=镇民胜；平民全灭/平民≤卧底=卧底胜；无卧底居民的世界不激活
- 存档域 `werewolfState`（SaveCodec/RestoreState/create_save_snapshot/恢复赋值 4 处已接）
- 提示词：common_knowledge 大会规则 + undercover/police 投票策略章节
- 验证：`tests/diag_werewolf_vote.gd` 48 项 PASS；回归 registry(79)/foundation(1236)/agent(967)/contract/prompt 全绿
- 已知坑：`snapshot.exile_vote` 空字典会被合同校验拒（TWR 侧已做"空则不带键"）；fixture 世界无卧底居民（diag_undercover_runtime 的 3 卧底断言因此既有失败）；gateway continuity 测试的 provider 绑定报错为上一轮多模型合并遗留，与本次无关
- 待观察：LLM 真实投票质量（fixture 只验证了世界侧逻辑）；可选进阶——夜间强制平民回家、投票前发言环节、遗言

### 2026-08-16 P0/P1 加固（同轮补丁）
- **无卧底世界整体停用**：`feature_active` 同时守卫死亡延迟/镇民大会/投票接口，普通与 fixture 世界不再开会放逐
- **终局语义**：夜间胜负当夜锁定 `gameOver/winner`（阻止投票与开票），胜负公告经 `winnerAnnounced` 标记压到次日 08:00 与死讯一起揭晓；白天终局仍即时公告
- **P0 修复**：`settle_vote_round` 在 gameOver 时清空并跳过开票，杜绝"终局后仍放逐最高票无辜者"
- **信息泄露封堵**：夜间待公布死亡不写公共事件日志（08:00 补记）、不进警察案件档案、不进 `get_public_death_events`；`TownResidentStateProjection` 与 wake nearby 感知在天亮前保持死者生前外观
- **投票参与度**：18:00 开会唤醒改为 `wake_while_current_action=true`，居民进行中的活动不打断也能投票
- 旧档兼容：`werewolfState.gameOver=true` 且无 `winnerAnnounced` 键的旧档，恢复时视为已公告，避免升级后次日重复广播

### 2026-08-17 日志可读性 + 每次运行独立存档
- 新增 `world/runtime/TownLog.gd`：`line(category, message)` 在日志类别切换（AGENT/CATMOUSE/WEREWOLF）时自动空一行；`section(title)` 打阶段横幅（天亮/大会/开票/胜负）
- 主干运行日志已迁移到 TownLog：TownWorldRuntime / TownWerewolfRuntime / AgentPromptCompiler 的 `[AGENT] 可选` / TownWorldAgentGateway 的 `[AGENT] 请求失败`
- **每次运行一个新日志文件**：`run-game-log.ps1` 启动游戏，自动生成 `logs\runs\godot-<yyyyMMdd-HHmmss>-pid<PID>.log`；控制台仍实时显示，历史日志不互相覆盖，另存 `latest.log`，默认保留最近 100 份
- **测试日志隔离**：`run-test-log.ps1 -ScriptPath res://tests/xxx.gd`，输出到 `logs\tests\test-<时间戳>-pid<PID>.log`，不再污染真实游戏的默认 `godot.log`
- `tail-log.ps1` 默认追踪 `logs\runs` 里最新一份，支持 `-Path` / `-Filter`
- 注意：TWR 阶段日志用 tick 分钟（`_label_for_minute`）打时间，不能再用 `world._time_label()`——一次 advance 跨多分钟时 `_time_label` 读到的是终态时间，横幅会错标

### 2026-08-17 身份技能第一批（医生/查验/嫁祸/警察额度）
- 新文件 `world/runtime/TownRoleSkillRuntime.gd`；技能走决策附件 `night_skill`（仿 exile_vote），不新增动作类型
- 状态放在 `werewolfState.roleSkills`（复用存档域，恢复时 `ensure_state` 自愈旧档）
- **白芷医生 `doctor_protect`**：20:00 后可提交，当夜被守护目标遇暗杀时在 `_activate_assassination_action` 直接挡下；08:00 结算时把该目标从 pending 死亡队列摘除并投递"守诊结果/被救/暗杀失败"事件；不可连续两夜守同一人
- **许照图书管理员 `scholar_inspect`**：3 次额度，每夜查验一人，08:00 收到"查验结果"行为线索（入夜位置/同区域者/今晨位置），不给阵营答案
- **卧底嫁祸 `undercover_frame`**：全阵营共用 1 次；提交后下一次暗杀发生时消费，警察案件档案的 `clue` 指向被嫁祸者
- **警察制服额度**：2 次；正确制服扣 1 次，错杀平民立即停职（额度清零 + 全镇公告）；`_prepare_subdue_action` 和 subdue 选项注入都按额度拦截；暗杀死因对警察脱敏（只写"被暗杀"，凶手名不再直接出现在案件档案）
- 合同：`night_skill` 字段白名单/校验/canonicalize 已接入 AgentContract/AgentContractSnapshot/TownActionValidation；EVENT_TYPES 补上"目睹暗杀/守诊结果/查验结果/被救/暗杀失败"（修复目击者决定被 `events.type 不是合法事件类型` 拒绝的旧坑）
- 提示词：common_knowledge 夜间身份技能公开规则；`resident_bai_zhi_01.md` 医生技能；`resident_xu_zhao_01.md` 查验技能；undercover 嫁祸策略；police 额度/停职/假线索警告
- 测试：`diag_role_skills.gd` 77 项 PASS；回归 foundation(1221)/agent(967)/presentation(1886)/registry(79)/werewolf(71) 全绿
- 已知边界：医生提交晚于暗杀时挡不住（建议提示词强调 20:00 尽快提交）；嫁祸不污染目击事件，只污染警察档案线索

### 2026-08-17 暗杀节奏：只限夜间 + 全队每晚一杀
- `TownWerewolfRuntime.undercover_kill_available / record_night_kill / night_index`：夜序按 20:00 归属当天、00:00-08:00 归属前一晚
- 白天 `_prepare_assassination_action` 拒绝、`_decorate_conflict_tension_options` 不再注入 assassinate、`_activate_assassination_action` 双保险拒绝；同夜第二次暗杀（含被医生挡下）一律拒绝
- 状态 `werewolfState.undercoverKillLastNight`（旧档缺键默认 -1，无需迁移）
- 提示词：undercover.md 明确"只有夜里能杀、全队每晚一次"；common_knowledge 公开"卧底只会在夜里动手且每晚最多一起暗杀"
- 测试更新：diag_assassinate/range/indoor/witness/police_investigate 全部推进到 20:00 夜间再验证；diag_role_skills 新增夜间门禁+配额场景（94 项）
- 回归全绿：foundation(1185)/agent(967)/presentation(1886)/save(179)/werewolf(71)/role_skills(94)/assassinate 系列全 PASS

---

## 五、血泪教训（新 agent 必读）

1. **加动作必须走 10 关清单**——漏 TENSION_KINDS 或 ACTION_TYPES = 居民决策卡死循环
2. **fixture 直调不走契约校验**——新字段必须真实运行验证，`_record_error` 加 print 是定位关键
3. **动作注册 ≠ LLM 能看到**——还要在 AgentPromptCompiler 生成选项（第 10 关）
4. **字段名必须和契约一致**——官方用 `target_name`，写 `target_resident_name` 会被拒
5. **存档/白名单不同步**——me 白名单漏字段 = "不是允许字段" 模型分配失败
6. 改 prompt 文件后要**重启游戏**才生效（编译时读取）
7. 任何改动先在 C 盘镜像同步一份（`cp /f/.../game/x → C:/Users/Administrator/.openclaw/workspace/2026-08-11-05-14-53/my_ai_town/game/x`）
