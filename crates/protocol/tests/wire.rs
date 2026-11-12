//! 线上协议的门槛测试。
//! - no_geometry_on_the_wire（perception §八）：除玩家专用状态和三维姿态上报外，`ServerMsg` 与
//!   `ClientMsg` 的每个变体各构造一份有内容的样本，序列化后断言 JSON 里没有几何痕迹。
//!   变体清单由 `variants!` 的穷举 match 保证：新增变体时这里编译失败；漏给样本时测试失败。
//! - samples_for_typescript：把全部样本写到 target/tmp，前端测试据此核对 protocol.ts。
//! - old_saved_values_still_read：旧存档里的旧取值（serde alias）仍能读入。
#[path = "wire/samples.rs"]
mod samples;

use protocol::*;
use samples::{client_samples, server_samples, shape_samples, tuning};
use serde_json::json;
use std::collections::BTreeSet;

/// 列出枚举全部变体的 serde 标签（snake_case）。match 穷举保证新增变体时编译失败。
macro_rules! variants {
    ($ty:ident { $($v:ident),+ $(,)? }) => {{
        fn exhaustive(m: &$ty) {
            match m { $($ty::$v { .. } => {}),+ }
        }
        let _ = exhaustive;
        vec![$(snake_case(stringify!($v))),+]
    }};
}

fn snake_case(name: &str) -> String {
    let mut out = String::new();
    for (i, c) in name.chars().enumerate() {
        if c.is_uppercase() {
            if i > 0 {
                out.push('_');
            }
            out.extend(c.to_lowercase());
        } else {
            out.push(c);
        }
    }
    out
}

fn server_variants() -> Vec<String> {
    variants!(ServerMsg {
        WorldIdentity,
        WeatherSaved,
        AvatarState,
        AvatarResult,
        ChatHistory,
        WorldSettings,
        WorldSettingsSaved,
        Props,
        PropResult,
        PlacementGrid,
        PlacementPreview,
        Roster,
        Event,
        ModelConfig,
        ConfigSaved,
        ModelTestResult,
        AgentConfig,
        AgentSaved,
        ResidentDetail,
        Error,
        WorldReset,
        Recordings,
        Diary,
        Notebook,
        NotebookDetail,
        AgentLimits,
        AgentTrace,
        Population,
        ResidentAppearanceSaved,
        Usage,
        ResidentLibrary,
        ResidentTemplate,
        TemplatePersona,
        TemplateGenerated,
        TemplateSaved,
        JoinPreview,
        ResidentJoined,
        JoinResult,
    })
}

fn client_variants() -> Vec<String> {
    variants!(ClientMsg {
        SetWeather,
        Avatar,
        AvatarInput,
        GetChatHistory,
        GetWorldSettings,
        SetWorldview,
        SetPhysiology,
        SetClimate,
        SetMiracles,
        SetRecording,
        GetRecordings,
        DeleteRecording,
        SetStrangers,
        SetGameMode,
        GetProps,
        Content,
        ValidateProp,
        SaveProp,
        DeleteProp,
        RemoveProp,
        PlaceProp,
        GetPlacementGrid,
        PreviewPlacement,
        SetSpeed,
        GetModelConfig,
        SetModelConfig,
        SetResidentModel,
        RestartBuiltinModel,
        TestModelConnection,
        GetAgentConfig,
        WatchResident,
        SetPersona,
        ResetWorld,
        GetPopulation,
        SetResidentAppearance,
        SetResidentBody,
        GetUsage,
        GetResidentLibrary,
        GetResidentTemplate,
        SaveResidentTemplate,
        PreviewTemplatePersona,
        GenerateResidentTemplate,
        ArchiveResidentTemplate,
        PreviewResidentJoin,
        JoinResident,
        GetResidentJoinResult,
        GetDiary,
        GetNotebook,
        GetNotebookDetail,
        GetAgentLimits,
        SetAgentLimits,
        GetAgentTrace,
        SetAgentTrace,
    })
}

/// 分页的 offset 与聊天的 seq 不是几何；这里只列几何与渲染资源的痕迹。
const BANNED: [&str; 12] = [
    "position", "polyline", "\"x\"", "\"y\"", "\"z\"", "px", "cells", "bounds", "res://", ".png",
    ".tres", "pixel",
];

fn check(name: &str, json: &str) {
    for banned in BANNED {
        assert!(
            !json.contains(banned),
            "几何痕迹 {banned:?} 出现在 {name} 的线上表示: {json}"
        );
    }
}

/// 每个变体至少一份样本，且样本的 `type` 标签都在变体清单里。
fn assert_covered(kind: &str, expected: Vec<String>, tags: BTreeSet<String>) {
    let expected: BTreeSet<String> = expected.into_iter().collect();
    let missing: Vec<_> = expected.difference(&tags).collect();
    assert!(missing.is_empty(), "{kind} 缺少样本：{missing:?}");
    let unknown: Vec<_> = tags.difference(&expected).collect();
    assert!(
        unknown.is_empty(),
        "{kind} 样本的标签不在变体清单里：{unknown:?}"
    );
}

#[test]
fn no_geometry_on_the_wire() {
    let mut server_tags = BTreeSet::new();
    for msg in server_samples() {
        let json = serde_json::to_string(&msg).unwrap();
        let tag = serde_json::from_str::<serde_json::Value>(&json).unwrap()["type"]
            .as_str()
            .unwrap()
            .to_string();
        // 化身状态是玩家专用的权威坐标回包；摆道具的格子和试放落点只回给摆道具的页面。
        // Agent 的意图协议仍禁止坐标输入。
        if ![
            "avatar_state",
            "avatar_result",
            "placement_grid",
            "placement_preview",
        ]
        .contains(&tag.as_str())
        {
            check(&format!("ServerMsg::{tag}"), &json);
        }
        server_tags.insert(tag);
    }
    assert_covered("ServerMsg", server_variants(), server_tags);

    let mut client_tags = BTreeSet::new();
    for msg in client_samples() {
        let json = serde_json::to_string(&msg).unwrap();
        let tag = serde_json::from_str::<serde_json::Value>(&json).unwrap()["type"]
            .as_str()
            .unwrap()
            .to_string();
        // avatar_input.pose 是玩家三维碰撞解算后的专用位置上报；place_prop、preview_placement 的
        // near 是玩家摆道具时在地图上点的位置，只作选点偏好。都只有玩家界面发，Agent 意图仍禁止几何。
        if !["avatar_input", "place_prop", "preview_placement"].contains(&tag.as_str()) {
            check(&format!("ClientMsg::{tag}"), &json);
        }
        client_tags.insert(tag);
    }
    assert_covered("ClientMsg", client_variants(), client_tags);
}

/// 把全部样本写成 JSON，给前端的类型比对测试用（frontend/town-shared/tests/protocol-wire.test.mjs）。
#[test]
fn samples_for_typescript() {
    let (mut server, mut client) = shape_samples();
    server.extend(server_samples());
    client.extend(client_samples());
    let samples = json!({ "server": server, "client": client });
    let path = std::path::Path::new(env!("CARGO_TARGET_TMPDIR")).join("protocol-wire-samples.json");
    std::fs::write(&path, serde_json::to_string_pretty(&samples).unwrap()).unwrap();
}

fn read<T: serde::de::DeserializeOwned>(value: &str) -> T {
    serde_json::from_value(json!(value)).unwrap()
}

/// 旧存档里的中文台账值与旧的事件种类仍能读回；线上一律输出 snake_case。
#[test]
fn old_saved_values_still_read() {
    let kinds: [(&str, RequestKind); 2] = [
        ("生活决策", RequestKind::Life),
        ("记忆整理", RequestKind::Reflection),
    ];
    for (old, kind) in kinds {
        assert_eq!(read::<RequestKind>(old), kind);
    }
    let statuses: [(&str, RequestStatus); 7] = [
        ("进行中", RequestStatus::InFlight),
        ("采纳", RequestStatus::Adopted),
        ("格式重发", RequestStatus::FormatRetry),
        ("过时退回", RequestStatus::Outdated),
        ("失败", RequestStatus::Failed),
        ("重启丢弃", RequestStatus::Dropped),
        ("受控操作取消", RequestStatus::Controlled),
    ];
    for (old, status) in statuses {
        assert_eq!(read::<RequestStatus>(old), status);
        assert_ne!(json!(status), json!(old));
    }
    assert_eq!(read::<FactKind>("job"), FactKind::Observation);
    assert_eq!(json!(FactKind::Observation), json!("observation"));
}

#[test]
fn need_rules_validate_tuning() {
    let rules = NeedRules::parse(
        r#"{"rate_min":0,"rate_max":10,"thresholds":[
            {"lower":0,"upper":"collapse","inclusive":false,"message":"失控须大于 0"},
            {"lower":"collapse","upper":"ring","inclusive":false,"message":"紧急须大于失控"},
            {"lower":"ring","upper":"ring_reset","inclusive":true,"message":"复位须不小于紧急"},
            {"lower":"ring_reset","upper":"voiced","inclusive":false,"message":"轻度须大于复位"},
            {"lower":"voiced","upper":100,"inclusive":false,"message":"轻度须小于 100"}
        ]}"#,
    )
    .unwrap();
    assert!(tuning().validate(&rules).is_ok());
    let mut bad = tuning();
    bad.ring = 70.0;
    assert_eq!(bad.validate(&rules).unwrap_err(), "复位须不小于紧急");
    bad = tuning();
    bad.labor_rate = 11.0;
    assert!(bad.validate(&rules).is_err());
}
