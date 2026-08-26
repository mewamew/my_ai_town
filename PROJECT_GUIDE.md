# PROJECT_GUIDE — my_ai_town 项目导航手册（新架构版）

> **给未来 agent 的一封信**：这是你接手本项目的第一份文档。读完后你会知道项目是什么、
> 代码怎么组织（特别是官方 #109 拆分后的新模块结构）、核心机制如何运转、之前做过哪些
> 改造、以及动手改代码前必须知道的坑。
>
> 项目路径：`F:\my_ai_town_upstream`（本手册所在仓库 = wolf-migrate 分支 worktree）
> 主仓库：`F:\my_ai_town`（检出 main，旧巨石架构的历史参考仍在这里）
> 官方仓库：`https://github.com/mewamey/my_ai_town`（origin 远程）
> 更新日期：2026-08-26

---

## 1. 项目是什么

**AI Town（我的AI小镇）**：Godot 4.7 + 纯 GDScript 的单机生活模拟游戏。小镇居民由 LLM 驱动，
结合性格、职业、关系、记忆、当前处境自主决定"下一步做什么、去哪、和谁交谈"。

- **规模**：约 660 个 `.gd` 文件（world 侧 234 个 runtime 模块 + 54 个 presentation + 数据/地图，
  agent 侧 60+ 个，tests 90 个），assets 约 500MB
- **运行**：Godot 4.7.1 打开 `game/project.godot`，需配置 LLM Provider + API Key
- **本机 Godot**：`F:\tools\godot\Godot_v4.7.1-stable_win64_console.exe`
- **游戏数据目录**：`%APPDATA%\Godot\app_userdata\我的ai小镇\`（存档/居民记忆/模型配置）

### 架构现状（2026-08）

官方 PR #109 把 23,509 行的 `TownWorldRuntime.gd` 巨石拆分为 `game/world/runtime/` 下
**20 个业务子域 + 根 17 个文件，共 234 个模块**；我们在此基础上：
1. 完成了狼人杀化改造向新架构的迁移（wolf-migrate 分支），并为保证迁移质量做了一轮
   **持续架构拆分**（`docs/architecture/TownWorldRuntime拆分基线.md` 记录了 E0→F2j 全过程：
   TownWorldRuntime 从 23,145 行降到 2,412 行、120 行以上大函数清零、公开接口/信号/存档全不退化）
2. 当前 `world/runtime/TownWorldRuntime.gd` 约 3,936 行——比拆分终点多出的 ~1,500 行
   是狼人杀改造（投票/死亡公告/处决/技能）按"总控协调 + 领域模块实现"回流的主控入口
3. 所有拆分受架构守卫保护：`tools/guards/`（`run_guards.sh` + 世界运行时架构基线 JSON），
   改代码后必须跑守卫，防止私有访问/大函数/巨石文件回潮

### 与旧版（main 分支）的区别

- 旧版 `game/world/runtime/TownWorldRuntime.gd` 是一个 2.3 万行的上帝文件，所有逻辑堆在一起；
  新版按领域拆成 20 个子目录，总控只保留公开兼容入口与跨域协调
- 旧版 `game/agent/` 是 6 个文件（AgentContract/ResidentRuntime/DecisionExecution/…）；
  新版拆成 `contract/`（11 个分领域合同）+ `memory/`（13 个记忆子系统）+ `model/`（14 个 Provider）+
  `avatar_memory/`（5 个）+ `soul/`（开局人格分析）+ `lifecycle/`
- 若看不懂新架构想对照旧代码，去 `F:\my_ai_town`（main）看旧版 PROJECT_GUIDE 与 `docs/学习笔记/`
  ——但**旧版笔记的代码位置已失效**，只用来理解机制与意图

---

## 2. 目录结构总览

```
F:\my_ai_town_upstream\
├── PROJECT_GUIDE.md                 ← 本文件：新架构导航入口
├── README.md / AGENT_HANDOFF.md     ← 官方向导 / 交接说明
├── 狼人杀化改造记录.md / 更新日志.md
├── game\                            ← Godot 工程根目录（project.godot）
│   ├── agent\                       ← ★居民 Agent 系统（决策/记忆/模型/人格，全部在"Agent 侧"）
│   │   ├── AgentSystem.gd           ← Agent 会话管理（新游戏/读档/存档事务）
│   │   ├── ResidentRuntime.gd       ← 每个居民一个运行时（记忆+提示词+决策，1130 行）
│   │   ├── DecisionExecution.gd     ← LLM 请求发起 + 结果校验重试
│   │   ├── contract\                ← ★11 个分领域决策合同（Action/Conversation/Environment/Events/
│   │   │                                Identity/Medical/Snapshot/Social/Wake/WorkTasks/WorldFacts）
│   │   │                                —— 旧 AgentContract.gd 拆分而来，顶层留有薄入口
│   │   ├── memory\                  ← ★13 个记忆子系统（证据队列/整理/干预/老化/检索/形式记忆）
│   │   ├── avatar_memory\           ← 头像记忆模块（组织/检索/证据队列/存储，告别信）
│   │   ├── model\                   ← 14 个模型提供商（DeepSeek/火山/Kimi/MiniMax/Ollama/302AI/GLM…）
│   │   ├── prompt\                  ← ★AgentPromptCompiler.gd（system+user 组装）
│   │   ├── soul\                    ← AgentSoulProfile.gd（开局 OC 分析：身份倾向+关系线索）
│   │   ├── conflict\                ← 冲突合同（攻击/争执的 Agent 侧约束）
│   │   ├── lifecycle\               ← Agent 保存/会话纪元/居民状态编解码
│   │   └── debug\                   ← Agent 调试场景/批次工具
│   ├── world\                       ← ★世界系统（数据/运行规则/表现）
│   │   ├── contract\                ← TownWorldContract + TownWorldResultShapes（结果结构契约）
│   │   ├── integration\             ← ★跨世界-代理的集成层：TownWorldAgentGateway(3745行 泵驱动)、
│   │   │                                TownAgentProviderService、会话照片存储、形式档案服务
│   │   ├── data\town\               ← ★世界数据（catalog + 烘焙工具）：
│   │   │                                resident_catalog.json(居民) / town_world.json(地图活动烘焙) /
│   │   │                                work_chain_catalog.json(工作链) / interest_catalog.json(兴趣) +
│   │   │                                TownWorldDataBuilder/Validator/Scalars 等 30 个 .gd
│   │   ├── maps\                    ← 地图运行时（town/Town.gd、TownBase、interiors/ 室内5件、
│   │   │                                redesign_v2 资产几何）
│   │   ├── presentation\            ← ★表现层 54 个 .gd（10 个方向：animals/announcement/conflict/
│   │   │                                environment/game_flow/lifecycle/residents/session/town_runtime/ui）
│   │   ├── prototypes\              ← demo_launcher（试用启动器/导航 demo）
│   │   └── runtime\                 ← ★★★世界核心（234 个模块，见 §3 模块地图）
│   │       ├── TownWorldRuntime.gd  ← 总控：公开兼容入口+跨域协调（3936 行，不再有 120 行+大函数）
│   │       ├── TownWerewolfRuntime.gd ← ★狼人杀核心（夜间/天亮死讯/投票/放逐/警察设备）
│   │       ├── TownRoleSkillRuntime.gd ← ★身份技能（医生守诊/查验/嫁祸/警察额度）
│   │       ├── TownUndercoverDeadlineRuntime.gd ← ★卧底期限（5天+处决）
│   │       └── action\ activity\ agent\ animals\ condition\ conflict\ conversation\ environment\
│   │           event\ lifecycle\ log\ movement\ perception\ persistence\ presentation\ prop\
│   │           relationship\ social\ time\ work\   ← 20 个业务子域
│   ├── prompts\                     ← ★提示词资产
│   │   ├── rules\                   ← 6 篇规则（identity/behavior/data_authority/events/contract/examples）
│   │   ├── roles\                   ← 10 篇角色（police/undercover/8 个具名居民）
│   │   ├── background\              ← 10_town_common_knowledge.md（小镇常识+狼人杀大会规则）
│   │   ├── avatar_memory\           ← 2 篇（记忆整理 + 告别信）
│   │   └── memory\                  ← 10_memory_organizer.md（记忆整理器）
│   ├── tests\                       ← ★90 个测试/诊断脚本（见 §7）
│   ├── ui\                          ← 88 个 UI 场景脚本（town/settings/mobile/… 28 个方向）
│   ├── common\                      ← ProviderEndpointSecurity.gd 等共享工具
│   └── characters\ assets\ audio\   ← 美术音频资源
├── docs\
│   ├── architecture\TownWorldRuntime拆分基线.md ← ★★E0→F2j 拆分全过程与量化验收（必读）
│   ├── design\手机端适配设计.md
│   ├── CI排查手册.md / 存档迁移手册.md / 狼人杀迁移方案.md / 狼人杀迁移结果汇总.md /
│   │   狼人杀持续优化记录与踩坑手册-20260825.md
│   └── 学习笔记\                    ← ★新架构分层学习笔记（本批重建，机制+代码地图）
│       ├── 第1层_决策循环.md
│       ├── 第2层_世界数据模型.md
│       ├── 第3层_动作与活动系统.md
│       ├── 第4层_冲突与关系系统.md
│       ├── 第5层_记忆系统.md
│       └── 第6层_存档与表现.md
└── tools\guards\                    ← ★架构守卫（run_guards.sh + 基线 JSON + 检查脚本）
```

---

## 3. world/runtime 模块地图（234 个模块怎么找）

拆分的总原则：**每个领域子目录是一个"领域边界"，内部分为纯规则（Policy/Projection/Judgments）与
带副作用提交（Runtime/Command/Commit）两类**；总控 `TownWorldRuntime` 只做协调入口，不持有业务状态。
业务状态所有权已下放到各领域模块（如 `TownResidentRegistry` 拥有居民表、`TownWorkDomainRuntime`
拥有工作/岗位/货运/生产/职业服务五套状态）。

| 子域 | 文件数 | 职责与代表模块 |
|---|---|---|
| `action/` | 19 | 动作类型注册(`TownActionTypeRegistry`)、校验(`TownActionValidation`)、准备(`TownActionPreparationRuntime`)、预览(`TownActionPreviewRuntime`)、推进(`TownActionAdvancementRuntime`)、结算(`TownActionSettlementRuntime`)、结果(`TownActionResultRuntime`)、确认激活(`TownConfirmedActionActivationRuntime`)、闲置/等待/道具推进 |
| `activity/` | 24 | 活动运行时(`TownWorldActivityRuntime`)、候选预检(`TownActivityCandidatePreflightRuntime`)、步骤执行(`TownActivityStepExecutionRuntime`)、例程(`TownActivityRoutine*`)、出席(`TownActivityAttendanceRuntime`)、可达性缓存(`TownActivityReachabilityCache`) |
| `agent/` | 13 | ★World 侧的 Agent 决策管线：唤醒包投影(`TownAgentWakePacketProjection`)、唤醒上下文(`TownAgentWakeContextRuntime`)、决策分派(`TownAgentDecisionDispatchRuntime`)、提交(`TownAgentDecisionSubmissionRuntime`)、日程(`TownAgentDecisionSchedulingRuntime`)、信封(`TownAgentDecisionEnvelopeRuntime`)、初始化投影(`TownAgentInitializationProjection`) |
| `animals/` | 2 | 动物事实/命令（`TownAnimalFactRuntime`/`TownAnimalCommandRuntime`） |
| `condition/` | 8 | 居民身体状态与病况（推进/结算）、睡眠(`TownResidentSleepRuntime`)、诊所问诊(`TownClinicInterview*`)、诊所协调 |
| `conflict/` | 7 | 冲突运行时(`TownConflictRuntime`)、世界控制(`TownConflictWorldController`)、知识投影、张力选项、判断纯函数、Agent 桥 |
| `conversation/` | 8 | 对话主运行(`TownConversationRuntime`)、状态(`TownConversationState`)、后续动作(`TownConversationFollowUpActionRuntime`)、承诺提交(`TownConversationCommitmentSubmissionRuntime`)、玩家命令 |
| `environment/` | 1 | `TownWorldEnvironment`（天气/环境） |
| `event/` | 3 | 世界事件投递(`TownWorldEventDeliveryRuntime`)、按居民入队(`TownResidentEventQueueRuntime`)、投递投影 |
| `lifecycle/` | 10 | ★居民生命周期：注册表(`TownResidentRegistry`)、死亡(`TownResidentDeathPolicy`/`TownResidentDeathConfirmationRuntime`)、替补接纳、启动(`TownWorldStartPreparation`/`TownWorldStartCommitRuntime`)、世界定义状态(`TownWorldDefinitionState`) |
| `log/` | 12 | 世界日志域(`TownWorldLogDomainState`)、日志提交/存储/捕获、故事/活动/工作日志策略、文案纯函数 |
| `movement/` | 4 | 出发推进(`TownGoActionAdvancementRuntime`)、预取、玩家化身移动命令、位置提交(`TownResidentPositionCommitRuntime`) |
| `perception/` | 1 | `TownPerceptionRuntime`（感知刷新与空间网格索引） |
| `persistence/` | 14 | ★存读档：保存(`TownWorldSaveCommandRuntime`/`TownWorldSaveSnapshotProjection`) 、恢复候选(`TownWorldRestoreCandidateRuntime`/`TownWorldRestoreCommitRuntime`)、各分域恢复(Layout/People/Work/SocialState/Animals/State) |
| `presentation/` | 10 | 表现投影（居民状态/公共查询/行动语义/地点查询）、帧预算(`TownWorldFrameBudgetRuntime`)、遥测(`TownWorldTelemetryRuntime`) |
| `prop/` | 4 | 动态道具(`TownDynamicPropRuntime`)、道具命令、室内布局命令、道具动作准备(`TownPropActionPreparer`) |
| `relationship/` | 3 | 旅行者关系(`TownTravelerRelationshipRuntime`/`State`)、关系证据进度(`TownRelationshipEvidenceProgress`) |
| `social/` | 29 | ★社会系统：事项(`TownSocialMatterRuntime`/`TownSocialRegistry`)、回应轮次(`TownSocialResponseRoundRuntime`)、公告(`TownAnnouncement*`)、私信(`TownPrivateMessage*`)、邮政(`TownPostalMessageRuntime`)、口信、社会判断纯函数、评论区/布告栏 |
| `time/` | 1 | `TownWorldAdvanceRuntime`（帧/分钟推进分派，全游戏唯一时间推进开关） |
| `work/` | 44 | ★工作域：域门面(`TownWorkDomainRuntime`)、任务(`TownWorkTaskRuntime`)、排班(`TownStaffing*`)、职业服务(`TownOccupationService*`)、餐饮(`TownDiningServiceRuntime`)、诊所(见 condition)、生产(`TownProductionRuntime`)、货运(`TownCargo*`)、演出、植物研究 |
| 根目录 | 17 | 总控(`TownWorldRuntime`)、狼人杀3件套(见 §5)、启动(`TownWorldStartupValidator`/`TownWorldOpeningConfig`)、唤醒准备(`TownAgentWakePreparationRuntime`/`TownAgentWakeStateRuntime`)、室内布局、移动净空、抵达、地图遮挡、性能探针、日志分隔器(`TownLog`) |

**找文件的口诀**：先判断改的是"规则判断"（找 Policy/Projection/Judgments/Query）还是"执行提交"
（找 Runtime/Command/Commit/Settlement）；再按领域落到上表的子目录。**不要直接去改
TownWorldRuntime.gd**——新逻辑应进入对应领域模块，总控只加必要的公开兼容入口
（这就是拆分基线停线条件，见 §8）。

---

## 4. 核心机制：居民决策循环（7 环节）

```
世界唤醒 → 提示词编译 → LLM 决策 → 合同校验 → 世界执行 → 结果落定 → 记忆沉淀
   wake       compile       model      validate     execute     result     remember
  (World   (Agent        (Provider   (Agent      (World      (World      (Agent
   runtime   prompt)      side)       contract)   runtime)    runtime)    memory)
   agent/)
```

- 世界侧与 Agent 侧完全解耦：中间只通过 `wake_packet`（进）和 `decision`（出）交换数据
- 泵驱动：`world/integration/TownWorldAgentGateway.gd`（3745 行）按帧预算发起模型请求，
  并发上限 `MAX_CONCURRENT_MODEL_REQUESTS=3`、派发速率 `DISPATCH_RATE_PER_SECOND=0.65`
- **新架构落点**（与旧版不同，详细见 `docs/学习笔记/第1层_决策循环.md`）：
  - wake：`runtime/agent/TownAgentWakePacketProjection.gd` + `TownAgentWakeContextRuntime.gd`
    （分帧准备在 `TownAgentWakePreparationRuntime.gd`）
  - 派发：`runtime/agent/TownAgentDecisionDispatchRuntime.gd`
  - compile：`agent/prompt/AgentPromptCompiler.gd`
  - model：`agent/model/OpenAICompatibleModelProvider.gd`（默认兼容网关，含 302-ai/DeepSeek 等）
  - validate：`agent/contract/` 11 个分域合同（`TownWorldAgentGateway` 在消费前调用）
  - execute/result：`runtime/agent/TownAgentDecisionSubmissionRuntime.gd` + `TownAgentDecisionActionRuntime.gd`
    + 各领域结算；结果结构契约在 `world/contract/TownWorldResultShapes.gd`
  - remember：`agent/memory/ResidentMemorySystem.gd` + 13 个记忆子模块

**三种动作结果状态**：`completed` / `rejected` / `interrupted` / `replaced`（结果只有这 4 态）。

---

## 5. 本地改造：狼人杀化（新架构落点）

狼人杀改造已从旧巨石迁移进新模块，**3 个核心文件在 `world/runtime/` 根目录**：

| 模块 | 职责 |
|---|---|
| `TownWerewolfRuntime.gd` | 狼人杀核心：夜间（20:00-08:00）暗杀死亡不即时公告、天亮 08:00 统一公布死讯、镇民大会投票（08:00 开始/12:00 提醒/12:30 开票放逐，`VOTE_*` 常量）、胜负判定、警察设备（定位器，有效期 1440 分钟） |
| `TownRoleSkillRuntime.gd` | 身份技能：医生守诊(`doctor_protect`)、图书管理员查验(`scholar_inspect`)、卧底嫁祸(`undercover_frame`)；`DOCTOR_ID=resident_bai_zhi_01 白芷`、`SCHOLAR_ID=resident_xu_zhao_01 许照`；警察额度 `POLICE_CHARGES_MAX=2`、查验 `SCHOLAR_CHARGES_MAX=3`、日限 `INVESTIGATE_DAILY_LIMIT=2` |
| `TownUndercoverDeadlineRuntime.gd` | 卧底期限：第 5 天结束未杀完 → 第 6/7/8 天依次处决卧底；无辜全灭 → 警察失败 |

**关键常量**：
- 卧底：`resident_xie_mian_01 谢眠` / `resident_qiao_yiming_01 乔一鸣` / `resident_hanako_01 花子`
- 警察：`resident_wen_xu_01 闻叙`；医生：`resident_bai_zhi_01 白芷`；学者：`resident_xu_zhao_01 许照`
- 时间（absolute_minute，游戏 60 倍速）：夜间 1200（20:00）→ 480（08:00）；投票窗 480-750（12:30 开票）
- 提示词侧：`prompts/roles/police.md` / `undercover.md` / 8 个具名居民 md
  + `prompts/background/10_town_common_knowledge.md`（大会规则），经编译注入 system
- Agent 侧人格：`agent/soul/AgentSoulProfile.gd` 在开局做一次性 OC 分析（身份倾向+关系线索），
  特殊身份影响行为倾向；关系只作为"未确认线索"，必须经过真实事件才能变成世界事实

改造全链路与踩坑记录见 `docs/狼人杀持续优化记录与踩坑手册-20260825.md` 与 `docs/狼人杀迁移结果汇总.md`。

---

## 6. 数据资产与提示词

- **`world/data/town/`**：`resident_catalog.json`（居民定义：人格/职业/兴趣，运行时直接读）、
  `town_world.json`（地图/活动/工作链烘焙产物，运行时只读）、`work_chain_catalog.json`、
  `interest_catalog.json`；**改地图/活动/职业在烘焙工具 .gd（TownWorldDataBuilder 等）与 source 数据**，
  改完重新烘焙，别直接改 town_world.json
- **`game/prompts/`**：
  - `rules/` 6 篇：identity(10)/behavior(20)/data_authority(30)/events(35)/decision_contract(40)/examples(50)
  - `roles/` 10 篇：police + undercover + 8 个具名居民（黑白芷/花子/林岚/罗远/乔一鸣/唐小满/谢眠/许照）
  - `background/10_town_common_knowledge.md`、`avatar_memory/`（整理器+告别信）、`memory/10_memory_organizer.md`
- **`world/maps/`**：`town/Town.gd` + `TownBase.gd` + `interiors/`（房间几何/家具运行时/墙壁遮挡/楼层剖面）
- **`world/presentation/` 54 个**：表现层只读世界投影，UI 不要直接碰 runtime 状态

---

## 7. 测试体系（tests/ 90 个脚本）

**核心回归套件**（跑 Agent 离线全链路，输出 `TOWN_WORLD_AGENT_PASS checks=1015` 之类）：
- `town_world_agent_test.gd` —— 世界 Agent 套件（1,015 项），含 Gateway 看门狗/连续性测试
- `town_world_foundation_test.gd` —— 世界基础套件（约 1,500+ 项）
- `town_activity_test.gd`（1,551 项）/ `town_conversation_test.gd`（709 项）/
  `town_occupation_test.gd`（381 项）/ `town_world_save_test.gd`（181 项）/
  `agent_soul_profile_test.gd`/`resident_presentation_test.gd`（1,927 项）
- 狼人杀/警察诊断：`diag_werewolf_vote.gd`、`diag_police_*`、`diag_undercover*`、`diag_role_*`

**跑测试**（必须前台、限时 300s）：
```powershell
& "F:\tools\godot\Godot_v4.7.1-stable_win64_console.exe" --path "F:\my_ai_town_upstream\game" --headless --script "res://tests/town_world_agent_test.gd"
```

**跑架构守卫**（每次改 world 代码后必跑）：
```bash
F:\my_ai_town_upstream\tools\guards\run_guards.sh
```

---

## 8. 维护铁律（拆分基线约束，违反会被守卫拦）

1. **公开接口、信号、存档结构、世界版本不得退化**（这是 E0→F2j 全过程的停止条件）
2. **新增功能进领域模块**：`runtime/<领域>/` 下找 Policy/Projection 放纯规则、
   Runtime/Command 放带副作用提交；TownWorldRuntime 只加确有必要的公开兼容入口
3. **私有访问只减不增**：跨模块禁止 `world._xxx`；有类型组件是唯一合法状态通道
4. **不造大函数**：新模块超 ~500 行前按内部职责拆成独立协作者
5. **改动作/活动/玩法 = 全链路**：白名单(wake) → 动作菜单(compile) → 合同(agent/contract) →
   执行器(对应领域 runtime) → 结果(contract/TownWorldResultShapes) → 记忆(agent/memory)，
   只改任何一环都会断——详细见 `docs/学习笔记/第3层_动作与活动系统.md`
6. **改完必跑**：对应领域套件 + 完整 Agent 离线套件（48 项）+ 架构守卫 + 预加载资源检查

---

## 9. 排障速查

- **居民全体不动 / 无日志**：先看 `logs/runs/` 最新日志（时间戳 UTC，+8=北京）。两类已知根因：
  1. Provider `finish_reason` 返回非字符串（302-ai 网关返 custom 对象）→ `_complete_failure` 不回调、
     泵饿死 → 已修（`OpenAICompatibleModelProvider.gd` L529 类型防御）
  2. 刷新阶段准备永久 pending → `pump_frame_budgeted` 每帧 return 1 → 已修（Gateway
     `REFRESH_PREPARATION_STALL_FRAMES=300` 看门狗，超限走 continuity fallback）
- **卡顿探针**：`AI_TOWN_ADVANCE_PROFILE=1` 环境变量跑局 → `logs/` 出推进分项计时
- **LLM 请求落盘**：`REQUEST_LOG_ROOT`（排障时开、平时关）
- 更多见 `docs/CI排查手册.md` 与 `docs/狼人杀持续优化记录与踩坑手册-20260825.md`

---

## 10. 文档导航

| 想了解 | 看这个 |
|---|---|
| 架构拆分全过程/量化验收 | `docs/architecture/TownWorldRuntime拆分基线.md` |
| 决策循环（新架构代码地图） | `docs/学习笔记/第1层_决策循环.md` |
| 世界数据模型 | `docs/学习笔记/第2层_世界数据模型.md` |
| 动作/活动系统、加新动作 | `docs/学习笔记/第3层_动作与活动系统.md` |
| 冲突/关系系统 | `docs/学习笔记/第4层_冲突与关系系统.md` |
| 记忆系统 | `docs/学习笔记/第5层_记忆系统.md` |
| 存档与表现 | `docs/学习笔记/第6层_存档与表现.md` |
| 狼人杀改造全貌/踩坑 | `docs/狼人杀化改造记录.md`、`docs/狼人杀迁移结果汇总.md`、`docs/狼人杀持续优化记录与踩坑手册-20260825.md` |
| 手机端适配 | `docs/design/手机端适配设计.md` |
| 存档迁移 | `docs/存档迁移手册.md` |

---

*本手册由项目分析+实战改造过程中沉淀，后续改动请同步更新本文件；新架构代码位置请以本文与
拆分基线文档为准，旧版学习笔记（main 分支）仅作机制参考。*