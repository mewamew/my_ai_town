//! 邀请只记录提议；对方明确答应交谈后才中断普通活动，安装共同交谈活动。
//! 完成、中断、占用与恢复均由内核维护，模型不能替另一个村民表示同意。
//! 规则在这里与 chat.rs（`impl Interactions`），世界入口在 commands.rs。
use crate::error::{KernelError, Result};
use crate::{
    activity::ActKind,
    actor::{Actor, Actors},
    World,
};
use protocol::{
    ChatEntryKind, FactKind, Interaction, InteractionKind, InteractionStatus as Status,
};
use std::collections::BTreeMap;

mod appointments;
mod chat;
mod chat_validation;
pub(crate) mod chat_view;
mod commands;
mod pledge;
mod proposals;
pub(crate) mod validation;
pub(crate) mod walk;

pub(crate) use chat::{ChatLine, LeaveKind};
pub(crate) use walk::WalkTrails;
pub use walk::LEAD_PACE;

/// 写给互动参与者的一条事实：种类、正文、涉及的对象。
pub(crate) struct Fact {
    pub kind: FactKind,
    pub text: String,
    pub objects: Vec<String>,
}

/// 邀请消息和聊天发言的字数上限。
pub(crate) const MESSAGE_MAX_CHARS: usize = 400;
/// 一人同时最多发出几个未处理的邀请；最多收到几个。
const MAX_OPEN_OFFERS: usize = 2;
const MAX_OPEN_INVITES: usize = 6;
/// 邀请多少分钟内可回应；agent 把它写进工具说明。
pub const INVITE_MINUTES: f64 = 600.0;
/// 玩家来搭话后，受邀的人手头的事先停这么久等回应（模拟分钟），不取消、之后照原样接着做；
/// 想好要聊时人还在原地。限时是因为模型可能出错或不回应，不能让人一直站着。
pub const TALK_HOLD_MINUTES: f64 = 10.0;
/// 交谈与赠予的固定时长（分钟）。
pub(crate) const TALK_MINUTES: f64 = 5.0;
pub(crate) const GIVE_MINUTES: f64 = 1.0;

/// 亲近多久：拥抱一下，牵手、依偎待一会儿。
pub(crate) fn touch_minutes(gesture: protocol::Gesture) -> f64 {
    match gesture {
        protocol::Gesture::HoldHands => 10.0,
        protocol::Gesture::Lean => 15.0,
        protocol::Gesture::Hug => 3.0,
    }
}

/// 亲近在旁人眼里的样子：成了是两人牵手、依偎、抱在一起，没成是一个人躲开了。
pub(crate) fn touch_scene(gesture: protocol::Gesture, a: &str, b: &str, accepted: bool) -> String {
    use protocol::Gesture::*;
    match (gesture, accepted) {
        (HoldHands, true) => format!("{a}和{b}牵起了手"),
        (Lean, true) => format!("{a}靠在了{b}身上"),
        (Hug, true) => format!("{a}和{b}抱在了一起"),
        (HoldHands, false) => format!("{a}想牵{b}的手，{b}躲开了"),
        (Lean, false) => format!("{a}想靠在{b}身上，{b}躲开了"),
        (Hug, false) => format!("{a}想抱{b}，{b}躲开了"),
    }
}

/// 全部互动，按编号索引。规则在这里与 chat.rs，改动的入口在 commands.rs（World）。
#[derive(Debug, Clone, Default)]
pub struct Interactions {
    pub(crate) items: BTreeMap<String, Interaction>,
    /// 每人最近一句台词在哪：由聊天记录派生，不存档；写台词时更新，读档时重建。
    /// 名册每拍都要给每个人取最近台词，不必每次扫全部聊天。
    latest_speech: BTreeMap<String, SpeechRef>,
}

/// 一句台词的位置。比较先看时刻，再看聊天编号，最后看序号。
#[derive(Debug, Clone, PartialEq)]
struct SpeechRef {
    at: f64,
    chat: String,
    seq: u64,
}

impl SpeechRef {
    fn later_than(&self, other: &SpeechRef) -> bool {
        self.at
            .total_cmp(&other.at)
            .then_with(|| self.chat.cmp(&other.chat))
            .then(self.seq.cmp(&other.seq))
            .is_gt()
    }
}

impl std::ops::Index<&str> for Interactions {
    type Output = Interaction;
    fn index(&self, id: &str) -> &Interaction {
        &self.items[id]
    }
}

impl Interactions {
    /// 读档装回互动表，并重建由聊天记录派生的索引。
    pub(crate) fn restore(items: BTreeMap<String, Interaction>) -> Self {
        let mut restored = Self {
            items,
            latest_speech: BTreeMap::new(),
        };
        let speeches: Vec<_> = restored
            .items
            .values()
            .filter_map(|i| Some((i.id.clone(), i.chat.as_ref()?)))
            .flat_map(|(id, c)| {
                c.entries
                    .iter()
                    .filter(|e| e.kind == ChatEntryKind::Speech)
                    .map(move |e| (e.actor.clone(), id.clone(), e.seq, e.at))
            })
            .collect();
        for (actor, chat, seq, at) in speeches {
            restored.note_speech(&actor, SpeechRef { at, chat, seq });
        }
        restored
    }

    /// 记下某人说了一句话：比已记的更晚才替换。
    fn note_speech(&mut self, actor: &str, speech: SpeechRef) {
        match self.latest_speech.get(actor) {
            Some(old) if !speech.later_than(old) => {}
            _ => {
                self.latest_speech.insert(actor.into(), speech);
            }
        }
    }

    /// 某人最近说的一句话所在的互动与记录。
    pub(crate) fn latest_speech_entry(
        &self,
        actor: &str,
    ) -> Option<(&Interaction, &protocol::ChatEntry)> {
        let at = self.latest_speech.get(actor)?;
        let item = self.items.get(&at.chat)?;
        let entry = item.chat.as_ref()?.entries.get(at.seq as usize - 1)?;
        Some((item, entry))
    }

    pub(crate) fn get(&self, id: &str) -> Option<&Interaction> {
        self.items.get(id)
    }

    fn get_mut(&mut self, id: &str) -> &mut Interaction {
        self.items.get_mut(id).expect("互动存在")
    }

    /// 这个编号有没有互动用着（不论有没有本人）；agent 起新编号时避开。
    pub fn contains(&self, id: &str) -> bool {
        self.items.contains_key(id)
    }

    /// 本人参与的某项互动。
    pub fn of(&self, actor: &str, id: &str) -> Option<&Interaction> {
        self.items.get(id).filter(|i| i.includes(actor))
    }

    /// 有人向本人发出、尚未回应的交谈或同行邀请：忙着也能考虑，接受才中断手头的事。
    pub fn has_talk_invitation(&self, actor: &str) -> bool {
        self.items
            .values()
            .any(|i| i.partner == actor && i.status == Status::Offered && i.kind.has_chat())
    }

    /// 玩家（化身或附身）发给这个人、还没回应、发出不到 TALK_HOLD_MINUTES 的交谈或同行邀请。
    pub(crate) fn player_talk_offer(&self, actors: &Actors, actor: &str, now: f64) -> bool {
        self.items.values().any(|i| {
            i.partner == actor
                && i.status == Status::Offered
                && i.kind.has_chat()
                && now < i.expires_at.min(i.created_at + TALK_HOLD_MINUTES)
                && actors
                    .get(&i.initiator)
                    .is_some_and(|a| a.player_controlled())
        })
    }

    /// 本人参与的互动：未结束的在前，其余按创建时间倒序，最多 12 项。
    pub fn for_actor(&self, actor: &str) -> Vec<&Interaction> {
        let mut items: Vec<_> = self.items.values().filter(|i| i.includes(actor)).collect();
        items.sort_by(|a, b| {
            a.status
                .terminal()
                .cmp(&b.status.terminal())
                .then_with(|| b.created_at.total_cmp(&a.created_at))
                .then_with(|| b.id.cmp(&a.id))
        });
        items.truncate(12);
        items
    }

    /// 本人最近一次发起、被对方婉拒的邀请（按发出的先后，和 `for_actor` 的次序一致）。
    /// 名册每拍给每个人取一次，所以只扫一遍、不排序。
    pub fn latest_declined_offer(&self, actor: &str) -> Option<&Interaction> {
        self.items
            .values()
            .filter(|i| i.status == Status::Declined && i.initiator == actor)
            .max_by(|a, b| {
                a.created_at
                    .total_cmp(&b.created_at)
                    .then_with(|| a.id.cmp(&b.id))
            })
    }

    /// 刚发出的邀请：状态为已提议，now 起 INVITE_MINUTES 内可回应。交谈邀请带着空的聊天状态。
    pub(crate) fn new_offer(
        id: &str,
        initiator: &Actor,
        partner: &str,
        kind: InteractionKind,
        message: &str,
        duration_minutes: f64,
        now: f64,
    ) -> Interaction {
        Interaction {
            chat: kind.has_chat().then(Default::default),
            id: id.into(),
            initiator: initiator.id.clone(),
            partner: partner.into(),
            locale: initiator.locus.locale.clone(),
            kind,
            message: message.into(),
            reply: None,
            accepted: None,
            status: Status::Offered,
            created_at: now,
            expires_at: now + INVITE_MINUTES,
            started_at: None,
            ended_at: None,
            duration_minutes,
            changes: vec![],
            reason: None,
            event_ids: Default::default(),
        }
    }

    /// 用过的邀请编号：内容相同是重送，返回原邀请；内容不同报错。没用过返回 None。
    pub(crate) fn resent_offer(
        &self,
        id: &str,
        actor: &str,
        partner: &str,
        kind: &InteractionKind,
        message: &str,
    ) -> Result<Option<Interaction>> {
        let Some(old) = self.items.get(id) else {
            return Ok(None);
        };
        ensure!(
            old.initiator == actor
                && old.partner == partner
                && old.kind == *kind
                && old.message == message,
            KernelError::interaction("互动编号已用于不同邀请")
        );
        Ok(Some(old.clone()))
    }

    /// 发新邀请的数量规则：两人之间只能有一个待回应的交谈邀请；未处理的邀请每人发出不超过
    /// MAX_OPEN_OFFERS 个，收到不超过 MAX_OPEN_INVITES 个。
    pub(crate) fn check_new_offer(
        &self,
        actor: &str,
        partner: &str,
        kind: &InteractionKind,
    ) -> Result<()> {
        if kind.has_chat() {
            ensure!(
                !self.items.values().any(|i| {
                    i.kind.has_chat()
                        && i.status == Status::Offered
                        && ((i.initiator == actor && i.partner == partner)
                            || (i.initiator == partner && i.partner == actor))
                }),
                KernelError::interaction("你们之间已有待回应的交谈或同行邀请")
            );
        }
        // 答应了的约定照常活动，不占邀请名额
        let open = |f: &dyn Fn(&Interaction) -> bool| {
            self.items
                .values()
                .filter(|i| !i.status.terminal() && f(i))
                .filter(|i| {
                    !(i.status == Status::Running
                        && matches!(i.kind, InteractionKind::Appointment { .. }))
                })
                .count()
        };
        ensure!(
            open(&|i| i.initiator == actor) < MAX_OPEN_OFFERS
                && open(&|i| i.partner == partner) < MAX_OPEN_INVITES,
            KernelError::interaction("尚未处理的邀请过多，请等待回应或取消原邀请")
        );
        Ok(())
    }

    /// 记下新邀请：双方各一条邀请事实、发起者的话，受邀者再收到一条带互动来源的通知。
    pub(crate) fn record_offer(
        &mut self,
        actors: &mut Actors,
        now: f64,
        item: &Interaction,
        message: &str,
    ) {
        let (from, to) = (&actors[&item.initiator].name, &actors[&item.partner].name);
        let label = item.kind.label();
        let text = format!("{from} 邀请 {to} 一起{label}");
        // 编号在通知的对象和观察的互动列表里，文字里不写：日志和记忆页会原样显示它
        let notice = format!("收到 {from} 的{label}邀请");
        self.items.insert(item.id.clone(), item.clone());
        self.fact(actors, now, item, &text);
        self.speech(actors, now, item, &item.initiator, message);
        // 带互动来源的通知可以唤醒思考，而不把打招呼当成强制中断身体动作。
        let objects = vec![
            item.id.clone(),
            item.initiator.clone(),
            item.partner.clone(),
        ];
        self.link_event(
            actors,
            now,
            &item.id,
            &item.partner,
            Fact {
                kind: FactKind::Notice,
                text: notice,
                objects,
            },
        );
    }

    /// 记下受邀者的回应；接受时互动开始。返回更新后的互动。
    pub(crate) fn record_reply(
        &mut self,
        id: &str,
        accept: bool,
        message: &str,
        now: f64,
    ) -> Interaction {
        let item = self.get_mut(id);
        item.reply = Some(message.into());
        item.accepted = Some(accept);
        if accept {
            item.status = Status::Running;
            item.started_at = Some(now);
        }
        item.clone()
    }

    /// 此刻正在用这件道具的人：单人道具动作和双人餐饮服务共用占用事实。
    /// 只算已经开始的使用，走向操作点的路上不算；用来判断道具能不能再被别人开始使用。
    /// （背包转移看 inventory::item_idle，移除道具看 remove_prop，口径各不相同。）
    pub(crate) fn prop_occupants(&self, actors: &Actors, now: f64, prop: &str) -> Vec<String> {
        actors
            .values()
            .filter(|a| {
                let active = !matches!(a.current.kind, ActKind::Travel { .. })
                    && a.current.remaining(now).is_none_or(|m| m > 1e-9);
                let uses_prop = a.current.action.as_ref().is_some_and(|b| b.uses_prop(prop));
                let served_at = a
                    .current
                    .interaction
                    .as_ref()
                    .and_then(|id| self.items.get(id))
                    .is_some_and(
                        |i| matches!(&i.kind, InteractionKind::Serve { prop_id, .. } if prop_id == prop),
                    );
                active && (uses_prop || served_at)
            })
            .map(|a| a.id.clone())
            .collect()
    }

    /// 本人正在参与的招待用餐所用的道具。
    pub(crate) fn prop_of(&self, actor: &Actor) -> Option<&str> {
        let id = actor.current.interaction.as_ref()?;
        match &self.items.get(id)?.kind {
            InteractionKind::Serve { prop_id, .. } => Some(prop_id),
            _ => None,
        }
    }

    /// 下一个邀请过期、停下等回应结束、约定提醒或判定还有多久。
    pub(crate) fn boundary(&self, now: f64) -> f64 {
        let appointments = self.appointment_boundary(now);
        self.items
            .values()
            .filter(|i| i.status == Status::Offered)
            .flat_map(|i| {
                let hold = i
                    .kind
                    .has_chat()
                    .then_some(i.created_at + TALK_HOLD_MINUTES);
                [Some(i.expires_at), hold]
            })
            .flatten()
            .filter(|at| *at > now)
            .map(|at| at - now)
            .fold(appointments, f64::min)
    }

    pub(crate) fn expire(&mut self, actors: &mut Actors, now: f64) {
        let ids: Vec<_> = self
            .items
            .values()
            .filter(|i| i.status == Status::Offered && i.expires_at <= now)
            .map(|i| i.id.clone())
            .collect();
        for id in ids {
            let minutes = self.items[&id].expires_at - self.items[&id].created_at;
            self.end(
                actors,
                now,
                &id,
                Status::Expired,
                Some(format!("邀请超过 {minutes:.0} 分钟未回应")),
            );
        }
    }

    /// 外部原因打断本人的互动；聊天按离开处理。失败时返回日志文本。
    pub(crate) fn interrupt(
        &mut self,
        actors: &mut Actors,
        now: f64,
        actor: &str,
        reason: &str,
    ) -> Option<String> {
        let id = actors.get(actor)?.current.interaction.clone()?;
        if self.items[&id].chat.is_some() {
            if let Err(e) = self.leave_chat(actors, now, actor, &id, LeaveKind::Forced, reason) {
                return Some(format!("{actor} 离开聊天 {id} 失败：{e}"));
            }
        } else {
            self.end(actors, now, &id, Status::Interrupted, Some(reason.into()));
        }
        None
    }

    pub(crate) fn end(
        &mut self,
        actors: &mut Actors,
        now: f64,
        id: &str,
        status: Status,
        reason: Option<String>,
    ) {
        if self.items[id].chat.is_some() && self.items[id].status == Status::Running {
            self.end_chat(actors, now, id, reason.as_deref().unwrap_or("交谈结束"));
            return;
        }
        let item = self.get_mut(id);
        if item.status.terminal() {
            return;
        }
        item.status = status;
        item.ended_at = Some(now);
        item.reason = reason;
        let text = if status == Status::Succeeded {
            match &item.kind {
                InteractionKind::Give { items } => {
                    format!("赠予完成：{} 件物品已进入对方背包", items.len())
                }
                InteractionKind::Talk => {
                    "双方完成交谈；双方说法各自留有来源，不作为已证实的事实".into()
                }
                InteractionKind::Serve { .. } => {
                    "招待用餐完成；补给与身体效果按道具定义结算，招待者未获得用餐收益".into()
                }
                InteractionKind::Walk { .. } => "同行结束".into(),
                InteractionKind::Appointment { .. } => "约定达成：按约在约好的地方见上了面".into(),
                InteractionKind::Touch { gesture } => format!("{}了一会儿", gesture.label()),
            }
        } else {
            format!(
                "{}未完成：{}；已发生的时间、身体变化和已听到的话保留",
                item.kind.label(),
                item.reason.as_deref().unwrap_or("互动结束")
            )
        };
        item.changes.push(text.clone());
        let item = item.clone();
        for actor in [&item.initiator, &item.partner] {
            let a = actors.get_mut(actor).expect("互动参与者存在");
            if a.current.interaction.as_deref() == Some(id) {
                a.reset_idle(now, true);
            }
        }
        self.fact(actors, now, &item, &text);
        for actor in [&item.initiator, &item.partner] {
            self.link_event(
                actors,
                now,
                id,
                actor,
                Fact {
                    kind: FactKind::Notice,
                    text: text.clone(),
                    objects: vec![id.into()],
                },
            );
        }
    }

    /// 给一名参与者写一条互动事实，并把事件编号挂到互动上。
    fn link_event(
        &mut self,
        actors: &mut Actors,
        now: f64,
        interaction: &str,
        actor: &str,
        fact: Fact,
    ) {
        let event = actors.get_mut(actor).expect("互动参与者存在").journal.fact(
            now,
            fact.kind,
            fact.text,
            fact.objects,
            None,
            None,
        );
        self.get_mut(interaction)
            .event_ids
            .entry(actor.into())
            .or_default()
            .push(event);
    }

    fn fact(&mut self, actors: &mut Actors, now: f64, item: &Interaction, text: &str) {
        for actor in [&item.initiator, &item.partner] {
            self.link_event(
                actors,
                now,
                &item.id,
                actor,
                Fact {
                    kind: FactKind::Interaction,
                    text: text.into(),
                    objects: vec![
                        item.initiator.clone(),
                        item.partner.clone(),
                        item.locale.clone(),
                        item.id.clone(),
                    ],
                },
            );
        }
    }

    fn speech(
        &mut self,
        actors: &mut Actors,
        now: f64,
        item: &Interaction,
        speaker: &str,
        text: &str,
    ) {
        if text.trim().is_empty() {
            return;
        }
        if item.chat.is_some() {
            let audience = [&item.initiator, &item.partner]
                .into_iter()
                .cloned()
                .collect();
            self.chat_event(
                actors,
                now,
                &item.id,
                ChatLine {
                    speaker,
                    kind: ChatEntryKind::Speech,
                    text,
                    audience,
                },
            );
            return;
        }
        let line = format!("{} 说：{}", actors[speaker].name, text);
        for actor in [&item.initiator, &item.partner] {
            self.link_event(
                actors,
                now,
                &item.id,
                actor,
                Fact {
                    kind: FactKind::Speech,
                    text: line.clone(),
                    objects: vec![
                        speaker.into(),
                        item.initiator.clone(),
                        item.partner.clone(),
                        item.locale.clone(),
                        item.id.clone(),
                    ],
                },
            );
        }
    }
}

/// 双方在场：对方受 Agent 控制且能回应。村民之间要在同一驻留处所；玩家搭话、送东西只看距离和遮挡
/// （见 World::player_pair_place 与 Reach::pair），路上也能聊。
pub(crate) fn check_pair_here(
    w: &World,
    actor: &str,
    partner: &str,
    kind: &InteractionKind,
) -> Result<()> {
    let a = w
        .actors
        .get(actor)
        .ok_or_else(|| KernelError::interaction("发起者不存在"))?;
    let b = w
        .actors
        .get(partner)
        .ok_or_else(|| KernelError::interaction("对方不存在"))?;
    let here = w.player_pair_place(actor, partner, kind).is_some()
        || (a.locus.locale == b.locus.locale && w.topo.is_dwell(&a.locus.locale));
    ensure!(
        actor != partner && here && a.present() && b.controllable() && !b.needs.incapacitated(),
        KernelError::interaction("需要另一名在场、能够回应的村民")
    );
    crate::avatar::Reach::new(w).pair(actor, partner)?;
    Ok(())
}

fn check_message(message: &str) -> Result<()> {
    ensure!(
        message.chars().count() <= MESSAGE_MAX_CHARS,
        KernelError::interaction(format!("对话内容不能超过 {MESSAGE_MAX_CHARS} 字"))
    );
    Ok(())
}
