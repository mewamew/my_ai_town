//! 生理计算唯一实现。按阈值与损害进度切片，暂停及离线不推进。
//! 规则都是 `Needs` 的方法或只读检查；改世界的入口在 commands.rs。
mod commands;
use crate::error::{KernelError, Result};
use crate::{
    actor::{Actor, Actors},
    affordance::Spot,
    needs::{
        NeedValues, Needs, EMPTY, FIXED_THRESHOLDS, FULL, LOW, RECOVERY_FED, RECOVERY_RESTED, SAFE,
    },
    props::{Action, Completion, InstantEffect, Need},
    World,
};
use protocol::{BodyCondition, BodyConditionKind as C, NeedsTuning, PhysiologySwitches};
pub const WATER_DECAY: f64 = 0.075;
/// 持续低值多少分钟后开始损害健康；下标与 `EXPOSURE_NEEDS` 同序。
pub const GRACE: [f64; 3] = [120.0, 60.0, 90.0];
pub const DAMAGE: [f64; 3] = [0.08, 0.16, 0.06];
pub const HEAL_RATE: f64 = 0.08;
/// 有持续损害机制的三项需求；顺序就是 exposure 数组的下标。
pub const EXPOSURE_NEEDS: [Need; 3] = [Need::Fullness, Need::Water, Need::Energy];
/// 劳作时水分的额外消耗（每分钟）。
const LABOR_WATER_COST: f64 = 0.04;
/// 淋湿进度的上限：到这里着凉生病，进度清零。
pub const WET_LIMIT: f64 = 90.0;
/// 不淋雨雪时每分钟变干多少。
const DRY_RATE: f64 = 1.0;

/// 世界开关里该项是否开启。
pub(crate) fn enabled(s: PhysiologySwitches, need: Need) -> bool {
    match need {
        Need::Fullness => s.fullness,
        Need::Energy => s.energy,
        Need::Water => s.water,
        Need::Health => s.health,
    }
}

/// 中文并列：「甲、乙和丙」。
fn join_list(parts: &[&str]) -> String {
    match parts.split_last() {
        Some((last, rest)) if !rest.is_empty() => format!("{}和{last}", rest.join("、")),
        _ => parts.concat(),
    }
}

/// 每分钟变化率。文案由 `Needs::causes` 另外生成，推进时不分配字符串。
#[derive(Debug, Clone, Copy, Default)]
pub(crate) struct Rates {
    pub values: NeedValues<f64>,
    /// 下标与 `EXPOSURE_NEEDS` 同序。
    pub exposure: [f64; 3],
    /// 淋湿进度每分钟的变化（天气影响身体开启时）。
    pub wet: f64,
}

/// 速率来源的文案收集器：只有 body_view 需要，推进时传 None。
type Trace<'a> = Option<&'a mut Vec<String>>;

fn note(trace: &mut Trace<'_>, text: impl FnOnce() -> String) {
    if let Some(t) = trace {
        t.push(text());
    }
}

/// 数值会停靠的阈值：needs.rs 的固定分界加需求参数里的四个阈值。
fn thresholds(t: &NeedsTuning) -> [f64; FIXED_THRESHOLDS.len() + 4] {
    let tuned = [t.voiced, t.ring, t.ring_reset, t.collapse];
    std::array::from_fn(|i| match FIXED_THRESHOLDS.get(i) {
        Some(v) => *v,
        None => tuned[i - FIXED_THRESHOLDS.len()],
    })
}

impl Needs {
    fn resting(spot: Option<&Spot>) -> bool {
        spot.is_some_and(|s| {
            s.action
                .as_ref()
                .is_some_and(|a| a.rest || a.completion == Completion::Sleep)
        })
    }

    /// 「前缀 + 开启项并列」的说明；全部关闭时不记。
    fn note_enabled(&self, trace: &mut Trace<'_>, prefix: &str, items: &[(Need, &str)]) {
        let Some(t) = trace else {
            return;
        };
        let parts: Vec<_> = items
            .iter()
            .filter(|(need, _)| self.on(*need))
            .map(|(_, text)| *text)
            .collect();
        if !parts.is_empty() {
            t.push(format!("{prefix}{}", join_list(&parts)));
        }
    }

    /// 第 i 项的持续低值进度只为损害健康而记；该项或健康关闭时冻结。
    pub(crate) fn tracks_exposure(&self, i: usize) -> bool {
        self.on(EXPOSURE_NEEDS[i]) && self.on(Need::Health)
    }

    /// 第 i 项是否处于持续低值：低于 LOW，且精力在休息时不算。
    fn exposed(&self, i: usize, resting: bool) -> bool {
        let need = EXPOSURE_NEEDS[i];
        self.track(need).value <= LOW && !(need == Need::Energy && resting)
    }

    fn rates(&self, spot: Option<&Spot>, mut trace: Trace<'_>) -> Rates {
        if self.body.dead {
            return Rates::default();
        }
        let mut r = Rates {
            values: NeedValues {
                fullness: -self.tuning.fullness_decay,
                energy: -self.tuning.energy_decay,
                water: -WATER_DECAY,
                health: 0.0,
            },
            exposure: [0.0; 3],
            wet: 0.0,
        };
        self.note_enabled(
            &mut trace,
            "时间流逝消耗",
            &[
                (Need::Fullness, "饱腹"),
                (Need::Water, "水分"),
                (Need::Energy, "适用活动下的精力"),
            ],
        );
        let resting = Self::resting(spot);
        if let Some(s) = spot {
            self.activity_rates(s, &mut r, &mut trace);
        }
        self.exposure_rates(resting, &mut r, &mut trace);
        if self.on(Need::Health) {
            self.condition_rates(&mut r, &mut trace);
            if resting && self.can_recuperate(resting) {
                r.values[Need::Health] += HEAL_RATE;
                note(&mut trace, || {
                    "饮食、水分和休息充足，无持续损害：休养恢复健康".into()
                });
            }
        }
        // 关掉的项数值冻结：自然消耗、恢复和状况带来的变化都不生效。
        for need in Need::ALL {
            if !self.on(need) {
                r.values[need] = 0.0;
            }
        }
        r
    }

    fn activity_rates(&self, s: &Spot, r: &mut Rates, trace: &mut Trace<'_>) {
        for (need, rate, pause) in [
            (Need::Fullness, s.fullness_rate, s.pause_fullness_decay),
            (Need::Energy, s.energy_rate, s.pause_energy_decay),
            (Need::Water, s.water_rate, s.pause_water_decay),
            (Need::Health, s.health_rate, false),
        ] {
            if rate > 0.0 {
                r.values[need] = if pause { rate } else { r.values[need] + rate };
                if !self.on(need) {
                    continue;
                }
                note(trace, || {
                    format!("{}：{}每分钟恢复 {rate:.3} 点", s.verb, need.label())
                });
            }
        }
        if s.labor {
            r.values[Need::Energy] -= self.tuning.labor_rate;
            r.values[Need::Water] -= LABOR_WATER_COST;
            self.note_enabled(
                trace,
                "劳作额外消耗",
                &[(Need::Energy, "精力"), (Need::Water, "水分")],
            );
        }
    }

    fn exposure_rates(&self, resting: bool, r: &mut Rates, trace: &mut Trace<'_>) {
        for (i, need) in EXPOSURE_NEEDS.into_iter().enumerate() {
            if !self.tracks_exposure(i) {
                continue;
            }
            let value = self.track(need).value;
            let exposed = self.exposed(i, resting);
            r.exposure[i] = if exposed && self.body.exposure[i] < GRACE[i] {
                1.0
            } else if (value >= SAFE || need == Need::Energy && resting)
                && self.body.exposure[i] > 0.0
            {
                -2.0
            } else {
                0.0
            };
            if exposed && self.body.exposure[i] >= GRACE[i] - 1e-8 {
                r.values[Need::Health] -= DAMAGE[i];
                note(trace, || {
                    format!(
                        "持续{}：健康每分钟损失 {:.3} 点",
                        need.shortage(),
                        DAMAGE[i]
                    )
                });
            }
        }
    }

    fn condition_rates(&self, r: &mut Rates, trace: &mut Trace<'_>) {
        for c in &self.body.conditions {
            let damage = match c.kind {
                C::Injury => 0.03,
                C::Illness => 0.02,
                C::Poison => 0.12,
            } * c.severity;
            r.values[Need::Health] -= damage;
            if c.kind == C::Illness {
                r.values[Need::Energy] -= 0.02 * c.severity;
                r.values[Need::Water] -= 0.02 * c.severity;
            }
            if c.kind == C::Poison {
                r.values[Need::Water] -= 0.03 * c.severity;
            }
            note(trace, || {
                format!(
                    "{}（{}）：健康每分钟损失 {damage:.3} 点",
                    c.kind.label(),
                    c.source
                )
            });
        }
    }

    /// 有直接治疗不掩盖损害；休养资格按是否存在伤害来源判断。
    /// 关掉的项不作为休养条件。
    fn can_recuperate(&self, resting: bool) -> bool {
        let no_damage = self.body.conditions.is_empty()
            && !(0..3).any(|i| {
                self.tracks_exposure(i)
                    && self.body.exposure[i] >= GRACE[i] - 1e-8
                    && self.exposed(i, resting)
            });
        no_damage
            && [
                (Need::Fullness, RECOVERY_FED),
                (Need::Water, RECOVERY_FED),
                (Need::Energy, RECOVERY_RESTED),
            ]
            .into_iter()
            .all(|(need, min)| !self.on(need) || self.track(need).value >= min)
    }

    /// 当前速率的来源说明（观察仪与提示词用）。
    pub(crate) fn causes(&self, spot: Option<&Spot>) -> Vec<String> {
        let mut causes = Vec::new();
        self.rates(spot, Some(&mut causes));
        causes
    }

    /// 正在损害健康的来源，与 causes 里的损害项一致：持续低值已到损害时长的需求，
    /// 以及健康机制开启时的身体状况。死亡提示卡用它写原因。
    pub(crate) fn death_cause(&self, spot: Option<&Spot>) -> protocol::DeathCause {
        let resting = Self::resting(spot);
        protocol::DeathCause {
            shortages: EXPOSURE_NEEDS
                .into_iter()
                .enumerate()
                .filter(|&(i, _)| {
                    self.tracks_exposure(i)
                        && self.exposed(i, resting)
                        && self.body.exposure[i] >= GRACE[i] - 1e-8
                })
                .map(|(_, need)| need)
                .collect(),
            conditions: if self.on(Need::Health) {
                self.body.conditions.iter().map(|c| c.kind).collect()
            } else {
                Vec::new()
            },
            killed: None,
        }
    }

    /// 按速率推进 dt 分钟；返回是否穿越了紧急阈值，以及要发出的通知。
    fn advance(&mut self, r: &Rates, dt: f64) -> (bool, Vec<String>) {
        let targets = thresholds(&self.tuning);
        let (ring, reset, collapse) = (
            self.tuning.ring,
            self.tuning.ring_reset,
            self.tuning.collapse,
        );
        let mut notices = Vec::new();
        let mut urgent = false;
        for need in Need::ALL {
            let track = self.track_mut(need);
            let old = track.value;
            track.value = snapped((old + r.values[need] * dt).clamp(EMPTY, FULL), &targets);
            if track.value >= reset {
                track.rang = false;
            }
            if old > ring && track.value <= ring && !track.rang {
                track.rang = true;
                urgent = true;
                notices.push(format!("{}降低，需要关注身体状态", need.label()));
            }
            // 第一次提醒被放过去（比如夜里又睡回去）时，跌到崩溃线再提醒、再打断一次；
            // 不然一路降到零就失能，家里有水有饭也只能等别人来救
            if need != Need::Health && old > collapse && track.value <= collapse {
                urgent = true;
                notices.push(format!("{}极低，再不补充就撑不住了", need.label()));
            }
        }
        self.body.wet = snapped(
            (self.body.wet + r.wet * dt).clamp(0.0, WET_LIMIT),
            &[0.0, WET_LIMIT],
        );
        for (i, need) in EXPOSURE_NEEDS.into_iter().enumerate() {
            let old = self.body.exposure[i];
            self.body.exposure[i] = snapped(
                (old + r.exposure[i] * dt).clamp(0.0, GRACE[i]),
                &[0.0, GRACE[i]],
            );
            if old < GRACE[i] && self.body.exposure[i] >= GRACE[i] {
                notices.push(format!("持续{}已达到损害时长", need.shortage()));
            }
        }
        (urgent, notices)
    }

    /// 身体能力门控：失能不能开始任何活动；行走要求能走；劳作动作要求能劳作。
    pub(crate) fn check_action(&self, travel: bool, spot: Option<&Spot>) -> Result<()> {
        let allowed = !self.incapacitated()
            && (!travel || self.can_move())
            && (!spot.is_some_and(|s| s.labor) || self.can_labor());
        ensure!(allowed, KernelError::physiology(self.limitation()));
        Ok(())
    }

    /// 直接设值（已经过 `check_values`，测试摆状态用）；不追溯损害。
    pub(crate) fn set_values(&mut self, values: NeedValues<Option<f64>>) -> Result<()> {
        ensure!(
            !self.body.dead,
            KernelError::physiology("死者不能通过修改数值复活，请使用明确复活效果")
        );
        ensure!(
            self.on(Need::Health) || values.health != Some(EMPTY),
            KernelError::physiology("健康机制已关闭，不能把健康设为 0")
        );
        for need in Need::ALL {
            if let Some(v) = values[need] {
                self.track_mut(need).value = v;
            }
        }
        Ok(())
    }

    /// 同类状况程度相加，上限 3；来源取最新（已经过 `check_condition`）。
    pub(crate) fn add_condition(
        &mut self,
        now: f64,
        kind: C,
        severity: f64,
        source: &str,
    ) -> Result<()> {
        ensure!(
            !self.body.dead,
            KernelError::physiology("不能向死者施加生理状况")
        );
        if let Some(c) = self.body.conditions.iter_mut().find(|c| c.kind == kind) {
            c.severity = (c.severity + severity).min(3.0);
            c.source = source.into();
        } else {
            self.body.conditions.push(BodyCondition {
                kind,
                severity,
                since: now,
                source: source.into(),
            });
        }
        Ok(())
    }

    pub(crate) fn cure(&mut self, kind: C) -> Result<()> {
        ensure!(
            !self.body.dead,
            KernelError::physiology("普通治疗不能复活死者")
        );
        self.body.conditions.retain(|c| c.kind != kind);
        Ok(())
    }

    /// 复活（已经过 `check_revival`）：四项回到给定值，损害进度清零。
    pub(crate) fn revive(&mut self, values: [f64; 4], clear_conditions: bool) -> Result<()> {
        ensure!(self.body.dead, KernelError::physiology("接受者尚未死亡"));
        self.body.dead = false;
        for (need, v) in Need::ALL.into_iter().zip(values) {
            let t = self.track_mut(need);
            t.value = v;
            t.rang = false;
        }
        self.body.exposure = [0.0; 3];
        self.body.killed = None;
        if clear_conditions {
            self.body.conditions.clear();
        }
        Ok(())
    }

    /// 受伤：立即扣掉健康，返回实际扣掉的量。死没死由 `settle_death` 结算。
    pub(crate) fn lose_health(&mut self, amount: f64) -> f64 {
        let t = self.track_mut(Need::Health);
        let old = t.value;
        t.value = (old - amount).max(EMPTY);
        old - t.value
    }

    /// 即时恢复一项需求，返回实际恢复量。
    pub(crate) fn restore(&mut self, need: Need, amount: f64) -> f64 {
        let t = self.track_mut(need);
        let old = t.value;
        t.value = (old + amount).min(FULL);
        t.value - old
    }

    /// 健康耗尽即死亡；返回本次是否死亡。
    pub(crate) fn settle_death(&mut self) -> bool {
        let died = self.health.value <= EMPTY && !self.body.dead;
        if died {
            self.health.value = EMPTY;
            self.body.dead = true;
        }
        died
    }
}
/// 直接设值的取值范围。
pub(crate) fn check_values(values: NeedValues<Option<f64>>) -> Result<()> {
    ensure!(
        Need::ALL
            .into_iter()
            .filter_map(|need| values[need])
            .all(|v| (EMPTY..=FULL).contains(&v)),
        KernelError::physiology("身体数值须为 0–100 的有限数")
    );
    Ok(())
}
pub(crate) fn check_condition(severity: f64, source: &str) -> Result<()> {
    ensure!(
        severity.is_finite()
            && (1.0..=3.0).contains(&severity)
            && !source.is_empty()
            && source.len() <= 1000,
        KernelError::physiology("状况程度须为 1–3，来源须有效")
    );
    Ok(())
}
pub(crate) fn check_revival(values: [f64; 4], source: &str) -> Result<()> {
    ensure!(
        !source.is_empty()
            && source.len() <= 1000
            && values.iter().all(|v| (1.0..=FULL).contains(v)),
        KernelError::physiology("复活来源和恢复值无效")
    );
    Ok(())
}
fn boundary(value: f64, rate: f64, targets: &[f64]) -> f64 {
    targets
        .iter()
        .map(|v| (v - value) / rate)
        .filter(|t| t.is_finite() && *t > 1e-8)
        .fold(f64::INFINITY, f64::min)
}
fn snapped(value: f64, targets: &[f64]) -> f64 {
    targets
        .iter()
        .copied()
        .find(|v| (v - value).abs() < 1e-8)
        .unwrap_or(value)
}

/// 当前定时道具动作对应的可供性；背包操作、移动和空等没有。
pub(crate) fn body_spot<'a>(w: &'a World, a: &Actor) -> Option<&'a Spot> {
    if a.current
        .action
        .as_ref()
        .is_some_and(|b| b.draft.inventory.is_some())
        || !matches!(a.current.kind, crate::world::ActKind::Timed { .. })
    {
        return None;
    }
    a.current
        .action
        .as_ref()
        .and_then(|b| b.draft.prop_id.as_deref())
        .or_else(|| w.interactions.prop_of(a))
        .and_then(|p| w.affordances.for_prop(p, &a.current.verb))
        .or_else(|| w.affordances.spot(&a.locus.locale, &a.current.verb))
}

/// 每个人当前的变化率。
/// 化身没有身体状态：不参与需求衰减、损害与死亡结算。
pub(crate) fn rates(w: &World) -> Vec<(String, Rates)> {
    w.actors
        .values()
        .filter(|a| a.present() && !a.is_avatar())
        .map(|a| {
            let mut r = a.needs.rates(body_spot(w, a), None);
            weather_rates(w, a, &mut r, &mut None);
            (a.id.clone(), r)
        })
        .collect()
}

/// 露天时这种天气每分钟额外消耗的精力和淋湿的速度；不下雨雪时为 None。
fn precipitation(kind: protocol::WeatherKind) -> Option<(f64, f64)> {
    use protocol::WeatherKind as K;
    match kind {
        K::Clear | K::Overcast => None,
        K::LightRain => Some((0.01, 0.5)),
        K::Rain | K::Snow => Some((0.02, 0.75)),
        K::HeavyRain => Some((0.04, 1.0)),
        K::Thunderstorm => Some((0.06, 1.5)),
    }
}

/// 天气影响身体：开启时露天淋雨雪额外消耗精力、越来越湿；在室内、遮蔽处或不下雨雪时慢慢变干。
/// 位置未知时不算淋着。
fn weather_rates(w: &World, a: &Actor, r: &mut Rates, trace: &mut Trace<'_>) {
    let n = &a.needs;
    if !w.physiology.weather || n.body.dead {
        return;
    }
    let exposed = w
        .weather
        .as_ref()
        .filter(|_| w.exposure_at(&a.id) == protocol::Exposure::Outdoor)
        .and_then(|weather| precipitation(weather.view.kind).map(|p| (weather.view.kind, p)));
    match exposed {
        Some((kind, (energy, wet))) => {
            if n.on(Need::Energy) {
                r.values[Need::Energy] -= energy;
            }
            if n.on(Need::Health) {
                r.wet = wet;
            }
            note(trace, || {
                let left = ((WET_LIMIT - n.body.wet) / wet).ceil();
                format!(
                    "露天淋{}：精力每分钟额外消耗 {energy:.2} 点；身上越来越湿，再淋约 {left:.0} 分钟会着凉生病",
                    kind.label()
                )
            });
        }
        None if n.body.wet > 0.0 => {
            r.wet = -DRY_RATE;
            note(trace, || {
                format!(
                    "身上还湿着，不淋雨雪时约 {:.0} 分钟变干",
                    n.body.wet / DRY_RATE
                )
            });
        }
        None => {}
    }
}

/// 当前速率的来源说明，加上天气的影响（观察仪与提示词用）。
pub(crate) fn world_causes(w: &World, a: &Actor) -> Vec<String> {
    let mut causes = a.needs.causes(body_spot(w, a));
    let mut r = Rates::default();
    weather_rates(w, a, &mut r, &mut Some(&mut causes));
    causes
}

/// 最近一个数值阈值或损害时长还有多久。
pub(crate) fn next_boundary(actors: &Actors, rates: &[(String, Rates)]) -> f64 {
    let mut next = f64::INFINITY;
    for (id, r) in rates {
        let n = &actors[id].needs;
        let targets = thresholds(&n.tuning);
        for need in Need::ALL {
            next = next.min(boundary(n.track(need).value, r.values[need], &targets));
        }
        for (i, g) in GRACE.into_iter().enumerate() {
            next = next.min(boundary(n.body.exposure[i], r.exposure[i], &[0.0, g]));
        }
        next = next.min(boundary(n.body.wet, r.wet, &[0.0, WET_LIMIT]));
    }
    next
}

/// 施用道具动作的条件：道具在眼前或随身、接受者在场、补给未耗尽、生死状态与效果相符。
pub(crate) fn check_body_use(
    w: &World,
    id: &str,
    locale: &str,
    prop: &str,
    action: &Action,
    recipient: Option<&str>,
) -> Result<()> {
    ensure!(
        recipient.is_none() || action.recipient,
        KernelError::physiology("该动作不支持对他人施用")
    );
    let target = recipient.unwrap_or(id);
    let harms = action.harms();
    ensure!(
        !harms || target != id,
        KernelError::physiology("伤人的动作只能对同一地点的别人用，要填 recipient")
    );
    let a = w
        .actors
        .get(target)
        .ok_or_else(|| KernelError::physiology("接受者不存在"))?;
    ensure!(
        !harms || (!a.is_avatar() && a.needs.on(Need::Health)),
        KernelError::physiology(if a.is_avatar() {
            "化身没有身体，不会受伤"
        } else {
            "这个世界关掉了健康，伤人的动作不起作用"
        })
    );
    let object = w.props.item(&w.topo, prop)?;
    ensure!(
        w.inventory.at_hand(&w.props, id, object, locale) && w.topo.is_dwell(locale),
        KernelError::physiology("须在合法驻留地点使用眼前或本人持有的道具")
    );
    ensure!(
        target == id
            || (a.locus.locale == locale && !matches!(a.locus.at, protocol::At::Transit { .. })),
        KernelError::physiology("接受者须与施用者和道具在同一地点，且不在途中")
    );
    let revive = action
        .on_complete
        .iter()
        .any(|e| matches!(e, InstantEffect::Revive { .. }));
    ensure!(
        !revive || (a.needs.body.dead && target != id),
        KernelError::physiology("复活需要由其他存活村民对死者施用")
    );
    ensure!(
        revive || !a.needs.body.dead,
        KernelError::physiology(if harms {
            "对方已经死了"
        } else {
            "普通进食和治疗不能作用于死者"
        })
    );
    ensure!(
        w.props
            .supply_remaining(prop, action)
            .zip(action.supply.as_ref())
            .is_none_or(|(n, s)| n >= s.cost),
        KernelError::physiology("道具补给已耗尽")
    );
    w.check_requirements(id, action)
}
