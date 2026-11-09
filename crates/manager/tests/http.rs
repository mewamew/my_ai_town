//! 手机上同一台设备的其他应用也连得到这个本机端口：小镇接口要会话 Cookie，写操作要应用自己的请求头，
//! 静态文件读不出前端目录以外的东西。建镇时网页交上来的地图要过 host 的校验才能存成小镇。
//! 内置模型下到一半断网能接着下，核对不上的文件不会换掉在用的模型。
//! 真实进程、临时目录，不启动世界、不读用户数据和密钥。
use std::collections::HashMap;
use std::fs;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

const SECRET: &str = "test-session-secret";

struct Manager {
    child: Child,
    dir: PathBuf,
    port: u16,
}

impl Drop for Manager {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
        let _ = fs::remove_dir_all(&self.dir);
    }
}

impl Manager {
    fn start(name: &str) -> Self {
        Self::start_with(name, serde_json::json!({}))
    }

    /// extra 里的字段写进应用配置
    fn start_with(name: &str, extra: serde_json::Value) -> Self {
        let dir = std::env::temp_dir().join(format!("town-manager-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        let (app, web) = (dir.join("app"), dir.join("web"));
        let repo = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
        fs::create_dir_all(app.join("config")).unwrap();
        fs::create_dir_all(web.join("assets")).unwrap();
        // 应用自带的内置地图
        for (_, map) in manager::storage::BUILTIN_TOWNS {
            fs::create_dir_all(app.join(map).parent().unwrap()).unwrap();
            fs::copy(repo.join(map), app.join(map)).unwrap();
        }
        // 道具库和场景包用仓库里的（绝对路径）；模型服务和密钥只在临时目录里，读不到仓库的密钥
        let data = |p: &str| repo.join(p).canonicalize().unwrap();
        let mut config = serde_json::json!({
            "port": 0,
            "topology_path": "data/maps/2d-town/map.json",
            "providers_path": "config/providers.json",
            "credentials_path": "config/credentials.json",
            "prop_catalog_path": data("data/props/core/definitions.json"),
            "legacy_prop_catalog_path": data("data/props/compatibility/retired-core-20260925.json"),
            "scene_assets_path": data("data/scene-assets"),
        });
        for (key, value) in extra.as_object().unwrap() {
            config[key] = value.clone();
        }
        fs::write(app.join("config/application.json"), config.to_string()).unwrap();
        // 应用带着推理程序，设定里才有内置模型；这里只要文件在，不会真的启动它
        fs::create_dir_all(app.join("builtin-model")).unwrap();
        let server = format!("llama-server{}", std::env::consts::EXE_SUFFIX);
        fs::write(app.join("builtin-model").join(server), "").unwrap();
        fs::write(web.join("index.html"), "<!doctype html>town").unwrap();
        fs::write(web.join("assets/app.js"), "void 0").unwrap();
        let ready = dir.join("ready.json");
        let child = Command::new(env!("CARGO_BIN_EXE_town-manager"))
            .arg("--root")
            .arg(dir.join("home"))
            .arg("--app")
            .arg(&app)
            .arg("--web")
            .arg(&web)
            .arg("--host-bin")
            .arg(dir.join("no-host"))
            .args(["--port", "0", "--session-secret", SECRET, "--ready-file"])
            .arg(&ready)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .unwrap();
        let deadline = Instant::now() + Duration::from_secs(20);
        let port = loop {
            let ready: Option<serde_json::Value> = fs::read(&ready)
                .ok()
                .and_then(|b| serde_json::from_slice(&b).ok());
            if let Some(port) = ready.and_then(|r| r["port"].as_u64()) {
                break port as u16;
            }
            assert!(Instant::now() < deadline, "管理服务没有就绪");
            std::thread::sleep(Duration::from_millis(50));
        };
        Manager { child, dir, port }
    }

    /// 发一个原始请求，返回状态码和整段响应（服务端每次都关连接）。
    fn request(&self, head: &str, body: &str) -> (u16, String) {
        let mut stream = TcpStream::connect(("127.0.0.1", self.port)).unwrap();
        let length = if body.is_empty() {
            String::new()
        } else {
            format!("Content-Length: {}\r\n", body.len())
        };
        write!(stream, "{head}{length}\r\n{body}").unwrap();
        let mut response = String::new();
        stream.read_to_string(&mut response).unwrap();
        let status = response[9..12].parse().unwrap();
        (status, response)
    }

    fn get(&self, path: &str, extra: &str) -> (u16, String) {
        self.request(
            &format!(
                "GET {path} HTTP/1.1\r\nHost: 127.0.0.1:{}\r\n{extra}",
                self.port
            ),
            "",
        )
    }
}

#[test]
fn town_api_needs_session_and_static_files_stay_in_web_dir() {
    let manager = Manager::start("http");
    let cookie = format!("Cookie: town_session={SECRET}\r\n");

    // 没有会话、口令不对、冒充别的站点：都拿不到小镇列表
    assert_eq!(manager.get("/api/towns", "").0, 403);
    assert_eq!(manager.get("/__session?k=wrong", "").0, 403);
    let (status, _) = manager.request(
        "GET /api/towns HTTP/1.1\r\nHost: evil.example\r\nCookie: town_session=test-session-secret\r\n",
        "",
    );
    assert_eq!(status, 403);

    // 应用壳用口令换到只给本站、脚本读不到的 Cookie
    let (status, response) = manager.get(&format!("/__session?k={SECRET}"), "");
    assert_eq!(status, 302);
    assert!(response.contains("HttpOnly; SameSite=Strict"), "{response}");
    let (status, response) = manager.get("/api/towns", &cookie);
    assert_eq!(status, 200);
    // 随应用发的内置小镇第一次运行就都在
    for (id, _) in manager::storage::BUILTIN_TOWNS {
        assert!(response.contains(id), "{response}");
    }

    // 写操作还要应用自己的请求头：别的网页带不上，就发不出跨站请求
    let post = format!(
        "POST /api/towns/default-town/close HTTP/1.1\r\nHost: 127.0.0.1\r\n{cookie}Content-Type: text/plain\r\n"
    );
    assert_eq!(manager.request(&post, "{}").0, 403);

    // 静态文件只认前端目录里的文件名
    assert_eq!(manager.get("/", "").0, 200);
    assert_eq!(manager.get("/assets/app.js", "").0, 200);
    for path in [
        "/assets/../app/config/application.json",
        "/assets/..%2Fapp%2Fconfig%2Fapplication.json",
        "/assets/%2e%2e%2fhome%2fconfig%2fcredentials.json",
        "/home/config/credentials.json",
        "/config/application.json",
    ] {
        assert_eq!(manager.get(path, "").0, 404, "{path}");
    }
}

/// 带会话 Cookie 和应用请求头的 POST，返回状态码和响应体
fn post(manager: &Manager, path: &str, body: &serde_json::Value) -> (u16, serde_json::Value) {
    let text = body.to_string();
    let (status, response) = manager.request(
        &format!(
            "POST /api/towns{path} HTTP/1.1\r\nHost: 127.0.0.1\r\nCookie: town_session={SECRET}\r\n\
             X-Town-Client: 1\r\nContent-Type: application/json\r\n"
        ),
        &text,
    );
    let json = response
        .split_once("\r\n\r\n")
        .and_then(|(_, b)| serde_json::from_str(b).ok())
        .unwrap_or_default();
    (status, json)
}

#[test]
fn created_maps_are_validated_before_they_become_towns() {
    let manager = Manager::start("creation");
    let repo = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let map: serde_json::Value =
        serde_json::from_slice(&fs::read(repo.join("data/maps/2d-town/map.json")).unwrap())
            .unwrap();

    // 改过内容却没重新封摘要的地图：拒收，不留草稿
    let mut tampered = map.clone();
    tampered["name"] = "改过的小镇".into();
    let (status, _) = post(
        &manager,
        "/drafts",
        &serde_json::json!({ "document": tampered }),
    );
    assert_eq!(status, 400);

    // 完整的地图：校验通过，草稿版本就是它的内容摘要
    let (status, draft) = post(&manager, "/drafts", &serde_json::json!({ "document": map }));
    assert_eq!(status, 200, "{draft}");
    assert_eq!(draft["version"], map["content_hash"]);

    // 版本对不上（页面拿着旧预览）：不保存。预览后改的名字随保存提交，只换名字、重算摘要
    let save = |version: &serde_json::Value| {
        post(
            &manager,
            "/save",
            &serde_json::json!({
                "draft_id": draft["id"],
                "request_id": "save-1",
                "expected_version": version,
                "name": "改过名的小镇",
                "creation": {
                    "description": "海边的小渔村，村口有一家小酒馆",
                    "worldview": "这里的人想靠海吃饭。",
                    "residents": ["在村口酒馆当老板娘的寡妇"],
                    "prefab": "battle-royale",
                },
            }),
        )
    };
    assert_eq!(save(&"旧版本".into()).0, 400);
    let (status, town) = save(&draft["version"]);
    assert_eq!(status, 200, "{town}");
    // 重复提交同一次保存：还是同一个小镇
    assert_eq!(save(&draft["version"]).1["id"], town["id"]);

    let (status, list) = manager.get("/api/towns", &format!("Cookie: town_session={SECRET}\r\n"));
    assert_eq!(status, 200);
    let id = town["id"].as_str().unwrap();
    assert!(list.contains(id), "{list}");
    // 一句话建镇的说明和小镇存在一起：列表简介是玩家那句话，条目里带着世界观建议和适合住进来的人
    assert!(list.contains("海边的小渔村，村口有一家小酒馆"), "{list}");
    assert!(list.contains("在村口酒馆当老板娘的寡妇"), "{list}");
    // 从预制小镇开的一局记着是哪个预制小镇，进镇时据此出开局设置
    assert!(list.contains(r#""prefab":"battle-royale""#), "{list}");
    let saved: serde_json::Value = serde_json::from_slice(
        &fs::read(manager.dir.join("home/towns").join(id).join("map.json")).unwrap(),
    )
    .unwrap();
    assert_eq!(saved["name"], "改过名的小镇");
    assert_eq!(saved["content_hash"], host::maps::hash(&saved).as_str());
    assert_eq!(town["mapHash"], saved["content_hash"]);
    assert_eq!(saved["layout"], map["layout"]);
}

/// 假的发布处：清单和模型文件，文件支持 Range。cut 打开时下一次整个模型文件的请求只给一半就断开，像网断了。
struct Source {
    port: u16,
    files: Arc<Mutex<HashMap<String, Vec<u8>>>>,
    ranges: Arc<Mutex<Vec<String>>>,
    cut: Arc<AtomicBool>,
}

impl Source {
    fn start() -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let source = Source {
            port,
            files: Default::default(),
            ranges: Default::default(),
            cut: Default::default(),
        };
        let (files, ranges, cut) = (
            source.files.clone(),
            source.ranges.clone(),
            source.cut.clone(),
        );
        std::thread::spawn(move || {
            for stream in listener.incoming().flatten() {
                Self::answer(stream, &files, &ranges, &cut);
            }
        });
        source
    }

    fn answer(
        mut stream: TcpStream,
        files: &Mutex<HashMap<String, Vec<u8>>>,
        ranges: &Mutex<Vec<String>>,
        cut: &AtomicBool,
    ) {
        let mut reader = BufReader::new(stream.try_clone().unwrap());
        let mut first = String::new();
        reader.read_line(&mut first).unwrap();
        let path = first.split(' ').nth(1).unwrap_or_default().to_owned();
        let mut start = None;
        loop {
            let mut line = String::new();
            if reader.read_line(&mut line).unwrap_or(0) == 0 || line == "\r\n" {
                break;
            }
            if let Some(range) = line.to_ascii_lowercase().strip_prefix("range: bytes=") {
                start = range.trim().trim_end_matches('-').parse::<usize>().ok();
                ranges.lock().unwrap().push(line.trim().to_owned());
            }
        }
        let Some(body) = files.lock().unwrap().get(&path).cloned() else {
            let _ = write!(
                stream,
                "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n"
            );
            return;
        };
        let _ = match start {
            Some(start) => write!(
                stream,
                "HTTP/1.1 206 Partial Content\r\nContent-Range: bytes {start}-{}/{}\r\nContent-Length: {}\r\n\r\n",
                body.len() - 1,
                body.len(),
                body.len() - start
            )
            .and_then(|()| stream.write_all(&body[start..])),
            None => write!(
                stream,
                "HTTP/1.1 200 OK\r\nContent-Length: {}\r\n\r\n",
                body.len()
            )
            .and_then(|()| {
                let end = if path.ends_with(".gguf") && cut.swap(false, Ordering::SeqCst) {
                    body.len() / 2
                } else {
                    body.len()
                };
                stream.write_all(&body[..end])
            }),
        };
    }

    fn put(&self, path: &str, bytes: Vec<u8>) {
        self.files.lock().unwrap().insert(path.to_owned(), bytes);
    }
}

fn sha256(bytes: &[u8]) -> String {
    use sha2::{Digest, Sha256};
    Sha256::digest(bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

fn version(date: &str, format: u32, bytes: &[u8]) -> serde_json::Value {
    serde_json::json!({
        "date": date, "format": format, "file": format!("{date}/model.gguf"),
        "size": bytes.len(), "sha256": sha256(bytes), "notes": format!("{date} 的版本"),
    })
}

/// 等到内置模型的状态满足条件，返回那一刻的状态
fn builtin_until(
    manager: &Manager,
    done: impl Fn(&serde_json::Value) -> bool,
) -> serde_json::Value {
    let cookie = format!("Cookie: town_session={SECRET}\r\n");
    let deadline = Instant::now() + Duration::from_secs(30);
    loop {
        let (_, response) = manager.get("/api/towns/builtin-model", &cookie);
        let status: serde_json::Value = response
            .split_once("\r\n\r\n")
            .and_then(|(_, b)| serde_json::from_str(b).ok())
            .unwrap_or_default();
        if done(&status) {
            return status;
        }
        assert!(
            Instant::now() < deadline,
            "内置模型一直没到预期的状态：{status}"
        );
        std::thread::sleep(Duration::from_millis(100));
    }
}

#[test]
fn builtin_model_resumes_after_network_break_and_never_installs_a_bad_file() {
    let source = Source::start();
    // 几 MB，下载线程要读好多次；内容不重复，接错位置一定核对不上
    let first: Vec<u8> = (0..3_000_000u32)
        .map(|i| (i.wrapping_mul(2654435761) >> 13) as u8)
        .collect();
    source.put(
        "/manifest.json",
        serde_json::to_vec(&serde_json::json!({ "models": [
            version("2026-10-08", 1, &first),
            // 格式号更大的只提示要先更新游戏，不会下
            version("2026-11-02", 99, b"newer"),
        ]}))
        .unwrap(),
    );
    source.put("/2026-10-08/model.gguf", first.clone());
    source.cut.store(true, Ordering::SeqCst);
    let manager = Manager::start_with(
        "builtin-model",
        serde_json::json!({ "builtin_model_source": format!("http://127.0.0.1:{}", source.port) }),
    );
    let model = manager.dir.join("home/builtin-model/model.gguf");

    let (status, checked) = post(
        &manager,
        "/builtin-model",
        &serde_json::json!({ "action": "check" }),
    );
    assert_eq!(status, 200, "{checked}");
    assert!(checked["supported"].as_bool().unwrap() && checked["installed"].is_null());
    assert_eq!(checked["latest"]["date"], "2026-10-08");
    assert_eq!(checked["needs_app"]["date"], "2026-11-02");

    // 第一次只下到一半就断了：隔一会儿带着 Range 接着下，下完核对过才换上
    let (status, started) = post(
        &manager,
        "/builtin-model",
        &serde_json::json!({ "action": "download" }),
    );
    assert_eq!(status, 200, "{started}");
    let done = builtin_until(&manager, |s| s["installed"]["date"] == "2026-10-08");
    assert!(
        done["download"].is_null() && !done["update"].as_bool().unwrap(),
        "{done}"
    );
    assert_eq!(fs::read(&model).unwrap(), first);
    let ranges = source.ranges.lock().unwrap().clone();
    assert_eq!(ranges, [format!("Range: bytes={}-", first.len() / 2)]);

    // 新版本发布了，可服务器上的文件和清单写的对不上：在用的模型不动，停在出错上等玩家
    let second: Vec<u8> = first.iter().rev().copied().collect();
    let manifest = serde_json::json!({ "models": [
        version("2026-10-08", 1, &first),
        version("2026-10-20", 1, &second),
    ]});
    source.put("/manifest.json", serde_json::to_vec(&manifest).unwrap());
    source.put("/2026-10-20/model.gguf", first.clone());
    let (_, checked) = post(
        &manager,
        "/builtin-model",
        &serde_json::json!({ "action": "check" }),
    );
    assert!(checked["update"].as_bool().unwrap(), "{checked}");
    post(
        &manager,
        "/builtin-model",
        &serde_json::json!({ "action": "download" }),
    );
    let failed = builtin_until(&manager, |s| s["download"]["state"] == "error-file");
    assert_eq!(failed["installed"]["date"], "2026-10-08", "{failed}");
    assert_eq!(fs::read(&model).unwrap(), first);
    assert!(!manager
        .dir
        .join("home/builtin-model/model.gguf.part")
        .exists());
}
