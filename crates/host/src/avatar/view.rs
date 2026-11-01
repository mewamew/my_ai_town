//! 发给控制者的化身状态：内核的化身视图加上 host 的世界编号、速度、租约与位置上报回执。
use crate::runtime::Runtime;
use protocol::{
    AvatarGoal, AvatarInteraction, AvatarLease, AvatarSession, AvatarSight, AvatarView,
    InteractionStatus, RecentEvent,
};

/// 附身时给控制者看的本人近况条数。
const RECENT_EVENTS: usize = 12;

impl Runtime {
    /// 发给一个连接的化身状态：内核视图，加上世界编号、速度、租约、附身时的近况与目标、位置上报回执。
    pub(super) fn avatar_session(&self, connection: u64) -> AvatarSession {
        let lease = self.avatar_control.lease.as_ref();
        let own = lease.is_some_and(|l| l.connection == connection);
        let occupied_elsewhere = (self.world.possessed().is_some() || lease.is_some()) && !own;
        let (view, recent, goals) = if occupied_elsewhere {
            let view = AvatarSight::Occupied {
                actor: (),
                supported: true,
            };
            (view, None, None)
        } else {
            let mut view = self.world.avatar_view();
            self.mark_reply_failures(&mut view);
            let possessed = self.world.possessed();
            let recent = possessed.map(|a| {
                a.journal
                    .events
                    .iter()
                    .rev()
                    .take(RECENT_EVENTS)
                    .map(|e| RecentEvent {
                        at: e.at,
                        text: e.text.clone(),
                    })
                    .collect()
            });
            let goals = possessed
                .and_then(|a| self.driver.runtime.session(&a.id))
                .map(|s| {
                    s.context_goals()
                        .iter()
                        .map(|g| AvatarGoal {
                            status: g.status,
                            text: g.title.clone(),
                        })
                        .collect()
                });
            (AvatarSight::Own(view), recent, goals)
        };
        let session = AvatarSession {
            view,
            world_id: self.population.world_id.clone(),
            // 化身每拍实际走的距离按它算（模拟分钟 / 秒），0 为暂停
            speed: self.normal_pace(),
            controlled: lease.is_some_and(|l| l.held_by(connection)),
            occupied: lease.is_some(),
            recent,
            goals,
            lease: lease.filter(|_| own).map(|l| AvatarLease {
                epoch: l.epoch.clone(),
                resume_token: l.token.clone(),
                sequence: self
                    .world
                    .player_control()
                    .map(|p| p.last_sequence)
                    .unwrap_or(0),
            }),
            // 旧协议字段仅为兼容保留，不再启用前端位置上报。
            client_positions: false,
            walk: self.world.avatar_walk(),
            position: None,
        };
        session
    }

    /// 受邀村民回应邀请的格式连续出错时，在邀请者看到的这条邀请上写明。
    fn mark_reply_failures(&self, view: &mut AvatarView) {
        let AvatarView::Present(state) = view else {
            return;
        };
        for item in &mut state.interactions {
            let (id, partner, status, response_error) = match item {
                AvatarInteraction::Chat(c) => (&c.id, &c.partner, c.status, &mut c.response_error),
                AvatarInteraction::Pair(p) => (&p.id, &p.partner, p.status, &mut p.response_error),
            };
            if status != InteractionStatus::Offered {
                continue;
            }
            let Some(failure) = self
                .driver
                .runtime
                .session(partner)
                .and_then(|s| s.invitation_reply_failure.as_ref())
                .filter(|f| f.invitation_ids.iter().any(|x| x == id))
            else {
                continue;
            };
            *response_error = Some(
                if failure.postponed() {
                    "模型连续返回了错误的回应格式，暂缓后会重试；你也可以取消邀请。"
                } else {
                    "模型返回的回应格式有误，正在尝试修正。"
                }
                .into(),
            );
        }
    }
}
