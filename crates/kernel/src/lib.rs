//! 世界内核：空间（Locale/Passage/Locus）、时间（Activity/计划队列）与命令入口。
//!
//! 三条不变式：
//! 1. 任何 Actor 的 current_activity 不可为空 —— 结构上保证：`Actor.current` 不是 Option。
//! 2. 等待和中断的作用域由 Activity 的 participants 决定；共同活动由 interactions 校验参与双方。
//! 3. 已下达意图不含绝对坐标/时刻 —— `protocol::IntentDraft` 使其不可表示，校验兜底。
//!
//! 执行器只做两件事：按时间推进活动、把事实分发为通知。**它不产生任何决策**。
//! 村民 Agent 改变世界只通过 `run_actions` 与 `interact`；玩家化身走 `avatar_*` 命令。
//! `place_prop`、`create_content` 等由 host 的设定命令调用；`set_body_values` 只给测试摆身体状态。
//!
//! 内核不内嵌任何数据文件：道具库、场景包与放置几何都由 host 运行期读入并注入。

/// 校验用：条件不成立就返回给定的 `KernelError`。每个条件一句话，不把多条件串成一句。
macro_rules! ensure {
    ($cond:expr, $err:expr) => {
        if !$cond {
            return Err($err);
        }
    };
}

mod action_check;
mod action_commands;
mod action_results;
mod action_snapshot;
pub mod action_state;
mod activity;
mod actor;
pub mod affordance;
pub mod avatar;
pub mod calendar;
pub mod content;
mod discovery;
pub mod error;
mod execution;
pub mod happenings;
pub mod intent;
pub mod interactions;
pub mod inventory;
pub mod journal;
pub mod navigation;
pub mod needs;
mod outcome;
pub mod path;
pub mod physiology;
pub mod population;
pub mod possession;
mod presence;
mod projection;
pub mod props;
mod simulation;
mod snapshot;
pub mod topology;
pub mod weather;
pub mod world;

pub use error::KernelError;
pub use journal::{Journal, Thought};
pub use needs::default_tuning;
pub use snapshot::{WorldCheckpoint, WorldSnapshot};
pub use topology::Topology;
pub use world::{Event, World};

/// 各类编号（命令、互动、行走空间、天气请求、作者，以及 host 回显的请求编号）的字节上限。
pub const ID_MAX_BYTES: usize = 160;

/// 一天的分钟数；天亮 06:00，天黑 19:00。
pub const DAY: f64 = 1440.0;
pub const DAWN: f64 = 360.0;
pub const DUSK: f64 = 1140.0;

pub fn time_of_day(minutes: f64) -> f64 {
    minutes.rem_euclid(DAY)
}

pub fn is_daylight(minutes: f64) -> bool {
    let t = time_of_day(minutes);
    (DAWN..DUSK).contains(&t)
}

pub fn clock_string(minutes: f64) -> String {
    let day = (minutes / DAY).floor() as i64 + 1;
    let t = time_of_day(minutes) as i64;
    format!("D{} {:02}:{:02}", day, t / 60, t % 60)
}
