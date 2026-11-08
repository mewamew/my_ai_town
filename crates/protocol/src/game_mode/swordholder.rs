//! 执剑人之夜的线上形状。座号从 1 数；时刻是世界分钟。
//! 名册里的 `SwordholderView` 是上帝视角（票投给了谁、每个人交选择时写的打算都在），
//! 给模型的 `SwordholderContext` 只有这个人自己知道的事。
use serde::{Deserialize, Serialize};

/// 这一局里的身份：按入住的号码排，1 号是现任执剑人，2、3 号是候选人，4 号是三体世界的代表，其余是选民
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SwordholderRole {
    /// 现任执剑人：没有选票，演说开始前说一句，19:00 交出开关
    Holder,
    /// 候选人：演说、争取选票；当选的人交接后握着开关
    Candidate,
    /// 三体世界的代表：没有选票
    Envoy,
    /// 选民：表态，投一票
    Voter,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SwordholderPhase {
    /// 天亮前：在家等开局
    Waiting,
    /// 白天自由活动：拉票、私聊、喝茶
    Day,
    /// 敲过钟，大家去广场
    Gather,
    /// 广场上按次序一次一人：现任执剑人说一句、两位候选人演说、选民表态
    Speech,
    /// 选民同时投票，交齐或到点一起亮票
    Vote,
    /// 平票：现任执剑人从平票的候选人里指定一位
    Tiebreak,
    /// 选出来了，等 19:00 交接
    Interval,
    /// 联合国大厅地下：现任执剑人对新执剑人说一句，交出开关
    Handover,
    /// 水滴来袭：执剑人在期限内按或不按
    Attack,
    /// 结局已定：三体世界的代表对全镇说最后一段话
    Aftermath,
    /// 一局结束
    Over,
}

/// 结局
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SwordholderEnding {
    /// 按下了：引力波广播发出，三体世界的坐标传遍宇宙，水滴转向
    Broadcast,
    /// 没按或到点：威慑失败，水滴摧毁引力波天线
    Failed,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SwordholderSeat {
    pub seat: u32,
    /// 村民编号
    pub id: String,
    pub name: String,
    pub role: SwordholderRole,
    /// 法官没经手就不在了：被人害死、饿死，或者离开了这里
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub gone: bool,
}

/// 一段话：现任执剑人的一句、演说、表态、交接时的话、三体代表最后的宣布
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SwordholderLine {
    pub seat: u32,
    /// 场合：一句话、演说、表态、交接、宣布
    pub occasion: String,
    pub text: String,
    pub at: f64,
    /// 说的时候人不在该在的地方（广场或联合国大厅）
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub away: bool,
    /// 交这段话时写的打算，只给旁观的人看
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
}

/// 一张票；target 为空是弃票（亮票前也不给 target）
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SwordholderBallot {
    pub voter: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub target: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
}

/// 执剑人在水滴来袭时交的决定；到点没交就没有这一项
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SwordholderDecision {
    pub seat: u32,
    /// 按下了开关
    pub press: bool,
    pub at: f64,
    /// 按或不按时说的话
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
}

/// 名册里随时间广播的执剑人之夜（上帝视角），前端按它画横幅、名单、发言卡、票型、开关卡和结局卡
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SwordholderView {
    pub phase: SwordholderPhase,
    pub seats: Vec<SwordholderSeat>,
    /// 法官此刻在说什么，横幅上的一句
    pub notice: String,
    /// 轮到谁：说话、指定或按开关
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub turn: Option<u32>,
    /// 这一步的期限
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub until: Option<f64>,
    /// 水滴来袭时离天线被毁还有几分钟；只在那十分钟里有
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub left: Option<f64>,
    /// 今天说过的话，按先后
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub lines: Vec<SwordholderLine>,
    /// 投票：亮票前只有交了票的人（target 不给），亮票后是全部
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub ballots: Vec<SwordholderBallot>,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub revealed: bool,
    /// 当选的人
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub elected: Option<u32>,
    /// 平票后由现任执剑人指定
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub appointed: bool,
    /// 此刻握着开关的人
    pub swordholder: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub decision: Option<SwordholderDecision>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ending: Option<SwordholderEnding>,
    /// 引力波天线所在的地点编号：画面里水滴朝它飞；地图上没有天线时不给
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub antenna: Option<String>,
}

/// 给模型看的执剑人之夜：自己是谁、此刻该做什么、今天大家说了什么
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SwordholderContext {
    pub phase: String,
    pub me: String,
    pub goal: String,
    pub seats: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub history: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub today: Vec<String>,
    pub now: String,
    /// 此刻能用 mode_action 交的动作
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub actions: Vec<String>,
}
