//! 世界天气事实；随机数与渲染参数不在线上暴露。
use serde::{Deserialize, Serialize};

/// 气候：天气怎么转的倾向，世界级，随存档保存。温带照天气规则的转移表（默认）；热带不下雪，
/// 转到雷暴的机会减半（荒岛这类地方）。
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Climate {
    #[default]
    Temperate,
    Tropical,
}
impl Climate {
    pub fn is_temperate(&self) -> bool {
        *self == Self::Temperate
    }
    pub fn label(self) -> &'static str {
        match self {
            Self::Temperate => "温带",
            Self::Tropical => "热带",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WeatherKind {
    Clear,
    Overcast,
    LightRain,
    Rain,
    HeavyRain,
    Thunderstorm,
    Snow,
}
impl WeatherKind {
    pub const ALL: [Self; 7] = [
        Self::Clear,
        Self::Overcast,
        Self::LightRain,
        Self::Rain,
        Self::HeavyRain,
        Self::Thunderstorm,
        Self::Snow,
    ];
    pub fn label(self) -> &'static str {
        match self {
            Self::Clear => "晴天",
            Self::Overcast => "阴天",
            Self::LightRain => "小雨",
            Self::Rain => "中雨",
            Self::HeavyRain => "大雨",
            Self::Thunderstorm => "雷暴",
            Self::Snow => "下雪",
        }
    }
    pub fn index(self) -> usize {
        Self::ALL.iter().position(|k| *k == self).unwrap()
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WeatherMode {
    Natural,
    Fixed,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WeatherSource {
    Natural,
    Manual,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WeatherTransition {
    pub id: u64,
    pub at: f64,
    pub from: WeatherKind,
    pub to: WeatherKind,
    pub source: WeatherSource,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WeatherView {
    pub world_id: String,
    pub revision: u64,
    pub kind: WeatherKind,
    pub mode: WeatherMode,
    pub changed_at: f64,
    pub last_transition: Option<WeatherTransition>,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Exposure {
    Indoor,
    Outdoor,
    Unknown,
    Offstage,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WeatherPolicy {
    pub allowed: bool,
    pub code: Option<WeatherCode>,
    pub reason: String,
}
/// 天气控制与活动策略的机器码；显示文案另给。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WeatherCode {
    InvalidWeather,
    RevisionConflict,
    WeatherUnavailable,
    WeatherUnsafe,
    SaveFailed,
    WorldMismatch,
    WorldNotReady,
}
impl WeatherCode {
    /// 线上取值；内核错误的文案以它开头。
    pub fn as_str(self) -> &'static str {
        match self {
            Self::InvalidWeather => "invalid_weather",
            Self::RevisionConflict => "revision_conflict",
            Self::WeatherUnavailable => "weather_unavailable",
            Self::WeatherUnsafe => "weather_unsafe",
            Self::SaveFailed => "save_failed",
            Self::WorldMismatch => "world_mismatch",
            Self::WorldNotReady => "world_not_ready",
        }
    }
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IndoorAlternative {
    pub locale: String,
    pub name: String,
    pub minutes: f64,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WeatherContext {
    pub weather: WeatherView,
    pub exposure: Exposure,
    pub activity: WeatherPolicy,
    pub indoor_alternatives: Vec<IndoorAlternative>,
}
