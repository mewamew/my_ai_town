//! 模型配置（设定中心）。
//! 纪律：密钥只在 客户端→服务端 方向出现（本机 ws）；服务端→客户端永远只有掩码。
use serde::{Deserialize, Serialize};

/// 小镇当前使用的服务商与模型。旧版 providers.json 里另有一个 resident 字段，读入时忽略，
/// 下次保存时不再写出。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ActiveModelChoice {
    pub provider: String,
    pub model: String,
}

/// 服务商与模型名的公开引用；不含端点或密钥。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ModelChoice {
    pub provider: String,
    pub model: String,
}

/// 服务商配置（不含密钥；providers.json 的行）
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProviderConfigMsg {
    pub id: String,
    #[serde(default)]
    pub name: String,
    pub base_url: String,
    /// 玩家在「模型服务」里给这个服务填的模型名：给村民或默认模型选这个服务时自动填上它。
    /// 没填过的为空；页面整表保存时原样带回来，只改别处时不会丢。
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub model: String,
}

/// 密钥提交（仅客户端→服务端；空串 = 删除该服务商的密钥）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderKeyMsg {
    pub provider: String,
    pub api_key: String,
}

/// 配置回读视图：密钥只给掩码
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderView {
    pub id: String,
    pub name: String,
    pub base_url: String,
    /// 掩码（如 sk-a…7890）；无密钥为空串
    pub key_mask: String,
    /// 这个服务记着的模型名（见 ProviderConfigMsg::model）；没填过为空串
    #[serde(default)]
    pub model: String,
}
