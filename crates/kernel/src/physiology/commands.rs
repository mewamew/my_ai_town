//! 生理的世界入口：状况与复活命令，道具效果结算，能力变化后的活动处置，以及测试摆身体状态的直接设值。
use super::{body_spot, check_body_use, check_condition, check_revival, check_values, Rates};
use crate::error::{KernelError, Result};
use crate::{
    needs::{Abilities, NeedValues},
    props::{InstantEffect, Need},
    World,
};
use protocol::{
    Alert, BodyConditionKind as C, BodyEventKind, DeathCause, EventActor, Killing, NeedsTuning,
    PhysiologySwitches,
};

impl World {
    pub fn body_view(&self, id: &str) -> Option<protocol::BodyView> {
        let a = self.actors.get(id)?;
        let mut v = a.needs.view(super::world_causes(self, a));
        v.revision = a.actions.revision;
        Some(v)
    }

    pub fn physiology(&self) -> PhysiologySwitches {
        self.physiology
    }

    /// 改世界级生理开关：不改任何数值；能力因此变化的人照常结算（中断或恢复活动）。
    pub fn set_physiology(&mut self, switches: PhysiologySwitches) {
        if self.physiology == switches {
            return;
        }
        self.physiology = switches;
        for id in self.actor_ids() {
            let was = self.actors[&id].needs.abilities();
            self.actor_mut(&id).needs.switches = switches;
            if !self.actors[&id].is_avatar() {
                self.reconcile_body(&id, was, "世界设定修改", DeathCause::default());
            }
        }
    }

    /// 改需求参数：先按规则校验，再应用；不重置当前值。
    pub fn tune_needs(&mut self, id: &str, tuning: NeedsTuning) -> Result<()> {
        tuning
            .validate(&self.need_rules)
            .map_err(KernelError::physiology)?;
        let a = self
            .actors
            .get_mut(id)
            .ok_or_else(|| KernelError::NoSuchActor(id.into()))?;
        a.needs.tuning = tuning;
        Ok(())
    }

    /// 测试用：只改饱腹和精力，见 `set_body_values`。
    pub fn set_need_values(
        &mut self,
        id: &str,
        fullness: Option<f64>,
        energy: Option<f64>,
    ) -> Result<()> {
        self.set_body_values(id, fullness, energy, None, None)
    }

    /// 时间片推进后的身体结算：紧急提醒、损害通知、能力变化。
    pub(crate) fn advance_needs(&mut self, dt: f64, rates: Vec<(String, Rates)>) {
        for (id, r) in rates {
            if self.actors[&id].needs.body.dead {
                continue;
            }
            let was = self.actors[&id].needs.abilities();
            let (urgent, notices) = self.actor_mut(&id).needs.advance(&r, dt);
            self.body_pressure(&id, urgent, notices);
            if self.actors[&id].needs.body.wet >= super::WET_LIMIT - 1e-8 {
                self.actor_mut(&id).needs.body.wet = 0.0;
                // 健康机制关闭时不会积累淋湿进度，这里一定能施加。
                let _ = self.apply_condition(&id, C::Illness, 1.0, "淋雨受凉");
                self.notify(&id, "淋得太久，着凉生病了".into());
            }
            let n = &self.actors[&id].needs;
            if (n.health.value <= 0.0 && !n.body.dead) || n.abilities() != was {
                let spot = body_spot(self, &self.actors[&id]);
                let source = n.causes(spot).join("；");
                let cause = n.death_cause(spot);
                self.reconcile_body(&id, was, &source, cause);
            }
        }
    }

    /// 需求跨线的结果：紧急时打断 Agent 正在执行的安排或互动，再把提醒记成生命事件。
    fn body_pressure(&mut self, id: &str, urgent: bool, notices: Vec<String>) {
        let a = &self.actors[id];
        if urgent
            && a.actions.agent_controlled
            && (a.current.interaction.is_some()
                || a.actions
                    .groups
                    .values()
                    .any(|g| g.status == protocol::GroupStatus::Running))
        {
            self.interrupt_actions(id, "身体需求紧急，重新考虑当前安排");
        }
        for notice in notices {
            self.body_event(id, BodyEventKind::Pressure, "生理变化", notice, None);
        }
    }

    /// 观察者调身体数值（村民卡片上的「调整」，host 只在世界暂停时放行）。这不是世界里发生的事：
    /// 本人的经历和身体记录里都不留痕，只在观察日志记一笔。跨过提醒线、崩溃线照常提醒和打断，
    /// 能力变化照常结算，和一路饿到这里看不出区别。健康最少留 1，死者要先复活。返回给观察者的一句结果。
    pub fn adjust_body(&mut self, id: &str, values: NeedValues<Option<f64>>) -> Result<String> {
        check_values(values)?;
        ensure!(
            values.health.is_none_or(|h| h >= 1.0),
            KernelError::physiology("健康最少留 1；人死要在世界里发生")
        );
        let a = self
            .actors
            .get(id)
            .ok_or_else(|| KernelError::NoSuchActor(id.into()))?;
        ensure!(!a.is_avatar(), KernelError::physiology("化身的身体不用调"));
        ensure!(
            !a.needs.body.dead,
            KernelError::physiology(format!("{}已经死了，先复活再调", a.name))
        );
        for need in Need::ALL {
            ensure!(
                values[need].is_none() || a.needs.on(need),
                KernelError::physiology(format!("这个世界关掉了{}", need.label()))
            );
        }
        let old = NeedValues {
            fullness: a.needs.fullness.value,
            energy: a.needs.energy.value,
            water: a.needs.water.value,
            health: a.needs.health.value,
        };
        let changes: Vec<String> = Need::ALL
            .into_iter()
            .filter_map(|need| {
                let v = values[need]?;
                Some(format!("{} {:.0} → {v:.0}", need.label(), old[need]))
            })
            .collect();
        ensure!(
            !changes.is_empty(),
            KernelError::physiology("没有要调的数值")
        );
        let name = a.name.clone();
        let was = a.needs.abilities();
        let n = &mut self.actor_mut(id).needs;
        n.set_values(values)?;
        let (urgent, notices) = n.note_adjusted(old);
        self.body_pressure(id, urgent, notices);
        let a = &self.actors[id];
        if a.needs.abilities() != was {
            let spot = body_spot(self, a);
            let source = a.needs.causes(spot).join("；");
            self.reconcile_body(id, was, &source, DeathCause::default());
        }
        let text = format!("观察者调整了{name}的身体：{}", changes.join("，"));
        let info = self.actors[id].event_info();
        self.log(info, text.clone());
        Ok(text)
    }

    /// 生命事件进历史、日记和观察日志；alert 是需要提示卡时的细节。
    pub(crate) fn body_event(
        &mut self,
        id: &str,
        kind: BodyEventKind,
        source: &str,
        text: String,
        alert: Option<Alert>,
    ) {
        self.record_body_event(id, kind, source, text, alert, true);
    }

    fn record_body_event(
        &mut self,
        id: &str,
        kind: BodyEventKind,
        source: &str,
        text: String,
        alert: Option<Alert>,
        fact: bool,
    ) {
        let now = self.minutes;
        let a = self.actor_mut(id);
        let log = a.body_event(now, kind, source, text, alert.clone(), fact);
        let info = a.event_info().with_alert(alert);
        self.log(info, log);
    }

    /// 结算死亡与能力转换：中断不再能做的活动，记生命事件。cause 是随时间推进的损害来源，
    /// 死亡时作为提示卡的细节；能力转换时健康危重也要提示。
    pub(crate) fn reconcile_body(
        &mut self,
        id: &str,
        was: Abilities,
        source: &str,
        cause: DeathCause,
    ) {
        let now_minutes = self.minutes;
        let n = &mut self.actor_mut(id).needs;
        let died = n.settle_death();
        if died {
            n.body.killed = cause.killed.clone();
        }
        let now = n.abilities();
        let reason = n.limitation().to_string();
        if !died && now == was {
            return;
        }
        let text = match &cause.killed {
            _ if !died => reason.clone(),
            Some(k) => format!("遇害身亡，{}。原因：{source}", k.wound),
            None => format!("健康耗尽，死亡。原因：{source}"),
        };
        let alert = if died {
            Some(Alert::Death(cause))
        } else {
            n.critical().then_some(Alert::Critical)
        };
        // 包括恢复能力在内都使旧观察失效，死亡前回复不能在复活后执行。
        self.actor_mut(id).actions.bump_revision();
        let labor_spot = body_spot(self, &self.actors[id]).is_some_and(|s| s.labor);
        if died
            || now.incapacitated
            || (!now.can_move && self.actors[id].current.is_travel())
            || (!now.can_labor && labor_spot)
        {
            self.interrupt_actions(id, &reason);
            let a = self.actor_mut(id);
            a.reset_idle(now_minutes, false);
            if now.incapacitated {
                a.current.verb = if died { "死亡" } else { "无法自主活动" }.into();
            }
        }
        if !now.incapacitated && was.incapacitated {
            self.actor_mut(id).reset_idle(now_minutes, false);
        }
        self.body_event(
            id,
            if died {
                BodyEventKind::Death
            } else {
                BodyEventKind::Ability
            },
            source,
            text,
            alert,
        );
    }

    /// 测试用：直接设身体数值，摆出要验证的状态；None 表示不改。游戏里没有这个入口。
    pub fn set_body_values(
        &mut self,
        id: &str,
        f: Option<f64>,
        e: Option<f64>,
        w: Option<f64>,
        h: Option<f64>,
    ) -> Result<()> {
        let values = NeedValues {
            fullness: f,
            energy: e,
            water: w,
            health: h,
        };
        check_values(values)?;
        let n = &mut self
            .actors
            .get_mut(id)
            .ok_or_else(|| KernelError::NoSuchActor(id.into()))?
            .needs;
        let was = n.abilities();
        n.set_values(values)?;
        self.body_event(
            id,
            BodyEventKind::Experiment,
            "受控实验",
            "受控实验设置身体数值；不追溯计算损害".into(),
            None,
        );
        self.reconcile_body(id, was, "受控实验设置健康", DeathCause::default());
        Ok(())
    }

    pub fn apply_condition(
        &mut self,
        id: &str,
        kind: C,
        severity: f64,
        source: &str,
    ) -> Result<()> {
        check_condition(severity, source)?;
        let now = self.minutes;
        self.actors
            .get_mut(id)
            .ok_or_else(|| KernelError::NoSuchActor(id.into()))?
            .needs
            .add_condition(now, kind, severity, source)?;
        self.body_event(
            id,
            BodyEventKind::Condition,
            source,
            format!("出现{}；重复发生程度相加，上限 3", kind.label()),
            Some(Alert::Condition { condition: kind }),
        );
        Ok(())
    }

    pub fn cure_condition(&mut self, id: &str, kind: C, source: &str) -> Result<()> {
        self.actors
            .get_mut(id)
            .ok_or_else(|| KernelError::NoSuchActor(id.into()))?
            .needs
            .cure(kind)?;
        self.body_event(
            id,
            BodyEventKind::Cure,
            source,
            format!("解除{}，已损失的健康不自动补回", kind.label()),
            None,
        );
        Ok(())
    }

    pub fn revive(
        &mut self,
        id: &str,
        values: [f64; 4],
        clear_conditions: bool,
        source: &str,
    ) -> Result<()> {
        check_revival(values, source)?;
        self.actors
            .get_mut(id)
            .ok_or_else(|| KernelError::NoSuchActor(id.into()))?
            .needs
            .revive(values, clear_conditions)?;
        // 活过来就不再是见过的尸体：以后再死，别人要重新发现。
        for a in self.actors.values_mut() {
            if let Some(seen) = &mut a.bodies_seen {
                seen.remove(id);
            }
        }
        self.interrupt_actions(id, "复活后重新观察");
        let now = self.minutes;
        self.actor_mut(id).reset_idle(now, false);
        self.body_event(
            id,
            BodyEventKind::Revive,
            source,
            format!(
                "由 {source} 复活；{}原身体状况",
                if clear_conditions { "清除" } else { "保留" }
            ),
            None,
        );
        Ok(())
    }

    /// 定时道具动作完成时的结算：先掷定概率效果，再做会失败的产出（建道具、放进背包），
    /// 然后才消耗补给和前提物品、施加身体效果、安排后续，最后通知双方。
    pub(crate) fn finish_body_use(&mut self, id: &str) -> Result<Vec<String>> {
        let Some(spot) = body_spot(self, &self.actors[id]).cloned() else {
            return Ok(vec![]);
        };
        let Some(action) = spot.action.clone() else {
            return Ok(vec![]);
        };
        if action.on_complete.is_empty() && !action.requires.iter().any(|r| r.consume) {
            return Ok(vec![]);
        }
        let a = &self.actors[id];
        let locale = a.locus.locale.clone();
        let recipient = a
            .current
            .action
            .as_ref()
            .and_then(|b| b.draft.recipient.clone());
        // 给自己用时句子里不写自己的名字：这些句子会进本人的经历，第三人称的「林晚使用……
        // 林晚饱腹恢复」会让村民把自己当成另一个人。给别人用时照写，对方要知道是谁。
        let user = match &recipient {
            Some(r) if r != id => a.name.as_str(),
            _ => "",
        };
        let source: String = format!("{user}使用{}／{}", spot.prop_name, action.label)
            .chars()
            .take(240)
            .collect();
        a.needs.check_action(false, Some(&spot))?;
        check_body_use(self, id, &locale, &spot.prop, &action, recipient.as_deref())?;
        let target = recipient.unwrap_or_else(|| id.to_string());
        let was = self.actors[&target].needs.abilities();
        let health_before = self.actors[&target]
            .needs
            .track(crate::props::Need::Health)
            .value;
        let key = format!("{}/{}@{}", spot.prop, action.id, self.minutes.to_bits());
        let (effects, misses) = self.roll_effects(id, &action.on_complete);
        self.check_made_items(id, &effects, &key)?;
        // 以上检查都通过才改世界；产出在消耗之前，放不下道具时什么都没用掉。
        let mut changes = self.make_things(id, &effects, &key)?;
        if let Some(s) = &action.supply {
            let remaining = self.props.consume_supply(&spot.prop, &action, 1);
            changes.push(crate::outcome::supply_used(s.cost, remaining));
        }
        changes.extend(self.use_up_requirements(id, &action));
        changes.extend(self.apply_instant_effects(id, &target, &effects, &source)?);
        changes.extend(misses);
        if action.consumes_item {
            self.consume_carried_prop(&spot.prop);
        }
        // 这次真的伤了人（概率效果已掷定）：死了就是遇害，记下凶手和伤口。
        let killed = effects.iter().find_map(|e| match e {
            InstantEffect::Harm { wound, .. } => Some(Killing {
                by: EventActor {
                    id: id.into(),
                    name: self.actors[id].name.clone(),
                },
                wound: wound.clone(),
            }),
            _ => None,
        });
        let attacked = killed.is_some();
        self.reconcile_body(
            &target,
            was,
            &source,
            DeathCause {
                killed,
                ..DeathCause::default()
            },
        );
        if attacked && self.actors[&target].needs.body.dead {
            changes.push(crate::outcome::killed(&self.actors[&target].name));
        }
        // 拿道具伤了别人：告诉开着的玩法（战报）
        if target != id && action.harms() {
            let (me, them) = (&self.actors[id].name, &self.actors[&target].name);
            let lost = health_before
                - self.actors[&target]
                    .needs
                    .track(crate::props::Need::Health)
                    .value;
            let mut text = format!("{me}{}{them}，健康 −{lost:.0}", action.label);
            if self.actors[&target].needs.body.dead {
                text.push_str(&format!("，{them}倒下了"));
            }
            self.game_mode_clash(id, &target, &text);
        }
        // 自己用道具：这些变化已经写在自己的动作结果里，身体事件只进身体记录和当天流水，
        // 不再给本人另记一条事实，免得一次吃饭在经历里出现好几回。
        let reported = target == id && self.actors[id].current.action.is_some();
        self.record_body_event(
            &target,
            BodyEventKind::Prop,
            &source,
            format!("{source}：{}", changes.join("；")),
            None,
            !reported,
        );
        if target != id {
            let received = if action.harms() { "遭到" } else { "接受" };
            self.notify(
                &target,
                format!("{received}{source}：{}", changes.join("；")),
            );
            let text = format!(
                "对{}施用完成：{}",
                self.actors[&target].name,
                changes.join("；")
            );
            self.notify(id, text);
        }
        Ok(changes)
    }

    /// 身体效果与后续安排；产出物品和建道具已在 `make_things` 里做完。
    /// 作用在使用者自己身上时，句子里不写名字（见 finish_body_use）。
    fn apply_instant_effects(
        &mut self,
        user: &str,
        target: &str,
        effects: &[InstantEffect],
        source: &str,
    ) -> Result<Vec<String>> {
        let name = if target == user {
            String::new()
        } else {
            self.actors[target].name.clone()
        };
        let mut changes = Vec::new();
        for e in effects {
            match e {
                InstantEffect::Restore { need, amount } => {
                    let gained = self.actor_mut(target).needs.restore(*need, *amount);
                    changes.push(crate::outcome::restored(&name, *need, gained));
                }
                // 健康机制关闭时，状况既不新增也不解除。
                InstantEffect::ApplyCondition { .. } | InstantEffect::CureCondition { .. }
                    if !self.actors[target].needs.on(Need::Health) => {}
                InstantEffect::ApplyCondition {
                    condition,
                    severity,
                } => {
                    self.apply_condition(target, *condition, *severity, source)?;
                    changes.push(crate::outcome::condition_applied(condition.label()));
                }
                InstantEffect::CureCondition { condition } => {
                    self.cure_condition(target, *condition, source)?;
                    changes.push(crate::outcome::condition_cured(condition.label()));
                }
                // 只扣健康；死没死、是不是遇害，由 finish_body_use 随后统一结算。
                InstantEffect::Harm { amount, wound } => {
                    let lost = self.actor_mut(target).needs.lose_health(*amount);
                    changes.push(crate::outcome::harmed(&name, wound, lost));
                }
                InstantEffect::Revive {
                    values,
                    clear_conditions,
                } => {
                    self.revive(target, *values, *clear_conditions, source)?;
                    changes.push(crate::outcome::REVIVED.into());
                }
                InstantEffect::Schedule {
                    key,
                    after_minutes,
                    text,
                    place,
                } => changes.push(self.schedule(target, key, *after_minutes, text, place.as_ref())),
                InstantEffect::Depart { text } => {
                    self.depart_later(target, text);
                    changes.push(text.clone());
                }
                // 产出已做完；概率效果已展开。
                InstantEffect::GiveItem { .. }
                | InstantEffect::PlaceProp { .. }
                | InstantEffect::Chance { .. } => {}
            }
        }
        Ok(changes)
    }

    /// 每轮推进前复查进行中的活动：身体能力或道具状态不再满足就物理性失败。
    pub(crate) fn check_ongoing_body_actions(&mut self) {
        for id in self.actor_ids() {
            let a = &self.actors[&id];
            if a.needs.incapacitated() {
                continue;
            }
            let spot = body_spot(self, a);
            let reason = a
                .needs
                .check_action(a.current.is_travel(), spot)
                .err()
                .or_else(|| {
                    let (s, action) = spot.and_then(|s| s.action.as_ref().map(|a| (s, a)))?;
                    let recipient = a
                        .current
                        .action
                        .as_ref()
                        .and_then(|b| b.draft.recipient.as_deref());
                    check_body_use(self, &id, &a.locus.locale, &s.prop, action, recipient).err()
                });
            if let Some(reason) = reason {
                self.fail_current(&id, self.minutes, reason.to_string());
            }
        }
    }
}
