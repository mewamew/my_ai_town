//! 客户端命令（页面 → 后端）。
//!
//! 改动状态的命令都带请求编号 `request_id`（加入小镇用操作编号 `op_id`）。后端对这条命令的
//! 回执、查询结果和错误只发给发出命令的连接，并带上同一个编号；前端按编号配对。
//! 化身的连续输入 `AvatarInput` 不回执，没有请求编号。
use crate::{
    ActiveModelChoice, AgentLimits, ContentCommand, LibraryFilter, ModelChoice,
    NotebookDetailQuery, NotebookQuery, PlaceNear, ProviderConfigMsg, ProviderKeyMsg,
    TemplateFields,
};
use serde::{Deserialize, Serialize};

/// 意图草案，是动作草案（actions.rs 的 ActionDraft）的一部分。字段封闭（deny_unknown_fields）：
/// 绝对坐标与绝对时刻在此不可表示（Invariant 3）。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct IntentDraft {
    pub verb: String,
    /// 目的地 / 活动地点（封闭集合内的 locale id）
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub locale: Option<String>,
    /// 落脚点（封闭集合内的 station id）；Agent 的道具和任务另有字段。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub target: Option<String>,
    /// 相对时长（分钟）。相对量合法，绝对时刻非法。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub duration_minutes: Option<f64>,
    /// 结束谓词。条件晚一点满足仍成立，时刻则会过期。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub until: Option<UntilPredicate>,
}

/// 意图的结束谓词；线上取值就是中文「天亮」「天黑」。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum UntilPredicate {
    #[serde(rename = "天亮")]
    Dawn,
    #[serde(rename = "天黑")]
    Dusk,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ClientMsg {
    SetWeather {
        world_id: String,
        request_id: String,
        expected_revision: u64,
        mode: crate::WeatherMode,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        kind: Option<crate::WeatherKind>,
    },
    Avatar {
        world_id: String,
        request_id: String,
        #[serde(default)]
        epoch: String,
        #[serde(default)]
        sequence: u64,
        command: crate::AvatarCommand,
    },
    AvatarInput {
        world_id: String,
        epoch: String,
        sequence: u64,
        navigation_revision: u64,
        direction: [f64; 2],
        /// 按住了奔跑键。
        #[serde(default, skip_serializing_if = "std::ops::Not::not")]
        run: bool,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        pose: Option<crate::AvatarPose>,
    },
    GetChatHistory {
        resident: String,
        request_id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        chat_id: Option<String>,
        #[serde(default)]
        offset: usize,
    },
    GetWorldSettings,
    SetWorldview {
        request_id: String,
        world_id: String,
        expected_revision: u64,
        text: String,
    },
    /// 保存世界级生理开关；回执与世界观相同（WorldSettingsSaved），随后广播世界设定和名册。
    SetPhysiology {
        request_id: String,
        world_id: String,
        expected_revision: u64,
        switches: crate::PhysiologySwitches,
    },
    /// 改气候（温带、热带）；回执与世界观相同（WorldSettingsSaved），随后广播世界设定。
    /// 不暂停世界，不核对设定修订号；地图没有天气时拒绝。
    SetClimate {
        request_id: String,
        world_id: String,
        climate: crate::Climate,
    },
    /// 打开或关掉化身神力；回执与世界观相同（WorldSettingsSaved），随后广播世界设定。
    /// 只是一个开关，不暂停世界，不核对设定修订号：别的页面正在改的世界观不会因此被拒。
    SetMiracles {
        request_id: String,
        world_id: String,
        enabled: bool,
    },
    /// 打开或关掉录像；回执与世界观相同（WorldSettingsSaved），随后广播世界设定和录像列表。
    /// 打开就开新的一卷，关掉就收起正在录的那一卷；不暂停世界，不核对设定修订号。
    SetRecording {
        request_id: String,
        world_id: String,
        enabled: bool,
    },
    /// 读录下的几卷（回 Recordings）
    GetRecordings,
    /// 删掉录完的一卷（正在录的删不了）；回执是 WorldSettingsSaved，随后广播录像列表。
    DeleteRecording {
        request_id: String,
        world_id: String,
        reel: String,
    },
    /// 打开或关掉陌生环境（村民初来乍到，只知道到过的地方）；回执与世界观相同（WorldSettingsSaved），
    /// 随后广播世界设定。改了就暂停世界，居民重新观察；打开时每人只记得眼下所在的地方和家。
    SetStrangers {
        request_id: String,
        world_id: String,
        enabled: bool,
    },
    /// 打开或关掉玩法：带 game_mode 是打开它，不带是关掉；回执与世界观相同（WorldSettingsSaved），
    /// 随后广播世界设定。已经开着同一个玩法时不重来。
    SetGameMode {
        request_id: String,
        world_id: String,
        #[serde(default)]
        game_mode: Option<crate::GameModeChoice>,
    },
    GetProps,
    Content {
        request_id: String,
        world_id: String,
        command: ContentCommand,
    },
    /// 校验道具定义（回 PropResult）。definition 是内核 `props::Definition` 的 JSON：类型和它的校验
    /// 规则都在内核，protocol 不依赖内核，所以这里收原文，由 host 解析，格式错误写在回执里。
    /// 形状由 kernel/tests/props.rs 与前端类型比对测试共用的样本核对。
    ValidateProp {
        request_id: String,
        definition: serde_json::Value,
    },
    /// 保存道具定义；definition 同 ValidateProp。
    SaveProp {
        request_id: String,
        definition: serde_json::Value,
    },
    /// 从道具库删掉自己做的一件道具，这个编号的所有版本一起删（回 PropResult，成功后广播道具目录）。
    /// 只删道具库：镇上已经摆着的、背包里的各自存着整份定义，不受影响；自带的、地图本身摆着的删不了。
    DeleteProp {
        request_id: String,
        id: String,
    },
    RemoveProp {
        request_id: String,
        world_id: String,
        id: String,
    },
    /// 放置道具；instance 是内核 `props::Instance` 的 JSON，理由同 ValidateProp。
    /// near 是在地图上点的位置，道具落在它附近的空位；不给时由放置器自己挑。
    PlaceProp {
        request_id: String,
        world_id: String,
        instance: serde_json::Value,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        near: Option<PlaceNear>,
    },
    /// 摆道具时要各地点能放的格子（回 PlacementGrid）。
    GetPlacementGrid {
        request_id: String,
        world_id: String,
    },
    /// 试放：instance、near 同 PlaceProp，只算这件会落在哪，不改世界（回 PlacementPreview）。
    PreviewPlacement {
        request_id: String,
        world_id: String,
        instance: serde_json::Value,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        near: Option<PlaceNear>,
    },
    SetSpeed {
        request_id: String,
        speed: f64,
    },
    /// 读模型配置（回 ModelConfig，密钥只有掩码）
    GetModelConfig,
    /// 保存模型配置：服务商表 + 指定 + 密钥（密钥单独落 credentials.json）
    SetModelConfig {
        request_id: String,
        active: Option<ActiveModelChoice>,
        providers: Vec<ProviderConfigMsg>,
        #[serde(default)]
        keys: Vec<ProviderKeyMsg>,
    },
    /// 设置一位村民的模型绑定；每位村民都必须有模型，不能改回未配置。
    SetResidentModel {
        request_id: String,
        resident: String,
        model: ModelChoice,
    },
    /// 重启内置模型的服务，换上刚下好的新版（回 ConfigSaved，再广播 ModelConfig）
    RestartBuiltinModel {
        request_id: String,
    },
    /// 连接测试：与正式调用同一条 HTTP 通道；api_key 缺省用已存密钥
    TestModelConnection {
        request_id: String,
        provider: ProviderConfigMsg,
        model: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        api_key: Option<String>,
    },
    /// 读村民设定（回 AgentConfig）
    GetAgentConfig {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        resident: Option<String>,
    },
    /// 说自己在看哪位村民的角色卡细节（回 ResidentDetail，之后细节变了再发）；不带 resident 是不看了。
    /// 一条连接同时只看一位；连接断了世界就不记得，重连后要再说一遍。
    WatchResident {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        resident: Option<String>,
    },
    /// 保存人设原文（markdown；热重载，下一次请求计划生效）
    SetPersona {
        request_id: String,
        resident: String,
        text: String,
    },
    /// 重置世界：人口、记忆、进度和用量全部清空，换世界标识，回到 D1 07:00 并暂停；村民库保留，居民须重新从村民库加入
    ResetWorld {
        request_id: String,
    },
    /// 读当前人口（回 Population）
    GetPopulation,
    /// 换已入住居民捏的长相（只换 appearance.look）；人口版本不符或长相不合格时拒绝
    /// （回 ResidentAppearanceSaved）。
    SetResidentAppearance {
        request_id: String,
        world_id: String,
        expected_revision: u64,
        resident_id: String,
        appearance: crate::Appearance,
    },
    /// 调已入住居民的身体数值（村民卡片上的「调整」）：只在世界暂停时放行，回 AgentSaved。
    /// 不是世界里发生的事，本人的经历里不留痕，跨过提醒线照常提醒。
    SetResidentBody {
        request_id: String,
        world_id: String,
        resident_id: String,
        values: crate::BodyValues,
    },
    /// 读模型请求与 token 消耗（回 Usage）
    GetUsage,
    /// 读村民库卡片（回 ResidentLibrary）
    GetResidentLibrary {
        #[serde(default)]
        filter: LibraryFilter,
    },
    /// 读模板详情（回 ResidentTemplate）
    GetResidentTemplate {
        template_id: String,
    },
    /// 新建或修改自定义模板；template_id 为空表示新建，expected_version 不符则冲突（回 TemplateSaved）
    SaveResidentTemplate {
        request_id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        template_id: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        expected_version: Option<u64>,
        fields: Box<TemplateFields>,
    },
    /// 按字段渲染人设全文，不保存（回 TemplatePersona）
    PreviewTemplatePersona {
        fields: Box<TemplateFields>,
    },
    /// 用小镇当前模型按一句话描述生成模板字段（回 TemplateGenerated，一次调用，不进村民额度）
    GenerateResidentTemplate {
        request_id: String,
        brief: String,
    },
    /// 归档或取消归档模板（回 TemplateSaved）
    ArchiveResidentTemplate {
        request_id: String,
        template_id: String,
        expected_version: u64,
        archived: bool,
    },
    /// 加入预览（回 JoinPreview）：本次姓名与住宅可省略，服务器给建议
    PreviewResidentJoin {
        template_id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        name: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        home: Option<String>,
    },
    /// 加入小镇（成功广播 ResidentJoined，失败回 JoinResult）
    JoinResident {
        op_id: String,
        world_id: String,
        template_id: String,
        template_version: u64,
        name: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        home: Option<String>,
        /// 入住时就定下用哪个模型思考；不带时先住下，选好模型后再行动
        #[serde(default, skip_serializing_if = "Option::is_none")]
        model: Option<ModelChoice>,
        /// 预制小镇的选手：用这份人设（来历、处境、目标……）入住，姓名取 name，长相照模板；
        /// 只给这一位居民，不回写村民库。不带时照模板的人设
        #[serde(default, skip_serializing_if = "Option::is_none")]
        persona: Option<Box<TemplateFields>>,
    },
    /// 断线后按操作编号查询加入结果（回 JoinResult）
    GetResidentJoinResult {
        world_id: String,
        op_id: String,
    },
    /// 读日志（回 Diary）
    GetDiary {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        resident: Option<String>,
    },
    GetNotebook {
        resident: String,
        request_id: String,
        #[serde(default)]
        query: NotebookQuery,
    },
    GetNotebookDetail {
        resident: String,
        request_id: String,
        query: NotebookDetailQuery,
    },
    /// 读调用额度与用量（回 AgentLimits）
    GetAgentLimits,
    /// 保存调用额度：即时生效并随存档保存；额度暂停后需再点开始继续
    SetAgentLimits {
        request_id: String,
        limits: AgentLimits,
    },
    /// 读 Agent 轨迹日志的开关和这个小镇的日志用了多少（回 AgentTrace）
    GetAgentTrace,
    /// 轨迹日志记不记完整题面：跟着这台设备，即时生效；回执是 ConfigSaved，随后广播 AgentTrace
    SetAgentTrace {
        request_id: String,
        full_prompts: bool,
    },
}

impl ClientMsg {
    /// 命令自带的编号：请求编号，加入小镇与查询加入结果用操作编号；查询命令没有编号。
    pub fn request_id(&self) -> Option<&str> {
        use ClientMsg::*;
        match self {
            SetWeather { request_id, .. }
            | Avatar { request_id, .. }
            | GetChatHistory { request_id, .. }
            | SetWorldview { request_id, .. }
            | SetPhysiology { request_id, .. }
            | SetClimate { request_id, .. }
            | SetMiracles { request_id, .. }
            | SetRecording { request_id, .. }
            | DeleteRecording { request_id, .. }
            | SetStrangers { request_id, .. }
            | SetGameMode { request_id, .. }
            | Content { request_id, .. }
            | ValidateProp { request_id, .. }
            | SaveProp { request_id, .. }
            | DeleteProp { request_id, .. }
            | RemoveProp { request_id, .. }
            | PlaceProp { request_id, .. }
            | GetPlacementGrid { request_id, .. }
            | PreviewPlacement { request_id, .. }
            | SetSpeed { request_id, .. }
            | SetModelConfig { request_id, .. }
            | SetResidentModel { request_id, .. }
            | RestartBuiltinModel { request_id }
            | TestModelConnection { request_id, .. }
            | SetPersona { request_id, .. }
            | ResetWorld { request_id }
            | SetResidentAppearance { request_id, .. }
            | SetResidentBody { request_id, .. }
            | SaveResidentTemplate { request_id, .. }
            | GenerateResidentTemplate { request_id, .. }
            | ArchiveResidentTemplate { request_id, .. }
            | GetNotebook { request_id, .. }
            | GetNotebookDetail { request_id, .. }
            | SetAgentLimits { request_id, .. }
            | SetAgentTrace { request_id, .. } => Some(request_id),
            JoinResident { op_id, .. } | GetResidentJoinResult { op_id, .. } => Some(op_id),
            AvatarInput { .. }
            | GetWorldSettings
            | GetRecordings
            | GetProps
            | GetModelConfig
            | GetAgentConfig { .. }
            | WatchResident { .. }
            | GetPopulation
            | GetUsage
            | GetResidentLibrary { .. }
            | GetResidentTemplate { .. }
            | PreviewTemplatePersona { .. }
            | PreviewResidentJoin { .. }
            | GetDiary { .. }
            | GetAgentLimits
            | GetAgentTrace => None,
        }
    }
}
