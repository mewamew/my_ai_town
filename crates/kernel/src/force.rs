//! 对在场的人动手：推搡、抢、偷。都是动作组里带 recipient 的内建动作，抢和偷再用 prop_id 指明对方
//! 身上的那件东西；入队、开始、完成时各查一遍条件，结算在完成那一刻。
//! - 推搡：扣一点健康，打断对方手上的事（睡着的会被推醒）；扣到 0 就是遇害，记下是谁推的。
//! - 抢：对方醒着才抢得了，按双方的精力和健康掷成败；成没成对方都马上知道。
//! - 偷：对方睡着或倒下时才偷得了。睡着的人有一定可能惊醒、当场撞见；没惊醒的，醒来才发现东西不见了。
//!
//! 同一处所醒着、能行动的旁人都看得见，记下所见并收到通知；观察日志各记一笔。
use crate::error::{KernelError, Result};
use crate::intent::BuiltinVerb;
use crate::{avatar::Reach, props::Need, World};
use protocol::{ActionDraft, BodyEventKind, DeathCause, EventActor, Killing};

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Force {
    Push,
    Rob,
    Steal,
}

/// 推搡扣的健康和留下的伤。
const PUSH_HARM: f64 = 5.0;
const PUSH_WOUND: &str = "被推倒在地，擦破了皮";
/// 偷东西时睡着的人惊醒的可能（百分比）。
const STEAL_WAKES: u32 = 20;
/// 抢的成功率范围（百分比）：两人一样强时一半一半。
const ROB_MIN: f64 = 15.0;
const ROB_MAX: f64 = 85.0;

impl Force {
    pub fn label(self) -> &'static str {
        self.verb().label()
    }

    fn verb(self) -> BuiltinVerb {
        match self {
            Self::Push => BuiltinVerb::Push,
            Self::Rob => BuiltinVerb::Rob,
            Self::Steal => BuiltinVerb::Steal,
        }
    }

    /// 内建动词对应的动手方式；不是动手的动词返回 None。
    pub fn from_verb(verb: BuiltinVerb) -> Option<Self> {
        match verb {
            BuiltinVerb::Push => Some(Self::Push),
            BuiltinVerb::Rob => Some(Self::Rob),
            BuiltinVerb::Steal => Some(Self::Steal),
            _ => None,
        }
    }

    pub(crate) fn of(verb: BuiltinVerb) -> Self {
        Self::from_verb(verb).expect("调用方已按动手的动词分支")
    }

    /// 花多少分钟：推一把很快，抢要拉扯一阵，偷要轻手轻脚。
    pub(crate) fn minutes(self) -> f64 {
        match self {
            Self::Push => 1.0,
            Self::Rob => 2.0,
            Self::Steal => 3.0,
        }
    }
}

/// 动作草案是不是动手；是的话返回方式。
pub(crate) fn of_draft(draft: &ActionDraft) -> Option<Force> {
    BuiltinVerb::parse(&draft.intent.verb).and_then(Force::from_verb)
}

impl World {
    /// 动手的条件：对方在眼前、不是自己也不是化身；推搡要对方活着；抢、偷要写明对方身上带着的东西、
    /// 自己背包放得下，抢要对方醒着，偷要对方睡着或倒下。
    pub(crate) fn check_force(&self, actor: &str, draft: &ActionDraft, kind: Force) -> Result<()> {
        let label = kind.label();
        let target = draft
            .recipient
            .as_deref()
            .ok_or_else(|| KernelError::action(format!("{label}要在 recipient 填对方的 ID")))?;
        ensure!(
            target != actor,
            KernelError::action(format!("不能对自己{label}"))
        );
        ensure!(
            draft.writing.is_none() && draft.inventory.is_none(),
            KernelError::action(format!("{label}不带写作和背包参数"))
        );
        let other = self
            .actors
            .get(target)
            .filter(|a| a.present())
            .ok_or_else(|| KernelError::action("对方不在这里"))?;
        ensure!(
            !other.is_avatar(),
            KernelError::action("化身没有身体，动手不起作用")
        );
        Reach::new(self).pair(actor, target)?;
        let name = &other.name;
        if kind == Force::Push {
            ensure!(
                draft.prop_id.is_none(),
                KernelError::action("推搡不用填 prop_id")
            );
            ensure!(
                !other.needs.body.dead,
                KernelError::action(format!("{name}已经死了"))
            );
            return Ok(());
        }
        let item = draft.prop_id.as_deref().ok_or_else(|| {
            KernelError::action(format!("{label}要在 prop_id 填{name}身上那件东西的 ID"))
        })?;
        let awake = self.can_notice(other);
        if kind == Force::Rob {
            ensure!(
                awake,
                KernelError::action(format!("{name}没醒着，抢不了；可以偷"))
            );
        } else {
            ensure!(
                !awake,
                KernelError::action(format!("{name}醒着，偷不了；可以抢"))
            );
        }
        self.inventory
            .check_seize(&self.topo, &self.props, target, actor, item)
    }

    /// 完成时再查一遍条件，然后结算；返回回执里的变化。
    pub(crate) fn finish_force(
        &mut self,
        actor: &str,
        draft: &ActionDraft,
        kind: Force,
    ) -> Result<Vec<String>> {
        self.check_force(actor, draft, kind)?;
        let target = draft.recipient.clone().expect("check_force 查过");
        let changes = match kind {
            Force::Push => self.push(actor, &target),
            Force::Rob => self.rob(actor, &target, draft.prop_id.as_deref().unwrap())?,
            Force::Steal => self.steal(actor, &target, draft.prop_id.as_deref().unwrap())?,
        };
        let now = self.minutes;
        for text in &changes {
            self.actor_mut(actor).journal.record(now, text.clone());
        }
        Ok(changes)
    }

    fn push(&mut self, actor: &str, target: &str) -> Vec<String> {
        let (me, them) = (
            self.actors[actor].name.clone(),
            self.actors[target].name.clone(),
        );
        let mut changes = vec![format!("推了{them}一把")];
        let mut felt = format!("{me}推了你一把");
        if self.actors[target].needs.on(Need::Health) {
            let was = self.actors[target].needs.abilities();
            let lost = self.actor_mut(target).needs.lose_health(PUSH_HARM);
            let hurt = crate::outcome::harmed(&them, PUSH_WOUND, lost);
            felt = format!("{felt}，{PUSH_WOUND}");
            let source = format!("{me}推搡");
            self.body_event(
                target,
                BodyEventKind::Prop,
                &source,
                format!("{source}：{hurt}"),
                None,
            );
            self.reconcile_body(
                target,
                was,
                &source,
                DeathCause {
                    killed: Some(Killing {
                        by: EventActor {
                            id: actor.into(),
                            name: me.clone(),
                        },
                        wound: PUSH_WOUND.into(),
                    }),
                    ..DeathCause::default()
                },
            );
            changes.push(hurt);
            if self.actors[target].needs.body.dead {
                changes.push(crate::outcome::killed(&them));
            }
        }
        self.feel(target, felt, format!("被{me}推了一把"));
        self.happened(actor, target, format!("{me}推了{them}一把"));
        changes
    }

    fn rob(&mut self, actor: &str, target: &str, item: &str) -> Result<Vec<String>> {
        let (me, them) = (
            self.actors[actor].name.clone(),
            self.actors[target].name.clone(),
        );
        let thing = self.props.item(&self.topo, item)?.name.clone();
        let percent = (50.0 + (self.strength(actor) - self.strength(target)) / 2.0)
            .clamp(ROB_MIN, ROB_MAX)
            .round() as u32;
        if self.happenings.roll(percent) {
            self.take_item(target, actor, item);
            self.feel(
                target,
                format!("{me}从你手里抢走了{thing}"),
                format!("{thing}被{me}抢走了"),
            );
            self.happened(actor, target, format!("{me}从{them}手里抢走了{thing}"));
            Ok(vec![format!("从{them}手里抢走了{thing}")])
        } else {
            self.feel(
                target,
                format!("{me}想抢你的{thing}，被你护住了"),
                format!("{me}想抢{thing}"),
            );
            self.happened(actor, target, format!("{me}想抢{them}的{thing}，没抢到"));
            Ok(vec![format!("想抢{them}的{thing}，被{them}护住了，没抢到")])
        }
    }

    fn steal(&mut self, actor: &str, target: &str, item: &str) -> Result<Vec<String>> {
        let (me, them) = (
            self.actors[actor].name.clone(),
            self.actors[target].name.clone(),
        );
        let thing = self.props.item(&self.topo, item)?.name.clone();
        // 睡着的人可能惊醒；倒下、死了的不会
        let n = &self.actors[target].needs;
        let (sleeping, dead) = (!n.incapacitated() && !n.body.dead, n.body.dead);
        if sleeping && self.happenings.roll(STEAL_WAKES) {
            self.feel(
                target,
                format!("你醒过来，看见{me}正伸手拿你身上的{thing}"),
                format!("惊醒了，{me}正在拿{thing}"),
            );
            self.happened(
                actor,
                target,
                format!("{me}偷拿{them}的{thing}时，{them}醒了"),
            );
            return Ok(vec![format!("正要拿{thing}，{them}醒了，没偷成")]);
        }
        self.take_item(target, actor, item);
        if !dead {
            self.actor_mut(target).lost.push(thing.clone());
        }
        let how = if dead {
            format!("从{them}的尸体上")
        } else if sleeping {
            format!("趁{them}睡着，从{them}身上")
        } else {
            format!("趁{them}倒在地上，从{them}身上")
        };
        self.happened(actor, target, format!("{me}{how}拿走了{thing}"));
        Ok(vec![if dead {
            format!("{how}拿走了{thing}")
        } else {
            format!("{how}拿走了{thing}，{them}没察觉")
        }])
    }

    /// 东西从 from 身上到 to 的背包里（check_force 已查过还在、放得下）。
    fn take_item(&mut self, from: &str, to: &str, item: &str) {
        // 对方正拿着它做事（比如正在吃这罐罐头）：那件事做不下去了
        if self.actors[from]
            .current
            .action
            .as_ref()
            .is_some_and(|b| b.draft.prop_id.as_deref() == Some(item))
        {
            self.interrupt_actions(from, "手上的东西没了");
        }
        self.inventory
            .seize(&mut self.topo, &mut self.props, to, item);
        self.refresh_inventory();
    }

    /// 力气：精力和健康的平均（关掉的项按满的算）。
    fn strength(&self, id: &str) -> f64 {
        let n = &self.actors[id].needs;
        let value = |need: Need| {
            if n.on(need) {
                n.track(need).value
            } else {
                100.0
            }
        };
        (value(Need::Energy) + value(Need::Health)) / 2.0
    }

    /// 对方亲身感到的：记一条通知，手上的安排被打断（睡着的会醒）。
    fn feel(&mut self, target: &str, notice: String, reason: String) {
        if self.actors[target].needs.body.dead {
            return;
        }
        self.interrupt_actions(target, &reason);
        let now = self.minutes;
        self.actor_mut(target).notify(now, notice);
    }

    /// 旁人看见的和观察日志：同一处所醒着、能行动的人（不含双方）记下所见并收到通知。
    fn happened(&mut self, actor: &str, target: &str, text: String) {
        let locale = self.actors[actor].locus.locale.clone();
        self.onlookers(&locale, &[actor, target], &format!("看见{text}"), true);
        let info = self.actors[actor].event_info();
        self.log(info, text);
    }

    /// 同一处所醒着、能行动的旁人（不含 skip 里的人）记下亲眼所见；stir 时还收到通知。
    pub(crate) fn onlookers(&mut self, locale: &str, skip: &[&str], text: &str, stir: bool) {
        let now = self.minutes;
        let objects: Vec<String> = skip
            .iter()
            .map(|s| s.to_string())
            .chain([locale.to_string()])
            .collect();
        for id in self.actor_ids() {
            let a = &self.actors[&id];
            if skip.contains(&id.as_str()) || a.locus.locale != locale || !self.can_notice(a) {
                continue;
            }
            let a = self.actor_mut(&id);
            a.journal
                .record_seen(now, text.to_string(), objects.clone());
            if stir {
                a.notify(now, text.to_string());
            }
        }
    }

    /// 睡着时被偷的人醒来（又能留意周围时）发现东西不见了。每拍查一遍。
    pub(crate) fn notice_losses(&mut self) {
        let now = self.minutes;
        for id in self.actor_ids() {
            let a = &self.actors[&id];
            if a.lost.is_empty() || !self.can_notice(a) {
                continue;
            }
            let a = self.actor_mut(&id);
            let lost = std::mem::take(&mut a.lost);
            a.notify(now, format!("醒来发现随身的{}不见了", lost.join("、")));
        }
    }
}
