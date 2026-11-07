//! 正式 host：世界推进、模型传输、共同存档，以及观察仪 WebSocket。
//!
//! cargo run -p host -- [--mock-llm [--mock-delay 3]]
//!   [--port 8787] [--speed 1.0] [--map-document data/maps/2d-town/map.json]
//!   [--save-file 路径 | --no-save] [--town-id ID] [--ready-file 路径] [--connection-token 标识]
//!   [--stop-on-stdin-close]
//!
//! 村民由 Agent 会话驱动；旧的无会话存档由 Agent 接续。
//! 模型和玩家的动作都走内核命令校验。
//! 1 现实秒推进 speed 个模拟分钟；不指定 speed 时沿用存档值。
//! 启动阶段的错误（配置损坏、存档不匹配）打印后退出；运行中的客户端命令不会让进程退出。

mod avatar;
mod join;
mod library_commands;
mod network;
mod prop_commands;
mod recording_commands;
mod resident_driver;
mod runtime;
mod settings;
mod startup;
mod transaction;
mod weather_commands;
mod world_commands;

use host::{
    agent_worker::AgentSave, application::Application, maps::placement::ScenePlacer,
    persistence::SaveStore, population::Population, props::PropLibrary,
    world_settings::WorldSettings, HostError,
};
use kernel::World;
use resident_driver::ResidentDriver;
use runtime::Runtime;
use settings::Settings;
use startup::{Args, WorldSetup};
use std::{
    path::{Path, PathBuf},
    sync::Arc,
    time::{Duration, Instant},
};

/// 一拍最多处理的客户端命令数；剩下的留到下一拍，推进不会被单个客户端拖住。
const COMMANDS_PER_TICK: usize = 32;

fn main() {
    if let Err(error) = run() {
        eprintln!("[host] {error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), HostError> {
    host::process::install_shutdown_handler()
        .map_err(|e| HostError::Runtime(format!("安装退出信号处理失败：{e}")))?;
    let app = Application::load()?;
    let args = Args::parse(&app)?;
    if args.stop_on_stdin_close {
        host::process::stop_when_stdin_closes();
    }
    let path = args.map_document.as_deref().unwrap_or(&app.topology_path);
    let source = std::fs::read_to_string(path)
        .map_err(|e| HostError::Map(format!("读取地图 {path} 失败：{e}")))?;
    let document: serde_json::Value = serde_json::from_str(&source)
        .map_err(|e| HostError::Map(format!("解析地图 {path} 失败：{e}")))?;
    let prop_library = PropLibrary::load(
        &app.prop_catalog_path,
        &app.legacy_prop_catalog_path,
        args.save_file.as_ref().and_then(|p| p.parent()),
        &document,
    )?;
    let hash = document["content_hash"].as_str().unwrap_or("").to_owned();
    let setup = load_map(&app, source, &document, &prop_library.catalog)?;
    let map = (Path::new(path), hash.as_str());
    let runtime = build_runtime(&app, &args, setup, prop_library, map)?;
    serve(runtime, &args, hash)
}

/// 地图文件只读这一次：带 topology 的完整地图先过校验并编译行走几何，裸拓扑原样使用；
/// 连同需求规则、天气规则（有行走地图时）与场景包放置器，得到建新世界要用的全部数据。
fn load_map(
    app: &Application,
    source: String,
    document: &serde_json::Value,
    catalog: &kernel::props::Catalog,
) -> Result<WorldSetup, HostError> {
    let (topology_json, walk_map, manifest) = if document.get("topology").is_none() {
        (source, None, None)
    } else {
        let validated = host::maps::validate(document, catalog, Path::new(&app.scene_assets_path))?;
        let topo = kernel::Topology::from_json(&validated.topology, catalog)?;
        let walk = host::maps::walk::compile(document, &topo)?;
        (validated.topology, walk, validated.manifest)
    };
    let weather_rules = walk_map
        .is_some()
        .then(|| load_weather_rules(&app.weather_rules_path))
        .transpose()?;
    Ok(WorldSetup {
        topology_json,
        walk_map: walk_map.map(Arc::new),
        need_rules: host::config::load_need_rules(&app.needs_rules_path)?,
        weather_rules,
        scene: ScenePlacer::new(manifest.as_ref()),
    })
}

fn load_weather_rules(path: &str) -> Result<kernel::weather::WeatherRules, HostError> {
    let source = std::fs::read_to_string(path)
        .map_err(|e| HostError::Config(format!("读取天气规则失败：{e}")))?;
    let rules: kernel::weather::WeatherRules = serde_json::from_str(&source)
        .map_err(|e| HostError::Config(format!("天气规则无效：{e}")))?;
    rules.validate()?;
    Ok(rules)
}

/// 存档恢复的结果；没有存档或存档不存在时全为空（世界设定为默认）。
#[derive(Default)]
struct Saved {
    speed: Option<f64>,
    world_settings: WorldSettings,
    agent: Option<AgentSave>,
    population: Option<Population>,
}

/// 打开存档并恢复到世界里。旧档（v1/v2）没有登记表：从存档自己的人物表补建，人口从此是存档自己的状态。
fn restore(store: &mut Option<SaveStore>, world: &mut World) -> Result<Saved, HostError> {
    let Some(store) = store else {
        return Ok(Saved::default());
    };
    let mut saved = Saved::default();
    if let Some(restored) = store.restore_bundle(world)? {
        saved.speed = Some(restored.speed);
        saved.agent = restored.agent;
        saved.population = Some(restored.population.unwrap_or_else(|| {
            startup::migrate_population(
                world,
                saved.agent.as_ref(),
                &restored.world_settings.worldview,
            )
        }));
        saved.world_settings = restored.world_settings;
    }
    println!(
        "[host] 存档 {}：{} · {}",
        store.path().display(),
        if saved.speed.is_some() {
            "已恢复"
        } else {
            "新世界"
        },
        world.clock()
    );
    Ok(saved)
}

/// 新世界 → 读档 → 人口与天气归属 → Agent 驱动 → 村民库，组装成运行中的应用。
/// `map` 是地图文件和它的摘要，录像按摘要另存一份地图。
fn build_runtime(
    app: &Application,
    args: &Args,
    setup: WorldSetup,
    prop_library: PropLibrary,
    map: (&Path, &str),
) -> Result<Runtime, HostError> {
    let fresh_population = Population::fresh();
    let mut world = setup.fresh_world(&prop_library.catalog, &fresh_population.world_id)?;
    let mut store = args
        .save_file
        .as_ref()
        .map(|path| {
            SaveStore::open_world(
                path,
                &setup.topology_json,
                &prop_library.catalog,
                Path::new(&app.compatibility_path),
            )
        })
        .transpose()?;
    let saved = restore(&mut store, &mut world)?;
    host::maps::walk::restore_prop_positions(&mut world, args.save_file.as_deref())?;
    world.avatar_leave()?;
    // 新世界一律空村：没有种子村民，居民只能从村民库加入。
    let population = saved.population.unwrap_or(fresh_population);
    if world.walk_map.is_some() && world.weather().is_none() {
        return Err(HostError::Save("2D 世界存档缺少已启用的天气状态".into()));
    }
    world.bind_weather_world(&population.world_id);
    let world_settings = saved.world_settings;
    let settings = Settings::load(app)?;
    let driver = start_driver(
        &mut world,
        &population,
        &world_settings,
        args,
        &settings,
        saved.agent,
    )?;
    // 管理服务给了共用村民库就用它，顺便把旧版存在各小镇目录里的模板收进来；
    // 单独运行（没有管理服务）时放在存档旁边
    let town_dir = store.as_ref().and_then(|s| s.path().parent());
    let reels = town_dir.map(|dir| recording_commands::ReelSource {
        town_dir: dir.to_path_buf(),
        town_id: args.town_id.clone(),
        map_hash: map.1.to_owned(),
        map_document: Some(map.0.to_path_buf()),
    });
    let (library_dir, legacy) = match (town_dir, &app.custom_library_path) {
        (Some(dir), Some(shared)) => (
            Some(PathBuf::from(shared)),
            host::library::legacy_libraries(dir),
        ),
        (Some(dir), None) => (Some(dir.join(host::library::LIBRARY_DIR)), Vec::new()),
        (None, _) => (None, Vec::new()),
    };
    let library = host::library::Library::load(
        Path::new(&app.resident_library_path),
        library_dir.as_deref(),
        &legacy,
    )?;
    println!(
        "[host] 村民 {} 人；村民库 {} 份模板，自定义模板保存在 {}",
        population.residents.len(),
        library.all().count(),
        library.root_display()
    );
    let speed = if world_settings.ready() {
        args.speed.or(saved.speed).unwrap_or(0.0)
    } else {
        0.0
    };
    Ok(Runtime {
        setup,
        avatar_control: avatar::Control::default(),
        speed,
        pace: 0.0,
        world_settings,
        world,
        settings,
        driver,
        store,
        population,
        library,
        prop_library,
        tasks: host::tasks::TaskPool::new(2, 4),
        save_failed: false,
        tape: Default::default(),
        reels,
    })
}

/// 按存档恢复村民会话；上次退出时玩家附身的村民交还给 AI。
fn start_driver(
    world: &mut World,
    population: &Population,
    world_settings: &WorldSettings,
    args: &Args,
    settings: &Settings,
    saved: Option<AgentSave>,
) -> Result<ResidentDriver, HostError> {
    let mut driver = ResidentDriver::build(
        world,
        population,
        &world_settings.worldview,
        &args.mode,
        settings,
        saved,
    )?;
    if let Some(id) = world.release_possession() {
        driver.runtime.player_handover(world, &id)?;
    }
    Ok(driver)
}

/// 监听、写就绪文件、主循环；收到退出信号或 stdin 关闭后保存并退出。
fn serve(mut runtime: Runtime, args: &Args, map_hash: String) -> Result<(), HostError> {
    runtime.checkpoint(true)?;
    let identity = protocol::ServerMsg::WorldIdentity {
        town_id: args.town_id.clone(),
        map_hash,
    };
    // 经 Value 输出，键按字母序，与握手和就绪文件里原来的裸 JSON 逐字节相同。
    let identity =
        serde_json::to_value(&identity).map_err(|e| HostError::Runtime(e.to_string()))?;
    // 只有管理进程启动的小镇（带 town_id）在握手后先发世界身份。
    let greeting = args.town_id.is_some().then(|| identity.to_string());
    let (clients, commands, port) = network::listen(
        args.port,
        greeting,
        args.connection_token.clone(),
        runtime.tape.clone(),
    )?;
    runtime.resume_recording();
    if let Some(path) = &args.ready_file {
        let ready = serde_json::json!({"pid":std::process::id(),"port":port,"identity":identity});
        host::persistence::atomic_write(path, ready.to_string().as_bytes())?;
    }
    let tick = Duration::from_millis(100);
    while !host::process::stopping() {
        let start = Instant::now();
        for _ in 0..COMMANDS_PER_TICK {
            let Ok(command) = commands.try_recv() else {
                break;
            };
            runtime.network_command(command, &clients);
        }
        for (id, at, input) in network::take_inputs(&clients) {
            runtime.avatar_input(id, input, at);
        }
        runtime.tick(&clients);
        if let Some(rest) = tick.checked_sub(start.elapsed()) {
            std::thread::sleep(rest);
        }
    }
    if let Err(error) = runtime.tape.stop() {
        eprintln!("[host] 收起录像失败：{error}");
    }
    runtime.checkpoint(true)?;
    println!("[host] 已保存并退出：{}", runtime.world.clock());
    Ok(())
}
