//! 聊天事件的语义记录。气泡尺寸、寿命和位置由显示端决定。
use crate::InteractionStatus;
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;

/// 聊天记录的一条：说了话，或加入、离开、结束这类过程记录。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ChatEntryKind {
    Speech,
    Joined,
    Left,
    Ended,
    /// 提出提议（同行等），正文是提议内容
    Proposed,
    /// 答应了提议
    Accepted,
    /// 没答应，或提议人撤回
    Declined,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatEntry {
    pub seq: u64,
    pub at: f64,
    pub actor: String,
    pub name: String,
    pub kind: ChatEntryKind,
    pub text: String,
    pub audience: BTreeSet<String>,
}

#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatState {
    pub members: BTreeSet<String>,
    pub ever_members: BTreeSet<String>,
    pub turn_queue: Vec<String>,
    pub entries: Vec<ChatEntry>,
    pub passes: usize,
    pub resume_at: f64,
    /// 等人回答的提议；旧存档没有这一项。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub proposal: Option<ChatProposal>,
}

/// 交谈里提出、等 to 回答的提议。答应、拒绝、撤回或有一方离开交谈时清掉。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChatProposal {
    pub by: String,
    pub to: String,
    #[serde(serialize_with = "crate::sorted")]
    pub interaction: crate::InteractionKind,
    pub at: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpeechView {
    pub chat_id: String,
    pub seq: u64,
    pub at: f64,
    pub text: String,
    /// 台词的第一句，地图气泡用；规则与想法的心声相同。
    #[serde(default)]
    pub line: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatPresence {
    pub id: String,
    pub participants: Vec<String>,
    pub turn: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatSummary {
    pub id: String,
    pub locale: String,
    pub participants: Vec<String>,
    pub status: InteractionStatus,
    pub created_at: f64,
    pub ended_at: Option<f64>,
    pub entries: usize,
}

/// 同一处所里进行中的聊天：谁在聊。路过的同行另带带路人，加入就是跟着一起走。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct NearbyChat {
    pub id: String,
    pub locale: String,
    pub members: BTreeSet<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub leader: Option<String>,
}

/// 聊天参与者看到的聊天：只含本人实际听到的最近台词。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ChatObservation {
    #[serde(serialize_with = "crate::sorted")]
    pub entries: Vec<ChatEntry>,
    pub id: String,
    pub initiator: String,
    #[serde(serialize_with = "crate::sorted")]
    pub kind: crate::InteractionKind,
    pub locale: String,
    pub members: BTreeSet<String>,
    pub partner: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub proposal: Option<ChatProposal>,
    pub reason: Option<String>,
    pub status: InteractionStatus,
    pub turn: Option<String>,
}

/// 参与者对一项互动的观察：聊天只给听到的部分，其他互动给完整记录。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum InteractionObservation {
    Chat(ChatObservation),
    Pair(#[serde(serialize_with = "crate::sorted")] crate::Interaction),
}
