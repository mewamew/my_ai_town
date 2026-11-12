//! 模型服务的读、存与连通测试。世界进程的设定中心和管理服务（首页的「设定」）共用这一份，
//! 读写的都是 providers.json 与 credentials.json 这一对文件。
//! 回读只给密钥掩码；存密钥前先读一遍磁盘上的，别处刚存的密钥不会被旧内容盖掉。
//! 管理服务的几个请求、开着的各个小镇可能同时来存，存的时候锁着 providers.json 旁边的
//! providers.json.lock，一个存完下一个再读再存。
use crate::{application::Application, builtin, config, llm, HostError};
use protocol::{ActiveModelChoice, ProviderConfigMsg, ProviderKeyMsg, ProviderView};
use serde::Deserialize;
use serde_json::{json, Value};
use std::{fs::File, path::Path, time::Instant};

/// 配置回读：密钥只给掩码。应用带着内置模型时排在最后（请人时先用玩家自己连的服务），
/// 它不在配置文件里，也没有地址和密钥。
pub fn views(
    file: &config::ProvidersFile,
    credentials: &config::Credentials,
    with_builtin: bool,
) -> Vec<ProviderView> {
    let builtin = with_builtin.then(|| ProviderView {
        id: builtin::PROVIDER.into(),
        name: builtin::NAME.into(),
        base_url: String::new(),
        key_mask: String::new(),
    });
    // 早先的安卓测试包把一条地址固定的 builtin 写进过配置：一律以应用自带的为准
    file.providers
        .iter()
        .filter(|p| p.id != builtin::PROVIDER)
        .map(|p| ProviderView {
            id: p.id.clone(),
            name: p.name.clone(),
            base_url: p.base_url.clone(),
            key_mask: credentials
                .get(&p.id)
                .map(|k| config::mask(k))
                .unwrap_or_default(),
        })
        .chain(builtin)
        .collect()
}

/// 写入服务商表与工具模型；keys 里空密钥表示删掉那个服务商的密钥。返回写好后的密钥表。
pub fn save(
    providers_path: &str,
    credentials_path: &str,
    file: &config::ProvidersFile,
    keys: Vec<ProviderKeyMsg>,
) -> Result<config::Credentials, HostError> {
    let _lock = lock(providers_path)?;
    store(providers_path, credentials_path, file, keys)
}

/// 等到别处存完再占住这对文件，返回的句柄关掉就放开；跨进程有效。读、改、写不锁的话，
/// 两次保存交错时会同时写同一个临时文件把配置写坏，只带改动项的密钥也会被后存的盖掉。
/// 拿着锁时不能再调 save，同一个线程再锁一次会一直等下去。
fn lock(providers_path: &str) -> Result<File, HostError> {
    let path = format!("{providers_path}.lock");
    let path = Path::new(&path);
    let locked = match path.parent() {
        Some(dir) if !dir.as_os_str().is_empty() => std::fs::create_dir_all(dir),
        _ => Ok(()),
    }
    .and_then(|()| crate::persistence::private_file(path, false))
    .and_then(|file| crate::process::lock_file(&file, true).map(|()| file));
    locked.map_err(|e| HostError::Io(format!("锁定模型配置 {} 失败：{e}", path.display())))
}

/// save 去掉锁的部分，调用方先拿着 lock。
fn store(
    providers_path: &str,
    credentials_path: &str,
    file: &config::ProvidersFile,
    keys: Vec<ProviderKeyMsg>,
) -> Result<config::Credentials, HostError> {
    config::save_providers(providers_path, file)?;
    let mut credentials = config::load_credentials(credentials_path)?;
    if !keys.is_empty() {
        for key in keys {
            if key.api_key.is_empty() {
                credentials.remove(&key.provider);
            } else {
                credentials.insert(key.provider, key.api_key);
            }
        }
        config::save_credentials(credentials_path, &credentials)?;
    }
    Ok(credentials)
}

/// 连通测试的结果；连通时 message 是回复的开头。
pub struct TestOutcome {
    pub ok: bool,
    pub message: String,
    pub latency_ms: u64,
}

/// 和正式调用同一条 HTTP 通道发一句很短的话；没给临时密钥时用已存的。
pub fn test(
    provider: &ProviderConfigMsg,
    model: String,
    api_key: Option<String>,
    saved: &config::Credentials,
) -> TestOutcome {
    let target = llm::LlmTarget {
        provider: provider.id.clone(),
        model,
        base_url: provider.base_url.clone(),
        api_key: api_key
            .filter(|key| !key.is_empty())
            .or_else(|| saved.get(&provider.id).cloned()),
    };
    let start = Instant::now();
    let result = llm::chat_completion(&target, agent::completion::CONNECTION_TEST_PROMPT);
    let latency_ms = start.elapsed().as_millis() as u64;
    match result {
        Ok(text) => TestOutcome {
            ok: true,
            message: text.chars().take(80).collect(),
            latency_ms,
        },
        Err(error) => TestOutcome {
            ok: false,
            message: error.to_string(),
            latency_ms,
        },
    }
}

// ---------- 首页「设定」用的接口：管理服务直接调 ----------

#[derive(Deserialize)]
struct SaveRequest {
    active: Option<ActiveModelChoice>,
    providers: Vec<ProviderConfigMsg>,
    #[serde(default)]
    keys: Vec<ProviderKeyMsg>,
}

#[derive(Deserialize)]
struct TestRequest {
    provider: ProviderConfigMsg,
    model: String,
    #[serde(default)]
    api_key: Option<String>,
}

fn parse<T: serde::de::DeserializeOwned>(body: &Value) -> Result<T, HostError> {
    T::deserialize(body).map_err(|e| HostError::Rejected(format!("请求格式不对：{e}")))
}

/// { active, providers }，密钥只有掩码。
pub fn read(app: &Application) -> Result<Value, HostError> {
    let file = config::load_providers(&app.providers_path)?;
    let credentials = config::load_credentials(&app.credentials_path)?;
    let with_builtin = builtin::supported(app);
    Ok(json!({ "active": file.active, "providers": views(&file, &credentials, with_builtin) }))
}

/// 保存后回读。首页只能添加或修改服务商：删掉的话，用着它的村民就找不到模型了，
/// 那要进小镇的设定里删，那里会先查哪些村民在用。
pub fn write(app: &Application, body: &Value) -> Result<Value, HostError> {
    let mut request: SaveRequest = parse(body)?;
    // 页面把回读到的整表带回来，内置模型也在里面；它不进配置文件
    request.providers.retain(|p| p.id != builtin::PROVIDER);
    if request
        .providers
        .iter()
        .any(|p| p.id.trim().is_empty() || p.base_url.trim().is_empty())
    {
        return Err(HostError::Rejected("模型服务缺少编号或地址".into()));
    }
    // 查有没有少带服务商和写入要在同一把锁里：查完之后小镇里刚添的服务商，也得算在里面
    let guard = lock(&app.providers_path)?;
    let existing = config::load_providers(&app.providers_path)?;
    if let Some(gone) = existing
        .providers
        .iter()
        .find(|old| !request.providers.iter().any(|p| p.id == old.id))
    {
        return Err(HostError::Rejected(format!(
            "这里不能删除模型服务「{}」，请进入小镇后在设定里删除",
            gone.name
        )));
    }
    let file = config::ProvidersFile {
        active: request.active,
        providers: request.providers,
    };
    store(
        &app.providers_path,
        &app.credentials_path,
        &file,
        request.keys,
    )?;
    drop(guard);
    read(app)
}

/// 连通测试：{ provider, ok, message, latency_ms }。
pub fn check(app: &Application, body: &Value) -> Result<Value, HostError> {
    let request: TestRequest = parse(body)?;
    let saved = config::load_credentials(&app.credentials_path)?;
    let outcome = test(&request.provider, request.model, request.api_key, &saved);
    Ok(json!({
        "provider": request.provider.id,
        "ok": outcome.ok,
        "message": outcome.message,
        "latency_ms": outcome.latency_ms,
    }))
}
