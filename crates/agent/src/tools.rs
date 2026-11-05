//! 模型可见工具只在这一张表里定义：名字、说明、参数 schema 与执行入口。
//! 工具路由只调用世界命令或自己的记录；耗时动作返回 pending，由运行器等待最终结果。
use crate::{
    conversation::ToolCall,
    memory::{MemoryIndex, RecallQuery},
    notebook::{self, DocumentsCache},
    observation, resident,
    session::{PendingTool, Session},
    AgentError,
};
use kernel::World;
use protocol::{ActionDraft, InteractionCommand, InteractionStatus, RequestKind};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::str::FromStr;

mod action_arguments;
mod goals;
mod invitations;
pub mod limits;
pub(crate) mod schema;
pub(crate) use goals::completion_evidence;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ToolName {
    ContextRead,
    MemorySearch,
    MemoryRead,
    Reflect,
    ReadContent,
    Observe,
    Recall,
    Inspect,
    SetGoal,
    RunActions,
    Interact,
    OfferInvitation,
    ReplyInvitation,
    WaitFor,
}

/// 整理轮次只开放的工具。
pub const REFLECTION_TOOLS: [ToolName; 3] = [
    ToolName::Reflect,
    ToolName::ReadContent,
    ToolName::ContextRead,
];

impl ToolName {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::ContextRead => "context_read",
            Self::MemorySearch => "memory_search",
            Self::MemoryRead => "memory_read",
            Self::Reflect => "reflect",
            Self::ReadContent => "read_content",
            Self::Observe => "observe",
            Self::Recall => "recall",
            Self::Inspect => "inspect",
            Self::SetGoal => "set_goal",
            Self::RunActions => "run_actions",
            Self::Interact => "interact",
            Self::OfferInvitation => "offer_invitation",
            Self::ReplyInvitation => "reply_invitation",
            Self::WaitFor => "wait_for",
        }
    }
    /// 各类轮次开放的工具：生活决策除 reflect 外全部，整理轮次只有整理工具，交谈轮次只有 interact。
    pub fn allowed_in(self, kind: RequestKind) -> bool {
        match kind {
            RequestKind::Life => self != Self::Reflect,
            RequestKind::Reflection => REFLECTION_TOOLS.contains(&self),
            RequestKind::Chat => self == Self::Interact,
        }
    }
    /// 改变世界的工具：请求期间收到重要通知时退回，要求先重新观察。
    pub fn changes_world(self) -> bool {
        matches!(
            self,
            Self::RunActions | Self::Interact | Self::OfferInvitation | Self::ReplyInvitation
        )
    }
    /// 查看或记目标：不动身体、不对人说话，也不是等待。
    pub fn is_lookup(self) -> bool {
        !self.changes_world() && self != Self::WaitFor
    }
}
impl FromStr for ToolName {
    type Err = ToolError;
    fn from_str(name: &str) -> Result<Self, ToolError> {
        TOOLS
            .iter()
            .map(|t| t.name)
            .find(|t| t.as_str() == name)
            .ok_or_else(|| {
                ToolError::new(ToolErrorKind::InvalidArguments, format!("未知工具 {name}"))
            })
    }
}
impl std::fmt::Display for ToolName {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

/// 工具执行所需的全部状态；一次回复内的每个调用共用同一份。
pub struct ToolContext<'a> {
    pub world: &'a mut World,
    pub session: &'a mut Session,
    pub index: &'a mut MemoryIndex,
    pub documents: &'a mut DocumentsCache,
    pub request: u64,
}

#[derive(Debug)]
pub enum ToolOutcome {
    Complete(Value),
    Pending(PendingTool),
}

/// 工具调用被退回的原因类别。写进工具结果的 error_kind；运行器按它判断，不看说明文字。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ToolErrorKind {
    /// 参数解析失败或工具名不存在：改格式重发即可。
    InvalidArguments,
    /// 这类轮次不开放这个工具。
    NotAllowed,
    /// 请求期间收到重要通知，改变世界的调用退回，先重新观察。
    Outdated,
    /// 还有未完成的动作或等待。
    Busy,
    /// 世界规则不允许（内核命令校验不通过）。
    World,
    /// 工具自己的规则不允许：目标条件、查询范围、读取来源等。
    Rejected,
}

/// 一次工具调用被退回：类别与给模型看的说明。
#[derive(Debug, Clone, PartialEq)]
pub struct ToolError {
    pub kind: ToolErrorKind,
    pub message: String,
}

impl ToolError {
    pub fn new(kind: ToolErrorKind, message: impl Into<String>) -> Self {
        Self {
            kind,
            message: message.into(),
        }
    }
    pub(crate) fn rejected(message: impl Into<String>) -> Self {
        Self::new(ToolErrorKind::Rejected, message)
    }
    /// 写进工具结果：{"ok":false,"error":说明,"error_kind":类别}。
    pub fn result(&self) -> Value {
        json!({"ok": false, "error": self.message, "error_kind": self.kind})
    }
}

impl From<kernel::KernelError> for ToolError {
    fn from(error: kernel::KernelError) -> Self {
        Self::new(ToolErrorKind::World, error.to_string())
    }
}

/// 内核错误是世界规则不允许，查询不合法是参数问题，其余是工具规则不允许。
impl From<AgentError> for ToolError {
    fn from(error: AgentError) -> Self {
        let kind = match &error {
            AgentError::Kernel(_) => ToolErrorKind::World,
            AgentError::Query(_) => ToolErrorKind::InvalidArguments,
            _ => ToolErrorKind::Rejected,
        };
        Self::new(kind, error.to_string())
    }
}

impl std::fmt::Display for ToolError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}

type Exec = fn(&mut ToolContext, &ToolCall) -> Result<ToolOutcome, ToolError>;

pub struct ToolSpec {
    pub name: ToolName,
    /// 说明文字；里面的数字由常量格式化，所以是函数。
    pub description: fn() -> String,
    parameters: fn() -> Value,
    exec: Exec,
}

impl ToolSpec {
    /// OpenAI 风格的 function 定义。
    pub fn definition(&self) -> Value {
        json!({
            "type": "function",
            "function": {
                "name": self.name.as_str(),
                "description": (self.description)(),
                "parameters": (self.parameters)()
            }
        })
    }
}

pub const TOOLS: [ToolSpec; 14] = [
    ToolSpec {
        name: ToolName::ContextRead,
        description: || {
            "分段读取上下文里 context_source 指向的完整来源，不重新执行原工具。pointer 可选 JSON pointer，offset 按字符计，next_offset 非空可继续。".into()
        },
        parameters: schema::context_read,
        exec: context_read,
    },
    ToolSpec {
        name: ToolName::MemorySearch,
        description: || {
            "在本人记忆文件里按关键词搜索，返回路径、偏移和片段；directory 可筛选目录，offset 翻页。".into()
        },
        parameters: schema::memory_search,
        exec: memory_search,
    },
    ToolSpec {
        name: ToolName::MemoryRead,
        description: || {
            "按路径分段读本人记忆原文；目录路径以 / 结尾列出文件，next_offset 非空可继续。".into()
        },
        parameters: schema::memory_read,
        exec: memory_read,
    },
    ToolSpec {
        name: ToolName::Reflect,
        description: || "整理轮次专用：总结本批新增经历并提交有来源的主题更新。".into(),
        parameters: schema::reflect,
        exec: reflect,
    },
    ToolSpec {
        name: ToolName::ReadContent,
        description: || "按本人已完成阅读的 event_id 查看当时正文和版本；不自动写入记忆。".into(),
        parameters: schema::read_content,
        exec: read_content,
    },
    ToolSpec {
        name: ToolName::Observe,
        description: || "观察本人状态、眼前对象和自己的新事件；远处和他人的私有记忆不可见。".into(),
        parameters: schema::observe,
        exec: observe,
    },
    ToolSpec {
        name: ToolName::Recall,
        description: || "检索自己的经历、认识和经验，返回来源和可信程度。".into(),
        parameters: schema::recall,
        exec: recall,
    },
    ToolSpec {
        name: ToolName::Inspect,
        description: || {
            "查看眼前道具的参数、条件和占用，或已知地点；远处的人、物和公告内容须到场查看。".into()
        },
        parameters: schema::inspect,
        exec: inspect,
    },
    ToolSpec {
        name: ToolName::SetGoal,
        description: || {
            "记录目标与承诺。condition 新建必填、更新可省略；完成须有世界证据，暂停、放弃和失败写明原因。和下一步动作放同一回复。".into()
        },
        parameters: schema::set_goal,
        exec: set_goal,
    },
    ToolSpec {
        name: ToolName::RunActions,
        description: || {
            format!(
                "提交 1–{} 项串行动作，失败停止后续步骤。前往、停留的参数见已知地图的 basic_actions；道具动作给 prop_id；背包转移 intent.verb 填拾取/放下/存放/取回/领取并给 inventory，不填 prop_id；写作给 writing；对人动手 intent.verb 填 people_here 里对方的 force_verbs 之一，recipient 填对方 ID，抢和偷再用 prop_id 填对方 carrying 里那件东西的 ID。",
                limits::ACTIONS_MAX
            )
        },
        parameters: schema::run_actions,
        exec: run_actions,
    },
    ToolSpec {
        name: ToolName::OfferInvitation,
        description: || {
            format!(
                "向在场的人发起交谈、同行、约定、赠予、用餐或亲近（牵手、依偎、拥抱）邀请；{} 分钟未回应过期。交谈和同行邀请发出后本次醒来结束，对方回应、重要通知或 {} 分钟后返回状态。",
                kernel::interactions::INVITE_MINUTES,
                OFFER_WAIT_MINUTES
            )
        },
        parameters: schema::offer_invitation,
        exec: invitations::offer,
    },
    ToolSpec {
        name: ToolName::ReplyInvitation,
        description: || {
            "接受或拒绝收到的邀请：interaction_id、accept、message。是否接受由自己决定。".into()
        },
        parameters: schema::reply_invitation,
        exec: invitations::reply,
    },
    ToolSpec {
        name: ToolName::Interact,
        description: || {
            "聊天中的操作：say 发言（to 可指定对象）、listen 倾听、leave 告辞；propose 提议一起走（同行）或约定时间地点，accept/decline 回答对方的提议；join 加入 nearby_chats（带 leader 的是路过的同行，加入就是跟着走）；cancel 取消自己发出的邀请或不再同行。每次只调用一个。".into()
        },
        parameters: schema::interact,
        exec: interact,
    },
    ToolSpec {
        name: ToolName::WaitFor,
        description: || {
            format!(
                "等待事件或若干分钟。只填 event：该类事件或重要通知到来就醒，没等到也在 {} 分钟后醒来重看；填 minutes 到点一定重看。轮到自己说话时调用等于 listen。",
                limits::EVENT_WAIT_MINUTES
            )
        },
        parameters: schema::wait_for,
        exec: wait_for,
    },
];

pub fn spec(name: ToolName) -> &'static ToolSpec {
    TOOLS
        .iter()
        .find(|t| t.name == name)
        .expect("工具表覆盖全部工具名")
}

/// 发给模型的工具定义，按轮次种类取子集。
pub fn definitions(kind: RequestKind) -> Vec<Value> {
    TOOLS
        .iter()
        .filter(|t| t.name.allowed_in(kind))
        .map(|t| {
            let mut definition = t.definition();
            // 交谈轮次只有 interact，且只列 say、listen、leave，和交谈规则一致。
            if kind == RequestKind::Chat {
                definition["function"]["description"] = json!(crate::prompts::CHAT_TOOLS_ONLY);
                definition["function"]["parameters"] = schema::chat_interact();
            }
            definition
        })
        .collect()
}

pub fn execute(ctx: &mut ToolContext, call: &ToolCall) -> Result<ToolOutcome, ToolError> {
    let name: ToolName = call.name.parse()?;
    (spec(name).exec)(ctx, call)
}

/// 参数解析失败时说明文字的开头。
const INVALID_ARGUMENTS: &str = "工具参数无效";
const INTENT_FIELDS: [&str; 5] = ["verb", "locale", "target", "duration_minutes", "until"];

fn decode<T: serde::de::DeserializeOwned>(value: &Value) -> Result<T, ToolError> {
    serde_json::from_value(value.clone()).map_err(|e| {
        ToolError::new(
            ToolErrorKind::InvalidArguments,
            format!("{INVALID_ARGUMENTS}：{}", explain(&e.to_string())),
        )
    })
}

/// 把 serde 的英文报错改成中文；run_actions 里放错层级的字段直接说明该放哪一层。
fn explain(error: &str) -> String {
    if let Some(rest) = error.strip_prefix("unknown field `") {
        let (field, rest) = rest.split_once('`').unwrap_or((rest, ""));
        let expected: Vec<&str> = rest.split('`').skip(1).step_by(2).collect();
        let hint = if INTENT_FIELDS.contains(&field) && expected.contains(&"intent") {
            format!("；{field} 要放在 intent 里面")
        } else if field == "prop_id" && expected.contains(&"verb") {
            format!("；{field} 要放在 intent 外面，与 intent 同级")
        } else {
            String::new()
        };
        let allowed = if expected.is_empty() {
            "这里不接受任何字段".to_string()
        } else {
            format!("这一层只有 {}", expected.join("、"))
        };
        return format!("不认识的字段 {field}，{allowed}{hint}");
    }
    if let Some(rest) = error.strip_prefix("missing field `") {
        return format!("缺少必填字段 {}", rest.trim_end_matches('`'));
    }
    if let Some(rest) = error.strip_prefix("invalid type: ") {
        return format!("字段类型不对：{rest}");
    }
    error.to_string()
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Empty {}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ReadContent {
    event_id: u64,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Inspect {
    id: String,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Actions {
    actions: Vec<ActionDraft>,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Wait {
    #[serde(default)]
    minutes: Option<f64>,
    #[serde(default)]
    event: Option<protocol::FactKind>,
    reason: String,
}

/// 发出交谈邀请后最多等对方这么久；到时仍无回应就交还本人决定。
const OFFER_WAIT_MINUTES: f64 = 60.0;

fn complete(value: Value) -> Result<ToolOutcome, ToolError> {
    Ok(ToolOutcome::Complete(value))
}

/// 本人；找不到时退回。
fn me<'w>(world: &'w World, ctx_actor: &str) -> Result<&'w kernel::world::Actor, ToolError> {
    Ok(resident(world, ctx_actor)?)
}

/// 世界命令的编号：会话、请求与调用三段，重放时可辨认。
fn command_id(ctx: &ToolContext, call: &ToolCall) -> String {
    format!("s{}-r{}-{}", ctx.session.id, ctx.request, call.id)
}
fn revision(ctx: &ToolContext) -> Result<u64, ToolError> {
    Ok(me(ctx.world, &ctx.session.actor_id)?.actions.revision)
}
fn require_idle(ctx: &ToolContext, message: &str) -> Result<(), ToolError> {
    if ctx.session.pending.is_empty() {
        Ok(())
    } else {
        Err(ToolError::new(ToolErrorKind::Busy, message))
    }
}

fn context_read(ctx: &mut ToolContext, call: &ToolCall) -> Result<ToolOutcome, ToolError> {
    complete(
        ctx.session
            .input
            .read(decode(&call.arguments)?)
            .map_err(ToolError::rejected)?,
    )
}
fn memory_search(ctx: &mut ToolContext, call: &ToolCall) -> Result<ToolOutcome, ToolError> {
    let query = decode(&call.arguments)?;
    let docs = ctx.documents.get(ctx.world, ctx.session);
    complete(notebook::search_in(&docs, query).map_err(ToolError::rejected)?)
}
fn memory_read(ctx: &mut ToolContext, call: &ToolCall) -> Result<ToolOutcome, ToolError> {
    let query = decode(&call.arguments)?;
    let docs = ctx.documents.get(ctx.world, ctx.session);
    complete(notebook::read_in(&docs, query).map_err(ToolError::rejected)?)
}
fn reflect(ctx: &mut ToolContext, call: &ToolCall) -> Result<ToolOutcome, ToolError> {
    notebook::apply_reflection(ctx.world, ctx.session, decode(&call.arguments)?)
        .map_err(ToolError::rejected)?;
    let book = &ctx.session.notebook;
    complete(json!({
        "saved": true,
        "through_event": book.through_event,
        "revision": book.revision
    }))
}
fn read_content(ctx: &mut ToolContext, call: &ToolCall) -> Result<ToolOutcome, ToolError> {
    let args = decode::<ReadContent>(&call.arguments)?;
    let reading = ctx
        .world
        .contents()
        .reading_result(&ctx.session.actor_id, args.event_id)?;
    complete(json!({"reading_result":reading,"event_id":args.event_id}))
}
fn observe(ctx: &mut ToolContext, call: &ToolCall) -> Result<ToolOutcome, ToolError> {
    decode::<Empty>(&call.arguments)?;
    let s = &mut *ctx.session;
    let (raw, _) = observation::observe(ctx.world, &s.actor_id, s.cursors.acknowledged)?;
    let (value, cursor) = crate::context::view::observation(s, &raw, 8_000);
    s.cursors.delivered = s.cursors.delivered.max(cursor);
    complete(crate::context::view::slim(&value))
}
fn recall(ctx: &mut ToolContext, call: &ToolCall) -> Result<ToolOutcome, ToolError> {
    let query = decode::<RecallQuery>(&call.arguments)?;
    let s = &mut *ctx.session;
    s.memory.ingest(ctx.world, &s.actor_id);
    let memories = ctx.index.recall(&s.actor_id, &s.memory, &query)?;
    complete(json!({ "memories": memories }))
}
fn inspect(ctx: &mut ToolContext, call: &ToolCall) -> Result<ToolOutcome, ToolError> {
    let args = decode::<Inspect>(&call.arguments)?;
    complete(observation::inspect(
        ctx.world,
        &ctx.session.actor_id,
        &args.id,
    )?)
}
fn set_goal(ctx: &mut ToolContext, call: &ToolCall) -> Result<ToolOutcome, ToolError> {
    let args = decode(&call.arguments)?;
    complete(goals::set_goal(ctx.world, ctx.session, args).map_err(ToolError::rejected)?)
}
fn interact(ctx: &mut ToolContext, call: &ToolCall) -> Result<ToolOutcome, ToolError> {
    let mut args = call.arguments.clone();
    let mut note = None;
    let mut chat_id_hint = None;
    if let Some(chat) = ctx.world.active_chat(&ctx.session.actor_id) {
        // 正在聊天时只有这一场对话：编号漏填就补上；回应对象写了名字就换成编号，不是参与者就不指定。
        if args.get("interaction_id").is_none() {
            args["interaction_id"] = json!(chat.id);
        }
        if matches!(args["operation"].as_str(), Some("say" | "listen" | "leave"))
            && args["interaction_id"].as_str().is_none_or(|id| {
                ctx.world
                    .interactions()
                    .of(&ctx.session.actor_id, id)
                    .is_none()
            })
        {
            // 不把模型写的 chat.id 等占位符替换成真实编号；只在拒绝后给下一次尝试提示。
            // 已存在但过时的互动保持原有错误，不暗示可把它当成当前聊天继续执行。
            chat_id_hint = Some(format!(
                "；当前聊天请原样填写 {}，不要使用 chat.id 这样的占位文字",
                json!({"interaction_id": chat.id})
            ));
        }
        if args["operation"] == "propose" {
            let partner = args["to"].as_str().map(str::to_owned).or_else(|| {
                let members = &chat.chat.as_ref()?.members;
                let mut others = members.iter().filter(|m| **m != ctx.session.actor_id);
                match (others.next(), others.next()) {
                    (Some(only), None) => Some(only.clone()),
                    _ => None,
                }
            });
            resolve_leader(
                ctx.world,
                &ctx.session.actor_id,
                partner.as_deref(),
                &mut args["interaction"],
            );
            resolve_appointment(ctx.world, &mut args["interaction"])?;
        }
        if let Some(to) = args["to"].as_str() {
            let members = chat.chat.as_ref().map(|c| &c.members);
            let resolved = members
                .into_iter()
                .flatten()
                .find(|id| *id == to || ctx.world.actor(id).is_some_and(|a| a.name == to));
            match resolved {
                Some(id) if *id != ctx.session.actor_id => args["to"] = json!(id),
                _ => {
                    note = Some(format!(
                        "to={to} 不是另一名在场参与者，这句话没有指定回应对象"
                    ));
                    args.as_object_mut().map(|o| o.remove("to"));
                }
            }
        }
    }
    let with_chat_hint = |mut error: ToolError| {
        if matches!(
            error.kind,
            ToolErrorKind::InvalidArguments | ToolErrorKind::World
        ) {
            if let Some(hint) = &chat_id_hint {
                error.message.push_str(hint);
            }
        }
        error
    };
    let command = decode::<InteractionCommand>(&args).map_err(with_chat_hint)?;
    if matches!(
        command,
        InteractionCommand::Offer { .. } | InteractionCommand::Reply { .. }
    ) {
        return Err(ToolError::new(
            ToolErrorKind::InvalidArguments,
            format!(
                "{INVALID_ARGUMENTS}：interact 不发邀请也不回应邀请，发邀请用 {}，回应用 {}",
                ToolName::OfferInvitation,
                ToolName::ReplyInvitation
            ),
        ));
    }
    let outcome = execute_interaction(ctx, call, command).map_err(with_chat_hint)?;
    Ok(match (outcome, note) {
        (ToolOutcome::Complete(mut value), Some(note)) => {
            value["note"] = json!(note);
            ToolOutcome::Complete(value)
        }
        (outcome, _) => outcome,
    })
}

/// 约定的时刻写成「D3 14:00」（只写「14:00」按接下来最近的那个时刻）：换成世界分钟，世界只认分钟。
/// 写法不对时说明怎么写。
pub(crate) fn resolve_appointment(world: &World, interaction: &mut Value) -> Result<(), ToolError> {
    if interaction["kind"] != "appointment" {
        return Ok(());
    }
    let Some(text) = interaction["at"].as_str().map(str::trim) else {
        return Ok(());
    };
    let now = world.minutes();
    let at = kernel::calendar::parse_clock(text).or_else(|| {
        let (h, m) = text.split_once(':')?;
        let (h, m) = (h.parse::<u32>().ok()?, m.parse::<u32>().ok()?);
        (h < 24 && m < 60).then(|| {
            let today = now - kernel::time_of_day(now) + f64::from(h * 60 + m);
            if today > now {
                today
            } else {
                today + kernel::DAY
            }
        })
    });
    let at = at.ok_or_else(|| {
        ToolError::new(
            ToolErrorKind::InvalidArguments,
            format!("{INVALID_ARGUMENTS}：约定时刻写成 D日数 HH:MM，例如 D3 14:00"),
        )
    })?;
    interaction["at"] = json!(at);
    Ok(())
}

/// 同行的带路人可以写 self、对方编号或名字：换成编号，世界只认编号。认不出就原样交给世界去拒绝。
pub(crate) fn resolve_leader(
    world: &World,
    me: &str,
    partner: Option<&str>,
    interaction: &mut Value,
) {
    if interaction["kind"] != "walk" {
        return;
    }
    let Some(raw) = interaction["leader"].as_str().map(str::trim) else {
        return;
    };
    let id = match raw {
        "self" | "me" | "我" | "自己" => Some(me.to_owned()),
        "partner" | "you" | "对方" | "你" => partner.map(str::to_owned),
        _ => world
            .actor_ids()
            .into_iter()
            .find(|id| id == raw || world.actor(id).is_some_and(|a| a.name == raw)),
    };
    if let Some(id) = id {
        interaction["leader"] = json!(id);
    }
}

fn execute_interaction(
    ctx: &mut ToolContext,
    call: &ToolCall,
    command: InteractionCommand,
) -> Result<ToolOutcome, ToolError> {
    // 收到交谈或同行邀请时可以在普通动作继续执行期间答复，其他工具仍遵守原等待规则。
    let talk_reply = matches!(&command, InteractionCommand::Reply { interaction_id, .. }
        if ctx.world.interactions().of(&ctx.session.actor_id, interaction_id)
            .is_some_and(|i| i.kind.has_chat()));
    if !talk_reply || ctx.session.pending.iter().any(PendingTool::blocks_request) {
        require_idle(ctx, "先等待当前工具结果，再处理互动")?;
    }
    let (id, revision) = (command_id(ctx, call), revision(ctx)?);
    let actor = ctx.session.actor_id.clone();
    let result = ctx.world.interact(&actor, &id, revision, &command)?;
    if result.status == InteractionStatus::Running && result.chat.is_none() {
        return Ok(ToolOutcome::Pending(PendingTool::Interaction {
            call: call.clone(),
            interaction_id: result.id,
        }));
    }
    let talk_offer = matches!(
        &command,
        InteractionCommand::Offer { interaction, .. } if interaction.has_chat()
    );
    if talk_offer && result.status == InteractionStatus::Offered {
        // 发出交谈或同行邀请后不再占一次请求去等：对方回应、重要通知或超时时把邀请状态一并返回。
        // 游标取邀请发出之后的，邀请本身的事件不算回应。
        return Ok(ToolOutcome::Pending(PendingTool::Wait {
            call: call.clone(),
            until: ctx.world.minutes() + OFFER_WAIT_MINUTES,
            after_cursor: me(ctx.world, &actor)?.journal.cursor(),
            event: Some(protocol::FactKind::Interaction),
            invitation: Some(result.id),
        }));
    }
    // 台词已经在观察和事件里，回执只带状态和轮次。
    let mut view = json!(kernel::interactions::Interactions::observation(
        &actor, &result
    ));
    if let Some(object) = view.as_object_mut() {
        object.remove("entries");
    }
    complete(json!({"interaction":view}))
}
fn run_actions(ctx: &mut ToolContext, call: &ToolCall) -> Result<ToolOutcome, ToolError> {
    let args = action_arguments::decode(&call.arguments)?;
    require_idle(ctx, "一次会话只能等待一组身体动作或事件")?;
    let (group_id, revision) = (command_id(ctx, call), revision(ctx)?);
    ctx.world
        .run_actions(&ctx.session.actor_id, &group_id, revision, &args.actions)?;
    Ok(ToolOutcome::Pending(PendingTool::Actions {
        call: call.clone(),
        group_id,
        reported_running: false,
    }))
}
fn wait_for(ctx: &mut ToolContext, call: &ToolCall) -> Result<ToolOutcome, ToolError> {
    let args = decode::<Wait>(&call.arguments)?;
    require_idle(ctx, "已有动作或事件正在等待")?;
    if args
        .event
        .is_some_and(|k| !schema::wait_events().contains(&k))
    {
        return Err(ToolError::new(
            ToolErrorKind::InvalidArguments,
            "等待时你手上没有进行中的动作，不会有动作或阅读的结果。等别人到来用 presence，等别人说话用 speech，想过一会儿再看就填 minutes。",
        ));
    }
    let minutes = match (args.minutes, args.event) {
        (Some(m), _) if m.is_finite() && limits::WAIT_MINUTES.contains(&m) => m,
        // 只等事件：到来或收到重要通知就醒，没等到也按时醒来重看。
        (None, Some(_)) => limits::EVENT_WAIT_MINUTES,
        _ => {
            return Err(ToolError::new(
                ToolErrorKind::InvalidArguments,
                format!(
                    "minutes 须在 {}–{} 分钟内；不填 minutes 时必须填 event",
                    limits::WAIT_MINUTES.start(),
                    limits::WAIT_MINUTES.end()
                ),
            ))
        }
    };
    if args.reason.chars().count() > limits::WAIT_REASON_CHARS {
        return Err(ToolError::new(
            ToolErrorKind::InvalidArguments,
            format!("reason 最多 {} 字", limits::WAIT_REASON_CHARS),
        ));
    }
    let actor = ctx.session.actor_id.clone();
    // 轮到自己说话时等待就是倾听；同行路上没轮到谁（带路人边走边等）照常等待
    if let Some(chat) = ctx
        .world
        .active_chat(&actor)
        .filter(|_| ctx.world.chat_turn(&actor))
    {
        let command = InteractionCommand::Listen {
            interaction_id: chat.id.clone(),
        };
        let (id, revision) = (command_id(ctx, call), revision(ctx)?);
        ctx.world.interact(&actor, &id, revision, &command)?;
        return complete(json!({"listening":true}));
    }
    Ok(ToolOutcome::Pending(PendingTool::Wait {
        call: call.clone(),
        until: ctx.world.minutes() + minutes,
        // 请求途中到达但模型尚未看到的通知，也必须唤醒这次等待。
        after_cursor: ctx.session.cursors.delivered,
        event: args.event,
        invitation: None,
    }))
}
