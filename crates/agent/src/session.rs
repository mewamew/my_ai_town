//! 可存档的村民会话。会话、目标和一次唤醒分别计数、分别结束。
//! 字段按职责分组；分组用 `#[serde(flatten)]` 平铺，存档 JSON 与分组前相同。
use crate::{
    budget::Account,
    conversation::{Message, ModelReply, ToolCall},
};
pub use protocol::{GoalStatus, HoldCause, PauseKind};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};

/// 提示词保留所有当前事务和最近这么多个已结束目标。
pub const CLOSED_GOALS_IN_CONTEXT: usize = 4;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum GoalCondition {
    Action { verb: String, locale: String },
    Interaction { interaction_id: String },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Goal {
    pub id: String,
    pub title: String,
    pub condition: GoalCondition,
    pub status: GoalStatus,
    pub next_steps: Vec<String>,
    pub commitment: String,
    pub reason: String,
    pub created_at: f64,
    pub updated_at: f64,
    /// 模型填写的约定时刻，如 `D2 14:00`；只供规划参考，不拦截提前行动。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub due_clock: Option<String>,
    pub evidence: Vec<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RequestStamp {
    pub id: u64,
    pub epoch: u64,
    pub revision: u64,
    pub seen_cursor: u64,
    pub sim_minutes: f64,
    pub reserved_tokens: u64,
    pub day: i64,
    /// 发出的正文字节数，回复带 usage 时用来校准系数。
    #[serde(default)]
    pub sent_bytes: u64,
    /// 发出时 system、工具与摘要的哈希；前缀变化后精确计数作废。
    #[serde(default)]
    pub prefix_digest: u64,
    /// 请求种类；回复按种类进不同的对话。
    #[serde(default)]
    pub kind: protocol::RequestKind,
}

/// 上一次请求精确计过数的前缀：system、工具、摘要与前 `messages` 条会话消息。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct KnownPrefix {
    pub prefix_digest: u64,
    pub messages: usize,
    pub tokens: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum PendingTool {
    Interaction {
        call: ToolCall,
        interaction_id: String,
    },
    Actions {
        call: ToolCall,
        group_id: String,
        /// 邀请到达时已返回“仍在执行”的工具结果；继续跟踪实际动作，最终结果另作通知。
        #[serde(default)]
        reported_running: bool,
    },
    Wait {
        call: ToolCall,
        until: f64,
        after_cursor: u64,
        event: Option<protocol::FactKind>,
        /// 发出交谈邀请后的等待：结束时把这个邀请的状态一并返回。
        #[serde(default)]
        invitation: Option<String>,
    },
}
impl PendingTool {
    pub fn blocks_request(&self) -> bool {
        !matches!(
            self,
            Self::Actions {
                reported_running: true,
                ..
            }
        )
    }
    pub fn call(&self) -> &ToolCall {
        match self {
            Self::Actions { call, .. }
            | Self::Wait { call, .. }
            | Self::Interaction { call, .. } => call,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Sleep {
    pub until: f64,
    pub reason: String,
    pub wake_on_notice: bool,
    pub after_cursor: u64,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct FailureStreak {
    pub key: String,
    pub count: u32,
}

/// 停止状态：原因文本与类别，只由 `Session::pause` 与 `Session::resume` 成对修改。
/// 没有停止时 reason 为空。
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Pause {
    #[serde(default, rename = "paused")]
    reason: Option<String>,
    /// 与 reason 配套；旧存档没有这个字段时按故障处理。
    #[serde(default, rename = "pause_kind")]
    kind: PauseKind,
    /// 故障的原因类别，供前端给出修复按钮；旧存档和其他原因是 Other，不写出。
    #[serde(
        default,
        rename = "pause_cause",
        skip_serializing_if = "is_other_cause"
    )]
    cause: HoldCause,
}
fn is_other_cause(cause: &HoldCause) -> bool {
    *cause == HoldCause::Other
}

/// 生活决策回复的累计数与其中过时退回数，供评估过时比例。
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Tally {
    #[serde(default)]
    pub replies: u64,
    #[serde(default)]
    pub stale_replies: u64,
}

/// 事件游标：模型已确认看过的事件、已随请求送出的事件、最近处理过的通知。
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Cursors {
    #[serde(rename = "acknowledged_cursor")]
    pub acknowledged: u64,
    #[serde(rename = "delivered_cursor")]
    pub delivered: u64,
    #[serde(rename = "last_notice_cursor")]
    pub last_notice: u64,
    /// 已折叠进摘要的最后一个事件；之后的事件还在会话原文里，不必再当记忆附带。
    #[serde(default, rename = "folded_through_cursor")]
    pub folded_through: u64,
    /// 最近看过的「有人来了」事件；目标里的人来了会提前结束停留（runtime/arrivals.rs）。
    #[serde(default, rename = "last_presence_cursor")]
    pub last_presence: u64,
}

/// 一次唤醒的等待与计数，只经 Session 的方法修改。
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Wake {
    #[serde(default)]
    sleep: Option<Sleep>,
    #[serde(default)]
    wake_calls: u32,
    /// 上次因轮到发言而唤醒时的动作版本；同一版本只唤醒一次。
    #[serde(default)]
    last_chat_revision: Option<u64>,
}

/// 连续计数：相同问题、过时回复、模型失败。成功一次即清零。
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Streaks {
    #[serde(default)]
    pub failures: FailureStreak,
    /// 连续因世界变化过时被退回的回复数；采纳一次即清零。
    #[serde(default)]
    pub stale_streak: u32,
    /// 连续模型请求失败数；成功一次即清零。
    #[serde(default)]
    pub model_failures: u32,
    /// 生活轮次模型请求失败后，最早再发请求的现实时刻（unix 秒）。只在内存里：重启后直接重试。
    #[serde(skip)]
    pub retry_at: u64,
}

/// 折叠后的历史与精确计数的前缀。
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Folded {
    #[serde(default)]
    pub compacted: String,
    #[serde(default)]
    pub compactions: u64,
    /// 只经 Session 的方法修改：前缀一变或上限改了就作废。
    #[serde(default)]
    known_tokens: Option<KnownPrefix>,
    /// 折叠归档的旧会话原文，按折叠编号。存档时由 host 拆成文件，不内嵌在运行时状态里。
    #[serde(default, deserialize_with = "deserialize_archives")]
    pub archives: BTreeMap<u64, Vec<Message>>,
}

// flatten 的中间表示不转换 JSON 对象的数字键；旧内嵌归档和直接状态恢复都要支持。
fn deserialize_archives<'de, D: serde::Deserializer<'de>>(
    de: D,
) -> Result<BTreeMap<u64, Vec<Message>>, D::Error> {
    BTreeMap::<String, Vec<Message>>::deserialize(de)?
        .into_iter()
        .map(|(key, value)| {
            key.parse()
                .map(|id| (id, value))
                .map_err(serde::de::Error::custom)
        })
        .collect()
}

/// 本段会话里已随请求发出的内容，下一轮不再重复；折叠后清空。
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Shown {
    /// 已发出的目标集合哈希；集合或状态变化后下一轮再带目标。
    #[serde(default)]
    pub sent_goals_digest: u64,
    /// 已发出记忆索引对应的笔记版本；None 表示本段会话尚未发过。
    #[serde(default)]
    pub sent_notebook_revision: Option<u64>,
    /// 已展示过的自动记忆与主题页（path@revision）。
    #[serde(default)]
    pub shown_memory_ids: BTreeSet<u64>,
    #[serde(default)]
    pub shown_notes: BTreeSet<String>,
    /// 观察里慢变字段上次发出时的摘要值；相同就省略这个字段。
    #[serde(default)]
    pub observation_digests: BTreeMap<String, u64>,
}

/// 本场交谈发给模型的对话。第一轮带全量状态，之后只在末尾追加新台词和有变化的状态，
/// 每轮请求都以上一轮为前缀，能命中缓存；本人说过的话留在自己的调用里。
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct ChatTranscript {
    /// 这份记录属于哪场聊天；换了聊天或记录太长就重新开始。
    pub chat_id: String,
    /// 回复已被采纳的消息：user、assistant、tool 依次排列。
    pub messages: Vec<Message>,
    /// 已送达的状态：最后一句台词、最后一条通知与各状态字段的摘要值。
    pub seen: ChatSeen,
    /// 这一次轮到本人发言后已采纳的回复数；交出发言权后清零。
    pub attempts: u32,
    /// 在途请求新加的内容；回复被采纳才并入记录，过时或失败就丢弃，下一轮重新比较。
    pub pending: Option<ChatDelta>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ChatSeen {
    pub seq: u64,
    pub notice: u64,
    pub digests: BTreeMap<String, u64>,
}

/// 一次交谈请求在记录末尾新加的内容。`restart` 为真时它是新记录的第一条。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatDelta {
    pub chat_id: String,
    pub restart: bool,
    pub message: Option<Message>,
    pub seen: ChatSeen,
}

impl ChatTranscript {
    /// 回复被采纳：在途内容并入记录。
    pub(crate) fn commit(&mut self) {
        let Some(delta) = self.pending.take() else {
            return;
        };
        if delta.restart {
            self.messages.clear();
            self.chat_id = delta.chat_id;
        }
        self.messages.extend(delta.message);
        self.seen = delta.seen;
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InvitationReplyFailure {
    pub invitation_ids: Vec<String>,
    pub attempts: u32,
}
impl InvitationReplyFailure {
    /// 连续格式错误已达到搁置次数：本人暂缓一阵再回应。
    pub fn postponed(&self) -> bool {
        self.attempts >= crate::runtime::SAME_FAILURE_BEFORE_POSTPONE
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    #[serde(default)]
    pub invitation_reply_failure: Option<InvitationReplyFailure>,
    #[serde(default)]
    pub input: crate::context::input::InputState,
    pub id: u64,
    pub actor_id: String,
    pub instructions: String,
    pub goals: BTreeMap<String, Goal>,
    pub messages: Vec<Message>,
    /// 本场交谈的对话记录，不进生活会话；交谈结束后清空。
    #[serde(default)]
    pub chat: ChatTranscript,
    pub pending: Vec<PendingTool>,
    pub in_flight: Option<RequestStamp>,
    #[serde(default)]
    pub last_request_id: u64,
    #[serde(flatten)]
    pause: Pause,
    #[serde(flatten)]
    pub tally: Tally,
    #[serde(flatten)]
    pub cursors: Cursors,
    pub daily: Account,
    pub memory: crate::memory::MemoryStore,
    #[serde(default)]
    pub notebook: crate::notebook::Notebook,
    #[serde(flatten)]
    wake: Wake,
    #[serde(flatten)]
    pub streaks: Streaks,
    #[serde(flatten)]
    pub folded: Folded,
    #[serde(flatten)]
    pub shown: Shown,
    /// 上一轮生活决策里当场被退回的工具：参数格式错误，或查看、记目标这类工具的任何退回。
    /// 只在内存里，重启后从空开始。
    #[serde(skip)]
    retry_tools: BTreeSet<String>,
}

impl Session {
    pub fn new(id: u64, actor_id: &str, instructions: &str) -> Self {
        Self {
            invitation_reply_failure: None,
            input: Default::default(),
            id,
            actor_id: actor_id.into(),
            instructions: instructions.into(),
            goals: BTreeMap::new(),
            messages: vec![],
            chat: ChatTranscript::default(),
            pending: vec![],
            in_flight: None,
            last_request_id: 0,
            pause: Pause::default(),
            tally: Tally::default(),
            cursors: Cursors::default(),
            daily: Account::default(),
            memory: Default::default(),
            notebook: Default::default(),
            wake: Default::default(),
            streaks: Default::default(),
            folded: Default::default(),
            shown: Default::default(),
            retry_tools: Default::default(),
        }
    }
    /// 记下这一轮当场被退回的工具，下一轮据此判断回复是不是只在改正调用。
    pub(crate) fn remember_retry_tools(&mut self, names: BTreeSet<String>) {
        self.retry_tools = names;
    }
    /// 上一轮某个工具被当场退回、这一轮又调用同一工具：回复文字只是改正调用，不算村民的想法。
    /// 身体动作和互动被世界规则拒绝后重新安排，仍是村民的想法。
    pub(crate) fn is_format_retry(&self, reply: &ModelReply) -> bool {
        reply
            .calls
            .iter()
            .any(|c| self.retry_tools.contains(&c.name))
    }
    /// 已结束目标完整留档；提示词保留所有当前事务和最近几个结束目标。
    pub fn context_goals(&self) -> Vec<&Goal> {
        let mut closed: Vec<_> = self
            .goals
            .values()
            .filter(|g| !g.status.is_open())
            .collect();
        closed.sort_by(|a, b| b.updated_at.total_cmp(&a.updated_at));
        self.goals
            .values()
            .filter(|g| g.status.is_open())
            .chain(closed.into_iter().take(CLOSED_GOALS_IN_CONTEXT))
            .collect()
    }
    /// 接管已有世界时把历史事件全部记为已看过，不当成新中断。
    pub fn start_at_cursor(&mut self, cursor: u64) {
        self.cursors = Cursors {
            acknowledged: cursor,
            delivered: cursor,
            last_notice: cursor,
            folded_through: cursor,
            last_presence: cursor,
        };
    }
    /// 进行中或暂停的目标里提到这个人（名字或编号）。
    pub fn goals_mention(&self, id: &str, name: &str) -> bool {
        self.goals.values().filter(|g| g.status.is_open()).any(|g| {
            [&g.title, &g.commitment, &g.reason]
                .into_iter()
                .chain(&g.next_steps)
                .any(|text| (!name.is_empty() && text.contains(name)) || text.contains(id))
        })
    }
    /// 停止原因；没有停止时为 None。
    pub fn pause_reason(&self) -> Option<&str> {
        self.pause.reason.as_deref()
    }
    /// 停止类别；没有停止时是缺省值，要先看 `pause_reason`。
    pub fn pause_kind(&self) -> PauseKind {
        self.pause.kind
    }
    /// 故障的原因类别；没有停止或不是模型原因时是 Other。
    pub fn pause_cause(&self) -> HoldCause {
        self.pause.cause
    }
    /// 停在等模型上（没有能用的模型）。
    pub fn waiting_for_model(&self) -> bool {
        self.pause.reason.is_some() && self.pause.kind == PauseKind::NoModel
    }
    /// 折叠归档的旧会话（存档目录按折叠编号写成文件）。
    pub fn archives(&self) -> &BTreeMap<u64, Vec<Message>> {
        &self.folded.archives
    }
    /// 存档写出后清空内嵌副本。
    pub fn take_archives(&mut self) -> BTreeMap<u64, Vec<Message>> {
        std::mem::take(&mut self.folded.archives)
    }
    /// 从存档目录读回一份折叠归档；同一编号出现两次视为目录损坏。
    pub fn restore_archive(
        &mut self,
        id: u64,
        messages: Vec<Message>,
    ) -> Result<(), crate::AgentError> {
        if self.folded.archives.insert(id, messages).is_some() {
            return Err(crate::AgentError::Restore(format!("对话归档 {id} 重复")));
        }
        Ok(())
    }
    /// 折叠后旧轮次不再是原文，已展示过的目标、索引、主题和观察字段下一轮重新提供。
    /// 自动附带的记忆展示过一次就不再重复：折叠后仍有摘要，需要细节可以 recall。
    pub(crate) fn forget_shown(&mut self) {
        self.folded.known_tokens = None;
        self.shown = Shown {
            shown_memory_ids: std::mem::take(&mut self.shown.shown_memory_ids),
            ..Shown::default()
        };
    }
    pub(crate) fn pause(&mut self, kind: PauseKind, reason: impl Into<String>) {
        self.pause_for(kind, reason, HoldCause::Other);
    }
    pub(crate) fn pause_for(
        &mut self,
        kind: PauseKind,
        reason: impl Into<String>,
        cause: HoldCause,
    ) {
        self.pause = Pause {
            reason: Some(reason.into()),
            kind,
            cause,
        };
    }
    /// 模型能用了：只清掉等模型的停止，连续计数不动。
    pub(crate) fn stop_waiting_for_model(&mut self) -> bool {
        if !self.waiting_for_model() {
            return false;
        }
        self.pause = Pause::default();
        true
    }
    /// 用户主动继续：清除停止原因与类别并重置连续计数；条件仍在时下一次请求前会再次停止。
    pub fn resume(&mut self) -> bool {
        if self.pause.reason.is_none() {
            return false;
        }
        self.pause = Pause::default();
        self.streaks.stale_streak = 0;
        self.streaks.model_failures = 0;
        self.input.rejections = 0;
        self.input.ceiling = None;
        true
    }
    /// 正在等待的条件；没有等待时为 None。
    pub fn sleep(&self) -> Option<&Sleep> {
        self.wake.sleep.as_ref()
    }
    /// 这次唤醒已发出的生活请求数。
    pub fn wake_calls(&self) -> u32 {
        self.wake.wake_calls
    }
    pub(crate) fn postpone(&mut self, sleep: Sleep) {
        self.wake.sleep = Some(sleep);
    }
    /// 等待结束或世界变化：清掉睡眠并重新计一次唤醒。
    pub(crate) fn wake_up(&mut self) {
        self.wake.sleep = None;
        self.wake.wake_calls = 0;
    }
    /// 安排被外部改变（接管、交还、世界设定变化）：结束等待、重新计唤醒，精确计数作废。
    pub(crate) fn restart_after_interruption(&mut self) {
        self.wake_up();
        self.forget_known_prefix();
    }
    /// 交谈进行中不再等待；这次唤醒的请求数照旧。
    pub(crate) fn cancel_sleep(&mut self) {
        self.wake.sleep = None;
    }
    /// 这次唤醒又发出一次生活请求。
    pub(crate) fn count_wake_call(&mut self) {
        self.wake.wake_calls += 1;
    }
    /// 待完成工具有了结果，或回复作废：这次唤醒的请求数从零重新计，等待不变。
    pub(crate) fn restart_wake_count(&mut self) {
        self.wake.wake_calls = 0;
    }
    /// 轮到本人发言时唤醒；同一动作版本只唤醒一次。
    pub(crate) fn wake_for_turn(&mut self, revision: u64) {
        if self.wake.last_chat_revision != Some(revision) {
            self.wake.last_chat_revision = Some(revision);
            self.wake_up();
        }
    }
    /// 上一次请求精确计过数的前缀。
    pub fn known_prefix(&self) -> Option<&KnownPrefix> {
        self.folded.known_tokens.as_ref()
    }
    pub(crate) fn remember_known_prefix(&mut self, prefix: KnownPrefix) {
        self.folded.known_tokens = Some(prefix);
    }
    /// 前缀变了或请求上限改了：精确计数作废，下一次按估算。
    pub(crate) fn forget_known_prefix(&mut self) {
        self.folded.known_tokens = None;
    }
    /// 丢弃在途请求：旧回复不再执行，整理批次与精确计数一起作废。
    pub(crate) fn drop_in_flight(&mut self) -> Option<RequestStamp> {
        let stamp = self.in_flight.take()?;
        self.notebook.request = None;
        self.chat.pending = None;
        self.folded.known_tokens = None;
        Some(stamp)
    }
}
