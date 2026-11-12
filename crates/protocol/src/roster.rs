//! Roster 流（后端 → 前端，全量）：每个处所里在场的人与他们的活动投影。
use crate::{
    At, BodyView, ChatPresence, InventoryView, NeedState, ResidentAgentView, SpeechView,
    ThoughtView,
};
use serde::{Deserialize, Serialize};

/// 名册成员的种类。现在只有村民；其他个体进入名册时在这里加变体。
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MemberKind {
    #[default]
    Resident,
    Avatar,
}

/// 当前活动是否有进度语义：移动与定时活动是 advancing；站立、旁听、空等是 placeholder。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ActivityKind {
    Advancing,
    Placeholder,
}

/// 动作属于哪一类；前端按它判断，动作词只用来显示。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum VerbKind {
    /// 前往某处
    Goto,
    /// 停留、空等，以及失能后原地不动
    Stay,
    /// 使用道具的动作：动作词是道具定义里的动作名
    Prop,
    /// 与人的共同活动：交谈、赠予、招待
    Interaction,
    /// 背包操作：拾取、放下、存放、取回、领取
    Inventory,
}

/// 精确导航下的移动阶段：travel 沿路线走，approach 是抵达处所后走向操作点。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MovementPhase {
    Travel,
    Approach,
}

/// 村民计划的只读投影。`current` 是正在执行的活动，`upcoming` 是已经
/// 通过世界校验、尚未开始的队列。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlanView {
    pub current: String,
    pub upcoming: Vec<String>,
    /// 身体闲着、什么也没安排（`current` 是「等待新计划」）；角色卡这时改说 Agent 在等什么、想什么
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub idle: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RosterMember {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub appearance: Option<crate::Appearance>,
    #[serde(default)]
    pub inventory: InventoryView,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub chat: Option<ChatPresence>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub speech: Option<SpeechView>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub movement: Option<MovementView>,
    pub id: String,
    pub name: String,
    pub kind: MemberKind,
    pub at: At,
    /// 表现语义：动词（前往 / 停留 / 工作 / 睡觉 …）
    pub verb: String,
    /// 动词属于哪一类
    pub verb_kind: VerbKind,
    pub activity: ActivityKind,
    /// 身体需求实时值（观察仪表用；无需求的个体为空）
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub needs: Vec<NeedState>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub body: Option<BodyView>,
    /// 当前活动与后续计划的只读清单（观察仪表用）
    pub plan: PlanView,
    /// 最近一次决定时的想法（无则省略）
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub thought: Option<ThoughtView>,
    /// Agent 此刻的状态（没有会话的个体省略）。角色卡细节不在名册里，见 ResidentDetailView
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub resident_agent: Option<ResidentAgentView>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RosterLocale {
    pub locale: String,
    pub members: Vec<RosterMember>,
}

/// 移动中的人在精确导航地图上的路线与阶段；几何由前端按路线 id 解析。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MovementView {
    pub route: String,
    pub navigation_revision: u64,
    pub destination_station: String,
    pub phase: MovementPhase,
}
