//! 狼人杀的线上形状。座号从 1 数；时刻是世界分钟。
//! 名册里的 `WerewolfView` 是上帝视角（身份、夜里的选择都在），给模型的 `WerewolfContext`
//! 只有这个人自己知道的事。
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WerewolfRole {
    Wolf,
    Seer,
    Witch,
    Hunter,
    Guard,
    Villager,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WerewolfPhase {
    /// 第 1 天天亮前：在家等开局
    Waiting,
    /// 白天自由活动
    Day,
    /// 敲过钟，大家去议事广场
    Gather,
    /// 议事发言：按座次一次一人
    Speech,
    /// 投票：同时交，交齐或到点一起亮票
    Vote,
    /// 被放逐的人说遗言
    LastWords,
    /// 猎人倒下前决定开不开枪
    Shot,
    /// 回家，等入夜
    Dusk,
    /// 夜里身份行动，之后睡到天亮
    Night,
    /// 一局结束
    Over,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WerewolfSide {
    Good,
    Wolf,
}

/// 怎么出局的
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WerewolfOut {
    /// 夜里被狼人杀害
    Killed,
    /// 被女巫毒死
    Poisoned,
    /// 白天被投票放逐
    Exiled,
    /// 被猎人开枪带走
    Shot,
    /// 法官没经手：白天被人害死、饿死，或者离开了这里
    Died,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WerewolfSeat {
    pub seat: u32,
    /// 村民编号
    pub id: String,
    pub name: String,
    pub role: WerewolfRole,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub out: Option<WerewolfOut>,
    /// 出局的那一天（夜里出局算那一夜的序号）
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub out_day: Option<u32>,
}

/// 一段话：议事发言、遗言或狼人频道里的话
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WerewolfLine {
    pub seat: u32,
    pub text: String,
    pub at: f64,
    /// 说的时候人不在议事广场
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub away: bool,
    /// 遗言
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub last: bool,
    /// 交这段话时写的打算，只给旁观的人看
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
}

/// 一张票；target 为空是弃票
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WerewolfBallot {
    pub voter: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub target: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
}

/// 预言家查验了谁、是不是狼人
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct WerewolfCheck {
    pub seat: u32,
    pub wolf: bool,
}

/// 一夜里各身份的选择（上帝视角）
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct WerewolfNight {
    /// 第几夜
    pub night: u32,
    /// 狼人频道
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub wolf_lines: Vec<WerewolfLine>,
    /// 狼人定下的刀口
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub kill: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub guard: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub check: Option<WerewolfCheck>,
    /// 女巫用了解药
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub save: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub poison: Option<u32>,
}

/// 名册里随时间广播的狼人杀状态（上帝视角），前端按它画横幅、座位和侧栏
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WerewolfView {
    pub phase: WerewolfPhase,
    /// 第几天；开局前是 0
    pub day: u32,
    pub seats: Vec<WerewolfSeat>,
    /// 法官此刻在说什么，横幅上的一句
    pub notice: String,
    /// 轮到谁：发言、遗言或开枪
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub turn: Option<u32>,
    /// 这一步的期限
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub until: Option<f64>,
    /// 今天的发言和遗言，按先后
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub lines: Vec<WerewolfLine>,
    /// 投票：亮票前只有交了票的人（target 不给），亮票后是全部
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub ballots: Vec<WerewolfBallot>,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub revealed: bool,
    /// 今晚，或天亮后的昨晚
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub night: Option<WerewolfNight>,
    /// 天亮公布的昨晚倒下的人
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub dawn: Vec<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub winner: Option<WerewolfSide>,
}

/// 给模型看的狼人杀：自己是谁、知道什么、此刻该做什么
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WerewolfContext {
    pub phase: String,
    pub me: String,
    pub goal: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub known: Vec<String>,
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
