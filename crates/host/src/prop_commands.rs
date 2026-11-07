//! 作者操作：校验/保存定义与放置实例。世界动作仍使用内核原命令检查。
//! 世界标识与就绪门槛在 runtime 统一检查，这里只做各自的事务。
use crate::runtime::{Outcome, Runtime};
use host::{props::CORE_PREFIX, HostError};
use kernel::props::{Definition, Instance, MissingMaterial, Placement};
use protocol::{ContentCommand, PlaceNear, PlaceRef, PropPreview, PropsCatalog, ServerMsg};
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};

impl Runtime {
    pub(crate) fn props_message(&self) -> ServerMsg {
        let catalog = &self.prop_library.catalog;
        let definition_actions = catalog
            .definitions
            .iter()
            .map(|(id, d)| (id.clone(), action_descriptions(d)))
            .collect();
        let locations = self
            .world
            .topo
            .places
            .iter()
            .map(|p| PlaceRef {
                id: p.locale.clone(),
                name: p.name.clone(),
                residential: p.residential,
            })
            .collect();
        let catalog = PropsCatalog {
            capabilities: kernel::props::capabilities(),
            definition_actions,
            definitions: catalog.definitions.values().map(definition_json).collect(),
            instances: self.world.prop_views(),
            locations,
            persistent: self.prop_library.persistent(),
            schema_version: CATALOG_SCHEMA_VERSION,
            spatial: self.world.spatial_overrides(),
            world_id: self.population.world_id.clone(),
        };
        ServerMsg::Props { catalog }
    }

    /// 道具命令的统一回执：失败时带说明文字；成功后全员刷新道具列表。
    fn prop_reply(&self, request_id: String, result: Result<PropPreview, String>) -> Outcome {
        self.prop_reply_saying(request_id, result, "操作完成".into())
    }

    /// 成功时回执写 `done`，其余同 prop_reply。
    fn prop_reply_saying(
        &self,
        request_id: String,
        result: Result<PropPreview, String>,
        done: String,
    ) -> Outcome {
        let (ok, message, preview) = match result {
            Ok(preview) => (true, done, Some(preview)),
            Err(e) => (false, e, None),
        };
        let outcome = Outcome::reply(ServerMsg::PropResult {
            request_id,
            ok,
            message,
            preview,
        });
        if ok {
            outcome.and_all(self.props_message())
        } else {
            outcome
        }
    }

    pub(crate) fn validate_prop(&self, request_id: String, definition: Value) -> Outcome {
        let result = decode_definition(definition)
            .map(|d| PropPreview::Definition {
                actions: Some(action_descriptions(&d)),
                definition: definition_json(&d),
            })
            .map_err(|e| e.to_string());
        self.prop_reply(request_id, result)
    }

    pub(crate) fn save_prop(&mut self, request_id: String, definition: Value) -> Outcome {
        let result = decode_definition(definition)
            .and_then(|d| {
                self.prop_library.save(d.clone())?;
                Ok(PropPreview::Definition {
                    actions: None,
                    definition: definition_json(&d),
                })
            })
            .map_err(|e| e.to_string());
        self.prop_reply(request_id, result)
    }

    /// 移除是事务：世界改动加存盘，失败时恢复移除前的状态。
    pub(crate) fn remove_prop(&mut self, request_id: String, id: &str) -> Outcome {
        let before = self.world.missing_materials();
        let result = self
            .transact(|rt| rt.world.remove_prop(id))
            .map(|()| PropPreview::Done {})
            .map_err(|aborted| aborted.to_string());
        let done = self.done_noting(&before);
        self.prop_reply_saying(request_id, result, done)
    }

    pub(crate) fn place_prop(
        &mut self,
        request_id: String,
        instance: Value,
        near: Option<PlaceNear>,
    ) -> Outcome {
        let before = self.world.missing_materials();
        let result = self.place_library_prop(instance, near);
        let done = self.done_noting(&before);
        self.prop_reply_saying(request_id, result, done)
    }

    /// 摆道具界面要的格子：各地点哪些格子能放、不能放的为什么。只回给发问的页面。
    pub(crate) fn placement_grid(&self, request_id: String) -> Outcome {
        Outcome::reply(ServerMsg::PlacementGrid {
            request_id,
            grids: self.world.placement_grids(),
        })
    }

    /// 试放：照真放的校验和选点算出这件会落在哪，不改世界、不存档。
    pub(crate) fn preview_placement(
        &self,
        request_id: String,
        instance: Value,
        near: Option<PlaceNear>,
    ) -> Outcome {
        let result = self.library_placement(instance).and_then(|placement| {
            self.world
                .preview_placement(&placement, near.as_ref())
                .map_err(|e| e.to_string())
        });
        let (ok, message, spot) = match result {
            Ok(spot) => (true, String::new(), spot),
            Err(e) => (false, e, None),
        };
        Outcome::reply(ServerMsg::PlacementPreview {
            request_id,
            ok,
            message,
            spot,
        })
    }

    /// 布置检查：这次放下或拿走以后新出现的材料缺口写进回执，比如放了营地空地却没有木头的来处。
    fn done_noting(&self, before: &BTreeSet<MissingMaterial>) -> String {
        let mut gaps: BTreeMap<(String, String), Vec<String>> = BTreeMap::new();
        for m in self.world.missing_materials().difference(before) {
            gaps.entry((m.prop.clone(), m.action.clone()))
                .or_default()
                .push(m.item.clone());
        }
        if gaps.is_empty() {
            return "操作完成".into();
        }
        let gaps: Vec<String> = gaps
            .into_iter()
            .map(|((prop, action), items)| format!("{prop}的「{action}」要{}", items.join("、")))
            .collect();
        format!(
            "操作完成。注意：{}，这张图上没有地方能弄到",
            gaps.join("；")
        )
    }

    pub(crate) fn content_command(
        &mut self,
        request_id: String,
        command: ContentCommand,
    ) -> Outcome {
        let result = self.manage_content(command);
        self.prop_reply(request_id, result)
    }

    /// 作品的张贴、修订与撤下是事务，失败时恢复到命令前；查看详情只读。
    fn manage_content(&mut self, command: ContentCommand) -> Result<PropPreview, String> {
        use protocol::ContentCommand::*;
        let read_only = matches!(command, Detail { .. });
        let change = |rt: &mut Self| match command {
            Detail { id } => rt.world.content_detail(&id),
            Create {
                id,
                locale,
                title,
                author,
                text,
                board,
            } => rt
                .world
                .create_content(id, locale, title, author, text, board),
            Revise {
                id,
                expected_version,
                title,
                author,
                text,
            } => rt
                .world
                .revise_bulletin(&id, expected_version, title, author, text),
            Withdraw {
                id,
                expected_version,
            } => rt.world.withdraw_bulletin(&id, expected_version),
        };
        let preview = |detail| PropPreview::Content(Box::new(detail));
        if read_only {
            return change(self).map(preview).map_err(|e| e.to_string());
        }
        self.transact(change)
            .map(preview)
            .map_err(|aborted| aborted.to_string())
    }

    /// 放置（含替换同编号的已有实例）是事务，失败时恢复到放置前。
    fn place_library_prop(
        &mut self,
        instance: Value,
        near: Option<PlaceNear>,
    ) -> Result<PropPreview, String> {
        let placement = self.library_placement(instance)?;
        self.transact(|rt| rt.world.place_prop_near(placement, near.as_ref()))
            .map_err(|aborted| aborted.to_string())?;
        Ok(PropPreview::Done {})
    }

    /// 页面发来的实例配上道具库里的定义；新实例编号须带玩家前缀。
    fn library_placement(&self, instance: Value) -> Result<Placement, String> {
        let instance: Instance =
            serde_json::from_value(instance).map_err(|e| format!("实例格式错误：{e}"))?;
        if !instance.id.starts_with(USER_PREFIX) {
            return Err(format!("新放置实例编号须使用 {USER_PREFIX} 前缀"));
        }
        let definition = self
            .prop_library
            .catalog
            .definitions
            .get(&instance.definition)
            .ok_or("道具版本不存在")?
            .clone();
        Ok(Placement {
            instance,
            definition,
        })
    }
}

/// 道具目录的格式版本。
const CATALOG_SCHEMA_VERSION: u32 = 1;
/// 玩家放置的道具实例编号前缀。
const USER_PREFIX: &str = "user:";
/// 一份道具定义 JSON 的字节上限。
const DEFINITION_MAX_BYTES: usize = 128_000;

fn action_descriptions(d: &Definition) -> Vec<protocol::PropActionView> {
    d.actions
        .iter()
        .map(kernel::props::action_description)
        .collect()
}

/// 道具定义原文；定义是内核类型，线上按它的 JSON 原样发出。
fn definition_json(d: &Definition) -> Value {
    serde_json::to_value(d).expect("道具定义可以序列化")
}

fn decode_definition(value: Value) -> Result<Definition, HostError> {
    if value.to_string().len() > DEFINITION_MAX_BYTES {
        return Err(HostError::Props("道具定义过大".into()));
    }
    let d: Definition = serde_json::from_value(value)
        .map_err(|e| HostError::Props(format!("道具格式错误：{e}")))?;
    d.validate()?;
    if d.readable
        .as_ref()
        .is_some_and(|t| !matches!(t.origin, kernel::content::Origin::Player))
        && !d.id.starts_with(CORE_PREFIX)
    {
        return Err(HostError::Props(
            "用户库作品来源须为 player，不能伪造系统作者身份".into(),
        ));
    }
    Ok(d)
}
