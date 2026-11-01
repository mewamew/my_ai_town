use super::*;
use protocol::{ActionDraft, Interaction, InteractionCommand, InventoryAction};

impl World {
    /// 按方向走 dt 模拟分钟；run 是按住了奔跑键。步速见 WALK_PACE、RUN_PACE。
    pub fn avatar_move(&mut self, direction: Point, run: bool, dt: f64) -> Result<()> {
        let actor_id = self.player_id().to_owned();
        let actor = actor_id.as_str();
        ensure!(
            direction.iter().all(|x| x.is_finite() && x.abs() <= 1.)
                && dt.is_finite()
                && (0.0..=10.0).contains(&dt), // 这一段的秒数 × 正常速度（模拟分钟 / 秒）
            KernelError::navigation("方向或移动步长无效")
        );
        let a = self
            .actors
            .get(actor)
            .ok_or_else(|| KernelError::action("尚未创建化身"))?;
        if !a.can_walk_freely() {
            return Ok(());
        }
        let map = self
            .walk_map
            .clone()
            .ok_or_else(|| KernelError::navigation("缺少行走地图"))?;
        let start = self
            .actor_spot(actor)
            .ok_or_else(|| KernelError::navigation("化身位置无效"))?;
        let n = direction[0].hypot(direction[1]).max(1.);
        let pace = if run { RUN_PACE } else { WALK_PACE };
        let d = direction.map(|v| v / n * map.metres_per_minute * pace * dt);
        let next = map.advance(&start, d, &self.avatar_obstacles());
        let a = self.actor_mut(actor);
        a.locus = next.locus();
        a.current.locale = next.locale;
        Ok(())
    }

    pub fn avatar_portal(&mut self, id: &str) -> Result<()> {
        let actor_id = self.player_id().to_owned();
        let actor = actor_id.as_str();
        let a = self
            .actors
            .get(actor)
            .ok_or_else(|| KernelError::action("尚未创建化身"))?;
        ensure!(
            a.interaction_available() && a.needs.can_move(),
            KernelError::action("请先停止当前活动")
        );
        let map = self
            .walk_map
            .clone()
            .ok_or_else(|| KernelError::navigation("缺少行走地图"))?;
        let portal = map
            .portals
            .iter()
            .find(|p| p.id == id)
            .ok_or_else(|| KernelError::navigation("门口不存在"))?;
        let here = self
            .actor_spot(actor)
            .ok_or_else(|| KernelError::navigation("化身不在场"))?;
        let obstacles = self.avatar_obstacles();
        ensure!(
            here.space == portal.from.space
                && distance(here.position, portal.from.position) <= REACH
                && map.visible(&here, &portal.from, &obstacles),
            KernelError::navigation("请走到门口")
        );
        let next = map
            .safe_near(&portal.to, &obstacles)
            .ok_or_else(|| KernelError::navigation("门内被阻挡"))?;
        let now = self.minutes;
        let a = self.actor_mut(actor);
        a.locus = next.locus();
        a.reset_idle(now, true);
        Ok(())
    }
    pub fn avatar_action(
        &mut self,
        id: &str,
        revision: u64,
        action: &ActionDraft,
    ) -> Result<protocol::ActionGroup> {
        let actor_id = self.player_id().to_owned();
        let actor = actor_id.as_str();
        ensure!(
            crate::intent::BuiltinVerb::parse(&action.intent.verb)
                != Some(crate::intent::BuiltinVerb::Goto),
            KernelError::action("请使用 WASD 行走")
        );
        if matches!(action.inventory, Some(InventoryAction::Drop { .. })) {
            let station = Reach::new(self)
                .drop_station()
                .ok_or_else(|| KernelError::inventory("请走近一个落脚点后放下物品"))?;
            self.player_control_mut().expect("玩家控制").drop_station = Some(station);
        }
        self.run_actions_from(actor, id, revision, std::slice::from_ref(action), true)
    }
    pub fn avatar_interact(
        &mut self,
        id: &str,
        revision: u64,
        command: &InteractionCommand,
    ) -> Result<Interaction> {
        let actor = self.player_id().to_owned();
        let result = self.interact_from(&actor, id, revision, command, true)?;
        self.actor_mut(&actor)
            .actions
            .player_interactions
            .insert(result.id.clone());
        Ok(result)
    }
    pub fn avatar_request_turn(&mut self, chat: &str, revision: u64) -> Result<()> {
        let actor_id = self.player_id().to_owned();
        let actor = actor_id.as_str();
        let a = self
            .actors
            .get(actor)
            .ok_or_else(|| KernelError::interaction("化身不存在"))?;
        ensure!(
            a.present() && a.actions.revision == revision && !a.needs.incapacitated(),
            KernelError::interaction("状态已改变")
        );
        let members = self.interactions.request_turn(chat, actor, self.minutes)?;
        for id in members {
            self.actor_mut(&id).actions.bump_revision();
        }
        Ok(())
    }
}
