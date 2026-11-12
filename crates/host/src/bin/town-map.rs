//! 地图校验：`town-map validate < 地图.json`，按世界进程的规则检查一份完整地图（道路、地点、道具、场景包
//! 都要对得上）。内置地图的设计脚本（scripts/maps/）和生成器的测试用它；建镇时管理服务对网页交上来的
//! 地图做的是同一套检查（crates/manager/src/creation.rs）。
use host::{application::Application, HostError};
use serde_json::{json, Value};
use std::io::{self, Read};

/// 标准输入最多读这么多字节。
const INPUT_MAX_BYTES: u64 = 16_000_000;

fn run() -> Result<Value, HostError> {
    if std::env::args().nth(1).as_deref() != Some("validate") {
        return Err(HostError::Runtime("未知地图操作".into()));
    }
    let mut input = String::new();
    io::stdin()
        .take(INPUT_MAX_BYTES + 1)
        .read_to_string(&mut input)
        .map_err(|e| HostError::Runtime(e.to_string()))?;
    if input.len() as u64 > INPUT_MAX_BYTES {
        return Err(HostError::Runtime("输入超过限制".into()));
    }
    let app = Application::load()?;
    validate(&app, &input)
}

/// 校验一份完整地图：道具库按地图引用加载，再过 host 的地图校验。
fn validate(app: &Application, input: &str) -> Result<Value, HostError> {
    let d: Value = serde_json::from_str(input).map_err(|e| HostError::Map(e.to_string()))?;
    let catalog = host::props::PropLibrary::load(
        &app.prop_catalog_path,
        &app.legacy_prop_catalog_path,
        None,
        &d,
    )?
    .catalog;
    host::maps::validate(&d, &catalog, std::path::Path::new(&app.scene_assets_path))?;
    Ok(json!({"ok":true}))
}

fn main() {
    match run() {
        Ok(v) => println!("{v}"),
        Err(error) => {
            println!("{}", json!({"error":error.to_string()}));
            std::process::exit(1);
        }
    }
}
