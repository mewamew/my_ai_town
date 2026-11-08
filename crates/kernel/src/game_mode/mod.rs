//! 玩法：有自己的目标、时间表和输赢的一套规则（大逃杀的潮水圈、狼人杀、执剑人之夜……），一个世界同时最多开一个，随快照保存。
//! 本体只在这几处接玩法，见 `Rules`：推进时间时要停下来结算的时刻和到点结算（simulation.rs）、
//! 身体的额外消耗（physiology）、名册里的状态（projection.rs）、给模型看的一栏（agent 的观察）、
//! 模型交选择用的玩法动作（agent 的 mode_action 工具）、世界走几倍速（host 的正常速度）、
//! 人对人动手的经过（force.rs 和拿道具伤人）。
//! 没开玩法时这些都不出现，存档、名册、设定和给模型的观察、工具表和没有玩法时一字不差。
//!
//! 加一个玩法：在这个目录写一个文件，实现 `Rules`；再在下面的 `GameMode`、`each!` 和
//! `World::set_game_mode` 里各加一项，协议那边在 protocol 的 game_mode 里加对应的类型。
mod swordholder;
mod tide;
mod werewolf;

use crate::actor::Actor;
use crate::error::{KernelError, Result};
use crate::physiology::{Rates, Trace};
use crate::World;
use protocol::{GameModeAction, GameModeChoice, GameModeContext, GameModeView};
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
    /// 世界此刻按正常速度的几倍走（1 是不改）：玩法里没什么要等的空档可以走快一点，
    /// 有期限的回合照常速。服务端把它乘在正常速度上；快进照旧按大家在不在忙来定。
    fn tempo(&self, _world: &World) -> f64 {
        1.0
    }
    /// 玩法动作工具（mode_action）给这个人的说明：规则、能做的动作和参数怎么填。
    /// None 是这个玩法不让他交选择，工具表里就没有这一件。
    fn tool(&self, _world: &World, _actor: &str) -> Option<String> {
        None
    }
    /// 这个人交一项玩法动作；返回给模型看的结果，不合规则时说明原因
    fn act(
        &mut self,
        _world: &mut World,
        _actor: &str,
        _action: &GameModeAction,
    ) -> Result<String> {
        Err(KernelError::action("这个玩法没有要交的动作"))
    }
    /// 有人对人动了手（推搡、抢、偷、搜身、拿道具伤人），text 是一句写好的经过，
    /// 比如「骆川用鱼叉刺白鸦，健康 −40」；玩法可以记进自己的战报。
    fn clash(&mut self, _world: &World, _actor: &str, _target: &str, _text: &str) {}
}

/// 世界里开着的玩法。存档里写成 `{"tide": {...}}`。一个世界只有一份，各玩法大小不一不要紧。
#[allow(clippy::large_enum_variant)]
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum GameMode {
    Tide(tide::Tide),
    Werewolf(werewolf::Werewolf),
    Swordholder(swordholder::Swordholder),
}

/// 对开着的玩法调同一个 `Rules` 方法。
macro_rules! each {
    ($mode:expr, $m:ident => $body:expr) => {
        match $mode {
            GameMode::Tide($m) => $body,
            GameMode::Werewolf($m) => $body,
            GameMode::Swordholder($m) => $body,
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
        let same = matches!(
            (choice, &self.game_mode),
            (GameModeChoice::Tide { .. }, Some(GameMode::Tide(_)))
                | (GameModeChoice::Werewolf { .. }, Some(GameMode::Werewolf(_)))
                | (
                    GameModeChoice::Swordholder { .. },
                    Some(GameMode::Swordholder(_))
                )
        );
        if same {
            return Ok(());
        }
        // 先建好新玩法再换上：打不开时原来的玩法不受影响
        let mode = match choice {
            GameModeChoice::Tide { seed } => {
                GameMode::Tide(tide::Tide::open(self, seed.unwrap_or(1).max(1))?)
            }
            GameModeChoice::Werewolf { seed, day_hours } => GameMode::Werewolf(
                werewolf::Werewolf::open(self, seed.unwrap_or(1).max(1), *day_hours)?,
            ),
            GameModeChoice::Swordholder { seed, day_hours } => GameMode::Swordholder(
                swordholder::Swordholder::open(self, seed.unwrap_or(1).max(1), *day_hours)?,
            ),
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

    /// 玩法要的速度倍数；没开玩法时是 1
    pub fn game_mode_tempo(&self) -> f64 {
        self.game_mode
            .as_ref()
            .map_or(1.0, |g| each!(g, m => m.tempo(self)))
            .clamp(0.25, 8.0)
    }

    /// 玩法动作工具给这个人的说明；没开玩法或玩法不让他交选择时为 None
    pub fn game_mode_tool(&self, actor: &str) -> Option<String> {
        self.game_mode
            .as_ref()
            .and_then(|g| each!(g, m => m.tool(self, actor)))
    }

    /// 交一项玩法动作。和结算一样先把玩法拿出来，玩法可以一边读写世界一边改自己。
    pub fn game_mode_act(&mut self, actor: &str, action: &GameModeAction) -> Result<String> {
        let Some(mut mode) = self.game_mode.take() else {
            return Err(KernelError::action("现在没有开着的玩法"));
        };
        let result = each!(&mut mode, m => m.act(self, actor, action));
        self.game_mode = Some(mode);
        result
    }

    /// 有人对人动了手：告诉开着的玩法（见 `Rules::clash`）。
    pub(crate) fn game_mode_clash(&mut self, actor: &str, target: &str, text: &str) {
        let Some(mut mode) = self.game_mode.take() else {
            return;
        };
        each!(&mut mode, m => m.clash(self, actor, target, text));
        self.game_mode = Some(mode);
    }
}
