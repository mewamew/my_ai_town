//! 人口服务：人口视图、加入预览、加入事务（先保存后发布）、操作去重与结果查询。
//! 不按人数拒绝加入；住宅、入口、额度暂停和模型配置各按自己的规则给出原因。
//! 身份、姓名、住宅、入口的规则在内核 `check_admission`，这里只追加模板、模型、暂停这些 host 层问题。
use crate::{
    network::Clients,
    runtime::{Outcome, Runtime},
    transaction::{Abort, Aborted},
};
use host::{
    library::{render_persona, validate_fields, NAME_MAX_CHARS},
    population::{fingerprint, Registration},
    world_settings::{instructions_chars, INSTRUCTIONS_MAX_CHARS},
};
use kernel::{
    default_tuning,
    population::{Admission, Entry},
    topology::EntryPoint,
};
use protocol::{
    Appearance, HomeView, JoinOutcome, JoinPreview, ModelChoice, PopulationView,
    ResidentRegistration, ResidentTemplate, ServerMsg, TemplateFields,
};
use rand::seq::SliceRandom;

pub(crate) struct JoinRequest {
    pub op_id: String,
    pub world_id: String,
    pub template_id: String,
    pub template_version: u64,
    pub name: String,
    pub home: Option<String>,
    /// 入住时选好的模型；没带时先住下，等玩家选好模型再行动
    pub model: Option<ModelChoice>,
    /// 预制小镇给这位选手的人设；没带时照模板
    pub persona: Option<TemplateFields>,
}

/// 检查通过、尚未安置的新人：编号、姓名、住宅、出生位置与采用的模板。
struct JoinPlan {
    id: String,
    name: String,
    home: Option<String>,
    home_name: Option<String>,
    entry: EntryPoint,
    entry_name: String,
    template: ResidentTemplate,
    persona: String,
}

enum JoinError {
    /// 规则不通过：记入操作记录，同号重试返回同一结果。
    Rejected(String),
    /// 中途失败（会话、需求参数）：不记录，允许重试。
    Failed(String),
}

impl std::fmt::Display for JoinError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Rejected(message) | Self::Failed(message) => f.write_str(message),
        }
    }
}

impl Runtime {
    pub(crate) fn population_msg(&self) -> ServerMsg {
        ServerMsg::Population {
            population: self.population_view(),
        }
    }

    fn population_view(&self) -> PopulationView {
        let residents = self
            .population
            .ordered()
            .into_iter()
            .map(|r| ResidentRegistration {
                id: r.id.clone(),
                name: r.name.clone(),
                home: r.home.clone(),
                home_name: r
                    .home
                    .as_deref()
                    .map(|home| self.world.topo.locale_name(home))
                    .unwrap_or_else(|| "未分配住宅".into()),
                joined_at: r.joined_at,
                joined_clock: r.joined_at.map(kernel::clock_string),
                template_id: r.template_id.clone(),
                template_version: r.template_version,
                appearance: r.appearance.clone(),
                model: r.model_binding.clone(),
            })
            .collect();
        PopulationView {
            world_id: self.population.world_id.clone(),
            revision: self.population.revision,
            residents,
            homes: self.homes(),
            entry_name: self.world.entry_name(),
        }
    }

    /// 换一位居民的长相（捏人）：只换 look，地图标记、颜色和旧形象编号沿用登记里的，不回写模板。
    /// 名单版本对不上就退回，免得盖掉别的页面刚做的修改。
    pub(crate) fn set_resident_appearance(
        &mut self,
        request_id: String,
        expected_revision: u64,
        resident_id: String,
        appearance: Appearance,
    ) -> Outcome {
        let problem = if expected_revision != self.population.revision {
            Some("居民名单刚有变化，请重新打开再改".to_string())
        } else {
            appearance.look.as_ref().and_then(|look| look.check().err())
        };
        let saved = match problem {
            Some(problem) => Err(problem),
            None => self
                .population
                .set_look(&resident_id, appearance.look)
                .map(|r| format!("{}的长相已保存", r.name))
                .ok_or_else(|| "没有这位居民".to_string()),
        };
        match saved {
            Ok(message) => Outcome::reply(self.resident_appearance_reply(
                request_id,
                resident_id,
                true,
                message,
            ))
            .and_all(self.population_msg())
            .persisted(),
            Err(message) => Outcome::reply(self.resident_appearance_reply(
                request_id,
                resident_id,
                false,
                message,
            )),
        }
    }

    pub(crate) fn resident_appearance_reply(
        &self,
        request_id: String,
        resident_id: String,
        ok: bool,
        message: String,
    ) -> ServerMsg {
        ServerMsg::ResidentAppearanceSaved {
            request_id,
            resident_id,
            ok,
            message,
            population: self.population_view(),
        }
    }

    fn homes(&self) -> Vec<HomeView> {
        self.world
            .homes()
            .into_iter()
            .map(|h| HomeView {
                occupant: h
                    .occupant
                    .as_ref()
                    .and_then(|id| self.world.actor(id))
                    .map(|a| a.name.clone()),
                locale: h.locale,
                name: h.name,
            })
            .collect()
    }

    pub(crate) fn join_preview(
        &self,
        template_id: &str,
        name: Option<&str>,
        home: Option<&str>,
    ) -> Outcome {
        Outcome::reply(ServerMsg::JoinPreview {
            preview: self.preview(template_id, None, name, home),
        })
    }

    pub(crate) fn join_result(&self, world_id: &str, op_id: String) -> Outcome {
        let outcome = (world_id == self.population.world_id)
            .then(|| self.population.joins.get(&op_id).map(|r| r.outcome.clone()))
            .flatten();
        Outcome::reply(ServerMsg::JoinResult { op_id, outcome })
    }

    pub(crate) fn failed_join(&self, op_id: &str, message: String) -> JoinOutcome {
        JoinOutcome {
            op_id: op_id.into(),
            ok: false,
            message,
            resident_id: None,
            name: None,
            home: None,
            joined_at: None,
            revision: self.population.revision,
        }
    }

    /// 只校验、不占房。`expected_version` 只有正式加入时才检查。
    fn preview(
        &self,
        template_id: &str,
        expected_version: Option<u64>,
        name: Option<&str>,
        home: Option<&str>,
    ) -> JoinPreview {
        let mut problems = Vec::new();
        let (name, version, persona_chars) =
            self.template_problems(template_id, expected_version, name, &mut problems);
        if name.is_empty() || name.chars().count() > NAME_MAX_CHARS {
            problems.push(format!("入村姓名须为 1–{NAME_MAX_CHARS} 个字符"));
        }
        if let Some(hold) = self.driver.runtime.town_holds(&self.world).first() {
            problems.push(format!(
                "小镇因{}暂停（{}），先解决再加入",
                hold.kind.label(),
                hold.resident
            ));
        }
        let homes = self.homes();
        let free: Vec<HomeView> = homes
            .iter()
            .filter(|h| h.occupant.is_none())
            .cloned()
            .collect();
        let requested = requested_home(home, &homes, &free, &mut problems);
        let chosen = requested
            .as_deref()
            .and_then(|h| homes.iter().find(|x| x.locale == h))
            .cloned();
        let (entry, entry_name) = self.entry_preview(requested.as_deref(), homes.is_empty());
        let entry = match entry {
            Ok(entry) => entry,
            Err(error) => {
                problems.push(error);
                None
            }
        };
        let id = self
            .population
            .allocate_id(|id| self.world.actor(id).is_some());
        let admission = Admission {
            id: &id,
            name: &name,
            home: requested.as_deref(),
            entry: entry.as_ref().map(|e| Entry {
                locale: &e.locale,
                station: e.station.as_deref(),
            }),
        };
        if let Err(more) = self.world.check_admission(&admission) {
            for problem in more {
                if !problems.contains(&problem) {
                    problems.push(problem);
                }
            }
        }
        JoinPreview {
            ok: problems.is_empty(),
            problems,
            template_id: template_id.into(),
            template_version: version,
            name,
            home: chosen.as_ref().map(|h| h.locale.clone()),
            home_name: chosen.as_ref().map(|h| h.name.clone()),
            entry_name,
            clock: self.world.clock(),
            persona_chars,
            free_homes: free,
        }
    }

    /// 模板层面的问题：存在、未归档、版本对上、没在村中、人设加公共知识不超上限。
    /// 返回最终入村姓名（缺省用模板姓名）、模板版本、人设字数。
    fn template_problems(
        &self,
        template_id: &str,
        expected_version: Option<u64>,
        name: Option<&str>,
        problems: &mut Vec<String>,
    ) -> (String, u64, usize) {
        let Some(t) = self.library.get(template_id) else {
            problems.push("模板不存在".into());
            return (name.unwrap_or("").trim().to_string(), 0, 0);
        };
        if t.archived {
            problems.push("这位已经收起了，先放回列表再请".into());
        }
        if expected_version.is_some_and(|v| v != t.version) {
            problems.push(format!("模板已更新到第 {} 版，请重新预览", t.version));
        }
        if let Some(r) = self.population.joined_from(template_id) {
            problems.push(format!(
                "该模板已在村中：{}；相似人物请「复制并修改」",
                r.name
            ));
        }
        let persona = render_persona(&t.fields);
        let total = instructions_chars(&persona, &self.world_settings.worldview);
        if total > INSTRUCTIONS_MAX_CHARS {
            problems.push(format!(
                "人设加公共知识共 {total} 字，超过 {INSTRUCTIONS_MAX_CHARS} 字上限"
            ));
        }
        let name = name
            .map(str::trim)
            .filter(|n| !n.is_empty())
            .unwrap_or(t.fields.name.trim())
            .to_string();
        (name, t.version, persona.chars().count())
    }

    /// 预览用的出现位置：固定入口或唯一候选给出地名；多候选时只说明规则。
    fn entry_preview(
        &self,
        home: Option<&str>,
        no_homes: bool,
    ) -> (Result<Option<EntryPoint>, String>, String) {
        let default = self.world.entry_name().unwrap_or_else(|| {
            "加入时随机选择可到达住处的公共地点；没有合适地点时出现在住处".into()
        });
        match self.world.topo.spawn_candidates(home) {
            Ok(candidates) if candidates.len() == 1 => {
                let name = self.world.topo.locale_name(&candidates[0].locale);
                (Ok(candidates.into_iter().next()), name)
            }
            Ok(candidates) => {
                let name = if no_homes {
                    "加入时随机选择有效活动地点".into()
                } else {
                    default
                };
                (Ok(candidates.into_iter().next()), name)
            }
            Err(error) => (Err(error.to_string()), default),
        }
    }

    /// 加入事务：检查 → 安置、登记会话与人口、保存检查点 → 发布。安置之后任一步失败整体回退，
    /// 不报告成功、不出现在名册、不发新人请求。同号同内容返回原结果，同号不同内容拒绝。
    pub(crate) fn join(&mut self, req: JoinRequest, clients: &Clients) -> Outcome {
        let version = req.template_version.to_string();
        let mut parts = vec![
            req.world_id.as_str(),
            &req.template_id,
            &version,
            req.name.trim(),
            req.home.as_deref().unwrap_or(""),
        ];
        // 不带模型、人设时摘要和以前一样，旧操作记录照样能认出同一次加入
        if let Some(model) = &req.model {
            parts.extend([model.provider.as_str(), &model.model]);
        }
        let persona = req
            .persona
            .as_ref()
            .map(|p| serde_json::to_string(p).unwrap_or_default());
        if let Some(persona) = &persona {
            parts.push(persona);
        }
        let print = fingerprint(&parts);
        if let Some(record) = self.population.joins.get(&req.op_id) {
            let outcome = if record.fingerprint == print {
                record.outcome.clone()
            } else {
                self.failed_join(
                    &req.op_id,
                    "同一操作编号的内容不一致，请发起新的加入操作".into(),
                )
            };
            return Outcome::reply(ServerMsg::JoinResult {
                op_id: req.op_id,
                outcome: Some(outcome),
            });
        }
        let plan = match self.plan_join(&req) {
            Ok(plan) => plan,
            Err(problems) => return self.reject_join(req, print, problems),
        };
        // 之前积压的世界日志先发出去，安置产生的日志成功后才发布。
        let earlier = self.world.take_events();
        self.driver.dispatch(&self.world, earlier, clients);
        match self.transact(|rt| rt.admit(&plan, &req, print)) {
            Ok(outcome) => {
                let placed = self.world.take_events();
                self.driver.dispatch(&self.world, placed, clients);
                println!("[host] {}", outcome.message);
                Outcome::none()
                    .and_all(ServerMsg::ResidentJoined { outcome })
                    .and_all(self.population_msg())
            }
            Err(Aborted {
                cause: Abort::Rejected(JoinError::Rejected(problems)),
                leftovers,
            }) if leftovers.is_empty() => self.reject_join(req, print, problems),
            Err(aborted) => {
                let message = match &aborted.cause {
                    Abort::SaveFailed(error) => {
                        format!("保存失败，未加入：{error}{}", aborted.leftover_note())
                    }
                    Abort::Rejected(_) => aborted.to_string(),
                };
                eprintln!("[host] 加入 {} 失败：{message}", req.op_id);
                Outcome::reply(ServerMsg::JoinResult {
                    outcome: Some(self.failed_join(&req.op_id, message)),
                    op_id: req.op_id,
                })
            }
        }
    }

    /// 规则不通过：记入操作记录，同号重试返回同一结果。
    fn reject_join(&mut self, req: JoinRequest, print: u64, problems: String) -> Outcome {
        let outcome = self.failed_join(&req.op_id, problems);
        self.population
            .remember_join(&req.op_id, print, outcome.clone());
        Outcome::reply(ServerMsg::JoinResult {
            op_id: req.op_id,
            outcome: Some(outcome),
        })
    }

    /// 预览通过后抽一次出生位置、分配编号；不改任何状态。
    fn plan_join(&self, req: &JoinRequest) -> Result<JoinPlan, String> {
        let preview = self.preview(
            &req.template_id,
            Some(req.template_version),
            Some(&req.name),
            req.home.as_deref(),
        );
        if !preview.ok {
            return Err(preview.problems.join("；"));
        }
        if let Some(model) = &req.model {
            self.settings.check_choice(model)?;
        }
        let template = self
            .library
            .get(&req.template_id)
            .cloned()
            .ok_or("模板不存在")?;
        let persona = match &req.persona {
            // 选手的人设：姓名取这次入住的名字，长相照模板，按村民库的规则校验
            Some(fields) => {
                let fields = TemplateFields {
                    name: preview.name.clone(),
                    appearance: template.fields.appearance.clone(),
                    ..fields.clone()
                };
                validate_fields(&fields).map_err(|e| e.to_string())?;
                let persona = render_persona(&fields);
                let total = instructions_chars(&persona, &self.world_settings.worldview);
                if total > INSTRUCTIONS_MAX_CHARS {
                    return Err(format!(
                        "人设加公共知识共 {total} 字，超过 {INSTRUCTIONS_MAX_CHARS} 字上限"
                    ));
                }
                persona
            }
            None => render_persona(&template.fields),
        };
        // 仅在确认加入时抽取一次；实际位置随世界检查点保存，重试返回原加入结果。
        let candidates = self
            .world
            .topo
            .spawn_candidates(preview.home.as_deref())
            .map_err(|e| e.to_string())?;
        let entry = candidates
            .choose(&mut rand::thread_rng())
            .cloned()
            .ok_or("没有有效出生位置")?;
        let id = self
            .population
            .allocate_id(|id| self.world.actor(id).is_some());
        Ok(JoinPlan {
            id,
            name: preview.name,
            home: preview.home,
            home_name: preview.home_name,
            entry_name: self.world.topo.locale_name(&entry.locale),
            entry,
            persona,
            template,
        })
    }

    /// 事务里的改动：安置到世界、登记会话与人口、记下操作结果。安置被内核规则拒绝算规则不通过。
    fn admit(
        &mut self,
        plan: &JoinPlan,
        req: &JoinRequest,
        print: u64,
    ) -> Result<JoinOutcome, JoinError> {
        self.world
            .admit(Admission {
                id: &plan.id,
                name: &plan.name,
                home: plan.home.as_deref(),
                entry: Some(Entry {
                    locale: &plan.entry.locale,
                    station: plan.entry.station.as_deref(),
                }),
            })
            .map_err(|e| JoinError::Rejected(e.to_string()))?;
        self.world
            .tune_needs(&plan.id, default_tuning())
            .map_err(|e| JoinError::Failed(format!("设置需求参数失败：{e}")))?;
        let common = self.world_settings.worldview.clone();
        self.driver
            .set_persona(&mut self.world, &plan.id, &plan.persona, &common)
            .map_err(|e| JoinError::Failed(format!("登记 Agent 会话失败：{e}")))?;
        let joined_at = self.world.minutes();
        self.population.insert(Registration {
            id: plan.id.clone(),
            name: plan.name.clone(),
            home: plan.home.clone(),
            joined_at: Some(joined_at),
            template_id: Some(req.template_id.clone()),
            template_version: Some(plan.template.version),
            persona: plan.persona.clone(),
            appearance: plan.template.fields.appearance.clone(),
            model_binding: req.model.clone(),
            needs: default_tuning(),
            order: 0,
        });
        let outcome = JoinOutcome {
            op_id: req.op_id.clone(),
            ok: true,
            message: match &plan.home_name {
                Some(home_name) => {
                    format!(
                        "{} 从{}来到小镇，住在「{home_name}」",
                        plan.name, plan.entry_name
                    )
                }
                None => format!("{} 在「{}」就位", plan.name, plan.entry_name),
            },
            resident_id: Some(plan.id.clone()),
            name: Some(plan.name.clone()),
            home: plan.home.clone(),
            joined_at: Some(joined_at),
            revision: self.population.revision,
        };
        self.population
            .remember_join(&req.op_id, print, outcome.clone());
        Ok(outcome)
    }
}

/// 没指定住宅时按地点表顺序分配下一处空房；有住宅却全满是 host 的分配规则，其余交内核判断。
fn requested_home(
    home: Option<&str>,
    homes: &[HomeView],
    free: &[HomeView],
    problems: &mut Vec<String>,
) -> Option<String> {
    match home.map(str::trim).filter(|h| !h.is_empty()) {
        Some(h) => Some(h.to_string()),
        None => {
            if free.is_empty() && !homes.is_empty() {
                problems.push(format!(
                    "没有空置住宅：可分配住宅共 {} 处均已占用",
                    homes.len()
                ));
            }
            free.first().map(|h| h.locale.clone())
        }
    }
}
