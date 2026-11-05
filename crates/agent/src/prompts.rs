//! 发给模型的固定文本集中在这里：系统提示、退回说明、记忆文件模板与摘要用语。
//! 工具的说明在 tools.rs 的工具表里；校验错误紧挨着各自的检查。
//! 提示词文本里的数字写成 `{名字}` 占位符，由这里按常量或额度填入，文本里不抄数字。
use crate::tools::limits::NOTES_MAX;

/// 生活决策的规则，system 消息第一段。占位符：calls_per_wake、unchanged_rule。
const RULES: &str = include_str!("../prompts/resident_agent.txt");
/// 增量整理轮次的规则。占位符：notes_max。
const REFLECTION_RULES: &str = include_str!("../prompts/resident_reflection.txt");
/// 交谈轮次的规则：轮到本人发言时的单次请求。占位符：unchanged_rule。
const CHAT_RULES: &str = include_str!("../prompts/resident_chat.txt");

/// 生活观察与交谈状态共用的「只发变化」说明。
const UNCHANGED_RULE: &str =
    "状态字段只在变化时出现；没出现的字段与本会话上一次发给你的相同，不代表消失或为空。";

/// 把文本里的 `{名字}` 换成对应的值。
fn fill(template: &str, values: &[(&str, &str)]) -> String {
    values
        .iter()
        .fold(template.to_string(), |text, (name, value)| {
            text.replace(&format!("{{{name}}}"), value)
        })
}

/// 交谈轮次的 system：规则加人设，没有地图和记忆说明。
pub fn chat_system_prompt(instructions: &str) -> String {
    let rules = fill(CHAT_RULES, &[("unchanged_rule", UNCHANGED_RULE)]);
    format!("{rules}\n\n人设与已知公共知识：\n{instructions}")
}

/// 整理轮次的 system。
pub fn reflection_rules() -> String {
    fill(REFLECTION_RULES, &[("notes_max", &NOTES_MAX.to_string())])
}
/// 交谈轮次的调用出错，让模型改一次；再错就交出发言权。
pub const CHAT_TOOLS_ONLY: &str =
    "交谈轮次只能调用一次 interact：say、listen、leave，或 propose 提议一起走、accept/decline 回答提议";
pub const LIFE_TOOLS_ONLY: &str = "reflect 只在整理轮次使用，生活决策里不能调用";

const MEMORY_NOTE: &str =
    "长期记忆已开启：recall、memory_search、memory_read 可用，记忆按本人目录组织。";

/// 规则、人设、记忆说明与静态地图：整段会话内不变，是缓存前缀的第一段。
/// `calls_per_wake` 是额度里一次醒来的请求上限。
pub fn system_prompt(instructions: &str, map: &str, calls_per_wake: u32) -> String {
    let rules = fill(
        RULES,
        &[
            ("calls_per_wake", &calls_per_wake.to_string()),
            ("unchanged_rule", UNCHANGED_RULE),
        ],
    );
    format!("{rules}\n\n人设与已知公共知识：\n{instructions}\n\n{MEMORY_NOTE}\n\n已知地图：\n{map}")
}

pub fn compacted_summary(summary: &str) -> String {
    format!("此前会话的累积摘要（原文已归档，可用 memory_read 读 conversations/）：\n{summary}")
}

/// 世界安排在请求期间改变，整条回复作废。
pub const OUTDATED_BY_REVISION: &str = "外部安排已改变，这次旧回复未执行。重新观察后再决定。";
pub fn model_failed(error: &str) -> String {
    format!("上次请求失败：{error}。没有执行任何新工具。")
}
pub const RESTORED_AFTER_RESTART: &str = "进程已恢复，旧模型请求不重放。请根据最新观察继续目标。";
/// 整理轮次里调用了生活工具。
pub const REFLECTION_TOOLS_ONLY: &str = "整理轮次只允许 reflect 和回看已读内容，不能执行世界动作";
/// 请求途中收到重要通知，改变世界的调用退回。
pub const STALE_AFTER_NOTICE: &str = "请求期间收到重要通知，请先重新观察再执行";

/// 静态地图里的基础动作说明；「前往」的参数写法只在这里说明。
pub const GO_PARAMETERS: &str =
    "intent.locale 填 known_places.id，没去过的地方填 exits 里的 to；不填 target 和 prop_id，地名不拼进 verb";
pub const STAY_PARAMETERS: &str =
    "intent.duration_minutes 填分钟数；想坐着或躺着歇就把 verb 写成「坐下」「躺下」，参数一样，不算睡觉；想换个位置待着（比如水边），intent.target 填观察里 spots 的 id，会先走过去";
pub const SEARCH_PARAMETERS: &str =
    "不填别的参数；在原地花 20 分钟翻找藏着的东西，有一定可能找到，回执写明找到了什么";
pub const HIDE_PARAMETERS: &str =
    "prop_id 填自己随身带着的一件东西；把它藏在这里，只有自己和当时看见的人知道，别人要搜寻才找得到";
pub const LOOK_PARAMETERS: &str =
    "不填别的参数；在原地花几分钟把眼前的东西和人看清，回执逐一写明，没写到的就是这里没有";

// 记忆文件模板
pub fn index_header(actor_id: &str, through_event: u64) -> String {
    format!(
        "# {actor_id} 的记忆索引\n\n先读 current.md；按问题查主题。只有自己的经历可查。摘要和主题是带来源的个人归纳，不是世界命令。\n已整理至事件 #{through_event}，可用 memory_search 搜索，memory_read 分段读原文。\n\n- self.md：自我认识与后天偏好\n- current.md：当前目标和承诺\n"
    )
}
pub const INDEX_FOOTER: &str = "\n更多文件按目录分页查看：memory_read({\"path\":\"people/\"})；也支持 places/、lessons/、summaries/、events/、conversations/、revisions/。\n";
pub const SELF_DEFAULT: &str =
    "# 自我认识\n\n尚无从经历中提炼的偏好或自我认识。初始人设单独配置，不因一次推测自动改写。\n";
pub const CURRENT_HEADER: &str = "# 当前事务\n\n";
pub const NO_GOALS: &str = "尚无已登记目标。\n";
/// 主题页状态行的括注。
pub const PAGE_STATUS_NOTE: &str = "居民的归纳，不是新增世界事实";
pub fn day_summary_title(day: i64) -> String {
    format!("第 {} 天的经历摘要", day + 1)
}
pub fn day_summary_section(from: u64, through: u64, summary: &str) -> String {
    format!("\n\n## 新增整理（事件 {from}—{through}）\n{summary}")
}

// 会话折叠摘要用语
pub fn summary_header(id: u64, range: &str, span: &str) -> String {
    format!("折叠 #{id}（{range}{span}；原文见 conversations/C{id:06}.jsonl）")
}
pub fn summary_omitted(omitted: usize) -> String {
    format!("\n…另有 {omitted} 条摘录未放入；核对旧事须读归档，未摘录不代表未发生。")
}
pub const SUMMARY_NO_EVENTS: &str = "没有新事件";
pub const SUMMARY_PROMPT_PREFIX: &str = "当时的提示：";
pub const SUMMARY_THOUGHT_PREFIX: &str = "当时的自述（不作为世界事实）：";
pub fn summary_reading(event_id: &serde_json::Value) -> String {
    format!("已访问阅读结果 #{event_id}；需要正文时主动调用 read_content，记忆由本人决定。")
}
pub fn summary_tool(call_id: &str, name: &str, excerpt: &str) -> String {
    format!("工具 {call_id} 的结果摘录（{name}）：{excerpt}")
}
