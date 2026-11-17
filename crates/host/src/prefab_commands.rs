//! 预制开局是持久化的顺序计划。先冻结选择，再逐步将副作用和游标写入同一个 world.json；
//! 页面只请求推进游标，不再提交可变参数。断线重试、并发旧页面和进程重启都不能重复执行一步。
use crate::{
    network::Clients,
    runtime::{Outcome, Runtime},
    world_commands::randomized_game_mode,
};
use host::{
    world_settings::{validate_prefab_plan, validate_prefab_setup_id},
    HostError,
};
use protocol::{PrefabSetupPlan, PrefabSetupState, PrefabSetupStep, ServerMsg};

impl Runtime {
    pub(crate) fn begin_prefab_setup(
        &mut self,
        request_id: String,
        setup_id: String,
        expected_revision: u64,
        plan: PrefabSetupPlan,
    ) -> Outcome {
        let result = self.check_prefab_begin(&setup_id, expected_revision, &plan);
        let result = result.and_then(|new| {
            if !new {
                return Ok(());
            }
            self.transact(|rt| {
                rt.speed = 0.0;
                rt.world_settings.prefab_setup = Some(PrefabSetupState {
                    id: setup_id,
                    plan,
                    next_step: 0,
                    joined: Vec::new(),
                });
                rt.world_settings.revision += 1;
                Ok::<_, HostError>(())
            })
            .map_err(|e| e.to_string())
        });
        self.prefab_reply(request_id, result)
    }

    /// 返回 false 是同一请求的重发；无标记的历史世界只能按原样继续，不猜测玩家的旧选择。
    fn check_prefab_begin(
        &self,
        setup_id: &str,
        expected_revision: u64,
        plan: &PrefabSetupPlan,
    ) -> Result<bool, String> {
        validate_prefab_setup_id(setup_id).map_err(|e| e.to_string())?;
        validate_prefab_plan(plan).map_err(|e| e.to_string())?;
        if let Some(current) = &self.world_settings.prefab_setup {
            if current.id == setup_id
                && serde_json::to_value(&current.plan).ok() == serde_json::to_value(plan).ok()
            {
                return Ok(false);
            }
            return Err("这一世界已有开局计划，请按已保存的选择继续".into());
        }
        if expected_revision != self.world_settings.revision {
            return Err("世界设定已被其他页面修改，请重新读取".into());
        }
        if !self.world_settings.worldview.trim().is_empty()
            || !self.population.residents.is_empty()
            || self.world.game_mode().is_some()
        {
            return Err("只能为尚未设置的新世界开始预制开局，不会覆盖已有世界".into());
        }
        Ok(true)
    }

    pub(crate) fn advance_prefab_setup(
        &mut self,
        request_id: String,
        setup_id: String,
        next_step: usize,
        clients: &Clients,
    ) -> Outcome {
        let result = self.check_prefab_step(&setup_id, next_step);
        let result = result.and_then(|step| {
            let Some(step) = step else { return Ok(()) };
            self.transact(|rt| {
                let joined = rt.apply_prefab_step(step, format!("{setup_id}:{next_step}"))?;
                let setup = rt
                    .world_settings
                    .prefab_setup
                    .as_mut()
                    .expect("上面已核对计划");
                if let Some(joined) = joined {
                    setup.joined.push(joined);
                }
                setup.next_step += 1;
                rt.world_settings.revision += 1;
                rt.speed = 0.0;
                Ok::<_, HostError>(())
            })
            .map_err(|e| e.to_string())
        });
        if result.is_ok() {
            // 和普通入住一样，只有提交成功后才发布安置产生的世界事件；暂停时 tick 不会替我们取走。
            let events = self.world.take_events();
            self.driver.dispatch(&self.world, events, clients);
        }
        self.prefab_reply(request_id, result)
    }

    fn check_prefab_step(
        &self,
        setup_id: &str,
        next_step: usize,
    ) -> Result<Option<PrefabSetupStep>, String> {
        let current = self
            .world_settings
            .prefab_setup
            .as_ref()
            .ok_or("这个世界没有待继续的预制开局")?;
        if current.id != setup_id {
            return Err("开局编号已变化，请重新读取世界".into());
        }
        if next_step > current.next_step {
            return Err("开局进度尚未到这一步，请重新读取".into());
        }
        if next_step < current.next_step || current.complete() {
            return Ok(None);
        }
        Ok(Some(current.plan.steps[next_step].clone()))
    }

    fn prefab_reply(&self, request_id: String, result: Result<(), String>) -> Outcome {
        Outcome::none()
            .and_all(self.world_settings_msg())
            .and_all(self.population_msg())
            .and_all(self.roster())
            .and_reply(ServerMsg::PrefabSetupSaved {
                request_id,
                ok: result.is_ok(),
                message: result.err().unwrap_or_else(|| "开局进度已保存".into()),
                state: self.world_settings.prefab_setup.clone(),
            })
    }

    /// 仅调用各功能的内存修改部分，由上层唯一事务负责持久化和回滚。
    fn apply_prefab_step(
        &mut self,
        step: PrefabSetupStep,
        op_id: String,
    ) -> Result<Option<String>, HostError> {
        use PrefabSetupStep::*;
        match step {
            Worldview { text } => {
                let next = self.check_worldview(self.world_settings.revision, &text)?;
                self.apply_worldview(next)?;
            }
            Physiology { switches } => self
                .set_physiology(self.world_settings.revision, switches)
                .map_err(HostError::Rejected)?,
            Climate { climate } => self.world.set_climate(climate)?,
            Weather { weather } => {
                let current = self
                    .world
                    .weather()
                    .ok_or_else(|| HostError::Rejected("此地图没有天气".into()))?;
                self.world.set_weather(kernel::weather::WeatherRequest {
                    request_id: op_id,
                    expected_revision: current.view.revision,
                    mode: protocol::WeatherMode::Fixed,
                    kind: Some(weather),
                })?;
            }
            RemoveProp { id } => {
                // 生成器版本不同可能已经没有这件；只略过不存在，不吞掉容器仍有物品等真实错误。
                if self.world.topo.prop(&id).is_some() {
                    self.world.remove_prop(&id)?;
                }
            }
            PlaceProp { instance, near } => {
                let placement = self
                    .library_placement(instance)
                    .map_err(HostError::Rejected)?;
                self.world.place_prop_near(placement, near.as_ref())?;
            }
            Limits { limits } => {
                let current = protocol::AgentLimits::from(&self.driver.runtime.state().limits);
                let mut value = serde_json::to_value(current).expect("额度可序列化");
                let target = value.as_object_mut().expect("额度是对象");
                for (key, value) in limits
                    .as_object()
                    .ok_or_else(|| HostError::Rejected("额度必须是对象".into()))?
                {
                    if !target.contains_key(key) {
                        return Err(HostError::Rejected(format!("未知额度：{key}")));
                    }
                    target.insert(key.clone(), value.clone());
                }
                let limits = serde_json::from_value(value)
                    .map_err(|e| HostError::Rejected(format!("额度无效：{e}")))?;
                self.driver.runtime.set_agent_limits(&limits)?;
            }
            Join {
                template_id,
                model,
                persona,
                look,
            } => {
                return self
                    .admit_prefab(op_id, template_id, model, persona, look.map(|look| *look))
                    .map(Some)
                    .map_err(HostError::Rejected);
            }
            GameMode { choice } => self
                .world
                .set_game_mode(Some(&randomized_game_mode(choice)))?,
        }
        Ok(None)
    }
}
