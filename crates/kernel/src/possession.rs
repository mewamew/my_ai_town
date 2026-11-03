//! 玩家控制权；居民身份、身体和经历始终由原系统保存。
use crate::{
    actor::Actor,
    avatar::{self, Spot},
    error::{KernelError, Result},
    World,
};
use protocol::At;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeMap;

/// 一个控制纪元里保留的操作回执数：写入时淘汰编号最小的，读档按同一上限校验。
pub const RECEIPT_LIMIT: usize = 64;
/// 每人保留的玩家行为来源记录数：写入时丢掉最早的，读档按同一上限校验。
pub const PLAYER_EVENT_LIMIT: usize = 500;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Control {
    #[serde(default)]
    pub awaiting_arrival: bool,
    pub epoch: String,
    pub last_sequence: u64,
    #[serde(deserialize_with = "read_receipts")]
    pub receipts: BTreeMap<u64, Value>,
    pub drop_station: Option<String>,
}

impl Control {
    /// 按控制纪元与操作编号查回执：处理过的返回原回执，新编号返回 None，过期编号报错。
    pub fn receipt(&self, epoch: &str, sequence: u64) -> Result<Option<Value>> {
        ensure!(self.epoch == epoch, KernelError::action("控制权已失效"));
        if let Some(v) = self.receipts.get(&sequence) {
            return Ok(Some(v.clone()));
        }
        ensure!(
            sequence > self.last_sequence,
            KernelError::action("操作编号已过期，请刷新状态")
        );
        Ok(None)
    }

    /// 换一个控制纪元：操作编号从头计，旧回执作废。
    pub(crate) fn reset(&mut self, epoch: String) {
        self.epoch = epoch;
        self.last_sequence = 0;
        self.receipts.clear();
    }

    /// 记下一条回执；超过上限时淘汰编号最小的。
    pub(crate) fn remember(&mut self, sequence: u64, receipt: Value) {
        self.last_sequence = sequence;
        self.receipts.insert(sequence, receipt);
        while self.receipts.len() > RECEIPT_LIMIT {
            self.receipts.pop_first();
        }
    }

    /// 回执账本合法：不超过上限，编号都不大于最后处理的编号。
    pub(crate) fn receipts_valid(&self) -> bool {
        self.receipts.len() <= RECEIPT_LIMIT
            && self.receipts.keys().all(|n| *n <= self.last_sequence)
    }
}

// serde 的 flatten 中间表示不会把 JSON 对象键自动转成整数。
fn read_receipts<'de, D: serde::Deserializer<'de>>(
    d: D,
) -> std::result::Result<BTreeMap<u64, Value>, D::Error> {
    BTreeMap::<String, Value>::deserialize(d)?
        .into_iter()
        .map(|(key, value)| {
            key.parse::<u64>()
                .map(|key| (key, value))
                .map_err(serde::de::Error::custom)
        })
        .collect()
}

/// 仪器记录，不进入角色观察、日记或记忆；事实仍由原动作/聊天系统产生。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlayerEvent {
    pub at: f64,
    pub cursor: u64,
    pub command: Value,
}

impl Actor {
    /// 只能接管在场、交给 Agent、能行动也能走路的居民。
    fn check_possessable(&self) -> Result<()> {
        ensure!(
            !self.is_avatar() && self.actions.agent_controlled && self.present(),
            KernelError::action("目标不是在场居民")
        );
        ensure!(
            !self.needs.incapacitated() && self.needs.can_move(),
            KernelError::action(self.needs.limitation())
        );
        Ok(())
    }

    /// 玩家接管：保留已经开始的身体活动和聊天，只结算尚未执行的旧安排。在路上时等到达再
    /// 交给玩家（awaiting_arrival）；否则位置换成行走地图上的自由位置。
    fn begin_possession(&mut self, now: f64, waiting: bool, spot: Option<Spot>) {
        if !waiting && (self.current.is_travel() || self.free_walk.is_some()) {
            self.interrupt_actions(now, "停止行走");
            self.reset_idle(now, false);
        } else if self.current.action.is_some() {
            // 回执必须按原动作顺序结算；当前动作完成时取消尾部，绝不执行旧队列。
            self.actions.cancel_after_current = true;
        } else {
            self.interrupt_actions(now, "重新安排，取消尚未开始的步骤");
        }
        self.actions.bump_revision();
        self.possession = Some(Control {
            awaiting_arrival: waiting,
            ..Default::default()
        });
        if let Some(spot) = spot {
            self.locus = spot.locus();
        }
    }

    /// 玩家行为记录不超过上限，时刻和日志游标都不晚于当前。
    fn player_events_valid(&self, now: f64) -> bool {
        self.player_events.len() <= PLAYER_EVENT_LIMIT
            && self
                .player_events
                .iter()
                .all(|e| e.at.is_finite() && e.at <= now && e.cursor <= self.journal.cursor())
    }

    /// 记一条玩家行为来源；超过上限时丢掉最早的。
    fn record_player_event(&mut self, at: f64, command: Value) {
        self.player_events.push(PlayerEvent {
            at,
            cursor: self.journal.cursor(),
            command,
        });
        if self.player_events.len() > PLAYER_EVENT_LIMIT {
            self.player_events.remove(0);
        }
    }
}

impl World {
    pub fn record_player_event(&mut self, id: &str, command: Value) {
        let at = self.minutes;
        if let Some(a) = self.actors.get_mut(id) {
            a.record_player_event(at, command);
        }
    }

    pub fn possessed(&self) -> Option<&Actor> {
        self.actors.values().find(|a| a.possession.is_some())
    }
    pub fn player_id(&self) -> &str {
        self.possessed().map_or(avatar::ID, |a| a.id.as_str())
    }
    pub fn player_control(&self) -> Option<&Control> {
        self.actors.get(self.player_id())?.control()
    }
    pub(crate) fn player_control_mut(&mut self) -> Option<&mut Control> {
        let id = self.player_id().to_owned();
        self.actors.get_mut(&id)?.control_mut()
    }
    pub fn possess(&mut self, id: &str) -> Result<()> {
        ensure!(
            self.possessed().is_none(),
            KernelError::action("请先交还当前村民")
        );
        ensure!(
            !self.avatar().is_some_and(|a| a.present()),
            KernelError::action("请先退出化身")
        );
        let a = self
            .actors
            .get(id)
            .ok_or_else(|| KernelError::NoSuchActor(id.into()))?;
        a.check_possessable()?;
        ensure!(
            self.walk_map.is_some(),
            KernelError::navigation("此处没有手动行走地图")
        );
        let waiting = matches!(a.locus.at, At::Transit { .. });
        let spot = self.actor_spot(id);
        ensure!(
            waiting || spot.is_some(),
            KernelError::navigation("当前位置无法接管")
        );
        let now = self.minutes;
        self.actor_mut(id).begin_possession(now, waiting, spot);
        // 同行里被接管的跟随者改由玩家自己走
        self.sync_walk_member(id);
        Ok(())
    }
    /// 附身等待到达的村民已经走到可以交给玩家的位置：`activate_possession` 会生效。
    pub fn possession_arrived(&self) -> bool {
        self.possessed()
            .filter(|a| a.possession.as_ref().is_some_and(|c| c.awaiting_arrival))
            .is_some_and(|a| self.actor_spot(&a.id).is_some())
    }
    pub fn activate_possession(&mut self) -> bool {
        if !self.possession_arrived() {
            return false;
        }
        let id = self.possessed().expect("刚确认有附身目标").id.clone();
        let spot = self.actor_spot(&id).expect("刚确认有位置");
        let a = self.actor_mut(&id);
        a.locus = spot.locus();
        a.possession.as_mut().unwrap().awaiting_arrival = false;
        a.actions.bump_revision();
        true
    }
    pub fn release_possession(&mut self) -> Option<String> {
        let id = self.possessed()?.id.clone();
        let a = self.actor_mut(&id);
        a.possession = None;
        a.actions.bump_revision();
        // 交还的同行跟随者重新由世界带着走
        self.sync_walk_member(&id);
        Some(id)
    }
    /// 读档校验：玩家行为记录、附身状态、接续行走与自由位置。
    pub(crate) fn validate_player_actor(&self, a: &Actor) -> Result<()> {
        ensure!(
            a.player_events_valid(self.minutes),
            KernelError::snapshot("玩家行为来源记录无效")
        );
        if let Some(c) = &a.possession {
            ensure!(
                !a.is_avatar() && a.actions.agent_controlled && a.present(),
                KernelError::snapshot("附身目标身份无效")
            );
            ensure!(c.receipts_valid(), KernelError::snapshot("附身回执无效"));
        }
        if let Some(walk) = &a.free_walk {
            // 接续行走是动作开始前的接近段，原动作挂在 pending 上。
            ensure!(
                a.current.pending.is_some(),
                KernelError::snapshot("接续行走进度无效")
            );
            walk.validate(&self.topo, self.walk_map.as_deref())?;
        }
        if matches!(a.locus.at, At::Free { .. }) {
            self.walk_map
                .as_ref()
                .ok_or_else(|| KernelError::snapshot("自由位置缺少行走地图"))?
                .check_free_locus(&a.locus, &self.topo)?;
        }
        Ok(())
    }
}
