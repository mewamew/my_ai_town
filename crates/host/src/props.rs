//! 道具库的版本化磁盘存储。库不保存地图摆放和世界运行状态。
//! 内置道具也是数据文件，由这里读入；内核不内嵌任何道具定义。
use crate::persistence::atomic_write;
use crate::HostError;
use kernel::props::{Catalog, Definition};
use std::{
    collections::BTreeSet,
    fs,
    io::ErrorKind,
    path::{Path, PathBuf},
};

/// 内置道具的命名空间前缀；用户库不能占用。
pub const CORE_PREFIX: &str = "core:";

/// 读一份道具库文件（内置库或测试用同一份数据）。
pub fn load_catalog(path: &str) -> Result<Catalog, HostError> {
    let text = fs::read_to_string(path)
        .map_err(|e| HostError::Props(format!("读取道具库 {path} 失败：{e}")))?;
    Ok(Catalog::from_json(&text)?)
}

pub struct PropLibrary {
    pub catalog: Catalog,
    root: Option<PathBuf>,
    /// 地图文件自己摆的道具用到的定义编号：每次开镇都要按它们找定义，删不得。
    map_uses: BTreeSet<String>,
}
impl PropLibrary {
    pub fn load(
        builtin: &str,
        legacy: &str,
        root: Option<&Path>,
        map_document: &serde_json::Value,
    ) -> Result<Self, HostError> {
        let mut catalog = load_catalog(builtin)?;
        let referenced: BTreeSet<_> = map_document
            .get("topology")
            .unwrap_or(map_document)
            .get("props")
            .and_then(serde_json::Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(|prop| prop.get("definition").and_then(serde_json::Value::as_str))
            .collect();
        for definition in load_catalog(legacy)?.definitions.into_values() {
            if referenced.contains(definition.reference().as_str()) {
                catalog.insert(definition)?;
            }
        }
        let map_uses = referenced
            .iter()
            .map(|reference| reference.split('@').next().unwrap_or(reference).to_owned())
            .collect();
        let root = root.map(|p| p.join("prop-library"));
        if let Some(root) = &root {
            if root.is_dir() {
                for entry in fs::read_dir(root).map_err(|e| HostError::Props(e.to_string()))? {
                    let path = entry.map_err(|e| HostError::Props(e.to_string()))?.path();
                    if path.extension().is_some_and(|x| x == "json") {
                        catalog.insert(read_definition(&path)?)?;
                    }
                }
            }
        }
        Ok(Self {
            catalog,
            root,
            map_uses,
        })
    }
    pub fn persistent(&self) -> bool {
        self.root.is_some()
    }
    /// 删掉自己做的一件道具：这个编号的所有版本连同道具库里的文件，返回最新一版的名字。
    /// 不碰存档：镇上已经摆着的、背包里的各自存着整份定义，照样能用。
    pub fn delete(&mut self, id: &str) -> Result<String, HostError> {
        if id.starts_with(CORE_PREFIX) {
            return Err(HostError::Props("自带的道具删不了".into()));
        }
        let name = self
            .catalog
            .definitions
            .values()
            .filter(|d| d.id == id)
            .max_by_key(|d| d.version)
            .map(|d| d.name.clone())
            .ok_or_else(|| HostError::Props("道具库里没有这件道具，可能已经删掉了".into()))?;
        if self.map_uses.contains(id) {
            return Err(HostError::Props(format!(
                "地图本身摆着「{name}」，删了小镇就打不开了"
            )));
        }
        if let Some(root) = &self.root {
            remove_files(root, id)?;
        }
        self.catalog.definitions.retain(|_, d| d.id != id);
        Ok(name)
    }
    pub fn save(&mut self, d: Definition) -> Result<(), HostError> {
        d.validate()?;
        if d.id.starts_with(CORE_PREFIX) {
            return Err(HostError::Props(
                "内置道具不能覆盖，请复制到自己的命名空间".into(),
            ));
        }
        if self.catalog.definitions.len() >= 4096
            && !self.catalog.definitions.contains_key(&d.reference())
        {
            return Err(HostError::Props("道具库数量已达上限".into()));
        }
        let mut next = self.catalog.clone();
        next.insert(d.clone())?;
        if let Some(root) = &self.root {
            let path = root.join(format!(
                "{}-{}.json",
                d.id.bytes().map(|b| format!("{b:02x}")).collect::<String>(),
                d.version
            ));
            let bytes =
                serde_json::to_vec_pretty(&d).map_err(|e| HostError::Props(e.to_string()))?;
            atomic_write(&path, &bytes)?;
        }
        self.catalog = next;
        Ok(())
    }
}

/// 道具库文件夹里定义这个编号的文件，哪一版都删。保存时文件按编号起名，手放进来的就不一定，
/// 所以按内容认。已经不在的不算失败：删了一半出错时，再删一次能删完。
fn remove_files(root: &Path, id: &str) -> Result<(), HostError> {
    let entries = match fs::read_dir(root) {
        Ok(entries) => entries,
        Err(e) if e.kind() == ErrorKind::NotFound => return Ok(()),
        Err(e) => return Err(HostError::Props(format!("读取道具库失败：{e}"))),
    };
    for entry in entries {
        let path = entry.map_err(|e| HostError::Props(e.to_string()))?.path();
        if path.extension().is_none_or(|x| x != "json") {
            continue;
        }
        let defines = fs::read_to_string(&path).is_ok_and(|text| {
            serde_json::from_str::<serde_json::Value>(&text)
                .is_ok_and(|d| d.get("id").and_then(serde_json::Value::as_str) == Some(id))
        });
        if !defines {
            continue;
        }
        match fs::remove_file(&path) {
            Err(e) if e.kind() != ErrorKind::NotFound => {
                return Err(HostError::Props(format!(
                    "删除道具文件 {} 失败：{e}",
                    path.display()
                )))
            }
            _ => {}
        }
    }
    Ok(())
}

fn read_definition(path: &Path) -> Result<Definition, HostError> {
    let text = fs::read_to_string(path)
        .map_err(|e| HostError::Props(format!("读取自定义道具 {} 失败：{e}", path.display())))?;
    if text.len() > 1_000_000 {
        return Err(HostError::Props(format!(
            "道具包 {} 超过大小限制",
            path.display()
        )));
    }
    let d: Definition = serde_json::from_str(&text)
        .map_err(|e| HostError::Props(format!("自定义道具文件 {} 无效：{e}", path.display())))?;
    if d.id.starts_with(CORE_PREFIX) {
        return Err(HostError::Props(format!(
            "自定义道具 {} 不能覆盖 core 命名空间",
            path.display()
        )));
    }
    Ok(d)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 旧道具库只补进地图引用到的定义。
    #[test]
    fn retired_props_only_load_for_maps_that_reference_them() {
        let dir = std::env::temp_dir().join(format!("host-props-test-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let builtin = dir.join("builtin.json");
        let legacy = dir.join("legacy.json");
        fs::write(
            &builtin,
            r#"[{"id":"test:bed","version":1,"name":"床","actions":[]}]"#,
        )
        .unwrap();
        fs::write(
            &legacy,
            r#"[{"id":"test:old-sign","version":1,"name":"旧告示","actions":[]}]"#,
        )
        .unwrap();
        let load = |map: serde_json::Value| {
            PropLibrary::load(
                builtin.to_str().unwrap(),
                legacy.to_str().unwrap(),
                None,
                &map,
            )
            .unwrap()
            .catalog
        };
        let fresh = load(serde_json::json!({"topology": {"props": []}}));
        let old = load(serde_json::json!({"topology": {"props": [
            {"definition": "test:old-sign@1"}
        ]}}));
        let _ = fs::remove_dir_all(&dir);
        assert!(fresh.definitions.contains_key("test:bed@1"));
        assert!(!fresh.definitions.contains_key("test:old-sign@1"));
        assert!(old.definitions.contains_key("test:old-sign@1"));
    }
}
