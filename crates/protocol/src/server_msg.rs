//! 服务端消息（后端 → 前端）。命令的回执、查询结果与错误只发给发出命令的连接，回执带命令的
//! 请求编号，前端按编号配对；名册、事件、想法和其他状态变化广播给所有连接。
//! 角色卡细节（ResidentDetail）和化身状态只发给在看、在控制的那条连接。
use crate::{
    ActiveModelChoice, AgentLimits, AgentUsage, ChatEntry, ChatSummary, DiaryDay, JoinOutcome,
    JoinPreview, ModelChoice, NeedsTuning, NotebookDetail, NotebookView, PopulationView,
    ProviderView, RequestView, ResidentDetailView, ResidentTemplate, ResidentUsage, RosterLocale,
    TemplateCard, TemplateFields, UsageSummary, WorldHold,
};
use serde::Serialize;

/// 运行世界的设定：世界观、模型与生理开关。线上按字段名字母序输出。
#[derive(Debug, Clone, Serialize)]
pub struct WorldSettingsView {
    /// 气候：温带或热带（不下雪、雷暴少）。随存档保存，缺省为温带。
    pub climate: crate::Climate,
    /// 开着的玩法（如 "tide"）；没开时不出现。随存档保存。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub game_mode: Option<String>,
    pub max_chars: usize,
    /// 化身神力：化身能对够得着的人复活、治愈、补满。随存档保存，缺省为关。
    pub miracles: bool,
    pub mock: bool,
    pub model: String,
    pub persistent: bool,
    pub physiology: crate::PhysiologySwitches,
    pub provider: String,
    pub ready: bool,
    /// 录像开关：开着时把广播给页面的消息录进小镇目录，事后能重演、换角度拍素材。
    /// 随存档保存，缺省为开；真的在录哪一卷看 `Recordings.live`。
    pub recording: bool,
    pub revision: u64,
    /// 陌生环境：村民初来乍到，只知道到过的地方。随存档保存，缺省为关。
    pub strangers: bool,
    pub world_id: String,
    pub worldview: String,
}

/// host 只发送、不解析这些消息，所以只实现 Serialize。
/// 改成结构体之前由 `serde_json::json!` 拼出的几个字段经 `crate::sorted` 输出，键按字母序，线上 JSON 不变。
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ServerMsg {
    /// 连接后的第一条：这是哪个小镇、哪版地图。
    WorldIdentity {
        town_id: Option<String>,
        map_hash: String,
    },
    AvatarState {
        #[serde(serialize_with = "crate::sorted")]
        state: crate::AvatarSession,
    },
    AvatarResult {
        request_id: String,
        ok: bool,
        code: crate::AvatarResultCode,
        message: String,
        #[serde(serialize_with = "crate::sorted")]
        state: crate::AvatarSession,
    },
    ChatHistory {
        resident: String,
        request_id: String,
        chat_id: Option<String>,
        offset: usize,
        total: usize,
        chats: Vec<ChatSummary>,
        entries: Vec<ChatEntry>,
    },
    WorldSettings {
        #[serde(serialize_with = "crate::sorted")]
        state: WorldSettingsView,
    },
    WorldSettingsSaved {
        request_id: String,
        ok: bool,
        message: String,
    },
    Props {
        #[serde(serialize_with = "crate::sorted")]
        catalog: crate::PropsCatalog,
    },
    PropResult {
        request_id: String,
        ok: bool,
        message: String,
        /// 失败时为 null。
        #[serde(serialize_with = "crate::sorted")]
        preview: Option<crate::PropPreview>,
    },
    /// 摆道具的格子（GetPlacementGrid 的回包）：每个能放东西的地点一份；没有空间地图的世界为空。
    PlacementGrid {
        request_id: String,
        grids: Vec<crate::PlaceGrid>,
    },
    /// 试放的回包（PreviewPlacement）：ok 时 spot 是这件会落在哪、朝向和占地，没有空间地图的世界为
    /// null；不 ok 时 message 说为什么放不下。
    PlacementPreview {
        request_id: String,
        ok: bool,
        message: String,
        spot: Option<crate::PropPosition>,
    },
    WeatherSaved {
        request_id: String,
        world_id: String,
        ok: bool,
        code: Option<crate::WeatherCode>,
        message: String,
        environment: Option<crate::WeatherView>,
    },
    Roster {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        environment: Option<crate::WeatherView>,
        /// 开着的玩法此刻的状态（潮水圈：水边和下一圈）；没开时不出现
        #[serde(default, skip_serializing_if = "Option::is_none")]
        game_mode: Option<crate::GameModeView>,
        sim_minutes: f64,
        /// 展示用时钟，如 "D1 07:32"
        clock: String,
        /// 选定的速度：正常速度的倍数，1 是正常速度（村民在画面上像散步），0 为暂停
        speed: f64,
        /// 这一拍实际的推进速度，同样是正常速度的倍数：大家都在做一件还要好一阵的事时自动快进，
        /// 比 speed 快；有人走动、交谈或在等模型回复时等于 speed
        #[serde(default)]
        pace: f64,
        /// 时段（上午 / 晌午 / …），观察仪顶条用
        #[serde(default)]
        period: String,
        /// 额度或故障导致的全镇暂停；为空表示只有用户自己的暂停或没有暂停
        #[serde(default, skip_serializing_if = "Vec::is_empty")]
        holds: Vec<WorldHold>,
        locales: Vec<RosterLocale>,
    },
    /// 观察日志行：正文给人读，种类、人物与提示卡细节给前端判断
    Event {
        sim_minutes: f64,
        clock: String,
        text: String,
        #[serde(flatten)]
        info: crate::EventInfo,
    },
    /// 模型配置回读（密钥只有掩码）
    ModelConfig {
        active: Option<ActiveModelChoice>,
        providers: Vec<ProviderView>,
        /// 内置模型的新版是小镇开着时下好的，服务还在用旧的；RestartBuiltinModel 换上
        #[serde(default)]
        builtin_stale: bool,
    },
    /// 模型服务与调用额度的保存结果
    ConfigSaved {
        request_id: String,
        ok: bool,
        message: String,
    },
    /// 连接测试结果
    ModelTestResult {
        request_id: String,
        provider: String,
        ok: bool,
        message: String,
        latency_ms: u64,
    },
    /// 单个村民的设定回读；resident_id 用于可靠匹配，resident 保留作显示名。
    /// health_marks 是健康条上的三条分界（危重、危险、受损），不随人调整。
    AgentConfig {
        resident_id: String,
        resident: String,
        persona: String,
        tuning: NeedsTuning,
        health_marks: [f64; 3],
        #[serde(default, skip_serializing_if = "Option::is_none")]
        model_binding: Option<ModelChoice>,
    },
    /// 村民设定（人设、使用模型、身体数值）的保存结果
    AgentSaved {
        request_id: String,
        ok: bool,
        message: String,
    },
    /// 角色卡细节：只发给用 WatchResident 说了在看这位村民的连接，说的时候一份，之后变了才发。
    /// 这位村民没有 Agent 会话（或不在世界里）时 detail 省略。
    ResidentDetail {
        resident_id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        detail: Option<ResidentDetailView>,
    },
    /// 通用错误：命令无法执行、格式错误、读取失败或保存失败。request_id 是引起错误的命令自带的
    /// 编号（加入小镇的命令是它的操作编号）；不是由某条命令引起的（周期存盘失败）或命令没有编号时省略。
    Error {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        request_id: Option<String>,
        message: String,
    },
    /// 世界已重置：人口与历史清空，回到第一天并暂停；村民库保留
    WorldReset { clock: String },
    /// 这个小镇录下的几卷（新的在前）与正在录的那一卷的编号（没在录时省略）。
    /// 查询时只回给发出者；开始录、停下、删掉一卷时广播。
    Recordings {
        reels: Vec<crate::ReelView>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        live: Option<String>,
    },
    /// 日志：按天归档的执行记录、想法与他自己写的「昨天」（观察仪日志页用）
    Diary {
        resident: String,
        days: Vec<DiaryDay>,
    },
    Notebook {
        resident: String,
        request_id: String,
        notebook: Option<Box<NotebookView>>,
        error: Option<String>,
    },
    NotebookDetail {
        resident: String,
        request_id: String,
        detail: Option<Box<NotebookDetail>>,
        error: Option<String>,
    },
    /// 调用额度、各项的取值范围与用量回读（设定中心调用额度页用）
    AgentLimits {
        limits: AgentLimits,
        ranges: crate::AgentLimitRanges,
        usage: AgentUsage,
    },
    /// 当前人口：世界标识、人口版本、居民登记与住宅占用
    Population { population: PopulationView },
    /// 已入住居民外观的保存结果；总是带当前人口，前端可据此处理版本冲突。
    ResidentAppearanceSaved {
        request_id: String,
        resident_id: String,
        ok: bool,
        message: String,
        population: PopulationView,
    },
    /// 消耗页：汇总、按人用量与最近的请求台账（新的在前）
    Usage {
        summary: UsageSummary,
        residents: Vec<ResidentUsage>,
        requests: Vec<RequestView>,
    },
    /// 村民库卡片；custom_root 是自定义模板的实际保存位置
    ResidentLibrary {
        templates: Vec<TemplateCard>,
        custom_root: String,
    },
    /// 模板详情与按字段渲染出的人设全文
    ResidentTemplate {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        template: Option<ResidentTemplate>,
        persona: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        error: Option<String>,
    },
    /// 按字段渲染的人设全文（编辑时实时预览）；字段不合规时给 error
    TemplatePersona {
        persona: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        error: Option<String>,
    },
    /// 用模型按一句话描述生成的模板字段；只填表单，不保存
    TemplateGenerated {
        request_id: String,
        ok: bool,
        message: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        fields: Option<Box<TemplateFields>>,
    },
    /// 模板保存/归档结果
    TemplateSaved {
        request_id: String,
        ok: bool,
        message: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        template: Option<ResidentTemplate>,
    },
    /// 加入预览：只校验，不占房
    JoinPreview { preview: JoinPreview },
    /// 只在保存成功后广播：新人已在名册里
    ResidentJoined { outcome: JoinOutcome },
    /// 加入命令失败或按操作编号查询的结果；outcome 为空表示该操作从未提交
    JoinResult {
        op_id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        outcome: Option<JoinOutcome>,
    },
}
