//! 人物活动与计划的组合更新只在此处维护。
use crate::{activity::Activity, journal::Journal, needs::Needs};
use protocol::{BodyEvent, BodyEventKind};
use std::collections::{BTreeMap, BTreeSet, VecDeque};

/// 全部人物，按编号索引。
pub(crate) type Actors = BTreeMap<String, Actor>;

// ---------- Actor ----------

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct Actor {
    #[serde(default)]
    pub kind: protocol::MemberKind,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub avatar: Option<crate::avatar::Profile>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub possession: Option<crate::possession::Control>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub free_walk: Option<crate::navigation::free::FreeWalk>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub player_events: Vec<crate::possession::PlayerEvent>,
    pub id: String,
    pub name: String,
    pub locus: protocol::Locus,
    /// 不变式 1：不是 Option。任何时刻都有一个活动。
    pub current: Activity,
    pub plan: VecDeque<crate::action_state::QueuedAction>,
    #[serde(default)]
    pub actions: crate::action_state::ActionState,
    /// 自述记忆：已执行项、显著通知、最近一次的想法（逻辑在 journal.rs，此处只接线）
    pub journal: Journal,
    /// 可选住宅；没有住宅的场景按实际出生位置活动。
    #[serde(default)]
    pub home: Option<String>,
    /// 身体需求（逻辑在 needs.rs 与 physiology，此处只接线）
    pub needs: Needs,
    /// 已经发现过的尸体（死者编号），每具只记一次发现（discovery.rs）。旧存档没有这一项：
    /// 读档时把当时已有的尸体都算作见过，不补发一串发现。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub bodies_seen: Option<BTreeSet<String>>,
}

impl Actor {
    pub(crate) fn waiting(id: &str, name: &str, locale: &str, station: String, now: f64) -> Self {
        Self {
            kind: protocol::MemberKind::Resident,
            avatar: None,
            possession: None,
            free_walk: None,
            player_events: vec![],
            id: id.into(),
            name: name.into(),
            locus: protocol::Locus {
                locale: locale.into(),
                at: protocol::At::Station { station },
            },
            current: Activity::waiting(id, now, locale.into()),
            plan: VecDeque::new(),
            actions: Default::default(),
            journal: Journal::default(),
            home: None,
            needs: Needs::initial(),
            bodies_seen: Some(BTreeSet::new()),
        }
    }

    /// 回到空等：清空队列，换上无期停留。`bump` 表示旧观察作废（安排修订号加一）。
    pub(crate) fn reset_idle(&mut self, now: f64, bump: bool) {
        self.plan.clear();
        self.free_walk = None;
        self.current = Activity::waiting(&self.id, now, self.locus.locale.clone());
        if bump {
            self.actions.bump_revision();
        }
    }

    /// 当前移动走完时的位置：接续行走的终点站点，或行程的目的落脚点；不在移动中为 None。
    pub(crate) fn destination(&self) -> Option<protocol::Locus> {
        if let Some(walk) = &self.free_walk {
            return walk.points.last().map(|dest| protocol::Locus {
                locale: dest.locale.clone(),
                at: protocol::At::Station {
                    station: walk.station.clone(),
                },
            });
        }
        match &self.current.kind {
            crate::activity::ActKind::Travel { journey, .. } => Some(journey.destination()),
            _ => None,
        }
    }

    /// 显著通知：进收件箱，也作为世界事件留给 Agent 按游标读取。
    pub(crate) fn notify(&mut self, now: f64, text: String) {
        let notice = format!("{} {text}", crate::clock_string(now));
        self.journal.notice(now, notice);
    }

    /// 活动物理性失败：记通知，回到空等；返回观察日志一行。
    pub(crate) fn fail_current(&mut self, now: f64, reason: String) -> String {
        let verb = self.current.verb.clone();
        let notice = format!("{} 「{verb}」失败：{reason}", crate::clock_string(now));
        self.journal.notice(now, notice.clone());
        self.current = Activity::waiting(&self.id, now, self.locus.locale.clone());
        format!("{} {notice}", self.name)
    }

    /// 能发起或接受互动：受 Agent 控制、能行动、没有安排也没有正在做的事。
    pub fn interaction_available(&self) -> bool {
        self.controllable()
            && !self.needs.incapacitated()
            && self.plan.is_empty()
            && self.current.action.is_none()
            && self.current.is_idle()
    }

    /// 普通活动可在本人接受聊天时中断；已有的共同互动不能被另一场聊天覆盖。
    pub(crate) fn talk_available(&self) -> bool {
        self.controllable()
            && !self.needs.incapacitated()
            && self.current.interaction.is_none()
            && !self.possession.as_ref().is_some_and(|p| p.awaiting_arrival)
    }

    /// 玩家可以直接移动这个人：在场、空闲、没有排队的动作，身体能走。
    pub(crate) fn can_walk_freely(&self) -> bool {
        self.present()
            && self.current.is_idle()
            && self.plan.is_empty()
            && self.current.action.is_none()
            && self.needs.can_move()
            && !self.needs.incapacitated()
    }

    pub fn is_avatar(&self) -> bool {
        self.kind == protocol::MemberKind::Avatar
    }

    pub fn player_controlled(&self) -> bool {
        self.is_avatar() || self.possession.is_some()
    }

    /// 玩家控制状态的唯一读取入口：附身的居民存在 possession，化身存在化身资料里。
    pub fn control(&self) -> Option<&crate::possession::Control> {
        self.possession
            .as_ref()
            .or_else(|| self.avatar.as_ref().map(|p| &p.control))
    }

    pub(crate) fn control_mut(&mut self) -> Option<&mut crate::possession::Control> {
        match (&mut self.possession, &mut self.avatar) {
            (Some(control), _) => Some(control),
            (None, Some(profile)) => Some(&mut profile.control),
            (None, None) => None,
        }
    }

    pub fn present(&self) -> bool {
        !matches!(self.locus.at, protocol::At::Offstage)
    }

    /// 日志里说的是这个人。
    pub(crate) fn event_info(&self) -> protocol::EventInfo {
        protocol::EventInfo::about(&self.id, &self.name)
    }

    /// 能行动却在无期空等：名册上的「等待新计划」就是这个状态。
    pub fn waiting_for_plan(&self) -> bool {
        !self.needs.incapacitated() && self.current.is_idle()
    }

    pub(crate) fn controllable(&self) -> bool {
        self.present() && (self.is_avatar() || self.actions.agent_controlled)
    }

    /// 生命事件：进生命历史与日记；除道具回执外也作为显著通知。返回观察日志一行。
    /// alert 是需要提示卡时的细节，随日记一起记下。
    pub(crate) fn body_event(
        &mut self,
        now: f64,
        kind: BodyEventKind,
        source: &str,
        text: String,
        alert: Option<protocol::Alert>,
    ) -> String {
        let source: String = source.chars().take(250).collect();
        let text: String = text.chars().take(1000).collect();
        self.needs.body.history.push(BodyEvent {
            at: now,
            kind,
            source,
            text: text.clone(),
        });
        self.journal.record_alert(now, text.clone(), alert);
        let log = format!("{} {text}", self.name);
        // 自己使用道具的完成回执由动作系统返回，不额外打断已经安排的后续动作。
        if kind != BodyEventKind::Prop {
            self.notify(now, text);
        }
        log
    }
}
