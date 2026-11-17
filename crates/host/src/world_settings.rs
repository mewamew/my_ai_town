//! 每个运行世界的设定，随世界存档保存。地图包只定义场景与资源。
use crate::HostError;
use protocol::{PrefabSetupPlan, PrefabSetupState, PrefabSetupStep};
use serde::{Deserialize, Serialize};
use std::ops::RangeInclusive;

pub const MAX_WORLDVIEW_CHARS: usize = 6_000;
/// 人设加公共知识（世界观）合计的字数上限，直接沿用 Agent 会话指令上限。
pub use agent::runtime::INSTRUCTIONS_MAX_CHARS;
/// 世界速度（模拟分钟 / 现实秒）的允许范围；启动参数、命令和存档都按它检查。
pub const SPEED_RANGE: RangeInclusive<f64> = 0.0..=600.0;

/// 村民的会话指令：人设接公共知识（世界观），中间一个换行。人设与世界观的拼法只在这里。
pub fn instructions(persona: &str, worldview: &str) -> String {
    format!("{persona}\n{worldview}")
}

/// `instructions` 拼出来的字数，与 INSTRUCTIONS_MAX_CHARS 比较。
pub fn instructions_chars(persona: &str, worldview: &str) -> usize {
    persona.chars().count() + 1 + worldview.chars().count()
}

pub fn valid_speed(speed: f64) -> bool {
    speed.is_finite() && SPEED_RANGE.contains(&speed)
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WorldSettings {
    pub worldview: String,
    pub revision: u64,
    /// 冻结的开局计划与已提交游标；完成标记保留，迟到页面不能再开一局。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub prefab_setup: Option<PrefabSetupState>,
    /// 录像开关（见 recording.rs）：新世界和没有这一项的旧存档都按开着算，好剧情不会没录上
    #[serde(default = "recording_on")]
    pub recording: bool,
    /// 旧存档里开发用「手动验证」模式的开关。这个模式已经删掉，只为读得进旧存档，不再使用也不再写出
    #[serde(default, rename = "autonomous", skip_serializing)]
    _autonomous: bool,
}

fn recording_on() -> bool {
    true
}

impl Default for WorldSettings {
    fn default() -> Self {
        Self {
            worldview: String::new(),
            revision: 0,
            prefab_setup: None,
            recording: recording_on(),
            _autonomous: false,
        }
    }
}

impl WorldSettings {
    pub fn ready(&self) -> bool {
        !self.worldview.trim().is_empty()
            && self
                .prefab_setup
                .as_ref()
                .is_none_or(PrefabSetupState::complete)
    }
    pub fn validate(&self) -> Result<(), HostError> {
        if self.worldview.chars().count() > MAX_WORLDVIEW_CHARS {
            return Err(HostError::Config(format!(
                "世界观最多 {MAX_WORLDVIEW_CHARS} 字"
            )));
        }
        if let Some(setup) = &self.prefab_setup {
            validate_prefab_setup_id(&setup.id)?;
            validate_prefab_plan(&setup.plan)?;
            let joined = setup
                .plan
                .steps
                .iter()
                .take(setup.next_step)
                .filter(|step| matches!(step, PrefabSetupStep::Join { .. }))
                .count();
            if setup.next_step > setup.plan.steps.len()
                || joined != setup.joined.len()
                || setup.joined.iter().any(|id| id.is_empty())
                || setup
                    .joined
                    .iter()
                    .collect::<std::collections::BTreeSet<_>>()
                    .len()
                    != joined
            {
                return Err(HostError::Config("预制开局进度与人物记录不一致".into()));
            }
        }
        Ok(())
    }
}

pub fn validate_prefab_setup_id(id: &str) -> Result<(), HostError> {
    if id.is_empty() || id.len() > 128 {
        return Err(HostError::Rejected("开局编号须为 1–128 字节".into()));
    }
    Ok(())
}

/// 上限同时用于接收和读档，拒绝无法恢复或能任意延长的计划；历史无标记的世界不做推断。
pub fn validate_prefab_plan(plan: &PrefabSetupPlan) -> Result<(), HostError> {
    let fail = || HostError::Rejected("预制开局计划不完整或超过上限".into());
    if plan.prefab.is_empty()
        || plan.prefab.len() > 80
        || !plan
            .prefab
            .bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
        || !(1..=12).contains(&plan.selection.players)
        || plan.selection.models.len() != plan.selection.players
        || !(2..=256).contains(&plan.steps.len())
        || serde_json::to_vec(plan).map_err(|_| fail())?.len() > 256_000
        || !matches!(plan.steps.first(), Some(PrefabSetupStep::Worldview { .. }))
        || !matches!(plan.steps.last(), Some(PrefabSetupStep::GameMode { .. }))
    {
        return Err(fail());
    }
    let mut joins = 0;
    for (i, step) in plan.steps.iter().enumerate() {
        match step {
            PrefabSetupStep::Worldview { text } => {
                if i != 0 || text.trim().is_empty() || text.chars().count() > MAX_WORLDVIEW_CHARS {
                    return Err(fail());
                }
            }
            PrefabSetupStep::GameMode { .. } if i + 1 != plan.steps.len() => return Err(fail()),
            PrefabSetupStep::Join { look, model, .. } => {
                if plan.selection.models.get(joins) != Some(model) {
                    return Err(fail());
                }
                joins += 1;
                if let Some(look) = look {
                    look.check().map_err(HostError::Rejected)?;
                }
            }
            PrefabSetupStep::Limits { limits } if !limits.is_object() => return Err(fail()),
            _ => {}
        }
    }
    if joins != plan.selection.players {
        return Err(fail());
    }
    Ok(())
}
