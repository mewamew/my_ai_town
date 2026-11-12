//! 只服务本机页面的最小 HTTP/1.1：每个连接一个请求，读完即关。
use serde_json::Value;
use std::collections::HashMap;
use std::io::{self, Read, Write};
use std::net::TcpStream;

const MAX_HEAD: usize = 64 * 1024;
/// 请求体上限。建镇时网页把整张生成好的地图交上来，有一两兆；与 town-map 的输入上限相同
pub const MAX_BODY: usize = 16_000_000;

pub struct Request {
    pub method: String,
    /// 解码后的路径，去掉末尾的 `/`；根路径是空串。
    pub path: String,
    pub query: HashMap<String, String>,
    /// 头名一律小写。
    pub headers: HashMap<String, String>,
    pub body: Vec<u8>,
}

impl Request {
    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers.get(name).map(String::as_str)
    }

    pub fn cookie(&self, name: &str) -> Option<&str> {
        self.header("cookie")?.split(';').find_map(|part| {
            let (k, v) = part.trim().split_once('=')?;
            (k == name).then_some(v)
        })
    }
}

pub struct Response {
    pub status: u16,
    pub headers: Vec<(String, String)>,
    pub body: Vec<u8>,
}

impl Response {
    pub fn json(status: u16, value: &Value) -> Self {
        Self {
            status,
            headers: vec![
                (
                    "Content-Type".into(),
                    "application/json; charset=utf-8".into(),
                ),
                ("Cache-Control".into(), "no-store".into()),
            ],
            body: value.to_string().into_bytes(),
        }
    }

    /// 已经是 JSON 文本的内容（地图文档）原样发送，不再解析一遍。
    pub fn raw_json(body: Vec<u8>) -> Self {
        Self {
            status: 200,
            headers: vec![
                (
                    "Content-Type".into(),
                    "application/json; charset=utf-8".into(),
                ),
                ("Cache-Control".into(), "no-store".into()),
            ],
            body,
        }
    }

    pub fn redirect(location: &str, cookie: Option<String>) -> Self {
        let mut headers = vec![
            ("Location".into(), location.into()),
            ("Cache-Control".into(), "no-store".into()),
        ];
        if let Some(cookie) = cookie {
            headers.push(("Set-Cookie".into(), cookie));
        }
        Self {
            status: 302,
            headers,
            body: Vec::new(),
        }
    }
}

/// 读一个请求。连接在读到完整请求头之前关闭时返回 None。
pub fn read_request(stream: &mut TcpStream) -> io::Result<Option<Request>> {
    let mut buffer = Vec::with_capacity(4096);
    let mut chunk = [0u8; 4096];
    let head_end = loop {
        if let Some(end) = find(&buffer, b"\r\n\r\n") {
            break end;
        }
        if buffer.len() > MAX_HEAD {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "请求头过大"));
        }
        let n = stream.read(&mut chunk)?;
        if n == 0 {
            return Ok(None);
        }
        buffer.extend_from_slice(&chunk[..n]);
    };
    let head = String::from_utf8_lossy(&buffer[..head_end]).into_owned();
    let mut lines = head.split("\r\n");
    let mut first = lines.next().unwrap_or_default().split(' ');
    let method = first.next().unwrap_or_default().to_owned();
    let target = first.next().unwrap_or_default().to_owned();
    let headers: HashMap<String, String> = lines
        .filter_map(|line| line.split_once(':'))
        .map(|(k, v)| (k.trim().to_ascii_lowercase(), v.trim().to_owned()))
        .collect();
    let length: usize = headers
        .get("content-length")
        .and_then(|v| v.parse().ok())
        .unwrap_or(0);
    if length > MAX_BODY {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "请求过大"));
    }
    let mut body = buffer[head_end + 4..].to_vec();
    while body.len() < length {
        let n = stream.read(&mut chunk)?;
        if n == 0 {
            break;
        }
        body.extend_from_slice(&chunk[..n]);
    }
    body.truncate(length);
    let (path, query) = target.split_once('?').unwrap_or((&target, ""));
    let path = decode(path, false);
    let path = path.trim_end_matches('/').to_owned();
    let query = query
        .split('&')
        .filter(|p| !p.is_empty())
        .map(|pair| {
            let (k, v) = pair.split_once('=').unwrap_or((pair, ""));
            (decode(k, true), decode(v, true))
        })
        .collect();
    Ok(Some(Request {
        method,
        path,
        query,
        headers,
        body,
    }))
}

pub fn write_response(
    stream: &mut TcpStream,
    response: &Response,
    head_only: bool,
) -> io::Result<()> {
    let mut head = format!(
        "HTTP/1.1 {} {}\r\n",
        response.status,
        reason(response.status)
    );
    head.push_str("X-Content-Type-Options: nosniff\r\nConnection: close\r\n");
    head.push_str(&format!("Content-Length: {}\r\n", response.body.len()));
    for (name, value) in &response.headers {
        head.push_str(&format!("{name}: {value}\r\n"));
    }
    head.push_str("\r\n");
    stream.write_all(head.as_bytes())?;
    if !head_only {
        stream.write_all(&response.body)?;
    }
    stream.flush()
}

fn find(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    haystack.windows(needle.len()).position(|w| w == needle)
}

/// 百分号解码；查询串里的 `+` 是空格。
fn decode(s: &str, query: bool) -> String {
    let bytes = s.as_bytes();
    let hex = |b: u8| (b as char).to_digit(16).map(|d| d as u8);
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        let b = bytes[i];
        if b == b'%' && i + 2 < bytes.len() {
            if let (Some(h), Some(l)) = (hex(bytes[i + 1]), hex(bytes[i + 2])) {
                out.push(h * 16 + l);
                i += 3;
                continue;
            }
        }
        out.push(if query && b == b'+' { b' ' } else { b });
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn reason(status: u16) -> &'static str {
    match status {
        200 => "OK",
        206 => "Partial Content",
        302 => "Found",
        400 => "Bad Request",
        403 => "Forbidden",
        404 => "Not Found",
        409 => "Conflict",
        413 => "Payload Too Large",
        416 => "Range Not Satisfiable",
        501 => "Not Implemented",
        503 => "Service Unavailable",
        _ => "Error",
    }
}
