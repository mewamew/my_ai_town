//! 约定：两人说好什么时候在哪儿见。答应后双方照常活动，不占身体；到点前提醒双方，
//! 在约好的时间前后都到了就算见上，过了宽限还没见上就记爽约，双方都收到通知。
//! 提醒和爽约都在世界推进跨过那个时刻时发一次（时刻是推进的边界，见 Interactions::boundary）。
use super::{Fact, Interactions};
use crate::error::{KernelError, Result};
use crate::World;
use protocol::{FactKind, Interaction, InteractionKind, InteractionStatus as Status};

/// 提前多少分钟提醒。
const REMIND_BEFORE: f64 = 30.0;
/// 约定时刻前多久到了也算见上；过了约定时刻再等多久才算爽约。
const EARLY: f64 = 60.0;
const GRACE: f64 = 30.0;
/// 约定至少要在这么多分钟以后，最多约到一天之内（存档里互动时长不超过一天）。
const MIN_LEAD: f64 = 10.0;

/// 约定的时间和地点规则：只给检查互动内容用。返回存档里的时长（到爽约判定为止）。
pub(crate) fn check_appointment(w: &World, locale: &str, at: f64) -> Result<f64> {
    ensure!(
        w.topo.place_of(locale).is_some(),
        KernelError::interaction(format!("约定地点 {locale} 不是已知地点"))
    );
    let now = w.minutes;
    ensure!(
        at.is_finite() && at >= now + MIN_LEAD && at + GRACE <= now + crate::DAY,
        KernelError::interaction(format!(
            "约定时间要在 {MIN_LEAD:.0} 分钟以后、一天以内，写成 D日数 HH:MM"
        ))
    );
    Ok(at + GRACE - now)
}

/// 约定的说法：「D13 14:00 在小广场见」。
pub(crate) fn describe(w: &World, locale: &str, at: f64) -> String {
    format!(
        "{} 在{}见",
        crate::clock_string(at),
        w.topo.locale_name(locale)
    )
}

impl Interactions {
    /// 进行中的约定（已答应、还没见上也没爽约）。
    fn appointments(&self) -> Vec<(String, String, f64)> {
        self.items
            .values()
            .filter(|i| i.status == Status::Running)
            .filter_map(|i| match &i.kind {
                InteractionKind::Appointment { locale, at } => {
                    Some((i.id.clone(), locale.clone(), *at))
                }
                _ => None,
            })
            .collect()
    }

    /// 下一个提醒或爽约判定还有多久；见没见上要每段推进都看，提醒和判定时刻要正好停下。
    pub(crate) fn appointment_boundary(&self, now: f64) -> f64 {
        self.appointments()
            .into_iter()
            .flat_map(|(_, _, at)| [at - REMIND_BEFORE, at + GRACE])
            .filter(|t| *t > now + 1e-9)
            .map(|t| t - now)
            .fold(f64::INFINITY, f64::min)
    }
}

impl World {
    /// 世界从 t0 推进到现在：跨过提醒时刻就提醒；在约好的时间前后两人都在约好的地方就算见上；
    /// 跨过宽限还没见上就记爽约。
    pub(crate) fn advance_appointments(&mut self, t0: f64) {
        let now = self.minutes;
        for (id, locale, at) in self.interactions.appointments() {
            let item = self.interactions[id.as_str()].clone();
            let remind = at - REMIND_BEFORE;
            if t0 < remind && remind <= now + 1e-9 && item.started_at.is_some_and(|s| s < remind) {
                self.remind(&item, &locale, at);
            }
            let both_there = [&item.initiator, &item.partner].iter().all(|p| {
                self.actors
                    .get(*p)
                    .is_some_and(|a| a.present() && a.locus.locale == locale)
            });
            if both_there && now >= at - EARLY {
                self.interactions
                    .end(&mut self.actors, now, &id, Status::Succeeded, None);
                continue;
            }
            if now + 1e-9 >= at + GRACE {
                let missing: Vec<String> = [&item.initiator, &item.partner]
                    .iter()
                    .filter(|p| self.actors[**p].locus.locale != locale)
                    .map(|p| self.actors[*p].name.clone())
                    .collect();
                let place = self.topo.locale_name(&locale);
                let reason = if missing.len() == 2 {
                    format!("两人都没有按约到{place}")
                } else {
                    format!("{}没有按约到{place}", missing.join("、"))
                };
                self.interactions.end(
                    &mut self.actors,
                    now,
                    &id,
                    Status::Interrupted,
                    Some(reason),
                );
            }
        }
    }

    /// 到点前的提醒：双方各收到一条重要通知，在做的事会被打断，好让人决定要不要动身。
    fn remind(&mut self, item: &Interaction, locale: &str, at: f64) {
        let now = self.minutes;
        let when = describe(self, locale, at);
        for (me, other) in [
            (&item.initiator, &item.partner),
            (&item.partner, &item.initiator),
        ] {
            let name = self.actors[other].name.clone();
            let text = format!("和{name}约好{when}，还有 {REMIND_BEFORE:.0} 分钟");
            self.interactions.link_event(
                &mut self.actors,
                now,
                &item.id,
                me,
                Fact {
                    kind: FactKind::Notice,
                    text,
                    objects: vec![item.id.clone(), other.clone(), locale.into()],
                },
            );
        }
    }
}
