//! 外部受控动作也进入会话的等待与结果记录，保存重启时仍能核对世界动作。
use super::{pending::ToolResult, RequestKind, RequestStatus, ResidentRuntime};
use crate::{session::PendingTool, AgentError};
use kernel::World;
use serde_json::json;

/// host 事务开始时的会话状态与轨迹长度；事务失败时按它回退。
pub struct ControlCheckpoint {
    state: super::RuntimeState,
    trace_len: usize,
}

impl ResidentRuntime {
    /// 控制权切换不改人设，不向角色透露玩家身份；只清理失效的请求与等待。
    pub fn player_handover(&mut self, world: &mut World, actor: &str) -> Result<(), AgentError> {
        let mut session = self
            .state
            .sessions
            .remove(actor)
            .ok_or_else(|| AgentError::NotFound("村民会话不存在".into()))?;
        if let Some(stamp) = session.drop_in_flight() {
            self.ledger_close(
                stamp.id,
                RequestStatus::Controlled,
                "玩家接管，迟到回复不执行；预留用量保留",
            );
        }
        for pending in std::mem::take(&mut session.pending) {
            if let PendingTool::Wait { call, .. } = &pending {
                self.complete_tool(
                    world,
                    &mut session,
                    ToolResult {
                        call,
                        value: json!({"ok":true,"at":world.minutes(),"woke_by":"state_changed"}),
                        kind: RequestKind::Life,
                    },
                );
            } else {
                session.pending.push(pending);
            }
        }
        // 不调用 interrupt_on_notice，避免接管/交还本身中断合法活动。
        session.restart_after_interruption();
        session.cursors.last_notice = world.actor(actor).map_or(0, |a| a.journal.cursor());
        session.cursors.last_presence = session.cursors.last_notice;
        self.state.sessions.insert(actor.into(), session);
        Ok(())
    }
    /// 与世界事务一起回退，不递增请求代次，也不重新加载或修改记忆文件。
    pub fn control_checkpoint(&self) -> ControlCheckpoint {
        ControlCheckpoint {
            state: self.state.clone(),
            trace_len: self.trace.len(),
        }
    }
    pub fn rollback_control(&mut self, checkpoint: ControlCheckpoint) {
        self.state = checkpoint.state;
        self.trace.truncate(checkpoint.trace_len);
    }

    /// 世界设定或运行模式改变：中断旧安排和等待，保留经历、会话和在途用量。
    pub fn world_changed(&mut self, world: &mut World, actor: &str, reason: &str) {
        world.interrupt_actions(actor, reason);
        let Some(mut session) = self.state.sessions.remove(actor) else {
            return;
        };
        session.restart_after_interruption();
        for pending in std::mem::take(&mut session.pending) {
            if let PendingTool::Wait { call, .. } = &pending {
                let value = json!({"ok":false,"reason":reason,"at":world.minutes()});
                self.complete_tool(
                    world,
                    &mut session,
                    ToolResult {
                        call,
                        value,
                        kind: RequestKind::Life,
                    },
                );
            } else {
                session.pending.push(pending);
            }
        }
        self.resolve_pending(world, &mut session);
        self.state.sessions.insert(actor.into(), session);
    }
}
