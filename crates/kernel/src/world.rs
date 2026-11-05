//! 世界执行器。只做两件事：按时间推进活动、把事实分发为通知与事件。
//! 不产生任何决策。各子系统持有自己的状态和规则，World 只做编排：
//! 命令入口取出参与者、调子系统方法、记录事实与事件。

use crate::error::Result;
use crate::{
    actor::Actors, affordance::Affordances, clock_string, content::ContentState,
    interactions::Interactions, inventory::Inventory, navigation::space::Placer, props::Props,
    topology::Topology,
};
use protocol::{EventInfo, NeedRules, PhysiologySwitches};

pub use crate::activity::{ActKind, Activity, TravelStage};
pub use crate::actor::Actor;

// ---------- 事件 ----------

#[derive(Debug, Clone)]
pub enum Event {
    /// 观察日志（仪器用）：正文给人读，info 是种类、人物与提示卡细节
    Log {
        minutes: f64,
        text: String,
        info: EventInfo,
    },
}

// ---------- 世界 ----------

pub struct World {
    pub(crate) weather: Option<crate::weather::WeatherState>,
    /// 开着的玩法（game_mode/），随快照保存；没开时为 None。
    pub(crate) game_mode: Option<crate::game_mode::GameMode>,
    /// 加载时注入的二维自由行走几何，不写入世界快照。
    pub walk_map: Option<std::sync::Arc<crate::avatar::WalkMap>>,
    pub topo: Topology,
    /// 可供性索引（由道具表派生，affordance.rs）
    pub affordances: Affordances,
    /// 道具实例的运行期状态：放置、墓碑、补给（props/state.rs）
    pub(crate) props: Props,
    pub(crate) contents: ContentState,
    pub(crate) inventory: Inventory,
    pub(crate) interactions: Interactions,
    pub(crate) actors: Actors,
    pub(crate) minutes: f64,
    pub(crate) events: Vec<Event>,
    /// 需求参数的合法范围；由 host 从 config/needs_rules.json 读入，存档恢复与改参数时校验。
    pub(crate) need_rules: NeedRules,
    /// 世界级生理开关（physiology/commands.rs），随快照保存。
    pub(crate) physiology: PhysiologySwitches,
    /// 化身神力开关（miracle.rs），随快照保存。
    pub(crate) miracles: bool,
    /// 陌生环境：村民只知道到过的地方（exploration.rs），随快照保存。
    pub(crate) strangers: bool,
    /// 藏着的东西（道具编号）：找到过的人才看得见（exploration.rs），随快照保存。
    pub(crate) concealed: std::collections::BTreeSet<String>,
    /// 空间放置器：由 host 注入，内核放置道具时向它要位置与通路。
    pub(crate) placer: Option<Box<dyn Placer>>,
    /// 道具动作引发的后续：定时事件、随机流（happenings.rs），随快照保存。
    pub(crate) happenings: crate::happenings::Happenings,
    /// 同行的足迹与计时（interactions/walk.rs），不存档。
    pub(crate) walk_trails: crate::interactions::WalkTrails,
    /// 每人上次所在的已知地点（sightings.rs），不存档；为空表示还没开始记。
    pub(crate) places_seen: Option<std::collections::BTreeMap<String, Option<String>>>,
}

impl World {
    /// t=0 是第 1 日 00:00；默认从 07:00 开出。
    pub fn new(topo: Topology, start_minutes: f64, need_rules: NeedRules) -> Self {
        World {
            weather: None,
            game_mode: None,
            walk_map: None,
            affordances: Affordances::build(&topo),
            contents: ContentState::from_topology(&topo),
            props: Props::from_topology(&topo),
            topo,
            inventory: Default::default(),
            interactions: Default::default(),
            minutes: start_minutes,
            actors: Actors::new(),
            events: Vec::new(),
            need_rules,
            physiology: Default::default(),
            miracles: false,
            strangers: false,
            concealed: Default::default(),
            placer: None,
            happenings: Default::default(),
            walk_trails: Default::default(),
            places_seen: None,
        }
    }

    /// 有空间地图的世界必须装一个放置器，否则不能放置道具。
    pub fn set_placer(&mut self, placer: Box<dyn Placer>) {
        self.placer = Some(placer);
    }

    pub fn minutes(&self) -> f64 {
        self.minutes
    }
    pub fn clock(&self) -> String {
        clock_string(self.minutes)
    }
    pub fn actor(&self, id: &str) -> Option<&Actor> {
        self.actors.get(id)
    }
    pub fn actor_ids(&self) -> Vec<String> {
        self.actors.keys().cloned().collect()
    }
    /// 有人倒下了但还活着：这时世界不自动快进，给旁人和玩家留出救人的时间。
    pub fn anyone_collapsed(&self) -> bool {
        self.actors
            .values()
            .any(|a| a.present() && a.needs.incapacitated() && !a.needs.body.dead)
    }

    /// 按编号取可变人物。编号来自 actors 表或已校验的命令，不存在即内核不变式被破坏。
    pub(crate) fn actor_mut(&mut self, id: &str) -> &mut Actor {
        self.actors
            .get_mut(id)
            .unwrap_or_else(|| panic!("村民 {id} 不存在"))
    }

    /// 显著通知：进收件箱，也作为世界事件留给 Agent 按游标读取。
    pub(crate) fn notify(&mut self, actor_id: &str, text: String) {
        let now = self.minutes;
        self.actor_mut(actor_id).notify(now, text);
    }

    /// 直接安置在家（出生处所即家）。从入口加入走 population.rs 的 `admit`。
    pub fn spawn(&mut self, id: &str, name: &str, locale: &str) -> Result<()> {
        self.admit(crate::population::Admission {
            id,
            name,
            home: Some(locale),
            entry: None,
        })
    }

    pub(crate) fn log(&mut self, info: EventInfo, text: String) {
        self.events.push(Event::Log {
            minutes: self.minutes,
            text,
            info,
        });
    }
}
