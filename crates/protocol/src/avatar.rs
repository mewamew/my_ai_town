//! 玩家命令与化身个人视图；二维只上传方向，三维上传前端碰撞解算后的姿态。
use crate::{
    ActionDraft, Appearance, BodyView, ChatEntry, ContentText, InteractionCommand, InteractionKind,
    InteractionStatus, InventoryView, Locus, NearbyChat, NeedState, PropActionView, StoredItem,
};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AvatarPose {
    pub actor: String,
    pub locale: String,
    pub space: String,
    pub position: [f64; 3],
    pub yaw: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum AvatarCommand {
    View,
    Enter {
        name: String,
        appearance: Appearance,
    },
    Possess {
        resident: String,
    },
    Resume {
        token: String,
    },
    Heartbeat,
    Leave,
    Profile {
        name: String,
        appearance: Appearance,
    },
    Stop,
    Portal {
        id: String,
    },
    Action {
        revision: u64,
        action: ActionDraft,
    },
    Interact {
        revision: u64,
        command: InteractionCommand,
    },
    RequestTurn {
        chat_id: String,
        revision: u64,
    },
    /// 化身神力：对够得着的人施展。只有世界打开了化身神力、控制的是化身本人时才行。
    Miracle {
        revision: u64,
        recipient: String,
        miracle: MiracleKind,
    },
}

/// 化身神力的三种：复活死者、治好伤病、补满饱腹精力水分。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MiracleKind {
    Revive,
    Heal,
    Refill,
}

/// 玩家控制目标的个人视图。地图不支持化身、还没有控制目标、有控制目标三种形状。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum AvatarView {
    Present(Box<AvatarState>),
    /// 支持化身，但还没有化身或附身目标；actor 为 null。
    Empty {
        actor: (),
        supported: bool,
        units: f64,
    },
    Unsupported {
        supported: bool,
    },
}

/// 有控制目标时的完整视图。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AvatarState {
    pub actor: AvatarActor,
    /// 附身时对方还在路上，到达后才交给玩家。
    pub awaiting_arrival: bool,
    pub can_drop: bool,
    /// 最近三个动作的变化与失败原因。
    pub feedback: Vec<String>,
    pub interactions: Vec<AvatarInteraction>,
    /// 化身神力开着，控制的又是化身本人：能对够得着的人施展。
    pub miracles: bool,
    pub mode: AvatarMode,
    pub navigation_revision: u64,
    pub nearby: Vec<NearbyPerson>,
    /// 附近还说不上话的人：再走近些，或换个不隔着东西的位置。
    #[serde(default)]
    pub approach: Vec<ApproachPerson>,
    pub nearby_chats: Vec<NearbyChat>,
    pub portals: Vec<PortalView>,
    pub props: Vec<AvatarPropView>,
    pub reading: Option<ContentText>,
    pub supported: bool,
    pub units: f64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AvatarMode {
    Avatar,
    Possession,
}

/// 控制目标本人。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AvatarActor {
    pub activity: String,
    #[serde(serialize_with = "crate::sorted")]
    pub appearance: Appearance,
    #[serde(serialize_with = "crate::sorted")]
    pub body: Option<BodyView>,
    pub busy: bool,
    pub id: String,
    pub inventory: InventoryView,
    #[serde(serialize_with = "crate::sorted")]
    pub locus: Locus,
    pub name: String,
    #[serde(serialize_with = "crate::sorted")]
    pub needs: Vec<NeedState>,
    pub present: bool,
    pub remaining: String,
    pub revision: u64,
}

/// 够得着的人。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct NearbyPerson {
    pub activity: String,
    /// 完全空闲，可以一起开始双方活动。
    pub available: bool,
    pub can_talk: bool,
    /// 现在聊不了的原因（正在和别人说话、倒下了……）；能聊时没有。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub busy: Option<String>,
    /// 已经死了：开着化身神力时能复活。
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub dead: bool,
    pub id: String,
    pub name: String,
}

/// 附近还说不上话的人。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ApproachPerson {
    pub id: String,
    pub name: String,
    /// 离玩家多少米。
    pub distance: f64,
    /// 已经够近，只是中间有东西挡着。
    pub blocked: bool,
}

/// 够得着的道具。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AvatarPropView {
    pub actions: Vec<PropActionView>,
    /// 公告栏：化身站在它跟前可以直接张贴公告
    pub bulletin_board: bool,
    pub carried: bool,
    pub contents: Vec<StoredItem>,
    pub id: String,
    pub name: String,
    pub portable: bool,
    pub storage_slots: u32,
}

/// 附近的门口。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PortalView {
    pub id: String,
    pub label: String,
}

/// 本人参与的互动：聊天与其他双方互动两种形状。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum AvatarInteraction {
    Chat(AvatarChatItem),
    Pair(AvatarPairItem),
}

/// 聊天：听到的台词、成员与轮次，外加邀请内容和玩家能不能发言。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AvatarChatItem {
    pub can_request_turn: bool,
    pub can_speak: bool,
    #[serde(serialize_with = "crate::sorted")]
    pub entries: Vec<ChatEntry>,
    pub expires_at: f64,
    pub id: String,
    pub initiator: String,
    #[serde(serialize_with = "crate::sorted")]
    pub kind: InteractionKind,
    pub locale: String,
    pub members: BTreeSet<String>,
    pub message: String,
    pub partner: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub proposal: Option<crate::ChatProposal>,
    pub reason: Option<String>,
    pub reply: Option<String>,
    pub status: InteractionStatus,
    pub turn: Option<String>,
    /// 受邀的村民回应格式出错时给邀请者看的说明，由 host 填；没有时不输出。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub response_error: Option<String>,
}

/// 赠予、招待用餐等双方互动：完整记录，外加玩家能不能发言。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AvatarPairItem {
    pub accepted: Option<bool>,
    pub can_request_turn: bool,
    pub can_speak: bool,
    pub changes: Vec<String>,
    pub created_at: f64,
    pub duration_minutes: f64,
    pub ended_at: Option<f64>,
    pub event_ids: BTreeMap<String, Vec<u64>>,
    pub expires_at: f64,
    pub id: String,
    pub initiator: String,
    #[serde(serialize_with = "crate::sorted")]
    pub kind: InteractionKind,
    pub locale: String,
    pub message: String,
    pub partner: String,
    pub reason: Option<String>,
    pub reply: Option<String>,
    pub started_at: Option<f64>,
    pub status: InteractionStatus,
    /// 同 `AvatarChatItem::response_error`。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub response_error: Option<String>,
}

/// 发给一个连接的化身状态：内核的化身视图，加上 host 的世界编号、速度、控制租约与位置上报回执。
/// 线上按字段名字母序输出（`ServerMsg` 里经 `crate::sorted`），与改成结构体之前一致。
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct AvatarSession {
    #[serde(flatten)]
    pub view: AvatarSight,
    pub world_id: String,
    /// 化身走路的速度：正常速度的模拟分钟 / 现实秒，0 为暂停。
    pub speed: f64,
    /// 本连接持有控制且在线。
    pub controlled: bool,
    /// 化身或附身目标已被某个连接控制。
    pub occupied: bool,
    /// 附身时本人最近的日志，新的在前。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub recent: Option<Vec<RecentEvent>>,
    /// 附身时本人的目标。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub goals: Option<Vec<AvatarGoal>>,
    /// 本连接持有的租约。
    #[serde(flatten)]
    pub lease: Option<AvatarLease>,
    /// 三维地图由前端上报位置；二维地图不输出。
    #[serde(skip_serializing_if = "std::ops::Not::not")]
    pub client_positions: bool,
    /// 玩家操控的人的步速；没有行走地图时不输出。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub walk: Option<AvatarWalk>,
    /// 三维地图且本连接持有租约时：位置上报的处理结果。
    #[serde(flatten)]
    pub position: Option<PositionAck>,
}

/// 本连接能看到什么。
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(untagged)]
pub enum AvatarSight {
    /// 内核给出的化身视图。
    Own(AvatarView),
    /// 化身或附身目标正被另一个页面控制：只说明地图支持化身，不给视图。
    Occupied { actor: (), supported: bool },
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct RecentEvent {
    pub at: f64,
    pub text: String,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct AvatarGoal {
    pub status: crate::GoalStatus,
    pub text: String,
}

/// 控制租约：控制代次、断线恢复凭据、已处理到的操作序号。
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct AvatarLease {
    pub epoch: String,
    pub resume_token: String,
    pub sequence: u64,
}

/// 玩家操控的人的步速：每模拟分钟走多少米，按住奔跑时乘的倍数。服务端按它移动化身，
/// 前端按它判断走没走动、到点前减速，并照着同样的方向和步速逐帧预测自己的小人。
#[derive(Debug, Clone, Copy, PartialEq, Serialize)]
pub struct AvatarWalk {
    pub metres_per_minute: f64,
    pub sprint_factor: f64,
}

/// 最近处理的位置上报序号，以及被拒时的原因（接受时为 null）。
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct PositionAck {
    pub position_error: Option<String>,
    pub position_sequence: u64,
}

/// 化身命令回执的结果类别。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AvatarResultCode {
    Ok,
    /// host 的其他规则不允许，或村民会话交接失败。
    Rejected,
    /// 命令带的世界编号不是当前世界。
    WrongWorld,
    /// 存盘失败，或上一次存盘失败还没恢复。
    SaveFailed,
    /// 还没设置世界观。
    NotReady,
    /// 控制租约失效、恢复窗口已过或恢复凭据不对。
    ControlLost,
    /// 同一操作编号已用于其他内容。
    Conflict,
    /// 世界暂停中。
    Paused,
    /// 附身的村民还没走到。
    Busy,
    /// 另一个页面正在控制。
    Occupied,
    /// 内核规则不允许。
    World,
}
