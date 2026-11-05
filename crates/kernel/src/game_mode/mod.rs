//! 玩法：有自己的目标、时间表和输赢的一套规则（大逃杀的潮水圈……），一个世界同时最多开一个，随快照保存。
//! 本体只在这几处接玩法，见 `Rules`：推进时间时要停下来结算的时刻和到点结算（simulation.rs）、
//! 身体的额外消耗（physiology）、名册里的状态（projection.rs）、给模型看的一栏（agent 的观察）。
//! 没开玩法时这些都不出现，存档、名册、设定和给模型的观察和没有玩法时一字不差。
//!
//! 加一个玩法：在这个目录写一个文件，实现 `Rules`；再在下面的 `GameMode`、`each!` 和
//! `World::set_game_mode` 里各加一项，协议那边在 protocol 的 game_mode 里加对应的类型。
mod tide;

use crate::actor::Actor;
use crate::error::Result;
use crate::physiology::{Rates, Trace};
use crate::World;
use protocol::{GameModeChoice, GameModeContext, GameModeView};
use serde::{Deserialize, Serialize};

/// 玩法接进本体的几处。玩法自己的状态在实现者里；本体的东西只通过 `world` 读写。
trait Rules {
    /// 存档、设定里认它的名字
    const ID: &'static str;
    /// 离下一个要停下来结算的时刻还有多久（分钟）；没有就是无穷大
    fn boundary(&self, world: &World) -> f64;
    /// 推进到 `world.minutes()` 时结算：发公告、记日志
    fn advance(&mut self, world: &mut World);
    /// 这个人身上额外的消耗；trace 收集给观察仪和模型看的说明
    fn rates(&self, _world: &World, _actor: &Actor, _rates: &mut Rates, _trace: &mut Trace<'_>) {}
    /// 名册里广播的状态
    fn view(&self, world: &World) -> GameModeView;
    /// 给这个人的模型看的一栏；没有可说的时为 None
    fn context(&self, world: &World, actor: &str) -> Option<GameModeContext>;
}

/// 世界里开着的玩法。存档里写成 `{"tide": {...}}`。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum GameMode {
    Tide(tide::Tide),
}

/// 对开着的玩法调同一个 `Rules` 方法。
macro_rules! each {
    ($mode:expr, $m:ident => $body:expr) => {
        match $mode {
            GameMode::Tide($m) => $body,
        }
    };
}

fn id_of<R: Rules>(_: &R) -> &'static str {
    R::ID
}

impl World {
    /// 开着的玩法的名字；没开时为 None。
    pub fn game_mode(&self) -> Option<&'static str> {
        self.game_mode.as_ref().map(|g| each!(g, m => id_of(m)))
    }

    /// 打开或关掉玩法（`None` 是关掉）。已经开着同一个玩法时不重来；换玩法时旧的直接关掉。
    pub fn set_game_mode(&mut self, choice: Option<&GameModeChoice>) -> Result<()> {
        let Some(choice) = choice else {
            self.game_mode = None;
            return Ok(());
        };
        let same = match (choice, &self.game_mode) {
            (GameModeChoice::Tide { .. }, Some(GameMode::Tide(_))) => true,
            (_, None) => false,
        };
        if same {
            return Ok(());
        }
        // 先建好新玩法再换上：打不开时原来的玩法不受影响
        let mode = match choice {
            GameModeChoice::Tide { seed } => {
                GameMode::Tide(tide::Tide::open(self, seed.unwrap_or(1).max(1))?)
            }
        };
        self.game_mode = Some(mode);
        Ok(())
    }

    pub(crate) fn game_mode_boundary(&self) -> f64 {
        self.game_mode
            .as_ref()
            .map_or(f64::INFINITY, |g| each!(g, m => m.boundary(self)))
    }

    /// 结算时先把玩法从世界里拿出来，免得它一边读写世界一边改自己。
    pub(crate) fn advance_game_mode(&mut self) {
        let Some(mut mode) = self.game_mode.take() else {
            return;
        };
        each!(&mut mode, m => m.advance(self));
        self.game_mode = Some(mode);
    }

    pub(crate) fn game_mode_rates(&self, a: &Actor, r: &mut Rates, trace: &mut Trace<'_>) {
        if let Some(g) = &self.game_mode {
            each!(g, m => m.rates(self, a, r, trace));
        }
    }

    pub fn game_mode_view(&self) -> Option<GameModeView> {
        self.game_mode.as_ref().map(|g| each!(g, m => m.view(self)))
    }

    pub fn game_mode_context(&self, actor: &str) -> Option<GameModeContext> {
        self.game_mode
            .as_ref()
            .and_then(|g| each!(g, m => m.context(self, actor)))
    }
}
