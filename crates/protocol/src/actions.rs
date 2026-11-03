//! Agent 命令与世界回执。正文用于展示，编号与状态用于接续和去重。
use crate::IntentDraft;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ActionDraft {
    pub intent: IntentDraft,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub inventory: Option<InventoryAction>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub prop_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub recipient: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub writing: Option<WritingDraft>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WritingDraft {
    pub title: String,
    pub text: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ActionStatus {
    Succeeded,
    Failed,
    Interrupted,
    Cancelled,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ActionResult {
    pub action_id: String,
    pub group_id: String,
    pub prop_id: Option<String>,
    pub verb: String,
    pub started_at: Option<f64>,
    pub ended_at: f64,
    pub status: ActionStatus,
    /// 仅记录已发生的变化；取消和失败也可能已经消耗时间与体力。
    pub changes: Vec<String>,
    pub reason: Option<String>,
    pub event_ids: Vec<u64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum GroupStatus {
    Running,
    Succeeded,
    Failed,
    Interrupted,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ActionGroup {
    pub id: String,
    pub accepted_at: f64,
    pub actions: Vec<ActionDraft>,
    pub results: Vec<ActionResult>,
    pub status: GroupStatus,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FactKind {
    // 旧委托事件仅作为历史记录读取，不触发新的紧急通知。
    #[serde(alias = "job")]
    Observation,
    /// 实际读到的内容；短公告也属于有内容的事实。
    Readable,
    Notice,
    Action,
    /// 明确记录是谁说的；说法内容不因此成为经世界验证的事实。
    Speech,
    Interaction,
    /// 人来人往：同一地点里有人来了、有人往哪儿去了。
    Presence,
}
impl FactKind {
    pub fn label(self) -> &'static str {
        match self {
            Self::Observation => "观察",
            Self::Readable => "阅读内容",
            Self::Notice => "收到通知",
            Self::Action => "行动经历",
            Self::Speech => "交谈",
            Self::Interaction => "共同活动",
            Self::Presence => "人来人往",
        }
    }
}

/// 每个村民独立递增的事件编号。运行器只确认已处理的游标，不清空新事件。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WorldFact {
    pub event_id: u64,
    pub at: f64,
    pub kind: FactKind,
    pub text: String,
    pub objects: Vec<String>,
    pub action_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub readable: Option<ReadableFact>,
}

/// 只记录本次阅读实际取得的内容身份，不把公告的说法当成已验证的世界事实。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ReadableFact {
    pub id: String,
    /// 标题和正文的 SHA-256；同一编号改正文时也能区分。
    pub version: String,
    pub previously_read: bool,
    /// 旧存档没有保存版本时为 None，不能据此宣称内容没有变化。
    pub previous_version: Option<String>,
}

/// Transfer operations share the timed, idempotent action queue.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "operation", rename_all = "snake_case", deny_unknown_fields)]
pub enum InventoryAction {
    PickUp {
        items: Vec<String>,
    },
    Drop {
        items: Vec<String>,
    },
    Store {
        items: Vec<String>,
        container: String,
    },
    Retrieve {
        items: Vec<String>,
        container: String,
    },
    Take {
        source: String,
        action: String,
        quantity: u32,
    },
}
impl InventoryAction {
    pub fn label(&self) -> &'static str {
        match self {
            Self::PickUp { .. } => "拾取",
            Self::Drop { .. } => "放下",
            Self::Store { .. } => "存放",
            Self::Retrieve { .. } => "取回",
            Self::Take { .. } => "领取",
        }
    }
    pub fn items(&self) -> &[String] {
        match self {
            Self::PickUp { items }
            | Self::Drop { items }
            | Self::Store { items, .. }
            | Self::Retrieve { items, .. } => items,
            Self::Take { .. } => &[],
        }
    }
}
