use serde_json::{json, Value};
use std::io;

/// 接口错误：状态码与给玩家看的说明。文件不存在是 404；其他系统错误是 500，且不把路径发给客户端；
/// 输入或状态不允许是 400。
#[derive(Debug)]
pub struct ApiError {
    pub status: u16,
    pub message: String,
    pub code: Option<String>,
}

impl ApiError {
    pub fn new(status: u16, message: impl Into<String>) -> Self {
        Self {
            status,
            message: message.into(),
            code: None,
        }
    }

    /// 输入无效或当前状态不允许。
    pub fn bad(message: impl Into<String>) -> Self {
        Self::new(400, message)
    }

    pub fn body(&self) -> Value {
        match &self.code {
            Some(code) => json!({ "error": self.message, "code": code }),
            None => json!({ "error": self.message }),
        }
    }
}

impl From<io::Error> for ApiError {
    fn from(e: io::Error) -> Self {
        if e.kind() == io::ErrorKind::NotFound {
            return Self::new(404, "请求的小镇或文件不存在");
        }
        eprintln!("[town-manager] {e}");
        Self::new(500, "服务内部错误")
    }
}

impl From<host::HostError> for ApiError {
    fn from(e: host::HostError) -> Self {
        match e {
            host::HostError::Io(message) => {
                eprintln!("[town-manager] {message}");
                Self::new(500, "服务内部错误")
            }
            other => Self::bad(other.to_string()),
        }
    }
}
