//! 正式应用的路径配置。环境变量只在这个文件读取。
//! 没有种子村民：人口只来自存档，居民只能从村民库加入。
use crate::HostError;
use serde::Deserialize;
use std::path::{Path, PathBuf};

/// AI_TOWN_CONFIG 未设置时的应用配置文件。
pub const CONFIG_PATH: &str = "config/application.json";
/// 配置文件没写 needs_rules_path 时的需求规则文件；前端构建时读的是同一份。
pub const NEEDS_RULES_PATH: &str = "config/needs_rules.json";
/// 缺省的内置道具库、场景包目录与旧档兼容标识表。内核不内嵌这些文件，都由 host 运行期读入。
pub const PROP_CATALOG_PATH: &str = "data/props/core/definitions.json";
pub const LEGACY_PROP_CATALOG_PATH: &str = "data/props/compatibility/retired-core-20260925.json";
pub const SCENE_ASSETS_PATH: &str = "data/scene-assets";
pub const COMPATIBILITY_PATH: &str = "data/props/compatibility/physiology-v1.json";

#[derive(Debug, Deserialize)]
pub struct Application {
    #[serde(default = "weather_rules_default")]
    pub weather_rules_path: String,
    pub port: u16,
    pub topology_path: String,
    #[serde(default = "prop_catalog_default")]
    pub prop_catalog_path: String,
    /// 已从新地图移除、但旧存档仍引用的道具定义。
    #[serde(default = "legacy_prop_catalog_default")]
    pub legacy_prop_catalog_path: String,
    /// 场景包目录；地图 assets.id 指向其中一个子目录。
    #[serde(default = "scene_assets_default")]
    pub scene_assets_path: String,
    /// 旧档（身体字段升级前）的兼容标识表。
    #[serde(default = "compatibility_default")]
    pub compatibility_path: String,
    pub providers_path: String,
    pub credentials_path: String,
    /// 需求参数的合法范围（衰减率区间、阈值顺序），启动时读入并注入世界
    #[serde(default = "needs_rules_default")]
    pub needs_rules_path: String,
    /// 内置村民模板目录
    #[serde(default = "library_default")]
    pub resident_library_path: String,
    /// 自定义村民模板目录：所有小镇共用一份，由管理服务设在用户数据目录下。
    /// 没写时（单独运行、测试）放在存档旁边，只有这个小镇看得到。
    #[serde(default)]
    pub custom_library_path: Option<String>,
    /// 应用自带的推理程序 llama-server 所在目录。没有这个程序时设定里不出现内置模型。
    #[serde(default = "builtin_model_default")]
    pub builtin_model_path: String,
    /// 内置模型文件和下载记录所在目录，由管理服务设在用户数据目录下；模型不随应用带，用到时下载。
    /// 没写时（单独运行、测试）和推理程序放在同一个目录。
    #[serde(default)]
    pub builtin_model_store: Option<String>,
    /// 内置模型的发布处：这个地址下有 manifest.json 和各版本的模型文件（见 builtin_store.rs）。
    #[serde(default = "builtin_source_default")]
    builtin_model_source: String,
    /// Agent 轨迹日志（agent_trace.rs）缺省记不记完整题面。仓库里的配置写着 true，开发和复盘时记；
    /// 打包时 scripts/app-bundle.mjs 去掉这一项，安装包缺省不记。玩家在设定里拨过就按拨的（preferences.json）。
    #[serde(default)]
    pub trace_full_prompts: bool,
}
fn weather_rules_default() -> String {
    "config/weather_rules.json".into()
}
fn library_default() -> String {
    format!("config/{}", crate::library::LIBRARY_DIR)
}
fn needs_rules_default() -> String {
    NEEDS_RULES_PATH.into()
}
fn prop_catalog_default() -> String {
    PROP_CATALOG_PATH.into()
}
fn legacy_prop_catalog_default() -> String {
    LEGACY_PROP_CATALOG_PATH.into()
}
fn scene_assets_default() -> String {
    SCENE_ASSETS_PATH.into()
}
fn compatibility_default() -> String {
    COMPATIBILITY_PATH.into()
}
/// 工作区里由 scripts/builtin-model/build.mjs 准备的目录；应用包由管理服务指到包里。
fn builtin_model_default() -> String {
    "target/builtin-model".into()
}
/// 魔搭上的模型仓库，按 master 取最新的清单。
pub const BUILTIN_SOURCE: &str =
    "https://modelscope.cn/models/hihuazi/ai-town-villager/resolve/master";
fn builtin_source_default() -> String {
    BUILTIN_SOURCE.into()
}

impl Application {
    pub fn load() -> Result<Self, HostError> {
        let path = config_path();
        let json = std::fs::read_to_string(&path)
            .map_err(|e| HostError::Config(format!("读取应用配置 {path} 失败：{e}")))?;
        serde_json::from_str(&json)
            .map_err(|e| HostError::Config(format!("解析应用配置 {path} 失败：{e}")))
    }

    /// 跟着这台设备的偏好（config.rs 的 Preferences），和密钥放在同一个目录：管理服务把密钥设在
    /// 用户数据目录的 config/ 下，所有小镇、电脑版和 mac 版共用一份。
    pub fn preferences_path(&self) -> String {
        Path::new(&self.credentials_path)
            .with_file_name("preferences.json")
            .to_string_lossy()
            .into_owned()
    }

    /// 内置模型文件和下载记录的目录。
    pub fn builtin_store(&self) -> &str {
        self.builtin_model_store
            .as_deref()
            .unwrap_or(&self.builtin_model_path)
    }

    /// AI_TOWN_MODEL_SOURCE：换一个内置模型的发布处（测试、发布前自己先试）；没设时用配置里的。
    pub fn builtin_source(&self) -> String {
        std::env::var("AI_TOWN_MODEL_SOURCE")
            .ok()
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| self.builtin_model_source.clone())
            .trim_end_matches('/')
            .to_owned()
    }
}

/// AI_TOWN_CONFIG：应用配置文件路径。
pub fn config_path() -> String {
    std::env::var("AI_TOWN_CONFIG").unwrap_or_else(|_| CONFIG_PATH.into())
}

/// AI_TOWN_HOME：运行数据根目录（存档、村民库、道具库）。未设置时按平台惯例放在用户数据目录，
/// 不放进仓库，也不与调用日志混用。
pub fn data_root() -> Result<PathBuf, HostError> {
    if let Some(root) = std::env::var_os("AI_TOWN_HOME").filter(|s| !s.is_empty()) {
        return Ok(PathBuf::from(root));
    }
    let home = std::env::var_os("HOME")
        .ok_or_else(|| HostError::Config("缺少 HOME；请指定 --save-file 或 AI_TOWN_HOME".into()))?;
    Ok(if cfg!(target_os = "macos") {
        PathBuf::from(home).join("Library/Application Support/MyAiTown/town-2d")
    } else {
        std::env::var_os("XDG_DATA_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from(home).join(".local/share"))
            .join("my-ai-town/town-2d")
    })
}

/// AI_TOWN_LOG_DIR：Agent 轨迹日志目录，缺省为当前目录下的 logs/。
pub fn log_dir() -> PathBuf {
    std::env::var_os("AI_TOWN_LOG_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("logs"))
}
