//! 小镇目录：每个小镇一份地图副本与它的存档与日志。与 scripts/towns/storage.mjs 同构。
use crate::error::ApiError;
use serde_json::{json, Value};
use std::fs;
use std::path::{Path, PathBuf};

/// 应用发布的默认地图。
pub const BUILTIN_MAP: &str = "data/maps/2d-town/map.json";
pub const BUILTIN_TOWN: &str = "default-town";

pub struct Storage {
    /// 用户数据目录：towns/、config/。
    pub root: PathBuf,
    /// 应用自带的数据：data/、config/（只读）。
    pub app: PathBuf,
}

pub fn safe_id(id: &str) -> Result<&str, ApiError> {
    let mut chars = id.chars();
    let first_ok = chars
        .next()
        .is_some_and(|c| c.is_ascii_lowercase() || c.is_ascii_digit());
    let rest_ok = chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-');
    if first_ok && rest_ok && id.len() <= 91 {
        Ok(id)
    } else {
        Err(ApiError::bad("小镇编号无效"))
    }
}

pub fn read_json(path: &Path) -> Result<Value, ApiError> {
    let text = fs::read(path)?;
    serde_json::from_slice(&text).map_err(|e| ApiError::bad(format!("文件格式无效：{e}")))
}

pub fn write_json(path: &Path, value: &Value) -> Result<(), ApiError> {
    let text = serde_json::to_vec_pretty(value).map_err(|e| ApiError::bad(e.to_string()))?;
    host::persistence::atomic_write(path, &[text, b"\n".to_vec()].concat())?;
    Ok(())
}

/// 旧 3D 地图仍留在用户目录；列表隐藏，直接打开也拒绝。
fn supports_hd2d(document: &Value) -> bool {
    let views = &document["views"];
    document.get("renderer").is_none()
        && views["default"].as_str().is_none_or(|v| v == "2d")
        && views["available"]
            .as_array()
            .is_none_or(|a| a.iter().all(|v| v == "2d"))
}

/// 版本、显示样式与内容摘要都对得上才算这张地图。
pub fn check_identity(document: &Value) -> Result<(), ApiError> {
    let schema = document["schema_version"].as_u64();
    if !matches!(schema, Some(1 | 2))
        || document["style_id"] != "svg-town-v1"
        || document["style_version"] != 1
    {
        return Err(ApiError::bad("不支持的地图或显示版本"));
    }
    if document["content_hash"].as_str() != Some(host::maps::hash(document).as_str()) {
        return Err(ApiError::bad("地图内容摘要不一致"));
    }
    Ok(())
}

/// 一句话建镇时的描述、世界观建议和推荐的居民，和小镇放在一起（creation.json）：换设备、换成电脑版
/// 打开也还在。逐步设置的小镇没有这个文件。从预制小镇开的一局另记 prefab（预制小镇的编号），进镇时按它
/// 出开局设置。规则与电脑版（scripts/towns/storage.mjs 的 townCreation）相同。
pub fn town_creation(value: &Value) -> Result<Option<Value>, ApiError> {
    if value.is_null() {
        return Ok(None);
    }
    let invalid = || ApiError::bad("建镇说明无效");
    if !value.is_object() {
        return Err(invalid());
    }
    let text = |item: &Value, max: usize| match item {
        Value::Null => Ok(String::new()),
        Value::String(s) if s.trim().chars().count() <= max => Ok(s.trim().to_owned()),
        _ => Err(invalid()),
    };
    let residents = match &value["residents"] {
        Value::Null => Vec::new(),
        Value::Array(items) if items.len() <= 5 => items
            .iter()
            .map(|item| {
                text(item, 300).and_then(|r| (!r.is_empty()).then_some(r).ok_or_else(invalid))
            })
            .collect::<Result<_, _>>()?,
        _ => return Err(invalid()),
    };
    let mut creation = json!({
        "description": text(&value["description"], 2000)?,
        "worldview": text(&value["worldview"], 6000)?,
        "residents": residents,
    });
    match &value["prefab"] {
        Value::Null => {}
        Value::String(id) if prefab_id(id) => creation["prefab"] = json!(id),
        _ => return Err(invalid()),
    }
    Ok(Some(creation))
}

/// 预制小镇的编号：小写字母、数字和连字符，字母或数字开头，最多 40 个字符。
fn prefab_id(id: &str) -> bool {
    let mut chars = id.chars();
    chars
        .next()
        .is_some_and(|c| c.is_ascii_lowercase() || c.is_ascii_digit())
        && id.len() <= 40
        && chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
}

pub struct TownMap {
    pub document: Value,
    /// 地图文件原文，发给页面时不再序列化一遍。
    pub bytes: Vec<u8>,
    pub hash: String,
}

/// 读不到地图时，旧 3D 地图与其他错误要分开：前者在列表里跳过。
pub enum MapError {
    Retired3d,
    Other(ApiError),
}

impl From<ApiError> for MapError {
    fn from(e: ApiError) -> Self {
        Self::Other(e)
    }
}

impl From<MapError> for ApiError {
    fn from(e: MapError) -> Self {
        match e {
            MapError::Retired3d => {
                ApiError::bad("此地图属于已停用的 3D 版本，存档保留，请使用 HD-2D 小镇")
            }
            MapError::Other(e) => e,
        }
    }
}

impl Storage {
    pub fn new(root: PathBuf, app: PathBuf) -> Self {
        Self { root, app }
    }

    pub fn town(&self, id: &str) -> Result<PathBuf, ApiError> {
        Ok(self.root.join("towns").join(safe_id(id)?))
    }

    /// 第一次运行时把默认地图放进用户目录。
    pub fn init(&self) -> Result<(), ApiError> {
        fs::create_dir_all(self.root.join("towns"))?;
        if self.town(BUILTIN_TOWN)?.join("map.json").exists() {
            return Ok(());
        }
        let document = read_json(&self.app.join(BUILTIN_MAP))?;
        self.create(
            BUILTIN_TOWN,
            &document,
            &json!({ "origin": "builtin" }),
            None,
        )
    }

    /// 新建一个小镇目录：地图和来源记录先写进临时目录，再整个改名，不会留下半个小镇。
    /// 同一次保存重复提交时目录已经在了：地图相同就算成功，不同就拒绝。
    pub fn create(
        &self,
        id: &str,
        document: &Value,
        receipt: &Value,
        creation: Option<&Value>,
    ) -> Result<(), ApiError> {
        if !supports_hd2d(document) {
            return Err(ApiError::bad("只能保存 HD-2D 地图"));
        }
        check_identity(document)?;
        let dir = self.town(id)?;
        let existing = || -> Result<bool, ApiError> {
            if !dir.join("map.json").exists() {
                return Ok(false);
            }
            let old = read_json(&dir.join("map.json"))?;
            if old["content_hash"] != document["content_hash"] {
                return Err(ApiError::bad("同一个保存操作对应不同的地图"));
            }
            Ok(true)
        };
        if existing()? {
            return Ok(());
        }
        let saving = self
            .root
            .join("towns")
            .join(format!(".saving-{}", crate::token()));
        fs::create_dir_all(&saving)?;
        let written = write_json(&saving.join("map.json"), document)
            .and_then(|_| write_json(&saving.join("receipt.json"), receipt))
            .and_then(|_| match creation {
                Some(creation) => write_json(&saving.join("creation.json"), creation),
                None => Ok(()),
            })
            .and_then(|_| fs::rename(&saving, &dir).map_err(ApiError::from));
        if written.is_err() {
            let _ = fs::remove_dir_all(&saving);
            // 两个并发保存同时落盘：先到者已经建好了目录
            if existing()? {
                return Ok(());
            }
        }
        written
    }

    pub fn load(&self, id: &str) -> Result<TownMap, MapError> {
        let bytes = fs::read(self.town(id)?.join("map.json")).map_err(ApiError::from)?;
        let document: Value = serde_json::from_slice(&bytes)
            .map_err(|e| ApiError::bad(format!("地图数据无法解析：{e}")))?;
        check_identity(&document)?;
        if !supports_hd2d(&document) {
            return Err(MapError::Retired3d);
        }
        let hash = document["content_hash"]
            .as_str()
            .unwrap_or_default()
            .to_owned();
        Ok(TownMap {
            document,
            bytes,
            hash,
        })
    }

    pub fn map(&self, id: &str) -> Result<TownMap, ApiError> {
        Ok(self.load(id)?)
    }

    /// 一句话建镇时记下的说明；没有或读不出时为 null。
    pub fn creation(&self, id: &str) -> Value {
        self.town(id)
            .ok()
            .and_then(|dir| read_json(&dir.join("creation.json")).ok())
            .and_then(|value| town_creation(&value).ok().flatten())
            .unwrap_or(Value::Null)
    }

    /// 名称、简介和建镇说明。内置小镇的名称与简介跟随应用版本；小镇目录里的地图副本不改，
    /// 它的摘要是存档身份。一句话建的小镇，简介写玩家当时那句话。
    pub fn labels(&self, id: &str, document: &Value) -> (String, String, Value) {
        let builtin = id == BUILTIN_TOWN;
        let source = if builtin {
            read_json(&self.app.join(BUILTIN_MAP)).unwrap_or_else(|_| document.clone())
        } else {
            document.clone()
        };
        let text = |key: &str| source[key].as_str().unwrap_or_default().to_owned();
        let creation = if builtin {
            Value::Null
        } else {
            self.creation(id)
        };
        let description = creation["description"]
            .as_str()
            .filter(|d| !d.is_empty())
            .map(str::to_owned)
            .unwrap_or_else(|| text("description"));
        (text("name"), description, creation)
    }

    /// 小镇显示的名字；地图读不出时用编号。
    pub fn name(&self, id: &str) -> String {
        self.map(id)
            .map(|map| self.labels(id, &map.document).0)
            .ok()
            .filter(|name| !name.is_empty())
            .unwrap_or_else(|| id.to_owned())
    }

    /// 内置小镇：随应用发的 default-town，和预制玩法的 prefab-<编号>（第一次选中时生成，只能重新开始）
    pub fn can_delete(&self, id: &str) -> bool {
        id != BUILTIN_TOWN && !id.starts_with("prefab-")
    }

    /// reset：重新开始预制小镇，允许删掉内置的 prefab-<编号>
    pub fn remove(&self, id: &str, reset: bool) -> Result<(), ApiError> {
        let allowed = if reset { id.starts_with("prefab-") } else { self.can_delete(id) };
        if !allowed {
            return Err(ApiError::new(403, "内置地图不能删除"));
        }
        self.map(id)?;
        let dir = self.town(id)?;
        // 不跟随小镇目录的符号链接，避免删除目录外的数据。
        let meta = fs::symlink_metadata(&dir)?;
        if !meta.is_dir() || meta.file_type().is_symlink() {
            return Err(ApiError::bad("小镇目录无效"));
        }
        fs::remove_dir_all(&dir)?;
        Ok(())
    }

    /// 小镇列表上的进度：玩到第几天、住了几个人。读存档 world.json，还没开始过的小镇是 null。
    /// 电脑上的管理服务（scripts/towns/storage.mjs）按同样的规则算，两边的 /api/towns 保持一致。
    fn progress(&self, id: &str) -> Value {
        #[derive(serde::Deserialize)]
        struct Save {
            world: SaveWorld,
            #[serde(default)]
            population: Option<SavePopulation>,
        }
        #[derive(serde::Deserialize)]
        struct SaveWorld {
            minutes: f64,
        }
        #[derive(serde::Deserialize)]
        struct SavePopulation {
            #[serde(default)]
            residents: std::collections::BTreeMap<String, serde::de::IgnoredAny>,
        }
        let path = self.root.join("towns").join(id).join("world.json");
        let Ok(text) = fs::read(path) else {
            return Value::Null;
        };
        match serde_json::from_slice::<Save>(&text) {
            Ok(save) => json!({
                "day": (save.world.minutes / 1440.0).floor() as i64 + 1,
                "residents": save.population.map_or(0, |p| p.residents.len()),
            }),
            Err(_) => Value::Null,
        }
    }

    pub fn list(&self) -> Result<Vec<Value>, ApiError> {
        let mut towns = Vec::new();
        for entry in fs::read_dir(self.root.join("towns"))? {
            let entry = entry?;
            let name = entry.file_name().to_string_lossy().into_owned();
            if !entry.file_type()?.is_dir() || name.starts_with('.') || safe_id(&name).is_err() {
                continue;
            }
            match self.load(&name) {
                Ok(map) => {
                    let (title, description, creation) = self.labels(&name, &map.document);
                    towns.push(json!({
                        "id": name,
                        "deletable": self.can_delete(&name),
                        "name": title,
                        "description": description,
                        "creation": creation,
                        "version": map.document["schema_version"].to_string(),
                        "views": ["2d"],
                        "clientKind": "town-2d",
                        "available": true,
                        "mapHash": map.hash,
                        "origin": map.document.get("origin").cloned().unwrap_or(Value::Null),
                        "progress": self.progress(&name),
                    }));
                }
                Err(MapError::Retired3d) => {}
                Err(MapError::Other(e)) => towns.push(json!({
                    "id": name,
                    "deletable": self.can_delete(&name),
                    "name": name,
                    "description": format!("地图数据无法读取：{}", e.message),
                    "available": false,
                    "clientKind": "town-2d",
                })),
            }
        }
        towns.sort_by(|a, b| {
            // 自带的小镇、预制小镇，再是玩家建的
            let rank = |t: &Value| match t["id"].as_str() {
                Some(BUILTIN_TOWN) => 0,
                Some(id) if id.starts_with("prefab-") => 1,
                _ => 2,
            };
            rank(a)
                .cmp(&rank(b))
                .then_with(|| a["name"].as_str().cmp(&b["name"].as_str()))
        });
        Ok(towns)
    }
}

/// 应用配置：服务商与密钥放在用户目录（第一次从应用自带的复制，不覆盖），自定义村民库也在用户目录，
/// 其余路径指向应用自带的数据。
pub fn setup_config(root: &Path, app: &Path) -> Result<PathBuf, ApiError> {
    let mut config = read_json(&app.join("config/application.json"))?;
    let absolute = |p: &str| app.join(p).to_string_lossy().into_owned();
    for field in ["providers_path", "credentials_path"] {
        let name = config[field]
            .as_str()
            .and_then(|p| Path::new(p).file_name())
            .map(|n| n.to_owned())
            .ok_or_else(|| ApiError::bad(format!("应用配置缺少 {field}")))?;
        let dest = root.join("config").join(name);
        if !dest.exists() {
            let value = config[field]
                .as_str()
                .and_then(|p| read_json(&app.join(p)).ok())
                .unwrap_or_else(|| json!({}));
            write_json(&dest, &value)?;
        }
        config[field] = Value::from(dest.to_string_lossy().into_owned());
    }
    // 自定义村民模板所有小镇共用一份，放在用户目录下；旧版存在各小镇目录里的由 host 开镇时收进来
    config["custom_library_path"] =
        Value::from(root.join("resident-library").to_string_lossy().into_owned());
    let defaults = [
        ("prop_catalog_path", "data/props/core/definitions.json"),
        (
            "legacy_prop_catalog_path",
            "data/props/compatibility/retired-core-20260925.json",
        ),
        ("scene_assets_path", "data/scene-assets"),
        (
            "compatibility_path",
            "data/props/compatibility/physiology-v1.json",
        ),
        ("resident_library_path", "config/resident-library"),
        ("topology_path", BUILTIN_MAP),
        ("needs_rules_path", "config/needs_rules.json"),
        ("weather_rules_path", "config/weather_rules.json"),
        // 内置模型的推理程序随应用包放在这里，没带时设定里不出现
        ("builtin_model_path", "builtin-model"),
    ];
    for (field, fallback) in defaults {
        let relative = config[field].as_str().unwrap_or(fallback).to_owned();
        config[field] = Value::from(absolute(&relative));
    }
    // 模型文件不随应用带，下载到用户目录；电脑版和 mac 版共用一个数据目录，只下一份
    config["builtin_model_store"] =
        Value::from(root.join("builtin-model").to_string_lossy().into_owned());
    let dest = root.join("config/application.json");
    write_json(&dest, &config)?;
    Ok(dest)
}
