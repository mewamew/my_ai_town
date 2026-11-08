//! 互动的世界入口：邀请、回应、取消与聊天命令；同意交谈后才中断双方的普通活动。
//! 只读检查用 `Interactions` 的规则方法，改动只发生在检查全部通过之后。
use super::{check_message, check_pair_here, Interactions, LeaveKind, GIVE_MINUTES, TALK_MINUTES};
use crate::error::{KernelError, Result};
use crate::{
    action_check::check_conditions,
    activity::{ActKind, Activity},
    intent::StopCond,
    physiology::check_body_use,
    World, ID_MAX_BYTES,
};
use protocol::{Interaction, InteractionCommand, InteractionKind, InteractionStatus as Status};

impl World {
    pub fn talk_available(&self, actor: &str) -> bool {
        self.actors.get(actor).is_some_and(|a| a.talk_available())
            && self.interactions.walk_of(actor).is_none()
            && self.check_weather_chat(actor).is_ok()
    }

    /// 同行路上不另起互动：带路人和玩家操控的同行者虽然不占活动，也算在一场互动里。
    /// 只有带路人再邀人同行（多人同行）例外，同行规则在 check_walk 里另查。
    fn check_not_walking(&self, ids: [&str; 2], kind: &InteractionKind) -> Result<()> {
        let leader = kind.walk_leader();
        ensure!(
            ids.iter().all(|id| {
                self.interactions.walk_of(id).is_none()
                    || (leader == Some(*id) && self.interactions.leads_walk(id))
            }),
            KernelError::interaction("正在同行，先到地方或结束同行")
        );
        Ok(())
    }

    /// 玩家（化身或附身的人）和村民搭话、送东西：在哪儿进行。只看距离和遮挡，不要求同一处所，
    /// 地点定在村民所在的处所；交谈连路上也行，送东西要那里是驻留地。不是玩家和村民之间的、
    /// 或招待用餐这类要用道具的互动为空，按原规则两人在同一驻留处所。
    pub(crate) fn player_pair_place(
        &self,
        a: &str,
        b: &str,
        kind: &InteractionKind,
    ) -> Option<String> {
        let (x, y) = (self.actors.get(a)?, self.actors.get(b)?);
        let resident = match (x.player_controlled(), y.player_controlled()) {
            (true, false) => y,
            (false, true) => x,
            _ => return None,
        };
        let place = &resident.locus.locale;
        match kind {
            InteractionKind::Talk | InteractionKind::Walk { .. } => Some(place.clone()),
            InteractionKind::Give { .. } | InteractionKind::Touch { .. }
                if self.topo.is_dwell(place) =>
            {
                Some(place.clone())
            }
            _ => None,
        }
    }

    /// 玩家操控的人往前挪一小步，站进处所 place（朝着 toward 这个人）：隔着处所分界说上话后，
    /// 两人要在同一处所进行互动（读档也这样校验）。本来就在那里时不动。
    fn step_player_into(&mut self, player: &str, place: &str, toward: &str) -> Result<()> {
        if self.actors[player].locus.locale == place {
            return Ok(());
        }
        let map = self
            .walk_map
            .clone()
            .ok_or_else(|| KernelError::navigation("缺少行走地图"))?;
        let reach = crate::avatar::Reach::new(self);
        let from = reach
            .talk_spot(player)
            .ok_or_else(|| KernelError::navigation("化身不在场"))?;
        let toward = reach
            .talk_spot(toward)
            .map_or(from.position, |s| s.position);
        let spot = map
            .step_into(place, &from, toward, &self.avatar_obstacles())
            .ok_or_else(|| KernelError::interaction("请再走近对方一点"))?;
        let a = self.actor_mut(player);
        a.locus = spot.locus();
        a.current.locale = place.into();
        Ok(())
    }

    /// 玩家参与的双方互动开始前（见 player_pair_place）：互动记在村民那边，玩家操控的人挪进去。
    fn settle_pair_place(&mut self, id: &str, place: &str) -> Result<()> {
        let item = &self.interactions[id];
        let (a, b) = (item.initiator.clone(), item.partner.clone());
        let (player, resident) = if self.actors[&a].player_controlled() {
            (a, b)
        } else {
            (b, a)
        };
        self.step_player_into(&player, place, &resident)?;
        self.interactions.get_mut(id).locale = place.into();
        Ok(())
    }

    pub fn prop_occupants(&self, prop: &str) -> Vec<String> {
        self.interactions
            .prop_occupants(&self.actors, self.minutes, prop)
    }

    pub fn active_chat(&self, actor: &str) -> Option<&Interaction> {
        self.interactions.active_chat(self.actors.get(actor)?)
    }

    pub fn chat_turn(&self, actor: &str) -> bool {
        self.actors
            .get(actor)
            .is_some_and(|a| self.interactions.chat_turn(a, self.minutes))
    }

    pub fn nearby_chats(&self, actor: &str) -> Vec<protocol::NearbyChat> {
        self.actors
            .get(actor)
            .map(|a| self.interactions.nearby_chats(&self.actors, a))
            .unwrap_or_default()
    }

    pub fn chat_history(
        &self,
        resident: &str,
        request_id: String,
        chat_id: Option<String>,
        offset: usize,
    ) -> protocol::ServerMsg {
        self.interactions
            .chat_history(&self.actors, resident, request_id, chat_id, offset)
    }

    pub fn interact(
        &mut self,
        actor: &str,
        command_id: &str,
        revision: u64,
        command: &InteractionCommand,
    ) -> Result<Interaction> {
        self.interact_from(actor, command_id, revision, command, false)
    }

    pub(crate) fn interact_from(
        &mut self,
        actor: &str,
        command_id: &str,
        revision: u64,
        command: &InteractionCommand,
        player: bool,
    ) -> Result<Interaction> {
        let a = self
            .actors
            .get(actor)
            .ok_or_else(|| KernelError::NoSuchActor(actor.into()))?;
        ensure!(
            a.player_controlled() == player
                && a.controllable()
                && a.actions.revision == revision
                && !a.needs.incapacitated(),
            KernelError::interaction("安排或身体状态已改变，请重新观察")
        );
        if matches!(
            command,
            InteractionCommand::Join { .. } | InteractionCommand::Say { .. }
        ) {
            self.check_weather_chat(actor)?;
        }
        if let InteractionCommand::Join { interaction_id, .. } = command {
            if let Some(i) = self
                .interactions
                .get(interaction_id)
                .filter(|i| i.status == Status::Running && i.kind.walk_leader().is_none())
            {
                let (place, members) =
                    (i.locale.clone(), i.chat.as_ref().map(|c| c.members.clone()));
                let members = members.unwrap_or_default();
                let reach = crate::avatar::Reach::new(self);
                for member in &members {
                    reach.pair(actor, member)?;
                }
                // 玩家走到聊天的人身边就能加入：隔着处所分界时往前挪一步，站进聊天所在的处所
                if player && !members.contains(actor) {
                    if let Some(member) = members.iter().next() {
                        self.step_player_into(actor, &place, member)?;
                    }
                }
            }
        }
        let now = self.minutes;
        if let InteractionCommand::Join {
            interaction_id,
            message,
        } = command
        {
            if self
                .interactions
                .get(interaction_id)
                .is_some_and(|i| i.kind.walk_leader().is_some())
            {
                return self.join_walk(actor, interaction_id, message);
            }
        }
        let result = match command {
            InteractionCommand::Offer {
                partner_id,
                interaction,
                message,
            } => self.offer(actor, command_id, partner_id, interaction, message),
            InteractionCommand::Reply {
                interaction_id,
                accept,
                message,
            } => self.reply(actor, interaction_id, *accept, message),
            InteractionCommand::Cancel { interaction_id } => self.cancel(actor, interaction_id),
            InteractionCommand::Propose {
                interaction_id,
                interaction,
                message,
                to,
            } => self.propose(actor, interaction_id, interaction, message, to.as_deref()),
            InteractionCommand::Accept {
                interaction_id,
                message,
                locale,
            } => self.accept_proposal(actor, interaction_id, message, locale.as_deref()),
            InteractionCommand::Decline {
                interaction_id,
                message,
            } => self.decline_proposal(actor, interaction_id, message),
            InteractionCommand::Join { .. }
            | InteractionCommand::Say { .. }
            | InteractionCommand::Listen { .. }
            | InteractionCommand::Leave { .. } => {
                self.interactions
                    .chat_command(&mut self.actors, now, actor, command)
            }
        };
        // 嘴上说把身上的东西给对方：东西还在他身上，两边各提醒一句（pledge.rs）
        if let Some((text, listener)) = result
            .as_ref()
            .ok()
            .and_then(|item| super::pledge::spoken(actor, command, item))
        {
            self.note_pledge(actor, &listener, text);
        }
        result
    }

    fn offer(
        &mut self,
        actor: &str,
        command_id: &str,
        partner: &str,
        kind: &InteractionKind,
        message: &str,
    ) -> Result<Interaction> {
        check_message(message)?;
        ensure!(
            !command_id.is_empty() && command_id.len() <= ID_MAX_BYTES,
            KernelError::interaction("互动编号无效")
        );
        let kind = normalize_kind(&self.topo, kind);
        if let Some(old) = self
            .interactions
            .resent_offer(command_id, actor, partner, &kind, message)?
        {
            return Ok(old);
        }
        ensure!(
            self.actors[actor].interaction_available(),
            KernelError::interaction("请先完成当前活动，再发起邀请")
        );
        self.check_not_walking([actor, partner], &kind)?;
        check_pair_here(self, actor, partner, &kind)?;
        self.interactions.check_new_offer(actor, partner, &kind)?;
        let duration_minutes = check_kind(self, actor, partner, &kind)?;
        let place = self.player_pair_place(actor, partner, &kind);
        let mut item = Interactions::new_offer(
            command_id,
            &self.actors[actor],
            partner,
            kind,
            message,
            duration_minutes,
            self.minutes,
        );
        // 玩家和村民之间的：记在村民所在的处所（接受时再按那时的位置定一次）
        if let Some(place) = place {
            item.locale = place;
        }
        // 约定的邀请最晚在约定时刻前要回答
        if let InteractionKind::Appointment { at, .. } = &item.kind {
            item.expires_at = item.expires_at.min(*at);
        }
        let now = self.minutes;
        self.interactions
            .record_offer(&mut self.actors, now, &item, message);
        Ok(item)
    }

    fn reply(
        &mut self,
        actor: &str,
        interaction_id: &str,
        accept: bool,
        message: &str,
    ) -> Result<Interaction> {
        check_message(message)?;
        let old = self
            .interactions
            .of(actor, interaction_id)
            .ok_or_else(|| KernelError::interaction("没有收到这项邀请"))?
            .clone();
        ensure!(
            old.partner == actor,
            KernelError::interaction("只有受邀者可以回应，不能代替对方同意")
        );
        if old.accepted.is_some() {
            ensure!(
                old.accepted == Some(accept) && old.reply.as_deref() == Some(message),
                KernelError::interaction("这项邀请已经回应，不能改写原回应")
            );
            return Ok(old);
        }
        ensure!(
            old.status == Status::Offered && self.minutes < old.expires_at,
            KernelError::interaction("邀请已结束或过期")
        );
        if accept {
            self.check_accept(actor, &old)?;
            if let Some(place) = self.player_pair_place(&old.initiator, actor, &old.kind) {
                self.settle_pair_place(interaction_id, &place)?;
            }
        }
        let now = self.minutes;
        // 所有距离、身体与同意校验通过后才中断，不把未完成的工作算作完成。
        if accept && old.kind.has_chat() {
            for id in [&old.initiator, &old.partner] {
                self.actor_mut(id)
                    .interrupt_actions(now, "接受交谈，结束原活动安排");
            }
        }
        let item = self
            .interactions
            .record_reply(interaction_id, accept, message, now);
        self.interactions
            .speech(&mut self.actors, now, &item, actor, message);
        if accept {
            self.start_pair_activity(&item);
        } else {
            let reason = match item.kind {
                InteractionKind::Touch { .. } => "对方躲开了",
                _ => "受邀者拒绝了邀请",
            };
            self.interactions.end(
                &mut self.actors,
                now,
                interaction_id,
                Status::Declined,
                Some(reason.into()),
            );
        }
        if let InteractionKind::Touch { gesture } = item.kind {
            self.witness_touch(&item, gesture, accept);
        }
        Ok(self.interactions[interaction_id].clone())
    }

    /// 亲近的那一下：双方各记一笔看得见的经过，同一处所醒着的旁人也看见，观察日志记一笔。
    fn witness_touch(&mut self, item: &Interaction, gesture: protocol::Gesture, accepted: bool) {
        let (a, b) = (&item.initiator, &item.partner);
        let scene = super::touch_scene(
            gesture,
            &self.actors[a].name,
            &self.actors[b].name,
            accepted,
        );
        let now = self.minutes;
        for id in [a, b] {
            self.actor_mut(id)
                .journal
                .record_seen(now, scene.clone(), vec![item.id.clone()]);
        }
        let locale = item.locale.clone();
        self.onlookers(&locale, &[a, b], &format!("看见{scene}"), false);
        let info = self.actors[a].event_info();
        self.log(info, scene);
    }

    /// 接受邀请前再查一遍：双方仍在邀请地点（玩家参与的只看还够不够得着）、能够回应，
    /// 互动内容本身仍然可行。
    fn check_accept(&self, actor: &str, old: &Interaction) -> Result<()> {
        self.check_not_walking([actor, &old.initiator], &old.kind)?;
        check_pair_here(self, &old.initiator, actor, &old.kind)?;
        ensure!(
            self.player_pair_place(&old.initiator, actor, &old.kind)
                .is_some()
                || self.actors[actor].locus.locale == old.locale,
            KernelError::interaction("双方已离开邀请地点，请重新发起")
        );
        if old.kind.has_chat() {
            ensure!(
                self.talk_available(actor) && self.talk_available(&old.initiator),
                KernelError::interaction("双方须能够回应，并先结束已有的共同互动")
            );
        } else if !matches!(old.kind, InteractionKind::Appointment { .. }) {
            // 约定答应了照常活动，不要求空闲
            ensure!(
                self.actors[actor].interaction_available()
                    && self.actors[&old.initiator].interaction_available(),
                KernelError::interaction("双方须先结束当前活动，才能共同开始")
            );
        }
        check_kind(self, &old.initiator, actor, &old.kind)?;
        Ok(())
    }

    /// 双方同意后安装同一参与者集合的身体活动；交谈另有轮次机制，同行由世界带着跟随的人走。
    fn start_pair_activity(&mut self, item: &Interaction) {
        let now = self.minutes;
        if let Some(leader) = item.kind.walk_leader() {
            // 带路人正在带别人：跟上那一场
            if let Some(walk) = self.interactions.walk_led_by(leader).map(|w| w.id.clone()) {
                return self.merge_walk_offer(&item.id, &walk);
            }
            self.interactions
                .start_chat(&mut self.actors, now, &item.id);
            self.begin_walk(&item.id);
            return;
        }
        if let InteractionKind::Appointment { locale, at } = &item.kind {
            // 约定不占身体：只记下说好了，到点由世界提醒
            let text = format!(
                "约好了：{}",
                super::appointments::describe(self, locale, *at)
            );
            self.interactions.fact(&mut self.actors, now, item, &text);
            return;
        }
        for id in [&item.initiator, &item.partner] {
            let verb = match &item.kind {
                InteractionKind::Serve { verb, .. } if id == &item.partner => verb.as_str(),
                _ => item.kind.label(),
            };
            let a = self.actor_mut(id);
            // 对方在途请求同样作废，不能覆盖双方刚同意的活动。
            a.actions.bump_revision();
            a.current = Activity::new(
                id,
                now,
                item.locale.clone(),
                verb,
                ActKind::Timed {
                    cond: StopCond::Duration(item.duration_minutes),
                },
            );
            a.current.participants = [item.initiator.clone(), item.partner.clone()].into();
            a.current.interaction = Some(item.id.clone());
        }
        if item.chat.is_some() {
            self.interactions
                .start_chat(&mut self.actors, now, &item.id);
        } else {
            self.interactions.fact(
                &mut self.actors,
                now,
                item,
                &format!("双方已同意，开始{}；尚未完成", item.kind.label()),
            );
        }
    }

    fn cancel(&mut self, actor: &str, interaction_id: &str) -> Result<Interaction> {
        let now = self.minutes;
        let item = self
            .interactions
            .of(actor, interaction_id)
            .ok_or_else(|| KernelError::interaction("互动不存在或不属于自己"))?;
        if item.status == Status::Running && item.chat.is_some() {
            let why = if item.kind.walk_leader().is_some() {
                "不走了"
            } else {
                "取消交谈"
            };
            self.interactions.leave_chat(
                &mut self.actors,
                now,
                actor,
                interaction_id,
                LeaveKind::Voluntary,
                why,
            )?;
        } else if !item.status.terminal() {
            self.interactions.end(
                &mut self.actors,
                now,
                interaction_id,
                Status::Cancelled,
                Some("参与者取消互动".into()),
            );
        }
        Ok(self.interactions[interaction_id].clone())
    }

    pub(crate) fn expire_interactions(&mut self) {
        let now = self.minutes;
        self.interactions.expire(&mut self.actors, now);
    }

    pub(crate) fn interrupt_interaction(&mut self, actor: &str, reason: &str) {
        let now = self.minutes;
        if let Some(log) = self
            .interactions
            .interrupt(&mut self.actors, now, actor, reason)
        {
            self.log(self.actors[actor].event_info(), log);
        }
    }

    /// 双人活动到时：赠品转移或餐饮结算，成功即完成，失败按中断结束。
    pub(crate) fn complete_interaction(&mut self, id: &str) {
        if self.interactions[id].status != Status::Running {
            return;
        }
        let now = self.minutes;
        let partner = self.interactions[id].partner.clone();
        if let InteractionKind::Give { items } = self.interactions[id].kind.clone() {
            let from = self.interactions[id].initiator.clone();
            if let Err(reason) = self.finish_gift(&from, &partner, &items) {
                self.interactions.end(
                    &mut self.actors,
                    now,
                    id,
                    Status::Interrupted,
                    Some(reason.to_string()),
                );
                return;
            }
            let names = items
                .iter()
                .map(|id| self.props.item(&self.topo, id).map(|p| p.name.clone()))
                .collect::<Result<Vec<_>, _>>()
                .unwrap_or_default();
            self.interactions
                .items
                .get_mut(id)
                .expect("互动存在")
                .changes
                .push(format!("赠品已转移：{}", names.join("、")));
        }
        if matches!(self.interactions[id].kind, InteractionKind::Serve { .. }) {
            match self.finish_body_use(&partner) {
                Ok(changes) => self
                    .interactions
                    .items
                    .get_mut(id)
                    .expect("互动存在")
                    .changes
                    .extend(changes),
                Err(reason) => {
                    self.interactions.end(
                        &mut self.actors,
                        now,
                        id,
                        Status::Interrupted,
                        Some(reason.to_string()),
                    );
                    return;
                }
            }
            self.affordances.rebuild_if_dirty(&self.topo);
        }
        self.interactions
            .end(&mut self.actors, now, id, Status::Succeeded, None);
    }
}

/// 校验互动内容，返回活动时长。天气、背包、可供性与身体都要查，所以放在世界这一层。
fn check_kind(w: &World, actor: &str, partner: &str, kind: &InteractionKind) -> Result<f64> {
    let locale = &w.actors[actor].locus.locale;
    match kind {
        InteractionKind::Walk { leader, locale } => {
            // 陌生环境里带路的人得认得要去的地方
            if let Some(place) = locale.as_deref() {
                let guide = if leader == "self" || leader == actor {
                    actor
                } else {
                    leader.as_str()
                };
                ensure!(w.knows_way(guide, place), World::unknown_way());
            }
            super::walk::check_walk(w, actor, partner, leader, locale.as_deref())
        }
        InteractionKind::Appointment { locale, at } => {
            ensure!(w.remembers(actor, locale), World::unknown_way());
            super::appointments::check_appointment(w, locale, *at)
        }
        InteractionKind::Talk => {
            w.check_weather_chat(actor)?;
            w.check_weather_chat(partner)?;
            Ok(TALK_MINUTES)
        }
        InteractionKind::Touch { gesture } => Ok(super::touch_minutes(*gesture)),
        InteractionKind::Give { items } => {
            w.inventory
                .check_gift(&w.topo, &w.props, actor, partner, items)?;
            Ok(GIVE_MINUTES)
        }
        InteractionKind::Serve { prop_id, verb } => {
            let spot = w
                .affordances
                .for_prop(prop_id, verb)
                .ok_or_else(|| KernelError::interaction("道具不支持这项餐饮服务"))?;
            ensure!(
                spot.restores_fullness(),
                KernelError::interaction("餐饮服务需要能恢复饱腹的道具动作")
            );
            ensure!(
                w.topo.prop(prop_id).is_some_and(|p| p.locale == *locale),
                KernelError::interaction("双方须到餐饮道具所在地点")
            );
            ensure!(
                w.prop_occupants(prop_id).is_empty(),
                KernelError::interaction("餐饮道具正被使用")
            );
            if let Some(action) = &spot.action {
                let users = [actor, partner];
                check_conditions(&w.topo, &w.actors, w.minutes, action, locale, &users)?;
                check_body_use(w, partner, locale, prop_id, action, None)?;
            }
            Ok(spot.minutes)
        }
    }
}

/// 招待用餐的动词允许写动作编号，与动作组一样归一成动作词。
fn normalize_kind(topo: &crate::topology::Topology, kind: &InteractionKind) -> InteractionKind {
    match kind {
        InteractionKind::Serve { prop_id, verb } => InteractionKind::Serve {
            prop_id: prop_id.clone(),
            verb: crate::action_check::normalize_verb(topo, Some(prop_id), verb),
        },
        other => other.clone(),
    }
}
