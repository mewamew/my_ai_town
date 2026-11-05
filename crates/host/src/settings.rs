//! 模型配置与村民设定命令；返回待发送的消息，模拟循环负责发送。村民一律按居民登记查找。
//! 村民设定（含身体数值）的写操作回 AgentSaved，模型服务与额度回 ConfigSaved，都带命令的请求编号、只发给发出者；
//! 读取失败回通用 Error。
use crate::{
    network::{send_to, Clients},
    runtime::{error_msg, Outcome, Runtime},
};
use host::{application::Application, builtin, config, llm::LlmTarget, models, HostError};
use kernel::{default_tuning, needs::NeedValues};
use protocol::{
    ActiveModelChoice, AgentLimits, BodyValues, ModelChoice, NotebookDetailQuery, NotebookQuery,
    ProviderConfigMsg, ProviderKeyMsg, ServerMsg,
};
use std::collections::BTreeSet;

pub(crate) struct Settings {
    pub providers: config::ProvidersFile,
    pub credentials: config::Credentials,
    providers_path: String,
    credentials_path: String,
    /// 应用带着内置模型的推理程序。
    builtin: bool,
}

impl Settings {
    /// 村民要用的模型能不能选：模型名不空、服务在配置里。入住时选和设定里换都按它。
    pub(crate) fn check_choice(&self, model: &ModelChoice) -> Result<(), String> {
        if model.model.trim().is_empty() {
            return Err("模型名不能为空".into());
        }
        if model.provider == builtin::PROVIDER && self.builtin {
            return Ok(());
        }
        if !self
            .providers
            .providers
            .iter()
            .any(|p| p.id == model.provider)
        {
            return Err(format!("模型服务尚未配置：{}", model.provider));
        }
        Ok(())
    }

    /// 村民的模型现在为什么还用不了，给玩家看；能用时为 None。没选模型、选的服务已删、
    /// 服务没有地址、远程服务还没填密钥都算；本机和局域网里的服务不用密钥。
    pub(crate) fn missing_model(&self, binding: Option<&ModelChoice>) -> Option<String> {
        let Some(choice) = binding.filter(|c| !c.model.trim().is_empty()) else {
            return Some("还没有选模型".into());
        };
        if choice.provider == builtin::PROVIDER {
            if !self.builtin {
                return Some(format!(
                    "这个版本没有带{}，到设定里换一个模型",
                    builtin::NAME
                ));
            }
            return (!builtin::ready()).then(|| format!("{}还没下载好", builtin::NAME));
        }
        let Some(entry) = self
            .providers
            .providers
            .iter()
            .find(|p| p.id == choice.provider)
        else {
            return Some("选的模型服务已经删掉了".into());
        };
        let name = self.provider_name(&choice.provider);
        if entry.base_url.trim().is_empty() {
            return Some(format!("{name} 还没有填服务地址"));
        }
        let keyless = local_endpoint(&entry.base_url);
        if !keyless
            && self
                .credentials
                .get(&choice.provider)
                .is_none_or(|k| k.is_empty())
        {
            return Some(format!("{name} 还没有填密钥"));
        }
        None
    }

    /// 村民选的模型怎么调用；服务不在配置里时为 None。内置模型没有地址，文件位置开镇时记在 builtin 里。
    pub(crate) fn target(&self, choice: &ModelChoice) -> Option<LlmTarget> {
        if choice.provider == builtin::PROVIDER {
            return self.builtin.then(|| LlmTarget {
                provider: choice.provider.clone(),
                model: choice.model.clone(),
                base_url: String::new(),
                api_key: None,
            });
        }
        LlmTarget::configured(
            &self.providers,
            &self.credentials,
            &choice.provider,
            &choice.model,
        )
    }

    /// 服务的显示名；配置里没写名字时用编号。
    pub(crate) fn provider_name(&self, id: &str) -> String {
        if id == builtin::PROVIDER {
            return builtin::NAME.into();
        }
        self.providers
            .providers
            .iter()
            .find(|p| p.id == id)
            .map(|p| p.name.trim())
            .filter(|name| !name.is_empty())
            .unwrap_or(id)
            .to_owned()
    }

    /// 文件不存在等于空配置；存在但损坏时报错，由启动流程退出。
    pub(crate) fn load(app: &Application) -> Result<Self, HostError> {
        Ok(Self {
            providers: config::load_providers(&app.providers_path)?,
            credentials: config::load_credentials(&app.credentials_path)?,
            providers_path: app.providers_path.clone(),
            credentials_path: app.credentials_path.clone(),
            builtin: builtin::configure(app),
        })
    }

    /// 首页「设定」不经过世界进程直接改文件：回读和保存前先从磁盘重读
    fn reload(&mut self) -> Result<(), HostError> {
        self.providers = config::load_providers(&self.providers_path)?;
        self.credentials = config::load_credentials(&self.credentials_path)?;
        Ok(())
    }

    fn save_models(
        &mut self,
        new: config::ProvidersFile,
        keys: Vec<ProviderKeyMsg>,
    ) -> Result<(), HostError> {
        self.credentials = models::save(&self.providers_path, &self.credentials_path, &new, keys)?;
        self.providers = new;
        Ok(())
    }
}

impl Runtime {
    /// 按 id 或姓名找村民后执行；找不到时把原因交给调用方决定回执类型。
    fn with_resident<T>(
        &mut self,
        target: Option<&str>,
        f: impl FnOnce(&mut Self, &str) -> T,
    ) -> Result<T, HostError> {
        let id = self.population.find(target)?.id.clone();
        Ok(f(self, &id))
    }

    /// 读操作：找不到村民或读取失败回通用错误。
    fn read_resident(
        &mut self,
        target: Option<&str>,
        f: impl FnOnce(&mut Self, &str) -> ServerMsg,
    ) -> Outcome {
        Outcome::reply(
            self.with_resident(target, f)
                .unwrap_or_else(|e| error_msg(e.to_string())),
        )
    }

    pub(crate) fn chat_history(
        &mut self,
        resident: &str,
        request_id: String,
        chat_id: Option<String>,
        offset: usize,
    ) -> Outcome {
        if self.world.actor(resident).is_some_and(|a| a.is_avatar()) {
            return Outcome::reply(
                self.world
                    .chat_history(resident, request_id, chat_id, offset),
            );
        }
        self.read_resident(Some(resident), |rt, id| {
            rt.world.chat_history(id, request_id, chat_id, offset)
        })
    }

    pub(crate) fn agent_config(&mut self, resident: Option<&str>) -> Outcome {
        self.read_resident(resident, |rt, id| rt.agent_config_msg(id))
    }

    pub(crate) fn diary(&mut self, resident: Option<&str>) -> Outcome {
        self.read_resident(resident, |rt, id| ServerMsg::Diary {
            resident: rt.population.residents[id].name.clone(),
            days: rt.world.diary(id),
        })
    }

    pub(crate) fn notebook(
        &mut self,
        resident: String,
        request_id: String,
        query: &NotebookQuery,
    ) -> Outcome {
        let result = self.population.find(Some(&resident)).and_then(|r| {
            Ok(self
                .driver
                .runtime
                .notebook_view(&self.world, &r.id, query)?)
        });
        let (notebook, error) = match result {
            Ok(view) => (view.map(Box::new), None),
            Err(e) => (None, Some(e.to_string())),
        };
        Outcome::reply(ServerMsg::Notebook {
            resident,
            request_id,
            notebook,
            error,
        })
    }

    pub(crate) fn notebook_detail(
        &mut self,
        resident: String,
        request_id: String,
        query: &NotebookDetailQuery,
    ) -> Outcome {
        let result = self.population.find(Some(&resident)).and_then(|r| {
            Ok(self
                .driver
                .runtime
                .notebook_detail(&self.world, &r.id, query)?)
        });
        let (detail, error) = match result {
            Ok(view) => (Some(Box::new(view)), None),
            Err(e) => (None, Some(e.to_string())),
        };
        Outcome::reply(ServerMsg::NotebookDetail {
            resident,
            request_id,
            detail,
            error,
        })
    }

    /// 只改本人采用的人设快照，不回写村民库模板。
    pub(crate) fn set_persona(
        &mut self,
        request_id: String,
        resident: &str,
        text: String,
    ) -> Outcome {
        let result = self.with_resident(Some(resident), |rt, id| {
            let common = rt.world_settings.worldview.clone();
            config::check_no_secret(&text)
                .and_then(|()| rt.driver.set_persona(&mut rt.world, id, &text, &common))?;
            rt.population.residents.get_mut(id).unwrap().persona = text;
            Ok(id.to_string())
        });
        self.agent_update(
            request_id,
            result.and_then(|r| r),
            "人设已保存，下一次请求生效",
        )
    }

    /// 观察者调身体数值：世界在跑时不收，免得正在做的事被突然改掉。调完的数值随名册广播；
    /// 观察日志那一笔当场发出去，暂停时世界不推进，不会自己发。
    pub(crate) fn set_resident_body(
        &mut self,
        request_id: String,
        resident: &str,
        values: BodyValues,
        clients: &Clients,
    ) -> Outcome {
        if self.speed > 0.0 {
            let paused = HostError::Rejected("先暂停世界再调身体".into());
            return Outcome::reply(agent_saved(request_id, Err(paused), ""));
        }
        let values = NeedValues {
            fullness: values.fullness,
            energy: values.energy,
            water: values.water,
            health: values.health,
        };
        let result = self
            .with_resident(Some(resident), |rt, id| rt.world.adjust_body(id, values))
            .and_then(|adjusted| adjusted.map_err(HostError::from));
        let events = self.world.take_events();
        self.driver.dispatch(&self.world, events, clients);
        match result {
            Ok(text) => Outcome::reply(agent_saved(request_id, Ok(()), &text))
                .and_all(self.roster())
                .persisted(),
            Err(error) => Outcome::reply(agent_saved(request_id, Err(error), "")),
        }
    }

    pub(crate) fn set_agent_limits(&mut self, request_id: String, limits: AgentLimits) -> Outcome {
        match self.driver.runtime.set_agent_limits(&limits) {
            Ok(()) => Outcome::reply(config_saved(
                request_id,
                Ok(()),
                "花费上限已保存，马上生效；因为到了上限而暂停的话，回地图点「开始」接着跑",
            ))
            .and_all(self.driver.limits_view(&self.world))
            .persisted(),
            Err(error) => Outcome::reply(config_saved(request_id, Err(error.into()), "")),
        }
    }

    pub(crate) fn model_config_msg(&self) -> ServerMsg {
        ServerMsg::ModelConfig {
            active: self.settings.providers.active.clone(),
            providers: models::views(
                &self.settings.providers,
                &self.settings.credentials,
                self.settings.builtin,
            ),
            builtin_stale: builtin::stale(),
        }
    }

    /// 换上小镇开着时下好的内置模型新版：停掉服务，下一次请求用新文件重新起。
    pub(crate) fn restart_builtin_model(&mut self, request_id: String) -> Outcome {
        builtin::restart();
        Outcome::reply(config_saved(request_id, Ok(()), "已换上新版内置模型"))
            .and_all(self.model_config_msg())
    }

    /// 回读前先从磁盘重读：首页「设定」可能刚连上了模型
    pub(crate) fn model_config(&mut self) -> Outcome {
        if let Err(error) = self.settings.reload() {
            return Outcome::reply(error_msg(error.to_string()));
        }
        self.driver
            .set_target(&self.settings.providers, &self.settings.credentials);
        Outcome::reply(self.model_config_msg())
    }

    /// 村民模型随当前世界存档；服务端配置与密钥仍保持全局且彼此隔离。
    pub(crate) fn set_resident_model(
        &mut self,
        request_id: String,
        resident: &str,
        model: ModelChoice,
    ) -> Outcome {
        let result = self
            .population
            .find(Some(resident))
            .map(|r| r.id.clone())
            .and_then(|id| {
                self.settings
                    .check_choice(&model)
                    .map_err(HostError::Rejected)?;
                self.population
                    .residents
                    .get_mut(&id)
                    .unwrap()
                    .model_binding = Some(model);
                self.population.revision += 1;
                Ok(id)
            });
        // 人口视图里带着各人的模型，页面的「还没选模型」提示跟着变
        let saved = result.is_ok();
        let outcome = self.agent_update(request_id, result, "使用模型已保存，下一次请求生效");
        if saved {
            outcome.and_all(self.population_msg())
        } else {
            outcome
        }
    }

    /// 模型换了会体现在 world_settings 里，一并广播。
    pub(crate) fn set_model_config(
        &mut self,
        request_id: String,
        active: Option<ActiveModelChoice>,
        mut providers: Vec<ProviderConfigMsg>,
        keys: Vec<ProviderKeyMsg>,
    ) -> Outcome {
        // 页面把回读到的整表带回来，内置模型也在里面；它不进配置文件，也删不掉
        providers.retain(|provider| provider.id != builtin::PROVIDER);
        let mut provider_ids: BTreeSet<_> = providers
            .iter()
            .map(|provider| provider.id.as_str())
            .collect();
        if self.settings.builtin {
            provider_ids.insert(builtin::PROVIDER);
        }
        let affected: Vec<_> = self
            .population
            .ordered()
            .into_iter()
            .filter_map(|resident| {
                let choice = resident.model_binding.as_ref()?;
                (!provider_ids.contains(choice.provider.as_str()))
                    .then(|| format!("{}（{}）", resident.name, choice.provider))
            })
            .collect();
        if !affected.is_empty() {
            let error = HostError::Rejected(format!(
                "不能删除仍被村民使用的模型服务：{}",
                affected.join("、")
            ));
            return Outcome::reply(config_saved(request_id, Err(error), ""));
        }
        let file = config::ProvidersFile { active, providers };
        match self
            .settings
            .reload()
            .and_then(|()| self.settings.save_models(file, keys))
        {
            Ok(()) => {
                self.driver
                    .set_target(&self.settings.providers, &self.settings.credentials);
                Outcome::reply(config_saved(request_id, Ok(()), "配置已保存"))
                    .and_all(self.model_config_msg())
                    .and_all(self.world_settings_msg())
            }
            Err(error) => Outcome::reply(config_saved(request_id, Err(error), "")),
        }
    }

    /// 与正式调用同一条 HTTP 通道；在有界池里跑，队列满了立刻回失败。结果只发给发出测试的连接。
    pub(crate) fn test_connection(
        &self,
        test: ConnectionTest,
        connection: u64,
        clients: &Clients,
    ) -> Outcome {
        let ConnectionTest {
            request_id,
            provider,
            model,
            api_key,
        } = test;
        let saved = self.settings.credentials.clone();
        let clients = clients.clone();
        let id = request_id.clone();
        let tested = provider.clone();
        let submitted = self.tasks.submit(move || {
            let outcome = models::test(&tested, model, api_key, &saved);
            send_to(
                &clients,
                connection,
                &ServerMsg::ModelTestResult {
                    request_id: id,
                    provider: tested.id,
                    ok: outcome.ok,
                    message: outcome.message,
                    latency_ms: outcome.latency_ms,
                },
            );
        });
        match submitted {
            Ok(()) => Outcome::none(),
            Err(error) => Outcome::reply(ServerMsg::ModelTestResult {
                request_id,
                provider: provider.id,
                ok: false,
                message: error.to_string(),
                latency_ms: 0,
            }),
        }
    }

    /// 村民设定改动的结果：回执给发出者；成功时这位村民的新设定广播给所有连接，改动随后存盘。
    fn agent_update(
        &self,
        request_id: String,
        result: Result<String, HostError>,
        success: &str,
    ) -> Outcome {
        match result {
            Ok(id) => Outcome::reply(agent_saved(request_id, Ok(()), success))
                .and_all(self.agent_config_msg(&id))
                .persisted(),
            Err(error) => Outcome::reply(agent_saved(request_id, Err(error), "")),
        }
    }

    /// 村民设定回读：采用的人设快照 + 当前需求参数（信息栏画需求分界用）。
    fn agent_config_msg(&self, id: &str) -> ServerMsg {
        let resident = &self.population.residents[id];
        ServerMsg::AgentConfig {
            resident_id: resident.id.clone(),
            resident: resident.name.clone(),
            persona: resident.persona.clone(),
            tuning: self
                .world
                .actor(id)
                .map_or_else(default_tuning, |a| a.needs.tuning),
            health_marks: [
                kernel::needs::HEALTH_CRITICAL,
                kernel::needs::HEALTH_DANGER,
                kernel::needs::HEALTH_GOOD,
            ],
            model_binding: resident.model_binding.clone(),
        }
    }
}

/// 一次连接测试：服务商、模型名与可选的临时密钥。
pub(crate) struct ConnectionTest {
    pub request_id: String,
    pub provider: ProviderConfigMsg,
    pub model: String,
    pub api_key: Option<String>,
}

fn agent_saved(request_id: String, result: Result<(), HostError>, success: &str) -> ServerMsg {
    let (ok, message) = match result {
        Ok(()) => (true, success.into()),
        Err(error) => (false, error.to_string()),
    };
    ServerMsg::AgentSaved {
        request_id,
        ok,
        message,
    }
}

fn config_saved(request_id: String, result: Result<(), HostError>, success: &str) -> ServerMsg {
    let (ok, message) = match result {
        Ok(()) => (true, success.into()),
        Err(error) => (false, error.to_string()),
    };
    ServerMsg::ConfigSaved {
        request_id,
        ok,
        message,
    }
}

/// 本机或局域网地址上的服务（Ollama、LM Studio 这类），不用密钥也能请求。
fn local_endpoint(base_url: &str) -> bool {
    let rest = base_url
        .split_once("://")
        .map_or(base_url, |(_, rest)| rest);
    let authority = rest.split('/').next().unwrap_or_default();
    let host = match authority.strip_prefix('[') {
        Some(v6) => v6.split(']').next().unwrap_or_default(),
        None => authority.split(':').next().unwrap_or_default(),
    }
    .to_ascii_lowercase();
    if host == "localhost" || host.ends_with(".localhost") || host.ends_with(".local") {
        return true;
    }
    match host.parse::<std::net::IpAddr>() {
        Ok(std::net::IpAddr::V4(ip)) => {
            ip.is_loopback() || ip.is_private() || ip.is_link_local() || ip.is_unspecified()
        }
        Ok(std::net::IpAddr::V6(ip)) => ip.is_loopback() || ip.is_unspecified(),
        Err(_) => false,
    }
}
