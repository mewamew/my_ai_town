//! 观察仪的 Agent 投影与调用额度、用量、请求台账。只读，不作为村民观察输入。
use crate::{ActionResult, FactKind, InteractionStatus, VerbKind, WorldFact};
use serde::{Deserialize, Serialize};

/// 会话停止的原因类别。前三种让全镇暂停：停下的村民不再做决定，世界却照走的话，
/// 他会一路饿着渴着直到失能、死去，玩家多半还没发现。
/// 等模型不算出错，也不暂停全镇：模型一能用就自动接着走；谁都还不能思考时 host 让时间停着。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PauseKind {
    #[default]
    Fault,
    Budget,
    Stale,
    /// 还没有能用的模型：没选模型、选的服务已删，或远程服务还没填密钥
    NoModel,
}
impl PauseKind {
    pub fn holds_town(self) -> bool {
        matches!(self, Self::Fault | Self::Budget | Self::Stale)
    }
    pub fn label(self) -> &'static str {
        match self {
            Self::Fault => "故障暂停",
            Self::Budget => "额度用尽",
            Self::Stale => "回复过时",
            Self::NoModel => "等模型",
        }
    }
}

/// 故障暂停的原因类别，前端据此给出能直接去修的按钮。非模型原因和旧存档是 Other。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HoldCause {
    /// 密钥无效、过期或没有权限
    Auth,
    /// 连不上服务：网络不通、超时
    Network,
    /// 账户余额不足
    Balance,
    /// 服务里没有这个模型名
    Model,
    /// 服务拒收或暂时出错：限流、服务端错误等
    Rejected,
    /// 回复格式不对，解析不了
    Reply,
    /// 上下文缩减重试用尽
    Context,
    #[default]
    Other,
}

/// 村民此刻的状态；按严重程度从前往后判断，前端按值查文案。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AgentState {
    /// 已死亡：停止决策，需要明确的复活手段
    Dead,
    /// 故障暂停
    Fault,
    /// 额度用尽
    Budget,
    /// 回复接连过时（全镇随之暂停）
    Stale,
    /// 需要救助：失能，无法自主活动或决策
    Rescue,
    /// 交谈中
    Chatting,
    /// 互动中：等待双方活动结束
    Interacting,
    /// 整理记忆：正在等记忆整理的模型响应
    Reflecting,
    /// 思考中：正在等生活决策的模型响应
    Thinking,
    /// 行动中：等待世界返回动作结果
    Acting,
    /// 等待中：模型主动等待某个时刻或事件
    Waiting,
    /// 待决定：等世界继续后决定下一步
    Undecided,
    /// 玩家正在附身操作，AI 暂停决策
    Manual,
    /// 待设置：等待设置世界观
    Unconfigured,
    /// 等模型：还没有能用的模型，连上或选好后自动开始行动
    NoModel,
}
impl AgentState {
    pub fn paused(kind: PauseKind) -> Self {
        match kind {
            PauseKind::Fault => Self::Fault,
            PauseKind::Budget => Self::Budget,
            PauseKind::Stale => Self::Stale,
            PauseKind::NoModel => Self::NoModel,
        }
    }
}

/// 请求种类。存档里旧的中文值可反序列化。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum RequestKind {
    #[default]
    #[serde(alias = "生活决策")]
    Life,
    #[serde(alias = "记忆整理")]
    Reflection,
    /// 交谈中轮到本人发言：只带聊天规则、人设、摘要、目标和本场对话。
    Chat,
}

/// 请求结果。存档里旧的中文值可反序列化。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RequestStatus {
    #[serde(alias = "进行中")]
    InFlight,
    #[serde(alias = "采纳")]
    Adopted,
    #[serde(alias = "格式重发")]
    FormatRetry,
    #[serde(alias = "过时退回")]
    Outdated,
    #[serde(alias = "失败")]
    Failed,
    #[serde(alias = "重启丢弃")]
    Dropped,
    /// 外部受控动作接管，迟到回复不执行。
    #[serde(alias = "受控操作取消")]
    Controlled,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum GoalStatus {
    Active,
    Paused,
    Completed,
    Abandoned,
    Failed,
}
impl GoalStatus {
    pub fn is_open(self) -> bool {
        matches!(self, Self::Active | Self::Paused)
    }
    pub fn label(self) -> &'static str {
        match self {
            Self::Active => "进行中",
            Self::Paused => "已暂停",
            Self::Completed => "已完成",
            Self::Abandoned => "已放弃",
            Self::Failed => "失败",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MemoryKind {
    Episode,
    Recognition,
    Experience,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MemoryStatus {
    Active,
    Candidate,
    Superseded,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EvidenceSource {
    Observed,
    Reported,
    Inferred,
}

/// 名册里每拍都带的 Agent 状态：画面和各面板判断用，名册每 0.1 秒整份广播，所以只放它们每拍要看的。
/// 目标、动作结果、互动和记着的事是角色卡细节（ResidentDetailView），不随名册发；调用次数和 token
/// 在消耗页（ResidentUsage）。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResidentAgentView {
    pub state: AgentState,
    pub reason: String,
    /// 在等时等什么、最迟几点醒来；没在等就省略
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub wait: Option<AgentWaitView>,
    /// 最近定下或改过的进行中目标；换了，画面上这个人头上冒灯泡。没有进行中的目标时省略
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub latest_goal: Option<GoalMark>,
    /// 最近一次自己发起、被对方婉拒的邀请的编号；换了，画面上这个人头上冒怒气。没有时省略
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub declined_invitation: Option<String>,
}

/// 一个目标此刻的记号：编号和最近改动的时刻，画面只用它认「换了没有」。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GoalMark {
    pub id: String,
    pub updated_at: f64,
}

/// 角色卡「目标与记忆」里的细节。一位村民的这一份有好几 KB，只发给说了在看他的连接
/// （ClientMsg::WatchResident → ServerMsg::ResidentDetail），说的时候一份，之后变了才发。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ResidentDetailView {
    pub goals: Vec<ResidentGoalView>,
    pub results: Vec<ActionResultView>,
    pub interactions: Vec<ResidentInteractionView>,
    pub memories: Vec<ResidentMemoryView>,
}

/// 村民在等什么：自己写的理由、最迟醒来的时刻，以及哪类事件来了会提前醒（只按时间等时没有）。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AgentWaitView {
    pub reason: String,
    pub until: f64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub event: Option<FactKind>,
}

/// 观察仪里的一条动作结果：动作结果本身加上动作种类。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ActionResultView {
    #[serde(flatten)]
    pub result: ActionResult,
    pub verb_kind: VerbKind,
}

/// 额度用尽、故障或回复接连过时导致的全镇暂停原因；由用户修改额度或检查服务后点开始继续。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorldHold {
    pub resident_id: String,
    pub resident: String,
    pub kind: PauseKind,
    pub reason: String,
    /// 故障的原因类别；其他暂停是 Other
    #[serde(default)]
    pub cause: HoldCause,
    /// 这位村民用的模型服务（显示名）；host 按村民的模型绑定填，没有绑定时为空
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub provider: String,
}

/// 运行中可改的调用额度；并发和上下文窗口不在其中。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct AgentLimits {
    pub calls_per_wake: u32,
    pub calls_per_day: u64,
    pub tokens_per_day: u64,
    pub total_calls: u64,
    pub total_tokens: u64,
    pub stale_replies_before_pause: u32,
    pub model_failures_before_pause: u32,
}

/// 一项额度的取值范围（闭区间）；max 为空表示没有上限。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct LimitRange {
    pub min: u64,
    pub max: Option<u64>,
}

/// 设定中心可改的各项额度的取值范围，由 agent 的校验规则给出；前端按它检查输入。
/// 两项之间的约束（总 token 不小于每日 token）不在这里，由服务端校验后回报。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct AgentLimitRanges {
    pub calls_per_wake: LimitRange,
    pub calls_per_day: LimitRange,
    pub tokens_per_day: LimitRange,
    pub total_calls: LimitRange,
    pub total_tokens: LimitRange,
    pub stale_replies_before_pause: LimitRange,
    pub model_failures_before_pause: LimitRange,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentUsage {
    pub lifetime_calls: u64,
    pub lifetime_tokens: u64,
    pub residents: Vec<ResidentUsage>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResidentUsage {
    pub id: String,
    pub name: String,
    pub daily_calls: u64,
    pub daily_tokens: u64,
    #[serde(default)]
    pub daily_input_tokens: u64,
    #[serde(default)]
    pub daily_cache_hit_tokens: u64,
    pub replies: u64,
    pub stale_replies: u64,
    #[serde(default)]
    pub in_flight: bool,
    /// 停止原因（含类别文案）；没有停止时省略
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub paused: Option<String>,
}

/// 消耗页汇总：今天按各人当日账合计，累计按运行时总账；含在途预留。
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct UsageSummary {
    pub today_calls: u64,
    pub today_tokens: u64,
    pub today_input_tokens: u64,
    pub today_cache_hit_tokens: u64,
    pub lifetime_calls: u64,
    pub lifetime_tokens: u64,
    pub lifetime_input_tokens: u64,
    pub lifetime_cache_hit_tokens: u64,
    pub calls_per_day: u64,
    pub tokens_per_day: u64,
    pub total_calls: u64,
    pub total_tokens: u64,
    pub in_flight: u64,
}

/// 一次模型请求的台账行。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RequestView {
    pub id: u64,
    pub resident_id: String,
    pub resident: String,
    pub kind: RequestKind,
    pub clock: String,
    pub sim_minutes: f64,
    pub sent_at: u64,
    pub reserved_tokens: u64,
    pub estimated_tokens: u64,
    pub status: RequestStatus,
    pub detail: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub latency_ms: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub input_tokens: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub output_tokens: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cache_hit_tokens: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ResidentInteractionView {
    pub id: String,
    pub title: String,
    pub status: InteractionStatus,
    pub participants: Vec<String>,
    pub result: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ResidentGoalView {
    pub id: String,
    pub title: String,
    pub status: GoalStatus,
    pub reason: String,
    pub commitment: String,
    pub next_steps: Vec<String>,
    pub updated_at: f64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ResidentMemoryView {
    pub memory_id: u64,
    pub kind: MemoryKind,
    pub source: EvidenceSource,
    pub status: MemoryStatus,
    pub confidence: f64,
    pub text: String,
    pub at: f64,
    pub replaces: Vec<u64>,
    pub events: Vec<WorldFact>,
}
