//! 建镇。生成器是 JS（scripts/mapgen），在网页的工作线程里跑（应用里没有 Node）；这里只做网页做不了的事：
//! 让模型理解小镇描述、按 host 的规则校验生成好的地图、暂存草稿、保存成小镇。/options 回答
//! generation: 'client'，网页据此自己生成、走 /drafts 交成品（frontend/town-2d/src/launcher/localCreation.ts）。
use crate::error::ApiError;
use crate::storage::{check_identity, safe_id, town_creation, Storage};
use host::application::Application;
use serde_json::{json, Value};
use std::path::Path;
use std::sync::Mutex;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

/// 草稿只放内存：最多 24 份，每份两小时后过期，服务重启即清空。
const DRAFT_LIMIT: usize = 24;
const DRAFT_TTL: Duration = Duration::from_secs(2 * 60 * 60);
/// 小镇描述的字数上限，与 town-map 相同。
const DESCRIPTION_MAX_CHARS: usize = 2000;
const MAX_REQUEST_ID: usize = 120;

struct Draft {
    id: String,
    document: Value,
    version: String,
    expires: Instant,
}

#[derive(Default)]
pub struct Drafts {
    /// 先放进来的在前，满了丢最早的
    entries: Mutex<Vec<Draft>>,
}

pub(crate) fn load_app(config: &Path) -> Result<Application, ApiError> {
    let text = std::fs::read_to_string(config)?;
    serde_json::from_str(&text).map_err(|e| ApiError::bad(format!("应用配置无法解析：{e}")))
}

/// 设定中心选的小镇工具模型，连同服务商的显示名。
fn active_model(app: &Application) -> Result<(host::llm::LlmTarget, String), ApiError> {
    let providers = host::config::load_providers(&app.providers_path)?;
    let active = providers
        .active
        .as_ref()
        .ok_or_else(|| ApiError::bad("请先在首页的「设定」里连接一个模型"))?;
    let name = providers
        .providers
        .iter()
        .find(|p| p.id == active.provider)
        .map(|p| p.name.clone())
        .ok_or_else(|| ApiError::bad("服务商不存在"))?;
    let credentials = host::config::load_credentials(&app.credentials_path)?;
    let target = host::llm::LlmTarget::active(&providers, &credentials)
        .ok_or_else(|| ApiError::bad("服务商不存在"))?;
    Ok((target, name))
}

/// 建镇页的选项：地点模板、上限这些网页自己有，这里只回答模型能不能用。
pub fn options(config: &Path) -> Value {
    let model = match load_app(config).and_then(|app| active_model(&app)) {
        Ok((target, provider)) => {
            json!({ "available": true, "provider": provider, "model": target.model })
        }
        Err(e) => json!({ "available": false, "error": e.message }),
    };
    json!({ "generation": "client", "model": model })
}

/// 一句话描述 → 结构化要求（模型调一次）。要求是否合规由网页按生成器的规则检查。
pub fn parse(config: &Path, body: &Value) -> Result<Value, ApiError> {
    let app = load_app(config)?;
    let (target, provider) = active_model(&app)?;
    let description = body["description"]
        .as_str()
        .ok_or_else(|| ApiError::bad("请填写小镇描述"))?;
    if description.trim().is_empty() || description.chars().count() > DESCRIPTION_MAX_CHARS {
        return Err(ApiError::bad(format!(
            "描述须为 1–{DESCRIPTION_MAX_CHARS} 字"
        )));
    }
    // 模型只能用建镇页卡片上有的地点；地点表由页面随请求给（生成器在页面里跑）
    let kinds = agent::completion::plan_kinds(&body["templates"]).map_err(ApiError::bad)?;
    let revision = agent::completion::plan_revision(body).map_err(ApiError::bad)?;
    let prompt =
        agent::completion::planner_prompt(&body["seed"], description, &kinds, revision.as_ref());
    let text = host::llm::chat_completion(&target, &prompt)
        .map_err(|e| ApiError::bad(format!("模型请求失败：{e}")))?;
    let mut parsed = agent::completion::parse_plan(&text)
        .map_err(|e| ApiError::bad(format!("模型回复无法理解：{e}")))?;
    parsed["model"] = json!(target.model);
    parsed["provider"] = json!(provider);
    parsed["calls"] = json!(1);
    Ok(parsed)
}

impl Drafts {
    /// 网页生成好的地图：先按 host 的规则校验（道路、地点、道具、场景包都要对得上），再暂存成草稿。
    pub fn put(&self, config: &Path, body: &Value) -> Result<Value, ApiError> {
        let document = &body["document"];
        let app = load_app(config)?;
        let catalog = host::props::PropLibrary::load(
            &app.prop_catalog_path,
            &app.legacy_prop_catalog_path,
            None,
            document,
        )?
        .catalog;
        host::maps::validate(document, &catalog, Path::new(&app.scene_assets_path))?;
        check_identity(document)?;
        let version = document["content_hash"]
            .as_str()
            .unwrap_or_default()
            .to_owned();
        let id = format!("draft-{}", crate::token());
        let mut entries = self.entries.lock().unwrap();
        entries.retain(|d| d.expires > Instant::now());
        if entries.len() >= DRAFT_LIMIT {
            entries.remove(0);
        }
        entries.push(Draft {
            id: id.clone(),
            document: document.clone(),
            version: version.clone(),
            expires: Instant::now() + DRAFT_TTL,
        });
        let expires_at = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0)
            + DRAFT_TTL.as_millis() as u64;
        Ok(json!({ "id": id, "version": version, "expires_at": expires_at }))
    }

    /// 保存草稿：小镇编号由草稿编号换前缀得到，同一份草稿重复保存得到同一个小镇。
    pub fn save(&self, storage: &Storage, body: &Value) -> Result<Value, ApiError> {
        let draft_id = safe_id(body["draft_id"].as_str().unwrap_or_default())?;
        let request_id = body["request_id"]
            .as_str()
            .filter(|r| r.len() <= MAX_REQUEST_ID)
            .ok_or_else(|| ApiError::bad("保存操作编号无效"))?;
        let (document, version) = {
            let entries = self.entries.lock().unwrap();
            let draft = entries
                .iter()
                .find(|d| d.id == draft_id && d.expires > Instant::now())
                .ok_or_else(|| ApiError::bad("预览草稿不存在或已过期，请重新生成"))?;
            (draft.document.clone(), draft.version.clone())
        };
        if body["expected_version"].as_str() != Some(version.as_str()) {
            return Err(ApiError::bad("预览版本已变化，请重新预览"));
        }
        let document = renamed(document, &body["name"])?;
        let creation = town_creation(&body["creation"])?;
        let hash = document["content_hash"].clone();
        // 预制小镇存成固定编号 prefab-<编号>，列表里当内置小镇
        let town_id = match &body["town_id"] {
            Value::Null => draft_id.replacen("draft-", "town-", 1),
            id => id
                .as_str()
                .filter(|id| id.starts_with("prefab-") && id.len() <= 67 && safe_id(id).is_ok())
                .ok_or_else(|| ApiError::bad("预制小镇编号无效"))?
                .to_owned(),
        };
        storage.create(
            &town_id,
            &document,
            &json!({ "request_id": request_id, "draft_id": draft_id, "map_hash": hash }),
            creation.as_ref(),
        )?;
        Ok(json!({ "id": town_id, "mapHash": hash }))
    }
}

/// 预览后改的名字：只换名字、重算摘要，布局不变，不用重新生成。
fn renamed(mut document: Value, name: &Value) -> Result<Value, ApiError> {
    if name.is_null() {
        return Ok(document);
    }
    let name = name
        .as_str()
        .map(str::trim)
        .filter(|n| !n.is_empty() && n.chars().count() <= 60)
        .ok_or_else(|| ApiError::bad("名称须为 1–60 个字符"))?;
    if document["name"] == name {
        return Ok(document);
    }
    document["name"] = json!(name);
    if document["generation"]["spec"].is_object() {
        document["generation"]["spec"]["name"] = json!(name);
        let input = host::maps::hash(&document["generation"]["spec"]);
        document["generation"]["input_hash"] = json!(input);
    }
    let hash = host::maps::hash(&document);
    document["content_hash"] = json!(hash);
    Ok(document)
}
