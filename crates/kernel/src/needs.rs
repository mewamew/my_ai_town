//! 身体数值与观察词表。时间、损害和生命转换在 physiology 模块。
use crate::error::{KernelError, Result};
use crate::props::Need;
use protocol::{
    BodyCondition, Life, NeedBand, NeedRules, NeedState, NeedsTuning, PhysiologySwitches,
};
use std::ops::{Index, IndexMut};

/// 身体数值的范围。
pub const EMPTY: f64 = 0.0;
pub const FULL: f64 = 100.0;
/// 健康不高于此值：危重，失能。
pub const HEALTH_CRITICAL: f64 = 10.0;
/// 健康不高于此值：不能行走。
pub const HEALTH_WEAK: f64 = 20.0;
/// 健康档位：不高于此值为危险，低于 HEALTH_GOOD 为受损。
pub const HEALTH_DANGER: f64 = 30.0;
pub const HEALTH_GOOD: f64 = 70.0;
/// 低值：饱腹、精力、水分不高于此值时不能劳作，也开始累计持续低值（physiology）。
pub const LOW: f64 = 15.0;
/// 回升到此值及以上，持续低值的累计开始消退。
pub const SAFE: f64 = 25.0;
/// 休养恢复健康的最低饱腹与水分、最低精力。
pub const RECOVERY_FED: f64 = 60.0;
pub const RECOVERY_RESTED: f64 = 35.0;
/// 数值会停靠的固定分界：上面每个判断门槛都在这里。推进时在分界处切片，
/// 高倍速下能力变化也不会拖到下一片才判断出来。
pub(crate) const FIXED_THRESHOLDS: [f64; 10] = [
    EMPTY,
    HEALTH_CRITICAL,
    LOW,
    HEALTH_WEAK,
    SAFE,
    HEALTH_DANGER,
    RECOVERY_RESTED,
    RECOVERY_FED,
    HEALTH_GOOD,
    FULL,
];

/// 四项需求各一个值，按需求取值。
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct NeedValues<T> {
    pub fullness: T,
    pub energy: T,
    pub water: T,
    pub health: T,
}
impl<T> Index<Need> for NeedValues<T> {
    type Output = T;
    fn index(&self, need: Need) -> &T {
        match need {
            Need::Fullness => &self.fullness,
            Need::Energy => &self.energy,
            Need::Water => &self.water,
            Need::Health => &self.health,
        }
    }
}
impl<T> IndexMut<Need> for NeedValues<T> {
    fn index_mut(&mut self, need: Need) -> &mut T {
        match need {
            Need::Fullness => &mut self.fullness,
            Need::Energy => &mut self.energy,
            Need::Water => &mut self.water,
            Need::Health => &mut self.health,
        }
    }
}

/// 新人物的起始数值。
const START: NeedValues<f64> = NeedValues {
    fullness: 75.0,
    energy: 90.0,
    water: 85.0,
    health: FULL,
};

pub fn default_tuning() -> NeedsTuning {
    NeedsTuning {
        fullness_decay: 0.05,
        energy_decay: 0.025,
        labor_rate: 0.04,
        voiced: 60.0,
        ring: 35.0,
        ring_reset: 45.0,
        collapse: 15.0,
    }
}
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct NeedTrack {
    pub value: f64,
    pub(crate) rang: bool,
}
impl NeedTrack {
    pub fn new(value: f64) -> Self {
        Self { value, rang: false }
    }
}
/// 没有水分、健康字段的旧存档按起始值读入。
fn initial_water() -> NeedTrack {
    NeedTrack::new(START.water)
}
fn initial_health() -> NeedTrack {
    NeedTrack::new(START.health)
}

/// 身体能力的三个门槛；比较前后差异用。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Abilities {
    pub incapacitated: bool,
    pub can_move: bool,
    pub can_labor: bool,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct Needs {
    pub fullness: NeedTrack,
    pub energy: NeedTrack,
    #[serde(default = "initial_water")]
    pub water: NeedTrack,
    #[serde(default = "initial_health")]
    pub health: NeedTrack,
    pub tuning: NeedsTuning,
    #[serde(default)]
    pub body: protocol::Physiology,
    /// 世界级生理开关的副本；由 World 在加入、恢复和改设置时写入，不单独存档。
    #[serde(skip)]
    pub(crate) switches: PhysiologySwitches,
    /// 旧快照（schema 1）的失能字段；只用来识别迁移，新快照不写入。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) collapsed: Option<serde_json::Value>,
}
impl Needs {
    /// 新人物的身体：起始数值与默认需求参数。
    pub fn initial() -> Self {
        Self {
            fullness: NeedTrack::new(START.fullness),
            energy: NeedTrack::new(START.energy),
            water: initial_water(),
            health: initial_health(),
            body: Default::default(),
            switches: Default::default(),
            collapsed: None,
            tuning: default_tuning(),
        }
    }
    pub fn track(&self, need: Need) -> &NeedTrack {
        match need {
            Need::Fullness => &self.fullness,
            Need::Energy => &self.energy,
            Need::Water => &self.water,
            Need::Health => &self.health,
        }
    }
    pub(crate) fn track_mut(&mut self, need: Need) -> &mut NeedTrack {
        match need {
            Need::Fullness => &mut self.fullness,
            Need::Energy => &mut self.energy,
            Need::Water => &mut self.water,
            Need::Health => &mut self.health,
        }
    }
    /// 该项机制是否开启；关掉的项不参与能力判断、变化率和观察。
    pub(crate) fn on(&self, need: Need) -> bool {
        crate::physiology::enabled(self.switches, need)
    }
    /// 开启的项是否已降到 limit 及以下。
    fn at_most(&self, need: Need, limit: f64) -> bool {
        self.on(need) && self.track(need).value <= limit
    }
    pub fn incapacitated(&self) -> bool {
        self.body.dead
            || self.at_most(Need::Health, HEALTH_CRITICAL)
            || self.at_most(Need::Fullness, EMPTY)
            || self.at_most(Need::Water, EMPTY)
    }
    pub fn can_move(&self) -> bool {
        !self.incapacitated() && !self.at_most(Need::Health, HEALTH_WEAK)
    }
    pub fn can_labor(&self) -> bool {
        self.can_move()
            && [Need::Energy, Need::Fullness, Need::Water]
                .into_iter()
                .all(|need| !self.at_most(need, LOW))
    }
    /// 健康机制关闭时，已有状况保留但不生效，也不对外显示。
    pub fn active_conditions(&self) -> &[BodyCondition] {
        if self.on(Need::Health) {
            &self.body.conditions
        } else {
            &[]
        }
    }
    pub fn abilities(&self) -> Abilities {
        Abilities {
            incapacitated: self.incapacitated(),
            can_move: self.can_move(),
            can_labor: self.can_labor(),
        }
    }
    /// 健康危重：活着但健康不高于危重线（limitation 的第二句）。
    pub(crate) fn critical(&self) -> bool {
        !self.body.dead && self.at_most(Need::Health, HEALTH_CRITICAL)
    }
    pub fn limitation(&self) -> &'static str {
        if self.body.dead {
            "已死亡，只能由明确的复活效果恢复生命"
        } else if self.at_most(Need::Health, HEALTH_CRITICAL) {
            "健康危重，无法自主活动或决策，需要他人救助"
        } else if self.at_most(Need::Fullness, EMPTY) {
            "饱腹耗尽，无法自主活动，需要他人喂食"
        } else if self.at_most(Need::Water, EMPTY) {
            "水分耗尽，无法自主活动，需要他人补水"
        } else if !self.can_move() {
            "身体虚弱，无法行走；可以交谈、求助和使用原地道具"
        } else if !self.can_labor() {
            "身体低值，不能劳作；仍可进食、饮水、休息和求助"
        } else {
            "可正常活动"
        }
    }
    fn band(&self, need: Need, value: f64) -> NeedBand {
        if need != Need::Health {
            return self.tuning.band(value);
        }
        if value <= HEALTH_CRITICAL {
            NeedBand::Collapse
        } else if value <= HEALTH_DANGER {
            NeedBand::Urgent
        } else if value < HEALTH_GOOD {
            NeedBand::Mild
        } else {
            NeedBand::Steady
        }
    }
    fn band_text(&self, need: Need, band: NeedBand) -> &'static str {
        use NeedBand::*;
        match need {
            Need::Fullness => match band {
                Steady => "饮食充足",
                Mild => "有些饿",
                Urgent => "很饿，需要进食",
                Collapse => "严重饥饿，持续低值会损害健康",
            },
            Need::Energy => match band {
                Steady => "精力充足",
                Mild => "有些疲劳",
                Urgent => "很疲劳，需要休息",
                Collapse => "严重疲劳，持续低值会损害健康",
            },
            Need::Water => match band {
                Steady => "水分充足",
                Mild => "口渴",
                Urgent => "很渴，需要饮水",
                Collapse => "严重缺水，持续低值会损害健康",
            },
            Need::Health if self.body.dead => "已死亡",
            Need::Health => match band {
                Steady => "健康良好",
                Mild => "健康受损",
                Urgent => "健康危险",
                Collapse => "健康危重",
            },
        }
    }
    pub fn states(&self) -> Vec<NeedState> {
        Need::ALL
            .into_iter()
            .filter(|need| self.on(*need))
            .map(|need| {
                let value = self.track(need).value;
                let band = self.band(need, value);
                NeedState {
                    kind: need,
                    need: need.label().into(),
                    value: (value * 10.0).round() / 10.0,
                    band,
                    text: self.band_text(need, band).into(),
                }
            })
            .collect()
    }
    pub fn view(&self, causes: Vec<String>) -> protocol::BodyView {
        protocol::BodyView {
            revision: 0,
            life: if self.body.dead {
                Life::Dead
            } else {
                Life::Alive
            },
            conditions: self.active_conditions().to_vec(),
            can_decide: !self.incapacitated(),
            can_move: self.can_move(),
            can_labor: self.can_labor(),
            limitation: self.limitation().into(),
            causes,
            exposure: std::array::from_fn(|i| {
                if self.tracks_exposure(i) {
                    self.body.exposure[i]
                } else {
                    0.0
                }
            }),
            history: self.body.history.clone(),
            wound: self.body.killed.as_ref().map(|k| k.wound.clone()),
        }
    }
    pub fn validate(&self, now: f64, rules: &NeedRules) -> Result<()> {
        ensure!(
            Need::ALL
                .iter()
                .all(|n| (EMPTY..=FULL).contains(&self.track(*n).value)),
            KernelError::snapshot("身体数值须为 0–100 的有限数")
        );
        ensure!(
            self.body.dead == (self.health.value == EMPTY),
            KernelError::snapshot("生命状态与健康值不一致")
        );
        ensure!(
            self.body.killed.as_ref().is_none_or(|k| self.body.dead
                && !k.wound.trim().is_empty()
                && k.wound.chars().count() <= 40),
            KernelError::snapshot("遇害记录只能在死者身上，伤口须为 1–40 字")
        );
        self.tuning.validate(rules).map_err(KernelError::snapshot)?;
        ensure!(
            self.body
                .exposure
                .iter()
                .zip(crate::physiology::GRACE)
                .all(|(v, max)| v.is_finite() && *v >= 0.0 && *v <= max),
            KernelError::snapshot("持续损害进度无效")
        );
        let mut kinds = std::collections::BTreeSet::new();
        for c in &self.body.conditions {
            ensure!(
                kinds.insert(c.kind),
                KernelError::snapshot("同类身体状况重复")
            );
            ensure!(
                c.since.is_finite() && c.since >= 0.0 && c.since <= now,
                KernelError::snapshot("身体状况起始时间无效")
            );
            ensure!(
                (1.0..=3.0).contains(&c.severity),
                KernelError::snapshot("身体状况程度无效")
            );
            ensure!(
                !c.source.is_empty() && c.source.len() <= 1000,
                KernelError::snapshot("身体状况来源无效")
            );
        }
        let mut last = 0.0;
        for e in &self.body.history {
            ensure!(
                e.at.is_finite() && e.at >= last && e.at <= now,
                KernelError::snapshot("生命历史时间无效")
            );
            ensure!(
                !e.source.is_empty() && e.source.len() <= 1000 && e.text.len() <= 4000,
                KernelError::snapshot("生命历史文案无效")
            );
            last = e.at;
        }
        Ok(())
    }
}
