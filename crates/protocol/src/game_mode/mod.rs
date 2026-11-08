//! 玩法（大逃杀的潮水圈、狼人杀……）在线上的形状。一个世界同时最多开一个玩法；没开时名册、设定里都没有
//! 玩法的字段，给模型的观察里也没有那一栏。加一个玩法：在这个目录写它自己的类型，再在下面三个枚举里
//! 各加一项（内核那边见 kernel 的 game_mode）。
mod tide;
mod werewolf;

pub use tide::{TideCircle, TideContext, TideNews, TideNewsKind, TidePhase, TidePlayer, TideView};
pub use werewolf::{
    WerewolfBallot, WerewolfCheck, WerewolfContext, WerewolfLine, WerewolfNight, WerewolfOut,
    WerewolfPhase, WerewolfRole, WerewolfSeat, WerewolfSide, WerewolfView,
};

use serde::{Deserialize, Serialize};

/// 名册里随时间广播的玩法状态，前端按 kind 认出是哪个玩法。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum GameModeView {
    Tide(TideView),
    Werewolf(WerewolfView),
}

/// 打开哪个玩法、带什么设置；SetGameMode 不带它就是关掉。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum GameModeChoice {
    /// 潮水圈：seed 定下这一局的圈；不给时 host 随机取一个
    Tide {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        seed: Option<u32>,
    },
    /// 狼人杀：seed 定下谁拿什么身份；day_hours 是白天自由活动几小时（天亮到 16:30 敲钟）
    Werewolf {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        seed: Option<u32>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        day_hours: Option<u32>,
    },
}

/// 给模型看的一栏：观察里的键名是 `key()`，值就是这一项本身。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum GameModeContext {
    Tide(TideContext),
    Werewolf(WerewolfContext),
}

impl GameModeContext {
    pub fn key(&self) -> &'static str {
        match self {
            GameModeContext::Tide(_) => "tide",
            GameModeContext::Werewolf(_) => "werewolf",
        }
    }
}

/// 玩法动作：模型用 mode_action 工具交的一项选择（投票、发言、夜里的身份行动……）。
/// 能做哪些、参数怎么填由开着的玩法说明。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GameModeAction {
    pub action: String,
    /// 对谁：座号或名字
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub target: Option<String>,
    /// 要说的话
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    /// 为什么这么选：只给旁观的人看
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
}
