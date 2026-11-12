//! 接口与页面路由。
use crate::error::ApiError;
use crate::http::{Request, Response};
use crate::positions::positions;
use crate::storage::safe_id;
use crate::App;
use serde_json::{json, Value};
use std::fs;
use std::path::Path;

/// 会话口令放在这个 Cookie 里；应用壳先用口令打开 /__session 拿到它。
pub const SESSION_COOKIE: &str = "town_session";

pub fn handle(app: &App, req: &Request) -> Response {
    match dispatch(app, req) {
        Ok(response) => response,
        Err(e) => {
            if e.status >= 500 {
                eprintln!("[town-manager] {} {}: {}", req.method, req.path, e.message);
            }
            Response::json(e.status, &e.body())
        }
    }
}

fn dispatch(app: &App, req: &Request) -> Result<Response, ApiError> {
    let host = req.header("host").unwrap_or_default();
    let local = ["127.0.0.1", "localhost"]
        .iter()
        .any(|h| host == *h || host.strip_prefix(h).is_some_and(|p| p.starts_with(':')));
    if !local {
        return Err(ApiError::new(403, "仅提供本机服务"));
    }
    if app.stopping() {
        return Err(ApiError::new(503, "应用正在退出"));
    }
    let path = req.path.as_str();
    let get = matches!(req.method.as_str(), "GET" | "HEAD");
    if path == "/__session" && get {
        return session(app, req);
    }
    if let Some(rest) = path.strip_prefix("/api/towns") {
        if let Some(secret) = &app.options.session_secret {
            if req.cookie(SESSION_COOKIE) != Some(secret.as_str()) {
                return Err(ApiError::new(403, "无效的应用请求"));
            }
        }
        return api(app, req, rest, get);
    }
    if !get {
        return Err(ApiError::new(404, "操作不存在"));
    }
    if path == "/data/props/core/definitions.json" {
        let bytes = fs::read(app.storage.app.join("data/props/core/definitions.json"))?;
        return Ok(file_response(bytes, "application/json", "no-cache"));
    }
    static_file(app, req, path)
}

/// 应用壳带着口令打开这里，换到会话 Cookie 后回到首页；口令不再出现在页面地址里。
fn session(app: &App, req: &Request) -> Result<Response, ApiError> {
    let Some(secret) = &app.options.session_secret else {
        return Ok(Response::redirect("/", None));
    };
    if req.query.get("k") != Some(secret) {
        return Err(ApiError::new(403, "无效的应用请求"));
    }
    let next = req
        .query
        .get("next")
        .filter(|n| n.starts_with('/') && !n.starts_with("//"))
        .cloned()
        .unwrap_or_else(|| "/".into());
    let cookie = format!("{SESSION_COOKIE}={secret}; Path=/; HttpOnly; SameSite=Strict");
    Ok(Response::redirect(&next, Some(cookie)))
}

fn body(req: &Request) -> Result<Value, ApiError> {
    if req.header("x-town-client") != Some("1")
        || !req
            .header("content-type")
            .is_some_and(|t| t.starts_with("application/json"))
    {
        return Err(ApiError::new(403, "无效的应用请求"));
    }
    serde_json::from_slice(&req.body).map_err(|_| ApiError::bad("请求内容不是有效的 JSON"))
}

fn api(app: &App, req: &Request, rest: &str, get: bool) -> Result<Response, ApiError> {
    let ok = |value: Value| Ok(Response::json(200, &value));
    match (get, rest) {
        (true, "/health") => {
            return ok(json!({
                "kind": "town-manager",
                "version": 1,
                "pid": std::process::id(),
                "source": app.storage.app.to_string_lossy(),
            }))
        }
        (true, "") => {
            let towns: Vec<Value> = app
                .storage
                .list()?
                .into_iter()
                .map(|mut town| {
                    let running = town["id"]
                        .as_str()
                        .is_some_and(|id| app.hosts.is_running(id));
                    town["running"] = Value::from(running);
                    town
                })
                .collect();
            return ok(json!({ "towns": towns }));
        }
        // 建镇：生成在网页里做，这里理解描述、校验成品、暂存草稿、保存（见 creation.rs）
        (true, "/options") => return ok(crate::creation::options(&app.config)),
        (false, "/parse") => return ok(crate::creation::parse(&app.config, &body(req)?)?),
        (false, "/drafts") => return ok(app.drafts.put(&app.config, &body(req)?)?),
        (false, "/save") => return ok(app.drafts.save(&app.storage, &body(req)?)?),
        (false, "/preview") => {
            return Err(ApiError::bad("请更新应用：建镇预览在页面里生成"));
        }
        // 首页「设定」的模型服务：读、存、连通测试。逻辑在 host::models，和世界进程的设定中心共用
        (true, "/models") => {
            return ok(host::models::read(&crate::creation::load_app(
                &app.config,
            )?)?)
        }
        (false, "/models") => {
            let app = crate::creation::load_app(&app.config)?;
            return ok(host::models::write(&app, &body(req)?)?);
        }
        (false, "/models/test") => {
            let app = crate::creation::load_app(&app.config)?;
            return ok(host::models::check(&app, &body(req)?)?);
        }
        // 内置模型的状态、看有没有新版本、下载暂停删除（host::builtin_store）
        (true, "/builtin-model") => {
            let config = crate::creation::load_app(&app.config)?;
            return ok(host::builtin_store::status(&config)?);
        }
        (false, "/builtin-model") => {
            let config = crate::creation::load_app(&app.config)?;
            let request = body(req)?;
            if request["action"] == "check" {
                return ok(host::builtin_store::check(&config)?);
            }
            let status = host::builtin_store::act(&config, &request)?;
            if request["action"] == "download" {
                app.downloads.ensure(&app.config);
            }
            return ok(status);
        }
        _ => {}
    }
    let mut parts = rest.trim_start_matches('/').splitn(2, '/');
    let (id, action) = (
        parts.next().unwrap_or_default(),
        parts.next().unwrap_or_default(),
    );
    let id = safe_id(id)?;
    match (get, action) {
        (true, "map") => {
            let map = app.storage.map(id)?;
            if req.query.get("hash").is_some_and(|h| *h != map.hash) {
                return Err(ApiError::bad("地图已变化，请返回小镇列表重新打开"));
            }
            Ok(Response::raw_json(map.bytes))
        }
        (false, "open") => {
            let automatic = body(req)?["automatic"].as_bool().unwrap_or(false);
            app.refuse_displaced(id, automatic)?;
            let _claim = app.claim(id);
            app.make_room(id)?;
            let _serial = app.town_lock(id);
            ok(app.hosts.open(&app.storage, id)?)
        }
        (false, "close") => {
            let lease = body(req)?["lease"].as_str().map(str::to_owned);
            let _serial = app.town_lock(id);
            // 带着打开凭证来关：之后又有页面打开过这个小镇（比如刷新），旧页面晚到的关闭不算数
            let superseded =
                lease.is_some_and(|lease| app.hosts.is_running(id) && !app.hosts.holds(id, &lease));
            if !superseded {
                app.hosts.close(id)?;
            }
            ok(json!({ "ok": true, "closed": !superseded }))
        }
        (false, "delete") => {
            body(req)?;
            let _serial = app.town_lock(id);
            if !app.storage.can_delete(id) {
                return Err(ApiError::new(403, "内置地图不能删除"));
            }
            app.hosts.close(id)?;
            app.storage.remove(id, false)?;
            ok(json!({ "ok": true }))
        }
        (false, "reset") => {
            body(req)?;
            let _serial = app.town_lock(id);
            if !id.starts_with("prefab-") {
                return Err(ApiError::new(403, "只有预制小镇能重新开始"));
            }
            app.hosts.close(id)?;
            app.storage.remove(id, true)?;
            ok(json!({ "ok": true }))
        }
        (false, "positions") => {
            let request = body(req)?;
            let _serial = app.town_lock(id);
            let map = app.storage.map(id)?;
            if request["map_hash"] != map.hash.as_str() {
                return Err(ApiError::bad("地图版本不匹配"));
            }
            let marks = positions(&app.storage.town(id)?, &map.document, &request["instances"])?;
            ok(json!({ "positions": marks }))
        }
        _ => Err(ApiError::new(404, "操作不存在")),
    }
}

const IMMUTABLE: &str = "public, max-age=31536000, immutable";

fn content_type(path: &Path) -> &'static str {
    match path
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or_default()
    {
        "html" => "text/html; charset=utf-8",
        "js" => "text/javascript; charset=utf-8",
        "css" => "text/css; charset=utf-8",
        "svg" => "image/svg+xml",
        "json" => "application/json",
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "webp" => "image/webp",
        "m4a" => "audio/mp4",
        "mp3" => "audio/mpeg",
        "ogg" => "audio/ogg",
        "woff2" => "font/woff2",
        "wasm" => "application/wasm",
        _ => "application/octet-stream",
    }
}

fn file_response(body: Vec<u8>, content_type: &str, cache: &str) -> Response {
    Response {
        status: 200,
        headers: vec![
            ("Content-Type".into(), content_type.into()),
            ("Cache-Control".into(), cache.into()),
            ("Accept-Ranges".into(), "bytes".into()),
        ],
        body,
    }
}

/// 前端构建产物：首页、游戏页与 assets/ 下的文件。音频按 Range 分段返回。
fn static_file(app: &App, req: &Request, path: &str) -> Result<Response, ApiError> {
    let name = match path {
        "" | "/index.html" => "index.html",
        "/game.html" => "game.html",
        other => other
            .strip_prefix("/assets/")
            .filter(|f| {
                !f.is_empty()
                    && f.chars()
                        .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-'))
                    && !f.starts_with('.')
            })
            .map(|_| other.trim_start_matches('/'))
            .ok_or_else(|| ApiError::new(404, "操作不存在"))?,
    };
    let full = app.options.web.join(name);
    let bytes = fs::read(&full).map_err(|e| match e.kind() {
        std::io::ErrorKind::NotFound => ApiError::new(404, "页面不存在，请先构建前端"),
        _ => ApiError::from(e),
    })?;
    let cache = if name.ends_with(".html") {
        "no-store"
    } else {
        IMMUTABLE
    };
    let kind = content_type(&full);
    if let Some(range) = req.header("range").and_then(|r| r.strip_prefix("bytes=")) {
        return Ok(partial(bytes, kind, cache, range));
    }
    Ok(file_response(bytes, kind, cache))
}

/// 单段 Range：`a-b`、`a-` 或 `-n`。
fn partial(bytes: Vec<u8>, kind: &str, cache: &str, range: &str) -> Response {
    let len = bytes.len();
    let (start, end) = match range.split_once('-') {
        Some(("", n)) => match n.parse::<usize>() {
            Ok(n) if n > 0 => (len.saturating_sub(n), len.saturating_sub(1)),
            _ => (len, 0),
        },
        Some((a, b)) => {
            let start = a.parse::<usize>().unwrap_or(len);
            let end = b.parse::<usize>().unwrap_or(len.saturating_sub(1));
            (start, end.min(len.saturating_sub(1)))
        }
        None => (len, 0),
    };
    if start >= len || start > end {
        return Response {
            status: 416,
            headers: vec![("Content-Range".into(), format!("bytes */{len}"))],
            body: Vec::new(),
        };
    }
    let mut response = file_response(bytes[start..=end].to_vec(), kind, cache);
    response.status = 206;
    response
        .headers
        .push(("Content-Range".into(), format!("bytes {start}-{end}/{len}")));
    response
}
