//! 待完成工具的结算：动作组、双方互动与等待结束后，把结果写回对应的对话。
use super::{event_arrived, RequestKind, ResidentRuntime, Trace};
use crate::{
    conversation::{Message, Role, ToolCall},
    session::{PendingTool, Session},
    tools::ToolName,
    NO_RESIDENT,
};
use kernel::World;
use protocol::{GroupStatus, InteractionStatus};
use serde_json::{json, Value};

/// 一个工具调用的结果；整理轮次的结果只进整理对话，不进生活会话。
pub(super) struct ToolResult<'a> {
    pub call: &'a ToolCall,
    pub value: Value,
    pub kind: RequestKind,
}

impl ResidentRuntime {
    /// 整理与交谈轮次的工具结果不进生活会话，只进各自的对话；都记轨迹。
    pub(super) fn complete_tool(&mut self, world: &World, s: &mut Session, result: ToolResult) {
        let bounded = crate::context::input::tool_result(&mut s.input, result.value.clone());
        let message = Message::result(&result.call.id, bounded);
        match result.kind {
            RequestKind::Life => s.messages.push(message),
            RequestKind::Chat => s.chat.messages.push(message),
            RequestKind::Reflection => {
                let allowed = result
                    .call
                    .name
                    .parse::<ToolName>()
                    .is_ok_and(|n| n.allowed_in(RequestKind::Reflection));
                if s.notebook.request.is_some() && allowed {
                    s.notebook.reading_dialogue.push(message);
                }
            }
        }
        let data = json!({
            "call_id": result.call.id,
            "name": result.call.name,
            "result": result.value
        });
        self.record(
            world,
            s,
            Trace::new("tool_result", data).request(s.last_request_id),
        );
    }

    pub(super) fn resolve_pending(&mut self, world: &mut World, s: &mut Session) {
        if world.actor(&s.actor_id).is_none() {
            self.pause_fault(world, s, NO_RESIDENT, None);
            return;
        }
        self.react_to_notices(world, s);
        self.react_to_arrivals(world, s);
        let mut finished = false;
        for pending in std::mem::take(&mut s.pending) {
            let settled = match &pending {
                PendingTool::Interaction {
                    call,
                    interaction_id,
                } => self.settle_interaction(world, s, call, interaction_id),
                PendingTool::Actions {
                    call,
                    group_id,
                    reported_running,
                } => self.settle_actions(world, s, call, group_id, *reported_running),
                PendingTool::Wait {
                    call,
                    until,
                    after_cursor,
                    event,
                    invitation,
                } => self.settle_wait(
                    world,
                    s,
                    call,
                    (*until, *after_cursor, *event),
                    invitation.as_deref(),
                ),
            };
            if settled {
                finished = true;
            } else {
                s.pending.push(pending);
            }
        }
        if finished {
            s.restart_wake_count();
            s.memory.consolidate(world, &s.actor_id);
        }
    }

    fn settle_interaction(
        &mut self,
        world: &World,
        s: &mut Session,
        call: &ToolCall,
        interaction_id: &str,
    ) -> bool {
        let Some(item) = world.interactions().of(&s.actor_id, interaction_id) else {
            self.pause_fault(world, s, "待完成工具找不到双方互动", None);
            return false;
        };
        if !item.status.terminal() {
            return false;
        }
        let success = item.status == InteractionStatus::Succeeded;
        let value = json!({"ok":success,"interaction":item});
        self.complete_tool(
            world,
            s,
            ToolResult {
                call,
                value,
                kind: RequestKind::Life,
            },
        );
        true
    }

    fn settle_actions(
        &mut self,
        world: &World,
        s: &mut Session,
        call: &ToolCall,
        group_id: &str,
        reported_running: bool,
    ) -> bool {
        let Some(group) = world.action_group(&s.actor_id, group_id).cloned() else {
            self.pause_fault(world, s, "待完成工具找不到世界动作组", None);
            return false;
        };
        if group.status == GroupStatus::Running {
            return false;
        }
        if reported_running && !crate::context::paired(&s.messages) {
            return false;
        }
        if group.status == GroupStatus::Failed {
            let error = group
                .results
                .iter()
                .find_map(|r| r.reason.as_deref())
                .unwrap_or("动作失败");
            self.note_failure(world, s, &call.arguments.to_string(), error);
        } else if group.status == GroupStatus::Succeeded {
            s.streaks.failures = Default::default();
        }
        let value = json!({"ok":group.status==GroupStatus::Succeeded,"group":group});
        if reported_running {
            s.messages.push(Message::text(
                Role::User,
                json!({"action_result":value}).to_string(),
            ));
            self.record(world, s, Trace::new("action_result", value));
            return true;
        }
        self.complete_tool(
            world,
            s,
            ToolResult {
                call,
                value,
                kind: RequestKind::Life,
            },
        );
        true
    }

    fn settle_wait(
        &mut self,
        world: &World,
        s: &mut Session,
        call: &ToolCall,
        (until, after_cursor, event): (f64, u64, Option<protocol::FactKind>),
        invitation: Option<&str>,
    ) -> bool {
        let Some(actor) = world.actor(&s.actor_id) else {
            return false;
        };
        let occurred = event_arrived(actor, after_cursor, event)
            || super::arrivals::relevant_arrival(world, s, after_cursor);
        if world.minutes() < until && !occurred && !world.chat_turn(&s.actor_id) {
            return false;
        }
        let mut value = json!({
            "ok": true,
            "at": world.minutes(),
            "woke_by": if occurred { "event" } else { "deadline" },
            "event_cursor": actor.journal.cursor()
        });
        if let Some(item) = invitation.and_then(|id| world.interactions().of(&s.actor_id, id)) {
            value["invitation"] = crate::interaction::observation(world, &s.actor_id, item);
            value["replied"] = json!(item.status != InteractionStatus::Offered);
        }
        self.complete_tool(
            world,
            s,
            ToolResult {
                call,
                value,
                kind: RequestKind::Life,
            },
        );
        true
    }
}
