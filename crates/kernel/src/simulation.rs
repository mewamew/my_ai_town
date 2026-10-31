//! 模拟时间推进及活动生命周期。世界后果由各领域模块计算，这里只做编排。
use crate::action_check::{check_intent, check_start_conditions};
use crate::action_state::{ActionBinding, QueuedAction};
use crate::error::Result;
use crate::{
    activity::Advance,
    calendar,
    intent::{BuiltinVerb, Intent},
    is_daylight, navigation, physiology,
    world::Activity,
    Event, World,
};
use protocol::ActionStatus;

/// 同一时刻连续结算零时长动作的上限，防止计划互相触发成死循环。
const INSTANT_GUARD: usize = 400;

impl World {
    // ---------- 推进 ----------

    /// 以活动结束、日历和需求阈值切分时间；所有村民共享同一段世界时间。
    pub fn step(&mut self, dt: f64) -> Vec<Event> {
        assert!(dt.is_finite() && dt >= 0.0, "模拟步长须是有限的非负数");
        let until = self.minutes + dt;
        let ids = self.actor_ids();
        self.expire_interactions();
        while self.minutes < until - 1e-9 {
            self.check_ongoing_body_actions();
            self.settle_instant_actions(&ids);
            let t0 = self.minutes;
            let rates = physiology::rates(self);
            let step = (until - t0)
                .min(self.activity_boundary(&ids, t0))
                .min(self.interactions.boundary(t0))
                .min(self.calendar_boundary())
                .min(
                    self.weather
                        .as_ref()
                        .map_or(f64::INFINITY, |w| w.boundary(t0)),
                )
                .min(physiology::next_boundary(&self.actors, &rates))
                .min(self.happenings_boundary());
            let completed = self.advance_activities(&ids, t0, step);
            self.minutes = t0 + step;
            self.advance_needs(step, rates);
            // 到达先更新位置，完成效果与下一项仍留到天气更新之后。
            for id in &completed {
                let a = self.actor_mut(id);
                if let Some(destination) = a.destination() {
                    a.locus = destination;
                }
            }
            self.advance_weather();
            for id in completed {
                // 第一名参与者完成会同时释放双方；第二名不能再结算已释放的空等。
                if self.actors[&id].current.remaining(self.minutes).is_some() {
                    self.complete_current(&id, self.minutes);
                }
            }
            self.fire_happenings();
            self.notice_bodies();
            self.day_boundary(t0, &ids);
            self.expire_interactions();
        }
        std::mem::take(&mut self.events)
    }

    /// 适合快进的空档：在场、活着的村民（化身不算）都在做一件有结束时间的事——睡觉、干活、
    /// 待一会儿——没人在走路、交谈或停下等别人回应。返回离最近一个人做完还有多少分钟；
    /// 有人在走、在交谈时返回 None。空等新计划的人按 `idle_for` 算：Agent 约好过多少分钟再想
    /// （等待工具、推迟），给不出就没有空档。host 只在这种空档里快进，走路和交谈总按正常速度给玩家看。
    pub fn quiet_minutes(&self, idle_for: impl Fn(&str) -> Option<f64>) -> Option<f64> {
        let now = self.minutes;
        let mut left = f64::INFINITY;
        for (id, a) in &self.actors {
            if a.is_avatar() || !a.present() || a.needs.body.dead {
                continue;
            }
            if a.current.is_travel()
                || a.free_walk.is_some()
                || a.possession.is_some()
                || a.current.interaction.is_some()
                || self.held_for_player(id, now)
            {
                return None;
            }
            let ends = if a.current.is_idle() && a.plan.is_empty() {
                idle_for(id)
            } else {
                a.current.remaining(now)
            };
            left = left.min(ends?);
        }
        left.is_finite().then_some(left)
    }

    /// 最近一个活动结束还有多久；停下等回应的人不算。
    fn activity_boundary(&self, ids: &[String], now: f64) -> f64 {
        ids.iter()
            .filter(|id| !self.held_for_player(id, now))
            .filter_map(|id| self.actors[id].current.remaining(now))
            .filter(|m| *m > 1e-9)
            .fold(f64::INFINITY, f64::min)
    }

    /// 玩家来搭话、还没回应：受邀的人手头的事先停着（不取消），回应了或停满 TALK_HOLD_MINUTES
    /// 就照原样接着做。不然模型想几秒的工夫人已走远，接受时已不在交谈距离内。
    /// 村民之间的邀请照旧边做边想。
    fn held_for_player(&self, id: &str, now: f64) -> bool {
        self.interactions.player_talk_offer(&self.actors, id, now)
    }

    /// 把每个人的活动推进 step 分钟；返回本片结束时完成的人。
    fn advance_activities(&mut self, ids: &[String], t0: f64, step: f64) -> Vec<String> {
        let mut completed = Vec::new();
        for id in ids {
            if self.held_for_player(id, t0) {
                continue;
            }
            if let Err(error) = self.advance_free_walk(id, step) {
                self.actor_mut(id).free_walk = None;
                self.fail_current(id, t0, error.to_string());
                continue;
            }
            let a = self.actor_mut(id);
            if let Advance::Done = a.current.advance(&mut a.locus, t0, step) {
                completed.push(id.clone());
            }
        }
        completed
    }

    fn settle_instant_actions(&mut self, ids: &[String]) {
        for id in ids {
            // 停下等回应的人也不接着开始下一项，免得刚好动身离开
            if self.held_for_player(id, self.minutes) {
                continue;
            }
            for guard in 0..=INSTANT_GUARD {
                if self.actors[id]
                    .current
                    .remaining(self.minutes)
                    .is_none_or(|m| m > 1e-9)
                {
                    break;
                }
                if guard == INSTANT_GUARD {
                    self.fail_current(id, self.minutes, "同一时刻的动作推进超限".into());
                    break;
                }
                self.complete_current(id, self.minutes);
            }
        }
    }

    /// 到下一个天亮、天黑或午夜的分钟数。
    fn calendar_boundary(&self) -> f64 {
        let tod = crate::time_of_day(self.minutes);
        [crate::DAWN, crate::DUSK, crate::DAY]
            .into_iter()
            .filter(|at| *at > tod + 1e-9)
            .map(|at| at - tod)
            .fold(crate::DAY - tod, f64::min)
    }

    /// 天亮：把昨天的流水归档进日志，按道具定义补回补给。
    fn day_boundary(&mut self, before: f64, ids: &[String]) {
        if is_daylight(before) || !is_daylight(self.minutes) {
            return;
        }
        let day = calendar::day_index(self.minutes);
        for id in ids {
            self.actor_mut(id).journal.roll_day(day - 1);
        }
        self.restock_supplies();
    }

    /// 活动自然完成：写执行记录、更新位置、从队列取下一项。
    fn complete_current(&mut self, id: &str, now: f64) {
        if let Some(interaction) = self.actors[id].current.interaction.clone() {
            self.complete_interaction(&interaction);
            return;
        }
        if let Some(intent) = self.actor_mut(id).current.pending.take() {
            // 接近段走完：落到操作点，再开始原来的意图。
            self.arrive(id);
            let queued = match self.actor_mut(id).current.action.take() {
                Some(action) => QueuedAction::Tracked {
                    intent,
                    action: Box::new(action),
                },
                None => QueuedAction::Untracked(intent),
            };
            self.start_intent(id, now, queued);
            return;
        }
        match self.settle_completion(id, now) {
            Ok(changes) => {
                self.finish_tracked_action(id, now, ActionStatus::Succeeded, changes, None);
                self.affordances.rebuild_if_dirty(&self.topo);
                self.start_next(id, now);
            }
            Err(reason) => self.fail_current(id, now, reason.to_string()),
        }
    }

    /// 当前动作结算回执；成功完成的阅读记入阅读结果。
    pub(crate) fn finish_tracked_action(
        &mut self,
        id: &str,
        now: f64,
        status: ActionStatus,
        changes: Vec<String>,
        reason: Option<String>,
    ) {
        let reading = self
            .actor_mut(id)
            .finish_tracked_action(now, status, changes, reason);
        if let Some(event_id) = reading {
            self.record_completed_reading(id, event_id);
        }
    }

    /// 行程走完：位置落到目的落脚点。返回目的处所；不是行程则 None。
    fn arrive(&mut self, id: &str) -> Option<String> {
        let a = self.actor_mut(id);
        let destination = a.destination()?;
        a.free_walk = None;
        a.locus = destination;
        Some(a.locus.locale.clone())
    }

    /// 完成的世界后果：背包转移、身体效果、到达或执行记录。返回回执的变化列表。
    fn settle_completion(&mut self, id: &str, now: f64) -> Result<Vec<String>> {
        let binding = self.actors[id].current.action.as_ref();
        let inventory = binding.and_then(|b| {
            b.draft
                .inventory
                .as_ref()
                .map(|op| (op.clone(), b.action_id.clone()))
        });
        let was_goto = binding
            .is_some_and(|b| BuiltinVerb::parse(&b.draft.intent.verb) == Some(BuiltinVerb::Goto));
        if let Some((op, key)) = inventory {
            let changes = self.finish_inventory(id, &op, &key)?;
            for text in &changes {
                self.actor_mut(id).journal.record(now, text.clone());
            }
            return Ok(changes);
        }
        let mut changes = self.finish_body_use(id)?;
        if let Some(dest) = self.arrive(id) {
            let text = crate::outcome::arrived(&self.topo.locale_name(&dest));
            let a = &self.actors[id];
            let info = protocol::EventInfo::movement(id, &a.name);
            let log = format!("{} {text}", a.name);
            self.actor_mut(id).journal.record(now, text.clone());
            self.log(info, log);
            changes.push(text);
        } else if !self.actors[id].current.is_instant() {
            changes.push(self.record_receipt(id, now)?);
        }
        if changes.is_empty() && was_goto {
            changes.push(crate::outcome::stayed(
                &self.topo.locale_name(&self.actors[id].locus.locale),
            ));
        }
        Ok(changes)
    }

    /// 执行记录：世界说清楚发生了什么，措辞在 outcome.rs；阅读回执带正文来源。
    fn record_receipt(&mut self, id: &str, now: f64) -> Result<String> {
        let verb = self.actors[id].current.verb.clone();
        let locale = self.actors[id].locus.locale.clone();
        let receipt = match self.complete_content(id)? {
            Some(receipt) => receipt,
            None => crate::outcome::receipt(self, id, &verb, now),
        };
        let a = self.actor_mut(id);
        match receipt.readable {
            Some(source) => {
                a.journal
                    .record_readable(now, receipt.text.clone(), source, locale);
                let event_id = a.journal.cursor();
                self.record_completed_reading(id, event_id);
            }
            None => a.journal.record(now, receipt.text.clone()),
        }
        Ok(receipt.text)
    }

    /// 物理性失败：写失败通知，当前动作按失败结算。不重试，也不换目标。
    pub(crate) fn fail_current(&mut self, id: &str, now: f64, reason: String) {
        if self.actors[id].current.interaction.is_some() {
            self.interrupt_interaction(id, &reason);
            return;
        }
        let elapsed = (now - self.actors[id].current.started_at).max(0.0);
        let changes = if elapsed > 0.0 {
            vec![crate::outcome::elapsed(elapsed)]
        } else {
            vec![]
        };
        self.finish_tracked_action(id, now, ActionStatus::Failed, changes, Some(reason.clone()));
        let log = self.actor_mut(id).fail_current(now, reason);
        self.log(self.actors[id].event_info(), log);
    }

    /// 从队列取下一项并开始；队列空则进入空等。
    pub(crate) fn start_next(&mut self, id: &str, now: f64) {
        let a = self.actor_mut(id);
        if a.needs.incapacitated() {
            return;
        }
        match a.plan.pop_front() {
            Some(queued) => self.start_intent(id, now, queued),
            None => a.reset_idle(now, false),
        }
    }

    /// 开始队首意图：先查静态条件，需要时先走到操作点，再查使用条件与占用。
    fn start_intent(&mut self, id: &str, now: f64, queued: QueuedAction) {
        if matches!(self.actors[id].locus.at, protocol::At::Free { .. })
            && !self.actors[id].player_controlled()
        {
            let original = queued.clone();
            if let Err(error) = self.start_free_approach(id, now, queued) {
                let (intent, binding) = original.into_parts();
                self.fail_start(id, now, &intent, binding, error.to_string());
            }
            return;
        }
        let (mut intent, binding) = queued.into_parts();
        let locale = self.actors[id].locus.locale.clone();
        let prop = binding.as_ref().and_then(|b| b.draft.prop_id.clone());
        let inventory_label = binding
            .as_ref()
            .and_then(|b| b.draft.inventory.as_ref())
            .map(|op| op.label());
        let spot = match check_intent(
            self,
            id,
            &intent,
            &locale,
            binding.as_ref().map(|b| &b.draft),
        ) {
            Ok(spot) => spot,
            Err(reason) => return self.fail_start(id, now, &intent, binding, reason.to_string()),
        };
        if let Some((locale, station)) =
            navigation::approach_station(self, id, &intent, prop.as_deref())
        {
            if let Intent::Do { station: s, .. } | Intent::Stay { station: s, .. } = &mut intent {
                *s = Some(station.clone());
            }
            if !navigation::at_station(&self.actors[id], &station) {
                return self.approach(id, now, intent, binding, locale, station);
            }
        }
        if let Some(spot) = spot {
            if let Err(reason) = check_start_conditions(self, id, spot) {
                return self.fail_start(id, now, &intent, binding, reason.to_string());
            }
        }
        let nominal_minutes = spot.map(|s| s.minutes);
        let result = self.actors.get_mut(id).expect("村民存在").start_activity(
            &self.topo,
            now,
            intent,
            nominal_minutes,
        );
        let a = self.actor_mut(id);
        a.current.action = binding;
        if let Some(label) = inventory_label {
            a.current.verb = label.into();
        }
        let result = result.and_then(|log| {
            if inventory_label.is_none() {
                self.prepare_content(id)?;
            }
            Ok(log)
        });
        self.settle_start(id, now, result);
    }

    /// 精确导航：先走到道具操作点，原意图挂在 pending 上，到达后再开始。
    fn approach(
        &mut self,
        id: &str,
        now: f64,
        intent: Intent,
        binding: Option<ActionBinding>,
        locale: String,
        station: String,
    ) {
        if let Err(reason) = self.actors[id].needs.check_action(true, None) {
            return self.fail_start(id, now, &intent, binding, reason.to_string());
        }
        let goto = Intent::Goto {
            locale,
            station: Some(station),
        };
        let result = self
            .actors
            .get_mut(id)
            .expect("村民存在")
            .start_activity(&self.topo, now, goto, None);
        let a = self.actor_mut(id);
        a.current.action = binding;
        a.current.pending = Some(intent);
        self.settle_start(id, now, result);
    }

    /// 开始前就不满足条件：换上零时长占位并按失败结算，回执记在原动作上。
    fn fail_start(
        &mut self,
        id: &str,
        now: f64,
        intent: &Intent,
        binding: Option<ActionBinding>,
        reason: String,
    ) {
        let a = self.actor_mut(id);
        a.current = Activity::instant(id, now, a.locus.locale.clone(), intent.verb());
        a.current.action = binding;
        self.fail_current(id, now, reason);
    }

    /// 开始成功时只有出发会写日志（start_activity 返回出发那一行）。
    fn settle_start(&mut self, id: &str, now: f64, result: Result<Option<String>>) {
        match result {
            Ok(Some(log)) => {
                let a = &self.actors[id];
                self.log(protocol::EventInfo::movement(id, &a.name), log)
            }
            Ok(None) => {}
            Err(reason) => self.fail_current(id, now, reason.to_string()),
        }
    }
}
