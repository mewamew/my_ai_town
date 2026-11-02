//! 化身神力：玩家化身对够得着的人复活、治愈、补满。只在世界打开化身神力时可用，附身村民时不行。
//! 改动走身体自己的入口（复活、解除状况、恢复数值）和同一套结算（reconcile_body），生命事件写明
//! 「某某的神迹」，本人收到通知；同一处所醒着、能行动的人记下亲眼所见。复活像发现尸体那样打断
//! 目击者手上的安排；治愈、补满只记一笔，谁都不打断。
use crate::{
    actor::Actor,
    avatar::{self, Reach},
    error::{KernelError, Result},
    props::Need,
    World,
};
use protocol::{BodyConditionKind, BodyEventKind, DeathCause, GroupStatus, MiracleKind};

/// 复活、治愈、补满后数值回到多少。
const FULL: f64 = 100.0;
/// 补满的三项；健康归治愈管。
const REFILLED: [Need; 3] = [Need::Fullness, Need::Energy, Need::Water];

/// 一次神力要改的东西，施展前按对方当时的身体定下来。
enum Plan {
    Revive,
    Heal(Vec<BodyConditionKind>),
    Refill(Vec<Need>),
}

impl Plan {
    /// 对方现在能不能受这一种神力；不能时写明原因（死者先复活、身体无恙、都是满的）。
    fn of(a: &Actor, kind: MiracleKind) -> Result<Self> {
        let n = &a.needs;
        let name = &a.name;
        if kind == MiracleKind::Revive {
            ensure!(n.body.dead, KernelError::action(format!("{name}还活着")));
            return Ok(Self::Revive);
        }
        ensure!(
            !n.body.dead,
            KernelError::action(format!("{name}已经死了，先复活"))
        );
        let below = |need: Need| n.on(need) && n.track(need).value < FULL;
        if kind == MiracleKind::Heal {
            ensure!(
                n.on(Need::Health),
                KernelError::action("这个世界关掉了健康，没有伤病可治")
            );
            let cured: Vec<_> = n.body.conditions.iter().map(|c| c.kind).collect();
            ensure!(
                !cured.is_empty() || below(Need::Health),
                KernelError::action(format!("{name}身体无恙"))
            );
            return Ok(Self::Heal(cured));
        }
        let needs: Vec<_> = REFILLED.into_iter().filter(|need| below(*need)).collect();
        ensure!(
            !needs.is_empty(),
            KernelError::action(format!("{name}的饱腹、精力、水分都是满的"))
        );
        Ok(Self::Refill(needs))
    }
}

impl World {
    /// 世界是否打开了化身神力。
    pub fn miracles(&self) -> bool {
        self.miracles
    }

    /// 打开或关掉化身神力：只是一个开关，不改任何人的身体，也不打断谁。
    pub fn set_miracles(&mut self, on: bool) {
        self.miracles = on;
    }

    /// 化身对够得着的人施展神力，返回给玩家看的一句结果。施展不占游戏时间。
    pub fn avatar_miracle(
        &mut self,
        revision: u64,
        recipient: &str,
        kind: MiracleKind,
    ) -> Result<String> {
        ensure!(
            self.miracles,
            KernelError::action("这个世界没有打开化身神力")
        );
        ensure!(
            self.possessed().is_none(),
            KernelError::action("附身村民时不能施展神力")
        );
        let me = self
            .avatar()
            .filter(|a| a.present())
            .ok_or_else(|| KernelError::action("化身不在小镇里"))?;
        ensure!(
            me.actions.revision == revision,
            KernelError::action("状态已改变，请再试一次")
        );
        let caster = me.name.clone();
        let target = self
            .actors
            .get(recipient)
            .filter(|a| !a.is_avatar() && a.present())
            .ok_or_else(|| KernelError::action("对方不在小镇里"))?;
        let plan = Plan::of(target, kind)?;
        Reach::new(self).pair(avatar::ID, recipient)?;
        let name = target.name.clone();
        let locale = target.locus.locale.clone();
        let was = target.needs.abilities();
        let source = format!("{caster}的神迹");
        let (seen, told) = match plan {
            // 复活自己记生命事件「由某某的神迹复活」、清掉已见尸体名单、让本人重新观察。
            Plan::Revive => {
                self.revive(recipient, [FULL; 4], true, &source)?;
                (
                    format!("看见{caster}让{name}活了过来"),
                    format!("{name}活了过来：四项回满，伤病已清除"),
                )
            }
            Plan::Heal(cured) => {
                let needs = &mut self.actor_mut(recipient).needs;
                for condition in &cured {
                    needs.cure(*condition)?;
                }
                needs.restore(Need::Health, FULL);
                let what = if cured.is_empty() {
                    "健康回满".to_string()
                } else {
                    let labels: Vec<_> = cured.iter().map(|c| c.label()).collect();
                    format!("解除{}，健康回满", labels.join("、"))
                };
                self.body_event(
                    recipient,
                    BodyEventKind::Miracle,
                    &source,
                    format!("{caster}施展神迹：{what}"),
                    None,
                );
                (
                    format!("看见{caster}治好了{name}"),
                    format!("{name}：{what}"),
                )
            }
            Plan::Refill(refilled) => {
                let needs = &mut self.actor_mut(recipient).needs;
                for need in &refilled {
                    needs.restore(*need, FULL);
                }
                let labels: Vec<_> = refilled.iter().map(|need| need.label()).collect();
                let what = format!("{}回满", labels.join("、"));
                self.body_event(
                    recipient,
                    BodyEventKind::Miracle,
                    &source,
                    format!("{caster}施展神迹：{what}"),
                    None,
                );
                (
                    format!("看见{caster}让{name}一下子恢复了气力"),
                    format!("{name}：{what}"),
                )
            }
        };
        // 能力因此恢复（醒过来、能走、能劳作）时照常结算并记一笔。
        self.reconcile_body(recipient, was, &source, DeathCause::default());
        self.witness(recipient, &locale, &seen, kind == MiracleKind::Revive);
        Ok(told)
    }

    /// 同一处所醒着、能行动的人记下亲眼所见；化身自己和受神力的人不记。
    /// stir 为真（复活）时还发显著通知，并像发现尸体那样打断手上的安排。
    fn witness(&mut self, target: &str, locale: &str, text: &str, stir: bool) {
        let now = self.minutes;
        for id in self.actor_ids() {
            let a = &self.actors[&id];
            if id == target || a.locus.locale != locale || !self.can_notice(a) {
                continue;
            }
            let busy = stir
                && a.actions.agent_controlled
                && !a.player_controlled()
                && (a.current.interaction.is_some()
                    || a.actions
                        .groups
                        .values()
                        .any(|g| g.status == GroupStatus::Running));
            let a = self.actor_mut(&id);
            a.journal.record_seen(
                now,
                text.to_string(),
                vec![avatar::ID.into(), target.into(), locale.into()],
            );
            if stir {
                a.notify(now, text.to_string());
            }
            if busy {
                self.interrupt_actions(&id, "看见有人活了过来，重新考虑当前安排");
            }
        }
    }
}
