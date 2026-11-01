//! 化身的每拍处理：控制目标死亡或断线超时就交还，附身的村民走到了就交给玩家，二维地图按方向移动，
//! 交谈轮到玩家太久没说话就代为倾听。
use crate::{network::Clients, runtime::Runtime};
use protocol::InteractionCommand;
use std::time::{Duration, Instant};

/// 二维地图的方向输入超过这么久没更新就停下：模拟循环卡了很久之后，也最多按这么久走一段。
const INPUT_TIMEOUT: Duration = Duration::from_millis(350);
/// 交谈轮到玩家后等这么久（或玩家已断线）就代为倾听，不让整场交谈卡住。
const TURN_WAIT: Duration = Duration::from_secs(60);

impl Runtime {
    pub(crate) fn avatar_tick(&mut self, _clients: &Clients) {
        let now = Instant::now();
        let elapsed = self
            .avatar_control
            .last_tick
            .replace(now)
            .map(|last| now.duration_since(last))
            .unwrap_or_default();
        if self
            .world
            .possessed()
            .is_some_and(|a| a.needs.incapacitated() && a.needs.body.dead)
        {
            self.release_player_safely();
            return;
        }
        // 附身的村民走到了：交给玩家。存盘失败时撤回，下一拍再试；失败日志由检查点记。
        if self.world.possession_arrived() {
            let _ = self.transact(|rt| {
                rt.world.activate_possession();
                Ok::<_, std::convert::Infallible>(())
            });
        }
        let Some(lease) = self.avatar_control.lease.as_mut() else {
            return;
        };
        if lease.lapse(now) {
            self.avatar_control.halt();
        }
        let Some(lease) = self.avatar_control.lease.as_ref() else {
            return;
        };
        if lease.expired() {
            self.release_player_safely();
            return;
        }
        let online = lease.online();
        if !online {
            self.avatar_control.halt();
        }
        self.advance_avatar(now);
        if self.save_failed || self.speed <= 0. || !self.world_settings.ready() {
            self.avatar_control.halt();
            return;
        }
        self.listen_when_turn_waits(online, elapsed);
    }

    /// 按方向输入把化身走到 until 这一刻：从上次走到的时刻算起，按真实经过的时间走，
    /// 输入到达 INPUT_TIMEOUT 后还没续上就停在那一刻。每拍和每来一条输入各调一次，
    /// 走的路就和玩家按住方向的时长一致，不随模拟循环一拍的长短（实际约 107 毫秒）忽快忽慢。
    /// 暂停、存盘失败、世界没设好时只记下时刻、不走；撞墙之类走不动时原地不动，不需要回执。
    pub(super) fn advance_avatar(&mut self, until: Instant) {
        let Some(from) = self.avatar_control.moved_at else {
            self.avatar_control.moved_at = Some(until);
            return;
        };
        // 上一拍处理期间到的输入，取出来时已经走过它到达的那一刻：从走到的地方接着算，不倒回去重走
        let until = until.max(from);
        self.avatar_control.moved_at = Some(until);
        let control = &self.avatar_control;
        let end = control
            .input_at
            .map_or(from, |at| (at + INPUT_TIMEOUT).min(until));
        if end <= from
            || control.direction == [0., 0.]
            || self.save_failed
            || self.speed <= 0.
            || !self.world_settings.ready()
        {
            return;
        }
        // 内核一次最多收 10 模拟分钟（最高倍率下一拍约 8 分钟）
        let minutes = ((end - from).as_secs_f64() * self.normal_pace()).min(10.);
        let _ = self
            .world
            .avatar_move(control.direction, control.run, minutes);
    }

    /// 交谈轮到玩家：同一次轮到（同一聊天、同一动作版本）累计等待，超时或断线就代为倾听。
    fn listen_when_turn_waits(&mut self, online: bool, elapsed: Duration) {
        let actor = self.world.player_id().to_owned();
        let turn = self
            .world
            .active_chat(&actor)
            .filter(|_| self.world.chat_turn(&actor))
            .map(|i| {
                let revision = self.world.actor(&actor).map_or(0, |a| a.actions.revision);
                (i.id.clone(), revision)
            });
        let Some((id, revision)) = turn else {
            self.avatar_control.turn = None;
            return;
        };
        let waited = match &self.avatar_control.turn {
            Some((old, r, d)) if *old == id && *r == revision => *d + elapsed,
            _ => Duration::ZERO,
        };
        self.avatar_control.turn = Some((id.clone(), revision, waited));
        if online && waited < TURN_WAIT {
            return;
        }
        let command_id = format!("control/auto-listen/{:032x}", rand::random::<u128>());
        // 轮次已经过去等情况下倾听会被拒绝，这时什么也不用做。
        let _ = self.world.avatar_interact(
            &command_id,
            revision,
            &InteractionCommand::Listen { interaction_id: id },
        );
        self.avatar_control.turn = None;
        // 存盘失败由检查点自己记日志，下一拍再存。
        let _ = self.checkpoint(true);
    }
}
