//! 启动参数与初始世界。参数解析出错返回 Err，由 main 打印后退出，不 panic。
use host::{
    application::Application,
    population::{Population, Registration},
    world_settings::{instructions_chars, valid_speed, INSTRUCTIONS_MAX_CHARS},
    HostError,
};
use kernel::{avatar::WalkMap, default_tuning, weather::WeatherRules, World};
use protocol::NeedRules;
use std::{path::PathBuf, sync::Arc, time::Duration};

pub(crate) enum Mode {
    /// 真实模型（缺省）
    Llm,
    /// 固定回复源：离线演示等待与接续
    MockLlm { delay: Duration },
}

pub(crate) struct Args {
    pub port: u16,
    pub speed: Option<f64>,
    pub mode: Mode,
    pub save_file: Option<PathBuf>,
    /// 缺省用配置文件的 topology_path。
    pub map_document: Option<String>,
    pub town_id: Option<String>,
    pub ready_file: Option<PathBuf>,
    pub connection_token: Option<String>,
    /// 管理进程启动时传入：stdin 关闭即视为父进程退出，保存后退出。
    pub stop_on_stdin_close: bool,
    /// 周期存盘隔多久一次；缺省用存档的 `AUTOSAVE_INTERVAL`。
    pub autosave: Option<Duration>,
}

impl Args {
    pub(crate) fn parse(app: &Application) -> Result<Self, HostError> {
        Self::from_iter(app, std::env::args().skip(1))
    }

    fn from_iter(app: &Application, args: impl Iterator<Item = String>) -> Result<Self, HostError> {
        let mut a = Args {
            port: app.port,
            speed: None,
            mode: Mode::Llm,
            save_file: None,
            map_document: None,
            town_id: None,
            ready_file: None,
            connection_token: None,
            stop_on_stdin_close: false,
            autosave: None,
        };
        let mut save_enabled = true;
        let mut mock_delay = Duration::from_secs(3);
        let mut mock = false;
        let mut it = args;
        while let Some(arg) = it.next() {
            let mut value = || {
                it.next()
                    .ok_or_else(|| HostError::Runtime(format!("{arg} 缺少参数值")))
            };
            match arg.as_str() {
                "--map-document" => a.map_document = Some(value()?),
                "--town-id" => a.town_id = Some(value()?),
                "--ready-file" => a.ready_file = Some(PathBuf::from(value()?)),
                "--connection-token" => a.connection_token = Some(value()?),
                "--port" => a.port = parse_number(&arg, &value()?)?,
                "--speed" => {
                    let speed: f64 = parse_number(&arg, &value()?)?;
                    if !valid_speed(speed) {
                        return Err(HostError::Runtime("--speed 必须在 0–600 内".into()));
                    }
                    a.speed = Some(speed);
                }
                "--save-file" => {
                    a.save_file = Some(PathBuf::from(value()?));
                    save_enabled = true;
                }
                "--no-save" => {
                    a.save_file = None;
                    save_enabled = false;
                }
                "--mock-llm" => mock = true,
                "--mock-delay" => {
                    mock_delay = Duration::from_secs_f64(parse_number(&arg, &value()?)?)
                }
                "--stop-on-stdin-close" => a.stop_on_stdin_close = true,
                "--autosave-seconds" => {
                    let seconds: f64 = parse_number(&arg, &value()?)?;
                    if !(seconds.is_finite() && (0.0..=3600.0).contains(&seconds)) {
                        return Err(HostError::Runtime(
                            "--autosave-seconds 必须在 0–3600 内".into(),
                        ));
                    }
                    a.autosave = Some(Duration::from_secs_f64(seconds));
                }
                other => return Err(HostError::Runtime(format!("未知参数 {other}"))),
            }
        }
        if mock {
            a.mode = Mode::MockLlm { delay: mock_delay };
        }
        if save_enabled && a.save_file.is_none() {
            a.save_file = Some(host::persistence::default_save_path()?);
        }
        Ok(a)
    }
}

fn parse_number<T: std::str::FromStr>(flag: &str, value: &str) -> Result<T, HostError> {
    value
        .parse()
        .map_err(|_| HostError::Runtime(format!("{flag} 的值无效：{value}")))
}

/// 新世界从 D1 07:00 开始。
const START_MINUTES: f64 = 420.0;

/// 建新世界要用的地图数据与规则：启动时读一次，重置时原样再用（配置文件不再读）。
pub(crate) struct WorldSetup {
    /// 交给内核的拓扑 JSON。
    pub topology_json: String,
    /// 化身行走几何；没有时地图不支持化身，也不开天气。
    pub walk_map: Option<Arc<WalkMap>>,
    pub need_rules: NeedRules,
    /// 有行走地图时才有。
    pub weather_rules: Option<WeatherRules>,
    /// 当前场景包的放置器。
    pub scene: host::maps::placement::ScenePlacer,
}

impl WorldSetup {
    /// 空的初始世界：D1 07:00，装好空间放置器与行走地图，有天气规则就开天气，天气属于 `world_id`。
    /// 人口另行安置。启动与重置都用它，新子系统只在这里加一次。
    pub(crate) fn fresh_world(
        &self,
        catalog: &kernel::props::Catalog,
        world_id: &str,
    ) -> Result<World, HostError> {
        let topo = host::maps::runtime_topology(&self.topology_json, catalog)
            .map_err(|e| HostError::Runtime(format!("地图拓扑无效：{e}")))?;
        let mut world = World::new(topo, START_MINUTES, self.need_rules.clone());
        world.set_placer(Box::new(self.scene.clone()));
        world.walk_map = self.walk_map.clone();
        if let Some(rules) = &self.weather_rules {
            world.enable_weather(rules.clone(), rand::random::<u32>().max(1), world_id.into())?;
        }
        Ok(world)
    }
}

/// 内置阿树模板与旧配置主村民的明确映射；只按旧 id，不按姓名猜。
fn template_of(id: &str) -> Option<String> {
    (id == "resident_ashu").then(|| "builtin_ashu".to_string())
}

/// 旧档迁移：世界人物已通过旧版校验并恢复，这里只补登记，设为原有居民。
/// 人设取会话指令去掉公共知识的部分；放不下时截断，不能让启动失败。
pub(crate) fn migrate_population(
    world: &World,
    agent: Option<&host::agent_worker::AgentSave>,
    common: &str,
) -> Population {
    let mut population = Population::fresh();
    for id in world
        .actor_ids()
        .into_iter()
        .filter(|id| world.actor(id).is_some_and(|a| !a.is_avatar()))
    {
        let Some(actor) = world.actor(&id) else {
            continue;
        };
        let persona = agent
            .and_then(|a| a.runtime.sessions.get(&id))
            .map(|s| legacy_persona(&s.instructions, common))
            .unwrap_or_default();
        population.insert(Registration {
            id: id.clone(),
            name: actor.name.clone(),
            home: actor.home.clone(),
            joined_at: None,
            template_id: template_of(&id),
            template_version: None,
            persona,
            appearance: Default::default(),
            model_binding: None,
            needs: world
                .actor(&id)
                .map_or_else(default_tuning, |a| a.needs.tuning),
            order: 0,
        });
    }
    println!(
        "[host] 旧存档已迁移：{} 位原有居民登记完成",
        population.residents.len()
    );
    population
}

fn legacy_persona(instructions: &str, common: &str) -> String {
    let persona = match instructions.strip_suffix(common) {
        Some(p) => p.trim_end().to_string(),
        None => instructions.to_string(),
    };
    let room = INSTRUCTIONS_MAX_CHARS.saturating_sub(instructions_chars("", common));
    if persona.chars().count() > room {
        eprintln!("[host] 旧人设过长，已截断到 {room} 字");
        persona.chars().take(room).collect()
    } else {
        persona
    }
}
