//! 配置持久化：服务商与模型选择（providers.json，可进 git）+
//! 密钥（credentials.json，0600、gitignore）+ 这台设备的偏好（preferences.json）。**密钥永不混入前者**
//! ——保存前扫描整份配置拒绝明文密钥字段（参照老项目 TownProviderConfigStore
//! 的扫描器与隔离导出测试）。文件不存在等于空配置；存在但损坏时读取报错、写入拒绝覆盖。

use crate::{persistence::atomic_write, HostError};
use protocol::{ActiveModelChoice, ProviderConfigMsg};
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use std::{collections::BTreeMap, io, path::Path};

/// 文件行直接复用线上类型（同一形状：id/name/base_url；没有密钥字段）。
pub type ActiveModel = ActiveModelChoice;
pub type ProviderEntry = ProviderConfigMsg;

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct ProvidersFile {
    /// 居民 → 服务商 + 模型（P3 只有阿树；结构按每居民设计，批量界面留 P4）
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub active: Option<ActiveModel>,
    #[serde(default)]
    pub providers: Vec<ProviderEntry>,
}

pub type Credentials = BTreeMap<String, String>;

/// 明文密钥扫描：配置文件里任何疑似凭据的字段名或取值都拒绝落盘。
fn contains_secret(v: &serde_json::Value) -> bool {
    match v {
        serde_json::Value::Object(map) => map.iter().any(|(k, val)| {
            let k = k.to_lowercase();
            k.contains("key") || k.contains("secret") || k.contains("token") || contains_secret(val)
        }),
        serde_json::Value::Array(a) => a.iter().any(contains_secret),
        serde_json::Value::String(s) => s.starts_with("sk-") || s.starts_with("Bearer "),
        _ => false,
    }
}

/// 不存在才是空配置；存在但读不出或解析失败都是错误，带上文件路径。
fn load_json<T: DeserializeOwned + Default>(path: &str) -> Result<T, HostError> {
    match std::fs::read_to_string(path) {
        Ok(text) => serde_json::from_str(&text)
            .map_err(|e| HostError::Config(format!("配置文件 {path} 损坏，原文件已保留：{e}"))),
        Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(T::default()),
        Err(e) => Err(HostError::Config(format!("读取配置文件 {path} 失败：{e}"))),
    }
}

pub fn load_providers(path: &str) -> Result<ProvidersFile, HostError> {
    load_json(path)
}

/// 配置写成缩进的 JSON 并原子替换。
fn write_json<T: Serialize>(path: &str, value: &T) -> Result<(), HostError> {
    let text = serde_json::to_string_pretty(value)
        .map_err(|e| HostError::Config(format!("编码配置文件 {path} 失败：{e}")))?;
    atomic_write(Path::new(path), text.as_bytes())
}

/// 磁盘上的文件若已损坏，拒绝覆盖，不把用户手改坏的配置悄悄换掉。
pub fn save_providers(path: &str, f: &ProvidersFile) -> Result<(), HostError> {
    load_providers(path)?;
    let v = serde_json::to_value(f)
        .map_err(|e| HostError::Config(format!("编码配置文件 {path} 失败：{e}")))?;
    if contains_secret(&v) {
        return Err(HostError::Config(
            "配置里出现疑似明文密钥，拒绝保存（密钥只进 credentials.json）".into(),
        ));
    }
    write_json(path, &v)
}

pub fn load_credentials(path: &str) -> Result<Credentials, HostError> {
    load_json(path)
}

/// 跟着这台设备的偏好（preferences.json，路径见 Application::preferences_path）。没拨过的项不写，
/// 按应用配置的缺省；不认识的项原样留着。
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Preferences {
    /// Agent 轨迹日志记不记完整题面（见 agent_trace.rs）
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub trace_full_prompts: Option<bool>,
    #[serde(flatten)]
    pub other: serde_json::Map<String, serde_json::Value>,
}

pub fn load_preferences(path: &str) -> Result<Preferences, HostError> {
    load_json(path)
}

pub fn save_preferences(path: &str, p: &Preferences) -> Result<(), HostError> {
    load_preferences(path)?;
    write_json(path, p)
}

pub fn save_credentials(path: &str, c: &Credentials) -> Result<(), HostError> {
    load_credentials(path)?;
    write_json(path, c)
}

/// 人设是散文，密钥没有理由出现在这里。
pub fn check_no_secret(text: &str) -> Result<(), HostError> {
    let leaky = text
        .split(|c: char| {
            c.is_whitespace()
                || c.is_ascii_punctuation() && c != '-' && c != '_'
                || "：，。；！？、（）【】「」“”‘’…".contains(c)
        })
        .any(|t| (t.starts_with("sk-") && t.len() > 10) || t.starts_with("Bearer"));
    if leaky {
        return Err(HostError::Config(
            "人设文本里出现疑似明文密钥，拒绝保存".into(),
        ));
    }
    Ok(())
}

/// 界面与配置回读只见掩码：sk-3…8905 形态。
pub fn mask(key: &str) -> String {
    let n = key.chars().count();
    if n <= 8 {
        return "＊＊＊".into();
    }
    let head: String = key.chars().take(4).collect();
    let tail: String = key.chars().skip(n - 4).collect();
    format!("{head}…{tail}")
}

/// 读需求规则文件；缺失或格式错误由启动流程退出。
pub fn load_need_rules(path: &str) -> Result<protocol::NeedRules, HostError> {
    let json = std::fs::read_to_string(path)
        .map_err(|e| HostError::Config(format!("读取需求规则 {path} 失败：{e}")))?;
    protocol::NeedRules::parse(&json).map_err(|e| HostError::Config(format!("{path}：{e}")))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 隔离导出测试（参照老项目）：明文密钥不得进 providers.json。
    #[test]
    fn plaintext_key_rejected_in_providers_file() {
        let mut f = ProvidersFile::default();
        f.providers.push(ProviderEntry {
            id: "deepseek".into(),
            name: "DeepSeek".into(),
            base_url: "sk-abcdef1234567890".into(), // 误把密钥填进端点
        });
        let dir = std::env::temp_dir().join(format!("ai-town-cfg-{}", std::process::id()));
        let path = dir.join("providers.json");
        let err = save_providers(path.to_str().unwrap(), &f).unwrap_err();
        assert!(matches!(err, HostError::Config(_)), "{err}");
        assert!(!path.exists());
    }
}
