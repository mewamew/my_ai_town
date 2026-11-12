//! 存档格式迁移与兼容标识表。版本：v1 记忆内嵌在会话里；v2 记忆拆成外部文件；
//! v3 加人口登记；v4 加玩家化身；v5 加天气；v6 把只增不改的历史拆成流水（history.rs）。
//! 读取时逐级升到当前版本，需要留原档的步骤记为 Backup，由调用方落盘。
//! 兼容标识表是数据文件，由 SaveStore 在需要时按配置路径读入。
use super::{retired_commissions, SaveFile};
use crate::fnv::fnv1a;
use crate::HostError;
use serde_json::Value;

pub(super) const SCHEMA_VERSION: u32 = 6;

#[derive(Debug, PartialEq, Eq)]
pub(super) enum Backup {
    /// 世界快照还是 v1（没有身体字段），内核升级前留原档
    Physiology,
    Avatar,
    Weather,
    /// 委托功能已移除，清理前留原档
    CommissionRemoval,
    /// 历史还都在 world.json 和记忆文件里（v5 及以前）；拆成流水前留原档，旧版本只读得了它
    History,
}

impl Backup {
    pub(super) fn suffix(&self) -> &'static str {
        match self {
            Backup::Weather => ".before-weather-v1",
            Backup::Avatar => ".before-avatar-v1",
            Backup::Physiology => ".before-physiology-v1",
            Backup::CommissionRemoval => ".before-commission-removal",
            Backup::History => ".before-history-v1",
        }
    }
    pub(super) fn label(&self) -> &'static str {
        match self {
            Backup::Weather => "天气加入前的原始存档",
            Backup::Avatar => "化身加入前的原始存档",
            Backup::Physiology => "生理状态升级备份",
            Backup::CommissionRemoval => "旧委托已迁出运行状态，原始存档备份",
            Backup::History => "历史拆成流水前的原始存档",
        }
    }
    /// 备份目录里附带的说明文件名；内容是兼容标识表本身。
    pub(super) fn extra_file(&self) -> Option<&'static str> {
        match self {
            Backup::Physiology => Some("physiology-content-versions.json"),
            Backup::CommissionRemoval | Backup::Avatar | Backup::Weather | Backup::History => None,
        }
    }
}

pub(super) struct Migration {
    pub file: SaveFile,
    /// 读到时的版本；兼容标识与记忆文件的处理按它分支。
    pub from_version: u32,
    pub backups: Vec<Backup>,
}

pub(super) fn migrate(mut value: Value) -> Result<Migration, HostError> {
    let from_version = value["schema_version"]
        .as_u64()
        .and_then(|v| u32::try_from(v).ok())
        .ok_or_else(|| HostError::Save("存档缺少版本号，原文件已保留".into()))?;
    if !(1..=SCHEMA_VERSION).contains(&from_version) {
        return Err(HostError::Save(format!(
            "存档版本 {from_version} 不受支持（当前 {SCHEMA_VERSION}），原文件已保留"
        )));
    }
    let mut backups = Vec::new();
    if retired_commissions::migrate(&mut value)? {
        backups.push(Backup::CommissionRemoval);
    }
    if value["world"]["schema_version"] == 1 {
        backups.push(Backup::Physiology);
    } else {
        require_body_fields(&value)?;
    }
    if from_version < 2 {
        v1_to_v2(&mut value)?;
    }
    if from_version < 3 {
        v2_to_v3(&mut value);
    }
    if from_version < 4 {
        backups.push(Backup::Avatar);
        value["schema_version"] = Value::from(4);
    } else {
        let actors = value["world"]["actors"]
            .as_object()
            .ok_or_else(|| HostError::Save("存档缺少人物表".into()))?;
        if actors.values().any(|a| a.get("kind").is_none()) {
            return Err(HostError::Save("v4 存档缺少人物种类，原文件已保留".into()));
        }
    }
    if from_version < 5 {
        backups.push(Backup::Weather);
        value["schema_version"] = Value::from(5);
    } else if value["world"]["schema_version"] != 5 || value["world"].get("weather").is_none() {
        return Err(HostError::Save(
            "v5 存档缺少天气状态或内核版本不一致，原文件已保留".into(),
        ));
    }
    // v5 及以前没有流水：历史照旧从 world.json 和记忆文件读，第一次存盘时拆出去。
    if from_version < 6 {
        backups.push(Backup::History);
        value["schema_version"] = Value::from(6);
    } else if !value["history"].is_object() {
        return Err(HostError::Save("v6 存档缺少流水清单，原文件已保留".into()));
    }
    let file: SaveFile = serde_json::from_value(value)
        .map_err(|e| HostError::Save(format!("存档格式不兼容，原文件已保留：{e}")))?;
    Ok(Migration {
        file,
        from_version,
        backups,
    })
}

/// 新世界快照必须带齐身体字段；只有 v1 快照由内核补。
fn require_body_fields(value: &Value) -> Result<(), HostError> {
    let actors = value["world"]["actors"]
        .as_object()
        .ok_or_else(|| HostError::Save("存档缺少人物表".into()))?;
    for actor in actors.values() {
        for key in ["water", "health", "body"] {
            if actor["needs"].get(key).is_none() {
                return Err(HostError::Save(format!(
                    "新存档缺少身体字段 {key}，原文件已保留"
                )));
            }
        }
    }
    Ok(())
}

/// v1 → v2：记忆仍内嵌在会话里，下一次检查点由 stage 拆成外部文件；v1 不能已有文件清单。
fn v1_to_v2(value: &mut Value) -> Result<(), HostError> {
    let has_files = value["resident_files"]
        .as_object()
        .is_some_and(|m| !m.is_empty());
    if has_files {
        return Err(HostError::Save("v1 存档不能包含外部记忆清单".into()));
    }
    value["schema_version"] = Value::from(2);
    Ok(())
}

/// v2 → v3：人口登记由启动流程按世界人物与会话补建（startup::migrate_population）。
fn v2_to_v3(value: &mut Value) {
    value["schema_version"] = Value::from(3);
}

/// 旧档标识是否在迁移表里。`legacy` 表示 v1/v2 存档：那时的标识把人物 id、住宅也算进哈希，
/// 用同一算法从表里的前缀哈希续算，保留身份校验。`table` 是兼容标识表的原文。
pub(super) fn known_upgrade(
    table: &str,
    previous: &str,
    current: &str,
    legacy: bool,
    identities: &[(String, String)],
) -> Result<bool, HostError> {
    let versions: Value = serde_json::from_str(table)
        .map_err(|e| HostError::Save(format!("兼容标识表格式错误：{e}")))?;
    let flat: Vec<&str> = identities
        .iter()
        .flat_map(|(id, home)| [id.as_str(), home.as_str()])
        .collect();
    Ok(versions.as_array().into_iter().flatten().any(|v| {
        if v["current"] != current {
            return false;
        }
        if !legacy {
            return v["previous"] == previous;
        }
        let Some(prefix) = v["legacy_prefix_hash"]
            .as_str()
            .and_then(|h| u64::from_str_radix(h, 16).ok())
        else {
            return false;
        };
        let suffix = format!("{}]", serde_json::json!(flat));
        previous == format!("{:016x}", fnv1a(suffix.as_bytes(), prefix))
    }))
}
