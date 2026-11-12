//! 正式 host 的 Agent 驱动：请求交给有界网络池，会话按居民登记建立。请求状态随周期存盘落盘，
//! 发之前不等存盘：强杀后读回的是更早的状态，没存上的请求当没发过（读档后世界代次加一，
//! 旧进程的回复对不上号），那几次的预留用量也不记。
use crate::{
    network::{broadcast_event, Clients},
    settings::Settings,
    startup::Mode,
};
use agent::{
    budget::Limits,
    completion::ModelError,
    runtime::{AgentRequest, ResidentRuntime},
};
use host::{
    agent_worker::{AgentSave, Work, WorkerPool},
    config,
    llm::LlmTarget,
    population::Population,
    world_settings::instructions,
    HostError,
};
use kernel::{Event, World};
use protocol::{AgentLimits, EventInfo, ResidentUsage, ServerMsg};
use serde_json::json;
use std::{
    collections::BTreeMap,
    fs::{self, File},
    io::{BufWriter, Write},
    time::Duration,
};

pub(crate) struct ResidentDriver {
    pub runtime: ResidentRuntime,
    pub target: LlmTarget,
    /// 固定回复池：不要求配置模型服务
    pub mock: bool,
    pool: WorkerPool,
    log: BufWriter<File>,
}
impl ResidentDriver {
    /// 同一世界共享运行器和工作池；每条请求在入队时解析模型目标。
    pub fn build(
        world: &mut World,
        population: &Population,
        common: &str,
        mode: &Mode,
        settings: &Settings,
        saved: Option<AgentSave>,
    ) -> Result<Self, HostError> {
        let (target, mock) = match mode {
            Mode::MockLlm { delay } => (
                LlmTarget {
                    provider: "mock".into(),
                    model: "agent-wiring-fixture".into(),
                    ..Default::default()
                },
                Some(*delay),
            ),
            Mode::Llm => (target(&settings.providers, &settings.credentials), None),
        };
        Self::new(world, population, common, target, mock, saved)
    }
    /// 存档里的会话在这里恢复成运行器，整个启动流程只恢复这一次。
    pub fn new(
        world: &mut World,
        population: &Population,
        common: &str,
        target: LlmTarget,
        mock: Option<Duration>,
        saved: Option<AgentSave>,
    ) -> Result<Self, HostError> {
        let mut runtime = match saved {
            Some(saved) => ResidentRuntime::restore(saved.runtime, world)?,
            None => ResidentRuntime::new(Limits::default())?,
        };
        for resident in population.residents.values() {
            runtime.register(
                world,
                &resident.id,
                &instructions(&resident.persona, common),
            )?;
        }
        let log_dir = host::application::log_dir();
        fs::create_dir_all(&log_dir)
            .map_err(|e| HostError::Io(format!("创建日志目录 {} 失败：{e}", log_dir.display())))?;
        let stamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_err(|e| HostError::Io(e.to_string()))?
            .as_millis();
        let path = log_dir.join(format!(
            "resident-agent-{stamp}-{}.jsonl",
            std::process::id()
        ));
        let log =
            BufWriter::new(File::create(&path).map_err(|e| {
                HostError::Io(format!("创建 Agent 轨迹 {} 失败：{e}", path.display()))
            })?);
        println!(
            "[host] 村民 Agent 已接入；完整工具轨迹 → {}",
            path.display()
        );
        let is_mock = mock.is_some();
        let pool = WorkerPool::new(runtime.state().limits.max_concurrent, mock);
        Ok(Self {
            runtime,
            target,
            mock: is_mock,
            pool,
            log,
        })
    }
    pub fn receive(&mut self, world: &mut World, clients: &Clients) -> Result<bool, HostError> {
        let mut received = false;
        while let Ok(result) = self.pool.results.try_recv() {
            received = true;
            let event = format!(
                "Agent 响应 #{}（{:.2}s）",
                result.id,
                result.latency_ms as f64 / 1000.0
            );
            self.runtime.on_reply(
                world,
                &result.actor,
                result.id,
                result.epoch,
                result.reply,
                result.latency_ms,
            );
            broadcast_event(clients, world, event, EventInfo::model());
        }
        self.flush_trace()?;
        Ok(received)
    }
    pub fn send(
        &mut self,
        world: &mut World,
        requests: Vec<AgentRequest>,
        population: &Population,
        settings: &Settings,
        clients: &Clients,
    ) -> Result<(), HostError> {
        let mut request_targets = BTreeMap::new();
        for request in requests {
            let actor = request.actor_id.clone();
            let id = request.stamp.id;
            let epoch = request.stamp.epoch;
            let target = if self.mock {
                Ok(self.target.clone())
            } else {
                resident_target(&actor, population, settings)
            };
            broadcast_event(
                clients,
                world,
                format!("Agent 请求 #{id}（{actor}）"),
                EventInfo::model(),
            );
            let target = match target {
                Ok(target) => target,
                Err(error) => {
                    self.runtime
                        .on_reply(world, &actor, id, epoch, Err(error), 0);
                    continue;
                }
            };
            request_targets.insert(id, target.clone());
            let work = Work { request, target };
            if let Err(error) = self.pool.submit(work) {
                self.runtime
                    .on_reply(world, &actor, id, epoch, Err(error), 0);
            }
        }
        self.flush_trace_with_targets(&request_targets)
    }
    /// 还没有能用模型的村民与原因；固定回复池不需要模型。
    pub fn missing_models(
        &self,
        population: &Population,
        settings: &Settings,
    ) -> BTreeMap<String, String> {
        if self.mock {
            return BTreeMap::new();
        }
        population
            .residents
            .values()
            .filter_map(|r| {
                let reason = settings.missing_model(r.model_binding.as_ref())?;
                Some((r.id.clone(), reason))
            })
            .collect()
    }
    /// 世界日志只转发给观察仪；请求时机由运行器的 poll 决定。
    pub fn dispatch(&mut self, world: &World, events: Vec<Event>, clients: &Clients) {
        for event in events {
            let Event::Log {
                minutes,
                text,
                info,
            } = event;
            broadcast_event(
                clients,
                world,
                format!("[{}] {text}", kernel::clock_string(minutes)),
                info,
            );
        }
    }
    pub fn roster(&self, world: &World, speed: f64) -> ServerMsg {
        let mut message = world.roster(speed);
        if let ServerMsg::Roster { locales, .. } = &mut message {
            for member in locales.iter_mut().flat_map(|l| &mut l.members) {
                member.resident_agent = self.runtime.view(world, &member.id);
            }
        }
        message
    }
    fn resident_rows(&self, world: &World) -> Vec<ResidentUsage> {
        self.runtime
            .state()
            .sessions
            .values()
            .map(|s| s.usage(world))
            .collect()
    }
    /// 消耗页：汇总、按人用量与最近请求台账，新的在前。只含村民请求。
    pub fn usage_view(&self, world: &World) -> ServerMsg {
        let state = self.runtime.state();
        let residents = self.resident_rows(world);
        let summary = protocol::UsageSummary {
            today_calls: residents.iter().map(|r| r.daily_calls).sum(),
            today_tokens: residents.iter().map(|r| r.daily_tokens).sum(),
            today_input_tokens: residents.iter().map(|r| r.daily_input_tokens).sum(),
            today_cache_hit_tokens: residents.iter().map(|r| r.daily_cache_hit_tokens).sum(),
            lifetime_calls: state.lifetime.calls,
            lifetime_tokens: state.lifetime.tokens,
            lifetime_input_tokens: state.lifetime.input_tokens,
            lifetime_cache_hit_tokens: state.lifetime.cache_hit_tokens,
            calls_per_day: state.limits.calls_per_day,
            tokens_per_day: state.limits.tokens_per_day,
            total_calls: state.limits.total_calls,
            total_tokens: state.limits.total_tokens,
            in_flight: residents.iter().filter(|r| r.in_flight).count() as u64,
        };
        let requests = self
            .runtime
            .requests()
            .iter()
            .rev()
            .map(|r| r.view(world))
            .collect();
        ServerMsg::Usage {
            summary,
            residents,
            requests,
        }
    }
    pub fn limits_view(&self, world: &World) -> ServerMsg {
        let state = self.runtime.state();
        ServerMsg::AgentLimits {
            limits: AgentLimits::from(&state.limits),
            ranges: state.limits.ranges(),
            usage: protocol::AgentUsage {
                lifetime_calls: state.lifetime.calls,
                lifetime_tokens: state.lifetime.tokens,
                residents: self.resident_rows(world),
            },
        }
    }
    /// 新人入村或个人设定改人设：只影响本人后续请求。
    pub fn set_persona(
        &mut self,
        world: &mut World,
        id: &str,
        persona: &str,
        common: &str,
    ) -> Result<(), HostError> {
        Ok(self
            .runtime
            .register(world, id, &instructions(persona, common))?)
    }
    /// 设置页面换模型后立即生效，已在途的请求仍用旧目标。
    pub fn set_target(
        &mut self,
        providers: &config::ProvidersFile,
        credentials: &config::Credentials,
    ) {
        self.target = target(providers, credentials);
    }
    pub fn flush_trace(&mut self) -> Result<(), HostError> {
        self.flush_trace_with_targets(&BTreeMap::new())
    }

    fn flush_trace_with_targets(
        &mut self,
        request_targets: &BTreeMap<u64, LlmTarget>,
    ) -> Result<(), HostError> {
        let records = self.runtime.drain_trace();
        if records.is_empty() {
            return Ok(());
        }
        for record in records {
            let model_snapshot = (record.event == "request")
                .then(|| record.request_id.and_then(|id| request_targets.get(&id)))
                .flatten()
                .map(|target| {
                    json!({
                        "provider": target.provider,
                        "model": target.model,
                    })
                });
            serde_json::to_writer(
                &mut self.log,
                &json!({"trace":record,"model_snapshot":model_snapshot}),
            )
            .map_err(|e| HostError::Io(format!("写 Agent 轨迹失败：{e}")))?;
            self.log
                .write_all(b"\n")
                .map_err(|e| HostError::Io(format!("写 Agent 轨迹失败：{e}")))?;
        }
        self.log
            .flush()
            .map_err(|e| HostError::Io(format!("写 Agent 轨迹失败：{e}")))
    }
}

/// 设定中心选的小镇工具模型；没选时是空目标，调用时报未配置端点。
fn target(providers: &config::ProvidersFile, credentials: &config::Credentials) -> LlmTarget {
    LlmTarget::active(providers, credentials).unwrap_or_default()
}

/// 村民自己绑定的模型。不静默改用默认模型：用不了的村民每拍由 `missing_models` 停在等模型上，
/// 不会走到这里；万一走到，按没发出的请求处理。
fn resident_target(
    actor: &str,
    population: &Population,
    settings: &Settings,
) -> Result<LlmTarget, ModelError> {
    let binding = population
        .residents
        .get(actor)
        .and_then(|resident| resident.model_binding.as_ref());
    if let Some(reason) = settings.missing_model(binding) {
        return Err(ModelError::NotSent(reason));
    }
    let Some(choice) = binding else {
        return Err(ModelError::NotSent("还没有选模型".into()));
    };
    settings.target(choice).ok_or_else(|| {
        ModelError::NotSent(format!(
            "绑定的模型服务不存在：{}，请到设定中心重新设置",
            choice.provider
        ))
    })
}
